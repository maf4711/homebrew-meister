# shellcheck shell=bash
# GNU timeout normally creates a separate process group. GUI cancellation owns
# one whole CLI group, so keep timeouts and their children in that group.
meister_configure_timeout() {
    [ "${MEISTER_GUI_PROCESS_GROUP:-0}" = 1 ] || return 0
    local resolved
    resolved=$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null) || return 0
    case "$resolved" in /*) ;; *) return 0 ;; esac
    [ -x "$resolved" ] || return 0
    MEISTER_TIMEOUT_BIN="$resolved"
    timeout() { "$MEISTER_TIMEOUT_BIN" --foreground "$@"; }
}
