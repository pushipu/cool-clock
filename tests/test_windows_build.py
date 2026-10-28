import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


def load_builder(version):
    spec = importlib.util.spec_from_file_location('windows_build', ROOT / 'scripts/build-windows.py')
    builder = importlib.util.module_from_spec(spec)
    with patch.object(Path, 'read_text', return_value=version):
        spec.loader.exec_module(builder)
    return builder


class WindowsBuildVersionTests(unittest.TestCase):
    def test_shared_version_becomes_four_component_pe_version(self):
        for version, expected in [('0.9.2\n', '0,9,2,0'), ('12.34.56', '12,34,56,0'),
                                  ('65535.65535.65535', '65535,65535,65535,0')]:
            with self.subTest(version=version):
                builder = load_builder(version)
                self.assertEqual(builder.VERSION, version.strip())
                self.assertEqual(builder.WINDOWS_VERSION, expected)

    def test_invalid_or_out_of_range_version_is_rejected(self):
        for version in ['', '1.2', '1.2.3.4', '-1.2.3', '1.2.preview', '65536.0.0',
                        '0.65536.0', '0.0.65536', '١.٢.٣']:
            with self.subTest(version=version), self.assertRaisesRegex(ValueError, 'three numeric components'):
                load_builder(version)
