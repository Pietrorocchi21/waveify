"""Free-plan-conscious backend deployment, verification and portable encrypted backups.

Administrative credentials are read only from environment variables. This module
is a server-side tool, never a Flutter dependency or part of the EXE.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tarfile
import tempfile
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlparse, parse_qs
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS = ROOT / 'supabase' / 'migrations'
TABLES = ('waveify_libraries', 'waveify_profiles', 'waveify_follows',
          'waveify_public_playlists', 'waveify_public_history', 'waveify_playback_state')
MAX_BYTES = 2 * 1024**3


class BackendError(RuntimeError):
    pass


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def sql_json(value):
    return literal(json.dumps(value, separators=(',', ':'), ensure_ascii=False)) + '::jsonb'


def migration_files():
    return sorted(p for p in MIGRATIONS.glob('*.sql') if p.name[:4].isdigit() and int(p.name[:4]) >= 4)


def migration_sql():
    parts = ["begin;", "set local standard_conforming_strings = on;",
             "select pg_advisory_xact_lock(hashtext('waveify_migrations'));",
             "create schema if not exists waveify_admin;",
             "revoke all on schema waveify_admin from public, anon, authenticated;",
             "create table if not exists waveify_admin.migrations (version text primary key, checksum text not null, applied_at timestamptz not null default now());"]
    for path in migration_files():
        body = path.read_text()
        checksum = hashlib.sha256(body.encode()).hexdigest()
        tag = '$body_' + checksum[:16] + '$'
        if tag in body:
            raise BackendError('Invalid SQL migration delimiter.')
        parts.append(f"""do $apply$
        declare previous text;
        begin
          select checksum into previous from waveify_admin.migrations where version = {literal(path.name)};
          if previous is null then
            execute {tag}{body}{tag};
            insert into waveify_admin.migrations(version, checksum) values ({literal(path.name)}, {literal(checksum)});
          elsif previous <> {literal(checksum)} then
            raise exception 'Waveify migration checksum mismatch: {path.name}';
          end if;
        end $apply$;""")
    return '\n'.join(parts + ['commit;', "notify pgrst, 'reload schema';", ''])


class ManagementDatabase:
    def __init__(self, project_url, token):
        host = urlparse(project_url).hostname or ''
        if not re.fullmatch(r'[a-z0-9]{20}\.supabase\.co', host):
            raise BackendError('Management API requires a standard Supabase project URL.')
        self.ref, self.token = host.split('.')[0], token
        self.project_url = project_url.rstrip('/')

    def api(self, path, body=None, method=None):
        req = Request('https://api.supabase.com/v1/projects/' + self.ref + path,
                      data=None if body is None else json.dumps(body).encode(),
                      headers={'Authorization': 'Bearer ' + self.token, 'Content-Type': 'application/json'},
                      method=method)
        try:
            with urlopen(req, timeout=90) as response:
                return json.load(response)
        except HTTPError as error:
            raise BackendError(f'Supabase management request failed (HTTP {error.code}).') from None
        except URLError:
            raise BackendError('Supabase management is unreachable.') from None

    def query(self, sql):
        result = self.api('/database/query', {'query': sql})
        if not isinstance(result, list):
            raise BackendError('Unexpected management query response.')
        return result

    def execute(self, sql):
        self.query(sql)

    def organization_plan(self):
        """Read billing tier only; never change plans, add-ons or resources."""
        try:
            project = self.api('')
            slug = project.get('organization_slug') or project.get('organization_id')
            if not slug:
                return 'unknown'
            request = Request('https://api.supabase.com/v1/organizations/' + quote(slug, safe=''),
                              headers={'Authorization': 'Bearer ' + self.token})
            with urlopen(request, timeout=30) as response:
                plan = json.load(response).get('plan')
            return plan if plan in {'free', 'pro', 'team', 'enterprise', 'platform'} else 'unknown'
        except (BackendError, HTTPError, URLError, ValueError):
            return 'unknown'

    def server_key(self):
        for key in self.api('/api-keys'):
            if key.get('name') == 'service_role':
                return key['api_key']
        raise BackendError('Server storage key unavailable. Configure SUPABASE_SERVICE_ROLE_KEY.')


class PsqlDatabase:
    def __init__(self, url=None, command=None):
        self.command = command or ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1']
        self.env = os.environ.copy()
        if url:
            parsed = urlparse(url)
            if parsed.scheme not in ('postgres', 'postgresql'):
                raise BackendError('WAVEIFY_DATABASE_URL must be a PostgreSQL connection URI.')
            from urllib.parse import unquote
            self.env.update(PGHOST=parsed.hostname or '', PGPORT=str(parsed.port or 5432),
                            PGUSER=unquote(parsed.username or ''), PGPASSWORD=unquote(parsed.password or ''),
                            PGDATABASE=unquote(parsed.path.lstrip('/')), PGCONNECT_TIMEOUT='15')
            params = parse_qs(parsed.query)
            self.env['PGSSLMODE'] = params.get('sslmode', ['require'])[0]

    def execute(self, sql):
        try:
            result = subprocess.run(self.command, input=sql, text=True, capture_output=True,
                                    env=self.env, timeout=180, check=False)
        except (OSError, subprocess.TimeoutExpired):
            raise BackendError('PostgreSQL client unavailable or timed out.') from None
        if result.returncode:
            # Never print SQL, connection URIs or error DETAIL containing private data.
            raise BackendError('PostgreSQL operation failed; check connectivity, schema and migration history.')
        return result.stdout

    def query(self, sql):
        result = self.execute("select coalesce(json_agg(q), '[]'::json) from (" + sql.rstrip(';') + ') q;')
        return json.loads(result)


def configured_database(env=os.environ):
    if env.get('WAVEIFY_DATABASE_URL'):
        return PsqlDatabase(env['WAVEIFY_DATABASE_URL'])
    if env.get('SUPABASE_ACCESS_TOKEN'):
        url = env.get('SUPABASE_URL') or json.loads((ROOT / 'supabase/project.json').read_text())['url']
        return ManagementDatabase(url, env['SUPABASE_ACCESS_TOKEN'])
    return None


def health(db):
    rows = db.query("select tablename, rowsecurity from pg_tables where schemaname='public' and tablename like 'waveify_%'")
    secured = {row['tablename'] for row in rows if row['rowsecurity']}
    if not set(TABLES).issubset(secured):
        raise BackendError('Waveify schema is missing or row-level security is disabled.')
    policy = db.query("select tablename, count(*) as count from pg_policies where schemaname='public' group by tablename")
    policies = {row['tablename']: int(row['count']) for row in policy}
    if any(policies.get(table, 0) == 0 for table in TABLES):
        raise BackendError('Waveify security policies are missing.')
    bucket = db.query("select public, file_size_limit from storage.buckets where id='waveify_media'")
    rpc = db.query("select to_regprocedure('public.waveify_save_library(bigint,jsonb)') is not null as available")
    if not bucket or bucket[0]['public'] or not rpc[0]['available']:
        raise BackendError('Private storage or the atomic library RPC is missing.')
    return {'schema_ready': True, 'rls_tables': len(TABLES), 'private_media': True,
            'max_upload_bytes': bucket[0]['file_size_limit']}


def safe_path(name):
    p = PurePosixPath(name)
    if not name or p.is_absolute() or '..' in p.parts or '\\' in name or ':' in name:
        raise BackendError('Unsafe path in backup or storage object.')
    return p


class Storage:
    def __init__(self, url, key):
        parsed = urlparse(url)
        if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
            raise BackendError('Storage must use an HTTPS Supabase endpoint.')
        self.url, self.key = url.rstrip('/'), key

    def request(self, path, method='GET', data=None):
        safe_path(path)
        route = '/storage/v1/object/' + ('authenticated/' if method == 'GET' else '') + 'waveify_media'
        content_type = 'application/octet-stream'
        if method == 'DELETE':
            data = json.dumps({'prefixes': [path]}).encode()
            content_type = 'application/json'
        else:
            route += '/' + quote(path, safe='/')
        request = Request(self.url + route, data=data, method=method,
                          headers={'apikey': self.key, 'Authorization': 'Bearer ' + self.key,
                                   'Content-Type': content_type, 'x-upsert': 'false'})
        try:
            return urlopen(request, timeout=90)
        except HTTPError as error:
            raise BackendError(f'Private media operation failed (HTTP {error.code}).') from None
        except URLError:
            raise BackendError('Private media storage is unreachable.') from None

    def download(self, name, destination, remaining):
        size = 0
        with self.request(name) as response, open(destination, 'xb') as out:
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                if size > remaining:
                    raise BackendError('Backup exceeds configured size limit.')
                out.write(chunk)
        return size

    def upload(self, name, content):
        with self.request(name, 'POST', content):
            pass

    def delete(self, name):
        with self.request(name, 'DELETE'):
            pass


def storage_client(db, env=os.environ):
    key = env.get('SUPABASE_SERVICE_ROLE_KEY')
    if not key and isinstance(db, ManagementDatabase):
        key = db.server_key()
    if not key:
        raise BackendError('A server storage key is required to export or restore media.')
    url = db.project_url if isinstance(db, ManagementDatabase) else env.get('SUPABASE_URL', '')
    return Storage(url, key)


def export_state(db):
    # One SQL statement gives a consistent DB snapshot. Pause writes to keep files aligned.
    return db.query("""select jsonb_build_object(
        'libraries', coalesce((select jsonb_agg(to_jsonb(l)) from public.waveify_libraries l), '[]'::jsonb),
        'follows', coalesce((select jsonb_agg(to_jsonb(f)) from public.waveify_follows f), '[]'::jsonb),
        'identities', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'email', email))
            from auth.users where id in (select owner_id from public.waveify_libraries union
                select follower_id from public.waveify_follows union select followed_id from public.waveify_follows)), '[]'::jsonb),
        'objects', coalesce((select jsonb_agg(jsonb_build_object('name', name)) from storage.objects where bucket_id='waveify_media'), '[]'::jsonb)
      ) as data""")[0]['data']


def backup(db, destination, passphrase, storage=None):
    from .crypto import encrypt
    if not 20 <= len(passphrase) <= 1024:
        raise BackendError('Backup passphrase must contain 20–1024 characters.')
    if Path(destination).exists():
        raise BackendError('Backup destination already exists; choose a new file.')
    health(db)
    state = export_state(db)
    if state['objects'] and storage is None:
        storage = storage_client(db)
    with tempfile.TemporaryDirectory(prefix='waveify-private-') as tmp:
        root = Path(tmp)
        (root / 'db').mkdir()
        (root / 'db/data.json').write_text(json.dumps(state, ensure_ascii=False))
        (root / 'schema').mkdir()
        for migration in migration_files():
            (root / 'schema' / migration.name).write_bytes(migration.read_bytes())
        size = sum(p.stat().st_size for p in root.rglob('*') if p.is_file())
        for obj in state['objects']:
            path = safe_path(obj['name'])
            target = root / 'media' / str(path)
            target.parent.mkdir(parents=True, exist_ok=True)
            size += storage.download(obj['name'], target, MAX_BYTES - size)
        files = {}
        for p in root.rglob('*'):
            if p.is_file():
                files[str(p.relative_to(root).as_posix())] = {'size': p.stat().st_size,
                    'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
        (root / 'manifest.json').write_text(json.dumps({'format': 'waveify-portable', 'version': 1, 'files': files}))
        archive = root / 'payload.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            for name in ['manifest.json', *sorted(files)]:
                tar.add(root / name, arcname=name, recursive=False)
        encrypt(archive, destination, passphrase)
    return {'backup': 'encrypted', 'libraries': len(state['libraries']), 'media_files': len(state['objects'])}


def read_backup(archive, passphrase, action):
    from .crypto import decrypt
    with tempfile.TemporaryDirectory(prefix='waveify-restore-') as tmp:
        payload = Path(tmp) / 'payload.tar.gz'
        decrypt(archive, payload, passphrase)
        with tarfile.open(payload, 'r:gz') as tar:
            members, total = [], 0
            for member in tar:
                total += member.size
                if total > MAX_BYTES or len(members) >= 100000:
                    raise BackendError('Uncompressed archive exceeds safety limits.')
                members.append(member)
            names = [m.name for m in members]
            if len(names) != len(set(names)) or len(names) > 100000:
                raise BackendError('Duplicate or excessive backup entries.')
            if sum(m.size for m in members) > MAX_BYTES:
                raise BackendError('Uncompressed backup exceeds size limit.')
            for m in members:
                safe_path(m.name)
                if not m.isfile():
                    raise BackendError('Backup must contain regular files only.')
            manifest_file = tar.getmember('manifest.json')
            if manifest_file.size > 16 * 1024**2:
                raise BackendError('Oversized manifest.')
            manifest = json.load(tar.extractfile(manifest_file))
            if manifest.get('format') != 'waveify-portable' or manifest.get('version') != 1:
                raise BackendError('Unsupported portable backup version.')
            if set(names) != {'manifest.json', *manifest['files']}:
                raise BackendError('Archive contents differ from the manifest.')
            for name, expected in manifest['files'].items():
                member = tar.getmember(name)
                if member.size != expected['size']:
                    raise BackendError('Backup file size mismatch.')
                digest = hashlib.sha256()
                with tar.extractfile(member) as content:
                    while chunk := content.read(1024 * 1024):
                        digest.update(chunk)
                if digest.hexdigest() != expected['sha256']:
                    raise BackendError('Backup file checksum mismatch.')
            if tar.getmember('db/data.json').size > 64 * 1024**2:
                raise BackendError('Oversized library metadata.')
            state = json.load(tar.extractfile('db/data.json'))
            return action(state, tar)


def inspect_backup(archive, passphrase):
    return read_backup(archive, passphrase, lambda state, _: {
        'integrity': 'passed', 'libraries': len(state['libraries']),
        'identities': len(state['identities']), 'media_files': len(state['objects'])})


def remap(value, identities):
    if isinstance(value, dict):
        return {k: remap(v, identities) for k, v in value.items()}
    if isinstance(value, list):
        return [remap(v, identities) for v in value]
    if isinstance(value, str):
        if value in identities:
            return identities[value]
        prefix = 'storage://waveify_media/'
        if value.startswith(prefix):
            owner, slash, path = value[len(prefix):].partition('/')
            if owner in identities:
                return prefix + identities[owner] + slash + path
    return value


def restore(db, archive, passphrase, identities, storage=None):
    import uuid
    health(db)
    def apply(state, tar):
        owners = {i['id'] for i in state['identities']}
        if not owners.issubset(identities) or len(set(identities.values())) != len(identities):
            raise BackendError('A complete, one-to-one identity mapping is required.')
        for old, new in identities.items():
            uuid.UUID(old)
            uuid.UUID(new)
        target = {r['id']: r.get('email') for r in db.query('select id::text, email from auth.users')}
        if not set(identities.values()).issubset(target):
            raise BackendError('Create all destination accounts before restore.')
        occupied = {r['id'] for r in db.query('select owner_id::text as id from public.waveify_libraries')}
        if occupied.intersection(identities.values()):
            raise BackendError('Destination libraries must be empty; no existing data is overwritten.')
        planned = []
        for obj in state['objects']:
            old_name = str(safe_path(obj['name']))
            owner, slash, suffix = old_name.partition('/')
            if not slash or owner not in identities:
                raise BackendError('Media owner is absent from identity mapping.')
            new_name = identities[owner] + '/' + suffix
            member = tar.getmember('media/' + old_name)
            if member.size > 50 * 1024**2:
                raise BackendError('Media exceeds portable restore size limit.')
            planned.append((new_name, member))
        client = storage or (storage_client(db) if planned else None)
        queries = ['begin;', 'set local standard_conforming_strings = on;']
        for library in state['libraries']:
            owner = identities[library['owner_id']]
            data = remap(library['data'], identities)
            data['user'] = {**data.get('user', {}), 'id': owner, 'email': target[owner]}
            queries.append('insert into public.waveify_libraries(owner_id, revision, data) values (' +
                           literal(owner) + ', 1, ' + sql_json(data) + ');')
        for follow in state['follows']:
            queries.append('insert into public.waveify_follows(follower_id, followed_id) values (' +
                           literal(identities[follow['follower_id']]) + ', ' +
                           literal(identities[follow['followed_id']]) + ');')
        queries.append('commit;')
        uploaded = []
        try:
            for name, member in planned:
                client.upload(name, tar.extractfile(member).read())
                uploaded.append(name)
            db.execute('\n'.join(queries))
        except BaseException:
            for name in reversed(uploaded):
                try:
                    client.delete(name)
                except Exception:
                    pass
            raise
        return {'restored_libraries': len(state['libraries']), 'restored_media': len(uploaded)}
    return read_backup(archive, passphrase, apply)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['status', 'auth-redirect', 'deploy', 'bundle', 'backup', 'inspect', 'restore'])
    parser.add_argument('--output')
    parser.add_argument('--archive')
    parser.add_argument('--identity-map')
    args = parser.parse_args()
    try:
        if args.operation == 'bundle':
            Path(args.output or ROOT / 'supabase/bootstrap.sql').write_text(migration_sql())
            print(json.dumps({'bundle': 'ready'}))
            return
        if args.operation == 'inspect':
            print(json.dumps(inspect_backup(args.archive, os.environ.get('WAVEIFY_BACKUP_PASSPHRASE', ''))))
            return
        db = configured_database()
        if args.operation == 'auth-redirect':
            if not isinstance(db, ManagementDatabase):
                raise BackendError('Supabase management access is required.')
            landing = 'https://pietrorocchi21.github.io/waveify/auth/'
            with urlopen(landing, timeout=30) as response:
                if response.status != 200 or b'WAVEIFY' not in response.read(65536):
                    raise BackendError('Confirmation page is not available; configuration was not changed.')
            db.api('/config/auth', {'site_url': landing}, method='PATCH')
            result = db.api('/config/auth')
            if result.get('site_url') != landing:
                raise BackendError('Auth redirect configuration did not persist.')
            print(json.dumps({'auth_redirect': 'configured', 'site_url': landing}))
            return
        if args.operation == 'status':
            report = {'admin_configured': db is not None}
            if isinstance(db, ManagementDatabase):
                report['organization_plan'] = db.organization_plan()
                auth = db.api('/config/auth')
                report['auth'] = {
                    'email_confirmation_required': not auth.get('mailer_autoconfirm', False),
                    'custom_smtp_configured': bool(auth.get('smtp_host')),
                    'site_url': auth.get('site_url'),
                    'redirect_allow_list': auth.get('uri_allow_list'),
                    'email_rate_limit_per_hour': auth.get('rate_limit_email_sent'),
                    'signup_disabled': auth.get('disable_signup'),
                }
            if db is not None:
                try:
                    report.update(health(db))
                except BackendError as error:
                    report.update(schema_ready=False, detail=str(error))
            else:
                report['next_step'] = 'Configure SUPABASE_ACCESS_TOKEN or WAVEIFY_DATABASE_URL in GitHub Secrets.'
            print(json.dumps(report))
            return
        if db is None:
            raise BackendError('Administrative access missing. Configure a GitHub Secret; never paste it in chat.')
        if args.operation == 'deploy':
            db.execute(migration_sql())
            print(json.dumps(health(db)))
        elif args.operation == 'backup':
            if not args.output:
                raise BackendError('--output is required.')
            print(json.dumps(backup(db, args.output, os.environ.get('WAVEIFY_BACKUP_PASSPHRASE', ''))))
        elif args.operation == 'restore':
            if not args.identity_map or not args.archive:
                raise BackendError('--archive and --identity-map are required.')
            print(json.dumps(restore(db, args.archive, os.environ.get('WAVEIFY_BACKUP_PASSPHRASE', ''),
                                     json.loads(Path(args.identity_map).read_text()))))
    except Exception as error:
        # A bounded allowlist keeps private SQL, tokens, email and signed URLs out of CI logs.
        message = str(error) if isinstance(error, BackendError) else type(error).__name__
        print('Backend operation failed: ' + message, file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
