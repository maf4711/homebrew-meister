#!/usr/bin/env bats

setup() {
  export MEISTER_DIR="$BATS_TEST_TMPDIR/meister"
  mkdir -p "$MEISTER_DIR"
  AI_HEAL_EXECUTE=false
  # shellcheck source=../lib/core/last_json.sh
  source "${BATS_TEST_DIRNAME}/../lib/core/last_json.sh"
}

@test "write_last_json creates valid-ish JSON" {
  AI_BACKEND_KIND=apple
  write_last_json 87 10 3 2 0 1 120 quick 6.16
  [ -f "$MEISTER_DIR/last.json" ]
  grep -q '"schema": "meister.last/v1"' "$MEISTER_DIR/last.json"
  grep -q '"score": 87' "$MEISTER_DIR/last.json"
  grep -q '"role": "batch-maintain"' "$MEISTER_DIR/last.json"
  grep -q '"ai_heal_mode": "suggest-only"' "$MEISTER_DIR/last.json"
  grep -q '"twin": "meisterSiri"' "$MEISTER_DIR/last.json"
}

@test "write_last_json execute mode" {
  AI_HEAL_EXECUTE=true
  write_last_json 90 1 0 0 0 0 10 deep 6.13
  grep -q '"ai_heal_mode": "execute"' "$MEISTER_DIR/last.json"
}

@test "JSON escapes strings and archives identical atomic reports" {
  REPORT_FIXED=($'fixed "name"\\path\nnext\tline\001')
  REPORT_WARNINGS=($'warning\rline')
  REPORT_ERRORS=()
  REPORT_WOULD_FIX=()
  MODULE_LEDGER=('FIX|Disk "cleanup"|12')
  VERIFIED_REPAIR_COUNT=1
  RUN_ID=20260914T123456Z-test
  write_last_json 87 10 1 1 0 1 120 $'quick"\nprofile' $'version\\test'
  python3 - "$MEISTER_DIR" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); r=json.loads((p/'last.json').read_text())
assert r['fixes']==['fixed "name"\\path\nnext\tline\x01']
assert r['warnings']==['warning\rline']
assert r['profile']=='quick"\nprofile'
assert r['verified_repair_count']==1
assert r['freed_bytes'] is None
assert r['modules']==[{'name':'Disk "cleanup"','status':'FIX','duration_sec':12}]
assert (p/'runs'/f"{r['run_id']}.json").read_bytes()==(p/'last.json').read_bytes()
assert not list(p.glob('.last.*')) and not list((p/'runs').glob('.report.*'))
PY
}

@test "preview cannot claim repairs or freed space even with bad caller counts" {
  DRY_RUN=true
  VERIFIED_REPAIR_COUNT=4
  FREED_BYTES=999
  REPORT_FIXED=('legacy unguarded claim')
  REPORT_WOULD_FIX=('preview action')
  write_last_json 99 1 4 0 0 9 10 quick 6.20
  python3 - "$MEISTER_DIR/last.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
assert r['dry_run'] is True
assert r['fix']==r['heal']==r['verified_repair_count']==0
assert r['freed_bytes'] is None and r['fixes']==[]
assert r['would_fix']==['preview action','legacy unguarded claim']
PY
}

@test "invalid numeric inputs cannot inject JSON and invalid run path is rejected" {
  write_last_json 'x,"bad":1' 0 0 0 0 0 'nope' auto '"'
  python3 - "$MEISTER_DIR/last.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); assert r['score'] is None and r['duration_sec']==0
PY
  cp "$MEISTER_DIR/last.json" "$MEISTER_DIR/before.json"
  RUN_ID='../escape'
  run write_last_json 99
  [ "$status" -ne 0 ]
  cmp "$MEISTER_DIR/last.json" "$MEISTER_DIR/before.json"
}

@test "a failed atomic replacement preserves the previous last report" {
  write_last_json 90
  cp "$MEISTER_DIR/last.json" "$MEISTER_DIR/before.json"
  mv() { case "${@: -1}" in */last.json) return 1 ;; *) command mv "$@" ;; esac; }
  run write_last_json 80
  [ "$status" -ne 0 ]
  cmp "$MEISTER_DIR/last.json" "$MEISTER_DIR/before.json"
}

@test "interrupted and partial reports preserve explicitly typed status" {
  for RUN_STATUS in interrupted partial; do
    write_last_json 42
    python3 - "$MEISTER_DIR/last.json" "$RUN_STATUS" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['status']==sys.argv[2]
PY
  done
}
