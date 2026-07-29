# shellcheck shell=bash
# lib/core/cleanup_tally.sh — count-based cleanup helpers
# Expects: DRY_RUN (true/false string), FIND_TIMEOUT_SEC optional.
# Bash 3.2 compatible (macOS).

# Sets CLEANUP_FOUND / CLEANUP_REMOVED / CLEANUP_SKIPPED
# $1 = basename pattern; remaining = root dirs
cleanup_find_delete() {
    local name="$1"
    shift
    CLEANUP_FOUND=0
    CLEANUP_REMOVED=0
    CLEANUP_SKIPPED=0
    local dir f
    for dir in "$@"; do
        [ -d "$dir" ] || continue
        while IFS= read -r -d '' f; do
            CLEANUP_FOUND=$((CLEANUP_FOUND + 1))
            if [ "${DRY_RUN:-false}" = "true" ]; then
                continue
            fi
            if rm -f "$f" 2>/dev/null; then
                CLEANUP_REMOVED=$((CLEANUP_REMOVED + 1))
            else
                CLEANUP_SKIPPED=$((CLEANUP_SKIPPED + 1))
            fi
        done < <(
            if command -v timeout >/dev/null 2>&1; then
                timeout "${FIND_TIMEOUT_SEC:-60}" find "$dir" \
                    \( -path "*/Library/*" -o -path "*/.Trash/*" \
                       -o -path "*/Mobile Documents/*" -o -path "*/.Trash" \) -prune \
                    -o -name "$name" -type f -print0 2>/dev/null || true
            else
                find "$dir" \
                    \( -path "*/Library/*" -o -path "*/.Trash/*" \
                       -o -path "*/Mobile Documents/*" -o -path "*/.Trash" \) -prune \
                    -o -name "$name" -type f -print0 2>/dev/null || true
            fi
        )
    done
    return 0
}
