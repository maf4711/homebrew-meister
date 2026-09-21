# shellcheck shell=bash
# Unattended confirmations: default yes, never block a LaunchAgent/GUI run.

meister_always_yes() {
    case "${MEISTER_ALWAYS_YES:-true}" in
        0|false|no|NO|off|OFF) ;;
        *) return 0 ;;
    esac
    [ "${REMOVE_YES:-false}" = true ] && return 0
    [ "${ORPH_YES:-false}" = true ] && return 0
    [ -t 0 ] && return 1
    return 0
}

# $1=prompt. Returns 0 for yes. Never waits when unattended or stdin is not a TTY.
meister_confirm() {
    local prompt="${1:-Continue?}"
    if meister_always_yes; then
        printf '  %s → yes\n' "$prompt"
        return 0
    fi
    local reply=""
    printf '  %s [Y/n] ' "$prompt"
    read -r reply || true
    case "$reply" in
        ''|[yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}
