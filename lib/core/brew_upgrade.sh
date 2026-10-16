# shellcheck shell=bash
# lib/core/brew_upgrade.sh — which brew upgrade Meister should run (testable)
#
# Daily hang 2026-08-18: bare `brew upgrade` also upgrades casks, output is
# captured until the process exits (UI looks frozen), then `--cask --greedy`
# has no timeout and blocks on WhatsApp livecheck / Word pkg installer.

# Auto-update / GUI casks that hang unattended (livecheck or sudo installer).
: "${BREW_CASK_SKIP:=whatsapp microsoft-word}"

# Preserve the actual failure even when a TTY bypasses the main log. The caller
# may delete its temporary capture; this private copy remains for diagnosis.
brew_record_upgrade_failure() {
    local kind="$1" name="$2" rc="$3" capture="${4:-}" evidence="" safe_name
    safe_name=${name//[^a-zA-Z0-9@._+-]/_}
    if [ -n "$capture" ] && [ -f "$capture" ] && [ -n "${MEISTER_DIR:-}" ]; then
        evidence=$(umask 077; mkdir -p "$MEISTER_DIR/update-failures" &&
            mktemp "$MEISTER_DIR/update-failures/${kind}-${safe_name}.XXXXXX") || evidence=""
        if [ -n "$evidence" ] && ! cat "$capture" > "$evidence"; then
            rm -f "$evidence"
            evidence=""
        fi
    fi
    report_add WARN "Homebrew: $name upgrade failed (exit $rc)${evidence:+; log: $evidence}"
}

# true if this profile should force auto-updating casks (--greedy).
# Override: BREW_CASK_GREEDY=true|false in ~/.meister/config
brew_cask_greedy_wanted() {
    local profile="${1:-${RUN_PROFILE:-auto}}"
    case "${BREW_CASK_GREEDY:-}" in
        true)  return 0 ;;
        false) return 1 ;;
    esac
    case "$profile" in
        deep|all) return 0 ;;
        *)        return 1 ;;
    esac
}

# $1 = cask token (no version). 0 = skip this cask.
brew_cask_is_skipped() {
    local name="${1%% *}"
    local tok
    [ -z "$name" ] && return 1
    # shellcheck disable=SC2086
    for tok in ${BREW_CASK_SKIP}; do
        [ "$tok" = "$name" ] && return 0
    done
    return 1
}

# stdin: brew outdated lines (token or "token version"). stdout: keepers.
brew_filter_skipped_casks() {
    local line name
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        name="${line%% *}"
        brew_cask_is_skipped "$name" && continue
        printf '%s\n' "$line"
    done
}

# Space-separated cask tokens from an outdated listing (one per line).
brew_cask_tokens() {
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        printf '%s\n' "${line%% *}"
    done
}
