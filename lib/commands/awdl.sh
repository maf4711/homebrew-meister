# shellcheck shell=bash
# lib/commands/awdl.sh — `meister awdl status|off|on|guard on|guard off [--yes]`.
#
# AWDL (awdl0) causes Wi-Fi latency spikes; turning it off stops AirDrop,
# AirPlay, Handoff, Universal Control and Apple Watch unlock, and macOS turns it
# back on within minutes. So `off` and `guard on` need an explicit opt-in
# (--yes or a `y` read from the terminal — never meister_confirm, which says yes
# when unattended), and `guard on` installs a LaunchDaemon that re-applies
# `ifconfig awdl0 down` every 30 s. `awdl_heal_step` (Healer) reloads an
# installed guard that is no longer loaded and, without a guard, reports a
# fresh netcheck `awdl_spikes` verdict with both fixes. sudo only via
# ensure_sudo + `sudo -n`. Exit codes: 0 ok, 1 not verified, 3 refused,
# 4 sudo unavailable. Bash 3.2 compatible.

AWDL_GUARD_LABEL=com.meister.awdl-guard
AWDL_LOST="AirDrop, AirPlay, Handoff, Universal Control, Apple Watch unlock"

_awdl_plist() { printf '%s\n' "${MEISTER_LAUNCHD_DIR:-/Library/LaunchDaemons}/${AWDL_GUARD_LABEL}.plist"; }
_awdl_cmd() { printf '%s\n' "${AWDL_CMD:-MeisterAI}"; }
_awdl_guard_loaded() { launchctl print "system/${AWDL_GUARD_LABEL}" >/dev/null 2>&1; }

# Prints exactly one of: up, down, absent.
awdl_state() {
    local out
    out=$(ifconfig awdl0 2>/dev/null) && [ -n "$out" ] || { echo absent; return 0; }
    if printf '%s\n' "$out" | head -1 | grep -Eq '[<,]UP[,>]'; then echo up; else echo down; fi
}

awdl_guard_plist_xml() {
    cat << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${AWDL_GUARD_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/sbin/ifconfig</string>
        <string>awdl0</string>
        <string>down</string>
    </array>
    <key>StartInterval</key>
    <integer>30</integer>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
PLISTEOF
}

# $MEISTER_DIR/netcheck/latest.json → "verdict<TAB>ts<TAB>age_days<TAB>idle_dev"
# (idle_dev "-" when none). Prints nothing when missing or unreadable.
_awdl_netcheck() {
    local f="${MEISTER_DIR:-$HOME/.meister}/netcheck/latest.json"
    [ -f "$f" ] || return 0
    python3 -c '
import calendar, json, sys, time
try:
    with open(sys.argv[1]) as fh:
        d = json.load(fh)
    v = d["verdict"]
except Exception:
    sys.exit(0)
ts = d.get("ts") or "-"
try:
    age = (time.time() - calendar.timegm(time.strptime(ts, "%Y-%m-%dT%H:%M:%SZ"))) / 86400
except (TypeError, ValueError):
    age = 9999
idle = [x for x in (d.get("idle_ethernet") or []) if isinstance(x, str) and x]
print("%s\t%s\t%d\t%s" % (v, ts, int(age), idle[0] if idle else "-"))
' "$f" 2>/dev/null
}

# Lost features + better fix, then the opt-in. $1=prompt $2=yes(1/0). 0 = go.
_awdl_opt_in() {
    local prompt="$1" yes="$2" tty reply="" idle
    echo "  Disabling AWDL stops: ${AWDL_LOST}"
    IFS="$(printf '\t')" read -r _ _ _ idle <<EOF
$(_awdl_netcheck)
EOF
    [ -n "$idle" ] && [ "$idle" != - ] && echo "  Better fix: connect a LAN cable to ${idle}"
    [ "$yes" = 1 ] && return 0
    # AWDL_TTY is a test hook (file holding the answer); unset in real use → /dev/tty.
    tty="${AWDL_TTY:-}"
    if [ -z "$tty" ]; then
        [ -t 0 ] && tty=/dev/tty
    fi
    if [ -n "$tty" ] && [ -r "$tty" ]; then
        printf '  %s [y/N] ' "$prompt"
        read -r reply < "$tty" || reply=""
        [ "$tty" = /dev/tty ] || echo "$reply"
        case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; esac
    fi
    echo "  refused: needs --yes or an interactive answer"
    return 3
}

_awdl_sudo() {
    ensure_sudo "awdl" && return 0
    echo "  sudo unavailable"
    return 4
}

_awdl_verify() { # expected(up|down)
    if [ "$(awdl_state)" = "$1" ]; then
        echo "  AWDL: $1 (verified)"
        return 0
    fi
    if [ "$1" = down ]; then echo "  AWDL: still up"; else echo "  AWDL: still down"; fi
    return 1
}

# Write (or replace) the plist and bootstrap it if not loaded. Needs a sudo ticket.
awdl_guard_install() {
    local plist tmp replaced=0 rc=0
    plist=$(_awdl_plist)
    tmp=$(mktemp "${TMPDIR:-/tmp}/awdl-guard.XXXXXX") || return 1
    awdl_guard_plist_xml > "$tmp"
    if [ -e "$plist" ] && cmp -s "$tmp" "$plist"; then
        :
    else
        [ -e "$plist" ] && replaced=1
        sudo -n install -o root -g wheel -m 644 "$tmp" "$plist" || rc=1
        [ "$replaced" = 1 ] && [ "$rc" = 0 ] && echo "  replaced existing guard plist"
    fi
    rm -f "$tmp"
    [ "$rc" = 0 ] || return 1
    if [ "$replaced" = 1 ] && _awdl_guard_loaded; then
        sudo -n launchctl bootout "system/${AWDL_GUARD_LABEL}" >/dev/null 2>&1 || true
    fi
    _awdl_guard_loaded || sudo -n launchctl bootstrap system "$plist" >/dev/null 2>&1
    _awdl_guard_loaded
}

# Boot out (if loaded) and delete the plist. Needs a sudo ticket.
awdl_guard_remove() {
    local plist rc=0
    plist=$(_awdl_plist)
    if _awdl_guard_loaded; then
        sudo -n launchctl bootout "system/${AWDL_GUARD_LABEL}" >/dev/null 2>&1 || rc=1
    fi
    if [ -e "$plist" ]; then
        sudo -n rm -f "$plist" || rc=1
    fi
    return "$rc"
}

_awdl_guard_status() {
    if [ ! -e "$(_awdl_plist)" ]; then
        echo "  Guard: not installed"
    elif _awdl_guard_loaded; then
        echo "  Guard: installed+loaded (${AWDL_GUARD_LABEL})"
    else
        echo "  Guard: installed, not loaded"
    fi
}

_awdl_status() {
    local verdict ts
    echo "  AWDL: $(awdl_state)"
    _awdl_guard_status
    IFS="$(printf '\t')" read -r verdict ts _ <<EOF
$(_awdl_netcheck)
EOF
    if [ -n "$verdict" ]; then
        echo "  Last netcheck: ${verdict} (${ts})"
    else
        echo "  Last netcheck: no netcheck result yet — run $(_awdl_cmd) netcheck"
    fi
}

# Healer step: never installs, never measures; reports only via report_add.
awdl_heal_step() {
    local plist verdict ts age idle msg cmd
    plist=$(_awdl_plist)
    cmd=$(_awdl_cmd)
    if [ -e "$plist" ]; then
        _awdl_guard_loaded && return 0
        if [ "${DRY_RUN:-false}" = true ]; then
            report_add WOULD "AWDL guard not loaded — would reload it"
        elif sudo -n true 2>/dev/null && sudo -n launchctl bootstrap system "$plist" >/dev/null 2>&1; then
            report_add FIX "AWDL guard reloaded"
        else
            report_add WARN "AWDL guard not loaded, sudo unavailable — run: sudo launchctl bootstrap system ${plist}"
        fi
        return 0
    fi
    IFS="$(printf '\t')" read -r verdict ts age idle <<EOF
$(_awdl_netcheck)
EOF
    [ "$verdict" = awdl_spikes ] && [ "${age:-9999}" -lt 7 ] 2>/dev/null || return 0
    msg="AWDL latency spikes on Wi-Fi (netcheck ${ts}): "
    [ -n "$idle" ] && [ "$idle" != - ] && msg="${msg}connect a LAN cable to ${idle}, or "
    msg="${msg}run ${cmd} awdl guard on (stops ${AWDL_LOST})"
    report_add WARN "$msg"
    return 0
}

_awdl_usage() {
    cat <<'USAGE'
    status              AWDL state, guard state, last netcheck verdict (no sudo)
    off [--yes]         ifconfig awdl0 down once (macOS turns it back on)
    on                  ifconfig awdl0 up
    guard on [--yes]    LaunchDaemon com.meister.awdl-guard: AWDL down every 30 s
    guard off           Remove the guard and bring AWDL back up
    --dry-run, -n       Show what would happen; no sudo, no change
  off / guard on stop AirDrop, AirPlay, Handoff, Universal Control, Apple Watch unlock
USAGE
}

# --dry-run: say what would happen; no prompt, no sudo, no change.
_awdl_dry_run() { # "sub arg"
    local plist
    plist=$(_awdl_plist)
    if [ "$1" != "status " ] && [ "$(awdl_state)" = absent ]; then
        echo "  AWDL: absent, nothing to do"
        return 0
    fi
    echo "  [DRY-RUN — no changes, no sudo]"
    case "$1" in
        "status ") _awdl_status ;;
        "off ") echo "  Would run: sudo -n ifconfig awdl0 down (stops ${AWDL_LOST})" ;;
        "on ") echo "  Would run: sudo -n ifconfig awdl0 up" ;;
        "guard on")
            echo "  Would install ${plist} (ifconfig awdl0 down every 30 s) and bootstrap ${AWDL_GUARD_LABEL}"
            echo "  Would stop: ${AWDL_LOST}" ;;
        "guard off") echo "  Would boot out ${AWDL_GUARD_LABEL}, remove ${plist} and run ifconfig awdl0 up" ;;
        *) echo "  Unknown awdl command: $1"; _awdl_usage; return 2 ;;
    esac
    return 0
}

cmd_awdl() {
    local yes=0 dry=0 args="" arg cmd state rc
    cmd=$(_awdl_cmd)
    [ "${DRY_RUN:-false}" = true ] && dry=1
    for arg in "$@"; do
        case "$arg" in
            --yes|-y) yes=1 ;;
            --dry-run|-n) dry=1 ;;
            -h|--help) _awdl_usage; return 0 ;;
            *) args="$args $arg" ;;
        esac
    done
    # shellcheck disable=SC2086
    set -- $args
    if [ "$dry" = 1 ]; then
        _awdl_dry_run "${1:-status} ${2:-}"
        return
    fi
    case "${1:-status} ${2:-}" in
        "status ")
            _awdl_status ;;
        "off ")
            state=$(awdl_state)
            [ "$state" = absent ] && { echo "  AWDL: absent, nothing to do"; return 0; }
            _awdl_opt_in "Disable AWDL now (macOS may re-enable it)?" "$yes" || return
            _awdl_sudo || return
            sudo -n ifconfig awdl0 down
            _awdl_verify down; rc=$?
            echo "  Undo: $cmd awdl on"
            return "$rc" ;;
        "on ")
            [ "$(awdl_state)" = absent ] && { echo "  AWDL: absent, nothing to do"; return 0; }
            _awdl_sudo || return
            sudo -n ifconfig awdl0 up
            _awdl_verify up; rc=$?
            _awdl_guard_loaded && echo "  Guard still loaded — run $cmd awdl guard off"
            return "$rc" ;;
        "guard on")
            [ "$(awdl_state)" = absent ] && { echo "  AWDL: absent, nothing to do"; return 0; }
            _awdl_opt_in "Keep AWDL off with a guard every 30 s?" "$yes" || return
            _awdl_sudo || return
            rc=0
            awdl_guard_install || rc=1
            _awdl_guard_status
            sudo -n ifconfig awdl0 down
            _awdl_verify down || rc=1
            echo "  Undo: $cmd awdl guard off"
            return "$rc" ;;
        "guard off")
            if _awdl_guard_loaded || [ -e "$(_awdl_plist)" ] || [ "$(awdl_state)" = down ]; then
                _awdl_sudo || return
                rc=0
                awdl_guard_remove || rc=1
                _awdl_guard_status
                if [ "$(awdl_state)" != absent ]; then
                    sudo -n ifconfig awdl0 up
                    _awdl_verify up || rc=1
                fi
                return "$rc"
            fi
            _awdl_guard_status
            echo "  AWDL: $(awdl_state)"
            return 0 ;;
        *)
            echo "  Unknown awdl command:$args"
            _awdl_usage
            return 2 ;;
    esac
}
