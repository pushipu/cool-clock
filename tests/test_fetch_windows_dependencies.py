import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('windows_dependencies', ROOT / 'scripts/fetch-windows-dependencies.py')
fetcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fetcher)


class WindowsDependencyTests(unittest.TestCase):
    def test_supported_hosts_have_pinned_compiler_and_installer(self):
        manifest = json.loads((ROOT / 'windows/dependencies.json').read_text())
        for system, machine, key in [('Darwin', 'arm64', 'Darwin-arm64'),
                                     ('Windows', 'AMD64', 'Windows-x64'),
                                     ('Windows', 'ARM64', 'Windows-arm64'),
                                     ('Windows', 'aarch64', 'Windows-arm64')]:
            with self.subTest(machine=machine), patch.object(fetcher.platform, 'system', return_value=system), patch.object(fetcher.platform, 'machine', return_value=machine):
                self.assertEqual(fetcher.host_key(), key)
                for name in manifest['hosts'][key].values():
                    self.assertRegex(manifest[name]['sha256'], r'^[a-f0-9]{64}$')

    def test_zip_rejects_escaping_paths_before_writing_anything(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for unsafe in ['../escape', '/escape', 'C:/escape', r'..\escape', 'file:stream']:
                with self.subTest(path=unsafe):
                    archive = root / 'tools.zip'
                    with zipfile.ZipFile(archive, 'w') as package:
                        package.writestr('valid/file.txt', b'valid')
                        package.writestr(unsafe, b'unsafe')
                    with self.assertRaisesRegex(ValueError, 'Unsafe'):
                        fetcher.extract(archive, root / 'unpacked')
                    self.assertFalse((root / 'unpacked').exists())

    def test_zip_extracts_nested_tool_distribution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / 'tools.zip'
            with zipfile.ZipFile(archive, 'w') as package:
                package.writestr('nsis/Stubs/stub.exe', b'test stub')
            fetcher.extract(archive, root / 'unpacked')
            self.assertEqual((root / 'unpacked/nsis/Stubs/stub.exe').read_bytes(), b'test stub')
