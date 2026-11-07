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
    local dir f metadata blocks links
    if [ "${DRY_RUN:-false}" != true ]; then
        : "${FREED_BYTES:=0}"
        # Allocated file bytes successfully unlinked, not a claim about APFS free
        # space (snapshots/open handles may retain blocks). Hard links excluded.
        # shellcheck disable=SC2034
        FREED_BYTES_SCOPE=measured_file_removals
    fi
    for dir in "$@"; do
        [ -d "$dir" ] || continue
        while IFS= read -r -d '' f; do
            CLEANUP_FOUND=$((CLEANUP_FOUND + 1))
            if [ "${DRY_RUN:-false}" = "true" ]; then
                continue
            fi
            metadata=$(stat -c '%b %h' "$f" 2>/dev/null) || metadata=$(stat -f '%b %l' "$f" 2>/dev/null) || metadata=''
            read -r blocks links <<< "$metadata"
            if [ -f "$f" ] && rm -f "$f" 2>/dev/null && [ ! -e "$f" ]; then
                CLEANUP_REMOVED=$((CLEANUP_REMOVED + 1))
                case "$blocks:$links" in *[!0-9:]*|:*) ;; *)
                    if [ "$links" = 1 ]; then FREED_BYTES=$((FREED_BYTES + blocks * 512)); fi ;;
                esac
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
    if [ "${DRY_RUN:-false}" != true ] && [ "${CLEANUP_REMOVED:-0}" -gt 0 ]; then
        : "${VERIFIED_REPAIR_COUNT:=0}"
        VERIFIED_REPAIR_COUNT=$((VERIFIED_REPAIR_COUNT + 1))
    fi
    return 0
}

# $1 = megabytes already claimed in a FIX line. Preview is a no-op.
# Bytes are allocated-file estimates (MB * 1048576), not APFS free space.
meister_record_freed_mb() {
    local mb="${1:-0}"
    [ "${DRY_RUN:-false}" = true ] && return 0
    case "$mb" in ''|*[!0-9]*) return 0 ;; esac
    [ "$mb" -gt 0 ] || return 0
    : "${FREED_BYTES:=0}"
    FREED_BYTES=$((FREED_BYTES + mb * 1048576))
    # shellcheck disable=SC2034
    FREED_BYTES_SCOPE=measured_file_removals
}
