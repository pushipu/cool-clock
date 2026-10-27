import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile


spec = importlib.util.spec_from_file_location('fetch_media', Path(__file__).resolve().parents[1] / 'scripts/fetch-media.py')
fetcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fetcher)


class FetchMediaTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / 'repo'
        self.root.mkdir()
        self.archive = Path(self.temporary.name) / 'release.zip'
        self.manifest = {
            'version': '0.7.1',
            'url': 'https://github.com/pushipu/cool-clock/releases/download/v0.7.1/Cool-Clock-0.7.1-saver.zip',
            'files': [],
        }
        with zipfile.ZipFile(self.archive, 'w') as archive:
            for index, (path, name) in enumerate(fetcher.MEDIA.items()):
                data = f'media {index}'.encode()
                member = f'Cool Clock.saver/Contents/Resources/{name}'
                archive.writestr(member, data)
                self.manifest['files'].append({'path': path, 'member': member, 'size': len(data),
                                               'sha256': hashlib.sha256(data).hexdigest()})
            archive.writestr('../../unwanted.txt', b'not extracted')
        self.manifest['sha256'] = fetcher.digest(self.archive)

    def fetch(self):
        return fetcher.fetch_media(self.root, self.manifest, self.archive)

    def assert_no_media(self):
        for path in fetcher.MEDIA:
            self.assertFalse((self.root / path).exists())

    def test_installs_only_expected_files_and_reuses_without_download(self):
        self.assertEqual(set(self.fetch()), set(fetcher.MEDIA))
        for item in self.manifest['files']:
            self.assertEqual(fetcher.digest(self.root / item['path']), item['sha256'])
        self.assertFalse((Path(self.temporary.name) / 'unwanted.txt').exists())
        with patch.object(fetcher, 'urlopen', side_effect=AssertionError('unnecessary download')):
            self.assertEqual(fetcher.fetch_media(self.root, self.manifest), [])

    def test_bad_archive_hash_writes_no_media(self):
        self.manifest['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'archive SHA-256'):
            self.fetch()
        self.assert_no_media()

    def test_bad_member_hash_writes_no_media(self):
        self.manifest['files'][-1]['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'Media SHA-256'):
            self.fetch()
        self.assert_no_media()

    def test_bad_member_size_writes_no_media(self):
        self.manifest['files'][-1]['size'] += 1
        with self.assertRaisesRegex(ValueError, 'Media size'):
            self.fetch()
        self.assert_no_media()

    def test_malformed_manifest_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'manifest object'):
            fetcher.fetch_media(self.root, [], self.archive)
        self.manifest['files'][0] = 'not an object'
        with self.assertRaisesRegex(ValueError, 'file object'):
            self.fetch()
        self.assert_no_media()

    def test_missing_member_writes_no_media(self):
        with zipfile.ZipFile(self.archive, 'w') as archive:
            archive.writestr(self.manifest['files'][0]['member'], b'media 0')
        self.manifest['sha256'] = fetcher.digest(self.archive)
        with self.assertRaisesRegex(ValueError, 'Missing or duplicate'):
            self.fetch()
        self.assert_no_media()

    def test_path_traversal_and_absolute_paths_are_rejected(self):
        for path in ['assets/../../escape', '/tmp/escape', 'assets/audio/../cloud-swift.mp4']:
            with self.subTest(path=path):
                self.manifest['files'][0]['path'] = path
                with self.assertRaisesRegex(ValueError, 'Unexpected media path'):
                    self.fetch()
        self.assert_no_media()

    def test_symlink_directory_cannot_escape_assets(self):
        (self.root / 'assets').symlink_to(Path(self.temporary.name), target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'leaves assets'):
            self.fetch()
        self.assert_no_media()

    def test_existing_different_file_is_not_overwritten(self):
        target = self.root / 'assets/cloud-swift.mp4'
        target.parent.mkdir()
        target.write_bytes(b'local edit')
        with self.assertRaisesRegex(ValueError, 'Existing file differs'):
            self.fetch()
        self.assertEqual(target.read_bytes(), b'local edit')
        self.assertFalse((self.root / 'assets/cloud-cirrus.mp4').exists())


if __name__ == '__main__':
    unittest.main()
