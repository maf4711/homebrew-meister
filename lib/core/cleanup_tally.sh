# shellcheck shell=bash
# lib/core/cleanup_tally.sh — count-based cleanup helpers
# Expects: DRY_RUN (true/false string), FIND_TIMEOUT_SEC optional.
# Bash 3.2 compatible (macOS).

# Remove only stale cache entries. macOS-owned caches and Homebrew downloads
# stay under their own managers' control; live temporary files are not caches.
# $2 may be "sudo". Counts describe entries, never bytes or APFS free space.
cleanup_cache_root() {
    local root="${1%/}" privilege="${2:-}" entry protected canonical keep scan flags
    local min_age="${CACHE_MIN_AGE_DAYS:-7}" root_canonical scan_timeout="${FIND_TIMEOUT_SEC:-60}"
    local -a preserved=()
    CACHE_CLEANUP_FOUND=0 CACHE_CLEANUP_REMOVED=0 CACHE_CLEANUP_PRESERVED=0
    CACHE_CLEANUP_ACTIVE=0 CACHE_CLEANUP_FAILED=0 CACHE_CLEANUP_ELIGIBLE=0
    [ -d "$root" ] || return 0
    if [[ ! "$min_age" =~ ^[1-9][0-9]{0,3}$ ]]; then
        log WARN "   Invalid CACHE_MIN_AGE_DAYS (must be a positive whole number)"
        CACHE_CLEANUP_FAILED=1
        return 1
    fi
    if [[ ! "$scan_timeout" =~ ^[1-9][0-9]{0,3}$ ]] || ! command -v timeout >/dev/null 2>&1; then
        log WARN "   Bounded cache inspection unavailable; caches preserved"
        CACHE_CLEANUP_FAILED=1
        return 1
    fi
    root_canonical=$(realpath "$root" 2>/dev/null) || root_canonical="$root"
    case "$root_canonical/" in /System/Library/Caches/*|/private/var/tmp/*|/var/tmp/*)
        CACHE_CLEANUP_PRESERVED=1
        log STEP "   Preserved macOS-managed cache/temporary root: $root"
        return 0 ;;
    esac
    # Listing names does not stat TCC-protected children (find would); it still
    # distinguishes an unreadable root from an empty cache before globbing.
    if ! timeout "$scan_timeout" /bin/ls -A "$root" >/dev/null 2>&1; then
        CACHE_CLEANUP_FAILED=1
        log WARN "   Cache root could not be listed; preserved $root"
        return 1
    fi
    for protected in "$HOME/Library/Caches/Homebrew" "${HOMEBREW_CACHE:-}"; do
        [ -n "$protected" ] || continue
        preserved+=("${protected%/}")
        if canonical=$(realpath "$protected" 2>/dev/null); then
            preserved+=("${canonical%/}")
        fi
    done
    for entry in "$root"/*; do
        # A literal unmatched glob is empty; an enumerated but TCC-protected
        # entry is not. Classify managed names before probing their metadata.
        if [ "$entry" = "$root/*" ] && [ ! -e "$entry" ] && [ ! -L "$entry" ]; then
            continue
        fi
        CACHE_CLEANUP_FOUND=$((CACHE_CLEANUP_FOUND + 1))
        case "${entry##*/}" in com.apple.*|CloudKit)
            CACHE_CLEANUP_PRESERVED=$((CACHE_CLEANUP_PRESERVED + 1))
            log STEP "   Preserved macOS-managed cache: $entry"
            continue ;;
        esac
        if [ ! -e "$entry" ] && [ ! -L "$entry" ]; then
            CACHE_CLEANUP_FAILED=$((CACHE_CLEANUP_FAILED + 1))
            log WARN "   Cache entry unavailable; preserved $entry"
            continue
        fi
        canonical=$(realpath "$entry" 2>/dev/null) || canonical="$entry"
        keep=false
        for protected in "${preserved[@]}"; do
            case "$protected/" in "$entry/"*|"$canonical/"*) keep=true ;; esac
            case "$entry/" in "$protected/"*) keep=true ;; esac
            case "$canonical/" in "$protected/"*) keep=true ;; esac
            $keep && break
        done
        if $keep; then
            CACHE_CLEANUP_PRESERVED=$((CACHE_CLEANUP_PRESERVED + 1))
            log STEP "   Preserved Homebrew cache path: $entry"
            continue
        fi
        if ! flags=$(stat -f '%Sf' "$entry" 2>/dev/null); then
            # GNU stat has no BSD file flags. Still require a successful
            # metadata probe; unreadable entries must never become candidates.
            if stat -c '%a' "$entry" >/dev/null 2>&1; then
                flags=''
            else
                CACHE_CLEANUP_FAILED=$((CACHE_CLEANUP_FAILED + 1))
                log WARN "   Cache metadata unavailable; preserved $entry"
                continue
            fi
        fi
        case "$flags" in *restricted*|*uchg*|*schg*|*sunlnk*|*uunlnk*)
            CACHE_CLEANUP_PRESERVED=$((CACHE_CLEANUP_PRESERVED + 1))
            log STEP "   Preserved protected cache: $entry"
            continue ;;
        esac
        # Inspect the whole entry so a stale directory containing a newly
        # written file is retained. find does not follow cache symlinks.
        local -a command_prefix=()
        [ "$privilege" != sudo ] || command_prefix=(sudo -n)
        if ! scan=$(timeout "$scan_timeout" "${command_prefix[@]}" find "$entry" -mtime "-$min_age" -print -quit 2>&1); then
            CACHE_CLEANUP_FAILED=$((CACHE_CLEANUP_FAILED + 1))
            log WARN "   Cache inspection failed; preserved $entry: $scan"
            continue
        fi
        if [ -n "$scan" ]; then
            CACHE_CLEANUP_ACTIVE=$((CACHE_CLEANUP_ACTIVE + 1))
            continue
        fi
        CACHE_CLEANUP_ELIGIBLE=$((CACHE_CLEANUP_ELIGIBLE + 1))
        if [ "${DRY_RUN:-false}" = true ]; then
            log STEP "   [DRY-RUN] would remove stale cache: $entry"
            continue
        fi
        if scan=$(timeout "$scan_timeout" "${command_prefix[@]}" rm -rf -- "$entry" 2>&1) &&
            [ ! -e "$entry" ] && [ ! -L "$entry" ]; then
            CACHE_CLEANUP_REMOVED=$((CACHE_CLEANUP_REMOVED + 1))
        else
            CACHE_CLEANUP_FAILED=$((CACHE_CLEANUP_FAILED + 1))
            log WARN "   Cache removal not verified: $entry${scan:+: $scan}"
        fi
    done
    if [ "$CACHE_CLEANUP_REMOVED" -gt 0 ]; then
        VERIFIED_REPAIR_COUNT=$((${VERIFIED_REPAIR_COUNT:-0} + 1))
    fi
    [ "$CACHE_CLEANUP_FAILED" -eq 0 ]
}

# Report verified work separately from retained entries and genuine failures.
# $1 root, $2 privilege (empty or sudo), $3 label (User/System).
cleanup_cache_report() {
    local root="$1" privilege="${2:-}" label="${3:-Cache}"
    cleanup_cache_root "$root" "$privilege" || true
    if [ "${DRY_RUN:-false}" = true ]; then
        [ "$CACHE_CLEANUP_ELIGIBLE" -eq 0 ] || report_add WOULD "$label caches: remove $CACHE_CLEANUP_ELIGIBLE stale entries (Homebrew downloads preserved)"
    elif [ "$CACHE_CLEANUP_REMOVED" -gt 0 ]; then
        report_add FIX "$label caches: removed $CACHE_CLEANUP_REMOVED stale entries (Homebrew downloads preserved)"
    fi
    if [ "$CACHE_CLEANUP_FAILED" -gt 0 ]; then
        report_add WARN "$label cache cleanup incomplete: $CACHE_CLEANUP_FAILED entries failed; see log (Homebrew downloads preserved)"
    else
        log STEP "   $label caches: $CACHE_CLEANUP_REMOVED removed, $CACHE_CLEANUP_ACTIVE recent, $CACHE_CLEANUP_PRESERVED managed/protected entries preserved"
    fi
    return 0
}

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
