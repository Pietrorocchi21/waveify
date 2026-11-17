import hashlib
from pathlib import Path
import tempfile
import unittest

from tool.generate_update_manifest import manifest


class ManifestTests(unittest.TestCase):
    def test_exact_installer_hash_size_and_encoded_release_url(self):
        with tempfile.TemporaryDirectory() as tmp:
            installer = Path(tmp) / 'Waveify-1.1.0+2-windows.exe'
            data = b'MZ-example-only-test-fixture'
            installer.write_bytes(data)
            result = manifest(installer, '1.1.0+2', 'Pietrorocchi21/waveify')
            self.assertEqual(result['sha256'], hashlib.sha256(data).hexdigest())
            self.assertEqual(result['size'], len(data))
            self.assertIn('/v1.1.0%2B2/', result['url'])
            self.assertTrue(result['url'].endswith('Waveify-1.1.0%2B2-windows.exe'))
            with self.assertRaises(ValueError):
                manifest(installer, '1.1.0', 'Pietrorocchi21/waveify')
            with self.assertRaises(ValueError):
                manifest(installer, '1.1.0+2', 'untrusted/repository')
