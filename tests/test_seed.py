import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('seed', Path(__file__).parents[1] / 'nix/seed-config.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SeedTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.src, self.dst = root / 'src', root / 'dst'
        (self.src / 'niri/config.d').mkdir(parents=True)
        (self.src / 'niri/config.kdl').write_text('include "config.d/70-binds.kdl"\n')
        (self.src / 'niri/config.d/70-binds.kdl').write_text('binds {}\n')
        (self.src / 'kdeglobals').write_text('[Colors:View]\nBackgroundNormal=1,2,3\n')
        self.legacy = root / 'legacy'
        self.legacy.write_text('old config')

    def seed(self):
        module.seed(self.src, self.dst, self.legacy)

    def test_fresh_and_repeat_preserve_edits(self):
        self.seed()
        binds = self.dst / 'niri/config.d/70-binds.kdl'
        binds.write_text('custom')
        self.seed()
        self.assertEqual(binds.read_text(), 'custom')
        self.assertTrue(binds.stat().st_mode & 0o200)

    def test_exact_migration_and_backup(self):
        (self.dst / 'niri').mkdir(parents=True)
        (self.dst / 'niri/config.kdl').write_text('old config')
        self.seed()
        self.assertEqual((self.dst / 'niri/config.kdl.pre-modular').read_text(), 'old config')
        self.assertEqual((self.dst / 'niri/config.kdl').read_bytes(), (self.src / 'niri/config.kdl').read_bytes())

    def test_custom_config_is_preserved(self):
        (self.dst / 'niri').mkdir(parents=True)
        (self.dst / 'niri/config.kdl').write_text('custom config')
        self.seed()
        self.assertEqual((self.dst / 'niri/config.kdl').read_text(), 'custom config')

    def test_incomplete_kde_palette_keeps_other_settings(self):
        self.dst.mkdir()
        (self.dst / 'kdeglobals').write_text('[General]\nfont=My Font\n')
        self.seed()
        text = (self.dst / 'kdeglobals').read_text()
        self.assertIn('font=My Font', text)
        self.assertIn('[Colors:View]', text)
        self.assertEqual((self.dst / 'kdeglobals.pre-inir').read_text(), '[General]\nfont=My Font\n')

    def test_symlink_directory_not_followed(self):
        self.dst.mkdir()
        (self.dst / 'niri').symlink_to(self.src / 'niri', target_is_directory=True)
        self.seed()
        self.assertEqual((self.src / 'niri/config.kdl').read_text(), 'include "config.d/70-binds.kdl"\n')

    def test_empty_palette_is_repaired(self):
        self.dst.mkdir()
        (self.dst / 'kdeglobals').touch()
        self.seed()
        self.assertIn('[Colors:View]', (self.dst / 'kdeglobals').read_text())

    def test_generated_palette_is_untouched(self):
        self.dst.mkdir()
        text = '[Colors:View]\nBackgroundNormal=9,8,7\n'
        (self.dst / 'kdeglobals').write_text(text)
        self.seed()
        self.assertEqual((self.dst / 'kdeglobals').read_text(), text)

    def test_helpers_keep_execute_permissions(self):
        helper = self.src / 'helper.sh'
        helper.write_text('#!/bin/sh\n')
        helper.chmod(0o555)
        self.seed()
        self.assertEqual((self.dst / 'helper.sh').stat().st_mode & 0o777, 0o755)

    def test_legacy_under_symlink_directory_is_not_migrated(self):
        (self.src / 'niri/config.kdl').write_text('old config')
        self.dst.mkdir()
        (self.dst / 'niri').symlink_to(self.src / 'niri', target_is_directory=True)
        self.seed()
        self.assertFalse((self.src / 'niri/config.kdl.pre-modular').exists())


if __name__ == '__main__':
    unittest.main()
