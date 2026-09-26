#!/usr/bin/env bats
setup() { bats_require_minimum_version 1.5.0; }
@test "mail aliases route help and status without a maintenance run" {
  for twin in MeisterAI.sh meister.sh; do
    for alias in megasmart smartinbox; do
      run env MEISTER_DIR="$BATS_TEST_TMPDIR/state" bash "$BATS_TEST_DIRNAME/../$twin" "$alias" --help
      [ "$status" -eq 0 ]
      [[ "$output" == *"Kein direkter IMAP-Zugang"* ]]
      # Node 22 emits its SQLite notice on stderr; JSON is a stdout contract.
      run --separate-stderr env MEISTER_DIR="$BATS_TEST_TMPDIR/state" bash "$BATS_TEST_DIRNAME/../$twin" "$alias" status --json
      [ "$status" -eq 0 ]
      [[ "$output" == '{"jobs":[]}' ]]
    done
  done
  [ ! -e "$BATS_TEST_TMPDIR/state/last.json" ]
  [ ! -e "$BATS_TEST_TMPDIR/state/mail/run.lock" ]
}
@test "SmartInbox is in every maintenance profile by default" {
  source "$BATS_TEST_DIRNAME/../lib/core/profiles.sh"
  for profile in quick auto deep all; do
    RUN_PROFILE="$profile"
    module_in_profile "SmartInbox"
  done
}
@test "daily dry run includes mail in the plan without opening Mail or running the model" {
  run env MEISTER_DIR="$BATS_TEST_TMPDIR/state" bash "$BATS_TEST_DIRNAME/../MeisterAI.sh" --auto -n
  [ "$status" -eq 0 ]
  [[ "$output" == *"SmartInbox"* ]]
  [ ! -d "$BATS_TEST_TMPDIR/state/mail" ]
}
@test "default Mail module reports only verified completion and never heals/retries failed writes" {
  python3 - "$BATS_TEST_DIRNAME/../MeisterAI.sh" <<'PY'
import subprocess,sys
source=open(sys.argv[1]).read()
function='module_megasmart() {'+source.split('module_megasmart() {',1)[1].split('\n}\n',1)[0]+'\n}'
for result,code,expected in [('{"status":"completed","moved":3}',0,'FIX'),('{"status":"failed","moved":0}',1,'WARN'),('{"status":"applying","moved":0}',0,'WARN'),('{"status":"completed","moved":0,"unavailable":7}',0,'WARN'),('{"status":"completed","moved":3,"unavailable":2}',0,'FIX\nWARN'),('{"status":"completed","moved":0,"deferred":12}',0,'WARN')]:
 script='''report_add() { printf '%s\\n' "$1"; }
log() { :; }
MEISTER_LIB_DIR=/unused
node() { printf '%s' '''+repr(result)+'''; return '''+str(code)+'''; }
'''+function+'\nmodule_megasmart\n'
 run=subprocess.run(['bash','-c',script],text=True,capture_output=True)
 assert run.returncode==0,(run.stdout,run.stderr)
 assert run.stdout.strip()==expected,(run.stdout,run.stderr)
PY
}
