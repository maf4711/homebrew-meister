import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'scripts/homebrew-launcher.sh'

class LaunchTests(unittest.TestCase):
    def run_case(self, command='meister', installed=True, failure='', exit_code=0,
                 stamp=None, config=None, ttl=None, args=None, opt=True, repeats=1):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'bin').mkdir()
            (root / 'opt').mkdir()
            (root / 'state').mkdir()
            (root / 'events').write_text('')
            cache = root / 'state/brew_launcher_last_update'
            if stamp is not None:
                cache.write_text(str(stamp) + '\n')
            if config is not None:
                (root / 'state/config').write_text(config)
            brew = root / 'bin/brew'
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
            launcher.write_text(SOURCE.read_text().replace('@HOMEBREW_PREFIX@', tmp))
            launcher.chmod(0o755)
            (root / 'keg/libexec').mkdir(parents=True)
            for name in ['meister', 'MeisterAI']:
                executable = root / 'keg/libexec' / name
                executable.write_text('''#!/bin/bash
printf 'start:%s\\n' "${0##*/}" >> "$TEST_ROOT/events"
printf '%s %s\\n' "$MEISTER_BREW_UPDATE_FRESH" "$([[ "$MEISTER_BREW_UPDATE_PID" = "$$" ]] && echo same-pid)" > "$TEST_ROOT/proof"
printf '<%s>\\n' "$@"
exit "$CHILD_EXIT"
''')
                executable.chmod(0o755)
            if installed and opt:
                (root / 'opt/meister').symlink_to(root / 'keg')
            env = dict(os.environ, TEST_ROOT=tmp, FAILURE=failure, MEISTER_DIR=str(root / 'state'),
                       INSTALLED='yes' if installed else 'no', CHILD_EXIT=str(exit_code))
            env.pop('RUN_PROFILE', None)
            env.pop('BREW_UPDATE_MAX_AGE_SEC', None)
            if ttl is not None:
                env['BREW_UPDATE_MAX_AGE_SEC'] = str(ttl)
            for _ in range(repeats):
                result = subprocess.run([str(launcher), *(args if args is not None else ['arg with spaces', '*', ''])],
                                        env=env, capture_output=True, text=True)
            result.cache_stamp = cache.read_text().strip() if cache.exists() else None
            result.proof = (root / 'proof').read_text().strip() if (root / 'proof').exists() else None
            return result, (root / 'events').read_text().splitlines()

    def test_update_upgrade_then_current_executable_and_arguments(self):
        for command, target in [('meister', 'meister'), ('meisterAI', 'MeisterAI'), ('MeisterAI', 'MeisterAI')]:
            with self.subTest(command=command):
                result, events = self.run_case(command)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(events, ['update', 'upgrade --formula maf4711/meister/meister', 'start:' + target])
                self.assertEqual(result.stdout, '<arg with spaces>\n<*>\n<>\n')
                self.assertEqual(result.proof, 'true same-pid')

    def test_install_if_missing(self):
        result, events = self.run_case(installed=False)
        self.assertEqual(result.returncode, 0)
        self.assertIn('install --formula maf4711/meister/meister', events)

    def test_update_failure_stops_start(self):
        result, events = self.run_case(failure='update')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(events, ['update'])
        self.assertIsNone(result.cache_stamp)

    def test_upgrade_failure_stops_start(self):
        result, events = self.run_case(failure='package')
        self.assertEqual(result.returncode, 1)
        self.assertFalse(any(event.startswith('start:') for event in events))
        self.assertIsNone(result.cache_stamp)

    def test_child_status_preserved(self):
        result, _ = self.run_case(exit_code=42)
        self.assertEqual(result.returncode, 42)

    def test_fresh_cache_avoids_all_brew_processes(self):
        result, events = self.run_case(stamp=int(time.time()) - 10)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(events, ['start:meister'])
        self.assertEqual(result.proof, 'false same-pid')
        self.assertIn('Cache', result.stderr)

    def test_success_stamp_is_shared_by_subsequent_invocations(self):
        result, events = self.run_case(repeats=2)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(events, ['update', 'upgrade --formula maf4711/meister/meister', 'start:meister', 'start:meister'])

    def test_stale_future_and_malformed_cache_force_refresh(self):
        for stamp in [int(time.time()) - 43201, int(time.time()) + 1000, 'garbage', '99999999999999999999']:
            with self.subTest(stamp=stamp):
                result, events = self.run_case(stamp=stamp)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(events[0], 'update')

    def test_deep_all_and_zero_ttl_force_refresh(self):
        for options in [{'args': ['--deep']}, {'args': ['-a']}, {'args': ['-an']}, {'args': ['-qa']},
                        {'args': ['-a', '--auto']}, {'ttl': 0},
                        {'config': 'RUN_PROFILE="deep"\n'}, {'config': 'BREW_UPDATE_MAX_AGE_SEC=0\n'}]:
            with self.subTest(options=options):
                result, events = self.run_case(stamp=int(time.time()) - 10, **options)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(events[0], 'update')

    def test_config_ttl_and_leading_zero_are_parsed_as_data(self):
        result, events = self.run_case(stamp=int(time.time()) - 100,
                                      config='BREW_UPDATE_MAX_AGE_SEC="00050"\n')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(events[0], 'update')

    def test_missing_opt_path_never_uses_cache_and_falls_back_to_prefix(self):
        result, events = self.run_case(stamp=int(time.time()) - 10, opt=False)
        self.assertEqual(result.returncode, 0)
        self.assertIn('--prefix maf4711/meister/meister', events)
        self.assertEqual(events[0], 'update')

    def test_missing_or_zero_stamp_cannot_claim_success_with_large_ttl(self):
        for stamp in [None, 0]:
            result, events = self.run_case(stamp=stamp, ttl=9999999999)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(events[0], 'update')

    def test_subcommand_arguments_and_option_delimiter_do_not_force_refresh(self):
        for args in [['explain', '--deep'], ['--', '-a']]:
            result, events = self.run_case(stamp=int(time.time()) - 10, args=args)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(events, ['start:meister'])

if __name__ == '__main__':
    unittest.main()
