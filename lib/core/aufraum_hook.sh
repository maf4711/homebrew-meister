# shellcheck shell=bash
# lib/core/aufraum_hook.sh — dry-run AufRaum from Docs _Inbox (live only if AUFRAUM_APPLY=true)

aufraum_apply_enabled() {
    [ "${AUFRAUM_APPLY:-false}" = "true" ]
}

aufraum_operator() {
    local cand="${AUFRAUM_OPERATOR:-}"
    if [ -n "$cand" ]; then
        [ -f "$cand" ] || return 1
        printf '%s\n' "$cand"
        return 0
    fi
    cand="${HOME}/.grok/skills/aufraum/scripts/aufraum.py"
    [ -f "$cand" ] || return 1
    printf '%s\n' "$cand"
}

# Count planned moves in dry-run/preview text (lines with " -> ").
aufraum_count_planned() {
    local n
    n=$(grep -c ' -> ' 2>/dev/null || true)
    [ -n "$n" ] || n=0
    printf '%s\n' "$n"
}

# $1=inbox dir $2=unsorted count
# Uses log/report_add when present; otherwise stdout.
aufraum_hook_inbox() {
    local inbox="${1:-}" unsorted="${2:-0}"
    [ "${unsorted:-0}" -gt 0 ] 2>/dev/null || return 0
    local op
    op=$(aufraum_operator) || {
        _aufraum_note STEP "AufRaum operator missing — skip ${inbox:-_Inbox} (set AUFRAUM_OPERATOR)"
        return 0
    }
    local out rc=0 planned=0
    out=$(python3 "$op" apply --dry 2>/dev/null) || rc=$?
    planned=$(printf '%s\n' "$out" | aufraum_count_planned)
    if [ "${DRY_RUN:-false}" = "true" ] || ! aufraum_apply_enabled; then
        _aufraum_note STEP "AufRaum dry: ${planned} planned move(s) for _Inbox (${unsorted} unsorted, rc=${rc})"
        return 0
    fi
    python3 "$op" apply --live >/dev/null 2>&1 || true
    _aufraum_note FIX "AufRaum live apply ran (was ${unsorted} unsorted)"
}

_aufraum_note() {
    local level="$1"; shift
    if command -v log >/dev/null 2>&1; then
        log "$level" "$*"
        return
    fi
    printf '%s %s\n' "$level" "$*"
}
