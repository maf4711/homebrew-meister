# shellcheck shell=bash
# lib/commands/sysdata.sh — `meister sysdata`: measure and slim macOS "System Data".
#
# Storage settings lump local Time Machine snapshots, caches, VM disks, LLM
# models and Xcode/Simulator data into one opaque "System Data" bar. sysdata
# measures each contributor (du -x, so mounted simulator runtimes are not
# counted twice; runtime images come from `simctl runtime list -j`), then:
#   (no flags)      read-only report, largest first, with review candidates
#   --do            safe steps only: thin local snapshots, Xcode DerivedData,
#                   unavailable simulators, uv/npm caches, docker prune
#                   (never volumes) + fstrim so Colima returns space to macOS
#   --do --review   additionally asks per item (default no, terminal only):
#                   ollama models, older simulator runtimes, LM Studio /
#                   Hugging Face / exo models, Xcode device support
# Bash 3.2 compatible.

SYSDATA_SYS_SIM="${SYSDATA_SYS_SIM:-/Library/Developer/CoreSimulator}"
SYSDATA_VM="${SYSDATA_VM:-/private/var/vm}"
SYSDATA_REVIEW_MIN_MB="${SYSDATA_REVIEW_MIN_MB:-500}"

sysdata_fmt() {
    awk -v b="${1:-0}" 'BEGIN {
        if (b >= 1e12)      printf "%.2f TB", b / 1e12
        else if (b >= 1e9)  printf "%.1f GB", b / 1e9
        else if (b >= 1e6)  printf "%.1f MB", b / 1e6
        else if (b >= 1e3)  printf "%.1f KB", b / 1e3
        else                printf "%d B", b
    }'
}

sysdata_volume() {
    if [ -n "${SYSDATA_VOLUME:-}" ]; then echo "$SYSDATA_VOLUME"
    elif [ -d /System/Volumes/Data ]; then echo /System/Volumes/Data
    else echo /; fi
}

# Prints "<used-bytes> <free-bytes>" of the data volume.
sysdata_df() {
    df -k "$(sysdata_volume)" 2>/dev/null | awk 'NR==2 {printf "%.0f %.0f\n", $3*1024, $4*1024}'
}

sysdata_progress() {
    local on="${SYSDATA_PROGRESS:-}"
    [ -z "$on" ] && { [ -t 2 ] && on=1 || on=0; }
    [ "$on" = 1 ] && printf '\r\033[K  measuring %s ...' "$1" >&2
    return 0
}

# Bytes on this filesystem only (-x): APFS mounts such as simulator runtimes are skipped.
sysdata_bytes() {
    [ -e "$1" ] || { echo 0; return 0; }
    du -skx "$1" 2>/dev/null | awk 'END {printf "%.0f\n", ($1+0)*1024}'
}

# group|label|path|parent-index (the parent's size excludes this child)
sysdata_items() {
    local ollama="${OLLAMA_MODELS:-$HOME/.ollama}"
    cat <<EOF
Xcode|Xcode DerivedData|$HOME/Library/Developer/Xcode/DerivedData|1
Xcode|Xcode device support, archives|$HOME/Library/Developer/Xcode|
Simulator|Simulator devices|$HOME/Library/Developer/CoreSimulator|
Simulator|Simulator system caches|$SYSDATA_SYS_SIM|
Docker|Colima VM disks|$HOME/.colima|
Docker|OrbStack|$HOME/.orbstack|
Docker|Docker Desktop|$HOME/Library/Containers/com.docker.docker|17
LLM models|ollama|$ollama|
LLM models|LM Studio|$HOME/.lmstudio|
LLM models|Hugging Face|$HOME/.cache/huggingface|
LLM models|exo|$HOME/.exo|
LLM models|exo cache|$HOME/.cache/exo|
LLM models|Whisper|$HOME/.cache/whisper|
Caches|uv cache|$HOME/.cache/uv|
Caches|npm cache|$HOME/.npm|
Caches|User caches|$HOME/Library/Caches|
App data|iOS device backups|$HOME/Library/Application Support/MobileSync|18
App data|App containers|$HOME/Library/Containers|
App data|Application Support|$HOME/Library/Application Support|
App data|Group containers|$HOME/Library/Group Containers|
System|Swap and sleep image|$SYSDATA_VM|
System|Logs|$HOME/Library/Logs|
EOF
}

# bytes<TAB>group<TAB>label<TAB>path, largest first; nested children are subtracted from parents.
sysdata_measure() {
    local groups=() labels=() paths=() parents=() sizes=() g l p par i=0
    while IFS='|' read -r g l p par; do
        groups[i]="$g"; labels[i]="$l"; paths[i]="$p"; parents[i]="$par"
        sysdata_progress "$l"
        sizes[i]=$(sysdata_bytes "$p")
        i=$((i + 1))
    done < <(sysdata_items)
    for ((i = 0; i < ${#labels[@]}; i++)); do
        par="${parents[i]}"
        if [ -n "$par" ] && [ "${sizes[i]}" -gt 0 ]; then
            sizes[par]=$((sizes[par] - sizes[i]))
            [ "${sizes[par]}" -lt 0 ] && sizes[par]=0
        fi
    done
    local rt
    rt=$(sysdata_runtimes | awk -F'\t' '{s += $4} END {printf "%.0f", s}')
    [ "${SYSDATA_PROGRESS:-}" = 1 ] || [ -t 2 ] && printf '\r\033[K' >&2
    {
        for ((i = 0; i < ${#labels[@]}; i++)); do
            [ "${sizes[i]}" -gt 0 ] && printf '%s\t%s\t%s\t%s\n' "${sizes[i]}" "${groups[i]}" "${labels[i]}" "${paths[i]}"
        done
        [ "${rt:-0}" -gt 0 ] && printf '%s\t%s\t%s\t%s\n' "$rt" Simulator "Simulator runtimes" "xcrun simctl runtime list"
    } | sort -t$'\t' -k1,1nr
}

# id<TAB>platform<TAB>version<TAB>bytes<TAB>last-used<TAB>candidate(1 = older runtime of its platform)
sysdata_runtimes() {
    command -v xcrun >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || return 0
    xcrun simctl runtime list -j 2>/dev/null | python3 -I -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
rts = list(data.values()) if isinstance(data, dict) else []
def key(r):
    return tuple(int(x) if x.isdigit() else 0 for x in str(r.get("version", "0")).split("."))
newest = {}
for r in rts:
    p = r.get("platformIdentifier", "")
    if p not in newest or key(r) > key(newest[p]):
        newest[p] = r
for r in rts:
    p = r.get("platformIdentifier", "")
    cand = 1 if r.get("deletable") and r is not newest[p] else 0
    name = p.split(".")[-1].replace("simulator", "")
    print("\t".join([r.get("identifier", ""), name, str(r.get("version", "")),
                     str(int(r.get("sizeBytes") or 0)), str(r.get("lastUsedAt", "never"))[:10], str(cand)]))
' 2>/dev/null
}

sysdata_snapshot_names() {
    tmutil listlocalsnapshots / 2>/dev/null | grep -E '^com\.apple\.TimeMachine\.' || true
}

# GB/MB/KB text from `ollama list` -> bytes (decimal, as ollama prints it)
_sysdata_unit_bytes() {
    awk -v n="$1" -v u="$2" 'BEGIN {
        m = (u=="TB") ? 1e12 : (u=="GB") ? 1e9 : (u=="MB") ? 1e6 : (u=="KB") ? 1e3 : 1
        printf "%.0f", n * m
    }'
}

# kind<TAB>bytes<TAB>target<TAB>label<TAB>note — things a human must decide on.
sysdata_review_items() {
    local name id num unit rest seen="" note line
    if command -v ollama >/dev/null 2>&1; then
        while read -r name id num unit rest; do
            [ -z "$name" ] || [ "$name" = NAME ] && continue
            note="modified $rest"
            line=$(printf '%s\n' "$seen" | awk -v i="$id" -F'=' '$1==i {print $2; exit}')
            if [ -n "$line" ]; then note="shares data with $line — removing frees space only with all its tags"
            else seen=$(printf '%s\n%s=%s' "$seen" "$id" "$name"); fi
            printf 'ollama\t%s\t%s\tollama %s\t%s\n' "$(_sysdata_unit_bytes "$num" "$unit")" "$name" "$name" "$note"
        done < <(ollama list 2>/dev/null)
    fi
    local rid plat ver bytes used cand
    while IFS=$'\t' read -r rid plat ver bytes used cand; do
        [ "$cand" = 1 ] || continue
        printf 'runtime\t%s\t%s\t%s simulator %s\tlast used %s; newer %s runtime stays\n' "$bytes" "$rid" "$plat" "$ver" "$used" "$plat"
    done < <(sysdata_runtimes)
    local min=$((SYSDATA_REVIEW_MIN_MB * 1000000)) d b
    for d in "$HOME"/.lmstudio/models/*/* "$HOME"/.cache/huggingface/hub/models--* \
             "$HOME"/.exo/downloads/* "$HOME"/.cache/exo/downloads/* \
             "$HOME"/Library/Developer/Xcode/*DeviceSupport/*; do
        [ -d "$d" ] || continue
        b=$(sysdata_bytes "$d")
        [ "$b" -ge "$min" ] || continue
        printf 'dir\t%s\t%s\t%s\tmodified %s\n' "$b" "$d" "${d#"$HOME"/}" "$(date -r "$d" +%Y-%m-%d 2>/dev/null || echo '?')"
    done
}

_sysdata_review_cmd() { # kind target
    case "$1" in
        ollama)  printf 'ollama rm %s' "$2" ;;
        runtime) printf 'xcrun simctl runtime delete %s' "$2" ;;
        dir)     printf "rm -rf '%s'" "$2" ;;
    esac
}

_sysdata_review_apply() { # kind target
    case "$1" in
        ollama)  ollama rm "$2" ;;
        runtime) xcrun simctl runtime delete "$2" ;;
        dir)     rm -rf "$2" ;;
    esac
}

sysdata_is_tty() { [ "${SYSDATA_ASSUME_TTY:-}" = 1 ] || [ -t 0 ]; }

# Destructive, so unlike meister_confirm the default is NO and there is no unattended yes.
sysdata_ask() {
    local reply=""
    printf '  %s [y/N] ' "$1"
    read -r reply || true
    case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# Each safe step: label, then the command. Prints what ran.
sysdata_safe_steps() {
    local before after dd="$HOME/Library/Developer/Xcode/DerivedData"
    before=$(sysdata_snapshot_names | grep -c . || true)
    if [ "$before" -gt 0 ]; then
        tmutil thinlocalsnapshots / 999999999999999 4 >/dev/null 2>&1 || true
        after=$(sysdata_snapshot_names | grep -c . || true)
        echo "  Snapshots: $before before, $after after"
    fi
    if [ -d "$dd" ]; then
        find "$dd" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
        echo "  Xcode DerivedData emptied (rebuilt on the next build)"
    fi
    if command -v xcrun >/dev/null 2>&1; then
        xcrun simctl delete unavailable >/dev/null 2>&1 && echo "  Unavailable simulators deleted"
    fi
    if command -v uv >/dev/null 2>&1 && [ -d "$HOME/.cache/uv" ]; then
        uv cache prune >/dev/null 2>&1 && echo "  uv cache pruned (unused entries)"
    fi
    if command -v npm >/dev/null 2>&1 && [ -d "$HOME/.npm" ]; then
        npm cache clean --force >/dev/null 2>&1 && echo "  npm cache cleaned"
    fi
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        # no -a and no --volumes: tagged images and database volumes stay
        local out
        out=$(docker system prune -f 2>/dev/null | tail -1)
        echo "  Docker: stopped containers, dangling images, build cache pruned${out:+ ($out)}"
        if command -v colima >/dev/null 2>&1 && colima status >/dev/null 2>&1; then
            colima ssh -- sudo fstrim -a >/dev/null 2>&1 &&
                echo "  Colima: fstrim returned freed VM blocks to macOS"
        fi
    fi
    return 0
}

_sysdata_usage() {
    echo "  Usage: ${SYSDATA_CMD:-meister} sysdata [--do] [--review]"
    cat <<'USAGE'
    (no flags)  Measure System Data: snapshots, Xcode/Simulator, Docker/Colima,
                LLM models (ollama, LM Studio, Hugging Face, exo), caches
    --do        Safe steps: thin local snapshots, DerivedData, unavailable
                simulators, uv/npm cache, docker prune (no volumes) + fstrim
    --review    With --do: ask per model/runtime/folder whether to delete it
                (default no; needs a terminal)
USAGE
}

cmd_sysdata() {
    local apply=false review=false arg
    while [ $# -gt 0 ]; do
        arg="$1"
        case "$arg" in
            --do) apply=true ;;
            -n|--dry-run) apply=false ;;
            --review) review=true ;;
            -h|--help) _sysdata_usage; return 0 ;;
            *) echo "  Unknown option: $arg"; _sysdata_usage; return 64 ;;
        esac
        shift
    done

    local used free_before
    read -r used free_before <<< "$(sysdata_df)"
    printf "  Data volume: %s used, %s free\n" "$(sysdata_fmt "${used:-0}")" "$(sysdata_fmt "${free_before:-0}")"
    $apply || echo "  [PREVIEW — nothing is changed]"
    echo ""

    local rows total max b g l p bar
    rows=$(sysdata_measure)
    total=$(printf '%s\n' "$rows" | awk -F'\t' '{s += $1} END {printf "%.0f", s}')
    max=$(printf '%s\n' "$rows" | awk -F'\t' 'NR==1 {print $1+0}')
    [ "${max:-0}" -gt 0 ] || max=1
    printf "  %10s  %-11s %-32s\n" SIZE GROUP ITEM
    while IFS=$'\t' read -r b g l p; do
        [ -n "$b" ] || continue
        bar=$(awk -v b="$b" -v m="$max" 'BEGIN {n = int(b * 20 / m); if (n < 1) n = 1; s = ""; for (i = 0; i < n; i++) s = s "#"; print s}')
        printf "  %10s  %-11s %-32s %s\n" "$(sysdata_fmt "$b")" "$g" "$l" "$bar"
    done <<< "$rows"
    echo ""
    printf "  Measured: %s" "$(sysdata_fmt "$total")"
    [ "${used:-0}" -gt 0 ] && printf " of %s used (rest: apps, documents, media, macOS)" "$(sysdata_fmt "$used")"
    echo ""

    local snaps snap_count
    snaps=$(sysdata_snapshot_names)
    snap_count=$(printf '%s' "$snaps" | grep -c . || true)
    printf "  Local Time Machine snapshots: %s" "$snap_count"
    [ "$snap_count" -gt 0 ] && printf " (size not reported by APFS; counted as purgeable, see '%s purge')" "${SYSDATA_CMD:-meister}"
    echo ""
    echo ""

    local items=() line
    while IFS= read -r line; do [ -n "$line" ] && items+=("$line"); done < <(sysdata_review_items | sort -t$'\t' -k2,2nr)

    if ! $apply; then
        echo "  Safe with --do: thin snapshots, DerivedData, unavailable simulators,"
        echo "                  uv/npm cache, docker prune (no volumes) + Colima fstrim"
        if [ ${#items[@]} -gt 0 ]; then
            echo ""
            echo "  Review with --do --review (asks per item, default no):"
            local kind ib target label note
            for line in "${items[@]}"; do
                IFS=$'\t' read -r kind ib target label note <<< "$line"
                printf "  %10s  %-40s %s\n" "$(sysdata_fmt "$ib")" "$label" "$note"
                printf "  %10s  → %s\n" "" "$(_sysdata_review_cmd "$kind" "$target")"
            done
        fi
        echo ""
        echo "  Apply with: ${SYSDATA_CMD:-meister} sysdata --do [--review]"
        return 0
    fi

    sysdata_safe_steps

    if $review && [ ${#items[@]} -gt 0 ]; then
        echo ""
        if ! sysdata_is_tty; then
            echo "  --review needs a terminal — no models, runtimes or folders were removed."
        else
            local kind ib target label note
            for line in "${items[@]}"; do
                IFS=$'\t' read -r kind ib target label note <<< "$line"
                if sysdata_ask "Delete $label ($(sysdata_fmt "$ib"); $note)?"; then
                    if _sysdata_review_apply "$kind" "$target" >/dev/null 2>&1; then
                        echo "    deleted: $label"
                    else
                        echo "    FAILED: $(_sysdata_review_cmd "$kind" "$target")"
                    fi
                else
                    echo "    kept: $label"
                fi
            done
        fi
    fi

    local free_after
    read -r _ free_after <<< "$(sysdata_df)"
    echo ""
    if [ -n "${free_after:-}" ]; then
        printf "  Free space: %s before, %s after" "$(sysdata_fmt "${free_before:-0}")" "$(sysdata_fmt "$free_after")"
        [ "$free_after" -gt "${free_before:-0}" ] && printf " (+%s)" "$(sysdata_fmt $((free_after - free_before)))"
        echo ""
        echo "  macOS can take a few minutes to return thinned snapshot space."
    fi
    return 0
}
