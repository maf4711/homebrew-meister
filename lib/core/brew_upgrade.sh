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

# Homebrew 7 prints `Error: <cask>: It seems there is already an App at '…'.`
# (also "a Command Wrapper", "a Binary"); a TTY capture adds ANSI codes and CR.
_brew_conflict_clean() {
    local esc
    esc=$(printf '\033')
    tr -d '\r' | sed -e "s/${esc}\[[0-9;]*[A-Za-z]//g"
}

# stdin: captured Homebrew output. stdout: one cask token per stale-artifact conflict.
brew_cask_conflict_names() {
    _brew_conflict_clean |
        sed -nE "s/^(.*[[:space:]])?([a-z0-9][a-z0-9@._+-]*): It seems there is already an? (App|Command Wrapper|Binary) at '.*/\2/p" |
        sort -u
}

# Casks already given their one forced reinstall in this process (AI Updates
# and Homebrew share it).
BREW_CASK_REPAIRED="${BREW_CASK_REPAIRED:-}"

# Remove $3 only when it is a real (non-symlink) entry, not named . or ..,
# whose physical parent lies below the physical $2/Caskroom/$1/ and that folder
# is not a symlink.
_brew_cask_remove_stale() {
    local cask="$1" prefix="$2" path="$3" base root parent
    while [[ "$path" == */ ]]; do path="${path%/}"; done
    base="${path##*/}"
    if [ -n "$prefix" ] && [ -n "$base" ] && [ "$base" != . ] && [ "$base" != .. ] &&
        root=$(cd -P "$prefix/Caskroom" 2>/dev/null && pwd -P) &&
        [ -d "$root/$cask" ] && [ ! -L "$root/$cask" ] &&
        parent=$(cd -P "$(dirname "$path")" 2>/dev/null && pwd -P) &&
        [[ "$parent" == "$root/$cask/"?* ]] &&
        [ ! -L "$parent/$base" ] && [ -e "$parent/$base" ]; then
        log STEP "     $cask: removing stale $parent/$base"
        rm -rf -- "${parent:?}/$base"
    else
        log STEP "     $cask: leaving $3 (not a Caskroom artifact)"
    fi
}

# Homebrew never replaces a real file at a link target, not even with --force
# (cask/artifact/symlinked.rb), so a self-updated binary blocks its cask for
# good. Park $3 in MEISTER_DIR only when it is a regular non-symlink file
# directly in the physical $2/bin and cask $1 declares exactly that target.
# Sets BREW_CASK_PARKED_FROM / BREW_CASK_PARKED_AT for the caller.
_brew_cask_park_conflict() {
    local cask="$1" prefix="$2" path="$3" bin parent base store
    base="${path##*/}"
    [ -n "$prefix" ] && [ -n "$base" ] && [ -n "${MEISTER_DIR:-}" ] || return 1
    bin=$(cd -P "$prefix/bin" 2>/dev/null && pwd -P) || return 1
    parent=$(cd -P "$(dirname "$path")" 2>/dev/null && pwd -P) || return 1
    [ "$parent" = "$bin" ] && [ -f "$bin/$base" ] && [ ! -L "$bin/$base" ] || return 1
    brew info --cask --json=v2 "$cask" 2>/dev/null | python3 -c '
import json, sys
try:
    cask = json.load(sys.stdin)["casks"][0]
    hit = any(isinstance(a, dict) and a.get("target") == sys.argv[1] for a in cask["artifacts"])
except (ValueError, KeyError, IndexError, TypeError):
    hit = False
sys.exit(0 if hit else 1)
' "$path" || return 1
    store=$(umask 077; mkdir -p "$MEISTER_DIR/backups/cask-conflicts" &&
        mktemp -d "$MEISTER_DIR/backups/cask-conflicts/${cask}.XXXXXX") || return 1
    if mv -- "$bin/$base" "$store/$base"; then
        BREW_CASK_PARKED_FROM="$bin/$base"
        BREW_CASK_PARKED_AT="$store/$base"
        log STEP "     $cask: moved $bin/$base aside (Homebrew does not overwrite real files)"
        return 0
    fi
    rmdir "$store" 2>/dev/null
    return 1
}

# After the reinstall: drop the parked file when Homebrew put its own artifact
# at the target, otherwise put it back so nothing the user had goes missing.
_brew_cask_unpark() {
    local ok="$1" from="${BREW_CASK_PARKED_FROM:-}" at="${BREW_CASK_PARKED_AT:-}"
    BREW_CASK_PARKED_FROM="" BREW_CASK_PARKED_AT=""
    [ -n "$from" ] && [ -n "$at" ] || return 0
    if [ "$ok" = true ] && { [ -e "$from" ] || [ -L "$from" ]; }; then
        rm -f -- "$at"
    elif [ ! -e "$from" ] && [ ! -L "$from" ] && mv -- "$at" "$from"; then
        log STEP "     restored $from"
    else
        log WARN "     previous $from kept at $at"
        return 0
    fi
    rmdir "$(dirname "$at")" 2>/dev/null || true
}

# $1 cask token, $2 capture of the failed upgrade, $3 true when it used --greedy.
# Removes the stale artifact named in $2 only under $(brew --prefix)/Caskroom/<cask>/
# (a real file at a cask-declared target in $(brew --prefix)/bin is parked instead),
# runs one forced reinstall per process (bounded by BREW_CASK_REPAIR_TIMEOUT,
# default 180 s; the caller pre-authenticates sudo), then returns 0 only when
# `brew outdated` no longer lists the cask.
brew_cask_repair() {
    local cask="$1" capture="${2:-}" greedy="${3:-false}" prefix path re out to why
    local -a bounded=() flags=(--cask)
    [ -n "$cask" ] || return 1
    [ "$greedy" = true ] && flags+=(--greedy)
    if command -v command_exists >/dev/null 2>&1; then
        command_exists timeout && bounded=(timeout)
    elif command -v timeout >/dev/null 2>&1; then
        bounded=(timeout)
    fi
    case " $BREW_CASK_REPAIRED " in
        *" $cask "*) ;;
        *)
            if ${DRY_RUN:-false}; then
                log STEP "   [DRY-RUN] $cask: remove stale Caskroom artifact; brew reinstall --cask --force"
                return 1
            fi
            BREW_CASK_REPAIRED="${BREW_CASK_REPAIRED:+$BREW_CASK_REPAIRED }$cask"
            if [ -s "$capture" ] && [ -r "$capture" ]; then
                prefix=$(brew --prefix 2>/dev/null) || prefix=""
                re=$(printf '%s' "$cask" | sed 's/[.+]/\\&/g')
                while IFS= read -r path; do
                    [ -n "${BREW_CASK_PARKED_AT:-}" ] || _brew_cask_park_conflict "$cask" "$prefix" "$path" ||
                        _brew_cask_remove_stale "$cask" "$prefix" "$path"
                done < <(_brew_conflict_clean < "$capture" |
                    sed -nE "s/^(.*[[:space:]])?${re}: It seems there is already an? (App|Command Wrapper|Binary) at '(.*)'\.?[[:space:]]*$/\3/p")
            fi
            log STEP "     $cask: brew reinstall --cask --force"
            to="${BREW_CASK_REPAIR_TIMEOUT:-180}"
            if ! out=$("${bounded[@]}" ${bounded:+"$to"} brew reinstall --cask --force "$cask" </dev/null 2>&1); then
                why=$(printf '%s\n' "$out" | _brew_conflict_clean | grep -E '^Error:' | tail -1)
                log WARN "     $cask: forced reinstall failed${why:+ — $why}"
                _brew_cask_unpark false
                return 1
            fi
            _brew_cask_unpark true
            ;;
    esac
    out=$("${bounded[@]}" ${bounded:+60} brew outdated "${flags[@]}" "$cask" 2>/dev/null) || return 1
    [ -z "$out" ]
}
