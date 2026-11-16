import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from tool.backend import crypto
from tool.backend.manage import (BackendError, PsqlDatabase, backup, health,
    inspect_backup, migration_sql, restore, safe_path)

A = '00000000-0000-4000-8000-000000000001'
B = '00000000-0000-4000-8000-000000000002'
C = '00000000-0000-4000-8000-000000000003'
PASSWORD = 'only-a-disposable-test-passphrase'
ROOT = Path(__file__).resolve().parents[2]


class CryptoTests(unittest.TestCase):
    def test_round_trip_and_authenticated_failures(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            original = os.urandom(crypto.CHUNK * 2 + 33)
            (p / 'plain').write_bytes(original)
            crypto.encrypt(p / 'plain', p / 'archive', PASSWORD)
            crypto.decrypt(p / 'archive', p / 'restored', PASSWORD)
            self.assertEqual((p / 'restored').read_bytes(), original)
            raw = (p / 'archive').read_bytes()
            for invalid in (raw[:-1], raw + b'x', raw[:80] + bytes([raw[80] ^ 1]) + raw[81:]):
                (p / 'damaged').write_bytes(invalid)
                with self.assertRaises(Exception):
                    crypto.decrypt(p / 'damaged', p / 'failed', PASSWORD)
                self.assertFalse((p / 'failed').exists())
            with self.assertRaises(Exception):
                crypto.decrypt(p / 'archive', p / 'failed', 'a-different-long-test-passphrase')
            # Existing destinations must survive even a failed decryption.
            with self.assertRaises(FileExistsError):
                crypto.decrypt(p / 'archive', p / 'restored', PASSWORD)
            self.assertEqual((p / 'restored').read_bytes(), original)

    def test_path_and_passphrase_validation(self):
        for path in ('../escape', '/absolute', 'a/../escape', r'a\bad', 'C:/bad'):
            with self.assertRaises(BackendError):
                safe_path(path)
        self.assertEqual(str(safe_path('owner/audio.mp3')), 'owner/audio.mp3')
        with self.assertRaises(ValueError):
            crypto._cipher('short', bytes(16))


class FakeStorage:
    def __init__(self, files=None):
        self.files = files or {}
        self.deleted = []

    def download(self, name, destination, remaining):
        data = self.files[name]
        if len(data) > remaining:
            raise BackendError('Size limit')
        Path(destination).write_bytes(data)
        return len(data)

    def upload(self, name, content):
        if name in self.files:
            raise BackendError('Existing object')
        self.files[name] = content

    def delete(self, name):
        self.deleted.append(name)
        del self.files[name]


@unittest.skipUnless(os.environ.get('WAVEIFY_TEST_DATABASE_URL') or os.environ.get('WAVEIFY_TEST_CONTAINER'),
                     'Requires a disposable PostgreSQL instance')
class PostgresTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        container = os.environ.get('WAVEIFY_TEST_CONTAINER')
        cls.db = PsqlDatabase(command=['docker', 'exec', '-i', container, 'psql', '-U', 'postgres',
                                      '-X', '-qAt', '-v', 'ON_ERROR_STOP=1']) if container else PsqlDatabase(os.environ['WAVEIFY_TEST_DATABASE_URL'])
        cls.db.execute((ROOT / 'supabase/tests/bootstrap.sql').read_text())
        cls.db.execute(migration_sql())

    def setUp(self):
        self.db.execute('truncate auth.users cascade; delete from storage.objects;')
        self.db.execute(f"insert into auth.users values ('{A}', 'a@test.invalid'), ('{B}', 'b@test.invalid'), ('{C}', 'c@test.invalid');")

    def as_user(self, owner, sql):
        return self.db.execute(f"begin; set local role authenticated; set local request.jwt.claim.sub = '{owner}'; {sql}; commit;")

    def save(self, owner, username, public=False, **fields):
        value = {'version': 1, 'user': {'id': owner, 'username': username, 'isPublic': public},
                 'tracks': {}, 'playlists': {}, 'history': [], 'liked': {}, 'collections': {}, **fields}
        payload = json.dumps(value).replace("'", "''")
        self.as_user(owner, f"select public.waveify_save_library(0, '{payload}'::jsonb)")
        return value

    def test_deploy_is_repeatable_and_checksum_checked(self):
        self.db.execute(migration_sql())
        self.assertTrue(health(self.db)['schema_ready'])
        self.assertEqual(self.db.query('select count(*) as n from waveify_admin.migrations')[0]['n'], 3)
        self.db.execute("update waveify_admin.migrations set checksum='bad' where version like '0006%'")
        try:
            with self.assertRaises(BackendError):
                self.db.execute(migration_sql())
        finally:
            import hashlib
            p = ROOT / 'supabase/migrations/0006_waveify_limits.sql'
            digest = hashlib.sha256(p.read_bytes()).hexdigest()
            self.db.execute(f"update waveify_admin.migrations set checksum='{digest}' where version like '0006%'")

    def test_actual_rls_and_compare_and_swap(self):
        self.save(A, 'alice')
        self.save(B, 'bob')
        raw = self.as_user(A, 'select count(*) from public.waveify_libraries')
        self.assertEqual(raw.strip(), '1')
        self.assertEqual(self.as_user(A, f"update public.waveify_libraries set revision=9 where owner_id='{B}' returning revision").strip(), '')
        for sql in (f"insert into public.waveify_libraries(owner_id,data) values ('{C}', '{{}}')",
                    f"insert into storage.objects(bucket_id,name) values ('waveify_media', '{B}/secret.mp3')",
                    'select * from waveify_admin.migrations',
                    'truncate public.waveify_libraries cascade'):
            with self.assertRaises(BackendError):
                self.as_user(A, sql)
        self.as_user(A, f"insert into storage.objects(bucket_id,name) values ('waveify_media', '{A}/song.mp3')")
        self.assertEqual(self.as_user(B, 'select count(*) from storage.objects').strip(), '0')
        result = self.as_user(A, "select public.waveify_save_library(99, '{}'::jsonb)")
        self.assertEqual(result.strip(), '')
        self.assertEqual(self.db.query(f"select revision from public.waveify_libraries where owner_id='{A}'")[0]['revision'], 1)

    def test_public_projection_sanitizes_files_and_respects_privacy(self):
        playlist = {'playlist': {'id': 'p', 'title': 'Shared', 'isPublic': True},
                    'items': [{'track': {'id': 't', 'sourceUrl': 'file:///private/song',
                                        'cover': {'url': 'storage://waveify_media/private'}, 'localLyrics': 'private'}}]}
        self.save(A, 'alice', True, playlists={'p': playlist})
        raw = self.as_user(B, 'select data::text from public.waveify_public_playlists')
        self.assertIn('Shared', raw)
        self.assertNotIn('private', raw)
        self.as_user(A, "update public.waveify_libraries set data=jsonb_set(data, '{user,isPublic}', 'false')")
        self.assertEqual(self.as_user(B, 'select count(*) from public.waveify_public_playlists').strip(), '0')

    def test_backup_restore_moves_media_and_identity_without_overwrite(self):
        source_path = A + '/audio/song.mp3'
        self.save(A, 'alice', tracks={'t': {'id': 't', 'sourceUrl': 'storage://waveify_media/' + source_path}})
        self.db.execute(f"insert into storage.objects(bucket_id,name) values ('waveify_media','{source_path}')")
        storage = FakeStorage({source_path: b'actual-media-bytes'})
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / 'backup.wfy'
            self.assertEqual(backup(self.db, archive, PASSWORD, storage)['media_files'], 1)
            self.assertEqual(inspect_backup(archive, PASSWORD)['integrity'], 'passed')
            with self.assertRaises(BackendError):
                restore(self.db, archive, PASSWORD, {}, storage)
            self.db.execute(f"delete from auth.users where id='{A}'")
            result = restore(self.db, archive, PASSWORD, {A: C}, storage)
            self.assertEqual(result['restored_libraries'], 1)
            data = self.db.query(f"select data from public.waveify_libraries where owner_id='{C}'")[0]['data']
            self.assertEqual(data['user']['id'], C)
            self.assertEqual(data['user']['email'], 'c@test.invalid')
            self.assertEqual(data['tracks']['t']['sourceUrl'], 'storage://waveify_media/' + C + '/audio/song.mp3')
            self.assertEqual(storage.files[C + '/audio/song.mp3'], b'actual-media-bytes')
            with self.assertRaises(BackendError):
                restore(self.db, archive, PASSWORD, {A: C}, storage)

    def test_failed_restore_cleans_new_media(self):
        name = A + '/test.wav'
        self.save(A, 'duplicate_name')
        self.db.execute(f"insert into storage.objects(bucket_id,name) values ('waveify_media','{name}')")
        storage = FakeStorage({name: b'audio'})
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / 'backup.wfy'
            backup(self.db, archive, PASSWORD, storage)
            # Same target username as existing source causes the transaction to fail.
            with self.assertRaises(BackendError):
                restore(self.db, archive, PASSWORD, {A: C}, storage)
            self.assertNotIn(C + '/test.wav', storage.files)
            self.assertIn(C + '/test.wav', storage.deleted)


if __name__ == '__main__':
    unittest.main()
