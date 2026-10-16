#!/usr/bin/env bats
setup() {
  MEISTER_DIR="$BATS_TEST_TMPDIR/meister"
  DOCS_ORDER_ROOT="$BATS_TEST_TMPDIR/Documents"
  mkdir -p "$MEISTER_DIR" "$DOCS_ORDER_ROOT"
  DOCS_ORDER_ENABLED=true
  DOCS_ORDER_GHOST_CLEAN=false
  DOCS_ORDER_DATALESS_SCAN=false
  DOCS_ORDER_KNOWN=""
  DRY_RUN=false
  log() { printf '%s %s\n' "$1" "$2"; }
  report_add() { log "$@"; }
  bw_phase() { :; }
  for fn in docs_order_root_entries docs_order_write_baseline docs_order_accept_baseline module_docs_order; do
    eval "$(awk -v name="$fn" '$0==name"() {" {on=1} on {print} on && /^}$/ {exit}' "$BATS_TEST_DIRNAME/../MeisterAI.sh")"
  done
}

@test "initial docs preview never writes a baseline" {
  touch "$DOCS_ORDER_ROOT/example"
  DRY_RUN=true
  run module_docs_order
  [ "$status" = 0 ]
  [[ "$output" == *'WOULD Learn initial Documents baseline'* ]]
  [ ! -e "$MEISTER_DIR/docs_order.baseline" ]
}

@test "dash prefixed baseline names match literally and new entries stay warnings" {
  touch "$DOCS_ORDER_ROOT/--known" "$DOCS_ORDER_ROOT/new"
  printf '%s\n' '--known' > "$MEISTER_DIR/docs_order.baseline"
  run module_docs_order
  [[ "$output" == *'WARN 1 new entries in Documents root'* ]]
  [[ "$output" != *'+ --known'* ]]
  [ "$(cat "$MEISTER_DIR/docs_order.baseline")" = '--known' ]
}

@test "failed root listing cannot learn or claim a matching baseline" {
  find() {
    case " $* " in *' -empty '*) return 0 ;; esac
    echo 'root unavailable' >&2
    return 1
  }
  run module_docs_order
  [[ "$output" == *'WARN Docs order: root entries could not be checked'* ]]
  [[ "$output" != *'Root entries match baseline'* && "$output" != *'Baseline learned'* ]]
  [ ! -e "$MEISTER_DIR/docs_order.baseline" ]
}

@test "failed baseline read stays visible and preserves baseline" {
  touch "$DOCS_ORDER_ROOT/known"
  printf 'known\n' > "$MEISTER_DIR/docs_order.baseline"
  cat() { return 1; }
  run module_docs_order
  [[ "$output" == *'WARN Docs order: baseline could not be read'* ]]
  [[ "$output" != *'Root entries match baseline'* ]]
  [ "$(command cat "$MEISTER_DIR/docs_order.baseline")" = known ]
}

@test "failed initial baseline write cannot claim baseline learned" {
  mv() { return 1; }
  run module_docs_order
  [[ "$output" == *'ERROR Docs order: baseline could not be written'* ]]
  [[ "$output" != *'Baseline learned'* ]]
  [ ! -e "$MEISTER_DIR/docs_order.baseline" ]
}

@test "explicit reviewed acceptance keeps a backup and does not move documents" {
  touch "$DOCS_ORDER_ROOT/new"
  printf 'old\n' > "$MEISTER_DIR/docs_order.baseline"
  printf 'new\n' > "$BATS_TEST_TMPDIR/reviewed"
  run docs_order_accept_baseline "$BATS_TEST_TMPDIR/reviewed"
  [ "$status" = 0 ]
  [[ "$output" == *'FIX Accepted reviewed Documents baseline'* ]]
  [ "$(cat "$MEISTER_DIR/docs_order.baseline")" = new ]
  [ "$(cat "$MEISTER_DIR"/docs_order.baseline.backup.*)" = old ]
  [ -f "$DOCS_ORDER_ROOT/new" ]
}

@test "reviewed acceptance rejects drift and preview never writes" {
  touch "$DOCS_ORDER_ROOT/new"
  printf 'old\n' > "$MEISTER_DIR/docs_order.baseline"
  printf 'stale\n' > "$BATS_TEST_TMPDIR/reviewed"
  run docs_order_accept_baseline "$BATS_TEST_TMPDIR/reviewed"
  [ "$status" = 1 ]
  [[ "$output" == *'root differs from the reviewed list'* ]]
  [ "$(cat "$MEISTER_DIR/docs_order.baseline")" = old ]
  printf 'new\n' > "$BATS_TEST_TMPDIR/reviewed"
  DRY_RUN=true
  run docs_order_accept_baseline "$BATS_TEST_TMPDIR/reviewed"
  [ "$status" = 0 ]
  [[ "$output" == *'WOULD Accept reviewed Documents baseline'* ]]
  [ "$(cat "$MEISTER_DIR/docs_order.baseline")" = old ]
  [ "$(find "$MEISTER_DIR" -name '*.backup.*' | wc -l | tr -d ' ')" = 0 ]
}

@test "newline names cannot create an ambiguous reviewed baseline" {
  touch "$DOCS_ORDER_ROOT/"$'first\nsecond'
  printf 'first\nsecond\n' > "$BATS_TEST_TMPDIR/reviewed"
  run docs_order_accept_baseline "$BATS_TEST_TMPDIR/reviewed"
  [ "$status" = 1 ]
  [[ "$output" == *'root entries could not be checked'* ]]
  [ ! -e "$MEISTER_DIR/docs_order.baseline" ]
}

@test "failed ghost scan cannot claim no ghost folders" {
  find() { return 1; }
  run module_docs_order
  [[ "$output" == *'WARN Docs order: ghost folders could not be checked'* ]]
  [[ "$output" != *'No ghost folders'* ]]
}

@test "failed inbox scan cannot claim inbox empty" {
  mkdir "$DOCS_ORDER_ROOT/_Inbox"
  find() {
    case " $* " in *'/Documents/_Inbox -type f '*) return 1 ;; esac
    command find "$@"
  }
  run module_docs_order
  [[ "$output" == *'WARN Docs order: _Inbox contents could not be checked'* ]]
  [[ "$output" != *'_Inbox empty'* ]]
}

@test "failed dataless scan cannot claim all content local" {
  DOCS_ORDER_DATALESS_SCAN=true
  find() {
    case " $* " in *' -not -path '*) return 1 ;; esac
    command find "$@"
  }
  run module_docs_order
  [[ "$output" == *'WARN Docs order: local file content could not be fully checked'* ]]
  [[ "$output" != *'all content local'* ]]
}

@test "empty dataless scan is a verified empty result" {
  DOCS_ORDER_DATALESS_SCAN=true
  run module_docs_order
  [[ "$output" == *'No dataless files - all content local'* ]]
  [[ "$output" != *'could not be fully checked'* ]]
}
