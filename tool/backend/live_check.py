"""Exercise the deployed project with disposable accounts; never send emails.

Only resources created by this invocation are touched. All temporary objects and
users are removed in finally, including when an individual check fails.
"""
import io
import json
import os
import secrets
import sys
import uuid
import wave
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen

from .manage import BackendError, ManagementDatabase, Storage, configured_database, health


class ProjectApi:
    def __init__(self, url, key):
        self.url = url.rstrip('/')
        self.key = key

    def request(self, method, path, token=None, body=None, binary=False, content_type=None, denied=False):
        endpoint = self.url + path if path.startswith('/') else path
        if urlparse(endpoint).netloc != urlparse(self.url).netloc or urlparse(endpoint).scheme != 'https':
            raise BackendError('Unexpected smoke-test endpoint.')
        data = body if isinstance(body, bytes) else None if body is None else json.dumps(body).encode()
        request = Request(endpoint, method=method, data=data, headers={
            'apikey': self.key, 'Authorization': 'Bearer ' + (token or self.key),
            'Content-Type': content_type or 'application/json', 'Prefer': 'return=representation',
        })
        try:
            with urlopen(request, timeout=30) as response:
                payload = response.read(1024 * 1024)
                if denied:
                    raise BackendError('Cross-account access was unexpectedly allowed.')
                return payload if binary else json.loads(payload) if payload else None
        except HTTPError as error:
            if denied and error.code in (400, 401, 403, 404):
                return None
            raise BackendError(f'Live API request failed (HTTP {error.code}).') from None
        except URLError:
            raise BackendError('Live API is unreachable.') from None


def check_project(db, api, server, cleanup_storage):
    users, media, checks = [], [], []
    stage = 'create_test_accounts'
    failure = None
    cleanup_errors = 0
    users_removed = 0
    try:
        credentials = []
        for _ in range(2):
            tag = uuid.uuid4().hex
            email = f'waveify-smoke-{tag}@example.invalid'
            password = secrets.token_urlsafe(32)
            # Admin confirmation bypasses email delivery; these are disposable users.
            user = server.request('POST', '/auth/v1/admin/users', body={
                'email': email, 'password': password, 'email_confirm': True,
                'user_metadata': {'username': 'wf_test_' + tag[:12], 'displayName': 'Waveify verification'},
            })
            users.append(user['id'])
            credentials.append((email, password, 'wf_test_' + tag[:12]))
        stage = 'email_password_login'
        sessions = [api.request('POST', '/auth/v1/token?grant_type=password', body={
            'email': email, 'password': password,
        }) for email, password, _ in credentials]
        tokens = [s['access_token'] for s in sessions]
        if [s['user']['id'] for s in sessions] != users:
            raise BackendError('Authenticated identities do not match.')
        checks.append(stage)
        owner, other = users
        token, other_token = tokens
        track_id, playlist_id, item_id = [str(uuid.uuid4()) for _ in range(3)]
        stamp = datetime.now(timezone.utc).isoformat()
        name = owner + '/waveify-smoke-' + uuid.uuid4().hex + '.wav'
        track = {'id': track_id, 'title': 'Waveify verification', 'durationMs': 1000,
                 'artists': [{'id': 'test-artist', 'name': 'Waveify'}],
                 'sourceUrl': 'storage://waveify_media/' + name}
        data = {'version': 1, 'tracks': {track_id: track}, 'liked': {track_id: stamp},
                'playlists': {playlist_id: {'playlist': {'id': playlist_id, 'title': 'Verification',
                    'ownerId': owner, 'isPublic': False}, 'items': [{'id': item_id, 'track': track}]}},
                'history': [], 'collections': {},
                'user': {'id': owner, 'username': credentials[0][2], 'displayName': 'Waveify verification',
                         'email': credentials[0][0], 'isPublic': False}}
        stage = 'library_favorites_playlists'
        def save(revision):
            return api.request('POST', '/rest/v1/rpc/waveify_save_library', token, {
                'expected_revision': revision, 'library_data': data})
        if save(0) != 1:
            raise BackendError('First library save did not commit.')
        query = '/rest/v1/waveify_libraries?select=owner_id,revision,data&owner_id=eq.' + owner
        rows = api.request('GET', query, token)
        if len(rows) != 1 or rows[0]['data'] != data:
            raise BackendError('Library persistence changed the saved data.')
        checks.append(stage)
        stage = 'cross_account_isolation'
        if api.request('GET', query, other_token) != []:
            raise BackendError('Another user can read a private library.')
        if api.request('PATCH', query, other_token, {'revision': 99}) != []:
            raise BackendError('Another user can change a private library.')
        if save(0) is not None:
            raise BackendError('A stale library revision was accepted.')
        checks.append(stage)
        stage = 'public_projection_privacy'
        data['user']['isPublic'] = True
        data['playlists'][playlist_id]['playlist']['isPublic'] = True
        if save(1) != 2:
            raise BackendError('Public library save failed.')
        public_query = '/rest/v1/waveify_public_playlists?select=data&id=eq.' + playlist_id
        shared = api.request('GET', public_query, other_token)
        serialized = json.dumps(shared)
        if len(shared) != 1 or 'storage://' in serialized or 'sourceUrl' in serialized:
            raise BackendError('Public projection is missing or exposes private transport locations.')
        data['user']['isPublic'] = False
        if save(2) != 3 or api.request('GET', public_query, other_token) != []:
            raise BackendError('Private sharing transition did not remove the public projection.')
        checks.append(stage)
        stage = 'private_media_upload_download'
        pcm = io.BytesIO()
        with wave.open(pcm, 'wb') as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(8000)
            audio.writeframes(bytes(16000))
        payload = pcm.getvalue()
        media.append(name)
        path = '/storage/v1/object/waveify_media/' + quote(name, safe='/')
        api.request('POST', path, token, payload, content_type='audio/wav')
        downloaded = api.request('GET', '/storage/v1/object/authenticated/waveify_media/' + quote(name, safe='/'), token, binary=True)
        if downloaded != payload:
            raise BackendError('Uploaded media did not round-trip.')
        signed = api.request('POST', '/storage/v1/object/sign/waveify_media/' + quote(name, safe='/'), token, {'expiresIn': 60})
        signed_url = signed.get('signedURL') or signed.get('signedUrl')
        if not signed_url:
            raise BackendError('No signed media URL was returned.')
        if signed_url.startswith('/object/'):
            signed_url = '/storage/v1' + signed_url
        if api.request('GET', signed_url, binary=True) != payload:
            raise BackendError('Signed media URL is not playable.')
        api.request('GET', '/storage/v1/object/authenticated/waveify_media/' + quote(name, safe='/'), other_token, binary=True, denied=True)
        api.request('POST', '/storage/v1/object/sign/waveify_media/' + quote(name, safe='/'), other_token, {'expiresIn': 60}, denied=True)
        checks.append(stage)
        stage = 'remote_state_and_isolation'
        device = str(uuid.uuid4())
        api.request('POST', '/rest/v1/waveify_playback_state', token,
                    {'user_id': owner, 'device_id': device, 'device_name': 'Disposable verification', 'track_id': track_id})
        remote_query = '/rest/v1/waveify_playback_state?user_id=eq.' + owner + '&device_id=eq.' + device
        if api.request('GET', remote_query, other_token) != []:
            raise BackendError('Remote playback is visible to another user.')
        command = str(uuid.uuid4())
        rows = api.request('PATCH', remote_query, token,
                           {'command': 'pause', 'command_id': command, 'command_created_at': stamp})
        if len(rows) != 1 or rows[0]['command_id'] != command:
            raise BackendError('Remote command did not persist.')
        publication = db.query("select 1 as enabled from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='waveify_playback_state'")
        if not publication:
            raise BackendError('Remote playback is not in the realtime publication.')
        checks.append(stage)
    except BaseException as error:
        failure = {'stage': stage, 'reason': str(error) if isinstance(error, BackendError) else type(error).__name__}
    finally:
        for name in reversed(media):
            try:
                cleanup_storage.delete(name)
            except Exception:
                cleanup_errors += 1
        for user in reversed(users):
            try:
                server.request('DELETE', '/auth/v1/admin/users/' + user)
                users_removed += 1
            except Exception:
                cleanup_errors += 1
    report = {'live_checks': 'passed' if failure is None and not cleanup_errors else 'failed',
              'checks': checks, 'temporary_users_removed': users_removed,
              'cleanup': 'passed' if cleanup_errors == 0 else 'failed'}
    if failure:
        report['failure'] = failure
    return report


def main():
    try:
        db = configured_database()
        if not isinstance(db, ManagementDatabase):
            raise BackendError('Live verification requires the Supabase management token.')
        health(db)
        keys = db.api('/api-keys')
        server_key = next((k['api_key'] for k in keys if k.get('name') == 'service_role'), None)
        public_key = os.environ.get('SUPABASE_PUBLISHABLE_KEY') or next((k['api_key'] for k in keys if k.get('name') == 'anon'), None)
        if not server_key or not public_key:
            raise BackendError('Live verification requires project API keys.')
        url = db.project_url
        report = check_project(db, ProjectApi(url, public_key), ProjectApi(url, server_key), Storage(url, server_key))
        print(json.dumps(report))
        sys.exit(0 if report['live_checks'] == 'passed' else 1)
    except Exception as error:
        print(json.dumps({'live_checks': 'failed', 'reason': str(error) if isinstance(error, BackendError) else type(error).__name__}))
        sys.exit(1)


if __name__ == '__main__':
    main()
