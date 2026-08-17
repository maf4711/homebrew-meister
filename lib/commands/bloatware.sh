# shellcheck shell=bash
# lib/commands/bloatware.sh — catalog scan + optional kill (quarantine).
# Source of truth for patterns: kill-bloatware skill catalog.
# Usage via twin: meisterSiri bloatware [scan|kill] [--p0|--p1] [--dry-run] [-y] [--json|--tsv]

: "${HOME_DIR:=${HOME:-/Users/$(id -un)}}"
: "${MEISTER_DIR:=$HOME_DIR/.meister}"
BLOAT_QUARANTINE_ROOT="${BLOAT_QUARANTINE_ROOT:-$MEISTER_DIR/bloatware-quarantine}"

# Patterns (case-insensitive). KEEP always wins.
BLOAT_P0_RE='cleanmymac|ccleaner|mackeeper|mac.?cleaner|advanced.?mac.?cleaner|dr\.?cleaner|disk.?doctor|adware.?doctor|search.?marquis|searchawesome|vsearch|genieo|installcore|bundlore|shlayer|avast|avghub|avasthub|mcafee|norton|trend.?micro'
BLOAT_P1_RE='google\.keystone|googleupdater|google\.googleupdater|microsoft\.autoupdate|microsoft-auto-update|ai\.perplexity|perplexity.*updater|dropbox|onedrive|spotify.*helper|zoomopener|us\.zoom\.updater|creative.?cloud|adobe.*updater|akamai'
BLOAT_KEEP_RE='com\.apple\.|com\.merados\.|com\.heald\.|com\.meister\.|com\.dev\.|homebrew\.|iterm|ghostty|claude|codex|collaborator|docker|lulu|little.?snitch|clamxav|malwarebytes|1password|bitwarden|github|goland|bbedit|xcode|raycast|signal|ledger|bitcoin|home-?assistant|aqara|eve|deco'

_bloat_severity_for() {
    local s="$1" low
    low="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
    # Optional local ignore file (substring match → KEEP)
    if [ -f "$HOME_DIR/.kill-bloatware-ignore" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [ -z "$line" ] && continue
            [[ "$line" == \#* ]] && continue
            if printf '%s' "$low" | grep -qiF "$line"; then
                echo "KEEP"
                return
            fi
        done < "$HOME_DIR/.kill-bloatware-ignore"
    fi
    if printf '%s' "$low" | grep -qiE "$BLOAT_KEEP_RE"; then
        echo "KEEP"
        return
    fi
    if printf '%s' "$low" | grep -qiE "$BLOAT_P0_RE"; then
        echo "P0"
        return
    fi
    if printf '%s' "$low" | grep -qiE "$BLOAT_P1_RE"; then
        echo "P1"
        return
    fi
    echo ""
}

_bloat_add() {
    # kind|severity|name|path|detail
    BLOAT_ROWS+=("$1|$2|$3|$4|$5")
}

_bloat_scan_apps() {
    local app name sev
    for app in /Applications/*.app "$HOME_DIR"/Applications/*.app; do
        [ -d "$app" ] || continue
        name="$(basename "$app" .app)"
        sev="$(_bloat_severity_for "$name")"
        [ -n "$sev" ] && [ "$sev" != "KEEP" ] || continue
        _bloat_add "app" "$sev" "$name" "$app" "Application bundle"
    done
}

_bloat_scan_agents() {
    local dir plist prog sev base
    for dir in "$HOME_DIR/Library/LaunchAgents" /Library/LaunchAgents; do
        [ -d "$dir" ] || continue
        for plist in "$dir"/*.plist; do
            [ -f "$plist" ] || continue
            base="$(basename "$plist")"
            [[ "$base" == *.disabled* ]] && continue
            sev="$(_bloat_severity_for "$base")"
            [ "$sev" = "KEEP" ] && continue
            prog=""
            if /usr/libexec/PlistBuddy -c 'Print :Program' "$plist" &>/dev/null; then
                prog="$(/usr/libexec/PlistBuddy -c 'Print :Program' "$plist" 2>/dev/null || true)"
            elif /usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$plist" &>/dev/null; then
                prog="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$plist" 2>/dev/null || true)"
            fi
            if [ -z "$sev" ] && [ -n "$prog" ]; then
                sev="$(_bloat_severity_for "$prog")"
                [ "$sev" = "KEEP" ] && continue
            fi
            if [ -n "$prog" ] && [[ "$prog" == /* ]] && [ ! -e "$prog" ]; then
                _bloat_add "launchagent" "P0" "$base" "$plist" "ORPHAN: missing binary: $prog"
                continue
            fi
            [ -n "$sev" ] && [ "$sev" != "KEEP" ] || continue
            _bloat_add "launchagent" "$sev" "$base" "$plist" "Program: ${prog:-unknown}"
        done
    done
}

_bloat_scan_brew() {
    command -v brew >/dev/null 2>&1 || return 0
    local cask sev
    while IFS= read -r cask; do
        [ -n "$cask" ] || continue
        sev="$(_bloat_severity_for "$cask")"
        [ -n "$sev" ] && [ "$sev" != "KEEP" ] || continue
        _bloat_add "brew-cask" "$sev" "$cask" "brew:cask:$cask" "Homebrew cask"
    done < <(brew list --cask 2>/dev/null || true)
}

_bloat_scan_support() {
    local d name sev size
    [ -d "$HOME_DIR/Library/Application Support" ] || return 0
    for d in "$HOME_DIR/Library/Application Support"/*; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        case "$name" in
            AddressBook|Apple*|CallHistory*|CloudDocs|CrashReporter|Dock|FaceTime|FileProvider|Knowledge|Microsoft|MobileSync|SyncServices|com.apple*|Caches|networkserviceproxy|iCloud*|ControlCenter|DifferentialPrivacy)
                continue
                ;;
        esac
        sev="$(_bloat_severity_for "$name")"
        [ -n "$sev" ] && [ "$sev" != "KEEP" ] || continue
        if ls /Applications/*"$name"* 2>/dev/null | head -1 | grep -q .; then
            continue
        fi
        size="$(du -sh "$d" 2>/dev/null | awk '{print $1}')"
        _bloat_add "support-dir" "$sev" "$name" "$d" "Leftover Application Support ($size)"
    done
}

_bloat_scan_login() {
    local items item sev
    items="$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || true)"
    [ -n "$items" ] || return 0
    local IFS=','
    # shellcheck disable=SC2086
    set -- $items
    for item in "$@"; do
        item="$(echo "$item" | sed 's/^ *//;s/ *$//')"
        [ -n "$item" ] || continue
        sev="$(_bloat_severity_for "$item")"
        [ -n "$sev" ] && [ "$sev" != "KEEP" ] || continue
        _bloat_add "login-item" "$sev" "$item" "login-item:$item" "Login item"
    done
}

_bloat_collect() {
    BLOAT_ROWS=()
    _bloat_scan_apps
    _bloat_scan_agents
    _bloat_scan_brew
    _bloat_scan_support
    _bloat_scan_login

    # Dedupe kind+name (bash 3.2 — no associative arrays), sort P0→P1→P2
    local unique=() r key sev seen_blob="|"
    for r in "${BLOAT_ROWS[@]+"${BLOAT_ROWS[@]}"}"; do
        key="$(printf '%s' "$r" | cut -d'|' -f1-3)"
        case "$seen_blob" in
            *"|$key|"*) continue ;;
        esac
        seen_blob="${seen_blob}${key}|"
        unique+=("$r")
    done
    BLOAT_SORTED=()
    for sev in P0 P1 P2; do
        for r in "${unique[@]+"${unique[@]}"}"; do
            [ "$(printf '%s' "$r" | cut -d'|' -f2)" = "$sev" ] && BLOAT_SORTED+=("$r")
        done
    done
}

_bloat_print_human() {
    local p0=0 p1=0 p2=0 r kind sev name path detail cur=""
    for r in "${BLOAT_SORTED[@]+"${BLOAT_SORTED[@]}"}"; do
        case "$(printf '%s' "$r" | cut -d'|' -f2)" in
            P0) p0=$((p0 + 1)) ;;
            P1) p1=$((p1 + 1)) ;;
            P2) p2=$((p2 + 1)) ;;
        esac
    done
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              meister bloatware SCAN                      ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║ Host: $(hostname -s)  User: $(whoami)"
    echo "║ Findings: P0=$p0  P1=$p1  P2=$p2  total=$((p0 + p1 + p2))"
    echo "║ Mode: READ-ONLY (use: bloatware kill --p0)"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo
    if [ "${#BLOAT_SORTED[@]}" -eq 0 ]; then
        echo "  No catalog-matched bloat found. Machine relatively clean."
        return 0
    fi
    for r in "${BLOAT_SORTED[@]}"; do
        IFS='|' read -r kind sev name path detail <<<"$r"
        if [ "$sev" != "$cur" ]; then
            cur="$sev"
            echo "── $sev ─────────────────────────────────────────────────"
        fi
        printf '  [%s] %-22s  %s\n' "$kind" "$name" "$detail"
        printf '         %s\n' "$path"
    done
    echo
    echo "  Kill P0 (quarantine): meisterSiri bloatware kill --p0"
    echo "  Dry-run:              meisterSiri bloatware kill --p0 --dry-run"
    echo "  Protected: Apple, meradOS, Homebrew, core dev tools."
    echo "  Quarantine: $BLOAT_QUARANTINE_ROOT/"
}

_bloat_print_tsv() {
    local r
    printf 'kind\tseverity\tname\tpath\tdetail\n'
    for r in "${BLOAT_SORTED[@]+"${BLOAT_SORTED[@]}"}"; do
        echo "$r" | tr '|' '\t'
    done
}

_bloat_print_json() {
    local r kind sev name path detail first=1
    echo '['
    for r in "${BLOAT_SORTED[@]+"${BLOAT_SORTED[@]}"}"; do
        IFS='|' read -r kind sev name path detail <<<"$r"
        [ $first -eq 1 ] || echo ','
        first=0
        printf '{"kind":"%s","severity":"%s","name":"%s","path":"%s","detail":"%s"}' \
            "${kind//\"/\\\"}" "${sev//\"/\\\"}" "${name//\"/\\\"}" \
            "${path//\"/\\\"}" "${detail//\"/\\\"}"
    done
    echo
    echo ']'
}

_bloat_quarantine_dir() {
    local day
    day="$(date +%Y%m%d)"
    mkdir -p "$BLOAT_QUARANTINE_ROOT/$day"
    printf '%s' "$BLOAT_QUARANTINE_ROOT/$day"
}

_bloat_kill_one() {
    # args: kind path name dry_run
    local kind="$1" path="$2" name="$3" dry="$4"
    local q uid
    uid="$(id -u)"
    q="$(_bloat_quarantine_dir)"

    case "$kind" in
        launchagent)
            if [ "$dry" = true ]; then
                echo "  [DRY] bootout+quarantine $path"
                return 0
            fi
            if [[ "$path" == "$HOME_DIR"/Library/LaunchAgents/* ]]; then
                launchctl bootout "gui/$uid" "$path" 2>/dev/null \
                    || launchctl unload "$path" 2>/dev/null || true
                mv "$path" "$q/" 2>/dev/null && echo "  ✓ quarantined agent $name" && return 0
            else
                echo "  ⚠ system LaunchAgent needs admin: $path (skipped)"
                return 1
            fi
            echo "  ✗ failed agent $name"
            return 1
            ;;
        app)
            if [ "$dry" = true ]; then
                echo "  [DRY] quarantine app $path"
                return 0
            fi
            if command -v trash >/dev/null 2>&1; then
                trash "$path" 2>/dev/null && echo "  ✓ trashed app $name" && return 0
            fi
            mkdir -p "$q/Apps"
            mv "$path" "$q/Apps/" 2>/dev/null && echo "  ✓ quarantined app $name" && return 0
            echo "  ✗ failed app $name (try: meisterSiri remove \"$name\")"
            return 1
            ;;
        brew-cask)
            if [ "$dry" = true ]; then
                echo "  [DRY] brew uninstall --cask $name"
                return 0
            fi
            if brew uninstall --cask "$name" 2>/dev/null; then
                echo "  ✓ brew uninstalled $name"
                return 0
            fi
            echo "  ⚠ brew uninstall failed for $name (may need admin leftovers)"
            return 1
            ;;
        support-dir)
            if [ "$dry" = true ]; then
                echo "  [DRY] quarantine support $path"
                return 0
            fi
            mkdir -p "$q/Support"
            mv "$path" "$q/Support/" 2>/dev/null && echo "  ✓ quarantined support $name" && return 0
            echo "  ✗ failed support $name"
            return 1
            ;;
        login-item)
            if [ "$dry" = true ]; then
                echo "  [DRY] delete login item $name"
                return 0
            fi
            if osascript -e "tell application \"System Events\" to delete login item \"$name\"" 2>/dev/null; then
                echo "  ✓ removed login item $name"
                return 0
            fi
            echo "  ✗ failed login item $name"
            return 1
            ;;
        *)
            echo "  ⚠ unknown kind $kind — skip"
            return 1
            ;;
    esac
}

# Main entry: cmd_bloatware [args...]
cmd_bloatware() {
    local mode="scan" format="human" kill_p0=false kill_p1=false dry=false yes=false
    local a
    for a in "$@"; do
        case "$a" in
            scan) mode="scan" ;;
            kill|remove) mode="kill" ;;
            --p0) kill_p0=true ;;
            --p1) kill_p1=true ;;
            --dry-run|-n) dry=true ;;
            -y|--yes) yes=true ;;
            --json) format="json" ;;
            --tsv) format="tsv" ;;
            --help|-h)
                cat <<'EOF'
Usage: meisterSiri bloatware [scan|kill] [flags]

  scan (default)   Read-only catalog scan (apps, LaunchAgents, brew, leftovers)
  kill             Quarantine approved severities (default needs --p0 and/or --p1)

Flags:
  --p0             Include P0 (confirmed junk / orphans)
  --p1             Include P1 (updaters / noise) — explicit only
  --dry-run, -n    Show actions, change nothing
  -y, --yes        Skip confirmation on kill
  --json / --tsv   Machine-readable scan output

Aliases: kill-bloat, bloat

Quarantine: ~/.meister/bloatware-quarantine/YYYYMMDD/
Rollback:   mv items back from quarantine
Ignore:     ~/.kill-bloatware-ignore (substring lines → KEEP)
EOF
                return 0
                ;;
            *)
                echo "Unknown flag: $a" >&2
                echo "Try: meisterSiri bloatware --help" >&2
                return 1
                ;;
        esac
    done

    # kill without severity → assume P0 only (safe default)
    if [ "$mode" = "kill" ] && [ "$kill_p0" = false ] && [ "$kill_p1" = false ]; then
        kill_p0=true
    fi

    _bloat_collect

    if [ "$mode" = "scan" ]; then
        case "$format" in
            json) _bloat_print_json ;;
            tsv)  _bloat_print_tsv ;;
            *)    _bloat_print_human ;;
        esac
        return 0
    fi

    # kill mode
    local targets=() r sev
    for r in "${BLOAT_SORTED[@]+"${BLOAT_SORTED[@]}"}"; do
        sev="$(printf '%s' "$r" | cut -d'|' -f2)"
        if [ "$sev" = "P0" ] && [ "$kill_p0" = true ]; then
            targets+=("$r")
        elif [ "$sev" = "P1" ] && [ "$kill_p1" = true ]; then
            targets+=("$r")
        fi
    done

    if [ "${#targets[@]}" -eq 0 ]; then
        echo "  Nothing to kill (no matching P0/P1 findings)."
        return 0
    fi

    echo "  Targets: ${#targets[@]} item(s) → quarantine (reversible)"
    [ "$dry" = true ] && echo "  [DRY-RUN — no changes]"
    echo
    local kind name path detail
    for r in "${targets[@]}"; do
        IFS='|' read -r kind sev name path detail <<<"$r"
        printf '  • [%s/%s] %s\n' "$sev" "$kind" "$name"
        printf '      %s\n' "$path"
    done
    echo

    if [ "$dry" = false ] && [ "$yes" = false ]; then
        local reply
        printf '  Quarantine these? [y/N] '
        read -r reply
        case "$reply" in
            [yY]|[yY][eE][sS]) ;;
            *) echo "  Aborted."; return 0 ;;
        esac
    fi

    local ok=0 fail=0
    for r in "${targets[@]}"; do
        IFS='|' read -r kind sev name path detail <<<"$r"
        if _bloat_kill_one "$kind" "$path" "$name" "$dry"; then
            ok=$((ok + 1))
        else
            fail=$((fail + 1))
        fi
    done
    echo
    echo "  Done: ok=$ok fail=$fail"
    [ "$dry" = false ] && echo "  Quarantine: $BLOAT_QUARANTINE_ROOT/"
    return 0
}
