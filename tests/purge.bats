#!/usr/bin/env bats
# meister purge — reclaim Finder "purgeable" space (local snapshots + iCloud copies).
# osascript and tmutil are stubbed; nothing here touches the real Mac.

setup() {
  export MEISTER_DIR="$BATS_TEST_TMPDIR/.meister"
  export HOME="$BATS_TEST_TMPDIR/home"
  CLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
  mkdir -p "$MEISTER_DIR" "$HOME/Desktop" "$HOME/Documents" "$CLOUD"
  ln -s "$HOME/Desktop" "$CLOUD/Desktop"
  ln -s "$HOME/Documents" "$CLOUD/Documents"
  source "$BATS_TEST_DIRNAME/../lib/commands/purge.sh"
  : > "$MEISTER_DIR/calls"
  # osascript stub: free space grows once an evict call happened (simulated reclaim)
  osascript() {
    local mode="${4:-}" root="${5:-}"
    printf 'osascript %s %s\n' "$mode" "$root" >> "$MEISTER_DIR/calls"
    case "$mode" in
      volume)
        if grep -q '^osascript evict' "$MEISTER_DIR/calls"; then
          echo "1200000000000 1000000000000 4000000000000"
        else
          echo "1200000000000 800000000000 4000000000000"
        fi ;;
      check|evict)
        tr '\0' '\n' >> "$MEISTER_DIR/stdin-$mode"
        echo "progress-from-js" >&2
        if [ "$mode" = check ]; then
          echo "ok=10 bytes=150000000000 failed=0 skipped=2"
        else
          echo "ok=9 bytes=140000000000 failed=1 skipped=2"
        fi ;;
      *) return 2 ;;
    esac
  }
  tmutil() {
    printf 'tmutil %s\n' "$*" >> "$MEISTER_DIR/calls"
    case "$1" in
      listlocalsnapshots)
        echo "Snapshots for disk /:"
        grep -q '^tmutil thinlocalsnapshots' "$MEISTER_DIR/calls" ||
          printf 'com.apple.TimeMachine.2026-11-05-120000.local\ncom.apple.TimeMachine.2026-11-06-080000.local\n' ;;
      thinlocalsnapshots) echo "Thinned local snapshots:" ;;
    esac
  }
}

old_file() { # path size_bytes
  mkdir -p "$(dirname "$1")"
  head -c "$2" /dev/zero > "$1"
  touch -t 202601010000 "$1"
}

@test "roots are iCloud Drive plus Desktop and Documents only when they sync to iCloud" {
  run purge_icloud_roots
  [ "$status" = 0 ]
  [ "${#lines[@]}" = 3 ]
  [ "${lines[0]}" = "$CLOUD" ]
  [ "${lines[1]}" = "$HOME/Desktop" ]
  [ "${lines[2]}" = "$HOME/Documents" ]
  rm "$CLOUD/Documents"
  run purge_icloud_roots
  [ "${#lines[@]}" = 2 ]
  [[ "$output" != *"$HOME/Documents"* ]]
}

@test "candidates skip recent, small, developer and nosync files" {
  old_file "$HOME/Documents/old.pdf" 2000000
  old_file "$HOME/Documents/small.txt" 1000
  old_file "$HOME/Documents/repo/.git/objects/pack.bin" 2000000
  old_file "$HOME/Documents/app/node_modules/x/big.bin" 2000000
  old_file "$HOME/Documents/cache.nosync/big.bin" 2000000
  head -c 2000000 /dev/zero > "$HOME/Documents/fresh.pdf"
  run bash -c "source '$BATS_TEST_DIRNAME/../lib/commands/purge.sh'; purge_candidates '$HOME/Documents' 30 1 | tr '\0' '\n'"
  [ "$status" = 0 ]
  [ "$output" = "$HOME/Documents/old.pdf" ]
  run bash -c "source '$BATS_TEST_DIRNAME/../lib/commands/purge.sh'; purge_candidates '$HOME/Documents' 30 0 | tr '\0' '\n' | sort"
  [[ "$output" == *small.txt* ]]
  [[ "$output" != *fresh.pdf* ]]
}

@test "preview reports purgeable, snapshots and evictable bytes and changes nothing" {
  old_file "$HOME/Documents/old.pdf" 2000000
  run cmd_purge
  [ "$status" = 0 ]
  [[ "$output" == *'Purgeable now:'*'400.0 GB'* ]]
  [[ "$output" == *'PREVIEW'* ]]
  [[ "$output" == *'Local snapshots:'*'2'* ]]
  [[ "$output" == *'com.apple.TimeMachine.2026-11-06-080000.local'* ]]
  [[ "$output" == *'Evictable total: 450.0 GB in 30 files'* ]]
  [[ "$output" == *'meister purge --do'* ]]
  [[ "$output" != *'Freed'* ]]
  ! grep -q 'thinlocalsnapshots\|^osascript evict' "$MEISTER_DIR/calls"
  grep -qx "osascript check $HOME/Documents" "$MEISTER_DIR/calls"
  grep -qx "$HOME/Documents/old.pdf" "$MEISTER_DIR/stdin-check"
}

@test "--do thins snapshots, evicts each root and reports measured freed space" {
  run cmd_purge --do
  [ "$status" = 0 ]
  grep -qE '^tmutil thinlocalsnapshots / [0-9]+ 4$' "$MEISTER_DIR/calls"
  [ "$(grep -c '^osascript evict' "$MEISTER_DIR/calls")" = 3 ]
  grep -qx "osascript evict $HOME/Desktop" "$MEISTER_DIR/calls"
  [[ "$output" == *'Snapshots: 2 before, 0 after'* ]]
  [[ "$output" == *'evicted 9 files (140.0 GB), 1 failed'* ]]
  [[ "$output" == *'Freed: 200.0 GB'* ]]
  [[ "$output" == *'Purgeable after:'*'200.0 GB'* ]]
}

@test "--do with an explicit path only evicts that path and leaves snapshots alone" {
  mkdir -p "$HOME/Documents/Archive"
  run cmd_purge --do "$HOME/Documents/Archive"
  [ "$status" = 0 ]
  [ "$(grep -c '^osascript evict' "$MEISTER_DIR/calls")" = 1 ]
  grep -qx "osascript evict $HOME/Documents/Archive" "$MEISTER_DIR/calls"
  ! grep -q 'tmutil' "$MEISTER_DIR/calls"
}

@test "--days and --min-mb are validated" {
  run cmd_purge --days 90
  [ "$status" = 0 ]
  [[ "$output" == *'last 90 days'* ]]
  run cmd_purge --days abc
  [ "$status" = 2 ]
  [[ "$output" == *'--days needs a whole number'* ]]
  run cmd_purge --min-mb
  [ "$status" = 2 ]
  run cmd_purge --bogus
  [ "$status" = 2 ]
  run cmd_purge "$HOME/does-not-exist"
  [ "$status" = 2 ]
}

@test "missing osascript fails honestly without touching snapshots" {
  PURGE_OSASCRIPT=/nonexistent/osascript
  run cmd_purge --do
  [ "$status" = 1 ]
  [[ "$output" == *'osascript'* ]]
  [[ "$output" != *'Freed'* ]]
  ! grep -q 'tmutil' "$MEISTER_DIR/calls"
}

@test "bytes are formatted in decimal units like Finder" {
  [ "$(purge_fmt_bytes 0)" = "0 B" ]
  [ "$(purge_fmt_bytes 150000000)" = "150.0 MB" ]
  [ "$(purge_fmt_bytes 445900000000)" = "445.9 GB" ]
  [ "$(purge_fmt_bytes 1237477133193)" = "1.24 TB" ]
}

@test "both twins wire purge into the CLI and the help text" {
  for script in MeisterAI.sh meister.sh; do
    grep -q 'cmd_purge' "$BATS_TEST_DIRNAME/../$script"
    grep -q 'commands/purge.sh' "$BATS_TEST_DIRNAME/../$script"
    grep -qE '^  (MeisterAI|meister) purge ' "$BATS_TEST_DIRNAME/../$script"
  done
}

@test "--do explains that Finder's Available stays the same while purgeable turns into free" {
  run cmd_purge --do
  [ "$status" = 0 ]
  [[ "$output" == *'Available'*'stays the same'* ]]
  [[ "$output" == *'purgeable to free'* ]]
  [[ "$output" == *'Cmd+I'* ]]
}

@test "preview warns up front that Finder's Available will not grow" {
  run cmd_purge
  [ "$status" = 0 ]
  [[ "$output" == *'Available'*'will not grow'* ]]
}

@test "progress from the helper is shown only when enabled" {
  PURGE_PROGRESS=1 run cmd_purge
  [[ "$output" == *'progress-from-js'* ]]
  PURGE_PROGRESS=0 run cmd_purge
  [[ "$output" != *'progress-from-js'* ]]
}

@test "real JXA helper reports progress on stderr when PURGE_PROGRESS=1" {
  command -v osascript >/dev/null 2>&1 || skip "no osascript"
  unset -f osascript
  f="$BATS_TEST_TMPDIR/local.bin"; head -c 1000 /dev/zero > "$f"
  out=$(printf '%s\0' "$f" | PURGE_PROGRESS=1 osascript -l JavaScript "$BATS_TEST_DIRNAME/../lib/commands/purge.js" check X 2>"$BATS_TEST_TMPDIR/err")
  [[ "$out" == "ok=0 bytes=0 failed=0 skipped=1" ]]
  grep -q '1/1' "$BATS_TEST_TMPDIR/err"
  out=$(printf '%s\0' "$f" | PURGE_PROGRESS=0 osascript -l JavaScript "$BATS_TEST_DIRNAME/../lib/commands/purge.js" check X 2>"$BATS_TEST_TMPDIR/err")
  [ ! -s "$BATS_TEST_TMPDIR/err" ]
}

@test "apply hint and usage name the CLI that was invoked" {
  PURGE_CMD=MeisterAI run cmd_purge
  [ "$status" = 0 ]
  [[ "$output" == *'Apply with: MeisterAI purge --do'* ]]
  PURGE_CMD=MeisterAI run cmd_purge --help
  [[ "$output" == *'Usage: MeisterAI purge'* ]]
}
