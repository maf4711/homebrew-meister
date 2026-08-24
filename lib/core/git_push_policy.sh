# shellcheck shell=bash
# lib/core/git_push_policy.sh — master switch + per-repo opt-out for auto-push
# Sourced by meisterSiri / meister. Safe to unit-test with bats.

# Global: may Autofix/Git module push at all?
git_push_enabled() {
    [ "${GIT_AUTO_PUSH:-false}" = "true" ] || return 1
    [ "${AUTOFIX_GIT_PUSH:-true}" = "true" ] || return 1
    return 0
}

# Per repo: enabled globally AND no .meister-nopush / git config meister.nopush
# $1 = repo directory (contains .git)
git_repo_may_push() {
    local repo_dir="${1:-}"
    git_push_enabled || return 1
    [ -n "$repo_dir" ] && [ -d "$repo_dir" ] || return 1
    [ -f "$repo_dir/.meister-nopush" ] && return 1
    case "$(git -C "$repo_dir" config --get meister.nopush 2>/dev/null || true)" in
        true|TRUE|1|yes) return 1 ;;
    esac
    return 0
}
