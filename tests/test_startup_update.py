import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'scripts/homebrew-launcher.sh'

class LaunchTests(unittest.TestCase):
    def run_case(self, command='meister', installed=True, failure='', exit_code=0):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            brew = root / 'brew'
            brew.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$TEST_ROOT/events"
case "$1" in
 update) [[ "$FAILURE" != update ]] ;;
 list) [[ "$INSTALLED" == yes ]] ;;
 upgrade|install) [[ "$FAILURE" != package ]] ;;
 --prefix) printf '%s\\n' "$TEST_ROOT/keg" ;;
esac
''')
            brew.chmod(0o755)
            launcher = root / command
            launcher.write_text(SOURCE.read_text().replace('@HOMEBREW_PREFIX@/bin/brew', str(brew)))
            launcher.chmod(0o755)
            (root / 'keg/libexec').mkdir(parents=True)
            for name in ['meister', 'MeisterAI']:
                executable = root / 'keg/libexec' / name
                executable.write_text('''#!/bin/bash
printf 'start:%s\\n' "${0##*/}" >> "$TEST_ROOT/events"
printf '<%s>\\n' "$@"
exit "$CHILD_EXIT"
''')
                executable.chmod(0o755)
            env = dict(os.environ, TEST_ROOT=tmp, FAILURE=failure,
                       INSTALLED='yes' if installed else 'no', CHILD_EXIT=str(exit_code))
            result = subprocess.run([str(launcher), 'arg with spaces', '*', ''], env=env, capture_output=True, text=True)
            return result, (root / 'events').read_text().splitlines()

    def test_update_upgrade_then_current_executable_and_arguments(self):
        for command, target in [('meister', 'meister'), ('meisterAI', 'MeisterAI'), ('MeisterAI', 'MeisterAI')]:
            with self.subTest(command=command):
                result, events = self.run_case(command)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(events, ['update', 'list --versions maf4711/meister/meister',
                    'upgrade --formula maf4711/meister/meister', '--prefix maf4711/meister/meister', 'start:' + target])
                self.assertEqual(result.stdout, '<arg with spaces>\n<*>\n<>\n')

    def test_install_if_missing(self):
        result, events = self.run_case(installed=False)
        self.assertEqual(result.returncode, 0)
        self.assertIn('install --formula maf4711/meister/meister', events)

    def test_update_failure_stops_start(self):
        result, events = self.run_case(failure='update')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(events, ['update'])

    def test_upgrade_failure_stops_start(self):
        result, events = self.run_case(failure='package')
        self.assertEqual(result.returncode, 1)
        self.assertFalse(any(event.startswith('start:') for event in events))

    def test_child_status_preserved(self):
        result, _ = self.run_case(exit_code=42)
        self.assertEqual(result.returncode, 42)

if __name__ == '__main__':
    unittest.main()
