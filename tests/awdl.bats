#!/usr/bin/env bats
# MeisterAI awdl — opt-in AWDL off/on, launchd guard, healer step, status.
# sudo, ensure_sudo, ifconfig, launchctl and install are shell-function stubs;
# the guard plist goes to a temp MEISTER_LAUNCHD_DIR. No real sudo, no launchd.

setup() {
  export MEISTER_DIR="$BATS_TEST_TMPDIR/.meister"
  export MEISTER_LAUNCHD_DIR="$BATS_TEST_TMPDIR/LaunchDaemons"
  mkdir -p "$MEISTER_DIR" "$MEISTER_LAUNCHD_DIR"
  source "$BATS_TEST_DIRNAME/../lib/commands/awdl.sh"
  STUB="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB"
  echo up > "$STUB/awdl"      # up | down | absent
  AWDL_FLIP=1                 # 0: "ifconfig awdl0 down" leaves it UP
  SUDO_OK=1
  unset AWDL_TTY
  export MEISTER_ALWAYS_YES=true
  DRY_RUN=false
  TM_MONITOR_ENABLED=true
  REPORT_FIXED=(); REPORT_SUCCESS=(); REPORT_WARNINGS=(); REPORT_ERRORS=(); REPORT_WOULD_FIX=()
  PLIST="$MEISTER_LAUNCHD_DIR/com.meister.awdl-guard.plist"
  log() { :; }
  eval "$(awk '$0=="report_add() {" {on=1} on {print} on && /^}$/ {exit}' "$BATS_TEST_DIRNAME/../MeisterAI.sh")"

  ensure_sudo() { echo "ensure_sudo $*" >> "$STUB/ensure"; [ "$SUDO_OK" = 1 ]; }
  sudo() {
    echo "$*" >> "$STUB/sudo_calls"
    [ "$SUDO_OK" = 1 ] || return 1
    [ "$1" = -n ] && shift
    "$@"
  }
  ifconfig() {
    [ "$1" = awdl0 ] || return 1
    local st
    st=$(cat "$STUB/awdl")
    case "${2:-}" in
      down) [ "$st" = absent ] && return 1; [ "$AWDL_FLIP" = 1 ] && echo down > "$STUB/awdl"; return 0 ;;
      up) [ "$st" = absent ] && return 1; echo up > "$STUB/awdl"; return 0 ;;
    esac
    case "$st" in
      up) echo "awdl0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500" ;;
      down) echo "awdl0: flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST> mtu 1500" ;;
      *) echo "ifconfig: interface awdl0 does not exist" >&2; return 1 ;;
    esac
  }
  launchctl() {
    echo "$*" >> "$STUB/launchctl_calls"
    case "$1" in
      print) [ -e "$STUB/loaded" ] && return 0; return 113 ;;
      bootstrap) echo "$3" > "$STUB/loaded" ;;
      bootout) rm -f "$STUB/loaded" ;;
    esac
  }
  install() { # install -o root -g wheel -m 644 src dst
    echo "$*" >> "$STUB/install_calls"
    while [ "$#" -gt 2 ]; do shift; done
    cp "$1" "$2"
  }
}

count() { # file pattern → matching lines (0 when file missing)
  [ -e "$1" ] || { echo 0; return; }
  grep -c -- "$2" "$1" || true
}

sudo_calls() { [ -e "$STUB/sudo_calls" ] && wc -l < "$STUB/sudo_calls" | tr -d ' ' || echo 0; }

iso_days_ago() {
  python3 -c 'import sys,time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - float(sys.argv[1]) * 86400)))' "$1"
}

write_latest() { # verdict days_old idle_json
  mkdir -p "$MEISTER_DIR/netcheck"
  printf '{"ts": "%s", "interface": "en1", "interface_type": "wifi", "awdl": "up", "verdict": "%s", "idle_ethernet": %s}\n' \
    "$(iso_days_ago "$2")" "$1" "${3:-[]}" > "$MEISTER_DIR/netcheck/latest.json"
}

answer() { printf '%s\n' "$1" > "$BATS_TEST_TMPDIR/tty"; export AWDL_TTY="$BATS_TEST_TMPDIR/tty"; }

# ── (a) opt-in gate ──

@test "opt-in gate: off refuses without --yes or terminal answer, even with MEISTER_ALWAYS_YES=true" {
  write_latest awdl_spikes 0 '["en0"]'
  run cmd_awdl off < /dev/null
  [ "$status" = 3 ]
  [[ "$output" == *"AirDrop, AirPlay, Handoff, Universal Control, Apple Watch unlock"* ]]
  [[ "$output" == *"Better fix: connect a LAN cable to en0"* ]]
  [[ "$output" == *"refused: needs --yes or an interactive answer"* ]]
  [ "$(sudo_calls)" = 0 ]
  [ "$(count "$STUB/ensure" ensure)" = 0 ]
  [ "$(cat "$STUB/awdl")" = up ]
}

@test "opt-in gate: guard on refuses without opt-in and writes no plist" {
  run cmd_awdl guard on < /dev/null
  [ "$status" = 3 ]
  [[ "$output" == *"AirDrop, AirPlay, Handoff, Universal Control, Apple Watch unlock"* ]]
  [[ "$output" != *"Better fix"* ]]
  [[ "$output" == *"refused: needs --yes or an interactive answer"* ]]
  [ "$(sudo_calls)" = 0 ]
  [ ! -e "$PLIST" ]
}

@test "opt-in gate: terminal answer y proceeds, n refuses" {
  answer y
  run cmd_awdl off
  [ "$status" = 0 ]
  [[ "$output" == *"AWDL: down (verified)"* ]]
  echo up > "$STUB/awdl"
  : > "$STUB/sudo_calls"
  answer n
  run cmd_awdl guard on
  [ "$status" = 3 ]
  [[ "$output" == *"refused: needs --yes or an interactive answer"* ]]
  [ "$(sudo_calls)" = 0 ]
  [ ! -e "$PLIST" ]
}

@test "opt-in gate: --yes proceeds without a terminal" {
  run cmd_awdl off --yes < /dev/null
  [ "$status" = 0 ]
  [[ "$output" == *"AWDL: down (verified)"* ]]
}

# ── (b) off / on ──

@test "off and on verify: off flips to down and is verified" {
  run cmd_awdl off --yes
  [ "$status" = 0 ]
  [[ "$output" == *"AWDL: down (verified)"* ]]
  [[ "$output" == *"Undo: MeisterAI awdl on"* ]]
  [ "$(count "$STUB/sudo_calls" '^-n ifconfig awdl0 down$')" = 1 ]
  [ "$(sudo_calls)" = 1 ]
}

@test "off and on verify: off reports still up when flags stay UP" {
  AWDL_FLIP=0
  run cmd_awdl off --yes
  [ "$status" = 1 ]
  [[ "$output" == *"AWDL: still up"* ]]
  [[ "$output" != *"(verified)"* ]]
}

@test "off and on verify: absent awdl0 exits 0 with no sudo for off and guard on" {
  echo absent > "$STUB/awdl"
  run cmd_awdl off --yes
  [ "$status" = 0 ]
  [[ "$output" == *"AWDL: absent, nothing to do"* ]]
  run cmd_awdl guard on --yes
  [ "$status" = 0 ]
  [[ "$output" == *"AWDL: absent, nothing to do"* ]]
  [ "$(sudo_calls)" = 0 ]
  [ ! -e "$PLIST" ]
}

@test "off and on verify: on brings awdl0 up and warns about a loaded guard" {
  echo down > "$STUB/awdl"
  echo "$PLIST" > "$STUB/loaded"
  run cmd_awdl on
  [ "$status" = 0 ]
  [[ "$output" == *"AWDL: up (verified)"* ]]
  [[ "$output" == *"Guard still loaded — run MeisterAI awdl guard off"* ]]
  [ "$(count "$STUB/sudo_calls" '^-n ifconfig awdl0 up$')" = 1 ]
  rm -f "$STUB/loaded"
  echo down > "$STUB/awdl"
  run cmd_awdl on
  [ "$status" = 0 ]
  [[ "$output" != *"Guard still loaded"* ]]
}

# ── (c) guard ──

@test "guard install and removal are idempotent: install twice" {
  run cmd_awdl guard on --yes
  [ "$status" = 0 ]
  [[ "$output" == *"Guard: installed+loaded (com.meister.awdl-guard)"* ]]
  [[ "$output" == *"AWDL: down (verified)"* ]]
  [[ "$output" == *"Undo: MeisterAI awdl guard off"* ]]
  run cmd_awdl guard on --yes
  [ "$status" = 0 ]
  [ "$(ls "$MEISTER_LAUNCHD_DIR" | wc -l | tr -d ' ')" = 1 ]
  [ -f "$PLIST" ]
  grep -q '<string>com.meister.awdl-guard</string>' "$PLIST"
  python3 - "$PLIST" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    d = plistlib.load(f)
assert d["Label"] == "com.meister.awdl-guard", d
assert d["ProgramArguments"] == ["/sbin/ifconfig", "awdl0", "down"], d
assert d["StartInterval"] == 30, d
assert d["RunAtLoad"] is True, d
PY
  [ "$(count "$STUB/sudo_calls" '^-n launchctl bootstrap system '"$PLIST"'$')" = 1 ]
  [ "$(count "$STUB/sudo_calls" '^-n install -o root -g wheel -m 644 ')" -ge 1 ]
}

@test "guard install and removal are idempotent: remove twice" {
  cmd_awdl guard on --yes > /dev/null
  : > "$STUB/sudo_calls"
  run cmd_awdl guard off
  [ "$status" = 0 ]
  [[ "$output" == *"Guard: not installed"* ]]
  [[ "$output" == *"AWDL: up (verified)"* ]]
  [ ! -e "$PLIST" ]
  [ ! -e "$STUB/loaded" ]
  run cmd_awdl guard off
  [ "$status" = 0 ]
  [[ "$output" == *"Guard: not installed"* ]]
  [ ! -e "$PLIST" ]
  [ "$(cat "$STUB/awdl")" = up ]
  [ "$(count "$STUB/sudo_calls" '^-n launchctl bootout system/com.meister.awdl-guard$')" = 1 ]
  [ "$(count "$STUB/sudo_calls" '^-n ifconfig awdl0 up$')" -ge 1 ]
}

@test "guard install and removal are idempotent: sudo unavailable exits 4 without plist" {
  SUDO_OK=0
  run cmd_awdl guard on --yes
  [ "$status" = 4 ]
  [[ "$output" == *"sudo unavailable"* ]]
  [ ! -e "$PLIST" ]
  [ "$(sudo_calls)" = 0 ]
}

@test "guard install and removal are idempotent: foreign plist is replaced" {
  echo '<plist>foreign</plist>' > "$PLIST"
  run cmd_awdl guard on --yes
  [ "$status" = 0 ]
  [[ "$output" == *"replaced existing guard plist"* ]]
  grep -q '<integer>30</integer>' "$PLIST"
  ! grep -q foreign "$PLIST"
}

# ── (d) healer ──

@test "healer: plist present and not loaded with sudo reloads the guard" {
  awdl_guard_plist_xml > "$PLIST"
  awdl_heal_step
  [ "${#REPORT_FIXED[@]}" = 1 ]
  [ "${REPORT_FIXED[0]}" = "AWDL guard reloaded" ]
  [ "${#REPORT_WARNINGS[@]}" = 0 ]
  [ "$(count "$STUB/sudo_calls" '^-n launchctl bootstrap system '"$PLIST"'$')" = 1 ]
}

@test "healer: plist present, not loaded, sudo unavailable warns without fix" {
  awdl_guard_plist_xml > "$PLIST"
  SUDO_OK=0
  awdl_heal_step
  [ "${#REPORT_FIXED[@]}" = 0 ]
  [ "${#REPORT_WARNINGS[@]}" = 1 ]
  [[ "${REPORT_WARNINGS[0]}" == *"AWDL guard not loaded, sudo unavailable"* ]]
  [ ! -e "$STUB/loaded" ]
}

@test "healer: loaded guard adds nothing" {
  awdl_guard_plist_xml > "$PLIST"
  echo "$PLIST" > "$STUB/loaded"
  awdl_heal_step
  [ "${#REPORT_FIXED[@]}" = 0 ]
  [ "${#REPORT_WARNINGS[@]}" = 0 ]
  [ "$(sudo_calls)" = 0 ]
}

@test "healer: fresh awdl_spikes verdict without guard warns with both fixes and no sudo" {
  write_latest awdl_spikes 1 '["en0"]'
  awdl_heal_step
  [ "${#REPORT_WARNINGS[@]}" = 1 ]
  [[ "${REPORT_WARNINGS[0]}" == *"AWDL latency spikes"* ]]
  [[ "${REPORT_WARNINGS[0]}" == *"connect a LAN cable to en0"* ]]
  [[ "${REPORT_WARNINGS[0]}" == *"MeisterAI awdl guard on"* ]]
  [ "${#REPORT_FIXED[@]}" = 0 ]
  [ "$(sudo_calls)" = 0 ]
}

@test "healer: ok_wired, 8-day-old or missing latest.json adds no warning" {
  write_latest ok_wired 0 '["en0"]'
  awdl_heal_step
  write_latest wifi_spikes 0
  awdl_heal_step
  write_latest awdl_spikes 8 '["en0"]'
  awdl_heal_step
  rm -f "$MEISTER_DIR/netcheck/latest.json"
  awdl_heal_step
  echo 'not json' > "$MEISTER_DIR/netcheck/latest.json"
  awdl_heal_step
  [ "${#REPORT_WARNINGS[@]}" = 0 ]
  [ "${#REPORT_FIXED[@]}" = 0 ]
  [ "$(sudo_calls)" = 0 ]
}

@test "healer: DRY_RUN=true makes no sudo calls" {
  DRY_RUN=true
  awdl_guard_plist_xml > "$PLIST"
  run awdl_heal_step
  [ "$status" = 0 ]
  awdl_heal_step
  [ "$(sudo_calls)" = 0 ]
  [ "${#REPORT_FIXED[@]}" = 0 ]
  [ "${#REPORT_WOULD_FIX[@]}" = 1 ]
  [[ "${REPORT_WOULD_FIX[0]}" == *"would reload"* ]]
  [[ "${REPORT_WOULD_FIX[0]}" != *"reloaded"* ]]
  [ ! -e "$STUB/loaded" ]
}

@test "healer: module_healer in MeisterAI.sh calls awdl_heal_step" {
  body=$(awk '$0=="module_healer() {" {on=1} on {print} on && /^}$/ {exit}' "$BATS_TEST_DIRNAME/../MeisterAI.sh")
  [ -n "$body" ]
  [[ "$body" == *"awdl_heal_step"* ]]
}

# ── dry run ──

@test "dry run: guard on --yes --dry-run makes no sudo calls and writes no plist" {
  run cmd_awdl guard on --yes --dry-run < /dev/null
  [ "$status" = 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
  [[ "$output" == *"Would install"* ]]
  [ "$(sudo_calls)" = 0 ]
  [ "$(count "$STUB/ensure" ensure)" = 0 ]
  [ ! -e "$PLIST" ]
  [ ! -e "$STUB/loaded" ]
}

@test "dry run: off -n and guard off --dry-run change nothing" {
  run cmd_awdl off -n < /dev/null
  [ "$status" = 0 ]
  [[ "$output" == *"Would run: sudo -n ifconfig awdl0 down"* ]]
  awdl_guard_plist_xml > "$PLIST"
  echo "$PLIST" > "$STUB/loaded"
  run cmd_awdl guard off --dry-run
  [ "$status" = 0 ]
  [ "$(sudo_calls)" = 0 ]
  [ "$(cat "$STUB/awdl")" = up ]
  [ -e "$PLIST" ]
  [ -e "$STUB/loaded" ]
}

# ── (e) status ──

@test "status: prints awdl, guard and last netcheck lines without sudo" {
  write_latest awdl_spikes 0 '["en0"]'
  ts=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ts"])' "$MEISTER_DIR/netcheck/latest.json")
  run cmd_awdl status
  [ "$status" = 0 ]
  [[ "$output" == *"AWDL: up"* ]]
  [[ "$output" == *"Guard: not installed"* ]]
  [[ "$output" == *"Last netcheck: awdl_spikes ($ts)"* ]]
  [ "$(sudo_calls)" = 0 ]
}

@test "status: guard states and missing netcheck result" {
  echo down > "$STUB/awdl"
  awdl_guard_plist_xml > "$PLIST"
  run cmd_awdl status
  [[ "$output" == *"AWDL: down"* ]]
  [[ "$output" == *"Guard: installed, not loaded"* ]]
  [[ "$output" == *"no netcheck result yet"* ]]
  echo "$PLIST" > "$STUB/loaded"
  echo absent > "$STUB/awdl"
  run cmd_awdl status
  [[ "$output" == *"AWDL: absent"* ]]
  [[ "$output" == *"Guard: installed+loaded"* ]]
  [ "$(sudo_calls)" = 0 ]
}
