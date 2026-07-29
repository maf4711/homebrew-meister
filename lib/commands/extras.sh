# shellcheck shell=bash
# lib/commands/extras.sh — P2/P3 subcommands as functions
# Called from meisterSiri.sh early-exit handlers. Expects MEISTER_DIR, colors optional.

# --- report history --diff (last two runs) ---
cmd_report_diff() {
    local hist="${MEISTER_DIR}/history.log"
    [ -f "$hist" ] || { echo "  No history yet ($hist)"; return 0; }
    local n
    n=$(wc -l < "$hist" | tr -d ' ')
    if [ "${n:-0}" -lt 2 ]; then
        echo "  Need at least 2 runs for --diff (have ${n:-0})"
        return 0
    fi
    local prev curr
    prev=$(tail -2 "$hist" | head -1)
    curr=$(tail -1 "$hist")
    echo "  Previous: $prev"
    echo "  Current:  $curr"
    echo ""
    _parse_hist_field() {
        local line="$1" key="$2"
        echo "$line" | grep -oE "${key}:[0-9]+" | head -1 | cut -d: -f2
    }
    local keys=(OK FIX WARN ERR HEAL SCORE)
    local k a b da
    printf "  %-8s %8s %8s %8s\n" "Field" "Prev" "Curr" "Δ"
    for k in "${keys[@]}"; do
        a=$(_parse_hist_field "$prev" "$k"); a=${a:-0}
        b=$(_parse_hist_field "$curr" "$k"); b=${b:-0}
        da=$((b - a))
        printf "  %-8s %8s %8s %+8d\n" "$k" "$a" "$b" "$da"
    done
    echo ""
    # Top modules field if present
    local top_prev top_curr
    top_prev=$(echo "$prev" | sed -n 's/.*top: //p')
    top_curr=$(echo "$curr" | sed -n 's/.*top: //p')
    [ -n "$top_prev" ] && echo "  Slowest prev: $top_prev"
    [ -n "$top_curr" ] && echo "  Slowest curr: $top_curr"
}

# --- why: explain module / warn / profile ---
cmd_why() {
    local q="${1:-}"
    if [ -z "$q" ]; then
        echo "Usage: meisterSiri why <module|warn-text|profile>"
        echo "  meisterSiri why Homebrew"
        echo "  meisterSiri why profile"
        echo "  meisterSiri why \"broken symlink\""
        return 1
    fi
    if [ "$q" = "profile" ] || [ "$q" = "profiles" ]; then
        echo "  Current RUN_PROFILE=${RUN_PROFILE:-auto}"
        echo "  AI_HEAL_EXECUTE=${AI_HEAL_EXECUTE:-false}"
        echo "  Quick whitelist: $PROFILE_QUICK_MODULES"
        echo ""
        echo "  Sample membership (current profile):"
        local m
        for m in Healer Homebrew Cleanup "Deep Clean" "iCloud Fix" Benchmark "Git repos" ".DS_Store"; do
            if module_in_profile "$m" 2>/dev/null; then
                echo "    ✓ $m"
            else
                echo "    · $m (skipped)"
            fi
        done
        return 0
    fi
    # Module membership
    if module_in_profile "$q" 2>/dev/null; then
        echo "  Module \"$q\": RUNS under profile=${RUN_PROFILE:-auto}"
    else
        echo "  Module \"$q\": SKIPPED under profile=${RUN_PROFILE:-auto}"
        case "${RUN_PROFILE:-auto}" in
            quick) echo "  Hint: only lean daily modules run in --quick; try --deep or -a" ;;
            auto)  echo "  Hint: may need a config gate (e.g. ICLOUD_FIX_ENABLED=true) or --deep" ;;
        esac
    fi
    # Config-related hints
    case "$q" in
        *Git*|git*)
            echo "  Git: GIT_AUTO_PUSH=${GIT_AUTO_PUSH:-false} RUN_GIT_REPOS=${RUN_GIT_REPOS:-false}"
            echo "  Per-repo opt-out: .meister-nopush or git config meister.nopush true"
            echo "  Policy: report-only in --quick; push only if GIT_AUTO_PUSH=true"
            ;;
        *Heal*|AI*|ai*)
            echo "  AI_HEAL_EXECUTE=${AI_HEAL_EXECUTE:-false} (false = suggest-only)"
            echo "  Opt-in: --ai-heal-execute or AI_HEAL_EXECUTE=true in config"
            ;;
        *iCloud*)
            echo "  ICLOUD_FIX_ENABLED=${ICLOUD_FIX_ENABLED:-false}"
            ;;
    esac
    # Search recent log for matching WARN/ERROR
    if [ -f "${LOGFILE:-$MEISTER_DIR/meister.log}" ]; then
        echo ""
        echo "  Recent log lines matching \"$q\":"
        grep -i "$q" "${LOGFILE:-$MEISTER_DIR/meister.log}" 2>/dev/null | tail -5 | sed 's/^/    /' \
            || echo "    (none)"
    fi
    # Last run score context
    if [ -f "$MEISTER_DIR/history.log" ]; then
        echo ""
        echo "  Last run: $(tail -1 "$MEISTER_DIR/history.log")"
    fi
}

# --- doctor --json ---
cmd_doctor_json() {
    local score fv fw sip disk host ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    host=$(scutil --get LocalHostName 2>/dev/null || echo unknown)
    score=$(grep -oE 'SCORE:[0-9]+' "$MEISTER_DIR/history.log" 2>/dev/null | tail -1 | cut -d: -f2)
    fv=$(fdesetup status 2>/dev/null | grep -q On && echo true || echo false)
    fw=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q enabled && echo true || echo false)
    sip=$(csrutil status 2>/dev/null | grep -q disabled && echo false || echo true)
    disk=$(df -P / | awk 'NR==2{gsub(/%/,"",$5); print $5}')
    local ai=false
    command -v fm_available >/dev/null 2>&1 && fm_available 2>/dev/null && ai=true
    cat <<EOF
{
  "schema": "meister.doctor/v1",
  "ts": "$ts",
  "host": "$host",
  "score": ${score:-null},
  "filevault": $fv,
  "firewall": $fw,
  "sip": $sip,
  "disk_used_pct": ${disk:-null},
  "ai_available": $ai,
  "ai_heal_execute": ${AI_HEAL_EXECUTE:-false},
  "profile_default": "${RUN_PROFILE:-auto}",
  "last_json": "$MEISTER_DIR/last.json"
}
EOF
}

# --- report --json (last N history lines as JSON array) ---
cmd_report_json() {
    local n="${1:-10}" hist="$MEISTER_DIR/history.log"
    if [ ! -f "$hist" ]; then
        echo '[]'
        return 0
    fi
    tail -n "$n" "$hist" | awk -F' \\| ' '
    BEGIN { print "[" }
    {
        date=$1; gsub(/^ +| +$/,"",date)
        dur=$2; gsub(/^ +| +$/,"",dur)
        ok=fix=warn=err=heal=0; score="null"
        n=split($3, a, " ")
        for (i=1; i<=n; i++) {
            split(a[i], kv, ":")
            if (kv[1]=="OK") ok=kv[2]+0
            else if (kv[1]=="FIX") fix=kv[2]+0
            else if (kv[1]=="WARN") warn=kv[2]+0
            else if (kv[1]=="ERR") err=kv[2]+0
            else if (kv[1]=="HEAL") heal=kv[2]+0
            else if (kv[1]=="SCORE") score=kv[2]+0
        }
        if (NR>1) printf ",\n"
        printf "{\"date\":\"%s\",\"duration\":\"%s\",\"ok\":%d,\"fix\":%d,\"warn\":%d,\"err\":%d,\"heal\":%d,\"score\":%s}", \
            date, dur, ok, fix, warn, err, heal, score
    }
    END { print "\n]" }
    '
}

# --- storage: safe-to-delete candidates with sizes ---
cmd_storage() {
    echo "  Scanning safe-to-delete candidates (read-only)..."
    echo ""
    printf "  %-12s %10s  %s\n" "MB" "Path" "Note"
    printf '  '; printf '─%.0s' $(seq 1 60); echo ""
    _row() {
        local path="$1" note="$2"
        [ -e "$path" ] || return 0
        local mb
        mb=$(du -sm "$path" 2>/dev/null | awk '{print $1}')
        [ "${mb:-0}" -gt 0 ] || return 0
        printf "  %-12s %10s  %s\n" "$mb" "$path" "$note"
    }
    _row "$HOME/Library/Developer/Xcode/DerivedData" "Xcode DerivedData — meister -X"
    _row "$HOME/Library/Developer/CoreSimulator" "iOS Simulators — meisterSiri simfix"
    _row "$HOME/Library/Caches" "User caches — meister -C"
    _row "$HOME/.Trash" "Trash — meister -T"
    _row "$HOME/Library/Logs" "User logs — deep clean"
    if command -v docker >/dev/null 2>&1; then
        local dmb
        dmb=$(docker system df --format '{{.Size}}' 2>/dev/null | head -1)
        echo "  (docker)     ${dmb:-?}  docker system df — CLEAN_DOCKER / --deep"
    fi
    # npm / cargo rough
    _row "$HOME/.npm" "npm cache — meister deep Dev Caches"
    _row "$HOME/go/pkg/mod" "Go module cache"
    _row "$HOME/.cargo/registry" "Cargo registry"
    echo ""
    echo "  Apply safely: meisterSiri --deep -n   # dry-run first"
    echo "                meisterSiri -X -C -T    # targeted"
}

# --- contacts doctor: AddressBook bloat / risk (read-only) ---
cmd_contacts_doctor() {
    local ab="$HOME/Library/Application Support/AddressBook"
    echo "  AddressBook health (read-only — no delete)"
    echo ""
    if [ ! -d "$ab" ]; then
        echo "  No AddressBook directory at:"
        echo "    $ab"
        return 0
    fi
    local total_mb sources_mb ext_mb
    total_mb=$(du -sm "$ab" 2>/dev/null | awk '{print $1}')
    echo "  Total size:     ${total_mb:-?} MB"
    if [ -d "$ab/Sources" ]; then
        sources_mb=$(du -sm "$ab/Sources" 2>/dev/null | awk '{print $1}')
        echo "  Sources/:       ${sources_mb:-?} MB"
        # Per-source sizes (top 5)
        echo "  Top sources:"
        du -sm "$ab/Sources"/* 2>/dev/null | sort -rn | head -5 | while read -r mb path; do
            printf "    %6s MB  %s\n" "$mb" "$(basename "$path")"
        done
    fi
    local ext_count
    ext_count=$(find "$ab" -type d -name '_EXTERNAL_DATA' 2>/dev/null | wc -l | tr -d ' ')
    if [ "${ext_count:-0}" -gt 0 ]; then
        ext_mb=$(find "$ab" -type d -name '_EXTERNAL_DATA' -exec du -sm {} + 2>/dev/null | awk '{s+=$1} END{print s+0}')
        echo "  _EXTERNAL_DATA: ${ext_mb:-?} MB across ${ext_count} dir(s) (photos / orphans risk)"
    fi
    # Changelog bloat
    local cl
    for cl in "$ab"/ABAssistantChangelog* "$ab"/Sources/*/ABAssistantChangelog*; do
        [ -e "$cl" ] || continue
        local cmb
        cmb=$(du -sm "$cl" 2>/dev/null | awk '{print $1}')
        [ "${cmb:-0}" -gt 50 ] && echo "  WARN changelog: ${cmb} MB  $cl"
    done
    # Risk bands
    echo ""
    if [ "${total_mb:-0}" -gt 1500 ]; then
        echo "  RISK: CRITICAL (>1.5 GB) — export vCard, disable iCloud Contacts, rebuild source"
        echo "  See: meister-app/docs/contacts-troubleshooting.md (legacy playbook)"
    elif [ "${total_mb:-0}" -gt 500 ]; then
        echo "  RISK: HIGH (>500 MB) — watch for sync loops; export vCard backup soon"
    elif [ "${total_mb:-0}" -gt 200 ]; then
        echo "  RISK: ELEVATED (>200 MB) — normal with many photos; re-check monthly"
    else
        echo "  RISK: OK"
    fi
    echo ""
    echo "  Meister will NOT auto-delete contacts. Manual recipe only."
}

# --- git policy note for quick runs ---
cmd_git_policy_hint() {
    echo "  Git policy: GIT_AUTO_PUSH=${GIT_AUTO_PUSH:-false} (false = report dirty/unpushed only)"
    echo "  Enable push: GIT_AUTO_PUSH=true in ~/.meister/config + profile with Git repos"
}
