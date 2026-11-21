import io
import unittest
from urllib.error import HTTPError
from unittest.mock import patch

from tool.backend.live_check import ProjectApi, check_project
from tool.backend.manage import BackendError


class TemporaryAccountCleanupTests(unittest.TestCase):
    def server(self, fail_second=False):
        class Server:
            users = []
            deleted = []
            def request(self, method, path, **kwargs):
                if method == 'POST':
                    if fail_second and self.users:
                        raise BackendError('Synthetic account creation failure.')
                    if kwargs['body']['email_confirm'] is not True:
                        raise AssertionError('Smoke users must not receive email.')
                    owner = 'temporary-' + str(len(self.users))
                    self.users.append(owner)
                    return {'id': owner}
                self.deleted.append(path.rsplit('/', 1)[-1])
        return Server()

    def test_login_failure_removes_both_created_users(self):
        server = self.server()
        class FailedLogin:
            def request(self, *args, **kwargs):
                raise BackendError('Synthetic login failure.')
        report = check_project(None, FailedLogin(), server, None)
        self.assertEqual(report['live_checks'], 'failed')
        self.assertEqual(report['failure']['stage'], 'email_password_login')
        self.assertEqual(report['cleanup'], 'passed')
        self.assertEqual(report['temporary_users_removed'], 2)
        self.assertEqual(server.deleted, list(reversed(server.users)))

    def test_partial_account_creation_still_cleans_first_user(self):
        server = self.server(fail_second=True)
        report = check_project(None, None, server, None)
        self.assertEqual(report['failure']['stage'], 'create_test_accounts')
        self.assertEqual(report['temporary_users_removed'], 1)
        self.assertEqual(server.deleted, server.users)


class ProjectApiTests(unittest.TestCase):
    def test_rejects_other_hosts_and_redacts_error_bodies(self):
        api = ProjectApi('https://project.supabase.co', 'not-a-real-key')
        with self.assertRaises(BackendError):
            api.request('GET', 'https://another.example/steal')
        error = HTTPError('https://project.supabase.co/endpoint', 403, 'Forbidden', {}, io.BytesIO(b'private-response'))
        with patch('tool.backend.live_check.urlopen', side_effect=error):
            with self.assertRaisesRegex(BackendError, 'HTTP 403') as result:
                api.request('GET', '/endpoint')
            self.assertNotIn('private-response', str(result.exception))
            self.assertIsNone(api.request('GET', '/endpoint', denied=True))


if __name__ == '__main__':
    unittest.main()
