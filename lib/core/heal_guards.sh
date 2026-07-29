# shellcheck shell=bash
# lib/core/heal_guards.sh — pure AI-Heal allowlist (no side effects)
# Sourced by meisterSiri / meister. Safe to unit-test with bats.

# Allowlisted verbs for AI-Heal / Learned-Fix execution
: "${FM_HEAL_ALLOW:= killall pkill qlmanage mdutil mdimport dscacheutil atsutil defaults launchctl lsregister tccutil purge fc-cache dot_clean }"

# Return 0 if $1 is a single simple allowlisted command (no shell metacharacters).
heal_command_allowed() {
    local cmd="$1"
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"; cmd="${cmd%"${cmd##*[![:space:]]}"}"
    [ -z "$cmd" ] && return 1
    case "$cmd" in
        *sudo*|*';'*|*'&'*|*'|'*|*'>'*|*'<'*|*'$'*|*'`'*|*'\'*) return 1 ;;
        'rm '*|*' rm '*|*chmod*|*chown*|'dd '*|*' dd '*|*mkfs*|*'-rf'*) return 1 ;;
    esac
    local verb="${cmd%%[[:space:]]*}"; verb="${verb##*/}"
    case "$FM_HEAL_ALLOW" in *" $verb "*) return 0 ;; *) return 1 ;; esac
}

# True if response looks like a model placeholder (INSIGHTS 2026-07-04 #1)
heal_is_placeholder() {
    local s="$1"
    echo "$s" | grep -qiE '/path/to|<[a-z_-]+>|your_|/example|example\.(com|txt)|placeholder'
}
