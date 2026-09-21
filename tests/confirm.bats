#!/usr/bin/env bats
# Unattended confirmations: yes without waiting, never abort for missing TTY.

setup() {
  # shellcheck source=../lib/core/confirm.sh
  source "${BATS_TEST_DIRNAME}/../lib/core/confirm.sh"
}

@test "ALWAYS_YES true confirms without reading stdin" {
  MEISTER_ALWAYS_YES=true
  run meister_confirm "Quarantine these?"
  [ "$status" -eq 0 ]
  [[ "$output" == *yes* ]]
}

@test "no TTY confirms even when ALWAYS_YES is false" {
  MEISTER_ALWAYS_YES=false
  run meister_confirm "Move to Trash?"
  [ "$status" -eq 0 ]
}

@test "meister_always_yes is the default" {
  unset MEISTER_ALWAYS_YES
  meister_always_yes
}

@test "remove/orphans without TTY no longer abort for missing -y" {
  python3 - "$BATS_TEST_DIRNAME/../MeisterAI.sh" "$BATS_TEST_TMPDIR" <<'PY'
import os, pathlib, subprocess, sys
script = pathlib.Path(sys.argv[1]).resolve()
root = pathlib.Path(sys.argv[2]) / 'fixture'
state = root / '.meister'
state.mkdir(parents=True)
env = {**os.environ, 'MEISTER_DIR': str(state), 'MEISTER_LIB': str(script.parent / 'lib'),
       'MEISTER_ALWAYS_YES': 'true'}
src = pathlib.Path(script).read_text()
assert 'Non-interactive terminal and no -y/--yes given — aborting.' not in src
assert 'meister_confirm' in src
PY
}
