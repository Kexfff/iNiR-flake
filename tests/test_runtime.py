"""Exercise the packaged theme writer with a failing GSettings backend."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


@unittest.skipUnless(os.environ.get('INIR_TEST_PACKAGE'), 'requires the built package')
class RuntimeTests(unittest.TestCase):
    def test_gsettings_failure_preserves_palette(self):
        package = Path(os.environ['INIR_TEST_PACKAGE'])
        script = (package / 'share/quickshell/inir/scripts/colors/apply-gtk-theme.sh').read_text()
        start = script.index('generate_kdeglobals() {')
        end = script.index('\n}', start) + 2
        block_start = script.index('    kde_tmp=$(mktemp')
        block_end = script.index('\n    # Generate Darkly', block_start)
        with tempfile.TemporaryDirectory() as directory:
            palette = Path(directory) / 'kdeglobals'
            palette.write_text('existing palette')
            env = dict(os.environ, KDEGLOBALS=str(palette))
            result = subprocess.run(['bash', '-c', 'set -euo pipefail\n'
                'gsettings() { return 1; }\n' + script[start:end] + '\n' + script[block_start:block_end]],
                env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(palette.read_text(), 'existing palette')
            self.assertEqual(list(Path(directory).iterdir()), [palette])

    def test_shell_syntax(self):
        runtime = Path(os.environ['INIR_TEST_PACKAGE']) / 'share/quickshell/inir'
        for file in ['scripts/inir', 'scripts/colors/apply-gtk-theme.sh']:
            subprocess.run(['bash', '-n', str(runtime / file)], check=True)
