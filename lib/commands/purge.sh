# shellcheck shell=bash
# lib/commands/purge.sh — `meister purge`: reclaim Finder's "purgeable" space.
#
# Finder's "löschbar/purgeable" is space macOS may reclaim on its own: local
# Time Machine snapshots and local copies of files that already live in iCloud.
# purge makes that explicit:
#   1. thin local Time Machine snapshots (tmutil, no sudo needed)
#   2. remove local copies of iCloud Drive / Desktop / Documents files that are
#      fully uploaded and unchanged for N days (they stay in iCloud and Finder,
#      a double-click downloads them again)
# Default is a read-only preview; --do applies. Bash 3.2 compatible.

PURGE_OSASCRIPT="${PURGE_OSASCRIPT:-osascript}"
PURGE_JS="${PURGE_JS:-$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/purge.js}"

# Decimal units, like Finder.
purge_fmt_bytes() {
    awk -v b="${1:-0}" 'BEGIN {
        if (b >= 1e12)      printf "%.2f TB", b / 1e12
        else if (b >= 1e9)  printf "%.1f GB", b / 1e9
        else if (b >= 1e6)  printf "%.1f MB", b / 1e6
        else if (b >= 1e3)  printf "%.1f KB", b / 1e3
        else                printf "%d B", b
    }'
}

purge_js() {
    "$PURGE_OSASCRIPT" -l JavaScript "$PURGE_JS" "$@"
}

# check/evict with live progress on stderr when it is a terminal (PURGE_PROGRESS=1/0 overrides).
purge_js_scan() {
    local progress="${PURGE_PROGRESS:-}"
    if [ -z "$progress" ]; then
        if [ -t 2 ]; then progress=1; else progress=0; fi
    fi
    if [ "$progress" = 1 ]; then
        PURGE_PROGRESS=1 purge_js "$@"
    else
        PURGE_PROGRESS=0 purge_js "$@" 2>/dev/null
    fi
}

purge_data_volume() {
    if [ -d /System/Volumes/Data ]; then echo /System/Volumes/Data; else echo /; fi
}

# Prints "<important-free> <free> <total>".
purge_volume() {
    purge_js volume "$(purge_data_volume)" 2>/dev/null
}

# iCloud Drive itself plus Desktop/Documents when "Desktop & Documents" sync is on.
purge_icloud_roots() {
    local cloud="$HOME/Library/Mobile Documents/com~apple~CloudDocs" name
    [ -d "$cloud" ] || return 0
    echo "$cloud"
    for name in Desktop Documents; do
        if [ -e "$cloud/$name" ] && [ -d "$HOME/$name" ]; then
            echo "$HOME/$name"
        fi
    done
}

# NUL-separated candidate files: not modified for <days>, >= <min_mb>.
# Access time is ignored: Spotlight and iCloud touch it, so it says nothing about real use.
# Developer folders and .nosync items are never offered for eviction.
purge_candidates() {
    local root="$1" days="$2" min_mb="$3"
    local size_args=()
    [ "$min_mb" -gt 0 ] && size_args=(-size +"$((min_mb * 1024 - 1))"k)
    find "$root" \( -name .git -o -name node_modules -o -name '*.nosync' -o -name .Trash \) -prune \
        -o -type f ! -name '*.icloud' ! -name .DS_Store \
        ${size_args[@]+"${size_args[@]}"} -mtime +"$days" -print0 2>/dev/null
}

purge_snapshot_names() {
    tmutil listlocalsnapshots / 2>/dev/null | grep -E '^com\.apple\.TimeMachine\.' || true
}

_purge_field() {
    printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -1
}

_purge_usage() {
    echo "  Usage: ${PURGE_CMD:-meister} purge [--do] [--days N] [--min-mb N] [path ...]"
    cat <<'USAGE'
    (no flags)   Preview: purgeable space, snapshots, evictable iCloud files
    --do         Thin local snapshots and remove local iCloud copies
    --days N     Keep files changed in the last N days local (default 30)
    --min-mb N   Only files of at least N MB (default 1, 0 = all)
    path ...     Only these iCloud folders; snapshots are left alone
USAGE
}

cmd_purge() {
    local apply=false days=30 min_mb=1 paths=() arg
    while [ $# -gt 0 ]; do
        arg="$1"
        case "$arg" in
            --do) apply=true ;;
            -n|--dry-run) apply=false ;;
            --days|--min-mb)
                if ! [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                    echo "  $arg needs a whole number"; _purge_usage; return 2
                fi
                if [ "$arg" = --days ]; then days="$2"; else min_mb="$2"; fi
                shift ;;
            -h|--help) _purge_usage; return 0 ;;
            -*) echo "  Unknown option: $arg"; _purge_usage; return 2 ;;
            *)
                if [ ! -e "$arg" ]; then echo "  Not found: $arg"; return 2; fi
                paths+=("$arg") ;;
        esac
        shift
    done

    if ! command -v "$PURGE_OSASCRIPT" >/dev/null 2>&1 || [ ! -f "$PURGE_JS" ]; then
        echo "  osascript (JavaScript for Automation) or purge.js is unavailable."
        echo "  Nothing was measured and nothing was changed."
        return 1
    fi

    local vol imp_before free_before total
    vol=$(purge_volume)
    read -r imp_before free_before total <<< "$vol"
    if ! [[ "${imp_before:-}" =~ ^[0-9]+$ && "${free_before:-}" =~ ^[0-9]+$ ]]; then
        echo "  Could not read the volume capacity. Nothing was changed."
        return 1
    fi
    local purgeable_before=$((imp_before - free_before))
    [ "$purgeable_before" -lt 0 ] && purgeable_before=0
    printf "  %-18s %s  (free %s, usable %s of %s)\n" "Purgeable now:" \
        "$(purge_fmt_bytes "$purgeable_before")" "$(purge_fmt_bytes "$free_before")" \
        "$(purge_fmt_bytes "$imp_before")" "$(purge_fmt_bytes "${total:-0}")"
    $apply || echo "  [PREVIEW — nothing is changed]"
    $apply || echo "  Note: Finder's \"Available\" already includes purgeable space and will not grow;"
    $apply || echo "        purge turns purgeable into truly free space."
    echo ""

    # 1. Local Time Machine snapshots (only for a full run, not for explicit paths)
    if [ ${#paths[@]} -eq 0 ]; then
        local snaps snap_count
        snaps=$(purge_snapshot_names)
        snap_count=$(printf '%s' "$snaps" | grep -c . || true)
        printf "  %-18s %s\n" "Local snapshots:" "$snap_count"
        [ -n "$snaps" ] && printf '%s\n' "$snaps" | head -10 | sed 's/^/    /'
        if $apply && [ "$snap_count" -gt 0 ]; then
            tmutil thinlocalsnapshots / 999999999999999 4 >/dev/null 2>&1 || true
            local snap_after
            snap_after=$(purge_snapshot_names | grep -c . || true)
            echo "  Snapshots: $snap_count before, $snap_after after"
        fi
        echo ""
        while IFS= read -r arg; do paths+=("$arg"); done < <(purge_icloud_roots)
    fi

    if [ ${#paths[@]} -eq 0 ]; then
        echo "  iCloud Drive is not set up on this Mac — no iCloud copies to remove."
    else
        local mode=check result ok bytes failed total_ok=0 total_bytes=0 total_failed=0 p
        $apply && mode=evict
        echo "  iCloud files unchanged in the last $days days, at least ${min_mb} MB:"
        for p in "${paths[@]}"; do
            result=$(purge_candidates "$p" "$days" "$min_mb" | purge_js_scan "$mode" "$p")
            ok=$(_purge_field "$result" ok); bytes=$(_purge_field "$result" bytes); failed=$(_purge_field "$result" failed)
            if ! [[ "${ok:-}" =~ ^[0-9]+$ ]]; then
                echo "    $p: could not be checked"
                continue
            fi
            total_ok=$((total_ok + ok)); total_bytes=$((total_bytes + ${bytes:-0})); total_failed=$((total_failed + ${failed:-0}))
            if $apply; then
                echo "    $p: evicted $ok files ($(purge_fmt_bytes "${bytes:-0}")), ${failed:-0} failed"
            else
                echo "    $p: $(purge_fmt_bytes "${bytes:-0}") in $ok files"
            fi
        done
        if $apply; then
            echo "  Evicted total: $(purge_fmt_bytes "$total_bytes") in $total_ok files, $total_failed failed"
        else
            echo "  Evictable total: $(purge_fmt_bytes "$total_bytes") in $total_ok files"
        fi
        echo "  Files stay in iCloud and in Finder; opening one downloads it again."
    fi
    echo ""

    if ! $apply; then
        echo "  Apply with: ${PURGE_CMD:-meister} purge --do"
        return 0
    fi

    local imp_after free_after freed purgeable_after
    read -r imp_after free_after _ <<< "$(purge_volume)"
    if [[ "${free_after:-}" =~ ^[0-9]+$ && "${imp_after:-}" =~ ^[0-9]+$ ]]; then
        freed=$((free_after - free_before))
        purgeable_after=$((imp_after - free_after)); [ "$purgeable_after" -lt 0 ] && purgeable_after=0
        if [ "$freed" -gt 0 ]; then
            echo "  Freed: $(purge_fmt_bytes "$freed") (measured free space)"
        else
            echo "  Free space has not grown yet — macOS can release it with a delay."
        fi
        printf "  %-18s %s\n" "Purgeable after:" "$(purge_fmt_bytes "$purgeable_after")"
        echo ""
        echo "  Finder's \"Available\" stays the same: it already counted purgeable space."
        echo "  The space moved from purgeable to free. Reopen Get Info (Cmd+I) to see it."
    else
        echo "  Could not re-measure the volume."
    fi
    return 0
}
