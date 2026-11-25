#!/usr/bin/env bats
# meister sysdata — measure and slim macOS "System Data".
# Every external tool is stubbed; nothing here touches the real Mac.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  CALLS="$BATS_TEST_TMPDIR/calls"
  SIZES="$BATS_TEST_TMPDIR/sizes"
  : > "$CALLS"; : > "$SIZES"
  export SYSDATA_SYS_SIM="$BATS_TEST_TMPDIR/sys/CoreSimulator"
  export SYSDATA_VM="$BATS_TEST_TMPDIR/sys/vm"
  export SYSDATA_VOLUME="$BATS_TEST_TMPDIR"
  export SYSDATA_PROGRESS=0
  export CALLS SIZES
  source "$BATS_TEST_DIRNAME/../lib/commands/sysdata.sh"

  # du -skx <path>: size in KB from the $SIZES map ("<kb> <path>"), 0 otherwise.
  du() {
    local path="${!#}" kb
    kb=$(awk -v p="$path" '{k=$1; sub(/^[^ ]+ /,""); if ($0==p) {print k; exit}}' "$SIZES")
    printf '%s\t%s\n' "${kb:-0}" "$path"
  }
  df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted\n/dev/disk3s5 3900000000 1900000000 2000000000 50%% /\n'; }
  tmutil() {
    printf 'tmutil %s\n' "$*" >> "$CALLS"
    case "$1" in
      listlocalsnapshots)
        echo "Snapshots for disk /:"
        grep -q '^tmutil thinlocalsnapshots' "$CALLS" ||
          printf 'com.apple.TimeMachine.2026-11-25-113935.local\ncom.apple.TimeMachine.2026-11-25-164954.local\n' ;;
    esac
  }
  xcrun() {
    printf 'xcrun %s\n' "$*" >> "$CALLS"
    if [ "$*" = "simctl runtime list -j" ]; then
      cat <<'JSON'
{"A":{"identifier":"A","platformIdentifier":"com.apple.platform.iphonesimulator","version":"26.4.1","sizeBytes":8000000000,"deletable":true,"lastUsedAt":"2026-08-27T11:26:33Z"},
 "B":{"identifier":"B","platformIdentifier":"com.apple.platform.iphonesimulator","version":"27.0","sizeBytes":9000000000,"deletable":true,"lastUsedAt":"2026-11-20T10:00:00Z"},
 "C":{"identifier":"C","platformIdentifier":"com.apple.platform.appletvsimulator","version":"26.5","sizeBytes":4000000000,"deletable":true}}
JSON
    fi
  }
  ollama() {
    printf 'ollama %s\n' "$*" >> "$CALLS"
    if [ "$1" = list ]; then
      printf 'NAME                       ID              SIZE      MODIFIED\n'
      printf 'qwen3-coder-next:latest    ca06e9e4087c    51 GB     2 months ago\n'
      printf 'eurollm:22b                24880ee79707    18 GB     3 months ago\n'
      printf 'eurollm:latest             24880ee79707    18 GB     3 months ago\n'
    fi
  }
  docker() {
    printf 'docker %s\n' "$*" >> "$CALLS"
    case "$1" in
      info) [ "${DOCKER_UP:-1}" = 1 ] ;;
      system) [ "$2" = prune ] && echo "Total reclaimed space: 3.2GB"; return 0 ;;
    esac
  }
  colima() {
    printf 'colima %s\n' "$*" >> "$CALLS"
    [ "$1" = status ] && return 0
    return 0
  }
  uv() { printf 'uv %s\n' "$*" >> "$CALLS"; }
  npm() { printf 'npm %s\n' "$*" >> "$CALLS"; }
}

size() { # kb path — also creates the path
  mkdir -p "$2"
  printf '%s %s\n' "$1" "$2" >> "$SIZES"
}

@test "measure lists categories largest first and never double counts mounted runtimes" {
  size 180000000 "$HOME/.ollama"
  size 62000000 "$HOME/.colima"
  size 2000000 "$HOME/Library/Developer/Xcode/DerivedData"
  size 17000000 "$SYSDATA_SYS_SIM"
  run cmd_sysdata
  [ "$status" = 0 ]
  [[ "$output" == *'PREVIEW'* ]]
  # ollama (184 GB) is listed before Colima (63 GB) and DerivedData
  ollama_line=$(printf '%s\n' "$output" | grep -n 'ollama' | head -1 | cut -d: -f1)
  colima_line=$(printf '%s\n' "$output" | grep -n 'Colima' | head -1 | cut -d: -f1)
  [ "$ollama_line" -lt "$colima_line" ]
  [[ "$output" == *'184.3 GB'*'ollama'* ]]
  # runtime images come from simctl sizeBytes (8+9+4 GB), the system cache from du -x
  [[ "$output" == *'21.0 GB'*'Simulator runtimes'* ]]
  [[ "$output" == *'Local Time Machine snapshots: 2'* ]]
  # preview never changes anything
  ! grep -qE 'thinlocalsnapshots|simctl delete|simctl runtime delete|ollama rm|prune|fstrim|cache clean' "$CALLS"
}

@test "du is always called with -x so APFS mounts are not counted" {
  size 1000 "$HOME/.ollama"
  du() { printf 'du %s\n' "$*" >> "$CALLS"; printf '0\t%s\n' "${!#}"; }
  run cmd_sysdata
  [ "$status" = 0 ]
  grep -q '^du ' "$CALLS"
  ! grep '^du ' "$CALLS" | grep -v -- '-skx'
}

@test "preview lists review candidates with the exact command" {
  size 1000 "$HOME/.ollama"
  run cmd_sysdata
  [[ "$output" == *'ollama rm qwen3-coder-next:latest'* ]]
  # shared blobs: eurollm tags have the same ID and are flagged as sharing data
  [[ "$output" == *'eurollm:latest'*'shares data with eurollm:22b'* ]]
  # oldest iOS runtime is a candidate, the newest per platform is kept
  [[ "$output" == *'xcrun simctl runtime delete A'* ]]
  [[ "$output" != *'xcrun simctl runtime delete B'* ]]
  [[ "$output" != *'xcrun simctl runtime delete C'* ]]
}

@test "--do runs only the safe steps and reports measured free space" {
  size 2000000 "$HOME/Library/Developer/Xcode/DerivedData"
  touch "$HOME/Library/Developer/Xcode/DerivedData/junk"
  mkdir -p "$HOME/.cache/uv" "$HOME/.npm"
  run cmd_sysdata --do
  [ "$status" = 0 ]
  grep -qE '^tmutil thinlocalsnapshots / [0-9]+ 4$' "$CALLS"
  grep -qx 'xcrun simctl delete unavailable' "$CALLS"
  grep -qx 'uv cache prune' "$CALLS"
  grep -qx 'npm cache clean --force' "$CALLS"
  grep -qx 'docker system prune -f' "$CALLS"
  grep -qx 'colima ssh -- sudo fstrim -a' "$CALLS"
  [ ! -e "$HOME/Library/Developer/Xcode/DerivedData/junk" ]
  [[ "$output" == *'Snapshots: 2 before, 0 after'* ]]
  # never removes models, runtimes or volumes without --review
  ! grep -qE 'ollama rm|runtime delete|--volumes' "$CALLS"
  [[ "$output" == *'Free space:'* ]]
}

@test "--do skips docker cleanly when the daemon is down" {
  DOCKER_UP=0
  run cmd_sysdata --do
  [ "$status" = 0 ]
  ! grep -q 'docker system prune' "$CALLS"
  ! grep -q 'fstrim' "$CALLS"
}

@test "--review without a terminal removes nothing" {
  run cmd_sysdata --do --review < /dev/null
  [ "$status" = 0 ]
  ! grep -qE 'ollama rm|runtime delete' "$CALLS"
  [[ "$output" == *'needs a terminal'* ]]
}

@test "--review asks per item, default is no, yes removes exactly that item" {
  export SYSDATA_ASSUME_TTY=1
  mkdir -p "$HOME/.lmstudio/models/pub/big-model"
  size 40000000 "$HOME/.lmstudio/models/pub/big-model"
  # largest first: qwen3-coder-next 51 GB=y, LM Studio 41 GB=n, eurollm 18 GB x2=<enter>/n, runtime A 8 GB=y
  run cmd_sysdata --do --review <<< $'y\nn\n\nn\ny\n'
  [ "$status" = 0 ]
  grep -qx 'ollama rm qwen3-coder-next:latest' "$CALLS"
  ! grep -q 'ollama rm eurollm' "$CALLS"
  grep -qx 'xcrun simctl runtime delete A' "$CALLS"
  [ -d "$HOME/.lmstudio/models/pub/big-model" ]
}

@test "unknown options are rejected with exit 64" {
  run cmd_sysdata --bogus
  [ "$status" = 64 ]
  [[ "$output" == *'Usage'* ]]
}

@test "MeisterAI and meister dispatch sysdata and list it in help" {
  for f in MeisterAI.sh meister.sh; do
    grep -q '"${1:-}" = "sysdata"' "$BATS_TEST_DIRNAME/../$f"
    grep -q 'commands/sysdata.sh' "$BATS_TEST_DIRNAME/../$f"
    grep -qE 'sysdata \[--do\]' "$BATS_TEST_DIRNAME/../$f"
  done
}
