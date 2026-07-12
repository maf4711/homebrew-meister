#!/bin/bash
# shellcheck disable=SC2155,SC2329
# ==============================================================================
# meister.sh
#
# Meister - macOS Maintenance, Update & Self-Healing
# Version: 5.26
# Date: 2026-07-12
#
# NEW in v5.26 — tcc-clean honesty:
#  - meister tcc-clean --do now reports the REAL sqlite3 error (was hidden
#    behind 2>/dev/null with a guessed "FDA?" message), runs a write-probe
#    up front, and gives an exact fix: run `sudo meister tcc-clean --do` in a
#    Full-Disk-Access terminal (it lists which terminals have FDA)
#  - dropped the tccutil path: tccutil reset REJECTS uninstalled bundle ids
#    (LSApplicationNotFound -10814), so it cannot remove orphans at all —
#    a direct sqlite3 DELETE from an FDA terminal is the only working method
#  - PRAGMA busy_timeout rides out a transient tccd lock on the db
#
# NEW in v5.25 — intelligence layer on top of the run:
#  - Maintenance score 0-100 in report + history (SCORE: field) with trend
#    arrow vs. previous run; `meister score` shows the sparkline history
#  - meister diff — time-travel: snapshots apps/autostart/brew/settings after
#    each run and shows what changed since last time (new autostart = flagged)
#  - meister undo [--do|--list] — reverts the last run's REVERSIBLE actions
#    from an undo journal (e.g. deleted orphan prefs restored from backup)
#  - meister explain <text> — Ollama explains a warning/log line in plain German
#    (no arg = explains the last WARN/ERROR from the log)
#  - meister fleet — aggregates score/status of several Macs over SSH
#    (FLEET_HOSTS in ~/.meister/config; read-only, key-based SSH)
#
# NEW in v5.24 — "ULTRA": absorb the best of the Mac-tool ecosystem
#  Output (topgrade-style):
#  - section separators: one line with timestamp ── HH:MM:SS · [n/N] Module ──
#  - end-of-run module ledger: ✓ ok / ↻ fixed / ⚠ warned / ✗ failed + duration
#  AI-Healer (emphasized):
#  - Learned-Fixes: AI fixes confirmed by a module retest are remembered
#    (~/.meister/learned_fixes) and tried before asking Ollama again
#  - iterative healing: 2nd AI round is told what round 1 tried
#  - meister ai: on-demand AI system diagnosis (read-only, local Ollama)
#  - report shows a dedicated ⚕ SELF-HEALING section
#  New module:
#  - Dev Updates (topgrade): npm -g, pipx, pip-report, rustup, cargo-update,
#    uv, gcloud, tldr, oh-my-zsh, conda (gated) — UNIVERSAL_UPDATES=false to off
#  New subcommands (tool absorption):
#  - meister pkg <f>   — Suspicious-Package-style installer inspector
#  - meister watch     — BlockBlock-style persistence watcher (WatchPaths agent)
#  - meister tweaks    — OnyX-style hidden settings toggles
#  - meister adopt     — Latest-style: bring unmanaged apps under brew (--adopt)
#  - meister dash      — Stats-style live terminal dashboard
#  - meister files     — Sloth-style lsof wrapper (port/process/file)
#  - meister win       — Rectangle-style window snapping via AppleScript
#  - meister clip      — Maccy-style clipboard history (chmod 600 + --purge)
#  - meister keys      — Karabiner-light: caps2esc/caps2ctrl via hidutil
#  - meister tcc-clean — remove privacy grants (FDA/Accessibility/...) whose
#    app/binary no longer exists (deleted apps stay in System Settings forever)
#  - meister appupdates — MacUpdater-style unified update check: brew casks +
#    Mac App Store + Sparkle appcast scan (SUFeedURL) per app
#  Security:
#  - Persistence-Audit prints SHA256 + VirusTotal link per suspicious binary
#
# NEW in v5.23 (feature release):
#  - meister touchid [--off]: enable Touch ID for sudo via /etc/pam.d/sudo_local
#    (survives macOS updates; falls back to password without a sensor)
#  - meister backup [--now]: Time Machine status; interactive destination setup
#    when none is configured (lists attached APFS/HFS volumes)
#  - meister report [N]: run-history table from history.log with per-run counts,
#    slowest modules, avg/longest duration and error total
#  - Time Machine module: "not configured" is now a WARN (Mac = single copy)
#    and lists attached candidate volumes with a `meister backup` hint
#  - XProtect: stale signatures (>14d) now trigger `xprotect update`
#    (fallback: softwareupdate --background-critical) instead of only warning
#  - history.log: per-run "top:" field with the 3 slowest modules (INSIGHTS #7)
#
# NEW in v5.22 (log-driven bugfix release):
#  - FIX exit codes: 6 modules ended in `[ cond ] && cmd` — false condition made
#    the whole module "fail" (Exit 1) and triggered pointless/dangerous AI-Heal
#    runs (broken_symlinks, dev_caches, dsstore, launchd_orphans, tcc_privacy,
#    receipts). All now `return 0`.
#  - AI-Heal hardened: placeholder answers (/path/to, <file>, example) rejected,
#    markdown fences stripped, `sudo rm` + glob-rm blocked, bash -o pipefail
#    (pipe masked failing finds as "success"), prompt forbids sudo/rm -rf.
#  - Sudo: max ONE password prompt per run. Upfront-auth failure sets
#    NEEDS_SUDO=false (modules skip gracefully); ALL module sudo calls are now
#    `sudo -n` — nothing can prompt mid-run anymore.
#  - Git: .meister-nopush marker / `git config meister.nopush true` skips push
#    per repo; "no push rights" and "SSH unreachable" are WARN with hint
#    instead of permanent ERROR; error line shows the real fatal line.
#  - Spotlight: /Volumes/Recovery whitelisted (read-only, mdutil always errors).
#  - Log-Analyse: anchored timestamp regex (no more quoting its own old output),
#    .old log ignored when >30d stale, German filter terms added.
#  - history.log: HEAL: field restored (parsers broke on missing field).
#  - Sleep Blockers: duplicate assertion lines deduped.
#  - ~/.meister hygiene: tb-sync-*.log >30d auto-removed.
#
# NEW in v5.21:
#  - Docs Order: new module module_docs_order — order check for ~/Documents:
#    root strangers (unknown top-level entries), empty iCloud ghost folders
#    ("X 2"/"X 3", cleanup config-gated), corrupt stubs (65535 links), unsorted
#    _Inbox files, dataless stats (content only in iCloud → backup warning).
#    Config: DOCS_ORDER_* in ~/.meister/config
#
# NEW in v5.20:
#  - Homebrew Quiet: module_homebrew now ensures HOMEBREW_NO_ENV_HINTS=1 and
#    HOMEBREW_NO_AUTO_UPDATE=1 — persisted once to the login shell's env file
#    (idempotent) and exported for the run. Kills the env-hint block and
#    auto-update chatter on every brew command. (The macOS pre-release
#    "Tier 2" support warning is not env-suppressible and is left as-is.)
#
# NEW in v5.19:
#  - Orphan Scanner: meister orphans — finds leftovers (prefs, caches, containers,
#    launchd, HTTPStorages, ...) of apps that are no longer installed, biggest
#    first, and lets you pick which to Trash. Conservative matching (skips
#    com.apple.*, live services, installed-app helpers/containers/siblings via a
#    single awk pass) keeps false positives low. bash-3.2 safe.
#
# NEW in v5.18:
#  - App Remover now CleanMyMac-aggressive: escalates to root on failure
#    (root-owned apps installed by pkg installers were silently left behind),
#    deep-scans /Library (Application Support, Caches, Preferences, Logs,
#    LaunchDaemons, LaunchAgents, PrivilegedHelperTools), unloads the app's
#    launchd services first, and `pkgutil --forget`s its receipts.
#
# NEW in v5.17:
#  - App Remover: meister remove <App> (AppCleaner-style uninstall)
#    Finds the .app bundle + every leftover (Application Support, Caches,
#    Preferences, Containers, Saved State, Logs, LaunchAgents) and moves
#    it all to Trash (reversible). --purge for permanent rm, --dry-run, -y.
#
# NEW in v1.1:
#  - Dotfiles Sync: meister push/pull/setup/init/scan/clone/bootstrap/status
#    Syncs AI configs (Claude, Gemini, Codex), shell, git, terminal across machines
#    manifest.txt driven — auto-detects configs via `meister scan`
#
# NEW in v1.0:
#  - AI-Heal: Ollama as fallback when known-fix fails
#    (Module failed → Known fix? → no → Ask Ollama → Execute fix → Retry)
#    Safety check blocks dangerous commands (rm -rf /, mkfs, dd, etc.)
#  - REMOVED: Git backup to iCloud (iCloud + .git = sync conflicts, GitHub is the backup)
#
# v0.09 (Elon Algorithm Cleanup):
#  - Removed: Lynis, RAM Purge, TCP/sysctl Tuning, fdupes, Mail-Check,
#    Recent Items, Launch Services rebuild, GUI-Animationen, Power-Override,
#    AI-Summary, AI-Performance-Tipps, doppelter Spotlight-Check
#  - Config parser simplified (case/esac → Loop)
#  - LaunchAgent: 1 template instead of 2
#  - Deep Clean: 14 instead of 20 sub-tasks
#  - Performance: 11 instead of 16 sub-tasks
#  - ~1000 lines less, same functionality
#
# Older versions: see git log
#   10. Dry-run mode (-n flag)
#   11. Network check with multiple endpoints
#   12. brew --greedy instead of --force
#   13. Config file (~/.meister/config)
#   14. Logfile moved to ~/.meister/meister.log
#   15. ClamAV: better exclude patterns
#   16. Run history in ~/.meister/history.log
#
# Usage: ./meister.sh [flags]
#   (no flags)  AUTO-DETECT: analyzes Mac, enables whas is needed
#   -a  Force ALL modules     -A  ClamAV (sudo)
#   -X  Xcode clean               -M  Monolingual
#   -T  Empty trash              -S  Sudo tasks
#   -C  Caches (sudo)             -L  Large files
#   -O  LM Studio sync            -c  ClamAV only
#   -P  Performance tuning        -G  Git repos
#   -H  Health dashboard          -n  Dry-Run
#   -N  Sniffnet (network monitor)    -q  Quiet (warnings/fixes only)
#   -I  LaunchAgent install           -h  Help
# ==============================================================================

#############################
# 1. CONFIGURATION
#############################

# Version is the single source of truth — extracted from the `# Version:`
# header comment, which release.sh also reads. Don't hardcode version
# strings elsewhere; reference $MEISTER_VERSION instead.
MEISTER_VERSION=$(awk '/^# Version:/ {print $3; exit}' "${BASH_SOURCE[0]}" 2>/dev/null)
MEISTER_VERSION=${MEISTER_VERSION:-unknown}

MEISTER_DIR="$HOME/.meister"
HEAL_LOG="$MEISTER_DIR/heal.log"
mkdir -p "$MEISTER_DIR/patches" "$MEISTER_DIR/output" 2>/dev/null

# v5.25: undo journal — reversible FIX actions as "RUN_ID<TAB>epoch<TAB>desc<TAB>src<TAB>dst".
# RUN_ID groups a run's actions so `meister undo` targets the latest run.
# NB: restore is ALWAYS a plain `cp -- src dst` executed WITHOUT a shell — the
# review found that shelling out a stored command allows injection via a
# preference filename containing a single quote (evil';touch pwned;'.plist).
UNDO_JOURNAL="$MEISTER_DIR/undo.journal"
RUN_ID=$(date +%Y%m%d-%H%M%S)
undo_record() {
    local desc="$1" src="$2" dst="$3"
    # flatten tabs+newlines — they are the field/line delimiters
    desc=$(printf '%s' "$desc" | tr '\n\t' '  ')
    src=$(printf '%s' "$src" | tr '\n\t' '  ')
    dst=$(printf '%s' "$dst" | tr '\n\t' '  ')
    printf '%s\t%s\t%s\t%s\t%s\n' "$RUN_ID" "$(date +%s)" "$desc" "$src" "$dst" >> "$UNDO_JOURNAL"
}

# Defaults
LOGFILE="$MEISTER_DIR/meister.log"
LOCKFILE="$MEISTER_DIR/meister.lock"
DISK_USAGE_THRESHOLD=80
LARGE_FILE_SIZE_MB=1000
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3-coder:30b}"
OLLAMA_FALLBACK_MODEL="llama3:latest"
OLLAMA_ENABLED=true
NET_CHECK_HOSTS="google.com apple.com cloudflare.com"

# Fix #78: Deep Clean Config-Gating (via ~/.meister/config steuerbar)
CLEAN_PKG_CACHES=true         # npm/pip/yarn/gem caches
CLEAN_DEV_CACHES=true         # CocoaPods/SPM/Carthage
CLEAN_PARALLELS_LOGS=true     # Parallels VM logs
CLEAN_FONT_CACHE=true         # Font cache + QuickLook cache

# Fix #93: macOS Performance-Optimization (via ~/.meister/config steuerbar)
PERF_SPOTLIGHT_EXCLUDE=true    # Exclude dev directories from Spotlight
PERF_DISABLE_AGENTS=true       # Disable unnecessary user LaunchAgents
PERF_CLEAN_OLLAMA=true         # Remove unused Ollama models
OLLAMA_KEEP_MODELS="qwen3-coder:30b llama3.2:latest"  # Models to keep

# Spotlight Fix (automatic on every run)
SPOTLIGHT_FIX_ENABLED=true         # Spotlight diagnosis and repair
SPOTLIGHT_MDS_CPU_THRESHOLD=30     # mds CPU threshold for restart (%)
SPOTLIGHT_REINDEX_ON_ERROR=true    # Auto-reindex on error

# iCloud Sync Fix (automatic on every run)
ICLOUD_FIX_ENABLED=true            # iCloud diagnosis and repair
ICLOUD_GHOST_DIRS_CLEAN=true       # Remove empty ghost folders in HOME
ICLOUD_STUBS_SCAN=true             # Detect corrupt iCloud stubs (65535 links)
ICLOUD_STUBS_DELETE=false          # Auto-delete corrupt stubs (default: off, safety)
ICLOUD_RESTART_BIRD=true           # bird-Daemon neustartingn at Problemen
ICLOUD_ORPHAN_CONTAINERS_WARN=true # Report orphaned CloudKit containers

# Docs Order check v5.21 (automatic on every run if root exists)
DOCS_ORDER_ENABLED=true            # Order check for DOCS_ORDER_ROOT
DOCS_ORDER_ROOT="$HOME/Documents"  # Directory to check
DOCS_ORDER_KNOWN=""                # Extra allowed top-level entries ("|"-separated), on top of learned baseline
DOCS_ORDER_GHOST_CLEAN=true        # Remove EMPTY "X 2"/"X 3" ghost folders at root
DOCS_ORDER_DATALESS_SCAN=true      # Scan for dataless files (content only in iCloud)
DOCS_ORDER_DATALESS_WARN_GB=5      # WARN when more than X GB exist only in iCloud

# Self-Healing v0.06: Automatic repair for all warnings
SELFHEAL_APPSTORE_OPEN=false       # Open App Store on missing login
SELFHEAL_FDA_OPEN=true             # Open privacy settings for FDA
SELFHEAL_ORPHAN_PREFS=true         # Backup + delete orphaned preferences
SELFHEAL_ICLOUD_CONTAINERS=true    # Delete orphaned iCloud containers
SELFHEAL_GIT_AUTOCOMMIT=true       # Auto-commit uncommitted changes
SELFHEAL_PERF_AUTO=true            # Auto-apply performance optimizations

# Git Repo Management (via -G Flag enabled)
GIT_AUTO_PUSH=true                          # Auto-push unpushed commits
GIT_REPO_SEARCH_PATHS="$HOME/Documents $HOME/Developer"  # Search paths for repos
GIT_REPO_MAXDEPTH=5                         # Max depth for repo search
# GIT_BACKUP_DIR/RETENTION/EXCLUDE removed (v0.09) - GitHub is the backup

# LaunchAgents to disable (partial match on plist name)
PERF_DISABLE_AGENT_PATTERNS="com.google.GoogleUpdater com.google.keystone com.macpaw.CleanMyMac com.bluebubbles.server"

# Benannte Konstanten (Fix #40)
LOG_MAX_SIZE=1048576          # 1MB - Log rotation threshold
LOG_GENERATIONS=3             # Anzahl rotierter Logs
OLLAMA_STARTUP_WAIT=15        # seconds waiting for Ollama server
LOG_CAPTURE_LINES=50          # Zeilen for Erroranalyse from Log
DISK_CRITICAL_THRESHOLD=95    # Percent - emergency cleanup threshold

# Fix #141: Track whether Meister started Ollama itself
OLLAMA_STARTED_BY_US=false

# Fix #144: Auto-Detect Schwellwerte (via ~/.meister/config steuerbar)
# Security Suite Konfiguration
SECURITY_PERSISTENCE_AUDIT=true        # LaunchAgent/Daemon integrity check
SECURITY_TCC_AUDIT=true                # Privacy permissions checking

# Docker + LaunchAgent Defaults
CLEAN_DOCKER=true                      # Docker Cleanup
LAUNCHAGENT_SCHEDULE="weekly"          # daily/weekly/monthly

AUTO_DETECT=true                       # Auto-detection enabled
AUTO_XCODE_THRESHOLD_MB=500            # Delete DerivedData above this size
AUTO_TRASH_THRESHOLD_ITEMS=50          # Empty trash above X items
AUTO_TRASH_THRESHOLD_MB=500            # Empty trash above X MB
AUTO_CACHE_THRESHOLD_MB=5000           # Delete user caches above X MB
AUTO_PERIODIC_INTERVAL_DAYS=7          # Run periodic scripts if last run > X days ago

# Load config file (overrides defaults)
MEISTER_CONFIG="$MEISTER_DIR/config"
if [ -f "$MEISTER_CONFIG" ]; then
    # Allowed config keys by type
    _BOOL_KEYS=" CLEAN_PKG_CACHES CLEAN_DEV_CACHES CLEAN_PARALLELS_LOGS CLEAN_FONT_CACHE CLEAN_DOCKER PERF_SPOTLIGHT_EXCLUDE PERF_DISABLE_AGENTS PERF_CLEAN_OLLAMA SPOTLIGHT_FIX_ENABLED SPOTLIGHT_REINDEX_ON_ERROR ICLOUD_FIX_ENABLED ICLOUD_GHOST_DIRS_CLEAN ICLOUD_STUBS_SCAN ICLOUD_STUBS_DELETE ICLOUD_RESTART_BIRD ICLOUD_ORPHAN_CONTAINERS_WARN SELFHEAL_APPSTORE_OPEN SELFHEAL_FDA_OPEN SELFHEAL_ORPHAN_PREFS SELFHEAL_ICLOUD_CONTAINERS SELFHEAL_GIT_AUTOCOMMIT SELFHEAL_PERF_AUTO SECURITY_PERSISTENCE_AUDIT SECURITY_TCC_AUDIT AUTO_DETECT GIT_AUTO_PUSH DOCS_ORDER_ENABLED DOCS_ORDER_GHOST_CLEAN DOCS_ORDER_DATALESS_SCAN UNIVERSAL_UPDATES UPDATE_GCLOUD UPDATE_CONDA "
    _NUM_KEYS=" DISK_USAGE_THRESHOLD LARGE_FILE_SIZE_MB SPOTLIGHT_MDS_CPU_THRESHOLD AUTO_XCODE_THRESHOLD_MB AUTO_TRASH_THRESHOLD_ITEMS AUTO_TRASH_THRESHOLD_MB AUTO_CACHE_THRESHOLD_MB AUTO_PERIODIC_INTERVAL_DAYS GIT_REPO_MAXDEPTH DOCS_ORDER_DATALESS_WARN_GB "
    _STR_KEYS=" OLLAMA_MODEL OLLAMA_FALLBACK_MODEL OLLAMA_URL NET_CHECK_HOSTS OLLAMA_KEEP_MODELS PERF_DISABLE_AGENT_PATTERNS GIT_REPO_SEARCH_PATHS LAUNCHAGENT_SCHEDULE DOCS_ORDER_ROOT DOCS_ORDER_KNOWN FLEET_HOSTS "

    while IFS='=' read -r key value; do
        key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"; value="${value%"${value##*[![:space:]]}"}"
        # strip ONE layer of matching surrounding quotes — the help/docs show
        # values like FLEET_HOSTS="a b c", but the file is parsed (not sourced),
        # so without this the literal quotes would end up in the value
        case "$value" in
            \"*\") value="${value#\"}"; value="${value%\"}" ;;
            \'*\') value="${value#\'}"; value="${value%\'}" ;;
        esac
        [ -z "$key" ] || [ "${key:0:1}" = "#" ] && continue
        if [[ " $_BOOL_KEYS " == *" $key "* ]]; then
            [[ "$value" =~ ^(true|false)$ ]] && declare "$key=$value"
        elif [[ " $_NUM_KEYS " == *" $key "* ]]; then
            [[ "$value" =~ ^[0-9]+$ ]] && declare "$key=$value"
        elif [[ " $_STR_KEYS " == *" $key "* ]]; then
            declare "$key=$value"
        fi
    done < "$MEISTER_CONFIG"
fi

# Report arrays
declare -a REPORT_SUCCESS
declare -a REPORT_FIXED
declare -a REPORT_WARNINGS
declare -a REPORT_ERRORS
SCRIPT_START_TIME=$(date +%s)

# Fix #84/#89: Cached values (single call, saves repeated forks)
_OLLAMA_LIST_CACHE=""

MODULE_STEP=0
MODULE_TOTAL=0
SUDO_KEEPALIVE_PID=""
INTERRUPTED=false

# Flags
CLEAN_XCODE=false
EMPTY_TRASH=false
RUN_SUDO_TASKS=false
CLEAN_CACHES=false
LIST_LARGE_FILES=false
NEEDS_SUDO=true  # Fix #145: Always-on self-healing - always request sudo
HEAL_COUNT=0     # heal events this run (for history.log HEAL: field)
MODULE_TIMINGS=() # "secs|name" per module — top-3 land in history.log (INSIGHTS #7)
MODULE_LEDGER=()  # "status|name|secs" per module — topgrade-style summary (v5.24)
MAINT_SCORE=""    # 0-100 maintenance score for this run (v5.25)
SHOW_HEALTH=false
DRY_RUN=false
INSTALL_LAUNCHAGENT=false
RUN_PERF_TUNE=false
RUN_GIT_REPOS=false
RUN_SNIFFNET=false
QUIET_MODE=false

#############################
# 2. CORE HELPERS & LOGGING
#############################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Fix #112: Timestamp-Cache spart ~200+ date-Forks pro Lauf
_LOG_TS_CACHE=""
_LOG_TS_SEC=-1

log() {
    local level="$1"; shift; local msg="$*"
    # Only recalculate timestamp when the second changes ($SECONDS is builtin, no fork)
    if [ "$SECONDS" != "$_LOG_TS_SEC" ]; then
        _LOG_TS_CACHE=$(date +'%Y-%m-%d %H:%M:%S')
        _LOG_TS_SEC=$SECONDS
    fi
    local ts="$_LOG_TS_CACHE"
    local color=$NC
    case "$level" in
        INFO)  color=$GREEN ;;
        WARN)  color=$YELLOW ;;
        ERROR) color=$RED ;;
        FIX)   color=$CYAN ;;
        HEAL)  color=$MAGENTA ;;
        STEP)  color=$DIM ;;
    esac
    # Quiet mode: only WARN/ERROR/FIX on terminal
    if ! $QUIET_MODE || [[ "$level" =~ ^(WARN|ERROR|FIX)$ ]]; then
        # Re-assert scroll region without moving cursor (DECSTBM homes cursor; save/restore protects current line)
        [ -n "$BW_MONITOR_PID" ] && printf '\0337\033[1;%dr\0338' "$((BW_TERM_LINES - 1))"
        echo -e "${color}[${level}]${NC} ${msg}"
    fi
    # Fix #91: ANSI-Strip only wenn needed (spart sed-Fork in ~95% der Aufrufe)
    if [[ "$msg" == *$'\033'* ]]; then
        echo "$ts - $level - $(echo "$msg" | sed 's/\x1b\[[0-9;]*m//g')" >> "$LOGFILE"
    else
        echo "$ts - $level - $msg" >> "$LOGFILE"
    fi
}

section_header() {
    local title="$1"
    MODULE_STEP=$((MODULE_STEP + 1))
    bw_set_status "$MODULE_STEP" "$MODULE_TOTAL" "$title"
    # v5.24: topgrade-style one-line separator: ── HH:MM:SS · [n/N] Title ────
    local ts; ts=$(date +%H:%M:%S)
    # Measure with an ASCII twin of the header ('--'/'*' have the same display
    # width as '──'/'·') — ${#var} is chars in UTF-8 locales but bytes under
    # launchd's C locale, so measuring the real string is locale-dependent.
    local plain="-- ${ts} * [${MODULE_STEP}/${MODULE_TOTAL}] ${title} "
    local fill_len=$(( 68 - ${#plain} )); [ "$fill_len" -lt 3 ] && fill_len=3
    local fill; fill=$(printf '─%.0s' $(seq 1 "$fill_len"))
    echo ""
    echo -e "${BLUE}── ${ts} · [${MODULE_STEP}/${MODULE_TOTAL}] ${BOLD}${title}${NC}${BLUE} ${fill}${NC}"
}

# v5.24: per-module status ledger for the topgrade-style end summary.
# Status is derived from what the module ADDED to the report arrays:
# ERR > WARN > FIX > OK (rc != 0 always wins as ERR).
ledger_add() {
    local name="$1" fix0="$2" warn0="$3" err0="$4" rc="$5"
    local status="OK"
    if [ "$rc" -ne 0 ] || [ ${#REPORT_ERRORS[@]} -gt "$err0" ]; then status="ERR"
    elif [ ${#REPORT_WARNINGS[@]} -gt "$warn0" ]; then status="WARN"
    elif [ ${#REPORT_FIXED[@]} -gt "$fix0" ]; then status="FIX"
    fi
    local elapsed=$(( $(date +%s) - MODULE_START_TS ))
    MODULE_LEDGER+=("${status}|${name}|${elapsed}")
}

module_timer_start() {
    MODULE_START_TS=$(date +%s)
}

module_timer_stop() {
    local name="$1"
    local end_ts=$(date +%s)
    local elapsed=$((end_ts - MODULE_START_TS))
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))
    MODULE_TIMINGS+=("${elapsed}|${name}")
    if [ $mins -gt 0 ]; then
        log STEP "   ${name} completed in ${mins}m ${secs}s"
    else
        log STEP "   ${name} completed in ${secs}s"
    fi
}

report_add() {
    local type="$1"; local msg="$2"
    case "$type" in
        SUCCESS) REPORT_SUCCESS+=("$msg") ;;
        FIX)     REPORT_FIXED+=("$msg") ;;
        WARN)    REPORT_WARNINGS+=("$msg") ;;
        ERROR)   REPORT_ERRORS+=("$msg") ;;
    esac
}

command_exists() { command -v "$1" &> /dev/null; }

rotate_logs() {
    if [ -f "$LOGFILE" ]; then
        local size=$(stat -f%z "$LOGFILE" 2>/dev/null || echo 0)
        if [ "$size" -gt "$LOG_MAX_SIZE" ]; then
            # Fix #36: Nummerierte Rotation (3 Generationen)
            local i=$((LOG_GENERATIONS - 1))
            while [ $i -ge 1 ]; do
                [ -f "${LOGFILE}.$i" ] && mv "${LOGFILE}.$i" "${LOGFILE}.$((i + 1))"
                i=$((i - 1))
            done
            [ -f "${LOGFILE}.old" ] && mv "${LOGFILE}.old" "${LOGFILE}.1"
            mv "$LOGFILE" "${LOGFILE}.old"
            log INFO "Logfile rotated (war $(( size / 1024 ))KB)"
        fi
    fi
    touch "$LOGFILE"
}

# Fuehrt Command from, zeigt Output zeilenweise, gibt echten Exit-Code zurueck
# Fix #68: tmpfile instead of PIPESTATUS (Subshell-Bug vermieden)
run_verbose() {
    if $DRY_RUN; then
        log STEP "   [DRY-RUN] $*"
        return 0
    fi
    local tmpout
    tmpout=$(mktemp)
    "$@" > "$tmpout" 2>&1
    local rc=$?
    while IFS= read -r line; do
        [ -n "$line" ] && log STEP "   $line"
    done < "$tmpout"
    rm -f "$tmpout"
    return $rc
}

# Einfacher Dry-Run-Wrapper ohne Output-Streaming
run_or_dry() {
    if $DRY_RUN; then
        log STEP "   [DRY-RUN] $*"
        return 0
    fi
    "$@"
}

# Fix #8: Lockfile
acquire_lock() {
    if [ -f "$LOCKFILE" ]; then
        local old_pid=$(cat "$LOCKFILE" 2>/dev/null)
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            log ERROR "Meister is already running (PID: $old_pid)"
            exit 1
        else
            log WARN "Stale lockfile removed (PID $old_pid no longer active)"
            rm -f "$LOCKFILE"
        fi
    fi
    echo $$ > "$LOCKFILE"
}

release_lock() {
    rm -f "$LOCKFILE" 2>/dev/null
}

# Fix #141: Ollama stop if started by Meister
shutdown_ollama() {
    if $OLLAMA_STARTED_BY_US; then
        log INFO "Stopping Ollama (started by Meister)..."
        pkill -f "ollama serve" 2>/dev/null
        # Kurz warten and checking ob stopped
        local w=0
        while [ $w -lt 5 ] && pgrep -f "ollama serve" >/dev/null 2>&1; do
            sleep 1
            w=$((w + 1))
        done
        if ! pgrep -f "ollama serve" >/dev/null 2>&1; then
            log FIX "   Ollama server stopped (RAM freed)"
        else
            log WARN "   Failed to stop Ollama server"
        fi
        OLLAMA_STARTED_BY_US=false
    fi
}

# Fix #35: Vereinheitlichter Trap for INT/TERM/EXIT
cleanup() {
    if $INTERRUPTED; then return; fi
    INTERRUPTED=true
    # Fix #141: Ollama stop before we clean up
    shutdown_ollama 2>/dev/null
    # Bei Signal (not normalem Exit) Report fromgeben
    if [ -n "$CLEANUP_SIGNAL" ]; then
        echo ""
        log WARN "Meister interrupted ($CLEANUP_SIGNAL), cleaning up..."
        print_report 2>/dev/null
        save_history 2>/dev/null
    fi
    [ -n "$SUDO_KEEPALIVE_PID" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    rm -f "$MEISTER_DIR/output"/*_$$.log 2>/dev/null
    release_lock
}

# Bandwidth + progress monitor (bottom pinned status line)
BW_MONITOR_PID=""
BW_TERM_LINES=""
BW_TERM_COLS=""
BW_STATUS_FILE="$MEISTER_DIR/status"
_bw_get_bytes() {
    netstat -ib 2>/dev/null | awk '/en0.*Link/ && NF>=10 {print $7, $10; exit}'
}
# Update current progress (called from section_header and ad-hoc from modules)
bw_set_status() {
    local cur="${1:-0}" tot="${2:-0}" label="${3:-}"
    [ -n "$BW_STATUS_FILE" ] && printf '%s|%s|%s\n' "$cur" "$tot" "$label" > "$BW_STATUS_FILE" 2>/dev/null
}
# Update just the label (keep current/total) — for showing sub-actions live in status bar
bw_phase() {
    local label="$1"
    bw_set_status "$MODULE_STEP" "$MODULE_TOTAL" "$label"
}
start_bw_monitor() {
    [ ! -t 1 ] && return
    kill_orphan_bw   # reap any stale status-bar process from a prior/crashed run
    # The bottom-pinned bandwidth/progress bar is redrawn from a background
    # process into a DECSTBM scroll region. That races fatally with this run's
    # own interactive `sudo` password prompt and the verbose TTY output of
    # brew/mas/softwareupdate, and with terminal resizes (the size is sampled
    # once at start): status snapshots leak into the scrollback and overwrite
    # log lines, garbling the whole run. The "[N/$MODULE_TOTAL] <module>"
    # section headers already convey progress, so the live bar is opt-in only:
    #   export MEISTER_STATUS_BAR=1
    case "${MEISTER_STATUS_BAR:-0}" in 1|true|yes|on|TRUE|YES|ON) ;; *) return ;; esac
    BW_TERM_LINES=$(tput lines 2>/dev/null || echo 24)
    BW_TERM_COLS=$(tput cols 2>/dev/null || echo 80)
    : > "$BW_STATUS_FILE"
    printf '\0337\033[1;%dr\0338' "$((BW_TERM_LINES - 1))"
    (
        local prev; prev=$(_bw_get_bytes)
        local prev_in=${prev%% *} prev_out=${prev##* }
        local bar_width=20
        while true; do
            sleep 1
            local curr; curr=$(_bw_get_bytes)
            local curr_in=${curr%% *} curr_out=${curr##* }
            local dl=$(( (curr_in - prev_in) / 1024 ))
            local ul=$(( (curr_out - prev_out) / 1024 ))
            [ "$dl" -lt 0 ] 2>/dev/null && dl=0
            [ "$ul" -lt 0 ] 2>/dev/null && ul=0
            # Read progress state
            local cur=0 tot=0 label=""
            if [ -s "$BW_STATUS_FILE" ]; then
                IFS='|' read -r cur tot label < "$BW_STATUS_FILE"
            fi
            # Build progress bar
            local filled=0
            if [ "${tot:-0}" -gt 0 ]; then
                filled=$(( (cur * bar_width) / tot ))
                [ "$filled" -gt "$bar_width" ] && filled=$bar_width
            fi
            local bar=""
            local i
            for ((i=0; i<filled; i++)); do bar+="█"; done
            for ((i=filled; i<bar_width; i++)); do bar+="░"; done
            local progress_str=""
            if [ "${tot:-0}" -gt 0 ]; then
                progress_str=$(printf ' [%s] %d/%d %s' "$bar" "$cur" "$tot" "$label")
            else
                progress_str=" [starting...]"
            fi
            local net_str=$(printf '↓ %d KB/s  ↑ %d KB/s' "$dl" "$ul")
            # Truncate progress_str to leave room for net_str (fixed ~30 cols) + padding
            local net_width=${#net_str}
            local max_progress=$(( BW_TERM_COLS - net_width - 3 ))
            [ "$max_progress" -lt 10 ] && max_progress=10
            if [ ${#progress_str} -gt $max_progress ]; then
                progress_str="${progress_str:0:$max_progress}"
            fi
            local pad_width=$(( BW_TERM_COLS - ${#progress_str} - net_width - 1 ))
            [ "$pad_width" -lt 1 ] && pad_width=1
            local padding
            printf -v padding '%*s' "$pad_width" ''
            local status="${progress_str}${padding}${net_str} "
            printf '\0337\033[1;%dr\033[%d;1H\033[2K\033[7m\033[2m%s\033[0m\0338' \
                "$((BW_TERM_LINES - 1))" "$BW_TERM_LINES" "$status"
            prev_in=$curr_in; prev_out=$curr_out
        done
    ) &
    BW_MONITOR_PID=$!
    echo "$BW_MONITOR_PID" > "$BW_PIDFILE"
}
BW_PIDFILE="$MEISTER_DIR/bw.pid"
kill_orphan_bw() {
    [ -f "$BW_PIDFILE" ] || return 0
    local old_pid; old_pid=$(cat "$BW_PIDFILE" 2>/dev/null)
    [ -n "$old_pid" ] && kill "$old_pid" 2>/dev/null
    rm -f "$BW_PIDFILE"
}
stop_bw_monitor() {
    [ -n "$BW_MONITOR_PID" ] || return 0
    kill "$BW_MONITOR_PID" 2>/dev/null
    wait "$BW_MONITOR_PID" 2>/dev/null
    BW_MONITOR_PID=""
    rm -f "$BW_PIDFILE"
    [ -t 1 ] || return 0
    local lines; lines=$(tput lines 2>/dev/null || echo 24)
    # Save cursor, clear status line at N, reset scroll region (DECSTBM-safe via save/restore), restore cursor
    printf '\0337\033[%d;1H\033[2K\033[1;%dr\0338' "$lines" "$lines"
}

trap 'CLEANUP_SIGNAL=INT; stop_bw_monitor; cleanup' INT
trap 'CLEANUP_SIGNAL=TERM; stop_bw_monitor; cleanup' TERM
trap 'stop_bw_monitor; cleanup' EXIT

#############################
# 3. OLLAMA SELF-HEALING
#############################

ollama_available() {
    [ "$OLLAMA_ENABLED" = "true" ] && curl -sf --max-time 5 "${OLLAMA_URL}/api/tags" >/dev/null 2>&1
}

# Fix #41: Central Ollama startingr (replaces duplicate code in module_ollama + main)
ensure_ollama_running() {
    local context="${1:-}"  # optional context for log messages
    if ollama_available; then
        return 0
    fi
    if ! command_exists ollama; then
        return 1
    fi
    log WARN "${context}Ollama offline - starting server..."
    ollama serve &>/dev/null &
    local ollama_pid=$!
    local wait_count=0
    while [ $wait_count -lt "$OLLAMA_STARTUP_WAIT" ]; do
        sleep 1
        wait_count=$((wait_count + 1))
        if curl -sf --max-time 2 "${OLLAMA_URL}/api/tags" >/dev/null 2>&1; then
            break
        fi
        [ $((wait_count % 5)) -eq 0 ] && log STEP "${context}   Waiting for Ollama server... (${wait_count}s)"
    done
    if ollama_available; then
        log FIX "${context}Ollama server started (after ${wait_count}s)"
        OLLAMA_ENABLED=true
        OLLAMA_STARTED_BY_US=true  # Fix #141: Remember that we started Ollama
        return 0
    else
        log WARN "${context}Ollama server not responding after ${OLLAMA_STARTUP_WAIT}s"
        if kill -0 "$ollama_pid" 2>/dev/null; then
            log STEP "${context}   Process running (PID: $ollama_pid) but API not reachable"
        else
            log WARN "${context}   Ollama process terminated immediately"
            local ollama_log="$HOME/.ollama/logs/server.log"
            if [ -f "$ollama_log" ]; then
                log STEP "${context}   Last log lines:"
                tail -5 "$ollama_log" 2>/dev/null | while IFS= read -r line; do
                    log STEP "${context}     $line"
                done
            fi
        fi
        OLLAMA_ENABLED=false
        return 1
    fi
}

# Fix #45: Model-Verfuegbarkeit checking, Auto-Pull or Fallback
ensure_ollama_model() {
    if ! ollama_available; then return 1; fi
    local model="$OLLAMA_MODEL"
    # Model name without tag for grep (e.g. "qwen3-coder" from "qwen3-coder:30b")
    if ollama_list_cached | awk 'NR>1 {print $1}' | grep -q "^${model}$"; then
        log STEP "   Model $model available"
        return 0
    fi
    # Model not present - versuche Auto-Pull
    log WARN "   Model $model not locally available, starting pull..."
    if ollama pull "$model" 2>/dev/null; then
        ollama_list_invalidate
        log FIX "   Model $model successfully downloaded"
        report_add FIX "Ollama: Model $model auto-pulled"
        return 0
    fi
    # Pull failed - Fallback-Model checking
    if [ -n "$OLLAMA_FALLBACK_MODEL" ] && [ "$OLLAMA_FALLBACK_MODEL" != "$model" ]; then
        if ollama_list_cached | awk 'NR>1 {print $1}' | grep -q "^${OLLAMA_FALLBACK_MODEL}$"; then
            log WARN "   Fallback to $OLLAMA_FALLBACK_MODEL (instead of $model)"
            OLLAMA_MODEL="$OLLAMA_FALLBACK_MODEL"
            log STEP "   Ollama: Fallback to $OLLAMA_FALLBACK_MODEL"
            return 0
        fi
    fi
    # Last Versuch: erstes availablees Model nehmen
    local first_model=$(ollama_list_cached | awk 'NR==2 {print $1}')
    if [ -n "$first_model" ]; then
        log WARN "   Fallback to erstes availablees Model: $first_model"
        OLLAMA_MODEL="$first_model"
        log STEP "   Ollama: Fallback to $first_model"
        return 0
    fi
    log ERROR "   No Ollama model available"
    OLLAMA_ENABLED=false
    return 1
}

# Fix #89: ollama list gecacht (wird only 1x abgefragt)
ollama_list_cached() {
    if [ -z "$_OLLAMA_LIST_CACHE" ]; then
        _OLLAMA_LIST_CACHE=$(ollama list 2>/dev/null)
    fi
    echo "$_OLLAMA_LIST_CACHE"
}
# Cache invalidieren (z.B. after pull)
ollama_list_invalidate() {
    _OLLAMA_LIST_CACHE=""
}

# Heal telemetry: append to ~/.meister/heal.log
log_heal_event() {
    local type="$1" module="$2" result="$3" detail="${4:-}"
    # detail can be a multi-line AI command — flatten, or heal.log line counts
    # (report section, HEAL_COUNT mapping) break
    detail=$(printf '%s' "$detail" | tr '\n' ' ')
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $type | $module | $result | $detail" >> "$HEAL_LOG"
    HEAL_COUNT=$((HEAL_COUNT + 1))
}

# v5.24: Learned-Fixes — AI fixes that worked once are remembered per module
# and tried BEFORE asking Ollama again (self-healing that gets smarter).
# Format: module<TAB>command, one line each, newest wins.
try_learned_fix() {
    local module_name="$1"
    local learned="$MEISTER_DIR/learned_fixes"
    [ -f "$learned" ] || return 1
    local cmd
    cmd=$(awk -F'\t' -v m="$module_name" '$1 == m {c=$2} END {if (c) print c}' "$learned")
    [ -z "$cmd" ] && return 1
    log HEAL "Learned-Fix: trying remembered fix for $module_name: $cmd"
    if $DRY_RUN; then log STEP "   [DRY-RUN] Would execute: $cmd"; return 0; fi
    if timeout 30 bash -o pipefail -c "$cmd" >/dev/null 2>&1; then
        log_heal_event "learned-fix" "$module_name" "applied" "$cmd"
        return 0
    fi
    # stopped working → forget it, fall through to Ollama.
    # NB: no && on grep — BSD grep -v exits 1 when it selects zero lines
    # (i.e. when this module's entry is the ONLY line), which silently
    # skipped the mv and kept the stale fix forever.
    grep -v "^${module_name}$(printf '\t')" "$learned" > "$learned.tmp" 2>/dev/null
    mv "$learned.tmp" "$learned"
    log HEAL "Learned-Fix failed — forgotten, asking Ollama fresh"
    return 1
}

remember_fix() {
    local module_name="$1" cmd="$2"
    local learned="$MEISTER_DIR/learned_fixes"
    # flatten multi-line commands (newline == ';' in bash) — the file format
    # is one TAB-separated line per module, a raw newline would corrupt it
    cmd=$(printf '%s' "$cmd" | tr '\n' ';')
    # replace any older entry for this module
    grep -v "^${module_name}$(printf '\t')" "$learned" > "$learned.tmp" 2>/dev/null
    printf '%s\t%s\n' "$module_name" "$cmd" >> "$learned.tmp"
    mv "$learned.tmp" "$learned"
}

# AI-Heal: Ollama fallback when known_fix() fails.
# $3 (optional): a previously tried command that did NOT fix it — the model
# is told to take a different approach (iterative healing, v5.24).
AI_LAST_CMD=""
ai_heal() {
    local module_name="$1"
    local error_output="$2"
    local prev_attempt="${3:-}"

    if ! ollama_available; then return 1; fi

    log HEAL "AI-Heal: Asking Ollama for fix for $module_name..."
    local retry_hint=""
    [ -n "$prev_attempt" ] && retry_hint="
A previous suggestion was already executed and did NOT fix it: $prev_attempt
Suggest a DIFFERENT approach."
    local prompt="You are a macOS sysadmin. A maintenance script module '$module_name' has failed.
Error: $error_output${retry_hint}
Reply ONLY with a single shell command that fixes the problem. No explanation, no markdown, just the command.
Rules: only safe, reversible commands. Never sudo. Never rm -rf. Never placeholders like /path/to or <file> — use only real absolute paths that appear in the error above. If no such fix is possible, reply with: NO_FIX"

    # Build request body (jq when available — handles all JSON escapes correctly)
    local request_body
    if command_exists jq; then
        request_body=$(jq -nc --arg model "$OLLAMA_MODEL" --arg prompt "$prompt" \
            '{model:$model, prompt:$prompt, stream:false}')
    else
        request_body=$(printf '{"model":"%s","prompt":"%s","stream":false}' \
            "$OLLAMA_MODEL" \
            "$(printf '%s' "$prompt" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')")
    fi

    local raw_response
    raw_response=$(curl -sf --max-time 30 "${OLLAMA_URL}/api/generate" \
        -d "$request_body" 2>/dev/null)

    # Parse .response — must decode \uXXXX, \n, \t, \", \\ correctly.
    # Bug history: a sed-only parser left && literal, so AI-Heal
    # ran `xcode-select --reset && ...` which xcode-select rejected.
    local ai_response
    if command_exists jq; then
        ai_response=$(printf '%s' "$raw_response" | jq -r '.response // ""' 2>/dev/null | head -3)
    else
        # Fallback: perl is always present on macOS and handles full JSON escapes
        ai_response=$(printf '%s' "$raw_response" \
            | perl -nle 'print $1 if /"response":"((?:[^"\\]|\\.)*)"/' \
            | perl -CSD -pe 's/\\u([0-9a-fA-F]{4})/chr(hex($1))/ge; s/\\n/\n/g; s/\\t/\t/g; s/\\r/\r/g; s/\\"/"/g; s/\\\\/\\/g' \
            | head -3)
    fi

    # Strip markdown fences/backticks (models wrap commands despite the prompt)
    ai_response=$(printf '%s\n' "$ai_response" | sed -e '/^```/d' -e 's/^`//; s/`$//' | head -3)

    if [ -z "$ai_response" ] || echo "$ai_response" | grep -qE "KEIN_FIX|NO_FIX"; then
        log WARN "AI-Heal: No fix found"
        log_heal_event "ai-heal" "$module_name" "no-fix" ""
        return 1
    fi

    # Reject placeholder commands — Ollama has answered with the literal
    # `/path/to/check` before, which then really ran (see INSIGHTS 2026-07-04 #1).
    if echo "$ai_response" | grep -qiE '/path/to|<[a-z_-]+>|your_|/example|example\.(com|txt)|placeholder'; then
        log WARN "AI-Heal: Placeholder in response — rejected: $ai_response"
        log_heal_event "ai-heal" "$module_name" "placeholder" "$ai_response"
        return 1
    fi

    # Reject responses that still contain raw JSON unicode escapes — means
    # the parser above failed, executing them produces garbage like &.
    if echo "$ai_response" | grep -qE '\\u[0-9a-fA-F]{4}'; then
        log WARN "AI-Heal: Malformed response (unicode escapes leaked) — skipping"
        log_heal_event "ai-heal" "$module_name" "malformed" "$ai_response"
        return 1
    fi

    # Security check: block dangerous commands.
    # sudo+rm and rm -rf with globs are blocked outright — an AI-Heal run once
    # executed `sudo rm -rf /Users/*/Library/...` (wildcard over ALL users).
    # NB: fork-bomb pattern must be escaped — unescaped `:(){ :` is an empty ERE
    # group; GNU/ugrep abort the WHOLE pattern with exit 2 → nothing gets blocked.
    if echo "$ai_response" | grep -qiE "rm -rf /[^a-z]|rm -rf?[[:space:]]+(/|~)[[:space:]]*(\||;|&|$)|sudo[[:space:]]+rm|rm -rf?[[:space:]][^;|&]*\*|mkfs|dd if=|:\(\)\{ :|> /dev/sd|shutdown|reboot|halt"; then
        log WARN "AI-Heal: Dangerous command blocked: $ai_response"
        log_heal_event "ai-heal" "$module_name" "blocked" "$ai_response"
        return 1
    fi

    # Block writes to system paths without sudo — reason: an AI-Heal run
    # tried `chmod 700 /etc/ssh` and burned an attempt with a guaranteed-fail.
    # If sudo is needed, the response must request it explicitly.
    if echo "$ai_response" | grep -qE "(chmod|chown|rm|mv|mkdir|touch|tee|>>?)[^|]*[[:space:]]+/(etc|System|Library|private|usr|bin|sbin|var)(/|[[:space:]]|$)" \
        && ! echo "$ai_response" | grep -qE "^[[:space:]]*sudo[[:space:]]"; then
        log WARN "AI-Heal: System-path mutation without sudo blocked: $ai_response"
        log_heal_event "ai-heal" "$module_name" "blocked-syspath" "$ai_response"
        return 1
    fi

    log HEAL "AI-Heal suggestion: $ai_response"

    if $DRY_RUN; then
        log STEP "   [DRY-RUN] Would execute: $ai_response"
        return 0
    fi

    # Execute with timeout. pipefail is essential: `find /bad/path | xargs rm -f`
    # otherwise reports exit 0 (xargs succeeds on empty input) and masks the failure.
    local ai_fix_output
    ai_fix_output=$(timeout 30 bash -o pipefail -c "$ai_response" 2>&1)
    local ai_rc=$?

    if [ $ai_rc -eq 0 ]; then
        log FIX "AI-Heal: Command successful"
        [ -n "$ai_fix_output" ] && log STEP "   Output: $(echo "$ai_fix_output" | head -3)"
        # NO report_add here — the command exiting 0 proves nothing; the caller
        # adds the FIX entry only after the module retest actually passes
        log_heal_event "ai-heal" "$module_name" "success" "$ai_response"
        AI_LAST_CMD="$ai_response"
        return 0
    else
        log WARN "AI-Heal: Command failed (Exit: $ai_rc)"
        log_heal_event "ai-heal" "$module_name" "failed" "$ai_response"
        [ -n "$ai_fix_output" ] && log STEP "   Output: $(echo "$ai_fix_output" | head -3)"
        return 1
    fi
}

# Known-Fix Patterns: fast fixes without Ollama
known_fix() {
    local module_name="$1"
    local error_output="$2"

    case "$error_output" in
        *"Could not resolve host"*|*"Failed to connect"*|*"Network is unreachable"*)
            log HEAL "Known-Fix: DNS/Network reset..."
            log_heal_event "known-fix" "$module_name" "applied" "dns-reset"
            sudo -n dscacheutil -flushcache 2>/dev/null
            sudo -n killall -HUP mDNSResponder 2>/dev/null
            sleep 2
            return 0
            ;;
        *"No space left on device"*)
            log HEAL "Known-Fix: Free disk space..."
            log_heal_event "known-fix" "$module_name" "applied" "disk-space"
            rm -rf "$HOME/Library/Caches"/* 2>/dev/null
            brew cleanup -s 2>/dev/null
            return 0
            ;;
        *"shallow"*|*"fetch-pack"*|*"Could not resolve HEAD"*)
            log HEAL "Known-Fix: Repair Homebrew repo..."
            log_heal_event "known-fix" "$module_name" "applied" "brew-repo"
            git -C "$(brew --repo)" fetch --unshallow 2>/dev/null
            brew update-reset 2>/dev/null
            return 0
            ;;
        *"already installed"*|*"is already an installed"*)
            log HEAL "Known-Fix: Already installed, OK"
            log_heal_event "known-fix" "$module_name" "applied" "already-installed"
            return 0
            ;;
        *"Couldn't find remote ref"*|*"fatal: bad object"*)
            log HEAL "Known-Fix: Git repository reset..."
            log_heal_event "known-fix" "$module_name" "applied" "git-reset"
            brew update-reset 2>/dev/null
            return 0
            ;;
        *"Error: Your CLT"*|*"xcode-select"*)
            log HEAL "Known-Fix: Repair Xcode CLT..."
            log_heal_event "known-fix" "$module_name" "applied" "xcode-clt"
            sudo -n xcode-select --reset 2>/dev/null
            return 0
            ;;
        *"SIGTERM"*|*"Terminated"*|*"kill"*)
            log HEAL "Known-Fix: Process terminated, retrying..."
            log_heal_event "known-fix" "$module_name" "applied" "process-killed"
            sleep 3
            return 0
            ;;
    esac
    return 1
}

# Fix #6: Logfile diff instead of empty stderr
run_module_safe() {
    local module_name="$1"
    local module_func="$2"

    section_header "$module_name"
    module_timer_start
    local log_lines_before=$(wc -l < "$LOGFILE" 2>/dev/null || echo 0)
    # Snapshot report counts — ledger_add derives the module status from the delta
    local fix0=${#REPORT_FIXED[@]} warn0=${#REPORT_WARNINGS[@]} err0=${#REPORT_ERRORS[@]}

    $module_func
    local rc=$?

    if [ $rc -eq 0 ]; then
        module_timer_stop "$module_name"
        ledger_add "$module_name" "$fix0" "$warn0" "$err0" 0
        return 0
    fi

    log ERROR "$module_name failed (Exit: $rc)"
    local module_output=$(tail -n +$((log_lines_before + 1)) "$LOGFILE" 2>/dev/null | head -"$LOG_CAPTURE_LINES")

    # Try known-fix + 1x retry
    if known_fix "$module_name" "Exit: $rc. $module_output"; then
        log HEAL "Known-Fix applied, retrying..."
        sleep 1
        $module_func
        rc=$?
        [ $rc -eq 0 ] && report_add FIX "$module_name via Known-Fix repaired"
    fi

    # v5.24: Learned-Fix — a remembered AI fix that worked before, no Ollama call
    if [ $rc -ne 0 ] && try_learned_fix "$module_name"; then
        log HEAL "Learned-Fix applied, retrying..."
        sleep 1
        $module_func
        rc=$?
        [ $rc -eq 0 ] && report_add FIX "$module_name via Learned-Fix repaired"
    fi

    # AI-Heal Fallback: up to 2 rounds — round 2 tells the model what round 1
    # tried, so it takes a different approach instead of repeating itself.
    local ai_round=1 last_ai_cmd=""
    while [ $rc -ne 0 ] && $OLLAMA_ENABLED && [ $ai_round -le 2 ]; do
        # LATEST lines of the module window (tail, not head) — round 2 must see
        # the retry's fresh error, not the same first-50 lines as round 1
        module_output=$(tail -n +$((log_lines_before + 1)) "$LOGFILE" 2>/dev/null | tail -"$LOG_CAPTURE_LINES")
        if ai_heal "$module_name" "Exit: $rc. $module_output" "$last_ai_cmd"; then
            last_ai_cmd="$AI_LAST_CMD"
            log HEAL "AI-Heal applied (round $ai_round), retrying..."
            sleep 1
            $module_func
            rc=$?
            if [ $rc -eq 0 ] && [ -n "$last_ai_cmd" ] && ! $DRY_RUN; then
                # FIX entry + remembering only after the retest confirms the fix
                report_add FIX "$module_name via AI-Heal repaired"
                remember_fix "$module_name" "$last_ai_cmd"
                log HEAL "Learned: fix for $module_name remembered for next time"
            fi
        else
            break
        fi
        ai_round=$((ai_round + 1))
    done

    [ $rc -ne 0 ] && report_add ERROR "$module_name failed"
    module_timer_stop "$module_name"
    ledger_add "$module_name" "$fix0" "$warn0" "$err0" "$rc"
    return $rc
}

#############################
# 4. INFRASTRUCTURE
#############################

# Fix #11: Moreere Endpunkte
check_net() {
    log INFO "Checking Network..."
    # Fix #114: Parallle Ping-Checks instead of sequentiell (bis 6s gespart at Error)
    # Fix #138: Nur Ping-PIDs abwarten, not ollama serve & (haengt sonst endlos)
    local _net_ok_file _ping_pids=""
    _net_ok_file=$(mktemp)
    rm -f "$_net_ok_file"
    for host in $NET_CHECK_HOSTS; do
        ( ping -c 1 -W 3 "$host" &>/dev/null && echo "$host" > "$_net_ok_file" ) &
        _ping_pids="$_ping_pids $!"
    done
    for _pid in $_ping_pids; do wait "$_pid" 2>/dev/null; done
    if [ -f "$_net_ok_file" ]; then
        local ok_host
        ok_host=$(cat "$_net_ok_file")
        rm -f "$_net_ok_file"
        log INFO "   Network OK (ping $ok_host)"
        return 0
    fi
    rm -f "$_net_ok_file" 2>/dev/null

    log STEP "   Ping failed, versuche HTTPS..."
    for host in $NET_CHECK_HOSTS; do
        if curl -sf --max-time 5 "https://$host" >/dev/null 2>&1; then
            log INFO "   Network OK (HTTPS $host)"
            return 0
        fi
    done

    log ERROR "No Internet-Connection!"

    report_add ERROR "No Internet connection"
    return 1
}

ensure_brew() {
    if ! command_exists brew; then
        log WARN "Homebrew not found. Installing..."
        run_or_dry /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if command_exists brew; then
            log FIX "Homebrew installed."
            report_add FIX "Installed Homebrew"
            eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null
        else
            log ERROR "Homebrew install failed."
            report_add ERROR "Homebrew missing"
            return 1
        fi
    else
        log STEP "   Homebrew found: $(brew --prefix)"
    fi
    return 0
}

# Keep Homebrew quiet: no env hints, no auto-update chatter on every command.
# Exports for the current run AND persists to the login shell's env file once
# (idempotent — guarded by the marker so re-running never duplicates).
ensure_brew_quiet() {
    export HOMEBREW_NO_ENV_HINTS=1
    export HOMEBREW_NO_AUTO_UPDATE=1

    local rc
    case "$(basename "${SHELL:-/bin/zsh}")" in
        zsh)  rc="$HOME/.zshenv" ;;
        bash) rc="$HOME/.bash_profile" ;;
        *)    rc="$HOME/.profile" ;;
    esac

    if [ -f "$rc" ] && grep -q 'HOMEBREW_NO_ENV_HINTS' "$rc" 2>/dev/null; then
        log STEP "   Homebrew already quiet ($rc)"
        return 0
    fi

    if $DRY_RUN; then
        log STEP "   [DRY-RUN] would silence Homebrew in $rc"
        return 0
    fi

    {
        printf '\n# meister: keep Homebrew quiet (env hints + auto-update)\n'
        printf 'export HOMEBREW_NO_ENV_HINTS=1\n'
        printf 'export HOMEBREW_NO_AUTO_UPDATE=1\n'
    } >> "$rc"
    log FIX "   Homebrew silenced (HOMEBREW_NO_* added to $rc)"
    report_add FIX "Silenced Homebrew noise in $rc"
}

ensure_tool() {
    local cmd="$1"
    local pkg="$2"
    local is_cask="${3:-}"

    if command_exists "$cmd"; then
        log STEP "   Tool '$cmd' present"
        return 0
    fi

    log WARN "Tool '$cmd' missing. Installing $pkg..."
    ensure_brew || return 1

    if run_or_dry brew install $is_cask "$pkg"; then
        log FIX "Installed '$pkg'."
        report_add FIX "Auto-installed: $pkg"
        return 0
    else
        log ERROR "Failed to install '$pkg'."
        report_add ERROR "Failed to install $pkg"
        return 1
    fi
}

#############################
# 5. MODULES
#############################

# ── HOMEBREW (Fix #4: korrekte Exit-Codes) ──

module_homebrew() {
    log INFO "Homebrew Maintenance..."
    ensure_brew || return 1
    ensure_brew_quiet

    local brew_version=$(brew --version 2>/dev/null | head -1)
    log STEP "   Version: $brew_version"

    # brew update mit korrektem Exit-Code
    log INFO "   brew update..."
    run_verbose brew update
    local update_rc=$?
    if [ $update_rc -ne 0 ]; then
        log WARN "brew update failed (Exit: $update_rc). Trying unshallow..."
        git -C "$(brew --repo)" fetch --unshallow &>/dev/null
        run_verbose brew update
        if [ $? -eq 0 ]; then
            report_add FIX "Fixed Homebrew repo (unshallow)"
        else
            log ERROR "brew update weiterhin failed"
        fi
    fi

    # Outdated formulae
    log INFO "   Checking outdated formulae..."
    local outdated_formulae=$(brew outdated --formula 2>/dev/null)
    if [ -n "$outdated_formulae" ]; then
        local formula_count=$(( $(echo "$outdated_formulae" | wc -l) ))
        log INFO "   ${formula_count} outdated formulae:"
        echo "$outdated_formulae" | while IFS= read -r line; do
            log STEP "     - $line"
        done
    else
        log INFO "   All formulae current"
    fi

    # Pinned Packages loggen (no Warning - bewusst gepinnt)
    local pinned=$(brew list --pinned 2>/dev/null)
    if [ -n "$pinned" ]; then
        local pin_count=$(( $(echo "$pinned" | wc -l) ))
        log STEP "   ${pin_count} gepinnte formulae (bewusst skipped)"
    fi

    # brew upgrade mit korrektem Exit-Code (capture to catch deprecated warnings)
    log INFO "   brew upgrade..."
    local formula_out; formula_out=$(mktemp)
    local rc=0
    if $DRY_RUN; then
        log STEP "   [DRY-RUN] brew upgrade"
        : > "$formula_out"
    else
        brew upgrade > "$formula_out" 2>&1
        rc=$?
        while IFS= read -r l; do [ -n "$l" ] && log STEP "   $l"; done < "$formula_out"
    fi
    if [ $rc -eq 0 ]; then
        report_add SUCCESS "Homebrew formulae upgraded"
    else
        log STEP "   Homebrew upgrade had issues (see log)"
    fi

    # Auto-uninstall deprecated/disabled formulae (brew refuses to upgrade them)
    local dead_formulae
    dead_formulae=$(grep -oE 'Warning: Not upgrading [a-zA-Z0-9@._+-]+, it is (deprecated|disabled)' "$formula_out" 2>/dev/null \
        | awk '{print $4}' | sed 's/,$//' | sort -u)
    if [ -n "$dead_formulae" ]; then
        log HEAL "   Auto-uninstalling deprecated/disabled formulae..."
        for name in $dead_formulae; do
            log STEP "     $name: brew uninstall --ignore-dependencies"
            if ! $DRY_RUN && brew uninstall --ignore-dependencies "$name" >/dev/null 2>&1; then
                report_add FIX "Uninstalled deprecated formula: $name"
            fi
        done
    fi
    rm -f "$formula_out"

    # Fix #142: Post-Upgrade Verifikation - sind still formulae veraltet?
    local still_outdated_formulae=$(brew outdated --formula 2>/dev/null)
    if [ -n "$still_outdated_formulae" ]; then
        local still_count=$(( $(echo "$still_outdated_formulae" | wc -l) ))
        log WARN "   ${still_count} formulae still outdated after upgrade - trying individual upgrade..."
        echo "$still_outdated_formulae" | while IFS= read -r pkg; do
            [ -z "$pkg" ] && continue
            local pkg_name=$(echo "$pkg" | awk '{print $1}')
            log STEP "     Retry: $pkg_name..."
            local upgrade_out
            upgrade_out=$(brew upgrade "$pkg_name" 2>&1)
            if [ $? -eq 0 ]; then
                log FIX "     $pkg_name successful updated"
                report_add FIX "brew upgrade (Retry): $pkg_name"
            else
                log WARN "     $pkg_name Upgrade failed:"
                echo "$upgrade_out" | tail -3 | while IFS= read -r errline; do
                    log STEP "       $errline"
                done
                log STEP "     brew upgrade failed: $pkg_name (siehe Log)"
            fi
        done
    fi

    # Outdated casks
    log INFO "   Checking outdated casks..."
    local outdated_casks=$(brew outdated --cask --greedy 2>/dev/null)
    if [ -n "$outdated_casks" ]; then
        local cask_count=$(( $(echo "$outdated_casks" | wc -l) ))
        log INFO "   ${cask_count} outdated casks:"
        echo "$outdated_casks" | while IFS= read -r line; do
            log STEP "     - $line"
        done
    else
        log INFO "   All casks current"
    fi

    # Fix #12: --greedy instead of --force
    log INFO "   Upgrading casks (--greedy)..."
    local cask_out; cask_out=$(mktemp)
    if $DRY_RUN; then
        log STEP "   [DRY-RUN] brew upgrade --cask --greedy"
        : > "$cask_out"
    else
        brew upgrade --cask --greedy > "$cask_out" 2>&1
        while IFS= read -r l; do [ -n "$l" ] && log STEP "   $l"; done < "$cask_out"
    fi

    # Fix #150: Auto-heal cask errors that block batch upgrade
    local missing_src stale_src
    missing_src=$(grep -oE '^[[:space:]]*[a-z0-9][a-z0-9_-]*: It seems the App source' "$cask_out" 2>/dev/null | sed -E 's/^[[:space:]]*([a-z0-9_-]+):.*/\1/' | sort -u)
    stale_src=$(grep -oE '^[[:space:]]*[a-z0-9][a-z0-9_-]*: It seems there is already an App' "$cask_out" 2>/dev/null | sed -E 's/^[[:space:]]*([a-z0-9_-]+):.*/\1/' | sort -u)
    local healed=0
    if [ -n "$missing_src" ] || [ -n "$stale_src" ]; then
        log HEAL "   Auto-healing broken casks..."
        for name in $stale_src; do
            local stale_path
            stale_path=$(grep "^[[:space:]]*${name}: It seems there is already an App at" "$cask_out" | grep -oE "'[^']+'" | head -1 | tr -d "'")
            if [ -n "$stale_path" ] && [ -e "$stale_path" ]; then
                log STEP "     $name: removing stale $stale_path"
                ! $DRY_RUN && rm -rf "$stale_path"
            fi
        done
        for name in $missing_src $stale_src; do
            log STEP "     $name: brew reinstall --cask --force"
            if ! $DRY_RUN && brew reinstall --cask --force "$name" >/dev/null 2>&1; then
                healed=$((healed + 1))
            fi
        done
        [ "$healed" -gt 0 ] && report_add FIX "Auto-healed ${healed} broken cask(s)"
    fi
    rm -f "$cask_out"

    # Fix #142: Post-Upgrade Cask-Verifikation — split deprecated/disabled from auto-update
    local still_outdated_casks=$(brew outdated --cask --greedy 2>/dev/null)
    if [ -n "$still_outdated_casks" ]; then
        local dead_casks="" live_casks=""
        while IFS= read -r line; do
            local name="${line%% *}"
            [ -z "$name" ] && continue
            if brew info --cask "$name" 2>&1 | grep -qE 'deprecated!|disabled!'; then
                dead_casks+="$line"$'\n'
            else
                live_casks+="$line"$'\n'
            fi
        done <<< "$still_outdated_casks"

        if [ -n "$live_casks" ]; then
            local live_count=$(echo -n "$live_casks" | grep -c '^')
            log STEP "   ${live_count} casks still outdated (auto-update apps, normal)"
            echo -n "$live_casks" | while IFS= read -r line; do
                log STEP "     - $line"
            done
        fi
        if [ -n "$dead_casks" ]; then
            local dead_count=$(echo -n "$dead_casks" | grep -c '^')
            log WARN "   ${dead_count} deprecated/disabled casks — uninstall recommended:"
            echo -n "$dead_casks" | while IFS= read -r line; do
                local name="${line%% *}"
                log STEP "     - $line  →  brew uninstall --cask $name"
            done
            report_add WARN "${dead_count} deprecated casks still installed"
        fi
    fi

    # Fix #23: autoremove after upgrade
    log INFO "   Autoremove unused dependencies..."
    local removed=$(brew autoremove 2>&1)
    if echo "$removed" | grep -q "Uninstalling"; then
        local rm_count=$(echo "$removed" | grep -c "Uninstalling")
        log FIX "   ${rm_count} unused dependencies removed"
        report_add FIX "brew autoremove: ${rm_count} Pakete removed"
    else
        log STEP "   No unused dependencies"
    fi

    log INFO "   Cleanup..."
    run_verbose brew cleanup -s
    report_add SUCCESS "Homebrew Cleanup finished"

    # Doctor-Check mit Auto-Fix (Fix #22)
    log INFO "   brew doctor..."
    local doctor_output=$(brew doctor 2>&1)
    if echo "$doctor_output" | grep -q "ready to brew"; then
        log INFO "   Homebrew ist healthy"
    else
        local warn_count=$(echo "$doctor_output" | grep -c "Warning" 2>/dev/null || echo 0)
        log WARN "   brew doctor: ${warn_count} Warnings"
        echo "$doctor_output" | grep "Warning" | head -5 | while IFS= read -r line; do
            log STEP "     $line"
        done

        # Auto-Fix: Unlinked kegs
        local did_autofix=false
        local unlinked=$(echo "$doctor_output" | grep -A20 "unlinked kegs" | grep "^  " | sed 's/^[[:space:]]*//' | head -10)
        if [ -n "$unlinked" ]; then
            log HEAL "   Auto-Fix: Unlinked Kegs linken..."
            did_autofix=true
            while IFS= read -r keg; do
                [ -z "$keg" ] && continue
                local keg_name=$(echo "$keg" | awk '{print $1}')
                if run_or_dry brew link "$keg_name" 2>/dev/null; then
                    log FIX "     Linked: $keg_name"
                    report_add FIX "brew link: $keg_name"
                else
                    log WARN "     Link failed: $keg_name (versuche --overwrite)"
                    run_or_dry brew link --overwrite "$keg_name" 2>/dev/null && \
                        report_add FIX "brew link --overwrite: $keg_name"
                fi
            done <<< "$unlinked"
        fi

        # Auto-Fix: Outdated Xcode CLT
        if echo "$doctor_output" | grep -qi "command line tools.*outdated\|CLT.*update"; then
            log HEAL "   Auto-Fix: Xcode CLT Update anstossen..."
            did_autofix=true
            run_or_dry softwareupdate --install --all 2>/dev/null
            report_add FIX "Xcode CLT Update angestossen"
        fi

        # Auto-Fix: Broken symlinks
        if echo "$doctor_output" | grep -qi "broken symlinks"; then
            log HEAL "   Auto-Fix: Broken symlinks cleaned up..."
            did_autofix=true
            brew cleanup -s 2>/dev/null
            report_add FIX "brew cleanup: Broken Symlinks cleaned up"
        fi

        # Fix #42: Re-check only wenn tatsaechlich Auto-Fixes angewendet wurden
        if $did_autofix; then
            local doctor_recheck=$(brew doctor 2>&1)
            if echo "$doctor_recheck" | grep -q "ready to brew"; then
                log FIX "   Homebrew healthy after auto-fix!"
                report_add FIX "brew doctor: All Warnings behoben"
            else
                local warn_remain=$(echo "$doctor_recheck" | grep -c "Warning" 2>/dev/null || echo 0)
                if [ "$warn_remain" -lt "$warn_count" ]; then
                    log FIX "   ${warn_count} -> ${warn_remain} Warnings reduziert"
                    report_add FIX "brew doctor: ${warn_count} -> ${warn_remain} Warnings"
                fi

                if [ "$warn_remain" -gt 0 ]; then
                    log STEP "   brew doctor: ${warn_remain} Warnings verbleiben (siehe Log)"
                fi
            fi
        else
            log STEP "   brew doctor: ${warn_count} warnings (no auto-fix possible, see log)"
        fi
    fi
}

# ── MAS (APP STORE) ──

module_mas() {
    log INFO "Checking Mac App Store..."
    ensure_tool "mas" "mas" || return 1

    # Login is only needed to purchase — outdated/upgrade run against local receipts
    if ! mas account &>/dev/null; then
        log STEP "   Not logged in (updates for installed apps still work)"
    fi

    export MAS_NO_AUTO_INDEX=1

    local spotlight_marker="$MEISTER_DIR/spotlight_fixed"
    if [ ! -f "$spotlight_marker" ]; then
        log INFO "   Indexing MAS apps for Spotlight (one-time)..."
        local idx_count=0
        for app_dir in /Applications/*.app; do
            [ -d "$app_dir/Contents/_MASReceipt" ] || continue
            mdimport "$app_dir" &>/dev/null || true
            idx_count=$((idx_count + 1))
            log STEP "   Indexiert: $(basename "$app_dir")"
        done
        touch "$spotlight_marker"
        log FIX "Spotlight index for ${idx_count} MAS apps rebuilt"
        report_add FIX "Spotlight index for ${idx_count} App Store apps repaired"
    fi

    log INFO "   Checking MAS-Updates..."
    local outdated=$(mas outdated 2>/dev/null)
    if [ -z "$outdated" ]; then
        log INFO "   All App Store Apps current"
        report_add SUCCESS "App Store apps up to date"
    else
        local count=$(( $(echo "$outdated" | wc -l) ))
        log INFO "   ${count} Updates available:"
        echo "$outdated" | while IFS= read -r line; do
            log STEP "     - $line"
        done
        log INFO "   Installiere Updates..."
        run_verbose mas upgrade
        if [ $? -eq 0 ]; then
            report_add FIX "Updated $count App Store Apps"
        else
            report_add ERROR "MAS Upgrade failed"
        fi
    fi
}

# ── OLLAMA (Fix #5: Subshell-Counter-Bug) ──

module_ollama() {
    log INFO "Checking Ollama..."

    if ! command_exists ollama; then
        if command_exists brew && brew list --cask ollama &>/dev/null; then
            ensure_tool "ollama" "ollama" "--cask"
        else
            log INFO "   Ollama not installed. Skipping."
            return 0
        fi
    fi

    if ! command_exists ollama; then return 0; fi

    # Fix #41: Use central startingr
    if ollama_available; then
        log INFO "   Ollama server running"
    elif ensure_ollama_running "   "; then
        report_add FIX "Ollama server auto-started"
    else
        log STEP "   Ollama-Server offline"
    fi

    local models=$(ollama_list_cached | awk 'NR>1 {print $1}')
    if [ -z "$models" ]; then
        log INFO "   No Ollama-models installed"
        return 0
    fi

    local model_count=$(( $(echo "$models" | wc -l) ))
    log INFO "   ${model_count} models found"

    # Fix #5: No Pipe, no Subshell-Problem
    local updated=0
    local failed=0
    for model in $models; do
        log INFO "   Pulling: $model"
        local pull_output
        pull_output=$(run_or_dry ollama pull "$model" 2>&1)
        local pull_rc=$?
        if [ $pull_rc -eq 0 ]; then
            updated=$((updated + 1))
            log STEP "     OK"
        else
            failed=$((failed + 1))
            log WARN "   Pull failed: $model"
            [ -n "$pull_output" ] && log STEP "     $(echo "$pull_output" | tail -1)"
        fi
    done

    [ $updated -gt 0 ] && ollama_list_invalidate
    log INFO "   ${updated}/${model_count} models updated"
    [ $failed -gt 0 ] && log WARN "   ${failed} Pulls failed"
    report_add FIX "Updated $updated/$model_count Ollama models"

}

# ── UNIVERSAL UPDATES (v5.24, topgrade-style) ──
# Everything brew/mas/softwareupdate do NOT cover: language package managers,
# toolchains, CLI SDKs, shell frameworks. Each step: detect → update → count.
# Config: UNIVERSAL_UPDATES=false disables the module, UPDATE_GCLOUD/UPDATE_CONDA
# gate the heavy ones.

module_universal_updates() {
    if [ "${UNIVERSAL_UPDATES:-true}" != "true" ]; then
        log STEP "   disabled (UNIVERSAL_UPDATES=false in config)"
        return 0
    fi
    log INFO "Universal Updates (npm/pipx/rust/gcloud/tldr/omz)..."
    local tools_updated=0 tools_current=0 tools_failed=0

    # npm globals (nvm-based installs only appear when npm is on PATH)
    if command_exists npm; then
        bw_phase "Updates: npm -g"
        local npm_outdated
        npm_outdated=$(timeout 60 npm outdated -g --parseable 2>/dev/null | grep -c . || true)
        if [ "${npm_outdated:-0}" -gt 0 ]; then
            if $DRY_RUN; then
                log STEP "   [DRY-RUN] npm -g: ${npm_outdated} outdated"
            elif timeout 300 npm update -g >/dev/null 2>&1; then
                log FIX "   npm -g: ${npm_outdated} package(s) updated"
                tools_updated=$((tools_updated + 1))
            else
                log WARN "   npm -g: update failed"
                tools_failed=$((tools_failed + 1))
            fi
        else
            log STEP "   npm -g: up to date"
            tools_current=$((tools_current + 1))
        fi
    fi

    # pipx-managed CLI tools
    if command_exists pipx; then
        bw_phase "Updates: pipx"
        if $DRY_RUN; then
            log STEP "   [DRY-RUN] pipx upgrade-all"
        else
            local pipx_out
            pipx_out=$(timeout 300 pipx upgrade-all 2>&1)
            local pipx_n
            pipx_n=$(echo "$pipx_out" | grep -c "upgraded package" || true)
            if [ "${pipx_n:-0}" -gt 0 ]; then
                log FIX "   pipx: ${pipx_n} package(s) upgraded"
                tools_updated=$((tools_updated + 1))
            else
                log STEP "   pipx: up to date"
                tools_current=$((tools_current + 1))
            fi
        fi
    fi

    # pip user packages: REPORT ONLY — auto-upgrading pip packages under a
    # conda/miniforge python breaks environments faster than it helps.
    if command_exists pip3; then
        bw_phase "Updates: pip (report)"
        local pip_outdated
        pip_outdated=$(timeout 60 pip3 list --outdated 2>/dev/null | tail -n +3 | grep -c . || true)
        if [ "${pip_outdated:-0}" -gt 0 ]; then
            log STEP "   pip: ${pip_outdated} outdated (report-only — update via conda/pipx)"
        else
            log STEP "   pip: up to date"
        fi
    fi

    # Rust toolchain
    if command_exists rustup; then
        bw_phase "Updates: rustup"
        if $DRY_RUN; then
            log STEP "   [DRY-RUN] rustup update"
        else
            local rust_out
            rust_out=$(timeout 300 rustup update 2>&1)
            if echo "$rust_out" | grep -q "updated"; then
                log FIX "   rustup: toolchain updated"
                tools_updated=$((tools_updated + 1))
            else
                log STEP "   rustup: up to date"
                tools_current=$((tools_current + 1))
            fi
        fi
    fi

    # cargo binaries (only with cargo-install-update helper present)
    if command_exists cargo-install-update; then
        bw_phase "Updates: cargo"
        if $DRY_RUN; then
            log STEP "   [DRY-RUN] cargo install-update -a"
        else
            local cargo_out
            cargo_out=$(timeout 600 cargo install-update -a 2>&1)
            if [ $? -ne 0 ]; then
                log WARN "   cargo install-update failed"
                tools_failed=$((tools_failed + 1))
            elif echo "$cargo_out" | grep -qi "updating\|installing"; then
                log FIX "   cargo: binaries updated"
                tools_updated=$((tools_updated + 1))
            else
                log STEP "   cargo: up to date"
                tools_current=$((tools_current + 1))
            fi
        fi
    fi

    # uv (python package manager, self-managed when not from brew)
    if command_exists uv && ! brew list uv &>/dev/null; then
        bw_phase "Updates: uv"
        if $DRY_RUN; then
            log STEP "   [DRY-RUN] uv self update"
        elif timeout 120 uv self update 2>&1 | grep -q "Upgraded"; then
            log FIX "   uv: updated"
            tools_updated=$((tools_updated + 1))
        else
            log STEP "   uv: up to date"
            tools_current=$((tools_current + 1))
        fi
    fi

    # Google Cloud SDK (heavy — gated, default on)
    if command_exists gcloud && [ "${UPDATE_GCLOUD:-true}" = "true" ]; then
        bw_phase "Updates: gcloud"
        if $DRY_RUN; then
            log STEP "   [DRY-RUN] gcloud components update"
        elif timeout 600 gcloud components update --quiet >/dev/null 2>&1; then
            log STEP "   gcloud: components checked/updated"
            tools_current=$((tools_current + 1))
        else
            log STEP "   gcloud: update skipped (managed install or offline)"
        fi
    fi

    # tldr pages cache
    if command_exists tldr; then
        bw_phase "Updates: tldr"
        $DRY_RUN || timeout 60 tldr --update >/dev/null 2>&1
        log STEP "   tldr: pages cache refreshed"
        tools_current=$((tools_current + 1))
    fi

    # oh-my-zsh (git-based — ff-only so a dirty checkout never breaks)
    if [ -d "$HOME/.oh-my-zsh/.git" ]; then
        bw_phase "Updates: oh-my-zsh"
        if $DRY_RUN; then
            log STEP "   [DRY-RUN] git -C ~/.oh-my-zsh pull"
        else
            local omz_before omz_after
            omz_before=$(git -C "$HOME/.oh-my-zsh" rev-parse HEAD 2>/dev/null)
            timeout 60 git -C "$HOME/.oh-my-zsh" pull --ff-only --quiet 2>/dev/null
            omz_after=$(git -C "$HOME/.oh-my-zsh" rev-parse HEAD 2>/dev/null)
            if [ -n "$omz_before" ] && [ "$omz_before" != "$omz_after" ]; then
                log FIX "   oh-my-zsh: updated"
                tools_updated=$((tools_updated + 1))
            else
                log STEP "   oh-my-zsh: up to date"
                tools_current=$((tools_current + 1))
            fi
        fi
    fi

    # conda: OFF by default — `conda update --all` reshuffles entire envs
    if command_exists conda; then
        if [ "${UPDATE_CONDA:-false}" = "true" ]; then
            bw_phase "Updates: conda"
            if $DRY_RUN; then
                log STEP "   [DRY-RUN] conda update -n base conda"
            elif timeout 600 conda update -n base -c conda-forge conda -y >/dev/null 2>&1; then
                log STEP "   conda: base checked"
                tools_current=$((tools_current + 1))
            else
                log WARN "   conda: base update failed"
                tools_failed=$((tools_failed + 1))
            fi
        else
            log STEP "   conda: present, skipped (enable: UPDATE_CONDA=true)"
        fi
    fi

    log INFO "   Universal Updates: ${tools_updated} updated, ${tools_current} current, ${tools_failed} failed"
    # failures must surface in report + ledger, not hide behind a SUCCESS line
    [ "$tools_failed" -gt 0 ] && report_add WARN "Universal Updates: ${tools_failed} toolchain update(s) failed"
    if [ "$tools_updated" -gt 0 ]; then
        report_add FIX "Universal Updates: ${tools_updated} toolchain(s) updated"
    elif [ "$tools_failed" -eq 0 ]; then
        report_add SUCCESS "Dev-Toolchains up to date"
    fi
    return 0
}

# ── GIT REPO MANAGEMENT (Fix #101-102) ──

module_git_repos() {
    log INFO "Git repository Management..."
    local repos_found=0

    # Git-Repo-Cache: find only 1x/Woche, daafter Cache verwenden (spart 10-30s)
    local repo_cache="$MEISTER_DIR/git_repos.cache"
    local repo_list=$(mktemp)
    local cache_max_age=$((7 * 86400))  # 7 Tage
    local use_cache=false

    if [ -f "$repo_cache" ]; then
        local cache_age=$(( $(date +%s) - $(stat -f%m "$repo_cache" 2>/dev/null || echo 0) ))
        if [ "$cache_age" -lt "$cache_max_age" ]; then
            # Cache valid - only checking ob Pfade still existieren
            while IFS= read -r gitdir; do
                [ -d "$gitdir" ] && echo "$gitdir"
            done < "$repo_cache" > "$repo_list"
            use_cache=true
            log STEP "   Repo cache used (age: $((cache_age / 86400))d)"
        fi
    fi

    if ! $use_cache; then
        # Frischer Scan
        for search_path in $GIT_REPO_SEARCH_PATHS; do
            [ ! -d "$search_path" ] && continue
            timeout 30 find "$search_path" -maxdepth "$GIT_REPO_MAXDEPTH" -name ".git" -type d \
                -not -path "*/node_modules/*" \
                -not -path "*/.Trash/*" \
                -not -path "*/Backups/*" \
                -not -path "*/Library/Mobile Documents/*" \
                2>/dev/null
        done | sort -u > "$repo_list"
        # Cache result
        cp "$repo_list" "$repo_cache" 2>/dev/null
    fi

    repos_found=$(wc -l < "$repo_list")
    repos_found=${repos_found##* }
    log INFO "   ${repos_found} Repos found"

    # ── [1/2] Unpushed Repos finden and pushen ──
    log STEP "   [1/2] Sync unpushed repos..."
    local repos_pushed=0
    local repos_dirty=0
    local repos_unpushed=0
    local repos_autocommitted=0

    while IFS= read -r gitdir; do
        [ -z "$gitdir" ] && continue
        local repo_dir=$(dirname "$gitdir")
        local repo_name=$(basename "$repo_dir")

        # Fix #105/#115: timeout 5 for all git commands (even local repos can hang on iCloud)
        # Fix #115: KEIN Pipe after timeout — head -1 frisst den Exit-Code 124
        local remote
        remote=$(timeout 5 git -C "$repo_dir" remote 2>/dev/null)
        if [ $? -eq 124 ]; then
            log WARN "     ${repo_name}: TIMEOUT on git remote"
            continue
        fi
        # Nur erste Zeile verwenden (falls moreere Remotes)
        remote=$(echo "$remote" | head -1)
        if [ -z "$remote" ]; then
            log STEP "     ${repo_name}: no remote, skipped"
            continue
        fi

        local branch
        branch=$(timeout 5 git -C "$repo_dir" symbolic-ref --short HEAD 2>/dev/null)
        [ -z "$branch" ] && continue

        # Fix #107: git status --porcelain einmal cachen instead of 2x aufrufen
        local dirty_output
        dirty_output=$(timeout 5 git -C "$repo_dir" status --porcelain 2>/dev/null)
        if [ -n "$dirty_output" ]; then
            local dirty_count
            dirty_count=$(echo "$dirty_output" | wc -l)
            dirty_count=${dirty_count##* }
            log WARN "     ${repo_name}: ${dirty_count} uncommitted changes (${branch})"
            # Self-Healing - Auto-Commit
            if $SELFHEAL_GIT_AUTOCOMMIT && ! $DRY_RUN; then
                local commit_msg="[meister] auto-commit: ${dirty_count} changes in ${repo_name}"
                # add -u (not -A): stage only already-tracked changes, never new
                # untracked files. Prevents auto-committing/pushing PII, secrets or
                # build junk that isn't gitignored yet. Untracked-only repos produce
                # an empty commit that fails harmlessly below.
                timeout 10 git -C "$repo_dir" add -u 2>/dev/null
                if timeout 10 git -C "$repo_dir" commit -m "$commit_msg" 2>/dev/null; then
                    log FIX "     ${repo_name}: Auto-Commit successful"
                    repos_autocommitted=$((repos_autocommitted + 1))
                else
                    log WARN "     ${repo_name}: Auto-Commit failed"
                    repos_dirty=$((repos_dirty + 1))
                fi
            else
                repos_dirty=$((repos_dirty + 1))
            fi
        fi

        # Fix #105: Upstream-Check mit timeout (kann Network brauchen)
        local upstream
        upstream=$(timeout 5 git -C "$repo_dir" rev-parse --abbrev-ref "${branch}@{upstream}" 2>/dev/null)
        if [ -z "$upstream" ]; then
            local remote_branch="${remote}/${branch}"
            local remote_exists
            remote_exists=$(timeout 5 git -C "$repo_dir" rev-parse --verify "$remote_branch" 2>/dev/null)
            [ -z "$remote_exists" ] && continue
            upstream="$remote_branch"
        fi

        # Fix #105: Log-Vergleich mit timeout
        local unpushed_output
        unpushed_output=$(timeout 5 git -C "$repo_dir" log "${upstream}..HEAD" --oneline 2>/dev/null)
        local unpushed=0
        [ -n "$unpushed_output" ] && unpushed=$(echo "$unpushed_output" | wc -l) && unpushed=${unpushed##* }
        if [ "${unpushed:-0}" -gt 0 ]; then
            repos_unpushed=$((repos_unpushed + 1))
            # Per-Repo-Opt-out: marker file or `git config meister.nopush true`
            # (forks without push rights, e.g. machato, produced a permanent ERROR)
            if [ -f "$repo_dir/.meister-nopush" ] || \
               [ "$(timeout 5 git -C "$repo_dir" config --get meister.nopush 2>/dev/null)" = "true" ]; then
                log STEP "     ${repo_name}: ${unpushed} unpushed, push opt-out (.meister-nopush)"
            elif $GIT_AUTO_PUSH; then
                log STEP "     ${repo_name}: ${unpushed} commits to push (${branch} -> ${remote})..."
                local push_output
                # Fix #105: Push mit timeout 30 (braucht more Zeit als Check)
                push_output=$(run_or_dry timeout 30 git -C "$repo_dir" push "$remote" "$branch" 2>&1)
                local push_rc=$?
                if [ $push_rc -eq 0 ]; then
                    log FIX "     ${repo_name}: ${unpushed} commits pushed"
                    repos_pushed=$((repos_pushed + 1))
                elif [ $push_rc -eq 124 ]; then
                    log ERROR "     ${repo_name}: Push Timeout (>30s)"
                elif echo "$push_output" | grep -qiE "permission denied \(publickey\)|denied to |403"; then
                    log WARN "     ${repo_name}: no push rights — set .meister-nopush or fork"
                elif echo "$push_output" | grep -qiE "port 22|Could not resolve host|Connection (refused|timed out|reset)"; then
                    log WARN "     ${repo_name}: network/SSH unreachable (transient?) — hint: ssh.github.com:443 as fallback"
                else
                    log ERROR "     ${repo_name}: Push failed"
                    # tail -1 often shows a useless advice line — prefer the actual error
                    [ -n "$push_output" ] && log STEP "       $(echo "$push_output" | grep -iE 'fatal|error|denied|rejected|failed' | head -1)"
                fi
            else
                log WARN "     ${repo_name}: ${unpushed} unpushed commits (${branch}) [-G to push]"
            fi
        fi
    done < "$repo_list"

    log INFO "   Push-Result: ${repos_pushed} pushed, ${repos_unpushed} had changes, ${repos_dirty} dirty, ${repos_autocommitted} auto-committed"
    [ "$repos_pushed" -gt 0 ] && report_add FIX "Git: ${repos_pushed} Repos pushed"
    [ "$repos_autocommitted" -gt 0 ] && report_add FIX "Git: ${repos_autocommitted} Repos auto-committed"
    [ "$repos_dirty" -gt 0 ] && log INFO "   Git: ${repos_dirty} repos with uncommitted changes"
    [ "$repos_unpushed" -gt "$repos_pushed" ] && \
        log INFO "   Git: $((repos_unpushed - repos_pushed)) repos still unpushed"

    # iCloud Git Backup removed (v0.09): Git repos belong on GitHub, not iCloud.
    # iCloud + .git = Sync-Konflikte, Lock-Files, kaputte Repos.

    rm -f "$repo_list"
}

# ── CLAMAV (Fix #15: bessere Excludes) ──

# Fix #147: ClamAV durch macOS-Bordmittel ersetzt (XProtect, Gatekeeper, MRT)
# ClamAV duplizierte only was macOS seit Ventura nativ macht, brauchte 20+ Minuten,
# haste staendig Permission-Probleme and fand praktisch nie was Neues.
module_xprotect() {
    log INFO "macOS Security Check (XProtect/Gatekeeper/MRT)..."
    local issues=0

    # 1. Gatekeeper active?
    local gk_status
    gk_status=$(spctl --status 2>&1)
    if echo "$gk_status" | grep -q "enabled"; then
        log STEP "   Gatekeeper: active"
    else
        log ERROR "   Gatekeeper: DISABLED!"
        issues=$((issues + 1))
        if ! $DRY_RUN; then
            sudo -n spctl --master-enable 2>/dev/null && log FIX "   Gatekeeper reenabled" && \
                report_add FIX "Gatekeeper reenabled"
        fi
    fi

    # 2. XProtect-Version and Aktualitaet
    local xp_bundle="/Library/Apple/System/Library/CoreServices/XProtect.bundle"
    if [ -d "$xp_bundle" ]; then
        local xp_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$xp_bundle/Contents/Info.plist" 2>/dev/null)
        log STEP "   XProtect: Version ${xp_version:-unbekannt}"

        # Alter der Signaturen checking
        local xp_mod=$(stat -f %m "$xp_bundle/Contents/Resources/XProtect.yara" 2>/dev/null || echo 0)
        local now=$(date +%s)
        local xp_age_days=$(( (now - xp_mod) / 86400 ))
        if [ "$xp_age_days" -gt 14 ]; then
            log WARN "   XProtect-Signaturen: ${xp_age_days} days old (>14)"
            issues=$((issues + 1))
            # Trigger the update instead of just warning about it every run.
            # `xprotect update` (macOS 15+) is authoritative; older systems get
            # the background critical-update check.
            if ! $DRY_RUN && $NEEDS_SUDO; then
                if command_exists xprotect && timeout 90 sudo -n xprotect update >/dev/null 2>&1; then
                    log FIX "   XProtect update triggered (xprotect update)"
                    report_add FIX "XProtect signature update triggered"
                elif timeout 90 sudo -n softwareupdate --background-critical >/dev/null 2>&1; then
                    log FIX "   Critical-update check triggered (softwareupdate --background-critical)"
                    report_add FIX "XProtect update check triggered"
                else
                    log INFO "   XProtect-Signaturen ${xp_age_days} days old (auto-update failed)"
                fi
            else
                log INFO "   XProtect-Signaturen ${xp_age_days} days old"
            fi
        else
            log STEP "   XProtect-Signaturen: ${xp_age_days} days old (OK)"
        fi
    else
        log ERROR "   XProtect bundle not found!"
        issues=$((issues + 1))
        report_add ERROR "XProtect-Bundle fehlt"
    fi

    # 3. XProtect Remediator (Background-Scanner seit Ventura)
    local xpr_dir="/Library/Apple/System/Library/CoreServices/XProtect.app"
    if [ -d "$xpr_dir" ]; then
        local xpr_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$xpr_dir/Contents/Info.plist" 2>/dev/null)
        log STEP "   XProtect Remediator: Version ${xpr_version:-unbekannt}"

        # Last Scan via XProtect Remediator
        local xpr_last=$(log show --predicate 'subsystem == "com.apple.XProtectFramework"' --last 24h --style compact 2>/dev/null | tail -1)
        if [ -n "$xpr_last" ]; then
            log STEP "   XProtect Remediator: Scan in letzten 24h found"
        else
            log STEP "   XProtect Remediator: no scan in last 24h (normal at low risk)"
        fi
    else
        log WARN "   XProtect Remediator not present (macOS < Ventura?)"
    fi

    # 4. MRT (Malware Removal Tool)
    local mrt_path="/Library/Apple/System/Library/CoreServices/MRT.app"
    if [ -d "$mrt_path" ]; then
        local mrt_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$mrt_path/Contents/Info.plist" 2>/dev/null)
        log STEP "   MRT: Version ${mrt_version:-unbekannt}"
    else
        log STEP "   MRT: not present (replaced by XProtect Remediator)"
    fi

    # 5. SIP (System Integrity Protection)
    local sip_status
    sip_status=$(csrutil status 2>&1)
    if echo "$sip_status" | grep -q "enabled"; then
        log STEP "   SIP: active"
    else
        log ERROR "   SIP: DISABLED!"
        issues=$((issues + 1))
        report_add ERROR "SIP disabled - Securitysrisiko!"
    fi

    # 6. Firewall
    local fw_status
    fw_status=$(sudo -n /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)
    if echo "$fw_status" | grep -q "enabled"; then
        log STEP "   Firewall: active"
    else
        log WARN "   Firewall: disabled"
        if ! $DRY_RUN; then
            sudo -n /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on 2>/dev/null && \
                log FIX "   Firewall enabled" && \
                report_add FIX "macOS Firewall enabled"
        fi
    fi

    if [ "$issues" -eq 0 ]; then
        report_add SUCCESS "macOS Security: XProtect + Gatekeeper + SIP OK"
    else
        log INFO "   macOS Security: ${issues} Hinweise (siehe Log)"
    fi
}

#############################
# 5b. SECURITY SUITE (Fix #145-#149)
#############################

# ── [146] LAUNCHDAEMON/LAUNCHAGENT INTEGRITAETSCHECK ──

module_persistence_audit() {
    log INFO "Persistence-Audit (LaunchAgents/Daemons)..."

    local suspicious=0
    local total_checked=0
    local findings=""

    # Bekannte Apple/System Bundle-IDs (Whitelist)
    local apple_pattern="^com\.apple\."
    local known_safe="com.meister|com.google.keystone|com.microsoft|com.docker|com.parallels|com.adobe|com.spotify|com.dropbox|com.1password|com.jetbrains|com.brew|homebrew|com.valvesoftware|com.jamf|com.nordvpn|com.bluebubbles|com.gytpol"

    # All LaunchAgent/Daemon Directories checking
    local -a plist_dirs=(
        "$HOME/Library/LaunchAgents"
        "/Library/LaunchAgents"
        "/Library/LaunchDaemons"
    )

    for plist_dir in "${plist_dirs[@]}"; do
        [ ! -d "$plist_dir" ] && continue
        log STEP "   Checking: $plist_dir"

        while IFS= read -r -d '' plist; do
            total_checked=$((total_checked + 1))
            local plist_name=$(basename "$plist")
            local label=""
            local program=""

            # Label and ProgramArguments extrahieren
            label=$(/usr/libexec/PlistBuddy -c "Print :Label" "$plist" 2>/dev/null)
            program=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2>/dev/null)
            [ -z "$program" ] && program=$(/usr/libexec/PlistBuddy -c "Print :Program" "$plist" 2>/dev/null)

            # Skip Apple-owned
            if [[ "$label" =~ $apple_pattern ]]; then
                continue
            fi

            # Skip known safe
            if echo "$label" | grep -qE "$known_safe"; then
                continue
            fi

            local issues=""

            # Check 1: Binary existiert?
            if [ -n "$program" ] && [ ! -f "$program" ] && [ ! -x "$program" ]; then
                issues="${issues}Binary fehlt ($program); "
            fi

            # Check 2: Binary an suspiciousem Ort?
            if [ -n "$program" ]; then
                case "$program" in
                    /tmp/*|/var/tmp/*|/private/tmp/*)
                        issues="${issues}Binary in /tmp (suspicious); " ;;
                    "$HOME"/.*/*|"$HOME"/.*)
                        # Hidden path - only warn if not known
                        if ! echo "$program" | grep -qE "\.(claude|ollama|nvm|npm|cargo|rustup|docker)/"; then
                            issues="${issues}Binary in hidden folder; "
                        fi ;;
                esac
            fi

            # Check 3: RunAtLoad + KeepAlive ohne bekannten Dienst
            local run_at_load=$(/usr/libexec/PlistBuddy -c "Print :RunAtLoad" "$plist" 2>/dev/null)
            local keep_alive=$(/usr/libexec/PlistBuddy -c "Print :KeepAlive" "$plist" 2>/dev/null)
            if [ "$run_at_load" = "true" ] && [ "$keep_alive" = "true" ]; then
                if ! echo "$label" | grep -qE "$known_safe"; then
                    issues="${issues}RunAtLoad+KeepAlive (Persistent); "
                fi
            fi

            # Check 4: Plist enthaelt suspiciouse Inhalte
            local plist_content=$(cat "$plist" 2>/dev/null)
            if echo "$plist_content" | grep -qE 'curl.*\|.*sh|wget.*\|.*sh|base64.*decode'; then
                issues="${issues}VERDAECHTIG: Download+Execute Pattern; "
            fi
            if echo "$plist_content" | grep -qi 'cryptominer\|coinhive\|xmrig\|minergate'; then
                issues="${issues}VERDAECHTIG: Cryptominer-Referenz; "
            fi

            # Check 5: Plist-Signatur checking (Code-Signing)
            if [ -n "$program" ] && [ -f "$program" ]; then
                if ! codesign -v "$program" 2>/dev/null; then
                    issues="${issues}Binary not signed; "
                fi
            fi

            if [ -n "$issues" ]; then
                suspicious=$((suspicious + 1))
                log WARN "   FOUND: $plist_name"
                log STEP "     Label:   $label"
                log STEP "     Binary:  ${program:-unbekannt}"
                log STEP "     Problem: $issues"
                # v5.24 (KnockKnock-style): hash + VirusTotal lookup link —
                # no API key needed, the link works in any browser
                if [ -n "$program" ] && [ -f "$program" ]; then
                    local bin_sha
                    bin_sha=$(shasum -a 256 "$program" 2>/dev/null | awk '{print $1}')
                    [ -n "$bin_sha" ] && log STEP "     Check:   https://www.virustotal.com/gui/file/$bin_sha"
                fi
                findings="${findings}\n${plist_name}: ${issues}"
            fi
        done < <(find "$plist_dir" -name "*.plist" -print0 2>/dev/null)
    done

    if [ "$suspicious" -gt 0 ]; then
        log INFO "   Persistence-Audit: ${suspicious}/${total_checked} entries checked (see log)"
    else
        report_add SUCCESS "Persistence-Audit: ${total_checked} entries checked, all OK"
    fi
    log INFO "   ${total_checked} plists checked, ${suspicious} suspicious"
}

# ── [148] TCC-AUDIT (Privacy permissions) ──

# Returns 0 if the TCC `client` (path or bundle id) currently resolves
# to an installed app, 1 otherwise. Shared by audit + heal so detection
# stays consistent.
#
# Detection cascade for whether a TCC client (path or bundle id) is
# currently present on the system.
#
# Hard guard first: bundle ids starting with com.apple. are NEVER flagged
# as orphan, even if the cascade can't locate them. macOS system daemons
# (e.g. com.apple.familycircled, com.apple.triald, com.apple.gamed) live
# in /System/Library and aren't .app bundles, widgets, or extensions —
# they evade mdfind/osascript/pluginkit. A live run of v5.12 deleted 10
# such Liverpool entries before this guard was added; manual surgical
# restore + this guard prevents recurrence. The trade-off (rare orphan
# Apple bundle id stays in TCC) is far cheaper than nuking iCloud
# Keychain sync permissions for system services.
#
# For non-Apple bundle ids the cascade is mdfind → osascript → pluginkit.
# Bundle id is "exists" if ANY tier finds it.
tcc_client_exists() {
    local client="$1"
    if [[ "$client" == /* ]]; then
        [ -e "$client" ]
        return $?
    fi
    # Apple system bundles: always treat as present
    [[ "$client" == com.apple.* ]] && return 0
    if [[ "$client" == *.* ]]; then
        if mdfind "kMDItemCFBundleIdentifier == '$client'" 2>/dev/null | grep -q .; then
            return 0
        fi
        local ls_id
        ls_id=$(osascript -e "try
            id of application id \"$client\"
        end try" 2>/dev/null)
        [ -n "$ls_id" ] && return 0
        if command_exists pluginkit; then
            pluginkit -m -i "$client" 2>/dev/null | grep -q .
            return $?
        fi
        return 1
    fi
    # No path, no dotted bundle id — assume exists (don't flag as orphan)
    return 0
}

module_tcc_audit() {
    log INFO "TCC-Audit (Privacy permissions)..."

    local tcc_findings=0

    # TCC-Datenbank Pfade
    local user_tcc="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    local system_tcc="/Library/Application Support/com.apple.TCC/TCC.db"

    # Berechtigungs-Typen die kritisch sind
    # kTCCServiceAccessibility = kann Tastatur/Mfrom steuern
    # kTCCServiceSystemPolicyAllFiles = Full Disk Access
    # kTCCServiceScreenCapture = Bildschirm aufnehmen
    # kTCCServiceMicrophone = Microphone
    # kTCCServiceCamera = Camera
    # kTCCServiceSystemPolicySysAdminFiles = System-Admin-Files

    local -a critical_services=(
        "kTCCServiceAccessibility:Bedienungshilfen (kann Tastatur/Mfrom steuern)"
        "kTCCServiceSystemPolicyAllFiles:Full Disk Access"
        "kTCCServiceScreenCapture:Bildschirmaufnahme"
        "kTCCServiceMicrophone:Microphone"
        "kTCCServiceCamera:Camera"
        "kTCCServiceSystemPolicySysAdminFiles:System-Admin-Files"
        "kTCCServiceAppleEvents:Apple Events (automation)"
    )

    # User-TCC-Datenbank lesen
    if [ -f "$user_tcc" ]; then
        log STEP "   Reading user permissions..."

        for service_entry in "${critical_services[@]}"; do
            local service="${service_entry%%:*}"
            local service_name="${service_entry#*:}"

            # Query all apps with this permission (allowed=1)
            local apps
            apps=$(sqlite3 "$user_tcc" \
                "SELECT client FROM access WHERE service='$service' AND auth_value=2;" 2>/dev/null)

            if [ -n "$apps" ]; then
                local app_count=$(echo "$apps" | wc -l | xargs)
                log STEP "   ${service_name}: ${app_count} apps authorized"
                while IFS= read -r app; do
                    [ -z "$app" ] && continue
                    local app_short=$(echo "$app" | sed 's|.*/||')

                    if tcc_client_exists "$app"; then
                        log STEP "     $app_short"
                    else
                        log WARN "     ORPHANED: $app_short has ${service_name} but is no longer installed!"
                        tcc_findings=$((tcc_findings + 1))
                    fi
                done <<< "$apps"
            fi
        done
    else
        log WARN "   User TCC database not readable (no Full Disk Access?)"
        tcc_findings=$((tcc_findings + 1))
        if $SELFHEAL_FDA_OPEN && ! $DRY_RUN; then
            log HEAL "   Oeffne Privacy-Settings..."
            open "x-apple.systempreferences:com.apple.preference.security?Privacy" 2>/dev/null
        fi
    fi

    # System-TCC checking (braucht root or FDA)
    if [ -f "$system_tcc" ] && [ -r "$system_tcc" ]; then
        log STEP "   Reading system permissions..."
        local fda_apps
        fda_apps=$(sqlite3 "$system_tcc" \
            "SELECT client FROM access WHERE service='kTCCServiceSystemPolicyAllFiles' AND auth_value=2;" 2>/dev/null)
        if [ -n "$fda_apps" ]; then
            local fda_count=$(echo "$fda_apps" | wc -l | xargs)
            log STEP "   Full Disk Access (System): ${fda_count} Apps"
            echo "$fda_apps" | while IFS= read -r app; do
                [ -z "$app" ] && continue
                log STEP "     $app"
            done
        fi
    else
        log STEP "   System TCC: not readable (needs sudo/FDA) - skipped"
    fi

    if [ "$tcc_findings" -gt 0 ]; then
        log INFO "   TCC-Audit: ${tcc_findings} entries (see log)"
    else
        report_add SUCCESS "TCC-Audit: all permissions current and valid"
    fi
}

# ── SECURITY SUITE ORCHESTRATOR ──

module_sniffnet() {
    if ! $RUN_SNIFFNET; then
        log INFO "Sniffnet: skipped (use -N to enable)"
        report_add SUCCESS "Sniffnet: skip (not requested)"
        return
    fi

    log INFO "Network Sniff..."
    local issues=0

    # 1. Active interface & IP
    log STEP "   [1/5] Active interface..."
    local iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
    if [ -n "$iface" ]; then
        local ip=$(ipconfig getifaddr "$iface" 2>/dev/null || echo "n/a")
        local mac=$(ifconfig "$iface" 2>/dev/null | awk '/ether/{print $2}')
        log STEP "   Interface: $iface | IP: $ip | MAC: $mac"
        report_add SUCCESS "Net: $iface ($ip)"
    else
        log WARN "   No active interface found"
        report_add WARN "Net: no active interface"
        issues=$((issues + 1))
    fi

    # 2. DNS check
    log STEP "   [2/5] DNS resolution..."
    local dns_servers=$(scutil --dns 2>/dev/null | awk '/nameserver\[/{print $3}' | sort -u | head -3 | tr '\n' ' ')
    local dns_ms=$(( $(date +%s%N 2>/dev/null || python3 -c 'import time;print(int(time.time()*1000))') ))
    local dns_ok=false
    dig +short apple.com A &>/dev/null && dns_ok=true
    local dns_end=$(( $(date +%s%N 2>/dev/null || python3 -c 'import time;print(int(time.time()*1000))') ))
    if $dns_ok; then
        log STEP "   DNS OK | Servers: $dns_servers"
    else
        log WARN "   DNS resolution failed"
        issues=$((issues + 1))
    fi

    # 3. Open connections (top processes)
    log STEP "   [3/5] Open connections..."
    local total_conn=$(netstat -an 2>/dev/null | grep -c ESTABLISHED)
    local listen_ports=$(netstat -an 2>/dev/null | grep -c LISTEN)
    log STEP "   Established: $total_conn | Listening: $listen_ports"

    local top_procs=$(lsof -i -nP 2>/dev/null | awk 'NR>1{print $1}' | sort | uniq -c | sort -rn | head -5)
    if [ -n "$top_procs" ]; then
        log STEP "   Top talkers (connections):"
        while IFS= read -r line; do
            log STEP "     $line"
        done <<< "$top_procs"
    fi
    report_add SUCCESS "Net: $total_conn established, $listen_ports listening"

    # 4. Bandwidth snapshot (bytes in/out on active interface)
    log STEP "   [4/5] Bandwidth snapshot..."
    if [ -n "$iface" ]; then
        local stats1=$(netstat -I "$iface" -b 2>/dev/null | awk 'NR==2{print $7, $10}')
        sleep 2
        local stats2=$(netstat -I "$iface" -b 2>/dev/null | awk 'NR==2{print $7, $10}')
        local in1=$(echo "$stats1" | awk '{print $1}') out1=$(echo "$stats1" | awk '{print $2}')
        local in2=$(echo "$stats2" | awk '{print $1}') out2=$(echo "$stats2" | awk '{print $2}')
        if [ -n "$in1" ] && [ -n "$in2" ]; then
            local in_rate=$(( (in2 - in1) / 2 / 1024 ))
            local out_rate=$(( (out2 - out1) / 2 / 1024 ))
            log STEP "   Throughput (2s avg): IN ${in_rate} KB/s | OUT ${out_rate} KB/s"
            report_add SUCCESS "Net throughput: IN ${in_rate} KB/s, OUT ${out_rate} KB/s"
        fi
    fi

    # 5. Suspicious connections check
    log STEP "   [5/5] Connection audit..."
    local non_std=$(lsof -i -nP 2>/dev/null | awk 'NR>1 && $8=="TCP" && $9~/ESTABLISHED/' | \
        awk -F'[>: ]' '{print $NF}' | sort -u | \
        grep -vE '^(80|443|53|22|8080|8443|993|587|465|143|110|25)$' | head -10)
    if [ -n "$non_std" ]; then
        log WARN "   Non-standard outbound ports: $(echo "$non_std" | tr '\n' ' ')"
        issues=$((issues + 1))
    else
        log STEP "   No suspicious outbound connections"
    fi

    [ "$issues" -eq 0 ] && report_add SUCCESS "Network sniff: clean" || report_add WARN "Network sniff: $issues issue(s)"
}

module_security_suite() {
    log INFO "Meister Security Suite..."

    module_xprotect
    $SECURITY_PERSISTENCE_AUDIT && module_persistence_audit || log STEP "   Persistence-Audit: disabled (Config)"
    $SECURITY_TCC_AUDIT && module_tcc_audit || log STEP "   TCC-Audit: disabled (Config)"

    log INFO "Security Suite completed"
}

# ── SYSTEM & CLEANUP ──

module_system() {
    log INFO "macOS system update check..."
    log STEP "   Checking softwareupdate..."
    local sysup=$(softwareupdate -l 2>&1)

    if echo "$sysup" | grep -q "No new software"; then
        log INFO "   macOS is up to date"
        report_add SUCCESS "macOS is up to date"
    else
        local update_count=$(echo "$sysup" | grep -c "^\*" 2>/dev/null || echo "?")
        log WARN "   ${update_count} macOS Updates available:"
        echo "$sysup" | grep "^\*\|Label\|Title" | while IFS= read -r line; do
            log STEP "     $line"
        done

        # Fix #26: Auto-install recommended updates (no restart)
        local has_restart=$(echo "$sysup" | grep -ci "restart" 2>/dev/null || echo 0)
        local has_recommended=$(echo "$sysup" | grep -ci "Recommended: YES" 2>/dev/null || echo 0)

        if [ "$has_recommended" -gt 0 ] && [ "$has_restart" -eq 0 ] && $NEEDS_SUDO; then
            log INFO "   Installing recommended updates (no restart needed)..."
            run_verbose sudo -n softwareupdate --install --recommended --agree-to-license
            if [ $? -eq 0 ]; then
                report_add FIX "macOS Recommended Updates installed"
            else
                log INFO "   macOS Update Installation failed (manual via Systemeinstellungen)"
            fi
        elif [ "$has_recommended" -gt 0 ] && [ "$has_restart" -eq 0 ]; then
            log WARN "   Empfohlene Updates available (sudo needed: -S or -a)"
            log INFO "   macOS Update available (sudo needed)"
        elif [ "$has_restart" -gt 0 ]; then
            log WARN "   Updates need restart - skipping auto-install"
            log INFO "   macOS Update available (Restart needed)"
        else
            log INFO "   macOS Update available ($update_count)"
        fi
    fi

    # Disk-Usage Check
    local disk_pct=$(df -h / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    local disk_free=$(df -h / | awk 'NR==2 {print $4}')
    log INFO "   Disk: ${disk_pct}% used, ${disk_free} free"
    if [ "$disk_pct" -gt "$DISK_USAGE_THRESHOLD" ] 2>/dev/null; then
        log WARN "   Disk usage above ${DISK_USAGE_THRESHOLD}%!"
        log INFO "   Disk usage: ${disk_pct}% (>${DISK_USAGE_THRESHOLD}%)"
    fi
}

module_cleanup() {
    log INFO "Cleanup..."

    if $CLEAN_XCODE; then
        local xcpath="$HOME/Library/Developer/Xcode/DerivedData"
        if [ -d "$xcpath" ]; then
            local xc_size=$(du -sh "$xcpath" 2>/dev/null | awk '{print $1}')
            log INFO "   Deleting Xcode DerivedData ($xc_size)..."
            run_or_dry rm -rf "$xcpath"
            report_add FIX "Deleted Xcode DerivedData ($xc_size)"
        else
            log INFO "   No Xcode DerivedData present"
        fi
    else
        log STEP "   Xcode clean: not needed (DerivedData < ${AUTO_XCODE_THRESHOLD_MB}MB)"
    fi

    if $EMPTY_TRASH; then
        local trash_count=$(( $(ls -1 "$HOME/.Trash" 2>/dev/null | wc -l) ))
        log INFO "   Emptying trash ($trash_count items)..."
        run_or_dry rm -rf "$HOME/.Trash"/*
        report_add FIX "Emptied Trash ($trash_count items)"
    else
        log STEP "   Trash: not needed (< ${AUTO_TRASH_THRESHOLD_ITEMS} items)"
    fi

    if $CLEAN_CACHES; then
        local cache_size=$(du -sh "$HOME/Library/Caches" 2>/dev/null | awk '{print $1}')
        log INFO "   Deleting User Caches ($cache_size)..."
        run_or_dry rm -rf "$HOME/Library/Caches"/*
        report_add FIX "Cleaned User Caches ($cache_size)"
        if $NEEDS_SUDO; then
            log INFO "   Deleting System Caches (sudo)..."
            run_or_dry sudo -n rm -rf /Library/Caches/* /System/Library/Caches/* /private/var/tmp/*
            report_add FIX "Cleaned System Caches"
        fi
    else
        log STEP "   Cache clean: not needed (< ${AUTO_CACHE_THRESHOLD_MB}MB)"
    fi

    if $LIST_LARGE_FILES; then
        log INFO "   Suche Files groesser ${LARGE_FILE_SIZE_MB}MB..."
        local large_files=$(find "$HOME" -xdev -type f -size +${LARGE_FILE_SIZE_MB}M -print0 2>/dev/null | xargs -0 ls -lh 2>/dev/null | awk '{print $5, $9}')
        if [ -n "$large_files" ]; then
            local lf_count=$(( $(echo "$large_files" | wc -l) ))
            log INFO "   ${lf_count} grosse Files found:"
            echo "$large_files" | head -10 | while IFS= read -r line; do
                log STEP "     $line"
            done
            [ "$lf_count" -gt 10 ] && log STEP "     ... and $((lf_count - 10)) weitere (siehe Log)"
            echo "$large_files" >> "$LOGFILE"
        else
            log INFO "   No Files groesser ${LARGE_FILE_SIZE_MB}MB"
        fi
        report_add SUCCESS "Large files logged"
    else
        log STEP "   Large files: not needed (Disk < ${DISK_USAGE_THRESHOLD}%)"
    fi
}

#############################
# 6. DEEP CLEAN & SYSTEM-HYGIENE (Fix #54-#67)
#############################

module_deepclean() {
    log INFO "Deep clean & system hygiene..."
    local total_freed=0

    # Fix #54: Clean up system logs
    log STEP "   [1/14] System-Logs..."
    local user_log_size=$(du -sm "$HOME/Library/Logs" 2>/dev/null | awk '{print $1}')
    [ -z "$user_log_size" ] && user_log_size=0
    if [ "$user_log_size" -gt 50 ]; then
        log INFO "   User-Logs: ${user_log_size} MB - cleaning up..."
        run_or_dry find "$HOME/Library/Logs" -type f -mtime +30 -delete
        local new_size=$(du -sm "$HOME/Library/Logs" 2>/dev/null | awk '{print $1}')
        [ -z "$new_size" ] && new_size=0
        local freed=$((user_log_size - new_size))
        [ "$freed" -gt 0 ] && { total_freed=$((total_freed + freed)); log FIX "   ${freed} MB User-Logs cleaned up"; }
    else
        log STEP "   User-Logs: ${user_log_size} MB (OK)"
    fi
    if $NEEDS_SUDO; then
        local sys_log_size=$(sudo -n du -sm /private/var/log 2>/dev/null | awk '{print $1}')
        [ -z "$sys_log_size" ] && sys_log_size=0
        if [ "$sys_log_size" -gt 200 ]; then
            log INFO "   System-Logs: ${sys_log_size} MB - cleaning up..."
            run_or_dry sudo -n find /private/var/log -type f -name "*.log" -mtime +30 -delete
            run_or_dry sudo -n rm -rf /private/var/log/asl/*.asl 2>/dev/null
            local freed_sys=$((sys_log_size - $(sudo -n du -sm /private/var/log 2>/dev/null | awk '{print $1}')))
            [ "$freed_sys" -gt 0 ] 2>/dev/null && { total_freed=$((total_freed + freed_sys)); log FIX "   ${freed_sys} MB System-Logs cleaned up"; }
        else
            log STEP "   System-Logs: ${sys_log_size} MB (OK)"
        fi
    fi

    # Fix #55: DMG/PKG/ZIP in Downloads (>30 Tage)
    log STEP "   [2/14] Clean up downloads..."
    local dl_junk_count=0
    local dl_junk_size=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        dl_junk_count=$((dl_junk_count + 1))
        local fsize=$(stat -f%z "$f" 2>/dev/null || echo 0)
        dl_junk_size=$((dl_junk_size + ${fsize:-0}))
    done < <(find "$HOME/Downloads" -maxdepth 1 -type f \( -name "*.dmg" -o -name "*.pkg" -o -name "*.zip" -o -name "*.tar.gz" -o -name "*.iso" \) -mtime +30 2>/dev/null)
    if [ "$dl_junk_count" -gt 0 ]; then
        local dl_mb=$((dl_junk_size / 1048576))
        log INFO "   ${dl_junk_count} old installers in Downloads (${dl_mb} MB, >30 Tage)"
        run_or_dry find "$HOME/Downloads" -maxdepth 1 -type f \( -name "*.dmg" -o -name "*.pkg" -o -name "*.zip" -o -name "*.tar.gz" -o -name "*.iso" \) -mtime +30 -delete
        total_freed=$((total_freed + dl_mb))
        report_add FIX "Downloads: ${dl_junk_count} old installers deleted (${dl_mb} MB)"
    else
        log STEP "   Downloads: no old installers"
    fi

    # Fix #56/#85: Orphaned Preferences - Batch-mdfind instead of einzeln (~50-100s gespart)
    # Fix #126: Self-Healing - Backup + Auto-Delete
    log STEP "   [3/14] Orphaned Preferences..."
    local orphan_count=0
    local installed_ids_file=$(mktemp)
    local orphan_list_file=$(mktemp)
    # All installeden Bundle-IDs in EINEM mdfind+mdls Aufruf sammeln
    mdfind "kMDItemContentType == 'com.apple.application-bundle'" 2>/dev/null | \
        xargs mdls -name kMDItemCFBundleIdentifier 2>/dev/null | \
        awk -F'"' '/kMDItemCFBundleIdentifier/ && $2 != "" {print $2}' | \
        sort -u > "$installed_ids_file"
    for plist in "$HOME/Library/Preferences"/*.plist; do
        [ ! -f "$plist" ] && continue
        local bundle_id=$(basename "$plist" .plist)
        # Skip system prefs and Apple-owned
        [[ "$bundle_id" == com.apple.* ]] && continue
        [[ "$bundle_id" == Apple.* ]] && continue
        [[ "$bundle_id" == loginwindow ]] && continue
        [[ "$bundle_id" == com.meister* ]] && continue
        # Fix #85: Checkingn gegen gecachte Bundle-ID-Liste (grep instead of mdfind pro Plist)
        if ! grep -qxF "$bundle_id" "$installed_ids_file" 2>/dev/null; then
            orphan_count=$((orphan_count + 1))
            echo "$plist" >> "$orphan_list_file"
            [ "$orphan_count" -le 50 ] && log STEP "     Orphan: $bundle_id"
        fi
    done
    rm -f "$installed_ids_file"
    if [ "$orphan_count" -gt 0 ]; then
        log INFO "   ${orphan_count} orphaned Preferences found"
        if $SELFHEAL_ORPHAN_PREFS && ! $DRY_RUN; then
            # Create backup
            local backup_dir="$MEISTER_DIR/backups/prefs_$(date +%Y%m%d)"
            mkdir -p "$backup_dir"
            local deleted=0
            while IFS= read -r orphan_plist; do
                [ -z "$orphan_plist" ] && continue
                local _bn; _bn=$(basename "$orphan_plist")
                # Only record undo if the BACKUP succeeded — otherwise undo would
                # point at a file that isn't there (review finding).
                if cp "$orphan_plist" "$backup_dir/" 2>/dev/null && rm -f "$orphan_plist" 2>/dev/null; then
                    deleted=$((deleted + 1))
                    undo_record "prefs: $_bn" "$backup_dir/$_bn" "$orphan_plist"
                fi
            done < "$orphan_list_file"
            log FIX "   ${deleted} orphaned Preferences deleted (Backup: $backup_dir)"
            report_add FIX "Deepclean: ${deleted} orphaned Preferences deleted (Backup in ~/.meister/backups/)"
        else
            log STEP "   ${orphan_count} orphaned preferences (will be deleted on next run)"
        fi
    else
        log STEP "   No orphaned preferences"
    fi
    rm -f "$orphan_list_file"

    # Fix #82: Broken Plists erkennen (paralllisiert)
    # Apple-eigene Plists (com.apple.*) werden ignoriert - Apple repaired die selbst
    log STEP "   [4/14] Broken Plists..."
    local broken_user=0
    local broken_list
    broken_list=$(find "$HOME/Library/Preferences" -name "*.plist" -not -name "com.apple.*" -print0 2>/dev/null | \
        xargs -0 -P 4 -I {} sh -c 'plutil -lint "$1" >/dev/null 2>&1 || basename "$1"' _ {} 2>/dev/null)
    if [ -n "$broken_list" ]; then
        while IFS= read -r bp; do
            [ -z "$bp" ] && continue
            broken_user=$((broken_user + 1))
            [ "$broken_user" -le 10 ] && log WARN "   Broken: $bp"
        done <<< "$broken_list"
        [ "$broken_user" -gt 0 ] && log INFO "   ${broken_user} broken Plists (non-Apple, siehe Log)"
    else
        log STEP "   All Plists OK"
    fi

    # Fix #59: Clean up screenshots (Desktop, >30 days)
    log STEP "   [5/14] Alte Screenshots..."
    local screenshot_count=0
    local screenshot_mb=0
    for dir in "$HOME/Desktop" "$HOME/Schreibtisch"; do
        [ ! -d "$dir" ] && continue
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            screenshot_count=$((screenshot_count + 1))
            local fsize=$(stat -f%z "$f" 2>/dev/null || echo 0)
            screenshot_mb=$((screenshot_mb + ${fsize:-0} / 1048576))
        done < <(find "$dir" -maxdepth 1 -type f \( -name "Screenshot*" -o -name "Bildschirmfoto*" -o -name "Screen Shot*" \) -mtime +30 2>/dev/null)
    done
    if [ "$screenshot_count" -gt 0 ]; then
        log INFO "   ${screenshot_count} alte Screenshots (${screenshot_mb} MB, >30 Tage)"
        for dir in "$HOME/Desktop" "$HOME/Schreibtisch"; do
            [ ! -d "$dir" ] && continue
            run_or_dry find "$dir" -maxdepth 1 -type f \( -name "Screenshot*" -o -name "Bildschirmfoto*" -o -name "Screen Shot*" \) -mtime +30 -delete
        done
        total_freed=$((total_freed + screenshot_mb))
        report_add FIX "Screenshots: ${screenshot_count} deleted (${screenshot_mb} MB)"
    else
        log STEP "   No old screenshots"
    fi

    # Fix #60: Time Machine lokale Snapshots
    log STEP "   [6/14] Time Machine Snapshots..."
    local tm_snapshots=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple" || echo 0)
    if [ "$tm_snapshots" -gt 0 ]; then
        # Purgeable Space durch TM Snapshots berechnen
        local tm_purgeable=$(( $(tmutil listlocalsnapshots / 2>/dev/null | wc -l) ))
        log INFO "   ${tm_purgeable} local TM snapshots found"
        local disk_pct=$(df -h / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
        if [ "$disk_pct" -gt "$DISK_USAGE_THRESHOLD" ] 2>/dev/null; then
            log WARN "   Disk ${disk_pct}% full - deleting old TM snapshots..."
            # Fix #69: Korrektes Snapshot-Datum extrahieren (Format: com.apple.TimeMachine.YYYY-MM-DD-HHMMSS.local)
            tmutil listlocalsnapshots / 2>/dev/null | sed -n 's/.*TimeMachine\.\(.*\)\.local/\1/p' | while IFS= read -r snap; do
                [ -n "$snap" ] && run_or_dry sudo -n tmutil deletelocalsnapshots "$snap"
            done
            report_add FIX "TM-Snapshots deleted (Disk war ${disk_pct}%)"
        else
            report_add SUCCESS "TM-Snapshots: ${tm_purgeable} present (Disk OK)"
        fi
    else
        log STEP "   No lokalen TM-Snapshots"
    fi

    # Fix #66: Alte iOS-Backups
    log STEP "   [7/14] iOS-Backups..."
    local backup_dir="$HOME/Library/Application Support/MobileSync/Backup"
    if [ -d "$backup_dir" ]; then
        local backup_count=0
        local backup_total_mb=0
        while IFS= read -r d; do
            [ ! -d "$d" ] && continue
            local bsize=$(du -sm "$d" 2>/dev/null | awk '{print $1}')
            [ -z "$bsize" ] && bsize=0
            backup_count=$((backup_count + 1))
            backup_total_mb=$((backup_total_mb + bsize))
            local bname=$(basename "$d")
            log STEP "     Backup: ${bname:0:12}... (${bsize} MB)"
        done < <(find "$backup_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
        if [ "$backup_count" -gt 0 ]; then
            log INFO "   ${backup_count} iOS-Backups, total ${backup_total_mb} MB"
            if [ "$backup_total_mb" -gt 10240 ]; then
                log INFO "   iOS-Backups: ${backup_total_mb} MB (${backup_count} Stueck)"
            else
                report_add SUCCESS "iOS-Backups: ${backup_count} (${backup_total_mb} MB)"
            fi
        else
            log STEP "   No iOS-Backups"
        fi
    else
        log STEP "   No iOS-Backup-Directory"
    fi

    # Fix #72: Package Manager Caches (npm/pip/yarn/gem)
    if $CLEAN_PKG_CACHES; then
        log STEP "   [8/12] Package Manager Caches..."
        local pkg_freed=0

        if command_exists npm && [ -d "$HOME/.npm" ]; then
            local npm_size=$(du -sm "$HOME/.npm" 2>/dev/null | awk '{print $1}')
            [ -z "$npm_size" ] && npm_size=0
            if [ "$npm_size" -gt 50 ]; then
                log INFO "   npm cache: ${npm_size} MB"
                run_or_dry npm cache clean --force 2>/dev/null
                pkg_freed=$((pkg_freed + npm_size))
            else
                log STEP "   npm cache: ${npm_size} MB (OK)"
            fi
        fi

        if command_exists yarn && [ -d "$HOME/.yarn/cache" ]; then
            local yarn_size=$(du -sm "$HOME/.yarn/cache" 2>/dev/null | awk '{print $1}')
            [ -z "$yarn_size" ] && yarn_size=0
            if [ "$yarn_size" -gt 50 ]; then
                log INFO "   yarn cache: ${yarn_size} MB"
                run_or_dry yarn cache clean 2>/dev/null
                pkg_freed=$((pkg_freed + yarn_size))
            fi
        fi

        if command_exists pip3; then
            local pip_dir="$HOME/Library/Caches/pip"
            if [ -d "$pip_dir" ]; then
                local pip_size=$(du -sm "$pip_dir" 2>/dev/null | awk '{print $1}')
                [ -z "$pip_size" ] && pip_size=0
                if [ "$pip_size" -gt 50 ]; then
                    log INFO "   pip cache: ${pip_size} MB"
                    run_or_dry pip3 cache purge 2>/dev/null
                    pkg_freed=$((pkg_freed + pip_size))
                fi
            fi
        fi

        if command_exists gem && [ -d "$HOME/.gem" ]; then
            local gem_size=$(du -sm "$HOME/.gem" 2>/dev/null | awk '{print $1}')
            [ -z "$gem_size" ] && gem_size=0
            if [ "$gem_size" -gt 50 ]; then
                log INFO "   gem cache: ${gem_size} MB"
                run_or_dry gem cleanup 2>/dev/null
                pkg_freed=$((pkg_freed + gem_size / 2))
            fi
        fi

        if [ "$pkg_freed" -gt 0 ]; then
            total_freed=$((total_freed + pkg_freed))
            report_add FIX "Package Caches: ${pkg_freed} MB cleaned up"
        else
            log STEP "   All Package Caches small or not present"
        fi
    else
        log STEP "   Package Caches: skipped (Config)"
    fi

    # Fix #73: Developer Tool Caches (CocoaPods/SPM/Carthage)
    if $CLEAN_DEV_CACHES; then
        log STEP "   [9/12] Developer Tool Caches..."
        local dev_freed=0

        if [ -d "$HOME/.cocoapods/repos" ]; then
            local pods_size=$(du -sm "$HOME/.cocoapods/repos" 2>/dev/null | awk '{print $1}')
            [ -z "$pods_size" ] && pods_size=0
            if [ "$pods_size" -gt 100 ]; then
                log INFO "   CocoaPods repos: ${pods_size} MB"
                run_or_dry rm -rf "$HOME/.cocoapods/repos/trunk"
                dev_freed=$((dev_freed + pods_size / 2))
            fi
        fi

        if [ -d "$HOME/.swiftpm/cache" ]; then
            local spm_size=$(du -sm "$HOME/.swiftpm/cache" 2>/dev/null | awk '{print $1}')
            [ -z "$spm_size" ] && spm_size=0
            if [ "$spm_size" -gt 100 ]; then
                log INFO "   SPM cache: ${spm_size} MB"
                run_or_dry rm -rf "$HOME/.swiftpm/cache"/*
                dev_freed=$((dev_freed + spm_size))
            fi
        fi

        local carthage_dir="$HOME/Library/Caches/org.carthage.CarthageKit"
        if [ -d "$carthage_dir" ]; then
            local cart_size=$(du -sm "$carthage_dir" 2>/dev/null | awk '{print $1}')
            [ -z "$cart_size" ] && cart_size=0
            if [ "$cart_size" -gt 100 ]; then
                log INFO "   Carthage cache: ${cart_size} MB"
                run_or_dry rm -rf "$carthage_dir"/*
                dev_freed=$((dev_freed + cart_size))
            fi
        fi

        if [ "$dev_freed" -gt 0 ]; then
            total_freed=$((total_freed + dev_freed))
            report_add FIX "Developer Caches: ${dev_freed} MB cleaned up"
        else
            log STEP "   All Developer Caches small or not present"
        fi
    else
        log STEP "   Developer Caches: skipped (Config)"
    fi

    # Fix #74: Docker Cleanup
    if $CLEAN_DOCKER && command_exists docker; then
        log STEP "   [10/12] Docker Cleanup..."
        if docker info &>/dev/null; then
            local stopped=$(( $(docker ps -aq --filter status=exited 2>/dev/null | wc -l) ))
            local dangling=$(( $(docker images -f "dangling=true" -q 2>/dev/null | wc -l) ))
            if [ "${stopped:-0}" -gt 0 ] || [ "${dangling:-0}" -gt 0 ]; then
                log INFO "   Docker: ${stopped} stopped containers, ${dangling} dangling images"
                run_or_dry docker container prune -f --filter "until=72h" 2>/dev/null
                run_or_dry docker image prune -f 2>/dev/null
                run_or_dry docker volume prune -f 2>/dev/null
                report_add FIX "Docker: ${stopped} containers + ${dangling} images cleaned up"
            else
                log STEP "   Docker: sauber"
            fi
        else
            log STEP "   Docker: Daemon unreachable"
        fi
    elif $CLEAN_DOCKER; then
        log STEP "   Docker: not installed"
    else
        log STEP "   Docker: skipped (Config: CLEAN_DOCKER=false)"
    fi

    # Fix #75: Parallels VM logs
    if $CLEAN_PARALLELS_LOGS && [ -d "$HOME/Library/Parallels" ]; then
        log STEP "   [11/12] Parallels VM logs..."
        local prl_log_count
        prl_log_count=$(( $(find "$HOME/Library/Parallels" -name "*.log" -mtime +30 2>/dev/null | wc -l) ))
        if [ "${prl_log_count:-0}" -gt 0 ]; then
            local prl_size=$(find "$HOME/Library/Parallels" -name "*.log" -mtime +30 -exec du -sm {} + 2>/dev/null | awk '{s+=$1} END {print s+0}')
            log INFO "   Parallels: ${prl_log_count} old logs (${prl_size:-0} MB)"
            run_or_dry find "$HOME/Library/Parallels" -name "*.log" -mtime +30 -delete
            total_freed=$((total_freed + ${prl_size:-0}))
            report_add FIX "Parallels Logs: ${prl_log_count} deleted"
        else
            log STEP "   Parallels: no old logs"
        fi
    else
        log STEP "   Parallels: skipped"
    fi

    # Fix #76: Font cache + QuickLook cache rebuild
    if $CLEAN_FONT_CACHE; then
        log STEP "   [12/12] Font & QuickLook Cache..."
        # Font-Cache
        if [ -x /usr/bin/atsutil ]; then
            run_or_dry atsutil databases -remove 2>/dev/null
            log FIX "   Font cache rebuilt"
        fi
        # QuickLook-Cache
        local ql_dir="$HOME/Library/Caches/com.apple.QuickLookDaemon"
        if [ -d "$ql_dir" ]; then
            local ql_size=$(du -sm "$ql_dir" 2>/dev/null | awk '{print $1}')
            run_or_dry rm -rf "$ql_dir"
            log FIX "   QuickLook-Cache deleted (${ql_size:-0} MB)"
            total_freed=$((total_freed + ${ql_size:-0}))
        fi
        # qlmanage Reset
        run_or_dry qlmanage -r 2>/dev/null
        report_add FIX "Font & QuickLook Cache rebuilt"
    else
        log STEP "   Font/QuickLook Cache: skipped (Config)"
    fi

    # Summary
    if [ "$total_freed" -gt 0 ]; then
        log FIX "   Deep Clean: ${total_freed} MB total freed"
        report_add FIX "Deep Clean: ${total_freed} MB freed"
    fi
}

#############################
# 6c. SPOTLIGHT FIX (Fix #120)
#############################

module_spotlight_fix() {
    if ! $SPOTLIGHT_FIX_ENABLED; then
        log STEP "Spotlight Fix: skipped (Config)"
        return 0
    fi

    log INFO "Spotlight diagnosis & repair..."
    local fixes=0

    # ── [1/5] mds/mds_stores CPU-Verbralso ──
    log STEP "   [1/5] mds CPU-Check..."
    local mds_cpu=$(ps -eo %cpu,comm 2>/dev/null | awk '/\/mds$/ {total+=$1} END {printf "%d", total+0}')
    local mds_stores_cpu=$(ps -eo %cpu,comm 2>/dev/null | awk '/mds_stores/ {total+=$1} END {printf "%d", total+0}')
    local mds_total=$((mds_cpu + mds_stores_cpu))

    if [ "$mds_total" -gt "$SPOTLIGHT_MDS_CPU_THRESHOLD" ]; then
        log WARN "   mds CPU: ${mds_total}% (mds:${mds_cpu}% mds_stores:${mds_stores_cpu}%) > threshold ${SPOTLIGHT_MDS_CPU_THRESHOLD}%"

        # Check if Spotlight is actively indexing
        local indexing_status=$(mdutil -s / 2>/dev/null)
        if echo "$indexing_status" | grep -qi "Indexing enabled"; then
            # Determine if normal indexing or stuck
            local mds_pid=$(pgrep -x mds 2>/dev/null | head -1)
            if [ -n "$mds_pid" ]; then
                local mds_state=$(ps -p "$mds_pid" -o state= 2>/dev/null)
                if [ "$mds_state" = "R" ] || [ "$mds_state" = "R+" ]; then
                    log STEP "   mds running actively (State: $mds_state) - normal indexing"
                    # CPU high because indexing active, no restart needed
                    log INFO "   Spotlight actively indexing (CPU: ${mds_total}%)"
                else
                    log WARN "   mds appears stuck (State: ${mds_state:-?})"
                    if $NEEDS_SUDO; then
                        log FIX "   Restarting mds..."
                        run_or_dry sudo -n killall mds 2>/dev/null
                        sleep 2
                        log FIX "   mds restarted"
                        report_add FIX "Spotlight: mds restarted (stuck at ${mds_total}% CPU)"
                        fixes=$((fixes + 1))
                    else
                        log INFO "   Spotlight: mds at ${mds_total}% CPU (sudo for Restart needed)"
                    fi
                fi
            fi
        fi
    else
        log STEP "   mds CPU: ${mds_total}% (OK)"
    fi

    # ── [2/5] Spotlight Index-Status (only User-relevante Volumes) ──
    log STEP "   [2/5] Spotlight Index-Status..."
    local volumes_checked=0
    local volumes_broken=0
    while IFS= read -r vol; do
        [ -z "$vol" ] && continue
        # Skip internal APFS system volumes (no Spotlight expected)
        case "$vol" in
            /System/Volumes/VM|/System/Volumes/Preboot|/System/Volumes/Update)    continue ;;
            /System/Volumes/xarts|/System/Volumes/iSCPreboot|/System/Volumes/Hardware) continue ;;
            /System/Volumes/Data|/System/Volumes/Data/*)                          continue ;;
            /Library/Developer/CoreSimulator/Volumes/*)                           continue ;;
            # Recovery volumes always report mdutil errors (read-only) — reindexing
            # them every run is pointless noise
            /Volumes/Recovery|/System/Volumes/Recovery)                           continue ;;
        esac
        volumes_checked=$((volumes_checked + 1))
        local vol_status=$(mdutil -s "$vol" 2>/dev/null)
        if echo "$vol_status" | grep -qi "error\|invalid"; then
            volumes_broken=$((volumes_broken + 1))
            log ERROR "   $vol: Spotlight-Index with errors"
            if $SPOTLIGHT_REINDEX_ON_ERROR && $NEEDS_SUDO; then
                log FIX "   Reindexiere $vol..."
                run_or_dry sudo -n mdutil -E "$vol" 2>/dev/null
                run_or_dry sudo -n mdutil -i on "$vol" 2>/dev/null
                report_add FIX "Spotlight: $vol reindexiert"
                fixes=$((fixes + 1))
            else
                log INFO "   Spotlight-Index with errors: $vol"
            fi
        elif echo "$vol_status" | grep -qi "disabled"; then
            # Only warn for root volume, others may be intentionally disabled
            if [ "$vol" = "/" ]; then
                log WARN "   /: Spotlight disabled auf Root-Volume!"
                if $NEEDS_SUDO; then
                    run_or_dry sudo -n mdutil -i on / 2>/dev/null
                    log FIX "   Spotlight auf / enabled"
                    report_add FIX "Spotlight: Root-Volume enabled"
                    fixes=$((fixes + 1))
                else
                    log INFO "   Spotlight on / disabled (sudo to enable)"
                fi
            else
                log STEP "   $vol: Spotlight disabled (intentional?)"
            fi
        fi
    done < <(df -Hl 2>/dev/null | awk 'NR>1 && $NF ~ /^\// {print $NF}')
    log STEP "   ${volumes_checked} user volumes checked, ${volumes_broken} with errors"

    # ── [3/5] Spotlight database integrity ──
    log STEP "   [3/5] Spotlight DB integrity..."
    local spotlight_db="/.Spotlight-V100"
    if [ -d "$spotlight_db" ]; then
        local db_size=$(du -sm "$spotlight_db" 2>/dev/null | awk '{print $1}')
        [ -z "$db_size" ] && db_size=0
        if [ "$db_size" -gt 5120 ]; then
            log WARN "   Spotlight-DB ungewoehnlich gross: ${db_size} MB (>5 GB)"
            if $SPOTLIGHT_REINDEX_ON_ERROR && $NEEDS_SUDO; then
                log FIX "   Baue Spotlight-Index neu auf..."
                run_or_dry sudo -n mdutil -E / 2>/dev/null
                report_add FIX "Spotlight: Index neu aufgebaut (war ${db_size} MB)"
                fixes=$((fixes + 1))
            else
                log INFO "   Spotlight-DB: ${db_size} MB (rebuild recommended)"
            fi
        else
            log STEP "   Spotlight-DB: ${db_size} MB"
        fi
    else
        # No .Spotlight-V100 auf APFS ist normal (liegt in /var)
        local var_spotlight="/private/var/db/Spotlight-V100"
        if [ -d "$var_spotlight" ]; then
            local var_db_size=$(sudo -n du -sm "$var_spotlight" 2>/dev/null | awk '{print $1}')
            log STEP "   Spotlight-DB (APFS): ${var_db_size:-?} MB"
        else
            log STEP "   Spotlight-DB: Standard-Pfad"
        fi
    fi

    # ── [4/5] Brokene Spotlight-Plugins ──
    log STEP "   [4/5] Spotlight-Plugins..."
    local plugin_count=0
    local broken_plugins=0
    for plugin_dir in /Library/Spotlight "$HOME/Library/Spotlight"; do
        [ ! -d "$plugin_dir" ] && continue
        while IFS= read -r plugin; do
            [ -z "$plugin" ] && continue
            plugin_count=$((plugin_count + 1))
            # Plugin-Binary checking
            if [ -f "$plugin/Contents/Info.plist" ] && ! plutil -lint "$plugin/Contents/Info.plist" &>/dev/null; then
                broken_plugins=$((broken_plugins + 1))
                log WARN "   Broken Plugin: $(basename "$plugin")"
            fi
        done < <(find "$plugin_dir" -maxdepth 1 -name "*.mdimporter" -type d 2>/dev/null)
    done
    if [ "$broken_plugins" -gt 0 ]; then
        log INFO "   Spotlight: ${broken_plugins} broken Plugins"
    else
        log STEP "   ${plugin_count} Plugins OK"
    fi

    # ── [5/5] Spotlight-Exclusions Audit ──
    log STEP "   [5/5] Spotlight-Exclusions Audit..."
    local excl_list=$(defaults read /.Spotlight-V100/VolumeConfiguration Exclusions 2>/dev/null)
    if [ -n "$excl_list" ]; then
        local excl_count=$(echo "$excl_list" | grep -c '"' 2>/dev/null || echo 0)
        log STEP "   ${excl_count} Pfade von Spotlight fromgeschlossen"
    fi

    # Summary
    if [ "$fixes" -gt 0 ]; then
        log FIX "   Spotlight: ${fixes} repairs performed"
        report_add FIX "Spotlight Fix: ${fixes} repairs"
    else
        log INFO "   Spotlight: all OK"
        report_add SUCCESS "Spotlight: healthy"
    fi
}

#############################
# 6d. ICLOUD SYNC FIX (Fix #121)
#############################

module_icloud_fix() {
    if ! $ICLOUD_FIX_ENABLED; then
        log STEP "iCloud Fix: skipped (Config)"
        return 0
    fi

    log INFO "iCloud sync diagnosis & repair..."
    local fixes=0
    local warns=0
    local icloud_dir="$HOME/Library/Mobile Documents/com~apple~CloudDocs"

    # ── [1/6] Ghost folders in HOME ──
    if $ICLOUD_GHOST_DIRS_CLEAN; then
        log STEP "   [1/6] Ghost folders in HOME..."
        local ghost_count=0
        local ghost_list=""
        # Bekannte Folder die in HOME NICHT sein sollten (leere iCloud-Ghosts)
        # Skip .Trash and standard folders (Desktop, Documents etc.)
        while IFS= read -r dir; do
            [ -z "$dir" ] && continue
            local dirname=$(basename "$dir")
            # Skip system folders and known tools
            case "$dirname" in
                .Trash|.cache|.config|.local|.ssh|.gnupg|.meister|.claude|.ollama|.nvm|.npm) continue ;;
                Desktop|Documents|Downloads|Movies|Music|Pictures|Public|Library) continue ;;
                Applications|Sites|.CFUserTextEncoding) continue ;;
                go|miniforge3|Parallels|Venvs|.docker|.gradle|.cargo|.rustup) continue ;;
            esac
            # Nur wirklich leere Folder (no .DS_Store etc.)
            local content_count=$(find "$dir" -mindepth 1 -not -name ".DS_Store" -not -name ".localized" 2>/dev/null | head -1)
            if [ -z "$content_count" ]; then
                ghost_count=$((ghost_count + 1))
                ghost_list="${ghost_list}${dirname} "
                log WARN "     Ghost folder: ~/${dirname}"
                run_or_dry rmdir "$dir" 2>/dev/null || run_or_dry rm -rf "$dir" 2>/dev/null
            fi
        done < <(find "$HOME" -maxdepth 1 -type d -mindepth 1 2>/dev/null)
        if [ "$ghost_count" -gt 0 ]; then
            log FIX "   ${ghost_count} ghost folders removed: ${ghost_list}"
            report_add FIX "iCloud: ${ghost_count} ghost folders removed (${ghost_list})"
            fixes=$((fixes + 1))
        else
            log STEP "   No ghost folders"
        fi
    else
        log STEP "   [1/6] Ghost folders: skipped (Config)"
    fi

    # ── [2/6] Detect corrupt iCloud stubs ──
    if $ICLOUD_STUBS_SCAN; then
        log STEP "   [2/6] Corrupt iCloud stubs..."
        local stub_count=0
        # Scan-Pfade: Documents, Desktop, iCloud Drive
        local scan_paths="$HOME/Documents $HOME/Desktop"
        [ -d "$icloud_dir" ] && scan_paths="$scan_paths $icloud_dir"

        for scan_path in $scan_paths; do
            [ ! -d "$scan_path" ] && continue
            while IFS= read -r entry; do
                [ -z "$entry" ] && continue
                local links=$(stat -f%l "$entry" 2>/dev/null)
                local size=$(stat -f%z "$entry" 2>/dev/null)
                if [ "${links:-0}" = "65535" ] && [ "${size:-1}" = "0" ]; then
                    stub_count=$((stub_count + 1))
                    local relpath="${entry#$HOME/}"
                    if [ "$stub_count" -le 20 ]; then
                        log ERROR "     Corrupt: ~/${relpath} (links=65535 size=0)"
                    fi
                    if $ICLOUD_STUBS_DELETE; then
                        run_or_dry rm -rf "$entry" 2>/dev/null
                    fi
                fi
            done < <(find "$scan_path" -maxdepth 3 \( -type f -o -type d \) 2>/dev/null)
        done

        if [ "$stub_count" -gt 0 ]; then
            if $ICLOUD_STUBS_DELETE; then
                log FIX "   ${stub_count} corrupt Stubs removed"
                report_add FIX "iCloud: ${stub_count} corrupt Stubs removed"
                fixes=$((fixes + 1))
            else
                log WARN "   ${stub_count} corrupt stubs found (set ICLOUD_STUBS_DELETE=true to delete)"
                log INFO "   iCloud: ${stub_count} corrupt Stubs (Config: ICLOUD_STUBS_DELETE)"
                warns=$((warns + 1))
            fi
        else
            log STEP "   No corrupt stubs"
        fi
    else
        log STEP "   [2/6] Stubs-Scan: skipped (Config)"
    fi

    # ── [3/6] bird (iCloud-Daemon) Status ──
    log STEP "   [3/6] bird-Daemon Status..."
    local bird_cpu=$(ps -eo %cpu,comm 2>/dev/null | awk '/\/bird$/ {printf "%d", $1}')
    local bird_mem=$(ps -eo %mem,comm 2>/dev/null | awk '/\/bird$/ {printf "%.1f", $1}')
    local bird_pid=$(pgrep -x bird 2>/dev/null | head -1)

    if [ -n "$bird_pid" ]; then
        log STEP "   bird: PID ${bird_pid}, CPU ${bird_cpu:-0}%, MEM ${bird_mem:-0}%"

        if [ "${bird_cpu:-0}" -gt 50 ]; then
            log WARN "   bird CPU: ${bird_cpu}% (haengt possibleerweise)"
            if $ICLOUD_RESTART_BIRD; then
                log FIX "   Restarting bird..."
                run_or_dry killall bird 2>/dev/null
                sleep 3
                # bird will be auto-restarted by launchd
                if pgrep -x bird &>/dev/null; then
                    log FIX "   bird restarted"
                    report_add FIX "iCloud: bird restarted (CPU was ${bird_cpu}%)"
                    fixes=$((fixes + 1))
                else
                    log WARN "   bird was not auto-restarted"
                    log INFO "   iCloud: bird not restarted"
                fi
            else
                log INFO "   iCloud: bird CPU ${bird_cpu}%"
                warns=$((warns + 1))
            fi
        fi
    else
        log WARN "   bird daemon not active"
        log INFO "   iCloud: bird not active"
        warns=$((warns + 1))
    fi

    # ── [4/6] iCloud Drive Storage ──
    # Fix #139: Timeout for du/find on iCloud (fileproviderd can hang)
    log STEP "   [4/6] iCloud Drive Storage..."
    if [ -d "$icloud_dir" ]; then
        local icloud_size=$(timeout 10 du -sm "$icloud_dir" 2>/dev/null | awk '{print $1}')
        if [ $? -eq 124 ] || [ -z "$icloud_size" ]; then
            icloud_size=0
            log WARN "   iCloud Drive: du timeout (fileproviderd haengt?)"
        fi
        local icloud_files=$(timeout 10 find "$icloud_dir" -type f 2>/dev/null | wc -l)
        icloud_files=${icloud_files##* }
        log STEP "   iCloud Drive: ${icloud_size} MB lokal, ${icloud_files} Files"

        # Checkingn auf .icloud-Platzhalter (not herunterloadede Files)
        local placeholder_count=$(timeout 10 find "$icloud_dir" -name "*.icloud" -type f 2>/dev/null | wc -l)
        placeholder_count=${placeholder_count##* }
        if [ "${placeholder_count:-0}" -gt 0 ]; then
            log STEP "   ${placeholder_count} Files only in der Cloud (not lokal)"
        fi
    else
        log STEP "   iCloud Drive path not present"
    fi

    # ── [5/6] Orphaned CloudKit-Container ──
    if $ICLOUD_ORPHAN_CONTAINERS_WARN; then
        log STEP "   [5/6] Orphaned CloudKit-Container..."
        local orphan_containers=0
        local orphan_size_total=0
        local mobile_docs="$HOME/Library/Mobile Documents"
        if [ -d "$mobile_docs" ]; then
            # Batch: All Bundle-IDs einmal sammeln (spart ~50 mdfind-Forks)
            local installed_ids_file=$(mktemp)
            timeout 15 mdfind "kMDItemContentType == 'com.apple.application-bundle'" 2>/dev/null | \
                xargs mdls -name kMDItemCFBundleIdentifier 2>/dev/null | \
                awk -F'"' '/kMDItemCFBundleIdentifier/ && $2 != "" {print $2}' | \
                sort -u > "$installed_ids_file"

            while IFS= read -r container; do
                [ -z "$container" ] && continue
                local cname=$(basename "$container")
                # Skip Apple-owned containers and system folders
                [ "$cname" = "com~apple~CloudDocs" ] && continue
                [[ "$cname" == com~apple~* ]] && continue
                [ "$cname" = ".Trash" ] && continue
                # Container-Bundle-ID rekonstruieren (~ → .)
                local bundle_id=$(echo "$cname" | tr '~' '.')
                # Checkingn gegen gecachte Bundle-ID-Liste (grep instead of mdfind)
                if ! grep -qxF "$bundle_id" "$installed_ids_file" 2>/dev/null; then
                    # Checkingn ob Container Daten enthaelt
                    local container_size=$(timeout 5 du -sm "$container" 2>/dev/null | awk '{print $1}')
                    [ -z "$container_size" ] && container_size=0
                    if [ "$container_size" -gt 0 ]; then
                        orphan_containers=$((orphan_containers + 1))
                        orphan_size_total=$((orphan_size_total + container_size))
                        [ "$orphan_containers" -le 10 ] && log STEP "     Orphaned: ${cname} (${container_size} MB)"
                    fi
                fi
            done < <(find "$mobile_docs" -maxdepth 1 -type d -mindepth 1 2>/dev/null)

            if [ "$orphan_containers" -gt 0 ]; then
                log WARN "   ${orphan_containers} orphaned CloudKit-Container (~${orphan_size_total} MB)"
                # Fix #145: Always-on self-healing - always delete orphaned containers (no size limit)
                if $SELFHEAL_ICLOUD_CONTAINERS && ! $DRY_RUN; then
                    local cleaned_containers=0
                    while IFS= read -r container; do
                        [ -z "$container" ] && continue
                        local cname=$(basename "$container")
                        [ "$cname" = "com~apple~CloudDocs" ] && continue
                        [[ "$cname" == com~apple~* ]] && continue
                        [ "$cname" = ".Trash" ] && continue
                        local bundle_id=$(echo "$cname" | tr '~' '.')
                        if ! grep -qxF "$bundle_id" "$installed_ids_file" 2>/dev/null; then
                            local cs=$(timeout 5 du -sm "$container" 2>/dev/null | awk '{print $1}')
                            if [ "${cs:-0}" -gt 0 ]; then
                                rm -rf "$container" 2>/dev/null && cleaned_containers=$((cleaned_containers + 1))
                                log FIX "     Deleted: ${cname} (${cs} MB)"
                            fi
                        fi
                    done < <(find "$mobile_docs" -maxdepth 1 -type d -mindepth 1 2>/dev/null)
                    [ "$cleaned_containers" -gt 0 ] && report_add FIX "iCloud: ${cleaned_containers} orphaned Container deleted (~${orphan_size_total} MB)"
                else
                    log INFO "   iCloud: ${orphan_containers} orphaned Container (~${orphan_size_total} MB)"
                fi
                warns=$((warns + 1))
            else
                log STEP "   No orphaned containers"
            fi
            rm -f "$installed_ids_file"
        fi
    else
        log STEP "   [5/6] CloudKit-Container: skipped (Config)"
    fi

    # ── [6/6] Pending Sync + Stuck Downloads ──
    log STEP "   [6/6] Sync-Status..."
    local brctl_avail=false
    command_exists brctl && brctl_avail=true

    if $brctl_avail; then
        # brctl status mit timeout (kann at vielen Containern >60s dauern)
        local sync_status
        sync_status=$(timeout 15 brctl status 2>/dev/null | head -50)
        # ANSI-Codes from brctl-Output entfernen (verursachen Zaehl-Error)
        local clean_sync=$(echo "$sync_status" | sed $'s/\x1b\\[[0-9;]*m//g')
        local needs_sync_count=$(echo "$clean_sync" | grep -c "needs-sync" 2>/dev/null || echo 0)
        local sync_disabled_count=$(echo "$clean_sync" | grep -c "SYNC DISABLED" 2>/dev/null || echo 0)

        if [ "${needs_sync_count:-0}" -gt 5 ]; then
            log WARN "   ${needs_sync_count} containers waiting for sync"
            if $ICLOUD_RESTART_BIRD && [ "${needs_sync_count:-0}" -gt 20 ]; then
                log FIX "   Viele wartende Syncs - starting bird neu..."
                run_or_dry killall bird 2>/dev/null
                sleep 3
                report_add FIX "iCloud: bird restarted (${needs_sync_count} pending syncs)"
                fixes=$((fixes + 1))
            else
                log INFO "   iCloud: ${needs_sync_count} containers waiting for sync"
                warns=$((warns + 1))
            fi
        else
            log STEP "   Sync-Status: OK (${needs_sync_count:-0} pending)"
        fi

        if [ "${sync_disabled_count:-0}" -gt 0 ]; then
            log STEP "   ${sync_disabled_count} containers with disabled sync (uninstalled apps)"
        fi
    else
        log STEP "   brctl not available - Sync-Status skipped"
    fi

    # Summary
    if [ "$fixes" -gt 0 ]; then
        log FIX "   iCloud: ${fixes} repairs, ${warns} warnings"
    elif [ "$warns" -gt 0 ]; then
        log WARN "   iCloud: ${warns} warnings"
    else
        log INFO "   iCloud: all OK"
        report_add SUCCESS "iCloud Sync: healthy"
    fi
}

#############################
# 6e. macOS PERFORMANCE OPTIMIERUNG (Fix #93)
#############################

module_performance() {
    log INFO "macOS Performance Optimization..."
    local perf_fixes=0
    local perf_warns=0

    # Fix #110: ps-Output einmal cachen instead of 5x forken
    local _ps_rss_cache _ps_cpu_cache
    _ps_rss_cache=$(ps -eo rss=,pid=,comm=,uid= 2>/dev/null)
    _ps_cpu_cache=$(ps -eo %cpu=,pid=,comm= 2>/dev/null)

    # ── [1/8] DNS latency ──
    log STEP "   [1/8] DNS latency..."
    local dns_ms_raw=$(curl -so /dev/null -w "%{time_namelookup}" https://www.apple.com 2>/dev/null)
    local dns_ms_int=$(echo "${dns_ms_raw:-0} * 1000" | bc 2>/dev/null | cut -d. -f1)
    if [ "${dns_ms_int:-0}" -gt 100 ]; then
        log WARN "   DNS langsam: ${dns_ms_int}ms (>100ms)"
        log INFO "   DNS-Latenz: ${dns_ms_int}ms (transient)"
        perf_warns=$((perf_warns + 1))
    else
        log STEP "   DNS OK: ${dns_ms_int:-?}ms"
    fi

    # ── [2/8] SSD TRIM + SMART ──
    log STEP "   [2/8] SSD TRIM & SMART..."
    local disk_info=$(diskutil info disk0 2>/dev/null)
    local trim_status=$(echo "$disk_info" | awk -F: '/TRIM Support:/ {gsub(/^[ ]+/,"",$2); print $2}')
    if [ -n "$trim_status" ]; then
        if echo "$trim_status" | grep -qi "yes"; then
            log STEP "   TRIM: enabled"
        else
            log WARN "   TRIM: DISABLED (SSD performance degraded!)"
            log INFO "   SSD TRIM disabled"
            perf_warns=$((perf_warns + 1))
        fi
    fi
    local smart_status=$(echo "$disk_info" | awk -F: '/SMART Status:/ {gsub(/^[ ]+/,"",$2); print $2}')
    if [ -n "$smart_status" ]; then
        if echo "$smart_status" | grep -qi "Verified"; then
            log STEP "   SMART: Verified"
        else
            log ERROR "   SMART: $smart_status - DISK PRUEFEN!"
            report_add ERROR "SMART Status: $smart_status"
        fi
    fi
    # APFS Container Health
    local apfs_free=$(diskutil apfs list 2>/dev/null | awk '/Free Space:/ {print $NF; exit}')
    [ -n "$apfs_free" ] && log STEP "   APFS Free: $apfs_free"

    # ── [3/8] Spotlight Exclusions ──
    if $PERF_SPOTLIGHT_EXCLUDE; then
        log STEP "   [3/8] Spotlight Exclusions..."
        local spotlight_excluded=0
        local spotlight_dirs=(
            "$HOME/go/pkg"
            "$HOME/miniforge3"
            "$HOME/Venvs"
            "$HOME/.ollama/models"
            "$HOME/.cargo"
            "$HOME/.rustup"
            "$HOME/.npm"
            "$HOME/.gradle"
            "$HOME/.docker"
        )
        for sdir in "${spotlight_dirs[@]}"; do
            if [ -d "$sdir" ] && [ ! -f "$sdir/.metadata_never_index" ]; then
                run_or_dry touch "$sdir/.metadata_never_index"
                log FIX "   Spotlight: $(basename "$sdir") fromgeschlossen"
                spotlight_excluded=$((spotlight_excluded + 1))
            fi
        done
        [ "$spotlight_excluded" -gt 0 ] && {
            perf_fixes=$((perf_fixes + spotlight_excluded))
            report_add FIX "Spotlight: ${spotlight_excluded} Directories fromgeschlossen"
        }
    else
        log STEP "   [3/8] Spotlight Exclusions: skipped (Config)"
    fi

    # ── [4/8] CPU & thermal ──
    log STEP "   [4/8] CPU & thermal..."
    local cpu_hogs
    cpu_hogs=$(echo "$_ps_cpu_cache" | sort -rn | awk '$1>50.0 {printf "     PID %s: %s (%.0f%%)\n", $2, $3, $1}' | head -5)
    if [ -n "$cpu_hogs" ]; then
        log INFO "   CPU-Hogs (>50%, transient):"
        echo "$cpu_hogs" | while IFS= read -r line; do
            [ -n "$line" ] && log STEP "$line"
        done
    else
        log STEP "   No CPU-Hogs"
    fi
    local cpu_speed_limit=$(pmset -g therm 2>/dev/null | awk '/CPU_Speed_Limit/ {print $3}')
    if [ -n "$cpu_speed_limit" ] && [ "$cpu_speed_limit" -lt 100 ] 2>/dev/null; then
        log WARN "   Thermal Throttling! CPU auf ${cpu_speed_limit}% gedrosselt"
        log INFO "   CPU thermisch gedrosselt (${cpu_speed_limit}%)"
        perf_warns=$((perf_warns + 1))
    else
        log STEP "   No Thermal Throttling"
    fi

    # ── [5/8] WindowServer Performance ──
    log STEP "   [5/8] WindowServer..."
    local ws_cpu=$(echo "$_ps_cpu_cache" | awk '/WindowServer/ {print int($1)}')
    if [ "${ws_cpu:-0}" -gt 15 ]; then
        log INFO "   WindowServer: ${ws_cpu}% CPU (transient)"
    else
        log STEP "   WindowServer: ${ws_cpu:-0}% CPU"
    fi

    # ── [6/8] Swap analysis ──
    log STEP "   [6/8] Swap analysis..."
    local swap_info=$(sysctl -n vm.swapusage 2>/dev/null)
    local swap_used_perf=$(echo "$swap_info" | awk -F'[ =M]+' '{for(i=1;i<=NF;i++) if($i=="used") print $(i+1)}' | cut -d. -f1)
    local swap_total_perf=$(echo "$swap_info" | awk -F'[ =M]+' '{for(i=1;i<=NF;i++) if($i=="total") print $(i+1)}' | cut -d. -f1)
    [ -z "$swap_used_perf" ] && swap_used_perf=0
    if [ "$swap_used_perf" -gt 4096 ] 2>/dev/null; then
        log WARN "   Swap: ${swap_used_perf}/${swap_total_perf:-?} MB (hoch!)"
        log STEP "   Recommendation: close apps or upgrade RAM"
        log INFO "   Swap hoch: ${swap_used_perf} MB"
        perf_warns=$((perf_warns + 1))
    elif [ "$swap_used_perf" -gt 1024 ] 2>/dev/null; then
        log STEP "   Swap: ${swap_used_perf} MB (moderat)"
    else
        log STEP "   Swap: ${swap_used_perf} MB (low)"
    fi

    # ── [7/8] Disable unnecessary LaunchAgents ──
    if $PERF_DISABLE_AGENTS; then
        log STEP "   [7/8] LaunchAgents cleanup..."
        local disabled_agents=0
        for pattern in $PERF_DISABLE_AGENT_PATTERNS; do
            for plist in "$HOME/Library/LaunchAgents/"*"${pattern}"*".plist" ; do
                [ ! -f "$plist" ] && continue
                local agent_label=$(basename "$plist" .plist)
                # Checkingn ob loaded
                if launchctl list "$agent_label" &>/dev/null; then
                    run_or_dry launchctl bootout "gui/$(id -u)" "$plist"
                    log FIX "     LaunchAgent disabled: $agent_label"
                    disabled_agents=$((disabled_agents + 1))
                else
                    log STEP "     Agent already inactive: $agent_label"
                fi
            done
        done
        [ "$disabled_agents" -gt 0 ] && {
            report_add FIX "LaunchAgents: ${disabled_agents} disabled"
            perf_fixes=$((perf_fixes + 1))
        }
    else
        log STEP "   [7/8] LaunchAgents: skipped (Config)"
    fi

    # ── [8/8] Ollama Model Cleanup ──
    if $PERF_CLEAN_OLLAMA && command_exists ollama; then
        log STEP "   [8/8] Ollama Model Cleanup..."
        local ollama_was_running=false
        ollama_available && ollama_was_running=true

        # Ensure Ollama is running for rm
        if ! $ollama_was_running; then
            ollama serve &>/dev/null &
            sleep 3
        fi

        if ollama_available; then
            local installed_models=$(ollama list 2>/dev/null | awk 'NR>1 {print $1}')
            local removed_models=0
            for model in $installed_models; do
                local keep=false
                for keeper in $OLLAMA_KEEP_MODELS; do
                    if [ "$model" = "$keeper" ]; then
                        keep=true
                        break
                    fi
                done
                if ! $keep; then
                    run_or_dry ollama rm "$model"
                    log FIX "     Ollama model removed: $model"
                    removed_models=$((removed_models + 1))
                else
                    log STEP "     Keeping: $model"
                fi
            done
            # If Ollama was only temporarily started, stop it again
            if ! $ollama_was_running; then
                pkill ollama 2>/dev/null
                log STEP "     Ollama server stopped again (RAM freed)"
            fi
            [ "$removed_models" -gt 0 ] && {
                report_add FIX "Ollama: ${removed_models} models removed"
                perf_fixes=$((perf_fixes + 1))
                ollama_list_invalidate
            }
        else
            log WARN "   Ollama-Server unreachable - Cleanup skipped"
        fi
    else
        log STEP "   [8/8] Ollama Cleanup: skipped (Config/not installed)"
    fi

    # ── Summary ──
    log INFO "   Performance: ${perf_fixes} optimizations, ${perf_warns} recommendations"
    [ "$perf_fixes" -gt 0 ] && report_add FIX "Performance: ${perf_fixes} optimizations applied"
    [ "$perf_warns" -gt 0 ] && log INFO "   ${perf_warns} Recommendationen skipped (brauchen sudo/Config)"
    return 0
}

#############################
# 6b. SELF-HEALING PREFLIGHT
#############################

selfheal_preflight() {
    log INFO "Self-Healing Preflight Check..."

    if command_exists brew; then
        log STEP "   Checking Homebrew health..."
        if ! brew --prefix &>/dev/null; then
            log WARN "   Homebrew not responding"
            log INFO "   Homebrew reagiert not (brew --prefix failed)"
        else
            log STEP "   Homebrew OK"
        fi
    fi

    log STEP "   Checking DNS..."
    # dscacheutil uses the full macOS resolver chain (mDNSResponder, VPN split-DNS, /etc/resolver)
    _dns_ok() { dscacheutil -q host -a name "$1" 2>/dev/null | grep -q '^ip_address:'; }
    if ! _dns_ok apple.com; then
        log WARN "   DNS-Aufloesung failed"
        sudo -n dscacheutil -flushcache 2>/dev/null
        sudo -n killall -HUP mDNSResponder 2>/dev/null
        sleep 1
        if _dns_ok apple.com; then
            log FIX "   DNS after Flush OK"
            report_add FIX "DNS-Cache geleert (Preflight)"
        fi
    else
        log STEP "   DNS OK"
    fi

    local disk_pct=$(df -h / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    if [ "$disk_pct" -gt "$DISK_CRITICAL_THRESHOLD" ] 2>/dev/null; then
        log ERROR "   KRITISCH: Disk ${disk_pct}% voll!"
        log WARN "   Raeume Temp-Files auf..."
        rm -rf /private/var/tmp/* 2>/dev/null
        rm -rf "$HOME/Library/Caches"/* 2>/dev/null
        report_add FIX "Notfall-Cleanup at ${disk_pct}% Disk"
    elif [ "$disk_pct" -gt "$DISK_USAGE_THRESHOLD" ] 2>/dev/null; then
        log WARN "   Disk ${disk_pct}% used (threshold: ${DISK_USAGE_THRESHOLD}%)"
    else
        log STEP "   Disk OK (${disk_pct}%)"
    fi

    log INFO "   Preflight completed"
}

#############################
# 7. SYSTEM BENCHMARK (Fix #53)
#############################

BENCHMARK_DIR="$MEISTER_DIR/benchmarks"
BENCHMARK_INTERVAL=86400  # 24h in seconds
mkdir -p "$BENCHMARK_DIR" 2>/dev/null

benchmark_should_run() {
    local last_file="$BENCHMARK_DIR/last_run"
    [ ! -f "$last_file" ] && return 0
    local last_ts=$(cat "$last_file" 2>/dev/null || echo 0)
    local now=$(date +%s)
    [ $((now - last_ts)) -ge "$BENCHMARK_INTERVAL" ]
}

# Fix #106: date +%s%N does not work on macOS (returns "N" instead of nanoseconds)
# → perl or gdate for millisecond precision
_epoch_ms() {
    if command_exists gdate; then
        gdate +%s%N | cut -c1-13
    elif command_exists perl; then
        perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000'
    else
        echo "$(date +%s)000"
    fi
}

benchmark_cpu() {
    # Single-core: Pi calculation via bc (1000 digits)
    local start=$(_epoch_ms)
    echo "scale=1000; 4*a(1)" | bc -l > /dev/null 2>&1
    local end=$(_epoch_ms)
    local ms=$(( end - start ))
    [ "$ms" -le 0 ] && ms=1
    echo "$ms"
}

benchmark_disk_write() {
    local tmpf="$BENCHMARK_DIR/.disktest_$$"
    local start=$(_epoch_ms)
    dd if=/dev/zero of="$tmpf" bs=1m count=256 2>/dev/null
    sync
    local end=$(_epoch_ms)
    rm -f "$tmpf"
    local ms=$(( end - start ))
    [ "$ms" -le 0 ] && ms=1
    local mbps=$(( 256 * 1000 / ms ))
    echo "$mbps"
}

benchmark_disk_read() {
    local tmpf="$BENCHMARK_DIR/.disktest_read_$$"
    dd if=/dev/zero of="$tmpf" bs=1m count=256 2>/dev/null
    sync
    # Fix #118: purge braucht sudo
    sudo -n purge 2>/dev/null || true
    local start=$(_epoch_ms)
    dd if="$tmpf" of=/dev/null bs=1m 2>/dev/null
    local end=$(_epoch_ms)
    rm -f "$tmpf"
    local ms=$(( end - start ))
    [ "$ms" -le 0 ] && ms=1
    local mbps=$(( 256 * 1000 / ms ))
    echo "$mbps"
}

benchmark_network() {
    # Fix #87: Latenz + DNS in EINEM curl-Aufruf instead of zwei
    local curl_times
    curl_times=$(curl -so /dev/null -w "%{time_namelookup} %{time_connect}" \
        https://www.apple.com 2>/dev/null || echo "0 0")
    local dns_raw connect_raw
    read -r dns_raw connect_raw <<< "$curl_times"
    local lat_ms=$(echo "${connect_raw:-0} * 1000" | bc 2>/dev/null | cut -d. -f1)
    local dns_ms=$(echo "${dns_raw:-0} * 1000" | bc 2>/dev/null | cut -d. -f1)
    [ -z "$lat_ms" ] && lat_ms=0
    [ -z "$dns_ms" ] && dns_ms=0

    # Download-Speed: 10MB von Apple CDN
    local dl_speed="0"
    local dl_out
    dl_out=$(curl -so /dev/null -w "%{speed_download}" \
        "https://updates.cdn-apple.com/2019/cert/041-88431-20191011-3d8da658-dca4-4a5b-b67c-69e87e3571b2/InstallAssistant.pkg" \
        --max-time 10 --range 0-10485759 2>/dev/null || echo "0")
    if [ -n "$dl_out" ] && [ "$dl_out" != "0" ]; then
        dl_speed=$(echo "$dl_out / 1048576" | bc -l 2>/dev/null | cut -c1-5)
    fi
    [ -z "$dl_speed" ] && dl_speed="0"

    echo "${lat_ms} ${dns_ms} ${dl_speed}"
}

benchmark_memory() {
    local total_mb free_mb pressure swap_used_mb
    total_mb=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%d", $1/1048576}')
    # Fix #87: vm_stat EINMAL aufrufen, beide Werte in einem awk extrahieren
    local pagesize=$(sysctl -n hw.pagesize 2>/dev/null || echo 16384)
    local free_pages inactive_pages
    read -r free_pages inactive_pages <<< $(vm_stat 2>/dev/null | awk '
        /Pages free:/ {gsub(/\./,"",$3); f=$3}
        /Pages inactive:/ {gsub(/\./,"",$3); i=$3}
        END {print f+0, i+0}')
    free_mb=$(( (${free_pages:-0} + ${inactive_pages:-0}) * pagesize / 1048576 ))
    # Memory Pressure (1=normal, 2=warn, 4=critical)
    pressure=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo "0")
    swap_used_mb=$(LC_ALL=C sysctl -n vm.swapusage 2>/dev/null | awk -F'[ =M]+' '{for(i=1;i<=NF;i++) if($i=="used") {gsub(/,/,".",$((i+1))); printf "%d", $(i+1)}}')
    [ -z "$swap_used_mb" ] && swap_used_mb=0

    echo "${total_mb} ${free_mb} ${pressure} ${swap_used_mb}"
}

benchmark_security() {
    local filevault firewall gatekeeper sip xprotect
    # FileVault
    if fdesetup status 2>/dev/null | grep -q "On"; then
        filevault="ON"
    else
        filevault="OFF"
    fi
    # Firewall
    local fw_state
    fw_state=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || echo "")
    if echo "$fw_state" | grep -qi "enabled"; then
        firewall="ON"
    else
        firewall="OFF"
    fi
    # Gatekeeper
    if spctl --status 2>/dev/null | grep -q "enabled"; then
        gatekeeper="ON"
    else
        gatekeeper="OFF"
    fi
    # SIP (System Integrity Protection)
    if csrutil status 2>/dev/null | grep -q "enabled"; then
        sip="ON"
    else
        sip="OFF"
    fi
    # Fix #88: XProtect Version via pkgutil instead of system_profiler (~10s schneller)
    xprotect=$(pkgutil --pkg-info com.apple.pkg.XProtectPlistConfigData 2>/dev/null | awk '/version:/ {print $2}')
    [ -z "$xprotect" ] && xprotect=$(pkgutil --pkg-info com.apple.pkg.XProtectPayloads 2>/dev/null | awk '/version:/ {print $2}')
    [ -z "$xprotect" ] && xprotect="n/a"

    echo "${filevault} ${firewall} ${gatekeeper} ${sip} ${xprotect}"
}

benchmark_system_info() {
    local uptime_secs load1 load5 load15 thermal battery_pct battery_cycles battery_health
    # Uptime
    uptime_secs=$(sysctl -n kern.boottime 2>/dev/null | awk -F'[ ,=]+' '{for(i=1;i<=NF;i++) if($i=="sec") print $(i+1)}')
    if [ -n "$uptime_secs" ]; then
        local now=$(date +%s)
        uptime_secs=$((now - uptime_secs))
    else
        uptime_secs=0
    fi
    local uptime_days=$((uptime_secs / 86400))

    # Load Average
    read -r load1 load5 load15 <<< $(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2, $3, $4}')
    [ -z "$load1" ] && load1="0" && load5="0" && load15="0"

    # Thermal (macOS Sequoia+)
    thermal=$(pmset -g therm 2>/dev/null | awk '/CPU_Speed_Limit/ {print $3}' || echo "100")
    [ -z "$thermal" ] && thermal="100"

    # Battery (only MacBooks)
    battery_pct=""
    battery_cycles=""
    battery_health=""
    if pmset -g batt 2>/dev/null | grep -q "InternalBattery"; then
        battery_pct=$(pmset -g batt 2>/dev/null | grep -o '[0-9]*%' | head -1 | tr -d '%')
        # Fix #87: ioreg EINMAL aufrufen instead of dreimal (~3s gespart)
        local ioreg_cache
        ioreg_cache=$(ioreg -rc AppleSmartBattery 2>/dev/null)
        # Fix: Nur Top-Level-Keys matchen (^ + Leerzeichen + "), not innerhalb BatteryData-Blob
        battery_cycles=$(echo "$ioreg_cache" | awk '/^[[:space:]]+"CycleCount" =/ {print $NF}')
        battery_health=$(echo "$ioreg_cache" | awk -F'"' '/^[[:space:]]+"BatteryHealth" =/ {print $4}')
        [ -z "$battery_health" ] && battery_health=$(echo "$ioreg_cache" | awk '/^[[:space:]]+"MaxCapacity" =/ {print $NF}')
    fi
    [ -z "$battery_pct" ] && battery_pct="-"
    [ -z "$battery_cycles" ] && battery_cycles="-"
    [ -z "$battery_health" ] && battery_health="-"

    echo "${uptime_days} ${load1} ${load5} ${load15} ${thermal} ${battery_pct} ${battery_cycles} ${battery_health}"
}

benchmark_save_json() {
    local ts="$1" cpu_ms="$2" disk_w="$3" disk_r="$4"
    local net_lat="$5" net_dns="$6" net_dl="$7"
    local mem_total="$8" mem_free="$9" mem_pressure="${10}" swap_mb="${11}"
    local fv="${12}" fw="${13}" gk="${14}" sip_val="${15}" xp="${16}"
    local up_days="${17}" l1="${18}" l5="${19}" l15="${20}" therm="${21}"
    local batt_pct="${22}" batt_cyc="${23}" batt_hp="${24}"
    local date_str=$(date +%Y-%m-%d)
    local json_file="$BENCHMARK_DIR/${date_str}.json"

    if command_exists jq; then
        jq -n \
            --arg ts "$ts" \
            --argjson cpu "$cpu_ms" \
            --argjson disk_w "$disk_w" \
            --argjson disk_r "$disk_r" \
            --argjson net_lat "$net_lat" \
            --argjson net_dns "$net_dns" \
            --arg net_dl "$net_dl" \
            --argjson mem_total "$mem_total" \
            --argjson mem_free "$mem_free" \
            --argjson mem_pressure "$mem_pressure" \
            --argjson swap "$swap_mb" \
            --arg filevault "$fv" \
            --arg firewall "$fw" \
            --arg gatekeeper "$gk" \
            --arg sip "$sip_val" \
            --arg xprotect "$xp" \
            --argjson uptime_days "$up_days" \
            --arg load1 "$l1" \
            --arg load5 "$l5" \
            --arg load15 "$l15" \
            --arg thermal "$therm" \
            --arg battery_pct "$batt_pct" \
            --arg battery_cycles "$batt_cyc" \
            --arg battery_health "$batt_hp" \
            '{timestamp:$ts, cpu_ms:$cpu, disk_write_mbps:$disk_w, disk_read_mbps:$disk_r,
              net_latency_ms:$net_lat, net_dns_ms:$net_dns, net_download_mbps:$net_dl,
              mem_total_mb:$mem_total, mem_free_mb:$mem_free, mem_pressure:$mem_pressure, swap_mb:$swap,
              security:{filevault:$filevault, firewall:$firewall, gatekeeper:$gatekeeper, sip:$sip, xprotect:$xprotect},
              uptime_days:$uptime_days, load:{l1:$load1, l5:$load5, l15:$load15},
              thermal:$thermal, battery:{pct:$battery_pct, cycles:$battery_cycles, health:$battery_health}}' \
            > "$json_file"
    else
        cat > "$json_file" << JSONEOF
{"timestamp":"$ts","cpu_ms":$cpu_ms,"disk_write_mbps":$disk_w,"disk_read_mbps":$disk_r,"net_latency_ms":$net_lat,"net_dns_ms":$net_dns,"net_download_mbps":"$net_dl","mem_total_mb":$mem_total,"mem_free_mb":$mem_free,"mem_pressure":$mem_pressure,"swap_mb":$swap_mb,"security":{"filevault":"$fv","firewall":"$fw","gatekeeper":"$gk","sip":"$sip_val","xprotect":"$xp"},"uptime_days":$up_days,"load":{"l1":"$l1","l5":"$l5","l15":"$l15"},"thermal":"$therm","battery":{"pct":"$batt_pct","cycles":"$batt_cyc","health":"$batt_hp"}}
JSONEOF
    fi
    echo "$json_file"
}

benchmark_compare() {
    local current_file="$1"
    # Letzten vorherigen Benchmark finden
    local prev_file
    prev_file=$(ls -1t "$BENCHMARK_DIR"/*.json 2>/dev/null | grep -v "$(basename "$current_file")" | head -1)
    [ -z "$prev_file" ] && { log STEP "   First benchmark - no comparison available"; return; }

    if ! command_exists jq; then return; fi

    local prev_cpu=$(jq -r '.cpu_ms' "$prev_file" 2>/dev/null || echo 0)
    local curr_cpu=$(jq -r '.cpu_ms' "$current_file" 2>/dev/null || echo 0)
    local prev_dw=$(jq -r '.disk_write_mbps' "$prev_file" 2>/dev/null || echo 0)
    local curr_dw=$(jq -r '.disk_write_mbps' "$current_file" 2>/dev/null || echo 0)
    local prev_date=$(jq -r '.timestamp' "$prev_file" 2>/dev/null | cut -d' ' -f1)

    log STEP "   Vergleich mit $prev_date:"

    # CPU: lower = besser
    if [ "$prev_cpu" -gt 0 ] && [ "$curr_cpu" -gt 0 ]; then
        local cpu_diff=$(( (curr_cpu - prev_cpu) * 100 / prev_cpu ))
        if [ "$cpu_diff" -gt 20 ]; then
            log WARN "   CPU: ${curr_cpu}ms vs ${prev_cpu}ms (+${cpu_diff}% langsamer!)"
            log INFO "   CPU-Benchmark ${cpu_diff}% langsamer als last Lauf"
        elif [ "$cpu_diff" -lt -10 ]; then
            log INFO "   CPU: ${curr_cpu}ms vs ${prev_cpu}ms (${cpu_diff}% schneller)"
        else
            log STEP "   CPU: ${curr_cpu}ms vs ${prev_cpu}ms (stabil)"
        fi
    fi

    # Disk Write: hoeher = besser
    if [ "$prev_dw" -gt 0 ] && [ "$curr_dw" -gt 0 ]; then
        local dw_diff=$(( (curr_dw - prev_dw) * 100 / prev_dw ))
        if [ "$dw_diff" -lt -30 ]; then
            log WARN "   Disk Write: ${curr_dw} MB/s vs ${prev_dw} MB/s (${dw_diff}% langsamer!)"
            log INFO "   Disk-Write ${dw_diff}% langsamer als last Lauf"
        else
            log STEP "   Disk Write: ${curr_dw} MB/s vs ${prev_dw} MB/s"
        fi
    fi
}

module_benchmark() {
    if ! benchmark_should_run; then
        log INFO "Benchmark: Already ran today - skipping"
        log STEP "   Next Benchmark in ~$((BENCHMARK_INTERVAL - ($(date +%s) - $(cat "$BENCHMARK_DIR/last_run" 2>/dev/null || echo 0)))) seconds"
        report_add SUCCESS "Benchmark: skip (already today)"
        return
    fi

    ensure_tool "jq" "jq" || { log WARN "jq not available, skipping benchmark"; return; }
    command_exists gdate || ensure_tool "gdate" "coreutils" 2>/dev/null
    log INFO "System-Benchmark & Security-Audit..."
    local ts=$(date +'%Y-%m-%d %H:%M:%S')

    # 1. CPU Benchmark
    log STEP "   CPU benchmark (Pi 1000 digits)..."
    local cpu_ms=$(benchmark_cpu)
    log STEP "   CPU: ${cpu_ms}ms"

    # 2. Disk I/O
    log STEP "   Disk-I/O Benchmark (256MB)..."
    local disk_w=$(benchmark_disk_write)
    local disk_r=$(benchmark_disk_read)
    log STEP "   Disk: Write ${disk_w} MB/s, Read ${disk_r} MB/s"

    # 3. Network
    log STEP "   Network-Benchmark..."
    local net_lat net_dns net_dl
    read -r net_lat net_dns net_dl <<< $(benchmark_network)
    log STEP "   Netz: Latenz ${net_lat}ms, DNS ${net_dns}ms, Download ${net_dl} MB/s"

    # 4. Memory
    log STEP "   Memory-Status..."
    local mem_total mem_free mem_pressure swap_mb
    read -r mem_total mem_free mem_pressure swap_mb <<< $(benchmark_memory)
    local mem_used=$((mem_total - mem_free))
    local mem_pct=$((mem_used * 100 / mem_total))
    local pressure_txt="normal"
    [ "$mem_pressure" -ge 2 ] 2>/dev/null && pressure_txt="WARNING"
    [ "$mem_pressure" -ge 4 ] 2>/dev/null && pressure_txt="KRITISCH"
    log STEP "   RAM: ${mem_used}/${mem_total} MB (${mem_pct}%), Pressure: ${pressure_txt}, Swap: ${swap_mb} MB"

    if [ "$mem_pressure" -ge 2 ] 2>/dev/null; then
        log INFO "   Memory Pressure: ${pressure_txt} (Swap: ${swap_mb} MB)"
    fi
    if [ "$swap_mb" -gt 4096 ] 2>/dev/null; then
        log INFO "   Hoher Swap: ${swap_mb} MB"
    fi

    # 5. Security Audit
    log STEP "   Security-Audit..."
    local fv fw gk sip_status xp
    read -r fv fw gk sip_status xp <<< $(benchmark_security)
    log STEP "   FileVault: $fv | Firewall: $fw | Gatekeeper: $gk | SIP: $sip_status"
    log STEP "   XProtect: $xp"

    # Security Self-Healing: auto-fixen was possible
    if [ "$fw" = "OFF" ] && ! $DRY_RUN; then
        sudo -n /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on 2>/dev/null && \
            { log FIX "   Firewall enabled"; report_add FIX "Firewall enabled"; fw="ON"; } || \
            log INFO "   Firewall disabled (sudo needed)"
    fi
    if [ "$gk" = "OFF" ] && ! $DRY_RUN; then
        sudo -n spctl --master-enable 2>/dev/null && \
            { log FIX "   Gatekeeper enabled"; report_add FIX "Gatekeeper reenabled"; gk="ON"; } || \
            log INFO "   Gatekeeper disabled (sudo needed)"
    fi
    [ "$fv" = "OFF" ] && log INFO "   FileVault disabled (manual via Systemeinstellungen)"
    [ "$sip_status" = "OFF" ] && log INFO "   SIP disabled (Recovery Mode needed)"

    # 6. System-Info
    log STEP "   System-Info..."
    local up_days l1 l5 l15 therm batt_pct batt_cyc batt_hp
    read -r up_days l1 l5 l15 therm batt_pct batt_cyc batt_hp <<< $(benchmark_system_info)
    log STEP "   Uptime: ${up_days} Tage | Load: ${l1}/${l5}/${l15} | Thermal: ${therm}%"
    if [ "$batt_pct" != "-" ]; then
        log STEP "   Batterie: ${batt_pct}% | Zyklen: ${batt_cyc} | Health: ${batt_hp}"
        if [ "$batt_pct" -lt 20 ] 2>/dev/null; then
            log INFO "   Batterie low: ${batt_pct}%"
        fi
    fi

    if [ "$up_days" -gt 30 ] 2>/dev/null; then
        log WARN "   System up for ${up_days} days - restart recommended"
        log INFO "   Uptime ${up_days} Tage"
    fi

    # 7. Resultse speichern (JSON)
    local json_file
    json_file=$(benchmark_save_json "$ts" "$cpu_ms" "$disk_w" "$disk_r" \
        "$net_lat" "$net_dns" "$net_dl" \
        "$mem_total" "$mem_free" "$mem_pressure" "$swap_mb" \
        "$fv" "$fw" "$gk" "$sip_status" "$xp" \
        "$up_days" "$l1" "$l5" "$l15" "$therm" \
        "$batt_pct" "$batt_cyc" "$batt_hp")
    log STEP "   Saved: $json_file"

    # 8. Vergleich mit letztem Lauf
    benchmark_compare "$json_file"

    # 9. Timestamp speichern
    date +%s > "$BENCHMARK_DIR/last_run"

    # 10. Clean up old benchmarks (>90 days)
    find "$BENCHMARK_DIR" -name "*.json" -mtime +90 -delete 2>/dev/null

    report_add SUCCESS "Benchmark: CPU ${cpu_ms}ms, Disk W:${disk_w}/R:${disk_r} MB/s, Net ${net_dl} MB/s"
    local sec_ok=0
    [ "$fv" = "ON" ] && sec_ok=$((sec_ok + 1))
    [ "$fw" = "ON" ] && sec_ok=$((sec_ok + 1))
    [ "$gk" = "ON" ] && sec_ok=$((sec_ok + 1))
    [ "$sip_status" = "ON" ] && sec_ok=$((sec_ok + 1))
    report_add SUCCESS "Security: ${sec_ok}/4 (FV:$fv FW:$fw GK:$gk SIP:$sip_status)"
}

#############################
# 7b. EXTRA MODULES (v5.6+)
#############################

module_healer() {
    log INFO "Healer — proactive auto-fixes..."
    local fixed=0

    # 1. Broken symlinks in PATH dirs (system bins need sudo)
    bw_phase "Healer: scanning symlinks"
    local sym_dirs=("$HOME/bin" "/opt/homebrew/bin" "/opt/homebrew/sbin" "/usr/local/bin")
    local needs_sudo=0
    for dir in "${sym_dirs[@]}"; do
        [ -d "$dir" ] || continue
        while IFS= read -r link; do
            [ -z "$link" ] && continue
            bw_phase "Healer: rm $(basename "$link")"
            log HEAL "   broken symlink: $link"
            fixed=$((fixed + 1))
            $DRY_RUN && continue
            if rm -f "$link" 2>/dev/null; then
                :
            elif sudo -n rm -f "$link" 2>/dev/null; then
                :
            else
                log WARN "     needs sudo — skipped (run: sudo rm -f '$link')"
                needs_sudo=$((needs_sudo + 1))
                fixed=$((fixed - 1))
            fi
        done < <(find "$dir" -maxdepth 1 -type l ! -exec test -e {} \; -print 2>/dev/null)
    done
    [ "$needs_sudo" -gt 0 ] && report_add WARN "Healer: ${needs_sudo} symlink(s) need sudo"

    # 2. Orphan LaunchAgents (plist points to missing binary) → quarantine
    bw_phase "Healer: LaunchAgents"
    local agent_dir="$HOME/Library/LaunchAgents"
    if [ -d "$agent_dir" ]; then
        while IFS= read -r plist; do
            [ -f "$plist" ] || continue
            local bin
            bin=$(plutil -extract ProgramArguments.0 raw -o - "$plist" 2>/dev/null)
            [ -z "$bin" ] && bin=$(plutil -extract Program raw -o - "$plist" 2>/dev/null)
            if [ -n "$bin" ] && [ ! -e "$bin" ]; then
                bw_phase "Healer: quarantine $(basename "$plist")"
                log HEAL "   orphan agent: $(basename "$plist") → missing $bin"
                fixed=$((fixed + 1))
                if ! $DRY_RUN; then
                    launchctl unload "$plist" 2>/dev/null
                    mv "$plist" "${plist}.disabled.$(date +%s)"
                fi
            fi
        done < <(find "$agent_dir" -maxdepth 1 -name "*.plist" 2>/dev/null)
    fi

    # 3. Corrupt user plist files → quarantine
    bw_phase "Healer: linting plists"
    while IFS= read -r plist; do
        [ -f "$plist" ] || continue
        if ! plutil -lint "$plist" >/dev/null 2>&1; then
            bw_phase "Healer: corrupt $(basename "$plist")"
            log HEAL "   corrupt plist: $(basename "$plist")"
            fixed=$((fixed + 1))
            $DRY_RUN || mv "$plist" "${plist}.bad.$(date +%s)"
        fi
    done < <(find "$HOME/Library/Preferences" -maxdepth 1 -name "*.plist" -size +0 2>/dev/null)

    # 4. Broken casks (app source gone) — auto-uninstall (app is already gone, cask is stale)
    bw_phase "Healer: scanning casks"
    if command_exists brew; then
        while IFS= read -r name; do
            [ -z "$name" ] && continue
            bw_phase "Healer: cask $name"
            local app_path
            app_path=$(brew info --cask "$name" 2>/dev/null | grep -oE "/Applications/[^']+\.app" | head -1)
            if [ -n "$app_path" ] && [ ! -d "$app_path" ]; then
                bw_phase "Healer: uninstall $name"
                log HEAL "   broken cask: $name (missing $app_path) — uninstalling"
                fixed=$((fixed + 1))
                $DRY_RUN || brew uninstall --cask --force "$name" >/dev/null 2>&1
            fi
        done < <(brew list --cask 2>/dev/null)
    fi

    # 5. DNS broken → flush
    bw_phase "Healer: DNS check"
    if ! dscacheutil -q host -a name apple.com 2>/dev/null | grep -q '^ip_address:'; then
        bw_phase "Healer: flushing DNS"
        log HEAL "   DNS resolution failing — flushing..."
        fixed=$((fixed + 1))
        if ! $DRY_RUN; then
            sudo -n dscacheutil -flushcache 2>/dev/null
            sudo -n killall -HUP mDNSResponder 2>/dev/null
        fi
    fi

    # 6. Stale Xcode DerivedData locks (>24h old)
    bw_phase "Healer: Xcode locks"
    local dd_dir="$HOME/Library/Developer/Xcode/DerivedData"
    if [ -d "$dd_dir" ]; then
        local stale_locks
        stale_locks=$(find "$dd_dir" -maxdepth 4 -name "*.lock" -mtime +1 2>/dev/null | wc -l | tr -d ' ')
        if [ "$stale_locks" -gt 0 ]; then
            log HEAL "   ${stale_locks} stale Xcode lock(s)"
            fixed=$((fixed + stale_locks))
            $DRY_RUN || find "$dd_dir" -maxdepth 4 -name "*.lock" -mtime +1 -delete 2>/dev/null
        fi
    fi

    # 7. Homebrew post-install cleanup if doctor flags linker issues
    bw_phase "Healer: brew doctor"
    if command_exists brew; then
        if brew doctor 2>&1 | grep -qE "Unbrewed header files|broken symlinks in"; then
            bw_phase "Healer: brew cleanup"
            log HEAL "   brew doctor flagged linker issues — cleanup..."
            fixed=$((fixed + 1))
            $DRY_RUN || brew cleanup -s >/dev/null 2>&1
        fi
    fi

    # 8. Orphan TCC entries — apps that were uninstalled but still hold
    # AppleEvents / Accessibility / etc. permissions.
    #
    # tccutil reset rejects unknown bundle ids (it asks LaunchServices to
    # resolve first) so it cannot clean entries for apps that are gone.
    # We first try tccutil; on failure we fall back to a direct DELETE on
    # the user TCC.db. Backup is taken before any DELETE; on sqlite error
    # the backup is restored. Path-based clients are skipped.
    bw_phase "Healer: TCC orphans"
    local user_tcc="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    if [ -f "$user_tcc" ] && command_exists sqlite3; then
        local tcc_backup_taken=false
        local tcc_backup="${user_tcc}.meister-backup-$(date +%Y%m%d_%H%M%S)"
        # Discover services dynamically — Apple keeps adding new TCC categories
        # (FileProviderDomain, BluetoothAlways, SystemPolicyDownloadsFolder, …).
        # A static list goes stale; DISTINCT covers everything that's actually
        # in the user's DB. Strip the kTCCService prefix for the loop body.
        local -a tcc_services
        while IFS= read -r svc_full; do
            [ -z "$svc_full" ] && continue
            tcc_services+=("${svc_full#kTCCService}")
        done < <(sqlite3 "$user_tcc" "SELECT DISTINCT service FROM access WHERE auth_value=2;" 2>/dev/null)
        for svc in "${tcc_services[@]}"; do
            local clients
            clients=$(sqlite3 "$user_tcc" \
                "SELECT client FROM access WHERE service='kTCCService${svc}' AND auth_value=2;" 2>/dev/null) \
                || continue
            [ -z "$clients" ] && continue
            while IFS= read -r client; do
                [ -z "$client" ] && continue
                tcc_client_exists "$client" && continue

                if [[ "$client" == /* ]]; then
                    log STEP "   orphan TCC ($svc) path-based: $client (skipped, manual)"
                    continue
                fi

                bw_phase "Healer: TCC reset $svc $client"
                log HEAL "   orphan TCC: $client → ${svc}"
                fixed=$((fixed + 1))
                $DRY_RUN && continue

                # Try the supported path first
                if tccutil reset "$svc" "$client" >/dev/null 2>&1; then
                    continue
                fi

                # Fallback: direct DELETE with one-shot backup
                if ! $tcc_backup_taken; then
                    if cp "$user_tcc" "$tcc_backup" 2>/dev/null; then
                        tcc_backup_taken=true
                        log STEP "     TCC.db backup → $(basename "$tcc_backup")"
                    else
                        log WARN "     could not back up TCC.db — skipping sqlite fallback"
                        fixed=$((fixed - 1))
                        continue
                    fi
                fi
                # busy_timeout — TCC.db uses rollback journaling (not WAL),
                # so concurrent tccd locks are possible; wait up to 5s.
                # Capture stderr only — PRAGMA echoes its old value to stdout,
                # which previously got mistaken for an error.
                local sql_err
                sql_err=$(sqlite3 -bail -cmd "PRAGMA busy_timeout=5000;" "$user_tcc" \
                    "DELETE FROM access WHERE service='kTCCService${svc}' AND client='${client//\'/\'\'}';" \
                    2>&1 >/dev/null)
                if [ -n "$sql_err" ]; then
                    log WARN "     sqlite DELETE failed: $sql_err — restoring backup"
                    cp "$tcc_backup" "$user_tcc" 2>/dev/null
                    fixed=$((fixed - 1))
                fi
            done <<< "$clients"
        done
        # Keep a small backup-rotation: prune all but the 3 newest meister-backups
        if $tcc_backup_taken; then
            ls -1t "${user_tcc}.meister-backup-"* 2>/dev/null | tail -n +4 | xargs -I{} rm -f "{}" 2>/dev/null
        fi
    fi

    if [ "$fixed" -gt 0 ]; then
        if $DRY_RUN; then
            log FIX "   Healer: ${fixed} fix(es) would apply (dry-run)"
        else
            log FIX "   Healer: ${fixed} fix(es) applied"
            report_add FIX "Healer: ${fixed} auto-fixes"
        fi
    else
        log STEP "   Nothing to heal — system clean"
    fi
}

# Local, writable, non-boot volumes that could serve as a TM destination.
# Output: "<mountpoint>|<free>" per line.
tm_candidate_volumes() {
    local vol fstype
    for vol in /Volumes/*; do
        [ -d "$vol" ] || continue
        case "$(basename "$vol")" in
            Recovery|Preboot|Update|.timemachine) continue ;;
        esac
        [ "$(readlink "$vol" 2>/dev/null)" = "/" ] && continue   # boot volume symlink
        [ -w "$vol" ] || continue
        # local APFS/HFS only — network mounts need URL-based setdestination
        fstype=$(mount | sed -n "s|^.* on ${vol} (\([a-z0-9]*\),.*|\1|p" | head -1)
        case "$fstype" in apfs|hfs) ;; *) continue ;; esac
        df -H "$vol" 2>/dev/null | awk -v v="$vol" 'NR==2 {print v"|"$4}'
    done
}

module_tm_health() {
    log INFO "Checking Time Machine..."
    if ! command_exists tmutil; then log STEP "   tmutil not available"; return 0; fi
    # NB: `tmutil destinationinfo` exits 0 even with NO destination ("No destinations
    # configured." on stdout) — the old exit-code check never detected this state.
    if tmutil destinationinfo 2>&1 | grep -qi "No destinations"; then
        # No destination = this Mac is a single copy. Surface candidates instead
        # of a quiet STEP line (Documents alone is 170 GB with no second copy).
        log WARN "   Time Machine NOT configured — no backup target, Mac is a single copy"
        report_add WARN "Time Machine: not configured (no backup!)"
        local candidates; candidates=$(tm_candidate_volumes)
        if [ -n "$candidates" ]; then
            log INFO "   Attached volumes usable as TM destination:"
            echo "$candidates" | while IFS='|' read -r cvol cfree; do
                log STEP "     $cvol (${cfree} free)"
            done
            log STEP "   Set up with: meister backup"
        else
            log STEP "   No suitable external volume attached (plug one in, then: meister backup)"
        fi
        return 0
    fi
    local latest; latest=$(tmutil latestbackup 2>/dev/null | tail -1)
    if [ -z "$latest" ]; then
        log WARN "   No Time Machine backups found"
        report_add WARN "Time Machine: no backups"
    else
        local bkup_date; bkup_date=$(basename "$latest" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
        if [ -n "$bkup_date" ]; then
            local bkup_epoch; bkup_epoch=$(date -j -f "%Y-%m-%d" "$bkup_date" +%s 2>/dev/null || echo 0)
            local age_days=$(( ($(date +%s) - bkup_epoch) / 86400 ))
            if [ "$age_days" -gt 7 ]; then
                log WARN "   Last backup ${age_days}d ago"
                report_add WARN "Time Machine: ${age_days}d old"
            else
                log STEP "   Last backup ${age_days}d ago (OK)"
            fi
        fi
    fi
    local snap_count; snap_count=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c com.apple.TimeMachine)
    log STEP "   Local snapshots on /: ${snap_count}"
}

module_battery() {
    local info; info=$(system_profiler SPPowerDataType 2>/dev/null)
    echo "$info" | grep -q "Battery Information" || { log STEP "No battery (desktop Mac)"; return 0; }
    log INFO "Checking battery..."
    local cycles condition max_cap
    cycles=$(echo "$info" | awk -F': ' '/Cycle Count/ {print $2; exit}' | tr -d ' ')
    condition=$(echo "$info" | awk -F': ' '/Condition/ {print $2; exit}' | sed 's/^ *//; s/ *$//')
    max_cap=$(echo "$info" | awk -F': ' '/Maximum Capacity/ {print $2; exit}' | tr -d ' ')
    log STEP "   Cycles: ${cycles:-?}, Condition: ${condition:-?}, Capacity: ${max_cap:-?}"
    if [ "${cycles:-0}" -gt 800 ] 2>/dev/null; then
        log WARN "   High cycle count (>800) — battery aging"
        report_add WARN "Battery: ${cycles} cycles"
    fi
    if [ -n "$condition" ] && [ "$condition" != "Normal" ]; then
        log WARN "   Condition: $condition"
        report_add WARN "Battery condition: $condition"
    fi
}

module_ios_sim() {
    command_exists xcrun || { log STEP "xcrun not available"; return 0; }
    local sim_dir="$HOME/Library/Developer/CoreSimulator/Devices"
    [ -d "$sim_dir" ] || { log STEP "No simulator dir"; return 0; }
    log INFO "Cleaning iOS simulators..."
    local before; before=$(du -sh "$sim_dir" 2>/dev/null | awk '{print $1}')
    if ! $DRY_RUN; then
        xcrun simctl delete unavailable 2>/dev/null
        xcrun simctl --set previews delete all 2>/dev/null || true
    fi
    local after; after=$(du -sh "$sim_dir" 2>/dev/null | awk '{print $1}')
    log STEP "   Simulators: ${before} → ${after}"
    [ "$before" != "$after" ] && report_add FIX "iOS Simulators: ${before} → ${after}"
    return 0
}

module_docker_prune() {
    command_exists docker || { log STEP "Docker not installed"; return 0; }
    docker info &>/dev/null || { log STEP "Docker daemon not running"; return 0; }
    log INFO "Docker prune..."
    local df_before; df_before=$(docker system df 2>/dev/null | tail -n +2)
    log STEP "$(echo "$df_before" | while IFS= read -r l; do echo "   $l"; done)"
    # Prune unused (no --volumes — too destructive for DB data)
    if ! $DRY_RUN; then
        docker system prune -af 2>&1 | tail -3 | while IFS= read -r l; do
            [ -n "$l" ] && log STEP "   $l"
        done
        report_add FIX "Docker: system prune -af"
    fi
}

module_panic_scan() {
    log INFO "Scanning kernel panics (last 7d)..."
    local panic_files; panic_files=$(find /Library/Logs/DiagnosticReports -maxdepth 1 -name "*.panic" -mtime -7 2>/dev/null | wc -l | tr -d ' ')
    if [ "$panic_files" -gt 0 ]; then
        log WARN "   ${panic_files} panic reports in last 7 days"
        report_add WARN "Kernel: ${panic_files} panics in 7d"
        find /Library/Logs/DiagnosticReports -maxdepth 1 -name "*.panic" -mtime -7 2>/dev/null | head -3 | while read -r f; do
            log STEP "     - $(basename "$f")"
        done
    else
        log STEP "   No kernel panics (7d)"
    fi
}

module_ssh_audit() {
    [ -d "$HOME/.ssh" ] || { log STEP "No ~/.ssh"; return 0; }
    log INFO "Auditing SSH keys..."
    local weak=0 total=0
    for key in "$HOME"/.ssh/*.pub; do
        [ -f "$key" ] || continue
        total=$((total + 1))
        local info; info=$(ssh-keygen -lf "$key" 2>/dev/null)
        [ -z "$info" ] && continue
        local bits; bits=$(echo "$info" | awk '{print $1}')
        local type; type=$(echo "$info" | grep -oE '\(([A-Z0-9]+)\)$' | tr -d '()')
        if [ "$type" = "DSA" ] || { [ "$type" = "RSA" ] && [ "${bits:-0}" -lt 3072 ]; }; then
            log WARN "   Weak: $(basename "$key") (${type}, ${bits} bit)"
            weak=$((weak + 1))
        fi
    done
    log STEP "   ${total} keys audited, ${weak} weak"
    [ "$weak" -gt 0 ] && report_add WARN "${weak} weak SSH keys"
    return 0
}

module_broken_symlinks() {
    log INFO "Checking broken symlinks..."
    local dirs=("$HOME/bin" "/opt/homebrew/bin" "/opt/homebrew/sbin" "/usr/local/bin")
    local total=0
    for dir in "${dirs[@]}"; do
        [ -d "$dir" ] || continue
        local broken
        broken=$(find "$dir" -maxdepth 1 -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l | tr -d ' ')
        if [ "$broken" -gt 0 ]; then
            log WARN "   ${broken} broken in $dir"
            total=$((total + broken))
        fi
    done
    [ "$total" -eq 0 ] && log STEP "   No broken symlinks"
    [ "$total" -gt 0 ] && report_add WARN "${total} broken symlinks"
    return 0
}

module_brew_age() {
    command_exists brew || { log STEP "brew missing"; return 0; }
    log INFO "Checking bottle ages..."
    local cellar; cellar=$(brew --cellar 2>/dev/null)
    [ -d "$cellar" ] || return 0
    local old_pkgs
    old_pkgs=$(find "$cellar" -maxdepth 2 -type d -mtime +180 2>/dev/null \
        | awk -F/ -v c="$cellar" '$0 != c {gsub(c"/",""); split($0, a, "/"); print a[1]}' \
        | sort -u)
    if [ -z "$old_pkgs" ]; then
        log STEP "   No bottles older than 180d"
        return 0
    fi
    local count; count=$(echo "$old_pkgs" | wc -l | tr -d ' ')
    log WARN "   ${count} bottles older than 180d (consider 'brew reinstall')"
    echo "$old_pkgs" | head -10 | while read -r p; do log STEP "     - $p"; done
    [ "$count" -gt 10 ] && log STEP "     ... +$((count - 10)) more"
    report_add WARN "${count} bottles >180d old"
}

module_launchd_orphans() {
    log INFO "Checking LaunchDaemons for orphans..."
    local orphans=0
    for plist in /Library/LaunchDaemons/*.plist; do
        [ -f "$plist" ] || continue
        local bin
        bin=$(plutil -extract ProgramArguments.0 raw -o - "$plist" 2>/dev/null)
        [ -z "$bin" ] && bin=$(plutil -extract Program raw -o - "$plist" 2>/dev/null)
        if [ -n "$bin" ] && [ ! -e "$bin" ]; then
            log WARN "   Orphan: $(basename "$plist") → missing $bin"
            orphans=$((orphans + 1))
        fi
    done
    [ "$orphans" -eq 0 ] && log STEP "   No orphan LaunchDaemons"
    [ "$orphans" -gt 0 ] && report_add WARN "${orphans} orphan LaunchDaemons"
    return 0
}

module_shell_history() {
    log INFO "Checking shell history sizes..."
    local files=("$HOME/.zsh_history" "$HOME/.bash_history")
    for f in "${files[@]}"; do
        [ -f "$f" ] || continue
        local size_mb=$(( $(stat -f%z "$f" 2>/dev/null || echo 0) / 1048576 ))
        if [ "$size_mb" -gt 10 ]; then
            log WARN "   $(basename "$f"): ${size_mb}MB — trim recommended"
            report_add WARN "$(basename "$f"): ${size_mb}MB"
        else
            log STEP "   $(basename "$f"): ${size_mb}MB OK"
        fi
    done
}

module_apfs_snapshots() {
    log INFO "Checking APFS local snapshots..."
    bw_phase "Snapshots: enumerating"
    command_exists tmutil || { log STEP "   tmutil missing"; return 0; }
    local snaps
    snaps=$(tmutil listlocalsnapshots / 2>/dev/null | grep com.apple.TimeMachine)
    [ -z "$snaps" ] && { log STEP "   No local snapshots"; return 0; }
    local count; count=$(echo "$snaps" | wc -l | tr -d ' ')
    local free_before; free_before=$(df -h / | awk 'NR==2{print $4}')
    log STEP "   ${count} local snapshots (free: $free_before)"
    # Thin to 5GB target purge
    bw_phase "Snapshots: thinning to 5GB"
    if ! $DRY_RUN; then
        tmutil thinlocalsnapshots / 5000000000 4 >/dev/null 2>&1
    fi
    local free_after; free_after=$(df -h / | awk 'NR==2{print $4}')
    local snaps_after; snaps_after=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c com.apple.TimeMachine)
    local thinned=$((count - snaps_after))
    if [ "$thinned" -gt 0 ]; then
        log FIX "   Thinned ${thinned} snapshots ($free_before → $free_after free)"
        report_add FIX "APFS snapshots: ${thinned} thinned"
    else
        log STEP "   No thinning needed ($free_after free)"
    fi
}

module_kext_audit() {
    log INFO "Auditing kernel extensions (non-Apple)..."
    bw_phase "Kexts: loading kextstat"
    local third_party
    third_party=$(kextstat -l 2>/dev/null | awk 'NR>1 && $6 !~ /^com\.apple\./ {print $6}')
    if [ -z "$third_party" ]; then
        log STEP "   No third-party kexts loaded"
        return 0
    fi
    local count; count=$(echo "$third_party" | wc -l | tr -d ' ')
    log STEP "   ${count} third-party kext(s) loaded:"
    echo "$third_party" | head -10 | while read -r k; do
        bw_phase "Kexts: $k"
        log STEP "     - $k"
    done
    report_add WARN "${count} third-party kexts (manual review — potential security risk)"
}

module_time_sync() {
    log INFO "Checking system time drift..."
    bw_phase "Time: querying NTP"
    command_exists sntp || { log STEP "   sntp missing"; return 0; }
    local offset
    offset=$(sntp time.apple.com 2>/dev/null | grep -oE '[+-][0-9]+\.[0-9]+' | head -1)
    [ -z "$offset" ] && { log STEP "   NTP check unavailable (offline?)"; return 0; }
    local abs_offset
    abs_offset=$(echo "$offset" | tr -d '+-' | awk -F. '{print $1}')
    log STEP "   Drift vs time.apple.com: ${offset}s"
    if [ "${abs_offset:-0}" -ge 2 ] 2>/dev/null; then
        bw_phase "Time: syncing"
        log HEAL "   Drift > 2s — syncing..."
        if ! $DRY_RUN && sudo -n sntp -sS time.apple.com >/dev/null 2>&1; then
            log FIX "   System time synced"
            report_add FIX "Time synced (was ${offset}s off)"
        fi
    fi
}

module_rendering_caches() {
    log INFO "Refreshing rendering caches (QuickLook + fonts)..."
    bw_phase "Caches: QuickLook reset"
    if ! $DRY_RUN; then
        qlmanage -r >/dev/null 2>&1
        qlmanage -r cache >/dev/null 2>&1
    fi
    log STEP "   QuickLook cache reset"
    bw_phase "Caches: font database"
    if ! $DRY_RUN; then
        atsutil databases -removeUser >/dev/null 2>&1
    fi
    log STEP "   Font database rebuilt"
    report_add FIX "QuickLook + font caches refreshed"
}

module_dev_caches() {
    log INFO "Cleaning dev-tool caches..."
    local total_before=0 total_after=0 cleaned=0
    # npm / pnpm / yarn
    if command_exists npm; then
        bw_phase "Dev caches: npm"
        local sz; sz=$(du -sk "$HOME/.npm" 2>/dev/null | awk '{print $1}'); total_before=$((total_before + ${sz:-0}))
        $DRY_RUN || npm cache clean --force >/dev/null 2>&1
        sz=$(du -sk "$HOME/.npm" 2>/dev/null | awk '{print $1}'); total_after=$((total_after + ${sz:-0}))
        cleaned=$((cleaned + 1))
    fi
    if command_exists pnpm; then
        bw_phase "Dev caches: pnpm"
        $DRY_RUN || pnpm store prune >/dev/null 2>&1
        cleaned=$((cleaned + 1))
    fi
    if command_exists yarn; then
        bw_phase "Dev caches: yarn"
        local sz; sz=$(du -sk "$HOME/Library/Caches/Yarn" 2>/dev/null | awk '{print $1}'); total_before=$((total_before + ${sz:-0}))
        $DRY_RUN || yarn cache clean >/dev/null 2>&1
        sz=$(du -sk "$HOME/Library/Caches/Yarn" 2>/dev/null | awk '{print $1}'); total_after=$((total_after + ${sz:-0}))
        cleaned=$((cleaned + 1))
    fi
    # pip
    if command_exists pip3; then
        bw_phase "Dev caches: pip"
        local cache_dir; cache_dir=$(pip3 cache dir 2>/dev/null)
        local sz; sz=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}'); total_before=$((total_before + ${sz:-0}))
        $DRY_RUN || pip3 cache purge >/dev/null 2>&1
        sz=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}'); total_after=$((total_after + ${sz:-0}))
        cleaned=$((cleaned + 1))
    fi
    # cargo (no official prune, use cargo-cache if installed)
    if command_exists cargo; then
        bw_phase "Dev caches: cargo"
        local sz; sz=$(du -sk "$HOME/.cargo/registry" 2>/dev/null | awk '{print $1}'); total_before=$((total_before + ${sz:-0}))
        if command_exists cargo-cache && ! $DRY_RUN; then
            cargo cache --autoclean >/dev/null 2>&1
        fi
        sz=$(du -sk "$HOME/.cargo/registry" 2>/dev/null | awk '{print $1}'); total_after=$((total_after + ${sz:-0}))
        cleaned=$((cleaned + 1))
    fi
    # go modules
    if command_exists go; then
        bw_phase "Dev caches: go"
        local sz; sz=$(du -sk "$HOME/go/pkg/mod" 2>/dev/null | awk '{print $1}'); total_before=$((total_before + ${sz:-0}))
        $DRY_RUN || go clean -modcache >/dev/null 2>&1
        sz=$(du -sk "$HOME/go/pkg/mod" 2>/dev/null | awk '{print $1}'); total_after=$((total_after + ${sz:-0}))
        cleaned=$((cleaned + 1))
    fi
    local freed_mb=$(( (total_before - total_after) / 1024 ))
    log STEP "   ${cleaned} dev-cache(s) cleaned, ${freed_mb} MB freed"
    [ "$freed_mb" -gt 100 ] && report_add FIX "Dev caches: ${freed_mb} MB freed"
    return 0
}

module_node_modules_aged() {
    log INFO "Finding ancient node_modules..."
    bw_phase "node_modules: scanning ~/Developer"
    [ -d "$HOME/Developer" ] || { log STEP "   ~/Developer missing"; return 0; }
    local found=0 total_mb=0
    while IFS= read -r dir; do
        [ -d "$dir" ] || continue
        local mb; mb=$(du -sm "$dir" 2>/dev/null | awk '{print $1}')
        [ "${mb:-0}" -lt 50 ] 2>/dev/null && continue
        local project; project=$(dirname "$dir" | sed "s|$HOME/||")
        log STEP "     $project/node_modules: ${mb}MB (>180d unused)"
        found=$((found + 1))
        total_mb=$((total_mb + mb))
        [ "$found" -ge 20 ] && break
    done < <(find "$HOME/Developer" -maxdepth 5 -type d -name node_modules -mtime +180 -prune 2>/dev/null)
    if [ "$found" -gt 0 ]; then
        log WARN "   ${found} abandoned node_modules (~${total_mb} MB total) — run: find ~/Developer -name node_modules -mtime +180 -exec rm -rf {} +"
        report_add WARN "${found} ancient node_modules (${total_mb} MB)"
    else
        log STEP "   No ancient node_modules"
    fi
}

module_sleep_blockers() {
    log INFO "Sleep assertions (what keeps Mac awake)..."
    bw_phase "Sleep: querying assertions"
    local assertions
    assertions=$(pmset -g assertions 2>/dev/null | awk '/PreventUserIdleSystemSleep|PreventSystemSleep/ && / pid /' | sort -u | head -10)
    if [ -z "$assertions" ]; then
        log STEP "   No processes blocking sleep"
        return 0
    fi
    echo "$assertions" | while IFS= read -r line; do
        local pid name; pid=$(echo "$line" | grep -oE 'pid [0-9]+' | awk '{print $2}')
        name=$(echo "$line" | grep -oE 'pid [0-9]+\([^)]+\)' | sed 's/.*(\(.*\))/\1/')
        [ -z "$name" ] && [ -n "$pid" ] && name=$(ps -p "$pid" -o comm= 2>/dev/null)
        log STEP "     pid $pid ($name) — blocking sleep"
    done
    report_add WARN "$(echo "$assertions" | wc -l | tr -d ' ') sleep blocker(s) active"
}

module_launchservices_rebuild() {
    log INFO "Rebuilding LaunchServices (fix 'Open With' duplicates)..."
    bw_phase "LaunchServices: rebuilding DB"
    local lsreg="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
    [ -x "$lsreg" ] || { log STEP "   lsregister not found"; return 0; }
    if ! $DRY_RUN; then
        "$lsreg" -kill -r -domain local -domain system -domain user >/dev/null 2>&1
        log FIX "   LaunchServices DB rebuilt"
        report_add FIX "LaunchServices rebuilt"
    else
        log STEP "   [DRY-RUN] would rebuild"
    fi
}

module_dsstore_cleanup() {
    log INFO "Cleaning .DS_Store files..."
    bw_phase "DS_Store: scanning"
    local dirs=("$HOME/Developer" "$HOME/Documents" "$HOME/Desktop")
    local total=0
    for dir in "${dirs[@]}"; do
        [ -d "$dir" ] || continue
        local count; count=$(find "$dir" -name .DS_Store 2>/dev/null | wc -l | tr -d ' ')
        if [ "$count" -gt 0 ]; then
            bw_phase "DS_Store: rm $dir ($count)"
            log STEP "   $dir: ${count} files"
            $DRY_RUN || find "$dir" -name .DS_Store -delete 2>/dev/null
            total=$((total + count))
        fi
    done
    [ "$total" -gt 0 ] && { log FIX "   ${total} .DS_Store removed"; report_add FIX "${total} .DS_Store files"; }
    [ "$total" -eq 0 ] && log STEP "   None found"
    return 0
}

# v5.21: Order check for DOCS_ORDER_ROOT (default ~/Documents)
module_docs_order() {
    $DOCS_ORDER_ENABLED || { log STEP "Docs order check disabled"; return 0; }
    local root="$DOCS_ORDER_ROOT"
    [ -d "$root" ] || { log STEP "   $root missing - skip"; return 0; }
    log INFO "Checking order in $root ..."

    # 1) Empty iCloud ghost folders ("X 2", "X 3") at root — before baseline
    #    check so removed ghosts never show up as new entries
    bw_phase "Docs: ghost folders"
    local ghosts; ghosts=$(find "$root" -mindepth 1 -maxdepth 1 -type d -name "* [2-9]" -empty 2>/dev/null)
    if [ -n "$ghosts" ]; then
        local gcount; gcount=$(printf '%s\n' "$ghosts" | wc -l | tr -d ' ')
        if $DOCS_ORDER_GHOST_CLEAN && ! $DRY_RUN; then
            printf '%s\n' "$ghosts" | while IFS= read -r g; do
                rmdir "$g" 2>/dev/null && log STEP "     rmdir: $(basename "$g")"
            done
            log FIX "   ${gcount} empty ghost folders removed"
            report_add FIX "${gcount} ghost folders in $(basename "$root")"
        else
            log WARN "   ${gcount} empty ghost folders (\"X 2\"/\"X 3\"):"
            printf '%s\n' "$ghosts" | head -5 | while IFS= read -r g; do log STEP "     - $(basename "$g")"; done
            report_add WARN "${gcount} ghost folders in $(basename "$root")"
        fi
    else
        log STEP "   No ghost folders"
    fi

    # 2) Root strangers: top-level entries vs learned baseline
    bw_phase "Docs: root entries"
    local baseline="$MEISTER_DIR/docs_order.baseline"
    local entries; entries=$(find "$root" -mindepth 1 -maxdepth 1 ! -name ".*" 2>/dev/null | sed 's|.*/||' | sort)
    if [ ! -f "$baseline" ]; then
        printf '%s\n' "$entries" > "$baseline"
        log STEP "   Baseline learned: $(printf '%s\n' "$entries" | wc -l | tr -d ' ') top-level entries → $baseline"
    else
        local new_entries
        new_entries=$(printf '%s\n' "$entries" | while IFS= read -r e; do
            [ -z "$e" ] && continue
            grep -qxF "$e" "$baseline" && continue
            [ -n "$DOCS_ORDER_KNOWN" ] && [[ "|$DOCS_ORDER_KNOWN|" == *"|$e|"* ]] && continue
            printf '%s\n' "$e"
        done)
        if [ -n "$new_entries" ]; then
            local ncount; ncount=$(printf '%s\n' "$new_entries" | wc -l | tr -d ' ')
            log WARN "   ${ncount} new top-level entries (not in baseline):"
            printf '%s\n' "$new_entries" | head -10 | while IFS= read -r e; do log STEP "     + $e"; done
            log STEP "   Accept: delete $baseline (re-learn) or add to DOCS_ORDER_KNOWN"
            report_add WARN "${ncount} new entries in $(basename "$root") root"
        else
            log STEP "   Root entries match baseline"
        fi
    fi

    # 3) _Inbox: unsorted files waiting for the filing daemon
    local inbox="$root/_Inbox"
    if [ -d "$inbox" ]; then
        local unsorted
        unsorted=$(find "$inbox" -type f ! -name ".*" ! -name "_HIER*" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$unsorted" -gt 0 ]; then
            log WARN "   _Inbox: ${unsorted} unsorted files"
            report_add WARN "_Inbox: ${unsorted} unsorted files"
        else
            log STEP "   _Inbox empty"
        fi
    fi

    # 4) Full-tree pass: dataless files (content only in iCloud) + corrupt stubs (65535 links)
    if $DOCS_ORDER_DATALESS_SCAN; then
        bw_phase "Docs: dataless scan"
        local scan
        scan=$(find "$root" -type f -not -path "*/.git/*" -print0 2>/dev/null \
            | xargs -0 stat -f "%b%t%z%t%l%t%N" 2>/dev/null \
            | awk -F'\t' '$3==65535 {print "STUB\t" $4}
                          $1==0 && $2>0 {n++; sz+=$2}
                          END {printf "SUM\t%d\t%.1f\n", n, sz/1e9}')
        local stubs; stubs=$(printf '%s\n' "$scan" | awk -F'\t' '$1=="STUB" {print $2}')
        local dl_count; dl_count=$(printf '%s\n' "$scan" | awk -F'\t' '$1=="SUM" {print $2}')
        local dl_gb; dl_gb=$(printf '%s\n' "$scan" | awk -F'\t' '$1=="SUM" {print $3}')
        if [ "${dl_count:-0}" -gt 0 ]; then
            log WARN "   ${dl_count} dataless files (~${dl_gb} GB exist only in iCloud)"
            if awk -v g="$dl_gb" -v t="$DOCS_ORDER_DATALESS_WARN_GB" 'BEGIN{exit !(g>=t)}'; then
                log WARN "   → content is NOT on this disk; no local backup covers it"
                report_add WARN "${dl_gb} GB in $(basename "$root") only in iCloud (dataless)"
            fi
        else
            log STEP "   No dataless files - all content local"
        fi
        if [ -n "$stubs" ]; then
            local scount; scount=$(printf '%s\n' "$stubs" | wc -l | tr -d ' ')
            log WARN "   ${scount} corrupt iCloud stubs (65535 links, need rm -rf):"
            printf '%s\n' "$stubs" | head -5 | while IFS= read -r s; do log STEP "     - $s"; done
            report_add WARN "${scount} corrupt iCloud stubs in $(basename "$root")"
        fi
    fi
}

module_tcc_privacy_audit() {
    log INFO "Privacy grants audit (camera/mic/screen recording)..."
    bw_phase "TCC: reading user DB"
    local tcc_db="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    [ -f "$tcc_db" ] || { log STEP "   User TCC DB not accessible"; return 0; }
    command_exists sqlite3 || { log STEP "   sqlite3 missing"; return 0; }
    local grants
    grants=$(sqlite3 "$tcc_db" "SELECT service, client FROM access WHERE auth_value IN (2,3)" 2>/dev/null)
    if [ -z "$grants" ]; then
        log STEP "   No user-level privacy grants"
        return 0
    fi
    local sensitive_count=0
    echo "$grants" | while IFS='|' read -r service client; do
        case "$service" in
            kTCCServiceCamera|kTCCServiceMicrophone|kTCCServiceScreenCapture|kTCCServiceSystemPolicyAllFiles)
                local label="${service#kTCCService}"
                log STEP "     $label: $client"
                ;;
        esac
    done
    sensitive_count=$(echo "$grants" | awk -F'|' '/kTCCServiceCamera|kTCCServiceMicrophone|kTCCServiceScreenCapture|kTCCServiceSystemPolicyAllFiles/' | wc -l | tr -d ' ')
    [ "$sensitive_count" -gt 0 ] && report_add WARN "${sensitive_count} apps with Camera/Mic/Screen/FDA grants"
    return 0
}

module_simfix() {
    log INFO "Fixing iOS Simulator..."
    command_exists xcrun || { log STEP "   xcrun missing (Xcode not installed)"; return 0; }

    bw_phase "SimFix: killing stale processes"
    local killed=0
    for proc in Simulator SimulatorTrampoline SimLaunchHost.arm64 simdiskimaged com.apple.CoreSimulator.CoreSimulatorService; do
        if pgrep -x "$proc" >/dev/null 2>&1; then
            log STEP "   kill: $proc"
            $DRY_RUN || killall -9 "$proc" 2>/dev/null
            killed=$((killed + 1))
        fi
    done
    [ "$killed" -eq 0 ] && log STEP "   No stale processes"

    bw_phase "SimFix: shutdown all devices"
    $DRY_RUN || xcrun simctl shutdown all 2>/dev/null

    bw_phase "SimFix: delete unavailable"
    local unavail_before
    unavail_before=$(xcrun simctl list devices 2>/dev/null | grep -c unavailable)
    if [ "$unavail_before" -gt 0 ]; then
        log STEP "   removing ${unavail_before} unavailable device(s)"
        $DRY_RUN || xcrun simctl delete unavailable 2>/dev/null
    fi

    bw_phase "SimFix: clear CoreSimulator caches"
    local cache_dir="$HOME/Library/Developer/CoreSimulator/Caches"
    if [ -d "$cache_dir" ]; then
        local cache_mb; cache_mb=$(du -sm "$cache_dir" 2>/dev/null | awk '{print $1}')
        log STEP "   caches: ${cache_mb} MB"
        $DRY_RUN || rm -rf "$cache_dir"/* 2>/dev/null
    fi

    bw_phase "SimFix: kickstart CoreSimulatorService"
    if ! $DRY_RUN; then
        if sudo -n launchctl kickstart -k "system/com.apple.CoreSimulator.CoreSimulatorService" 2>/dev/null; then
            log FIX "   CoreSimulatorService restarted"
        else
            log STEP "   (skipped kickstart — needs sudo)"
        fi
    fi

    bw_phase "SimFix: verifying"
    sleep 2
    if xcrun simctl list devices available >/dev/null 2>&1; then
        log FIX "   Simulator ready — launch: open -a Simulator"
        report_add FIX "iOS Simulator reset (try: open -a Simulator)"
    else
        log WARN "   simctl still unresponsive — try: sudo xcode-select -r"
        report_add WARN "Simulator still broken after reset"
    fi
}

module_receipts_audit() {
    log INFO "Auditing orphan installer receipts..."
    bw_phase "Receipts: enumerating"
    local receipts_dir="/var/db/receipts"
    [ -d "$receipts_dir" ] || return 0
    local total; total=$(find "$receipts_dir" -maxdepth 1 -name "*.plist" 2>/dev/null | wc -l | tr -d ' ')
    local orphans=0
    # An orphan receipt is for software whose install location no longer exists
    # (not bulletproof — but catches obvious ones)
    while IFS= read -r plist; do
        [ -f "$plist" ] || continue
        local pkg_id; pkg_id=$(basename "$plist" .plist)
        local install_loc; install_loc=$(pkgutil --pkg-info "$pkg_id" 2>/dev/null | awk -F': ' '/location:/ {print $2}')
        if [ -n "$install_loc" ] && [ "$install_loc" != "/" ] && [ ! -e "/$install_loc" ]; then
            orphans=$((orphans + 1))
        fi
    done < <(find "$receipts_dir" -maxdepth 1 -name "*.plist" 2>/dev/null | head -200)
    log STEP "   ${total} receipts total, ${orphans} potentially orphaned"
    [ "$orphans" -gt 0 ] && report_add WARN "${orphans} orphan receipts (review manually)"
    return 0
}

#############################
# 8. MAIN
#############################

keep_sudo() {
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
}

# Fix #16: Run-History
# v5.25: System time-travel snapshot. Captures the state that tends to change
# silently (apps, persistence, brew packages, key settings) into one sorted
# text file per run. `meister diff` compares the two newest.
SNAPSHOT_DIR="$MEISTER_DIR/snapshots"

write_system_snapshot() {
    mkdir -p "$SNAPSHOT_DIR"
    local f="$SNAPSHOT_DIR/snap-$(date +%Y%m%d-%H%M%S).txt"
    {
        echo "# meister snapshot $(date '+%Y-%m-%d %H:%M:%S')"
        echo "## apps"
        # name + version, one per line, from both app locations
        local appdir
        for appdir in /Applications "$HOME/Applications"; do
            [ -d "$appdir" ] || continue
            /bin/ls -1 "$appdir" 2>/dev/null | grep '\.app$' | while IFS= read -r a; do
                local v
                v=$(defaults read "$appdir/$a/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
                echo "app|${a%.app}|${v:-?}"
            done
        done
        echo "## launch"
        local d
        for d in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
            [ -d "$d" ] || continue
            /bin/ls -1 "$d" 2>/dev/null | grep '\.plist$' | while IFS= read -r p; do
                echo "launch|$d/$p"
            done
        done
        echo "## brew"
        if command_exists brew; then
            brew leaves 2>/dev/null | sed 's/^/formula|/'
            brew list --cask 2>/dev/null | sed 's/^/cask|/'
        fi
        echo "## settings"
        echo "setting|firewall|$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo '?')"
        echo "setting|sip|$(csrutil status 2>/dev/null | grep -o 'enabled\|disabled' | head -1)"
        echo "setting|hostname|$(scutil --get LocalHostName 2>/dev/null || echo '?')"
    } | LC_ALL=C sort > "$f"
    # keep the 30 most recent snapshots
    /bin/ls -1t "$SNAPSHOT_DIR"/snap-*.txt 2>/dev/null | tail -n +31 | while IFS= read -r old; do
        rm -f "$old"
    done
    echo "$f"
}

# v5.25: Maintenance score 0-100. Starts at 100, subtracts weighted penalties
# for what the run found. Echoes the score; caller stores it in MAINT_SCORE.
compute_score() {
    local score=100
    score=$((score - ${#REPORT_ERRORS[@]} * 8))      # errors hurt most
    score=$((score - ${#REPORT_WARNINGS[@]} * 3))     # warnings moderate
    # Standing security/backup facts weigh heavier than transient warnings
    printf '%s\n' "${REPORT_WARNINGS[@]}" | grep -qiE 'Time Machine|no backup|single copy' && score=$((score - 12))
    printf '%s\n' "${REPORT_WARNINGS[@]}" | grep -qiE 'XProtect|Gatekeeper|SIP|Firewall' && score=$((score - 6))
    printf '%s\n' "${REPORT_WARNINGS[@]}" | grep -qiE 'persistence|suspicious|VERDAECHTIG' && score=$((score - 6))
    [ "$score" -lt 0 ] && score=0
    [ "$score" -gt 100 ] && score=100
    echo "$score"
}

save_history() {
    local history_file="$MEISTER_DIR/history.log"
    local end_ts=$(date +%s)
    local total_secs=$((end_ts - SCRIPT_START_TIME))
    local total_mins=$((total_secs / 60))
    local total_secs_rem=$((total_secs % 60))
    local ts=$(date +'%Y-%m-%d %H:%M:%S')
    MAINT_SCORE=$(compute_score)
    # Top-3 slowest modules (INSIGHTS #7): the 27m-outlier run of 2026-07-04 was
    # unattributable without per-module timing in the history.
    local top_modules=""
    if [ ${#MODULE_TIMINGS[@]} -gt 0 ]; then
        top_modules=$(printf '%s\n' "${MODULE_TIMINGS[@]}" | sort -t'|' -k1,1 -rn | head -3 | \
            awk -F'|' '$1 > 0 {m=int($1/60); s=$1%60; d=(m>0) ? m"m"s"s" : s"s";
                       printf "%s%s %s", (out++ ? ", " : ""), $2, d}')
    fi
    # HEAL: field kept — older lines have it, dropping it broke parsers (INSIGHTS #5)
    # SCORE: field appended v5.25 (trailing → old parsers unaffected)
    echo "$ts | ${total_mins}m${total_secs_rem}s | OK:${#REPORT_SUCCESS[@]} FIX:${#REPORT_FIXED[@]} WARN:${#REPORT_WARNINGS[@]} ERR:${#REPORT_ERRORS[@]} HEAL:${HEAL_COUNT} SCORE:${MAINT_SCORE}${top_modules:+ | top: $top_modules}" >> "$history_file"
}

print_report() {
    local end_ts=$(date +%s)
    local total_secs=$((end_ts - SCRIPT_START_TIME))
    local total_mins=$((total_secs / 60))
    local total_secs_rem=$((total_secs % 60))

    # Score (v5.25): computed here if save_history hasn't run yet, with trend
    # arrow vs. the previous run in history.log
    [ -z "${MAINT_SCORE:-}" ] && MAINT_SCORE=$(compute_score)
    local score_color="$GREEN"
    [ "$MAINT_SCORE" -lt 80 ] && score_color="$YELLOW"
    [ "$MAINT_SCORE" -lt 55 ] && score_color="$RED"
    local prev_score trend=""
    prev_score=$(grep -oE 'SCORE:[0-9]+' "$MEISTER_DIR/history.log" 2>/dev/null | tail -1 | cut -d: -f2)
    if [ -n "$prev_score" ]; then
        if [ "$MAINT_SCORE" -gt "$prev_score" ]; then trend=" ↑$((MAINT_SCORE - prev_score))"
        elif [ "$MAINT_SCORE" -lt "$prev_score" ]; then trend=" ↓$((prev_score - MAINT_SCORE))"
        else trend=" ="; fi
    fi

    echo ""
    echo -e "${BLUE}====================================================${NC}"
    echo -e "${BLUE}   MEISTER REPORT (v1.0)${NC}"
    echo -e "${BLUE}   Runtime: ${total_mins}m ${total_secs_rem}s${NC}"
    echo -e "${BLUE}   Wartungs-Score: ${score_color}${MAINT_SCORE}/100${NC}${BLUE}${trend}${NC}"
    $DRY_RUN && echo -e "${YELLOW}   [DRY-RUN MODE]${NC}"
    echo -e "${BLUE}====================================================${NC}"

    # v5.24: topgrade-style per-module summary — one glance shows what ran,
    # what fixed something, what warned, what failed.
    if [ ${#MODULE_LEDGER[@]} -gt 0 ]; then
        echo ""
        local entry status name secs icon color dur
        for entry in "${MODULE_LEDGER[@]}"; do
            IFS='|' read -r status name secs <<< "$entry"
            case "$status" in
                FIX)  icon="↻"; color="$CYAN" ;;
                WARN) icon="⚠"; color="$YELLOW" ;;
                ERR)  icon="✗"; color="$RED" ;;
                *)    icon="✓"; color="$GREEN" ;;
            esac
            if [ "${secs:-0}" -ge 60 ]; then dur="$((secs / 60))m$((secs % 60))s"; else dur="${secs}s"; fi
            printf "  ${color}%s${NC} %-24s %7s\n" "$icon" "$name" "$dur"
        done
    fi

    # v5.24: AI-Healer front and center — what the healer did this run
    if [ "${HEAL_COUNT:-0}" -gt 0 ] && [ -f "$HEAL_LOG" ]; then
        echo -e "\n${CYAN}⚕ SELF-HEALING (${HEAL_COUNT} Events):${NC}"
        tail -n "$HEAL_COUNT" "$HEAL_LOG" | awk -F' \\| ' '{
            r = $4; if (r == "success" || r == "applied") r = "OK"
            printf "  - [%s] %s: %s\n", $2, $3, r
        }'
    fi

    if [ ${#REPORT_SUCCESS[@]} -gt 0 ]; then
        echo -e "\n${GREEN}SUCCESS (${#REPORT_SUCCESS[@]}):${NC}"
        printf '  - %s\n' "${REPORT_SUCCESS[@]}"
    fi
    if [ ${#REPORT_FIXED[@]} -gt 0 ]; then
        echo -e "\n${CYAN}FIXED (${#REPORT_FIXED[@]}):${NC}"
        printf '  - %s\n' "${REPORT_FIXED[@]}"
    fi
    if [ ${#REPORT_WARNINGS[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}WARNINGS (${#REPORT_WARNINGS[@]}):${NC}"
        printf '  - %s\n' "${REPORT_WARNINGS[@]}"
    fi
    if [ ${#REPORT_ERRORS[@]} -gt 0 ]; then
        echo -e "\n${RED}ERRORS (${#REPORT_ERRORS[@]}):${NC}"
        printf '  - %s\n' "${REPORT_ERRORS[@]}"
    fi

    # Fix #80: Extract total storage summary from FIXED entries
    local total_mb_freed=0
    for entry in "${REPORT_FIXED[@]}"; do
        local mb_val
        mb_val=$(echo "$entry" | grep -oE '[0-9]+ MB' | head -1 | awk '{print $1}')
        [ -n "$mb_val" ] && total_mb_freed=$((total_mb_freed + mb_val))
    done
    if [ "$total_mb_freed" -gt 0 ]; then
        echo -e "\n${GREEN}--- Storage Summary ---${NC}"
        if [ "$total_mb_freed" -gt 1024 ]; then
            local gb_freed=$(echo "scale=1; $total_mb_freed / 1024" | bc 2>/dev/null || echo "$((total_mb_freed / 1024))")
            echo "  Freed: ~${gb_freed} GB (${total_mb_freed} MB)"
        else
            echo "  Freed: ~${total_mb_freed} MB"
        fi
    fi

    echo -e "\n${BLUE}====================================================${NC}"
    echo "Log: $LOGFILE"
    echo "Config: $MEISTER_CONFIG"
}

health_dashboard() {
    echo -e "\n${MAGENTA}═══════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  Self-Healing Status (v1.0)${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════${NC}"
    if ollama_available; then
        echo -e "  Ollama:  ${GREEN}online${NC} ($OLLAMA_MODEL)"
        local model_count=$(( $(ollama_list_cached | awk 'NR>1' | wc -l) ))
        echo -e "  Models: ${model_count}"
    else
        echo -e "  Ollama:  ${RED}offline${NC}"
    fi
    echo -e "  Disk:    $(df -h / | awk 'NR==2 {print $5}') used ($(df -h / | awk 'NR==2 {print $4}') free)"
    local pc=$(( $(ls -1 "$MEISTER_DIR/patches/" 2>/dev/null | wc -l) ))
    echo -e "  Patches: ${pc} saved"
    if [ $pc -gt 0 ]; then
        echo -e "  Letzte:"
        ls -1t "$MEISTER_DIR/patches/" 2>/dev/null | head -5 | while IFS= read -r f; do
            echo -e "    - $f"
        done
    fi
    # Run History
    local history_file="$MEISTER_DIR/history.log"
    if [ -f "$history_file" ]; then
        local run_count=$(wc -l < "$history_file" | xargs)
        echo -e "  Runs:    ${run_count} total"
        echo -e "  Letzte Laeufe:"
        tail -5 "$history_file" | while IFS= read -r line; do
            echo -e "    $line"
        done
    fi
    echo -e "  Config:  $MEISTER_CONFIG"
    # Last Benchmark
    local last_bench=$(ls -1t "$BENCHMARK_DIR"/*.json 2>/dev/null | head -1)
    if [ -n "$last_bench" ] && command_exists jq; then
        local b_date=$(basename "$last_bench" .json)
        local b_cpu=$(jq -r '.cpu_ms' "$last_bench" 2>/dev/null)
        local b_dw=$(jq -r '.disk_write_mbps' "$last_bench" 2>/dev/null)
        local b_dr=$(jq -r '.disk_read_mbps' "$last_bench" 2>/dev/null)
        local b_fv=$(jq -r '.security.filevault' "$last_bench" 2>/dev/null)
        local b_fw=$(jq -r '.security.firewall' "$last_bench" 2>/dev/null)
        local b_gk=$(jq -r '.security.gatekeeper' "$last_bench" 2>/dev/null)
        local b_sip=$(jq -r '.security.sip' "$last_bench" 2>/dev/null)
        echo -e "  ─── Benchmark ($b_date) ───"
        echo -e "  CPU:     ${b_cpu}ms | Disk: W:${b_dw}/R:${b_dr} MB/s"
        echo -e "  Security: FV:$b_fv FW:$b_fw GK:$b_gk SIP:$b_sip"
        local bench_count=$(( $(ls -1 "$BENCHMARK_DIR"/*.json 2>/dev/null | wc -l) ))
        echo -e "  History: ${bench_count} Benchmarks saved"
    fi
    echo -e "${MAGENTA}═══════════════════════════════════════${NC}"
}

#############################
# 8. LOG-ANALYSE (Fix #27)
#############################

log_analysis() {
    local history_file="$MEISTER_DIR/history.log"
    [ ! -f "$history_file" ] && return
    local run_count=$(wc -l < "$history_file" | xargs)
    [ "$run_count" -lt 3 ] && return

    log INFO "Log-Analyse: Checking recurring problems..."

    # Warnings and Errors from letzten 5 Runs zaehlen.
    # Anchored timestamp: a greedy `^.*` also matched STEP lines that QUOTE old
    # WARN lines (the module's own output!) — recursive self-noise every run.
    local warn_re='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} - (WARN|ERROR) - '
    local recent_warns=""
    if [ -f "$LOGFILE" ]; then
        recent_warns=$(grep -E "$warn_re" "$LOGFILE" 2>/dev/null | \
            sed 's/^.\{19\} - [A-Z]* - //' | sort | uniq -c | sort -rn | head -10)
    fi

    # .old Log only when recent — March data is not a "recurring" problem in July
    if [ -f "${LOGFILE}.old" ] && [ -n "$(find "${LOGFILE}.old" -mtime -30 2>/dev/null)" ]; then
        local old_warns=$(grep -E "$warn_re" "${LOGFILE}.old" 2>/dev/null | \
            sed 's/^.\{19\} - [A-Z]* - //' | sort | uniq -c | sort -rn | head -10)
        if [ -n "$old_warns" ]; then
            recent_warns=$(echo -e "${recent_warns}\n${old_warns}" | sort -rn | head -10)
        fi
    fi

    if [ -n "$recent_warns" ]; then
        # Filter stale entries (uninstalled apps, old timeouts) + own report lines
        local recurring=$(echo "$recent_warns" | awk '$1 >= 3 {$1=""; print}' | sed 's/^ //' | \
            grep -vE "ORPHANED:.*not more installed|TIMEOUT on git remote|TIMEOUT bei git remote|Recurring problems|Wiederkehrende Probleme")
        if [ -n "$recurring" ]; then
            log INFO "   Recurring problems:"
            echo "$recurring" | while IFS= read -r line; do
                [ -n "$line" ] && log STEP "     - $line"
            done
        else
            log STEP "   No recurring problems (stale entries filtered)"
        fi
    fi

    # Own log hygiene (INSIGHTS #8): one-off tool logs >30d have no value
    find "$MEISTER_DIR" -maxdepth 1 -name "tb-sync-*.log" -mtime +30 -delete 2>/dev/null
    return 0
}

#############################
# 9. NOTIFICATIONS (Fix #28, #29)
#############################

# Fix #28: terminal-notifier mit Fallback
send_notification() {
    local title="$1"
    local message="$2"
    local subtitle="${3:-}"

    if command_exists terminal-notifier; then
        local tn_args=(-title "$title" -message "$message" -group "meister")
        [ -n "$subtitle" ] && tn_args+=(-subtitle "$subtitle")
        # Clickable: oeffnet Logfile
        tn_args+=(-open "file://$LOGFILE")
        terminal-notifier "${tn_args[@]}" 2>/dev/null
    else
        local osa_msg="$message"
        [ -n "$subtitle" ] && osa_msg="$subtitle: $message"
        osascript -e "display notification \"$osa_msg\" with title \"$title\"" 2>/dev/null
    fi
}

build_report_summary() {
    local summary="OK:${#REPORT_SUCCESS[@]} FIX:${#REPORT_FIXED[@]} WARN:${#REPORT_WARNINGS[@]} ERR:${#REPORT_ERRORS[@]}"
    local end_ts=$(date +%s)
    local total_mins=$(( (end_ts - SCRIPT_START_TIME) / 60 ))
    echo "Meister v${MEISTER_VERSION} | ${total_mins}min | $summary"
}

send_report_notification() {
    local summary=$(build_report_summary)
    local err_count=${#REPORT_ERRORS[@]}
    local fix_count=${#REPORT_FIXED[@]}

    local subtitle=""
    [ $err_count -gt 0 ] && subtitle="${err_count} Error!"
    [ $fix_count -gt 0 ] && subtitle="${subtitle} ${fix_count} Fixes"
    send_notification "Meister" "$summary" "$subtitle"
}

#############################
# 10. LAUNCHAGENT (Fix #30)
#############################

install_launchagent() {
    local script_path=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
    local plist_path="$HOME/Library/LaunchAgents/com.meister.maintenance.plist"
    local label="com.meister.maintenance"

    # Schedule bestimmen
    local interval_secs=604800  # default: weekly
    case "$LAUNCHAGENT_SCHEDULE" in
        daily)   interval_secs=86400 ;;
        weekly)  interval_secs=604800 ;;
    esac

    log INFO "Installing LaunchAgent ($LAUNCHAGENT_SCHEDULE)..."
    log STEP "   Script: $script_path"
    log STEP "   Plist:  $plist_path"

    # Bestehenden Agent stoppen
    if launchctl list 2>/dev/null | grep -q "$label"; then
        launchctl unload "$plist_path" 2>/dev/null
        log STEP "   Existing Agent stopped"
    fi

    mkdir -p "$HOME/Library/LaunchAgents"

    # Schedule-Key generieren
    local schedule_key=""
    if [ "$LAUNCHAGENT_SCHEDULE" = "monthly" ]; then
        schedule_key="<key>StartCalendarInterval</key>
    <dict><key>Day</key><integer>1</integer><key>Hour</key><integer>10</integer><key>Minute</key><integer>0</integer></dict>"
    else
        schedule_key="<key>StartInterval</key>
    <integer>${interval_secs}</integer>"
    fi

    cat > "$plist_path" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${script_path}</string>
    </array>
    ${schedule_key}
    <key>StandardOutPath</key>
    <string>${MEISTER_DIR}/launchagent.log</string>
    <key>StandardErrorPath</key>
    <string>${MEISTER_DIR}/launchagent_err.log</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
PLISTEOF

    launchctl load "$plist_path" 2>/dev/null
    if launchctl list 2>/dev/null | grep -q "$label"; then
        log FIX "LaunchAgent installed and loaded"
        log INFO "   Schedule: $LAUNCHAGENT_SCHEDULE"
        log INFO "   Uninstall: launchctl unload $plist_path && rm $plist_path"
        echo ""
        echo -e "${GREEN}LaunchAgent successful installed!${NC}"
        echo -e "  Schedule:      $LAUNCHAGENT_SCHEDULE"
        echo -e "  Plist:         $plist_path"
        echo -e "  Log:           $MEISTER_DIR/launchagent.log"
        echo -e "  Uninstall: launchctl unload $plist_path"
    else
        log ERROR "LaunchAgent konnte not loaded werden"
        echo -e "${RED}LaunchAgent Installation failed!${NC}"
    fi
}

# ── Dotfiles Sync Subcommands ──
# If first arg is a sync subcommand, delegate to meister-dotfiles and exit
_MEISTER_SCRIPT_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
_MEISTER_DOTFILES_SCRIPT=""
# Check next to script (dev), then ../libexec/tools (brew install)
for _candidate in "$_MEISTER_SCRIPT_DIR/tools/dotfiles.sh" "$_MEISTER_SCRIPT_DIR/../libexec/tools/dotfiles.sh"; do
    [ -f "$_candidate" ] && _MEISTER_DOTFILES_SCRIPT="$_candidate" && break
done
if [ -n "$_MEISTER_DOTFILES_SCRIPT" ]; then
    case "${1:-}" in
        push|up|u|pull|down|d|setup|init|scan|clone|bootstrap|boot|status|st|edit)
            exec bash "$_MEISTER_DOTFILES_SCRIPT" "$@"
            ;;
    esac
fi

# ── Interactive Menu (meister menu) — Dexter-style TUI ──
if [ "${1:-}" = "menu" ]; then
    _MENU_PRIMARY='\033[38;5;33m'   # blue
    _MENU_BOLD='\033[1m'
    _MENU_DIM='\033[2m'
    _MENU_NC='\033[0m'
    _MENU_REV='\033[7m'
    _MENU_CYAN='\033[0;36m'

    _menu_banner() {
        echo -e "${_MENU_PRIMARY}${_MENU_BOLD}"
        cat << 'BANNER'

███╗   ███╗███████╗██╗███████╗████████╗███████╗██████╗
████╗ ████║██╔════╝██║██╔════╝╚══██╔══╝██╔════╝██╔══██╗
██╔████╔██║█████╗  ██║███████╗   ██║   █████╗  ██████╔╝
██║╚██╔╝██║██╔══╝  ██║╚════██║   ██║   ██╔══╝  ██╔══██╗
██║ ╚═╝ ██║███████╗██║███████║   ██║   ███████╗██║  ██║
╚═╝     ╚═╝╚══════╝╚═╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
BANNER
        echo -e "${_MENU_NC}"
        echo -e "  ${_MENU_DIM}macOS Maintenance, Self-Healing & Dotfiles Sync${_MENU_NC}"
        echo -e "  ${_MENU_DIM}Version 4.2${_MENU_NC}"
        echo ""
    }

    # Menu items: label|command
    _MENU_ITEMS=(
        "Auto-Detect (recommended)|auto"
        "All Modules|all"
        "Health Dashboard|health"
        "Performance Tuning|perf"
        "─── Tools ───|separator"
        "Network Monitor (sniff)|sniff"
        "Network Top|ntop"
        "Disk Analyzer|disk"
        "Open Ports|ports"
        "DNS Leak Test|dns"
        "Battery Health|battery"
        "Startup Audit|startup"
        "Wi-Fi Diagnostics|wifi"
        "Process Monitor|top"
        "SSL Certificates|certs"
        "Thermal Monitor|thermal"
        "Speed Test|speed"
        "─── Modules ───|separator"
        "Xcode Clean|xcode"
        "Empty Trash|trash"
        "Clean Caches|caches"
        "Large Files|large"
        "Git Repos|git"
        "─── Dotfiles ───|separator"
        "Push Configs|push"
        "Pull Configs|pull"
        "Scan Configs|scan"
        "Bootstrap Machine|bootstrap"
        "Dotfiles Status|status"
        "─── ───|separator"
        "Dry-Run Mode|dryrun"
        "Quit|quit"
    )

    _menu_selected=0
    # Skip separators for initial selection
    while [[ "${_MENU_ITEMS[$_menu_selected]}" == *"|separator" ]]; do
        _menu_selected=$((_menu_selected + 1))
    done

    _menu_draw() {
        local total=${#_MENU_ITEMS[@]}
        for ((i=0; i<total; i++)); do
            local label="${_MENU_ITEMS[$i]%%|*}"
            local cmd="${_MENU_ITEMS[$i]##*|}"

            if [ "$cmd" = "separator" ]; then
                echo -e "  ${_MENU_DIM}${label}${_MENU_NC}"
                continue
            fi

            if [ "$i" -eq "$_menu_selected" ]; then
                echo -e "  ${_MENU_PRIMARY}${_MENU_BOLD}❯ ${label}${_MENU_NC}"
            else
                echo -e "    ${label}"
            fi
        done
        echo ""
        echo -e "  ${_MENU_DIM}↑/↓ navigate · enter select · q quit${_MENU_NC}"
    }

    _menu_next() {
        local total=${#_MENU_ITEMS[@]}
        local n=$((_menu_selected + 1))
        while [ "$n" -lt "$total" ]; do
            [[ "${_MENU_ITEMS[$n]}" != *"|separator" ]] && { _menu_selected=$n; return; }
            n=$((n + 1))
        done
    }

    _menu_prev() {
        local n=$((_menu_selected - 1))
        while [ "$n" -ge 0 ]; do
            [[ "${_MENU_ITEMS[$n]}" != *"|separator" ]] && { _menu_selected=$n; return; }
            n=$((n - 1))
        done
    }

    _menu_exec() {
        local cmd="${_MENU_ITEMS[$_menu_selected]##*|}"
        local self="$0"
        tput cnorm
        echo ""
        case "$cmd" in
            auto)      exec bash "$self" ;;
            all)       exec bash "$self" -a ;;
            health)    exec bash "$self" -H ;;
            perf)      exec bash "$self" -P ;;
            sniff)     exec bash "$self" sniff ;;
            ntop)      exec bash "$self" ntop ;;
            disk)      exec bash "$self" disk ;;
            ports)     exec bash "$self" ports ;;
            dns)       exec bash "$self" dns ;;
            battery)   exec bash "$self" battery ;;
            startup)   exec bash "$self" startup ;;
            wifi)      exec bash "$self" wifi ;;
            top)       exec bash "$self" top ;;
            certs)     exec bash "$self" certs ;;
            thermal)   exec bash "$self" thermal ;;
            speed)     exec bash "$self" speed ;;
            xcode)     exec bash "$self" -X ;;
            trash)     exec bash "$self" -T ;;
            caches)    exec bash "$self" -C ;;
            large)     exec bash "$self" -L ;;
            git)       exec bash "$self" -G ;;
            push)      exec bash "$self" push ;;
            pull)      exec bash "$self" pull ;;
            scan)      exec bash "$self" scan ;;
            bootstrap) exec bash "$self" bootstrap ;;
            status)    exec bash "$self" status ;;
            dryrun)    exec bash "$self" -n ;;
            quit)      exit 0 ;;
        esac
    }

    # TUI loop
    clear
    tput civis
    trap 'tput cnorm; exit 0' INT TERM
    while true; do
        tput home
        _menu_banner
        _menu_draw
        # Clear leftover lines from previous render
        tput ed
        # Read single keypress
        IFS= read -rsn1 key
        case "$key" in
            q) tput cnorm; exit 0 ;;
            "") _menu_exec ;;  # Enter
            $'\x1b')
                read -rsn2 -t 0.1 seq
                case "$seq" in
                    '[A') _menu_prev ;;  # Up
                    '[B') _menu_next ;;  # Down
                esac
                ;;
            k) _menu_prev ;;  # vim up
            j) _menu_next ;;  # vim down
        esac
    done
fi

# ── Live Network Monitor (meister sniff) ──
if [ "${1:-}" = "sniff" ]; then
    INTERVAL="${2:-3}"
    # Prefer physical interface (en0/en1) over VPN tunnel for bandwidth stats
    PHYS_IFACE=""
    for _if in en0 en1; do
        if ipconfig getifaddr "$_if" &>/dev/null; then PHYS_IFACE="$_if"; break; fi
    done
    IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
    [ -z "$IFACE" ] && [ -z "$PHYS_IFACE" ] && echo "No active interface" && exit 1
    BW_IFACE="${PHYS_IFACE:-$IFACE}"
    PHYS_IP=$(ipconfig getifaddr "$BW_IFACE" 2>/dev/null || echo "n/a")
    VPN_IFACE=""
    if [ -n "$PHYS_IFACE" ] && [ "$IFACE" != "$PHYS_IFACE" ]; then
        VPN_IFACE="$IFACE"
    fi
    trap 'tput cnorm; echo; exit 0' INT TERM

    tput civis
    while true; do
        # Bandwidth sample on physical interface
        local_s1=$(netstat -I "$BW_IFACE" -b 2>/dev/null | awk 'NR==2{print $7, $10}')
        sleep "$INTERVAL"
        local_s2=$(netstat -I "$BW_IFACE" -b 2>/dev/null | awk 'NR==2{print $7, $10}')
        in1=$(echo "$local_s1" | awk '{print $1}') out1=$(echo "$local_s1" | awk '{print $2}')
        in2=$(echo "$local_s2" | awk '{print $1}') out2=$(echo "$local_s2" | awk '{print $2}')
        in_kb=$(( (in2 - in1) / INTERVAL / 1024 ))
        out_kb=$(( (out2 - out1) / INTERVAL / 1024 ))

        # Connections
        established=$(netstat -an 2>/dev/null | grep -c ESTABLISHED)
        listening=$(netstat -an 2>/dev/null | grep -c LISTEN)

        # Top 10 processes by connection count
        top_procs=$(lsof -i -nP 2>/dev/null | awk 'NR>1{print $1}' | sort | uniq -c | sort -rn | head -10)

        # Top remote hosts
        top_hosts=$(lsof -i -nP 2>/dev/null | awk 'NR>1 && /ESTABLISHED/' | \
            grep -oE '>[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sed 's/>//' | sort | uniq -c | sort -rn | head -8)

        clear
        printf '\033[1;34m'
        printf '  ╔══════════════════════════════════════════════════╗\n'
        printf '  ║  MEISTER SNIFF — Live Network Monitor           ║\n'
        printf '  ╚══════════════════════════════════════════════════╝\n'
        printf '\033[0m\n'
        printf '  Interface: %s (%s)' "$BW_IFACE" "$PHYS_IP"
        [ -n "$VPN_IFACE" ] && printf '  VPN: %s' "$VPN_IFACE"
        printf '  Refresh: %ss\n\n' "$INTERVAL"

        printf '\033[1m  Bandwidth (%s)\033[0m\n' "$BW_IFACE"
        printf '  ↓ IN:  %s KB/s    ↑ OUT: %s KB/s\n\n' "$in_kb" "$out_kb"

        printf '\033[1m  Connections\033[0m\n'
        printf '  Established: %s    Listening: %s\n\n' "$established" "$listening"

        printf '\033[1m  Top Processes (connections)\033[0m\n'
        if [ -n "$top_procs" ]; then
            printf '  %6s  %s\n' "COUNT" "PROCESS"
            echo "$top_procs" | while IFS= read -r line; do
                cnt=$(echo "$line" | awk '{print $1}')
                name=$(echo "$line" | awk '{print $2}')
                printf '  %6s  %s\n' "$cnt" "$name"
            done
        fi
        printf '\n'

        printf '\033[1m  Top Remote Hosts\033[0m\n'
        if [ -n "$top_hosts" ]; then
            printf '  %6s  %s\n' "COUNT" "HOST"
            echo "$top_hosts" | while IFS= read -r line; do
                cnt=$(echo "$line" | awk '{print $1}')
                host=$(echo "$line" | awk '{print $2}')
                printf '  %6s  %s\n' "$cnt" "$host"
            done
        fi

        printf '\n\033[2m  Ctrl+C to exit\033[0m\n'
    done
fi

# ── Network Top (meister ntop) ──
if [ "${1:-}" = "ntop" ]; then
    INTERVAL="${2:-3}"
    trap 'tput cnorm; echo; exit 0' INT TERM
    tput civis
    while true; do
        # Sample with nettop delta mode
        raw=$(nettop -P -d -L 2 -n -x -j bytes_in,bytes_out -s "$INTERVAL" 2>/dev/null | tail -n +2)

        # Parse: process.pid, bytes_in, bytes_out → sort by total
        parsed=$(echo "$raw" | awk -F',' '
            $2 != "" {
                name=$2; sub(/\.[0-9]+$/,"",name);
                bi=$5+0; bo=$6+0; total=bi+bo;
                if(total>0) printf "%d\t%d\t%d\t%s\n", total, bi, bo, name
            }' | sort -rn | head -10)

        clear
        printf '\033[1;34m'
        printf '  ╔══════════════════════════════════════════════════╗\n'
        printf '  ║  MEISTER NTOP — Network Traffic Top 10          ║\n'
        printf '  ╚══════════════════════════════════════════════════╝\n'
        printf '\033[0m\n'

        # Header
        printf '  \033[1m%-20s  %10s  %10s  %10s\033[0m\n' "PROCESS" "IN" "OUT" "TOTAL"
        printf '  %-20s  %10s  %10s  %10s\n' "-------" "----" "-----" "------"

        # Find max for bar scaling
        max_total=$(echo "$parsed" | head -1 | cut -f1)
        [ -z "$max_total" ] || [ "$max_total" -eq 0 ] 2>/dev/null && max_total=1

        echo "$parsed" | while IFS=$'\t' read -r total bi bo name; do
            # Human-readable sizes
            if [ "$bi" -ge 1048576 ]; then
                bi_h=$(awk "BEGIN{printf \"%.1f MB\", $bi/1048576}")
            elif [ "$bi" -ge 1024 ]; then
                bi_h=$(awk "BEGIN{printf \"%.0f KB\", $bi/1024}")
            else
                bi_h="${bi} B"
            fi
            if [ "$bo" -ge 1048576 ]; then
                bo_h=$(awk "BEGIN{printf \"%.1f MB\", $bo/1048576}")
            elif [ "$bo" -ge 1024 ]; then
                bo_h=$(awk "BEGIN{printf \"%.0f KB\", $bo/1024}")
            else
                bo_h="${bo} B"
            fi
            if [ "$total" -ge 1048576 ]; then
                tot_h=$(awk "BEGIN{printf \"%.1f MB\", $total/1048576}")
            elif [ "$total" -ge 1024 ]; then
                tot_h=$(awk "BEGIN{printf \"%.0f KB\", $total/1024}")
            else
                tot_h="${total} B"
            fi

            bar_len=$((total * 25 / max_total))
            [ "$bar_len" -lt 1 ] && bar_len=1
            bar=$(printf '%*s' "$bar_len" '' | tr ' ' '█')
            printf '  %-20s  %10s  %10s  %10s  %s\n' "$name" "$bi_h" "$bo_h" "$tot_h" "$bar"
        done

        if [ -z "$parsed" ]; then
            echo "  (no network activity)"
        fi

        printf '\n\033[2m  Refresh: %ss  Ctrl+C to exit\033[0m\n' "$INTERVAL"
    done
fi

# ── Disk Analyzer (meister disk) ──
if [ "${1:-}" = "disk" ]; then
    TARGET="${2:-$HOME}"
    echo -e "\033[1;34m  MEISTER DISK — Top Space Usage: $TARGET\033[0m"
    echo ""
    printf '  %10s  %s\n' "SIZE" "DIRECTORY"
    printf '  %10s  %s\n' "----" "---------"
    # Collect data first, then scale bars relative to largest entry
    _disk_data=$(du -d 1 -h "$TARGET" 2>/dev/null | sort -rh | head -25 | while IFS=$'\t' read -r size dir; do
        [ "$dir" = "$TARGET" ] && continue
        name="${dir#$TARGET/}"
        mb=$(echo "$size" | awk '{
            s=$1; gsub(/,/,".",s); u=substr(s,length(s));
            n=substr(s,1,length(s)-1)+0;
            if(u=="T") n=n*1048576; else if(u=="G") n=n*1024; else if(u=="M") n=n; else if(u=="K") n=n/1024; else n=0;
            printf "%.0f", n
        }')
        printf '%s\t%s\t%s\n' "$mb" "$size" "$name"
    done)
    _max_mb=$(echo "$_disk_data" | head -1 | cut -f1)
    [ -z "$_max_mb" ] || [ "$_max_mb" -eq 0 ] 2>/dev/null && _max_mb=1
    echo "$_disk_data" | while IFS=$'\t' read -r mb size name; do
        bar_len=$((mb * 30 / _max_mb))
        [ "$bar_len" -lt 1 ] && [ "$mb" -gt 0 ] 2>/dev/null && bar_len=1
        bar=$(printf '%*s' "$bar_len" '' | tr ' ' '█')
        printf '  %10s  %-30s %s\n' "$size" "$name" "$bar"
    done
    echo ""
    df -h "$TARGET" 2>/dev/null | awk 'NR==2{printf "  Disk: %s used of %s (%s)\n", $3, $2, $5}'
    exit 0
fi

# ── Port Scanner (meister ports) ──
if [ "${1:-}" = "ports" ]; then
    echo -e "\033[1;34m  MEISTER PORTS — Open Ports & Listeners\033[0m"
    echo ""
    printf '  \033[1m%7s  %-6s  %-15s  %s\033[0m\n' "PORT" "PROTO" "PROCESS" "PID"
    printf '  %7s  %-6s  %-15s  %s\n' "------" "-----" "----------" "---"
    lsof -i -nP 2>/dev/null | awk 'NR>1 && /LISTEN/' | \
        awk '{split($9,a,":"); port=a[length(a)]; print port, $1, $2, $5}' | \
        sort -t' ' -k1 -n -u | while read -r port proc pid proto; do
            known=""
            case "$port" in
                22) known="SSH" ;; 53) known="DNS" ;; 80) known="HTTP" ;;
                443) known="HTTPS" ;; 3000) known="Dev" ;; 5432) known="Postgres" ;;
                6379) known="Redis" ;; 8080) known="HTTP-Alt" ;; 3306) known="MySQL" ;;
                27017) known="MongoDB" ;;
            esac
            [ -n "$known" ] && proc="$proc ($known)"
            printf '  %7s  %-6s  %-15s  %s\n' "$port" "$proto" "$proc" "$pid"
        done
    echo ""
    total=$(netstat -an 2>/dev/null | grep -c LISTEN)
    echo "  Total listening: $total"
    exit 0
fi

# ── DNS Leak Test (meister dns) ──
if [ "${1:-}" = "dns" ]; then
    echo -e "\033[1;34m  MEISTER DNS — DNS Leak Test\033[0m"
    echo ""
    # Current DNS servers
    echo -e "  \033[1mConfigured DNS Servers\033[0m"
    scutil --dns 2>/dev/null | awk '/nameserver\[/{print "  " $3}' | sort -u
    echo ""

    # System resolver
    echo -e "  \033[1mResolver Test\033[0m"
    for domain in apple.com google.com cloudflare.com github.com; do
        ip=$(dig +short "$domain" A 2>/dev/null | head -1)
        ms=$(dig "$domain" 2>/dev/null | awk '/Query time/{print $4}')
        if [ -n "$ip" ]; then
            printf '  \033[0;32m✓\033[0m %-20s → %-16s (%s ms)\n' "$domain" "$ip" "${ms:-?}"
        else
            printf '  \033[0;31m✗\033[0m %-20s → FAILED\n' "$domain"
        fi
    done
    echo ""

    # VPN leak check
    echo -e "  \033[1mVPN Leak Check\033[0m"
    default_if=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
    if [[ "$default_if" == utun* ]]; then
        echo -e "  \033[0;32m✓\033[0m Default route via VPN ($default_if)"
        # Check if DNS goes through VPN
        dns_server=$(scutil --dns 2>/dev/null | awk '/nameserver\[/{print $3; exit}')
        if [[ "$dns_server" == 10.* ]] || [[ "$dns_server" == 100.* ]] || [[ "$dns_server" == 172.16.* ]]; then
            echo -e "  \033[0;32m✓\033[0m DNS via private range ($dns_server) — no leak"
        else
            echo -e "  \033[1;33m⚠\033[0m DNS server is public ($dns_server) — possible leak"
        fi
    else
        echo "  No VPN detected (default route: $default_if)"
    fi

    # External IP
    echo ""
    echo -e "  \033[1mExternal IP\033[0m"
    ext_ip=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "timeout")
    echo "  $ext_ip"
    exit 0
fi

# ── Battery Health (meister battery) ──
if [ "${1:-}" = "battery" ]; then
    echo -e "\033[1;34m  MEISTER BATTERY — Battery Health\033[0m"
    echo ""
    if ! system_profiler SPPowerDataType &>/dev/null; then
        echo "  No battery (desktop Mac)"
        exit 0
    fi
    batt_info=$(system_profiler SPPowerDataType 2>/dev/null)
    cycle=$(echo "$batt_info" | awk -F': ' '/Cycle Count/{print $2}')
    condition=$(echo "$batt_info" | awk -F': ' '/Condition/{print $2}')
    max_cap=$(echo "$batt_info" | awk -F': ' '/Maximum Capacity/{print $2}')
    charging=$(echo "$batt_info" | awk -F': ' '/Charging/{print $2}' | head -1)
    connected=$(echo "$batt_info" | awk -F': ' '/Connected/{print $2}' | head -1)
    pct=$(pmset -g batt 2>/dev/null | grep -oE '[0-9]+%' | head -1)
    remaining=$(pmset -g batt 2>/dev/null | grep -oE '[0-9]+:[0-9]+' | head -1)
    temp=$(ioreg -r -n AppleSmartBattery 2>/dev/null | awk -F'= ' '/"Temperature" =/{printf "%.1f", $2/100; exit}')

    echo -e "  \033[1mStatus\033[0m"
    echo "  Charge:       ${pct:-n/a}"
    [ -n "$remaining" ] && echo "  Remaining:    $remaining"
    echo "  Connected:    ${connected:-n/a}"
    echo "  Charging:     ${charging:-n/a}"
    echo ""
    echo -e "  \033[1mHealth\033[0m"
    echo "  Max Capacity: ${max_cap:-n/a}"
    echo "  Cycle Count:  ${cycle:-n/a}"
    echo "  Condition:    ${condition:-n/a}"
    [ -n "$temp" ] && echo "  Temperature:  ${temp}°C"
    echo ""

    # Health assessment
    if [ -n "$cycle" ]; then
        cyc_num=${cycle//[^0-9]/}
        if [ "$cyc_num" -lt 300 ]; then
            echo -e "  \033[0;32m✓ Battery excellent ($cyc_num cycles)\033[0m"
        elif [ "$cyc_num" -lt 700 ]; then
            echo -e "  \033[1;33m⚠ Battery good ($cyc_num cycles)\033[0m"
        else
            echo -e "  \033[0;31m✗ Battery degraded ($cyc_num cycles — consider replacement)\033[0m"
        fi
    fi
    exit 0
fi

# ── Startup Audit (meister startup) ──
if [ "${1:-}" = "startup" ]; then
    echo -e "\033[1;34m  MEISTER STARTUP — Login Items & Launch Agents\033[0m"
    echo ""

    echo -e "  \033[1mLogin Items (User)\033[0m"
    osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | \
        tr ',' '\n' | sed 's/^ */  /' || echo "  (none or access denied)"
    echo ""

    echo -e "  \033[1mUser LaunchAgents (~\/Library\/LaunchAgents)\033[0m"
    ls ~/Library/LaunchAgents/*.plist 2>/dev/null | while read -r plist; do
        name=$(basename "$plist" .plist)
        loaded=$(launchctl list 2>/dev/null | grep -c "$name")
        if [ "$loaded" -gt 0 ]; then
            printf '  \033[0;32m●\033[0m %s\n' "$name"
        else
            printf '  \033[2m○\033[0m %s (not loaded)\n' "$name"
        fi
    done
    [ -z "$(ls ~/Library/LaunchAgents/*.plist 2>/dev/null)" ] && echo "  (none)"
    echo ""

    echo -e "  \033[1mSystem LaunchAgents (\/Library\/LaunchAgents)\033[0m"
    ls /Library/LaunchAgents/*.plist 2>/dev/null | while read -r plist; do
        name=$(basename "$plist" .plist)
        # Flag non-Apple
        if [[ "$name" != com.apple.* ]]; then
            printf '  \033[1;33m●\033[0m %s (third-party)\n' "$name"
        else
            printf '  \033[2m●\033[0m %s\n' "$name"
        fi
    done
    [ -z "$(ls /Library/LaunchAgents/*.plist 2>/dev/null)" ] && echo "  (none)"
    echo ""

    echo -e "  \033[1mSystem LaunchDaemons (\/Library\/LaunchDaemons) — third-party only\033[0m"
    ls /Library/LaunchDaemons/*.plist 2>/dev/null | while read -r plist; do
        name=$(basename "$plist" .plist)
        [[ "$name" == com.apple.* ]] && continue
        printf '  \033[1;33m●\033[0m %s\n' "$name"
    done
    echo ""

    total_user=$(ls ~/Library/LaunchAgents/*.plist 2>/dev/null | wc -l | tr -d ' ')
    total_sys=$(ls /Library/LaunchAgents/*.plist /Library/LaunchDaemons/*.plist 2>/dev/null | grep -cv 'com.apple' || echo 0)
    echo "  Summary: $total_user user agents, $total_sys third-party system agents/daemons"
    exit 0
fi

# ── Wi-Fi Diagnostics (meister wifi) ──
if [ "${1:-}" = "wifi" ]; then
    echo -e "\033[1;34m  MEISTER WIFI — Wi-Fi Diagnostics\033[0m"
    echo ""
    # Parse from system_profiler (works on all macOS versions incl. Apple Silicon)
    sp_out=$(system_profiler SPAirPortDataType 2>/dev/null)
    ssid=$(echo "$sp_out" | awk -F': ' '/Current Network Information:/{getline; gsub(/^[ \t]+|:$/,"",$0); print; exit}')
    # Extract from current network block
    net_block=$(echo "$sp_out" | sed -n '/Current Network Information:/,/Other Local/p')
    channel=$(echo "$net_block" | awk -F': ' '/Channel:/{print $2; exit}')
    security=$(echo "$net_block" | awk -F': ' '/Security:/{print $2; exit}')
    phy=$(echo "$net_block" | awk -F': ' '/PHY Mode:/{print $2; exit}')
    tx_rate=$(echo "$net_block" | awk -F': ' '/Transmit Rate:/{print $2; exit}')
    mcs=$(echo "$net_block" | awk -F': ' '/MCS Index:/{print $2; exit}')
    signal_noise=$(echo "$net_block" | awk -F': ' '/Signal \/ Noise:/{print $2; exit}')
    rssi=$(echo "$signal_noise" | awk -F'/' '{gsub(/[^0-9-]/,"",$1); print $1}')
    noise=$(echo "$signal_noise" | awk -F'/' '{gsub(/[^0-9-]/,"",$2); print $2}')
    mac=$(echo "$sp_out" | awk -F': ' '/MAC Address:/{print $2; exit}')
    country=$(echo "$sp_out" | awk -F': ' '/Country Code:/{print $2; exit}')

    snr=0
    [ -n "$rssi" ] && [ -n "$noise" ] && snr=$((rssi - noise))

    echo -e "  \033[1mConnection\033[0m"
    echo "  SSID:       ${ssid:-n/a}"
    echo "  PHY Mode:   ${phy:-n/a}"
    echo "  Channel:    ${channel:-n/a}"
    echo "  TX Rate:    ${tx_rate:-n/a} Mbps"
    echo "  MCS Index:  ${mcs:-n/a}"
    echo "  Security:   ${security:-n/a}"
    echo "  MAC:        ${mac:-n/a}"
    echo "  Country:    ${country:-n/a}"
    echo ""

    echo -e "  \033[1mSignal Quality\033[0m"
    echo "  Signal:     ${rssi:-n/a} dBm"
    echo "  Noise:      ${noise:-n/a} dBm"
    echo "  SNR:        ${snr} dB"
    if [ -n "$rssi" ]; then
        if [ "$rssi" -ge -50 ] 2>/dev/null; then
            echo -e "  Quality:    \033[0;32m████████████████████ Excellent\033[0m"
        elif [ "$rssi" -ge -60 ] 2>/dev/null; then
            echo -e "  Quality:    \033[0;32m███████████████░░░░░ Good\033[0m"
        elif [ "$rssi" -ge -70 ] 2>/dev/null; then
            echo -e "  Quality:    \033[1;33m██████████░░░░░░░░░░ Fair\033[0m"
        elif [ "$rssi" -ge -80 ] 2>/dev/null; then
            echo -e "  Quality:    \033[0;31m█████░░░░░░░░░░░░░░░ Weak\033[0m"
        else
            echo -e "  Quality:    \033[0;31m██░░░░░░░░░░░░░░░░░░ Very Weak\033[0m"
        fi
    fi
    echo ""

    # Nearby networks
    echo -e "  \033[1mNearby Networks\033[0m"
    printf '  %-30s  %-15s  %-10s  %s\n' "SSID" "CHANNEL" "SECURITY" "SIGNAL"
    echo "$sp_out" | sed -n '/Other Local Wi-Fi Networks:/,/^$/p' | \
        awk -F': ' '
        /^[[:space:]]+[A-Za-z0-9].*:$/ {gsub(/^[ \t]+|:$/,"",$0); name=$0}
        /Channel:/ {ch=$2}
        /Security:/ {sec=$2}
        /Signal \/ Noise:/ {sig=$2; printf "  %-30s  %-15s  %-10s  %s\n", name, ch, sec, sig}
        '
    exit 0
fi

# ── Process Monitor (meister top) ──
if [ "${1:-}" = "top" ]; then
    INTERVAL="${2:-3}"
    trap 'tput cnorm; echo; exit 0' INT TERM
    tput civis
    while true; do
        clear
        printf '\033[1;34m'
        printf '  ╔══════════════════════════════════════════════════╗\n'
        printf '  ║  MEISTER TOP — Process Monitor                  ║\n'
        printf '  ╚══════════════════════════════════════════════════╝\n'
        printf '\033[0m\n'

        # System overview
        load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2, $3, $4}')
        mem_press=$(memory_pressure 2>/dev/null | tail -1 || echo "n/a")
        cpu_usage=$(ps -A -o %cpu | awk '{s+=$1} END {printf "%.0f", s}')
        echo "  Load: $load  CPU: ${cpu_usage}%  $mem_press"
        echo ""

        # Top CPU
        printf '  \033[1mTop CPU\033[0m\n'
        printf '  %6s  %6s  %s\n' "%CPU" "%MEM" "PROCESS"
        ps -Arco pid,%cpu,%mem,comm 2>/dev/null | head -11 | tail -10 | \
            awk '{printf "  %6s  %6s  %s\n", $2, $3, $4}'
        echo ""

        # Top Memory
        printf '  \033[1mTop Memory\033[0m\n'
        printf '  %6s  %8s  %s\n' "%MEM" "RSS(MB)" "PROCESS"
        ps -Amro pid,%mem,rss,comm 2>/dev/null | head -11 | tail -10 | \
            awk '{n=$4; gsub(/.*\//,"",n); printf "  %6s  %8.0f  %s\n", $2, $3/1024, n}'
        echo ""

        # Energy (if available)
        printf '  \033[1mTop Energy (AppNap)\033[0m\n'
        ps -Aro pid,%cpu,comm 2>/dev/null | head -6 | tail -5 | \
            awk '{n=$3; gsub(/.*\//,"",n); if($2>1.0) printf "  \033[1;33m%6s%%\033[0m  %s\n", $2, n; else printf "  %6s%%  %s\n", $2, n}'

        printf '\n\033[2m  Refresh: %ss  Ctrl+C to exit\033[0m\n' "$INTERVAL"
        sleep "$INTERVAL"
    done
fi

# ── Certificate Checker (meister certs) ──
if [ "${1:-}" = "certs" ]; then
    echo -e "\033[1;34m  MEISTER CERTS — Certificate Checker\033[0m"
    echo ""

    # Check remote hosts from args, or defaults
    shift
    if [ $# -eq 0 ]; then
        hosts="github.com google.com apple.com localhost:443"
    else
        hosts="$*"
    fi

    echo -e "  \033[1mRemote Certificates\033[0m"
    printf '  %-25s  %-12s  %-20s  %s\n' "HOST" "DAYS LEFT" "ISSUER" "STATUS"
    printf '  %-25s  %-12s  %-20s  %s\n' "----" "---------" "------" "------"
    for host in $hosts; do
        port=443
        if [[ "$host" == *:* ]]; then
            port="${host#*:}"
            host="${host%%:*}"
        fi
        cert_info=$(echo | timeout 5 openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null)
        if [ -z "$cert_info" ]; then
            printf '  %-25s  %-12s  %-20s  \033[0;31m%s\033[0m\n' "$host:$port" "-" "-" "UNREACHABLE"
            continue
        fi
        expiry=$(echo "$cert_info" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
        issuer=$(echo "$cert_info" | openssl x509 -noout -issuer 2>/dev/null | sed 's/.*O = //;s/,.*//' | head -c 18)
        if [ -n "$expiry" ]; then
            exp_epoch=$(python3 -c "from datetime import datetime; d=datetime.strptime('$expiry','%b %d %H:%M:%S %Y %Z'); print(int(d.timestamp()))" 2>/dev/null || echo 0)
            now_epoch=$(date +%s)
            days_left=$(( (exp_epoch - now_epoch) / 86400 ))
            if [ "$days_left" -lt 0 ]; then
                status="\033[0;31mEXPIRED\033[0m"
            elif [ "$days_left" -lt 30 ]; then
                status="\033[1;33mEXPIRING\033[0m"
            else
                status="\033[0;32mOK\033[0m"
            fi
            printf "  %-25s  %-12s  %-20s  $status\n" "$host:$port" "${days_left}d" "$issuer"
        fi
    done
    echo ""

    # Local keychain certs expiring soon
    echo -e "  \033[1mLocal Keychain — Expiring within 30 days\033[0m"
    expiring=$(security find-certificate -a -p /Library/Keychains/System.keychain 2>/dev/null | \
        awk '/BEGIN CERT/,/END CERT/' | \
        while IFS= read -r line; do echo "$line"; done | \
        openssl x509 -noout -enddate -subject 2>/dev/null | paste - - | \
        while IFS= read -r combo; do
            exp=$(echo "$combo" | grep -oP 'notAfter=\K.*' 2>/dev/null || echo "$combo" | sed 's/.*notAfter=//;s/subject.*//')
            subj=$(echo "$combo" | sed 's/.*CN = //;s/,.*//' | head -c 30)
            exp_ep=$(date -jf "%b %d %T %Y %Z" "$exp" +%s 2>/dev/null || echo 0)
            now_ep=$(date +%s)
            dl=$(( (exp_ep - now_ep) / 86400 ))
            [ "$dl" -lt 30 ] && [ "$dl" -gt -365 ] && printf '  %-35s  %sd\n' "$subj" "$dl"
        done 2>/dev/null)
    if [ -n "$expiring" ]; then
        echo "$expiring"
    else
        echo "  (none)"
    fi
    exit 0
fi

# ── Thermal Monitor (meister thermal) ──
if [ "${1:-}" = "thermal" ]; then
    INTERVAL="${2:-2}"
    trap 'tput cnorm; echo; exit 0' INT TERM
    tput civis
    while true; do
        clear
        printf '\033[1;34m'
        printf '  ╔══════════════════════════════════════════════════╗\n'
        printf '  ║  MEISTER THERMAL — Temperature & Fan Monitor    ║\n'
        printf '  ╚══════════════════════════════════════════════════╝\n'
        printf '\033[0m\n'

        # Battery temperature (reliable on Apple Silicon)
        batt_temp=$(ioreg -r -n AppleSmartBattery 2>/dev/null | awk -F'= ' '/"Temperature" =/{printf "%.1f", $2/100; exit}')
        if [ -n "$batt_temp" ] && [ "$batt_temp" != "0.0" ]; then
            printf '  \033[1mTemperature\033[0m\n'
            batt_int=${batt_temp%.*}
            if [ "$batt_int" -ge 40 ] 2>/dev/null; then
                printf '  Battery:  \033[0;31m%s°C (HOT)\033[0m\n' "$batt_temp"
            elif [ "$batt_int" -ge 35 ] 2>/dev/null; then
                printf '  Battery:  \033[1;33m%s°C (warm)\033[0m\n' "$batt_temp"
            else
                printf '  Battery:  \033[0;32m%s°C\033[0m\n' "$batt_temp"
            fi
        else
            printf '  \033[1mTemperature\033[0m\n'
            printf '  Battery:  n/a\n'
        fi

        # Thermal pressure via pmset
        therm_warn=$(pmset -g therm 2>/dev/null | grep -c "No thermal warning")
        if [ "$therm_warn" -gt 0 ]; then
            printf '  Throttle: \033[0;32mNone\033[0m\n'
        else
            pmset_therm=$(pmset -g therm 2>/dev/null | grep -i "cpu_speed_limit" | awk '{print $NF}')
            if [ -n "$pmset_therm" ] && [ "$pmset_therm" -lt 100 ] 2>/dev/null; then
                printf '  Throttle: \033[0;31m%s%% (throttled!)\033[0m\n' "$pmset_therm"
            else
                printf '  Throttle: \033[0;32mNone\033[0m\n'
            fi
        fi

        # Fan speed
        echo ""
        printf '  \033[1mFans\033[0m\n'
        fans_found=false
        for key in $(ioreg -r -n AppleSMC 2>/dev/null | grep -oE '"F[0-9]Ac"' | tr -d '"' | sort -u); do
            speed=$(ioreg -r -n AppleSMC 2>/dev/null | awk -v k="\"$key\"" '$0 ~ k {print $NF; exit}')
            [ -n "$speed" ] && [ "$speed" != "0" ] && printf '  Fan %s: %s RPM\n' "${key:1:1}" "$speed" && fans_found=true
        done
        if ! $fans_found; then
            echo "  No active fans (Apple Silicon passive cooling or idle)"
        fi

        # CPU usage heatmap
        echo ""
        printf '  \033[1mCPU Load\033[0m\n'
        load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2, $3, $4}')
        ncpu=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
        printf '  Load: %s  (cores: %s)\n' "$load" "$ncpu"

        # Per-core approximation
        top -l 1 -n 0 -stats "" 2>/dev/null | grep "CPU usage" | \
            awk '{printf "  User: %s  Sys: %s  Idle: %s\n", $3, $5, $7}'

        # Memory pressure
        echo ""
        printf '  \033[1mMemory Pressure\033[0m\n'
        mem_out=$(memory_pressure 2>/dev/null | tail -3)
        echo "$mem_out" | sed 's/^/  /'

        printf '\n\033[2m  Refresh: %ss  Ctrl+C to exit\033[0m\n' "$INTERVAL"
        sleep "$INTERVAL"
    done
fi

# ── App Remover (meister remove <AppName>) ──
# AppCleaner-style uninstall: find the .app bundle, read its bundle-id, collect
# every leftover (Application Support, Caches, Preferences, Containers, Saved
# State, Logs, LaunchAgents, ...) and move it all to Trash (reversible).
#   --purge   permanent rm instead of Trash
#   --dry-run show what would be removed, change nothing
#   -y/--yes  skip the confirmation prompt
if [ "${1:-}" = "remove" ] || [ "${1:-}" = "uninstall" ]; then
    shift
    REMOVE_DRY=false; REMOVE_PURGE=false; REMOVE_YES=false; REMOVE_NAME=""
    for _a in "$@"; do
        case "$_a" in
            --dry-run|-n) REMOVE_DRY=true ;;
            --purge)      REMOVE_PURGE=true ;;
            -y|--yes)     REMOVE_YES=true ;;
            -*)           echo "[ERROR] Unknown flag: $_a"; echo "Usage: meister remove <AppName> [--dry-run] [--purge] [-y]"; exit 1 ;;
            *)            [ -z "$REMOVE_NAME" ] && REMOVE_NAME="$_a" || REMOVE_NAME="$REMOVE_NAME $_a" ;;
        esac
    done
    if [ -z "$REMOVE_NAME" ]; then
        echo "Usage: meister remove <AppName> [--dry-run] [--purge] [-y]"
        echo "  Uninstall an app bundle + all its leftover files."
        echo "  Default: moves everything to Trash (reversible).  --purge: permanent rm."
        exit 1
    fi

    echo -e "\033[1;34m  MEISTER REMOVE — Uninstall app + leftovers\033[0m"
    echo ""
    DRY_RUN=$REMOVE_DRY
    $DRY_RUN && echo "  [DRY-RUN — no changes]" && echo ""
    shopt -s nullglob

    _hkb() { awk -v k="${1:-0}" 'BEGIN{ if(k<1024) printf "%d KB",k; else if(k<1048576) printf "%.1f MB",k/1024; else printf "%.2f GB",k/1048576 }'; }

    # ── 1. Locate the .app bundle ──
    _name="${REMOVE_NAME%.app}"
    _app=""
    if [ -d "$REMOVE_NAME" ] && [[ "$REMOVE_NAME" == *.app ]]; then _app="$REMOVE_NAME"; fi
    if [ -z "$_app" ]; then
        for _cand in "/Applications/$_name.app" "$HOME/Applications/$_name.app" "/Applications/Utilities/$_name.app"; do
            [ -d "$_cand" ] && _app="$_cand" && break
        done
    fi
    if [ -z "$_app" ]; then
        _hits=()
        while IFS= read -r _line; do
            [ -d "$_line" ] || continue
            case "$_line" in /System/*) continue ;; esac
            _hits+=("$_line")
        done < <(mdfind "kMDItemContentType == 'com.apple.application-bundle' && kMDItemFSName == '$_name.app'c" 2>/dev/null)
        if [ "${#_hits[@]}" -eq 1 ]; then
            _app="${_hits[0]}"
        elif [ "${#_hits[@]}" -gt 1 ]; then
            log WARN "Multiple apps match '$_name' — pass the full path to disambiguate:"
            for _h in "${_hits[@]}"; do echo "    $_h"; done
            exit 1
        fi
    fi
    if [ -z "$_app" ]; then
        log ERROR "No app named '$_name' found (checked /Applications, ~/Applications, Spotlight)."
        if command -v brew >/dev/null 2>&1 && { brew list --cask "$_name" &>/dev/null || brew list --formula "$_name" &>/dev/null; }; then
            echo "  Hint: '$_name' is a Homebrew package — use:  brew uninstall $_name"
        fi
        exit 1
    fi
    case "$_app" in /System/*) log ERROR "Refusing to remove a system app: $_app"; exit 1 ;; esac

    # ── 2. Bundle identifier ──
    _bid="$(defaults read "$_app/Contents/Info" CFBundleIdentifier 2>/dev/null)"
    [ -z "$_bid" ] && _bid="$(mdls -name kMDItemCFBundleIdentifier -raw "$_app" 2>/dev/null)"
    [ "$_bid" = "(null)" ] && _bid=""
    _base="$(basename "$_app" .app)"
    log INFO "App:       $_app"
    if [ -n "$_bid" ]; then log INFO "Bundle-ID: $_bid"; else log WARN "No bundle-id — leftover match limited to app name."; fi

    # ── 3. Collect targets (app bundle + existing leftovers) ──
    _targets=("$_app")
    _add() { local p="$1" t; [ -e "$p" ] || return 0; for t in "${_targets[@]}"; do [ "$t" = "$p" ] && return 0; done; _targets+=("$p"); }
    # name-based (specific base name — safe)
    for _p in \
        "$HOME/Library/Application Support/$_base" \
        "$HOME/Library/Caches/$_base" \
        "$HOME/Library/Logs/$_base"; do
        _add "$_p"
    done
    # bundle-id based (ONLY when a bundle-id exists — an empty id would turn globs catastrophic)
    if [ -n "$_bid" ]; then
        for _p in \
            "$HOME/Library/Application Support/$_bid" \
            "$HOME/Library/Caches/$_bid" \
            "$HOME/Library/Containers/$_bid" \
            "$HOME/Library/HTTPStorages/$_bid" \
            "$HOME/Library/HTTPStorages/$_bid.binarycookies" \
            "$HOME/Library/WebKit/$_bid" \
            "$HOME/Library/Cookies/$_bid.binarycookies" \
            "$HOME/Library/Application Scripts/$_bid" \
            "$HOME/Library/Saved Application State/$_bid.savedState" \
            "$HOME/Library/Logs/$_bid" \
            "$HOME/Library/Preferences/$_bid.plist"; do
            _add "$_p"
        done
        for _p in \
            "$HOME/Library/Preferences/$_bid"[._]*.plist \
            "$HOME/Library/Preferences/ByHost/$_bid".*.plist \
            "$HOME/Library/LaunchAgents/$_bid"*.plist \
            "$HOME/Library/Group Containers/"*"$_bid"*; do
            _add "$_p"
        done
    fi
    # system-level (root-owned) leftovers — the CleanMyMac-style deep scan.
    # These are what a pkg installer drops outside ~/Library; the app-name and
    # bundle-id are specific enough to be safe. Removed via elevation in step 7.
    for _p in \
        "/Library/Application Support/$_base" \
        "/Library/Logs/$_base"; do
        _add "$_p"
    done
    if [ -n "$_bid" ]; then
        for _p in \
            "/Library/Application Support/$_bid" \
            "/Library/Caches/$_bid" \
            "/Library/Preferences/$_bid.plist"; do
            _add "$_p"
        done
        for _p in \
            /Library/LaunchDaemons/"$_bid"*.plist \
            /Library/LaunchAgents/"$_bid"*.plist \
            /Library/PrivilegedHelperTools/"$_bid"*; do
            _add "$_p"
        done
    fi

    # ── 4. Size + preview ──
    _total_kb=0
    echo ""
    echo "  Will remove:"
    for _t in "${_targets[@]}"; do
        _kb=$(du -sk "$_t" 2>/dev/null | awk '{print $1}'); _kb=${_kb:-0}
        _total_kb=$((_total_kb + _kb))
        printf '    %-10s %s\n' "$(_hkb "$_kb")" "${_t/#$HOME/~}"
    done
    echo "    ----------"
    printf '    %s item(s), %s total\n' "${#_targets[@]}" "$(_hkb "$_total_kb")"
    echo ""

    # ── 5. Quit the app if running ──
    if pgrep -f "$_app/Contents/MacOS/" >/dev/null 2>&1; then
        log INFO "Quitting running app '$_base'..."
        run_or_dry osascript -e "tell application \"$_base\" to quit" >/dev/null 2>&1 || true
        if ! $DRY_RUN; then
            _w=0
            while [ $_w -lt 5 ] && pgrep -f "$_app/Contents/MacOS/" >/dev/null 2>&1; do sleep 1; _w=$((_w + 1)); done
            pgrep -f "$_app/Contents/MacOS/" >/dev/null 2>&1 && run_or_dry pkill -f "$_app/Contents/MacOS/"
        fi
    fi

    # ── 6. Confirm ──
    if ! $DRY_RUN && ! $REMOVE_YES; then
        if [ ! -t 0 ]; then
            log ERROR "Non-interactive terminal and no -y/--yes given — aborting."
            exit 1
        fi
        if $REMOVE_PURGE; then
            printf "  \033[1;31mPERMANENTLY delete\033[0m these %s item(s)? [y/N] " "${#_targets[@]}"
        else
            printf "  Move these %s item(s) to Trash? [y/N] " "${#_targets[@]}"
        fi
        read -r _reply
        case "$_reply" in [yY]|[yY][eE][sS]) ;; *) echo "  Aborted."; exit 0 ;; esac
    fi

    # ── 7. Remove (unprivileged first, escalate to root on failure — like CleanMyMac) ──
    # Why not pre-guess: moving a root-owned .app to Trash needs write on the bundle
    # itself (its ".." link is rewritten), not just on /Applications. The old parent-dir
    # check saw /Applications as writable and never escalated, so the app was left behind.
    # Correct + simple: try as the user, and only if that fails escalate — one auth prompt.
    _authed=false
    _ensure_sudo() {
        $_authed && return 0
        [ -t 0 ] || return 1            # never block on auth in a non-interactive run
        log INFO "System-owned (root) items present — authorizing removal..."
        sudo -v 2>/dev/null && { _authed=true; return 0; }
        log WARN "Authorization failed — root-owned items will be skipped."
        return 1
    }

    # Unload any launchd services the app registered (else they respawn / hold files open)
    if [ -n "$_bid" ]; then
        while IFS= read -r _svc; do
            [ -z "$_svc" ] && continue
            if $DRY_RUN; then log STEP "   [DRY-RUN] launchctl bootout $_svc"; continue; fi
            launchctl bootout "gui/$(id -u)/$_svc" 2>/dev/null && { log FIX "Unloaded service: $_svc"; continue; }
            _ensure_sudo && sudo launchctl bootout "system/$_svc" 2>/dev/null && log FIX "Unloaded service: $_svc"
        done < <(launchctl list 2>/dev/null | awk -v b="$_bid" 'BEGIN{b=tolower(b)} NR>1 { s=tolower($3); if (index(s,b)==1) print $3 }')
    fi

    _trash="$HOME/.Trash"
    _removed=0; _failed=0
    for _t in "${_targets[@]}"; do
        case "$_t" in
            "" | "/" | "$HOME" | "$HOME/" | "/Applications" | "/Library" | "/Library/Application Support" | /System*)
                log WARN "Skipping unsafe path: $_t"; _failed=$((_failed + 1)); continue ;;
        esac
        if $DRY_RUN; then log STEP "   [DRY-RUN] remove ${_t/#$HOME/~}"; _removed=$((_removed + 1)); continue; fi
        if $REMOVE_PURGE; then
            if rm -rf "$_t" 2>/dev/null || { _ensure_sudo && sudo rm -rf "$_t" 2>/dev/null; }; then
                _removed=$((_removed + 1)); continue
            fi
        else
            _dest="$_trash/$(basename "$_t")"
            [ -e "$_dest" ] && _dest="$_dest.$(date +%Y%m%d%H%M%S)"
            if mv "$_t" "$_dest" 2>/dev/null; then
                _removed=$((_removed + 1)); continue
            fi
            if _ensure_sudo && sudo mv "$_t" "$_dest" 2>/dev/null; then
                sudo chown -R "$(id -u):$(id -g)" "$_dest" 2>/dev/null   # user-owned so Trash restore/empty needs no auth
                _removed=$((_removed + 1)); continue
            fi
        fi
        log WARN "Failed: $_t"; _failed=$((_failed + 1))
    done

    # Forget package receipts so a reinstall starts clean (removes only the receipt record,
    # touches no files). Tightly matched: same vendor prefix AND app name — never a stray pkg.
    if [ -n "$_bid" ] && ! $DRY_RUN; then
        _vendor="$(printf '%s' "$_bid" | cut -d. -f1,2)"
        _lname="$(printf '%s' "$_base" | tr '[:upper:]' '[:lower:]')"
        while IFS= read -r _rcpt; do
            [ -z "$_rcpt" ] && continue
            _ensure_sudo && sudo pkgutil --forget "$_rcpt" >/dev/null 2>&1 && log FIX "Forgot pkg receipt: $_rcpt"
        done < <(pkgutil --pkgs 2>/dev/null | awk -v v="$_vendor" -v n="$_lname" 'index($0,v)==1 && index(tolower($0),n)')
    fi

    echo ""
    if $DRY_RUN; then
        log INFO "Dry-run complete — nothing changed. ($_removed item(s) would be removed)"
    elif $REMOVE_PURGE; then
        log INFO "Permanently removed $_removed item(s). ($_failed failed/skipped)"
    else
        log INFO "Moved $_removed item(s) to Trash. ($_failed failed/skipped)  Restore from ~/.Trash if needed."
    fi
    exit 0
fi

# ── Orphan Leftover Scanner (meister orphans) ──
# Finds files in ~/Library and /Library whose bundle-id belongs to an app that
# is no longer installed — CleanMyMac's "Leftovers". Conservative by design so
# it never eats data of an app that IS installed:
#   - only reverse-DNS id-form names (>=2 dots); human-named dirs are skipped
#   - never com.apple.* or known updaters (Keystone, AutoUpdate)
#   - skip ids with a live launchd service (in use) or a related installed app
#     (helpers/containers share a parent-or-child id)
# Moves to Trash (reversible) by default. --purge, --dry-run, -y as with remove.
if [ "${1:-}" = "orphans" ]; then
    shift
    ORPH_DRY=false; ORPH_PURGE=false; ORPH_YES=false
    for _a in "$@"; do
        case "$_a" in
            --dry-run|-n) ORPH_DRY=true ;;
            --purge)      ORPH_PURGE=true ;;
            -y|--yes)     ORPH_YES=true ;;
            -*) echo "[ERROR] Unknown flag: $_a"; echo "Usage: meister orphans [--dry-run] [--purge] [-y]"; exit 1 ;;
            *)  echo "[ERROR] Unexpected argument: $_a"; echo "Usage: meister orphans [--dry-run] [--purge] [-y]"; exit 1 ;;
        esac
    done

    echo -e "\033[1;34m  MEISTER ORPHANS — Leftovers of uninstalled apps\033[0m"
    echo ""
    DRY_RUN=$ORPH_DRY
    $DRY_RUN && echo "  [DRY-RUN — no changes]" && echo ""
    shopt -s nullglob

    _hkb() { awk -v k="${1:-0}" 'BEGIN{ if(k<1024) printf "%d KB",k; else if(k<1048576) printf "%.1f MB",k/1024; else printf "%.2f GB",k/1048576 }'; }

    # ── 1. Index installed bundle-ids (one Spotlight call + /Applications fallback) ──
    log INFO "Indexing installed apps..."
    _installed="$(mktemp)"; _cand="$(mktemp)"
    trap 'rm -f "$_installed" "$_cand"' EXIT
    {
        # -attr returns "<path>  kMDItemCFBundleIdentifier = <id>" in a single process
        mdfind -attr kMDItemCFBundleIdentifier \
            "kMDItemContentType == 'com.apple.application-bundle'" 2>/dev/null \
            | sed -n 's/.*kMDItemCFBundleIdentifier = //p'
        for _d in /Applications "$HOME/Applications" /Applications/Utilities; do
            [ -d "$_d" ] || continue
            while IFS= read -r _ip; do
                defaults read "${_ip%.plist}" CFBundleIdentifier 2>/dev/null
            done < <(find "$_d" -maxdepth 3 -path "*.app/Contents/Info.plist" 2>/dev/null)
        done
        # PreferencePanes are "installed" apps without a .app (e.g. Hazel) — index them too
        for _pp in "$HOME/Library/PreferencePanes"/*.prefPane /Library/PreferencePanes/*.prefPane; do
            [ -d "$_pp" ] && defaults read "$_pp/Contents/Info" CFBundleIdentifier 2>/dev/null
        done
    } | grep -v '^(null)$' | tr '[:upper:]' '[:lower:]' | grep -E '^[a-z0-9].*\.' | sort -u > "$_installed"

    _icount=$(grep -c . "$_installed")
    if [ "$_icount" -lt 20 ]; then
        log ERROR "Only $_icount apps indexed — Spotlight looks incomplete; everything would"
        log ERROR "appear orphaned. Refusing to run. Rebuild the index with: sudo mdutil -E /"
        exit 1
    fi
    log INFO "Indexed $_icount installed bundle-ids."

    _svc="$(mktemp)"; _raw="$(mktemp)"; _picked="$(mktemp)"
    trap 'rm -f "$_installed" "$_cand" "$_svc" "$_raw" "$_picked" "$_annot" "$_sizes"' EXIT
    launchctl list 2>/dev/null | awk 'NR>1{print tolower($3)}' | sort -u > "$_svc"

    # ── 2. Collect raw candidates from id-named locations (basename encodes the id) ──
    for _dir in \
        "$HOME/Library/Preferences" \
        "$HOME/Library/Containers" \
        "$HOME/Library/Saved Application State" \
        "$HOME/Library/HTTPStorages" \
        "$HOME/Library/Application Scripts" \
        "$HOME/Library/WebKit" \
        "$HOME/Library/Caches" \
        "$HOME/Library/Application Support" \
        "$HOME/Library/Logs" \
        "$HOME/Library/LaunchAgents" \
        "/Library/Application Support" \
        "/Library/LaunchDaemons" \
        "/Library/LaunchAgents" \
        "/Library/PrivilegedHelperTools"; do
        [ -d "$_dir" ] || continue
        for _e in "$_dir"/*; do
            [ -e "$_e" ] || continue
            _bn="${_e##*/}"                                       # basename, no fork
            case "$_bn" in *" "*|*_tmp_*|*.dat) continue ;; esac  # skip temp/non-id junk
            printf '%s\t%s\n' "$_bn" "$_e" >> "$_raw"
        done
    done

    # ── Classify in ONE awk pass — portable to bash 3.2 (no associative arrays in bash). ──
    # awk loads installed ids + their >=3-label prefixes + loaded services, then for each
    # candidate decides whether an installed app owns it (exact / helper / container /
    # sibling-extension, incl. the <TeamID>.<bundleid> naming of Application Scripts).
    awk -F'\t' -v svcfile="$_svc" '
        function ndots(s,  t){ t=s; return gsub(/\./,"",t) }
        function hasteam(id,  a){ return (split(id,a,".")>=2 && length(a[1])==10 && a[1] ~ /^[a-z0-9]+$/) }
        function check(p){ while(1){ if(p in inst || p in pref) return 1; if(sub(/\.[^.]*$/,"",p)==0) return 0 } }
        function owned(id,  v){ if(check(id)) return 1; if(hasteam(id)){ v=id; sub(/^[^.]*\./,"",v); if(check(v)) return 1 } return 0 }
        BEGIN{ while((getline s < svcfile) > 0) loaded[s]=1 }
        NR==FNR {                                         # installed ids (lowercased, sorted)
            if($0!=""){ inst[$0]=1; p=$0
                while(sub(/\.[^.]*$/,"",p)){ if(ndots(p)>=2) pref[p]=1; else break } }
            next
        }
        {                                                 # raw candidate: base \t path
            id=tolower($1)
            sub(/\.plist$/,"",id); sub(/\.savedstate$/,"",id); sub(/\.binarycookies$/,"",id)
            if(id=="") next
            if(id ~ /^com\.apple\./ || id ~ /^apple\./ || id ~ /\.com\.apple\./) next
            if(id ~ /^com\.google\.keystone/ || id ~ /^com\.google\.googleupdater/ || id ~ /^com\.microsoft\.autoupdate/ || id ~ /^com\.oracle\.java/ || id ~ /^org\.swift\./) next
            if(ndots(id) < 2) next                        # need reverse-DNS; skip human-named dirs
            if(id in loaded) next                         # live launchd service → in use
            if(owned(id)) next                            # an installed app owns it
            print id "\t" $2
        }
    ' "$_installed" "$_raw" | sort -u > "$_cand"

    if [ ! -s "$_cand" ]; then
        log INFO "No orphaned leftovers found. 🎉"
        exit 0
    fi

    # ── 3. Size each item, group by app, preview (numbered, biggest first) ──
    _annot="$(mktemp)"; _sizes="$(mktemp)"
    while IFS=$'\t' read -r _cid _path; do
        _kb=$(du -sk "$_path" 2>/dev/null | awk '{print $1}')
        printf '%s\t%s\t%s\n' "$_cid" "${_kb:-0}" "$_path" >> "$_annot"
    done < "$_cand"
    awk -F'\t' '{k[$1]+=$2} END{for(i in k) printf "%d\t%s\n", k[i], i}' "$_annot" | sort -rn > "$_sizes"

    _gids=(); _total_kb=0; _i=0
    echo "  Orphaned leftovers — no installed app owns these (biggest first):"
    echo ""
    while IFS=$'\t' read -r _gkb _gid; do
        _i=$((_i + 1)); _gids+=("$_gid"); _total_kb=$((_total_kb + _gkb))
        printf '  \033[1m[%3d]\033[0m %-10s %s\n' "$_i" "$(_hkb "$_gkb")" "$_gid"
    done < "$_sizes"
    echo "        ----------"
    printf '  %s app(s), %s total\n' "${#_gids[@]}" "$(_hkb "$_total_kb")"

    # ── 4. Select which apps' leftovers to remove ──
    # Review first: shared components (Office licensing, Python, VPN helpers) can appear
    # here if their parent app is uninstalled. Deselect anything you still use — and note
    # everything goes to the Trash, so a wrong pick is recoverable.
    _pick_all=false
    if $DRY_RUN || $ORPH_YES; then
        _pick_all=true
    else
        [ -t 0 ] || { log ERROR "Non-interactive terminal and no -y/--yes given — aborting."; exit 1; }
        echo ""
        echo "  Select:  [a]=all   \"3 7\"=only these   \"!3 7\"=all except these   [Enter]=cancel"
        printf "  → "
        read -r _sel
        case "$_sel" in
            a|A|all|ALL) _pick_all=true ;;
            "") echo "  Cancelled."; exit 0 ;;
            "!"*)
                _ex=" ${_sel#!} "
                for _k in $(seq 1 "${#_gids[@]}"); do
                    case "$_ex" in *" $_k "*) continue ;; esac
                    echo "${_gids[$((_k - 1))]}" >> "$_picked"
                done ;;
            *)
                for _k in $_sel; do
                    case "$_k" in ''|*[!0-9]*) continue ;; esac
                    [ "$_k" -ge 1 ] && [ "$_k" -le "${#_gids[@]}" ] && echo "${_gids[$((_k - 1))]}" >> "$_picked"
                done ;;
        esac
        if ! $_pick_all && [ ! -s "$_picked" ]; then echo "  Nothing selected — aborting."; exit 0; fi
        $_pick_all && _cnt="${#_gids[@]}" || _cnt="$(grep -c . "$_picked")"
        if $ORPH_PURGE; then printf "  \033[1;31mPERMANENTLY delete\033[0m leftovers of %s app(s)? [y/N] " "$_cnt"
        else printf "  Move leftovers of %s app(s) to Trash? [y/N] " "$_cnt"; fi
        read -r _reply
        case "$_reply" in [yY]|[yY][eE][sS]) ;; *) echo "  Aborted."; exit 0 ;; esac
    fi

    # ── 5. Reap (unprivileged first, escalate to root on failure — like remove) ──
    _authed=false
    _ensure_sudo() {
        $_authed && return 0
        [ -t 0 ] || return 1
        log INFO "System-owned (root) items present — authorizing removal..."
        sudo -v 2>/dev/null && { _authed=true; return 0; }
        log WARN "Authorization failed — root-owned items will be skipped."
        return 1
    }
    _trash="$HOME/.Trash"; _removed=0; _failed=0
    while IFS=$'\t' read -r _cid _t; do
        $_pick_all || grep -qxF "$_cid" "$_picked" || continue   # honor per-app selection
        case "$_t" in
            "" | "/" | "$HOME" | "$HOME/" | /System*) log WARN "Skipping unsafe path: $_t"; _failed=$((_failed + 1)); continue ;;
        esac
        if $DRY_RUN; then log STEP "   [DRY-RUN] remove ${_t/#$HOME/~}"; _removed=$((_removed + 1)); continue; fi
        if $ORPH_PURGE; then
            if rm -rf "$_t" 2>/dev/null || { _ensure_sudo && sudo rm -rf "$_t" 2>/dev/null; }; then
                _removed=$((_removed + 1)); continue
            fi
        else
            _dest="$_trash/$(basename "$_t")"
            [ -e "$_dest" ] && _dest="$_dest.$(date +%Y%m%d%H%M%S)"
            if mv "$_t" "$_dest" 2>/dev/null; then _removed=$((_removed + 1)); continue; fi
            if _ensure_sudo && sudo mv "$_t" "$_dest" 2>/dev/null; then
                sudo chown -R "$(id -u):$(id -g)" "$_dest" 2>/dev/null
                _removed=$((_removed + 1)); continue
            fi
        fi
        log WARN "Failed: $_t"; _failed=$((_failed + 1))
    done < "$_cand"

    echo ""
    if $DRY_RUN; then
        log INFO "Dry-run complete — nothing changed. ($_removed item(s) would be removed)"
    elif $ORPH_PURGE; then
        log INFO "Permanently removed $_removed item(s). ($_failed failed/skipped)"
    else
        log INFO "Moved $_removed item(s) to Trash. ($_failed failed/skipped)  Restore from ~/.Trash if needed."
    fi
    exit 0
fi

# ── Simulator Fix (meister simfix) ──
if [ "${1:-}" = "simfix" ]; then
    echo -e "\033[1;34m  MEISTER SIMFIX — Repair iOS Simulator\033[0m"
    echo ""
    DRY_RUN=false
    [ "${2:-}" = "--dry-run" ] && DRY_RUN=true
    $DRY_RUN && echo "  [DRY-RUN MODE — no changes]" && echo ""
    # Cache sudo for CoreSimulatorService kickstart
    if ! $DRY_RUN && [ -t 0 ]; then
        sudo -v 2>/dev/null || echo "  (sudo unavailable — kickstart step will skip)"
    fi
    MODULE_TOTAL=1
    start_bw_monitor
    bw_set_status 1 1 "Simulator Fix"
    module_simfix
    stop_bw_monitor
    exit 0
fi

# ── Free RAM (meister free) ──
# ── TCC Orphan Cleanup (meister tcc-clean) ──
# Removes privacy grants (Full Disk Access, Accessibility, ...) whose app or
# binary no longer exists — deleted apps like Malwarebytes otherwise stay in
# System Settings forever. Reading/writing TCC.db needs the terminal to have
# Full Disk Access; the system DB additionally needs sudo.
if [ "${1:-}" = "tcc-clean" ]; then
    echo -e "\033[1;34m  MEISTER TCC-CLEAN — verwaiste Privacy-Eintraege\033[0m"
    echo ""
    _T_DO=false; [ "${2:-}" = "--do" ] && _T_DO=true
    _T_USER_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    _T_SYS_DB="/Library/Application Support/com.apple.TCC/TCC.db"
    _T_FOUND=0

    # LaunchServices register as second source of truth — Spotlight misses
    # apps outside indexed locations (OneDrive, helpers), which must NOT be
    # reported as orphans. Dumped once, grepped per bundle id.
    _T_LSREG_CACHE=$(mktemp)
    /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
        -dump 2>/dev/null | grep -iE 'bundle id|CFBundleIdentifier' > "$_T_LSREG_CACHE" 2>/dev/null

    # exists check: client_type 1 = absolute path, 0 = bundle id.
    # Conservative by design: any hit in ANY source = exists. Only entries with
    # no trace anywhere are orphans.
    _tcc_exists() {
        local client="$1" ctype="$2"
        if [ "$ctype" = "1" ]; then
            [ -e "$client" ]
            return $?
        fi
        # Apple components are never orphans (system binaries aren't indexed)
        case "$client" in com.apple.*) return 0 ;; esac
        [ -n "$(mdfind "kMDItemCFBundleIdentifier == '$client'" 2>/dev/null | head -1)" ] && return 0
        [ -e "/Library/PrivilegedHelperTools/$client" ] && return 0
        pgrep -qf "$client" 2>/dev/null && return 0
        grep -qiF "$client" "$_T_LSREG_CACHE" 2>/dev/null && return 0
        return 1
    }

    _tcc_scan() {  # $1: db path, $2: "sudo" | ""
        local db="$1" use_sudo="$2" rows
        if [ "$use_sudo" = "sudo" ]; then
            rows=$(sudo sqlite3 "$db" "SELECT DISTINCT client, client_type FROM access;" 2>/dev/null)
        else
            rows=$(sqlite3 "$db" "SELECT DISTINCT client, client_type FROM access;" 2>/dev/null)
        fi
        [ -z "$rows" ] && return 1
        echo "$rows" | while IFS='|' read -r client ctype; do
            [ -z "$client" ] && continue
            if ! _tcc_exists "$client" "$ctype"; then
                echo "${client}|${ctype}"
            fi
        done
        return 0
    }

    # Probe whether we can WRITE the db: run a DELETE that matches nothing and
    # capture the real error. The system TCC.db is world-READABLE, so a failed
    # write is the real signal (missing Full Disk Access, or a locked db) — the
    # old code hid it behind 2>/dev/null and printed a guessed cause.
    _TCC_WRITE_OK=false; _TCC_WRITE_ERR=""
    _tcc_write_probe() {  # $1 db  $2 sudo|""
        local db="$1" use_sudo="$2" err
        if [ "$use_sudo" = "sudo" ]; then
            err=$(sudo sqlite3 "$db" "DELETE FROM access WHERE client='__meister_probe__';" 2>&1)
        else
            err=$(sqlite3 "$db" "DELETE FROM access WHERE client='__meister_probe__';" 2>&1)
        fi
        if [ $? -eq 0 ]; then _TCC_WRITE_OK=true; _TCC_WRITE_ERR=""
        else _TCC_WRITE_OK=false; _TCC_WRITE_ERR="$err"; fi
    }

    _tcc_clean_db() {  # $1: db, $2: "sudo"|"", $3: label
        local db="$1" use_sudo="$2" dblabel="$3"
        echo -e "  \033[1m${dblabel}\033[0m"
        [ -r "$db" ] || { echo "    (Datei nicht lesbar: $db)"; return 0; }
        local orphans
        orphans=$(_tcc_scan "$db" "$use_sudo")
        if [ -z "$orphans" ]; then
            echo "    Keine verwaisten Eintraege"
            return 0
        fi
        # For --do: probe writability ONCE. tccutil is NOT an option for
        # orphans — it rejects uninstalled bundle ids (LSApplicationNotFound),
        # so the only removal path is a direct sqlite3 DELETE, which needs the
        # terminal to hold Full Disk Access.
        if $_T_DO; then
            _tcc_write_probe "$db" "$use_sudo"
            if ! $_TCC_WRITE_OK; then
                echo -e "    \033[1;31mSchreibzugriff verweigert:\033[0m ${_TCC_WRITE_ERR:-unbekannt}"
                case "$_TCC_WRITE_ERR" in
                    *"authorization denied"*|*"not authorized"*|*"unable to open"*)
                        echo "    → Terminal hat keinen Festplattenvollzugriff (FDA)." ;;
                    *"locked"*)
                        echo "    → DB ist gesperrt (tccd) — spaeter erneut versuchen." ;;
                    *"readonly"*)
                        echo "    → DB schreibgeschuetzt — FDA fuers Terminal fehlt oder SIP." ;;
                esac
                echo "    → Bitte in iTerm oder Ghostty ausfuehren (die haben FDA):"
                echo "        sudo meister tcc-clean --do"
                echo "      Oder FDA fuer dein Terminal aktivieren: Systemeinstellungen →"
                echo "      Datenschutz & Sicherheit → Festplattenvollzugriff."
                return 0
            fi
        fi
        local backup="$MEISTER_DIR/backups/tcc_orphans_$(date +%Y%m%d_%H%M%S)_${dblabel}.txt"
        mkdir -p "$MEISTER_DIR/backups"
        echo "$orphans" | while IFS='|' read -r client ctype; do
            local kind="Pfad"; [ "$ctype" = "0" ] && kind="Bundle-ID"
            echo "    ORPHAN ($kind): $client"
            $_T_DO || continue
            local sql_client="${client//\'/\'\'}" q
            # PRAGMA busy_timeout rides out a transient tccd lock
            if [ "$use_sudo" = "sudo" ]; then
                sudo sqlite3 "$db" "SELECT * FROM access WHERE client='$sql_client';" >> "$backup" 2>/dev/null
                q=$(sudo sqlite3 "$db" "PRAGMA busy_timeout=3000; DELETE FROM access WHERE client='$sql_client';" 2>&1)
            else
                sqlite3 "$db" "SELECT * FROM access WHERE client='$sql_client';" >> "$backup" 2>/dev/null
                q=$(sqlite3 "$db" "PRAGMA busy_timeout=3000; DELETE FROM access WHERE client='$sql_client';" 2>&1)
            fi
            if [ -z "$q" ]; then echo "      → entfernt (Backup: $backup)"
            else echo "      → FEHLER: $(echo "$q" | head -1)"; fi
        done
        return 0
    }

    command_exists sqlite3 || { echo "  sqlite3 fehlt"; exit 1; }
    _tcc_clean_db "$_T_USER_DB" ""     "User-TCC"
    echo ""
    _tcc_clean_db "$_T_SYS_DB"  "sudo" "System-TCC"
    echo ""
    if $_T_DO; then
        echo "  Fertig. Systemeinstellungen ggf. neu oeffnen (killall 'System Settings')."
    else
        echo "  Nur Analyse. Entfernen mit: meister tcc-clean --do"
        echo "  Wichtig: das Entfernen braucht ein Terminal mit Festplattenvollzugriff"
        echo "  (FDA) — sonst verweigert macOS den Schreibzugriff auf die TCC-DB."
        _fda_terms=$(sqlite3 "$_T_SYS_DB" "SELECT client FROM access WHERE service='kTCCServiceSystemPolicyAllFiles' AND auth_value=2;" 2>/dev/null \
            | grep -iE 'iterm|ghostty|terminal|warp|kitty|alacritty|wezterm')
        if [ -n "$_fda_terms" ]; then
            echo "  Terminals mit FDA auf diesem Mac:"
            echo "$_fda_terms" | sed 's/^/    ✓ /'
        else
            echo "  Kein Terminal hat FDA — erst in Systemeinstellungen aktivieren."
        fi
    fi
    exit 0
fi

# ── App Updates (meister appupdates) — MacUpdater-style unified check ──
# One list for ALL app updates: brew casks, Mac App Store, and Sparkle-based
# apps (reads each app's SUFeedURL appcast — the same mechanism MacUpdater uses).
if [ "${1:-}" = "appupdates" ] || [ "${1:-}" = "macupdate" ]; then
    echo -e "\033[1;34m  MEISTER APPUPDATES — alle App-Updates (MacUpdater-Style)\033[0m"
    echo ""
    _AU_TOTAL=0

    if command_exists brew; then
        echo -e "  \033[1mHomebrew Casks\033[0m"
        _AU_BREW=$(brew outdated --cask --greedy --verbose 2>/dev/null | grep -v '(latest)')
        if [ -n "$_AU_BREW" ]; then
            echo "$_AU_BREW" | sed 's/^/    /'
            _AU_TOTAL=$((_AU_TOTAL + $(echo "$_AU_BREW" | grep -c .)))
            echo "    → brew upgrade --cask"
        else
            echo "    alle aktuell"
        fi
        echo ""
    fi

    if command_exists mas; then
        echo -e "  \033[1mMac App Store\033[0m"
        _AU_MAS=$(mas outdated 2>/dev/null)
        if [ -n "$_AU_MAS" ]; then
            echo "$_AU_MAS" | sed 's/^/    /'
            _AU_TOTAL=$((_AU_TOTAL + $(echo "$_AU_MAS" | grep -c .)))
            echo "    → mas upgrade"
        else
            echo "    alle aktuell"
        fi
        echo ""
    fi

    echo -e "  \033[1mSparkle-Apps (Appcast-Check)\033[0m"
    _AU_SPARKLE=0
    for _app in /Applications/*.app; do
        [ -d "$_app" ] || continue
        _feed=$(defaults read "$_app/Contents/Info.plist" SUFeedURL 2>/dev/null)
        [ -z "$_feed" ] && continue
        _cur=$(defaults read "$_app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
        [ -z "$_cur" ] && continue
        _latest=$(curl -sfL --max-time 8 "$_feed" 2>/dev/null | \
            grep -oE 'sparkle:shortVersionString="[^"]+"' | head -1 | cut -d'"' -f2)
        [ -z "$_latest" ] && continue
        if [ "$_cur" != "$_latest" ]; then
            echo "    $(basename "$_app" .app): ${_cur} → ${_latest}  (App-Menue: Nach Updates suchen)"
            _AU_SPARKLE=$((_AU_SPARKLE + 1))
            _AU_TOTAL=$((_AU_TOTAL + 1))
        fi
    done
    [ "$_AU_SPARKLE" -eq 0 ] && echo "    alle aktuell (oder kein Sparkle-Feed)"
    echo ""

    if [ -d "/Applications/MacUpdater.app" ]; then
        echo "  MacUpdater ist installiert — Vollscan: open -a MacUpdater"
        echo ""
    fi
    echo "  ${_AU_TOTAL} Update(s) insgesamt. Nicht-brew-Apps adoptieren: meister adopt"
    exit 0
fi

# ── System Diff (meister diff) — Zeitreise: was hat sich geaendert? ──
if [ "${1:-}" = "diff" ]; then
    echo -e "\033[1;34m  MEISTER DIFF — Systemaenderungen seit letztem Snapshot\033[0m"
    echo ""
    SNAPSHOT_DIR="$MEISTER_DIR/snapshots"
    if [ "${2:-}" = "--snapshot" ]; then
        _s=$(write_system_snapshot)
        echo "  Snapshot geschrieben: $_s"
        exit 0
    fi
    _SNAPS=$(/bin/ls -1t "$SNAPSHOT_DIR"/snap-*.txt 2>/dev/null)
    _SNAP_N=$(printf '%s\n' "$_SNAPS" | grep -c . || true)
    if [ "${_SNAP_N:-0}" -lt 2 ]; then
        echo "  Nicht genug Snapshots (${_SNAP_N:-0}). Es entsteht nach jedem 'meister'-Lauf einer."
        echo "  Jetzt einen anlegen: meister diff --snapshot"
        exit 0
    fi
    _NEW=$(printf '%s\n' "$_SNAPS" | sed -n '1p')
    _OLD=$(printf '%s\n' "$_SNAPS" | sed -n '2p')
    echo "  Vergleich: $(basename "$_OLD")  →  $(basename "$_NEW")"
    echo ""
    # LC_ALL=C: snapshots are C-sorted; comm needs the SAME collation or it
    # silently mis-classifies when the two files were sorted in different
    # locales (launchd C-locale run vs. interactive UTF-8 run)
    _ADDED=$(LC_ALL=C comm -13 "$_OLD" "$_NEW" | grep -vE '^(#|##)')
    _REMOVED=$(LC_ALL=C comm -23 "$_OLD" "$_NEW" | grep -vE '^(#|##)')
    _print_diff() {
        local sign="$1" color="$2" data="$3" label="$4"
        [ -z "$data" ] && return
        echo -e "  ${color}${label}${NC}"
        echo "$data" | while IFS='|' read -r kind a b; do
            case "$kind" in
                app)     printf "    %s App: %s %s\n" "$sign" "$a" "$b" ;;
                launch)  printf "    %s Autostart: %s\n" "$sign" "$a" ;;
                formula) printf "    %s brew: %s\n" "$sign" "$a" ;;
                cask)    printf "    %s cask: %s\n" "$sign" "$a" ;;
                setting) printf "    %s Einstellung: %s=%s\n" "$sign" "$a" "$b" ;;
            esac
        done
    }
    if [ -z "$_ADDED$_REMOVED" ]; then
        echo "  Keine Aenderungen."
    else
        _print_diff "+" "$GREEN" "$_ADDED"   "Neu / geaendert:"
        _print_diff "-" "$RED"   "$_REMOVED" "Entfernt / alte Version:"
        if echo "$_ADDED" | grep -q '^launch|'; then
            echo ""
            echo -e "  ${YELLOW}⚠ Neue Autostart-Eintraege — pruefen mit: meister watch${NC}"
        fi
    fi
    exit 0
fi

# ── Maintenance Score (meister score) — Verlauf des Wartungs-Scores ──
if [ "${1:-}" = "score" ]; then
    echo -e "\033[1;34m  MEISTER SCORE — Wartungs-Score-Verlauf\033[0m"
    echo ""
    _hist="$MEISTER_DIR/history.log"
    if [ ! -f "$_hist" ] || ! grep -q 'SCORE:' "$_hist"; then
        echo "  Noch kein Score aufgezeichnet (entsteht ab dem naechsten 'meister'-Lauf)."
        exit 0
    fi
    _LAST=$(grep -oE 'SCORE:[0-9]+' "$_hist" | tail -1 | cut -d: -f2)
    _col="$GREEN"; [ "$_LAST" -lt 80 ] && _col="$YELLOW"; [ "$_LAST" -lt 55 ] && _col="$RED"
    echo -e "  Aktuell: ${_col}${_LAST}/100${NC}"
    echo ""
    echo "  Verlauf (letzte 15):"
    grep 'SCORE:' "$_hist" | tail -15 | while IFS= read -r line; do
        _d=$(echo "$line" | cut -d'|' -f1 | xargs)
        _sc=$(echo "$line" | grep -oE 'SCORE:[0-9]+' | cut -d: -f2)
        _bars=$(( _sc / 5 ))
        # guard: BSD `seq 1 0` counts DOWN and prints "1 0" → 2 bars for score 0-4
        _bar=""; [ "$_bars" -gt 0 ] && _bar=$(printf '█%.0s' $(seq 1 "$_bars"))
        printf "    %s  %3s  %s\n" "$_d" "$_sc" "$_bar"
    done
    exit 0
fi

# ── Undo (meister undo) — reversible FIX-Aktionen des letzten Laufs ──
if [ "${1:-}" = "undo" ]; then
    echo -e "\033[1;34m  MEISTER UNDO — letzte reversible Aktionen zuruecknehmen\033[0m"
    echo ""
    if [ ! -s "$UNDO_JOURNAL" ]; then
        echo "  Keine rueckgaengig machbaren Aktionen aufgezeichnet."
        echo "  (meister sichert z.B. verwaiste Prefs vor dem Loeschen — die tauchen hier auf.)"
        exit 0
    fi
    if [ "${2:-}" = "--list" ]; then
        echo "  Aufgezeichnete Aktionen (neueste zuletzt):"
        awk -F'\t' '{print $1, $3}' "$UNDO_JOURNAL" | sed 's/^/    /' | tail -30
        exit 0
    fi
    _U_RUN=$(cut -f1 "$UNDO_JOURNAL" | sort -u | tail -1)
    _U_ROWS=$(awk -F'\t' -v r="$_U_RUN" '$1==r' "$UNDO_JOURNAL")
    _U_N=$(printf '%s\n' "$_U_ROWS" | grep -c . || true)
    echo "  Letzter Lauf mit reversiblen Aktionen: ${_U_RUN} (${_U_N} Aktion(en))"
    echo "$_U_ROWS" | awk -F'\t' '{print "    - "$3}'
    echo ""
    if [ "${2:-}" != "--do" ]; then
        echo "  Wiederherstellen mit: meister undo --do"
        exit 0
    fi
    _U_OK=0; _U_FAIL=0
    # collect rows that could NOT be restored — they stay in the journal so a
    # retry (e.g. after fixing perms) is still possible
    _U_KEEP=$(mktemp)
    while IFS=$'\t' read -r _rid _ep _desc _src _dst; do
        [ "$_rid" = "$_U_RUN" ] || continue
        [ -z "$_src" ] && continue
        # plain cp, no shell — src/dst can contain any character safely
        if [ -e "$_src" ] && cp -- "$_src" "$_dst" 2>/dev/null; then
            echo "    ✓ $_desc"; _U_OK=$((_U_OK + 1))
        else
            echo "    ✗ $_desc (Backup nicht mehr da)"; _U_FAIL=$((_U_FAIL + 1))
            printf '%s\t%s\t%s\t%s\t%s\n' "$_rid" "$_ep" "$_desc" "$_src" "$_dst" >> "$_U_KEEP"
        fi
    done <<EOF
$_U_ROWS
EOF
    echo ""
    echo "  ${_U_OK} wiederhergestellt, ${_U_FAIL} fehlgeschlagen."
    # rebuild journal: other runs' rows + this run's still-failed rows
    { grep -v "^${_U_RUN}$(printf '\t')" "$UNDO_JOURNAL" 2>/dev/null; cat "$_U_KEEP" 2>/dev/null; } \
        > "$UNDO_JOURNAL.tmp" && mv "$UNDO_JOURNAL.tmp" "$UNDO_JOURNAL"
    rm -f "$_U_KEEP"
    exit 0
fi

# ── Explain (meister explain <text>) — Ollama erklaert eine Warnung ──
if [ "${1:-}" = "explain" ]; then
    shift
    _EX_TEXT="$*"
    if [ -z "$_EX_TEXT" ]; then
        # anchored timestamp regex — an unanchored ' - WARN - ' also matches STEP
        # lines that QUOTE old warnings, yielding a mangled stale fragment
        _EX_TEXT=$(grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} - (WARN|ERROR) - ' "$LOGFILE" 2>/dev/null | tail -1 | sed 's/^.\{19\} - [A-Z]* - //')
        if [ -z "$_EX_TEXT" ]; then
            echo "Usage: meister explain <Warnung oder Log-Zeile>"; exit 1
        fi
    fi
    echo -e "\033[1;34m  MEISTER EXPLAIN\033[0m"
    echo ""
    echo "  Meldung: $_EX_TEXT"
    echo ""
    if ! ollama_available && ! ensure_ollama_running ""; then
        echo "  Ollama nicht erreichbar — starte mit: ollama serve"
        exit 1
    fi
    _EX_PROMPT="Erklaere diese macOS-Wartungsmeldung einem technisch interessierten Laien auf Deutsch:
\"$_EX_TEXT\"
In 3 kurzen Absaetzen: (1) Was bedeutet das? (2) Ist es gefaehrlich/dringend? (3) Konkrete Handlung, mit Befehl falls sinnvoll. Keine Einleitung."
    if command_exists jq; then
        _EX_BODY=$(jq -nc --arg m "$OLLAMA_MODEL" --arg p "$_EX_PROMPT" '{model:$m, prompt:$p, stream:false}')
    else
        _EX_BODY=$(printf '{"model":"%s","prompt":"%s","stream":false}' "$OLLAMA_MODEL" \
            "$(printf '%s' "$_EX_PROMPT" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')")
    fi
    echo "  Frage ${OLLAMA_MODEL}..."
    echo ""
    _EX_RESP=$(curl -sf --max-time 120 "${OLLAMA_URL}/api/generate" -d "$_EX_BODY" 2>/dev/null)
    if command_exists jq; then
        printf '%s' "$_EX_RESP" | jq -r '.response // "keine Antwort"' | sed 's/^/  /'
    else
        printf '%s' "$_EX_RESP" | perl -nle 'print $1 if /"response":"((?:[^"\\]|\\.)*)"/' \
            | perl -CSD -pe 's/\\u([0-9a-fA-F]{4})/chr(hex($1))/ge; s/\\n/\n/g; s/\\"/"/g; s/\\\\/\\/g' | sed 's/^/  /'
    fi
    echo ""
    exit 0
fi

# ── Fleet (meister fleet) — Reports mehrerer Macs per SSH einsammeln ──
# Config: FLEET_HOSTS="mini.local macbook.local user@host" in ~/.meister/config.
if [ "${1:-}" = "fleet" ]; then
    echo -e "\033[1;34m  MEISTER FLEET — Status aller Macs\033[0m"
    echo ""
    if [ -z "${FLEET_HOSTS:-}" ]; then
        echo "  Keine Hosts konfiguriert. In ~/.meister/config eintragen:"
        echo "    FLEET_HOSTS=\"mini.local macbook.local user@host.local\""
        echo "  Voraussetzung je Host: meister installiert + SSH-Key (kein Passwort)."
        exit 0
    fi
    printf "  %-22s %-8s %-8s %s\n" "Host" "Score" "Status" "Letzter Lauf"
    printf '  '; printf '─%.0s' $(seq 1 62); echo ""
    _F_LOCAL_LINE=$(tail -1 "$MEISTER_DIR/history.log" 2>/dev/null)
    _F_LOCAL_SCORE=$(echo "$_F_LOCAL_LINE" | grep -oE 'SCORE:[0-9]+' | cut -d: -f2)
    _F_LOCAL_DATE=$(echo "$_F_LOCAL_LINE" | cut -d'|' -f1 | xargs)
    printf "  %-22s %-8s %-8s %s\n" "$(scutil --get LocalHostName 2>/dev/null || echo local)" "${_F_LOCAL_SCORE:-?}/100" "lokal" "${_F_LOCAL_DATE:-nie}"
    for _fh in $FLEET_HOSTS; do
        _F_LINE=$(timeout 15 ssh -o ConnectTimeout=8 -o BatchMode=yes "$_fh" \
            'tail -1 ~/.meister/history.log 2>/dev/null' 2>/dev/null)
        if [ -z "$_F_LINE" ]; then
            printf "  %-22s %-8s %-8s %s\n" "$_fh" "?" "offline" "nicht erreichbar"
            continue
        fi
        _F_SCORE=$(echo "$_F_LINE" | grep -oE 'SCORE:[0-9]+' | cut -d: -f2)
        _F_ERR=$(echo "$_F_LINE" | grep -oE 'ERR:[0-9]+' | cut -d: -f2)
        _F_DATE=$(echo "$_F_LINE" | cut -d'|' -f1 | xargs)
        _F_ST="ok"; [ "${_F_ERR:-0}" -gt 0 ] 2>/dev/null && _F_ST="ERR:$_F_ERR"
        printf "  %-22s %-8s %-8s %s\n" "$_fh" "${_F_SCORE:-?}/100" "$_F_ST" "${_F_DATE:-?}"
    done
    echo ""
    exit 0
fi

# ── AI System-Doktor (meister ai) — Ollama-Diagnose auf Abruf ──
# Feeds the last run's warnings/errors + live system facts to the local
# Ollama model and prints a prioritized diagnosis. Read-only, nothing runs.
if [ "${1:-}" = "ai" ]; then
    echo -e "\033[1;34m  MEISTER AI — System-Diagnose (${OLLAMA_MODEL})\033[0m"
    echo ""
    if ! ollama_available && ! ensure_ollama_running ""; then
        echo "  Ollama nicht erreichbar — starte mit: ollama serve"
        exit 1
    fi
    echo "  Sammle Systemzustand..."
    _AI_WARNS=$(grep -E '^[0-9-]+ [0-9:]+ - (WARN|ERROR) - ' "$LOGFILE" 2>/dev/null | tail -25 | sed 's/^.\{19\} - //')
    _AI_DISK=$(df -h / | awk 'NR==2 {print $5" belegt, "$4" frei"}')
    _AI_RAM=$(vm_stat | awk '/Pages free/ {gsub(/\./,""); printf "%.1f GB frei", $3*16384/1073741824}')
    _AI_UPTIME=$(uptime | sed 's/^ *//')
    _AI_TOP=$(ps -Areo pcpu,comm | sort -rn | head -4 | awk '{c=$2; sub(/.*\//,"",c); printf "%s(%s%%) ", c, $1}')
    _AI_HEALS=$(tail -5 "$HEAL_LOG" 2>/dev/null)
    _AI_PROMPT="Du bist ein macOS-Systemdoktor. Analysiere diesen Zustand und antworte auf Deutsch.

Letzte Warnungen/Fehler des Wartungslaufs:
${_AI_WARNS:-keine}

System: Disk ${_AI_DISK} | RAM ${_AI_RAM} | ${_AI_UPTIME}
Top-CPU: ${_AI_TOP}
Letzte Self-Healing-Events:
${_AI_HEALS:-keine}

Gib maximal 5 priorisierte Punkte: was ist das wichtigste Problem, was konkret tun (mit Befehl wo sinnvoll). Kurz und praezise, keine Einleitung."
    if command_exists jq; then
        _AI_BODY=$(jq -nc --arg m "$OLLAMA_MODEL" --arg p "$_AI_PROMPT" '{model:$m, prompt:$p, stream:false}')
    else
        _AI_BODY=$(printf '{"model":"%s","prompt":"%s","stream":false}' "$OLLAMA_MODEL" \
            "$(printf '%s' "$_AI_PROMPT" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')")
    fi
    echo "  Frage ${OLLAMA_MODEL}..."
    echo ""
    _AI_RESP=$(curl -sf --max-time 120 "${OLLAMA_URL}/api/generate" -d "$_AI_BODY" 2>/dev/null)
    if command_exists jq; then
        printf '%s' "$_AI_RESP" | jq -r '.response // "keine Antwort"' | sed 's/^/  /'
    else
        printf '%s' "$_AI_RESP" | perl -nle 'print $1 if /"response":"((?:[^"\\]|\\.)*)"/' \
            | perl -CSD -pe 's/\\u([0-9a-fA-F]{4})/chr(hex($1))/ge; s/\\n/\n/g; s/\\"/"/g; s/\\\\/\\/g' | sed 's/^/  /'
    fi
    echo ""
    exit 0
fi

# ── Package Inspector (meister pkg) — Suspicious-Package-style ──
# Inspect a .pkg BEFORE installing: signature, payload, install scripts.
if [ "${1:-}" = "pkg" ]; then
    _PKG="${2:-}"
    if [ -z "$_PKG" ] || [ ! -f "$_PKG" ]; then
        echo "Usage: meister pkg <file.pkg>"; exit 1
    fi
    echo -e "\033[1;34m  MEISTER PKG — Installer-Inspektor\033[0m"
    echo ""
    echo -e "  \033[1mFile:\033[0m $_PKG ($(du -h "$_PKG" | awk '{print $1}'))"
    echo ""
    echo -e "  \033[1mSignature\033[0m"
    pkgutil --check-signature "$_PKG" 2>&1 | sed -n '1,6p' | sed 's/^/  /'
    echo ""
    echo -e "  \033[1mPayload\033[0m"
    _pl_count=$(pkgutil --payload-files "$_PKG" 2>/dev/null | grep -c . || true)
    echo "  ${_pl_count:-0} files. Top-level targets:"
    pkgutil --payload-files "$_PKG" 2>/dev/null | awk -F/ 'NF<=3' | sort -u | head -20 | sed 's/^/    /'
    echo ""
    echo -e "  \033[1mInstall-Skripte (laufen als root!)\033[0m"
    _PKG_TMP=$(mktemp -d)
    if pkgutil --expand "$_PKG" "$_PKG_TMP/x" 2>/dev/null; then
        _scripts=$(find "$_PKG_TMP/x" -name preinstall -o -name postinstall 2>/dev/null)
        if [ -n "$_scripts" ]; then
            echo "$_scripts" | while IFS= read -r _s; do
                echo "  ── $(basename "$(dirname "$(dirname "$_s")")")/$(basename "$_s") ──"
                head -25 "$_s" | sed 's/^/    /'
                echo ""
            done
        else
            echo "  Keine pre/postinstall-Skripte — gut."
        fi
        # red flags in any script
        if grep -rqiE 'curl.*\|.*sh|base64 -d|nvram|csrutil|spctl --master-disable' "$_PKG_TMP/x" 2>/dev/null; then
            echo -e "  \033[1;31mWARNUNG: verdaechtige Muster in Skripten (Download+Execute / SIP / Gatekeeper)\033[0m"
        fi
    else
        echo "  (expand fehlgeschlagen — evtl. kein flat package)"
    fi
    rm -rf "$_PKG_TMP"
    exit 0
fi

# ── Persistence Watch (meister watch) — BlockBlock-style ──
# LaunchAgent with WatchPaths on the persistence dirs: any new/changed plist
# triggers a check against the baseline + notification.
if [ "${1:-}" = "watch" ]; then
    _W_BASE="$MEISTER_DIR/persistence.baseline"
    _W_LOG="$MEISTER_DIR/watch.log"
    _W_AGENT="$HOME/Library/LaunchAgents/com.meister.watch.plist"
    _W_SELF=$(command -v meister 2>/dev/null)
    [ -z "$_W_SELF" ] && _W_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

    _watch_snapshot() {
        local d
        for d in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
            [ -d "$d" ] || continue
            find "$d" -maxdepth 1 -name '*.plist' -exec shasum -a 256 {} \; 2>/dev/null
        done | sort -k2
    }

    case "${2:-}" in
        --install)
            echo "  Baseline: $(_watch_snapshot | tee "$_W_BASE" | grep -c .) plists erfasst"
            cat > "$_W_AGENT" <<WATCHEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>com.meister.watch</string>
    <key>ProgramArguments</key><array>
        <string>/bin/bash</string>
        <string>${_W_SELF}</string>
        <string>watch</string>
        <string>--check</string>
    </array>
    <key>WatchPaths</key><array>
        <string>${HOME}/Library/LaunchAgents</string>
        <string>/Library/LaunchAgents</string>
        <string>/Library/LaunchDaemons</string>
    </array>
    <key>ThrottleInterval</key><integer>30</integer>
</dict></plist>
WATCHEOF
            launchctl bootout "gui/$(id -u)/com.meister.watch" 2>/dev/null
            launchctl bootstrap "gui/$(id -u)" "$_W_AGENT" 2>/dev/null \
                && echo "  Watcher aktiv: meldet neue/geaenderte LaunchAgents & Daemons sofort" \
                || echo "  [WARN] bootstrap fehlgeschlagen — pruefe: launchctl bootstrap gui/$(id -u) $_W_AGENT"
            ;;
        --uninstall)
            launchctl bootout "gui/$(id -u)/com.meister.watch" 2>/dev/null
            rm -f "$_W_AGENT"
            echo "  Watcher entfernt"
            ;;
        --check)
            if [ ! -f "$_W_BASE" ]; then _watch_snapshot > "$_W_BASE"; exit 0; fi
            _W_CUR=$(mktemp)
            _watch_snapshot > "$_W_CUR"
            _W_NEW=$(comm -13 <(awk '{print $2}' "$_W_BASE" | sort) <(awk '{print $2}' "$_W_CUR" | sort))
            _W_GONE=$(comm -23 <(awk '{print $2}' "$_W_BASE" | sort) <(awk '{print $2}' "$_W_CUR" | sort))
            _W_CHANGED=$(comm -13 <(sort "$_W_BASE") <(sort "$_W_CUR") | awk '{print $2}' | grep -vxF "$_W_NEW" 2>/dev/null || true)
            if [ -n "$_W_NEW$_W_GONE$_W_CHANGED" ]; then
                # Notify only when the diff changed since the last alert —
                # the baseline is NOT auto-updated (an attacker would get one
                # notification and then be silently accepted). User blesses
                # legit changes with: meister watch --accept
                _W_DIFF_HASH=$(printf '%s\n%s\n%s' "$_W_NEW" "$_W_CHANGED" "$_W_GONE" | shasum -a 256 | awk '{print $1}')
                _W_LAST_HASH=$(cat "$MEISTER_DIR/watch.lastnotify" 2>/dev/null)
                if [ "$_W_DIFF_HASH" != "$_W_LAST_HASH" ]; then
                    {
                        echo "$(date '+%Y-%m-%d %H:%M:%S') persistence change:"
                        [ -n "$_W_NEW" ]     && echo "$_W_NEW"     | sed 's/^/  NEU:      /'
                        [ -n "$_W_CHANGED" ] && echo "$_W_CHANGED" | sed 's/^/  GEAENDERT: /'
                        [ -n "$_W_GONE" ]    && echo "$_W_GONE"    | sed 's/^/  ENTFERNT: /'
                    } >> "$_W_LOG"
                    _W_MSG=$(printf '%s\n%s\n%s' "$_W_NEW" "$_W_CHANGED" "$_W_GONE" | grep -c . || true)
                    send_notification "Meister Watch" "${_W_MSG} Persistence-Aenderung(en) — pruefen: meister watch" "LaunchAgents/Daemons"
                    echo "$_W_DIFF_HASH" > "$MEISTER_DIR/watch.lastnotify"
                fi
            fi
            rm -f "$_W_CUR"
            ;;
        --accept)
            _watch_snapshot > "$_W_BASE"
            rm -f "$MEISTER_DIR/watch.lastnotify"
            echo "  Baseline aktualisiert ($(grep -c . "$_W_BASE") plists) — aktuelle Eintraege gelten als OK"
            ;;
        *)
            echo -e "\033[1;34m  MEISTER WATCH — Persistence-Waechter (BlockBlock-Style)\033[0m"
            echo ""
            if launchctl print "gui/$(id -u)/com.meister.watch" &>/dev/null; then
                echo "  Status: AKTIV"
            else
                echo "  Status: nicht installiert  (meister watch --install)"
            fi
            [ -f "$_W_BASE" ] && echo "  Baseline: $(grep -c . "$_W_BASE") plists"
            if [ -f "$_W_BASE" ]; then
                _W_CUR=$(mktemp); _watch_snapshot > "$_W_CUR"
                _W_PEND=$(comm -13 <(sort "$_W_BASE") <(sort "$_W_CUR") | awk '{print $2}')
                rm -f "$_W_CUR"
                if [ -n "$_W_PEND" ]; then
                    echo "  UNBESTAETIGTE Aenderungen (legitim? → meister watch --accept):"
                    echo "$_W_PEND" | sed 's/^/    /'
                fi
            fi
            if [ -f "$_W_LOG" ]; then
                echo "  Letzte Ereignisse:"
                tail -10 "$_W_LOG" | sed 's/^/    /'
            else
                echo "  Keine Ereignisse bisher"
            fi
            ;;
    esac
    exit 0
fi

# ── System Tweaks (meister tweaks) — OnyX-style hidden settings ──
if [ "${1:-}" = "tweaks" ]; then
    _tweak_get() {  # $1 domain $2 key
        defaults read "$1" "$2" 2>/dev/null || echo "-"
    }
    _TW_NAMES="showhidden extensions pathbar keyrepeat savepanel dockfast screenshots-jpg"
    _tweak_status() {
        echo "  showhidden      Finder zeigt versteckte Dateien        [$(_tweak_get com.apple.finder AppleShowAllFiles)]"
        echo "  extensions      Alle Datei-Endungen anzeigen           [$(_tweak_get NSGlobalDomain AppleShowAllExtensions)]"
        echo "  pathbar         Finder Pfad- & Statusleiste            [$(_tweak_get com.apple.finder ShowPathbar)]"
        echo "  keyrepeat       Schnelle Tastenwiederholung (2/15)     [$(_tweak_get NSGlobalDomain KeyRepeat)]"
        echo "  savepanel       Sichern-Dialog immer ausgeklappt       [$(_tweak_get NSGlobalDomain NSNavPanelExpandedStateForSaveMode)]"
        echo "  dockfast        Dock-Autohide ohne Verzoegerung        [$(_tweak_get com.apple.dock autohide-time-modifier)]"
        echo "  screenshots-jpg Screenshots als JPG statt PNG          [$(_tweak_get com.apple.screencapture type)]"
    }
    _T="${2:-}"; _V="${3:-on}"
    if [ -z "$_T" ]; then
        echo -e "\033[1;34m  MEISTER TWEAKS — versteckte macOS-Einstellungen (OnyX-Style)\033[0m"
        echo ""
        _tweak_status
        echo ""
        echo "  Umschalten: meister tweaks <name> [on|off]"
        exit 0
    fi
    _ON=true; [ "$_V" = "off" ] && _ON=false
    case "$_T" in
        showhidden)
            defaults write com.apple.finder AppleShowAllFiles -bool "$_ON"; killall Finder 2>/dev/null ;;
        extensions)
            defaults write NSGlobalDomain AppleShowAllExtensions -bool "$_ON"; killall Finder 2>/dev/null ;;
        pathbar)
            defaults write com.apple.finder ShowPathbar -bool "$_ON"
            defaults write com.apple.finder ShowStatusBar -bool "$_ON"; killall Finder 2>/dev/null ;;
        keyrepeat)
            if $_ON; then
                defaults write NSGlobalDomain KeyRepeat -int 2
                defaults write NSGlobalDomain InitialKeyRepeat -int 15
            else
                defaults delete NSGlobalDomain KeyRepeat 2>/dev/null
                defaults delete NSGlobalDomain InitialKeyRepeat 2>/dev/null
            fi
            echo "  (greift nach Ab-/Anmelden)" ;;
        savepanel)
            defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool "$_ON"
            defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool "$_ON" ;;
        dockfast)
            if $_ON; then
                defaults write com.apple.dock autohide-time-modifier -float 0.15
                defaults write com.apple.dock autohide-delay -float 0
            else
                defaults delete com.apple.dock autohide-time-modifier 2>/dev/null
                defaults delete com.apple.dock autohide-delay 2>/dev/null
            fi
            killall Dock 2>/dev/null ;;
        screenshots-jpg)
            if $_ON; then defaults write com.apple.screencapture type jpg
            else defaults delete com.apple.screencapture type 2>/dev/null; fi
            killall SystemUIServer 2>/dev/null ;;
        *) echo "Unbekannter Tweak: $_T"; echo "Verfuegbar: $_TW_NAMES"; exit 1 ;;
    esac
    echo "  $_T → $_V"
    exit 0
fi

# ── App Adoption (meister adopt) — Latest-style update coverage ──
# Finds apps in /Applications that neither brew nor mas manages and checks
# whether a Homebrew cask exists — adopting them makes updates automatic.
if [ "${1:-}" = "adopt" ]; then
    echo -e "\033[1;34m  MEISTER ADOPT — Apps unter Homebrew-Verwaltung bringen\033[0m"
    echo ""
    command_exists brew || { echo "  brew fehlt"; exit 1; }
    _A_CASKS=$(brew list --cask 2>/dev/null | tr '[:upper:]' '[:lower:]')
    _A_MAS=$(command_exists mas && mas list 2>/dev/null | sed 's/^[0-9]* *//;s/ *([^)]*)$//' | tr '[:upper:]' '[:lower:]')
    _A_FOUND=0; _A_ADOPTABLE=""
    for _app in /Applications/*.app; do
        [ -d "$_app" ] || continue
        _name=$(basename "$_app" .app)
        _lname=$(echo "$_name" | tr '[:upper:]' '[:lower:]')
        _cask_guess=$(echo "$_lname" | tr ' ' '-')
        # skip Apple apps + already managed
        case "$_lname" in safari|mail|calendar|notes|music|tv|photos|facetime|messages|maps|reminders|freeform|news|stocks|home|books|podcasts|shortcuts|numbers|pages|keynote|garageband|imovie|xcode) continue ;; esac
        echo "$_A_CASKS" | grep -qx "$_cask_guess" && continue
        echo "$_A_MAS" | grep -qxF "$_lname" && continue
        _A_FOUND=$((_A_FOUND + 1))
        if brew info --cask "$_cask_guess" &>/dev/null; then
            echo "  ✓ $_name  →  Cask '$_cask_guess' existiert"
            _A_ADOPTABLE="${_A_ADOPTABLE}${_cask_guess} "
        else
            echo "  · $_name  (kein passender Cask gefunden)"
        fi
    done
    echo ""
    echo "  ${_A_FOUND} unverwaltete App(s) geprueft"
    if [ -n "$_A_ADOPTABLE" ]; then
        echo ""
        if [ "${2:-}" = "--do" ]; then
            # name→cask matching is a heuristic — confirm each app individually
            # (a wrong guess would install a DIFFERENT app over the existing one)
            for _c in $_A_ADOPTABLE; do
                if [ -t 0 ]; then
                    printf '  %s adoptieren? [y/N]: ' "$_c"
                    read -r _yn
                    [ "$_yn" = "y" ] || [ "$_yn" = "Y" ] || { echo "    uebersprungen"; continue; }
                fi
                echo "  Adoptiere $_c..."
                brew install --cask --adopt "$_c" 2>&1 | tail -1 | sed 's/^/    /'
            done
        else
            echo "  Adoptieren (App bleibt, Updates laufen kuenftig ueber brew):"
            echo "    meister adopt --do"
            echo "  oder einzeln: brew install --cask --adopt <name>"
        fi
    fi
    exit 0
fi

# ── Live Dashboard (meister dash) — Stats-style terminal monitor ──
if [ "${1:-}" = "dash" ]; then
    _D_INT="${2:-3}"
    case "$_D_INT" in *[!0-9]*) _D_INT=3 ;; esac
    [ "$_D_INT" -lt 1 ] && _D_INT=3   # 0 would divide by zero in the rate math
    # bytes columns counted from the RIGHT — link rows without a MAC (utun,
    # gif, stf) have one field less, absolute $7/$10 would grab packet counts
    _d_net() { netstat -ib 2>/dev/null | awk '$1 !~ /lo0/ && $3 ~ /Link/ {i+=$(NF-4); o+=$(NF-1)} END {print i+0, o+0}'; }
    _D_PREV=$(_d_net)
    trap 'tput cnorm 2>/dev/null; exit 0' INT TERM
    tput civis 2>/dev/null
    while true; do
        _D_CPU=$(top -l 1 -n 0 2>/dev/null | awk -F'[:,%]' '/CPU usage/ {gsub(/ /,""); printf "user %s%%  sys %s%%  idle %s%%", $2, $4, $6}')
        _D_LOAD=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}')
        _D_PGSZ=$(sysctl -n hw.pagesize 2>/dev/null); : "${_D_PGSZ:=16384}"
        _D_RAM=$(vm_stat 2>/dev/null | awk -v pgsz="$_D_PGSZ" '
            /Pages free/ {free=$3} /Pages active/ {act=$3} /Pages inactive/ {inact=$3}
            /Pages wired/ {wired=$4} /Pages occupied by compressor/ {comp=$5}
            END {gsub(/\./,"",free); gsub(/\./,"",act); gsub(/\./,"",wired); gsub(/\./,"",comp)
                 pg=pgsz/1048576
                 printf "used %.1f GB  wired %.1f GB  compressed %.1f GB  free %.1f GB",
                 (act+wired+comp)*pg/1024, wired*pg/1024, comp*pg/1024, free*pg/1024}')
        # Data volume, not the sealed system snapshot (df / shows only ~12 GB)
        _D_DISK=$(df -h /System/Volumes/Data 2>/dev/null | awk 'NR==2 {printf "%s / %s (%s belegt)", $3, $2, $5}')
        _D_CUR=$(_d_net)
        _D_RX=$(( ($(echo "$_D_CUR" | awk '{print $1}') - $(echo "$_D_PREV" | awk '{print $1}')) / _D_INT / 1024 ))
        _D_TX=$(( ($(echo "$_D_CUR" | awk '{print $2}') - $(echo "$_D_PREV" | awk '{print $2}')) / _D_INT / 1024 ))
        _D_PREV=$_D_CUR
        clear
        echo -e "\033[1;34m  MEISTER DASH — $(date '+%H:%M:%S')   (q beendet, Intervall ${_D_INT}s)\033[0m"
        echo ""
        echo -e "  \033[1mCPU \033[0m  ${_D_CPU}    load ${_D_LOAD}"
        echo -e "  \033[1mRAM \033[0m  ${_D_RAM}"
        echo -e "  \033[1mDisk\033[0m  ${_D_DISK}"
        echo -e "  \033[1mNetz\033[0m  ↓ ${_D_RX} KB/s   ↑ ${_D_TX} KB/s"
        echo ""
        echo -e "  \033[1mTop-Prozesse (CPU)\033[0m"
        ps -Areo pcpu,pmem,comm 2>/dev/null | sort -rn | head -6 | \
            awk '{c=$3; sub(/.*\//,"",c); printf "    %5.1f%%  %4.1f%%  %s\n", $1, $2, c}'
        # read rc: 0 = key, >128 = timeout (the normal tick), 1 = EOF (non-tty).
        # On EOF sleep manually — otherwise the loop spins hot without a tty.
        _D_KEY=""
        read -r -t "$_D_INT" -n 1 _D_KEY
        _D_RC=$?
        [ "$_D_RC" -eq 0 ] && [ "$_D_KEY" = "q" ] && break
        [ "$_D_RC" -ge 1 ] && [ "$_D_RC" -le 128 ] && sleep "$_D_INT"
    done
    tput cnorm 2>/dev/null
    exit 0
fi

# ── Open Files (meister files) — Sloth-style lsof wrapper ──
if [ "${1:-}" = "files" ]; then
    _F="${2:-}"
    if [ -z "$_F" ]; then
        echo "Usage: meister files <port|prozessname|pfad>"
        echo "  meister files 8080      → wer lauscht/verbindet auf Port 8080"
        echo "  meister files node      → was hat Prozess 'node' offen"
        echo "  meister files ~/foo.db  → wer haelt diese Datei offen"
        exit 1
    fi
    echo -e "\033[1;34m  MEISTER FILES — offene Dateien/Ports (Sloth-Style)\033[0m"
    echo ""
    # NB: no case-in-$() here — bash 3.2 parses $() lazily and chokes on the
    # unbalanced ')' of case patterns at RUNTIME (bash -n does not catch it)
    if echo "$_F" | grep -q '[^0-9]'; then
        if [ -e "$_F" ]; then
            _F_OUT=$(lsof -- "$_F" 2>/dev/null | head -30)
        else
            _F_OUT=$(lsof -c "$_F" 2>/dev/null | grep -vE 'REG.*/(Frameworks|dyld)' | head -40)
        fi
    else
        _F_OUT=$(lsof -nP -i ":$_F" 2>/dev/null)
    fi
    if [ -n "$_F_OUT" ]; then
        echo "$_F_OUT" | sed 's/^/  /'
    else
        echo "  Keine Treffer fuer '$_F' (Port frei / Prozess laeuft nicht / Datei nicht offen)"
    fi
    echo ""
    exit 0
fi

# ── Window Management (meister win) — Rectangle-style via AppleScript ──
if [ "${1:-}" = "win" ]; then
    _W_POS="${2:-}"
    if [ -z "$_W_POS" ]; then
        echo "Usage: meister win <left|right|max|center|tl|tr|bl|br>"
        echo "  Positioniert das vorderste Fenster (braucht Bedienungshilfen-Rechte fuers Terminal)."
        echo "  Hinweis: Geometrie bezieht sich auf den Gesamt-Desktop — bei mehreren"
        echo "  Displays landet das Fenster ggf. auf dem falschen. Single-Display: exakt."
        exit 1
    fi
    _W_BOUNDS=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null)
    _W_SW=$(echo "$_W_BOUNDS" | awk -F', ' '{print $3}')
    _W_SH=$(echo "$_W_BOUNDS" | awk -F', ' '{print $4}')
    if [ -z "$_W_SW" ] || [ -z "$_W_SH" ]; then echo "  [ERROR] Bildschirmgroesse nicht lesbar"; exit 1; fi
    _W_MB=25  # menu bar
    _W_HW=$((_W_SW / 2)); _W_HH=$(( (_W_SH - _W_MB) / 2 ))
    case "$_W_POS" in
        left)   _X=0;      _Y=$_W_MB; _W=$_W_HW;  _H=$((_W_SH - _W_MB)) ;;
        right)  _X=$_W_HW; _Y=$_W_MB; _W=$_W_HW;  _H=$((_W_SH - _W_MB)) ;;
        max)    _X=0;      _Y=$_W_MB; _W=$_W_SW;  _H=$((_W_SH - _W_MB)) ;;
        center) _X=$((_W_SW / 8)); _Y=$((_W_MB + (_W_SH - _W_MB) / 8)); _W=$((_W_SW * 3 / 4)); _H=$(( (_W_SH - _W_MB) * 3 / 4 )) ;;
        tl)     _X=0;      _Y=$_W_MB;               _W=$_W_HW; _H=$_W_HH ;;
        tr)     _X=$_W_HW; _Y=$_W_MB;               _W=$_W_HW; _H=$_W_HH ;;
        bl)     _X=0;      _Y=$((_W_MB + _W_HH));   _W=$_W_HW; _H=$_W_HH ;;
        br)     _X=$_W_HW; _Y=$((_W_MB + _W_HH));   _W=$_W_HW; _H=$_W_HH ;;
        *) echo "Unbekannte Position: $_W_POS (left|right|max|center|tl|tr|bl|br)"; exit 1 ;;
    esac
    if ! osascript >/dev/null 2>&1 <<WINEOF
tell application "System Events"
    set frontApp to first application process whose frontmost is true
    tell front window of frontApp
        set position to {${_X}, ${_Y}}
        set size to {${_W}, ${_H}}
    end tell
end tell
WINEOF
    then
        echo "  [ERROR] Fenster nicht steuerbar — Terminal braucht Bedienungshilfen-Rechte:"
        echo "  Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen"
        exit 1
    fi
    exit 0
fi

# ── Clipboard History (meister clip) — Maccy-style ──
# ACHTUNG: speichert Klartext (chmod 600). Passwoerter, die kopiert werden,
# landen mit in der History — --purge loescht alles sofort.
if [ "${1:-}" = "clip" ]; then
    _C_HIST="$MEISTER_DIR/clip.history"
    _C_AGENT="$HOME/Library/LaunchAgents/com.meister.clip.plist"
    _C_SEP="\x1e----MEISTERCLIP----"
    _C_SELF=$(command -v meister 2>/dev/null)
    [ -z "$_C_SELF" ] && _C_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    case "${2:-}" in
        --install)
            touch "$_C_HIST" && chmod 600 "$_C_HIST"
            cat > "$_C_AGENT" <<CLIPEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>com.meister.clip</string>
    <key>ProgramArguments</key><array>
        <string>/bin/bash</string>
        <string>${_C_SELF}</string>
        <string>clip</string>
        <string>--snap</string>
    </array>
    <key>StartInterval</key><integer>5</integer>
</dict></plist>
CLIPEOF
            launchctl bootout "gui/$(id -u)/com.meister.clip" 2>/dev/null
            launchctl bootstrap "gui/$(id -u)" "$_C_AGENT" 2>/dev/null \
                && echo "  Clipboard-History aktiv (5s-Intervall, ~/.meister/clip.history, chmod 600)" \
                || echo "  [WARN] bootstrap fehlgeschlagen"
            echo "  ACHTUNG: kopierte Passwoerter landen im Klartext in der History (meister clip --purge loescht)"
            ;;
        --uninstall)
            launchctl bootout "gui/$(id -u)/com.meister.clip" 2>/dev/null
            rm -f "$_C_AGENT"
            echo "  Clipboard-Watcher entfernt (History bleibt: $_C_HIST)"
            ;;
        --purge)
            rm -f "$_C_HIST" "$_C_HIST.last" "$_C_HIST.tmp"; echo "  History geloescht"
            ;;
        --snap)
            _C_CUR=$(pbpaste 2>/dev/null | head -c 10240)
            [ -z "$_C_CUR" ] && exit 0
            # dedup via companion file (robust vs. awk-RS quirks across awks)
            _C_LAST=$(cat "$_C_HIST.last" 2>/dev/null)
            [ "$_C_CUR" = "$_C_LAST" ] && exit 0
            # ensure 600 BEFORE writing — --purge removes the file and the
            # agent would otherwise recreate it umask-default world-readable
            if [ ! -f "$_C_HIST" ]; then : > "$_C_HIST"; chmod 600 "$_C_HIST"; fi
            printf '%s' "$_C_CUR" > "$_C_HIST.last"; chmod 600 "$_C_HIST.last"
            { printf '\x1e----MEISTERCLIP----\n'; printf '%s\n' "$_C_CUR"; } >> "$_C_HIST"
            # keep last 200 entries
            _C_N=$(grep -c $'\x1e----MEISTERCLIP----' "$_C_HIST" 2>/dev/null || echo 0)
            if [ "${_C_N:-0}" -gt 200 ]; then
                awk -v RS="$(printf '\x1e')----MEISTERCLIP----\n" -v keep=200 \
                    'NR>1 {a[NR]=$0} END {for (i=NR-keep+1; i<=NR; i++) printf "\x1e----MEISTERCLIP----\n%s", a[i]}' \
                    "$_C_HIST" > "$_C_HIST.tmp" && mv "$_C_HIST.tmp" "$_C_HIST" && chmod 600 "$_C_HIST"
            fi
            ;;
        ''|*[0-9]*)
            if [ ! -s "$_C_HIST" ]; then
                echo "  Keine History. Aktivieren: meister clip --install"; exit 0
            fi
            if [ -n "${2:-}" ]; then
                _C_PICK=$(awk -v RS="$(printf '\x1e')----MEISTERCLIP----\n" -v n="$2" 'NR==n+1 {printf "%s", $0}' "$_C_HIST")
                if [ -n "$_C_PICK" ]; then
                    printf '%s' "$_C_PICK" | sed -e '$ { /^$/d; }' | pbcopy
                    echo "  Eintrag $2 → Zwischenablage"
                else
                    echo "  Eintrag $2 nicht gefunden"
                fi
                exit 0
            fi
            echo -e "\033[1;34m  MEISTER CLIP — Clipboard-History (Maccy-Style)\033[0m"
            echo ""
            awk -v RS="$(printf '\x1e')----MEISTERCLIP----\n" \
                'NR>1 {line=$0; sub(/\n.*/,"",line); if (length(line)>70) line=substr(line,1,67)"..."; a[NR-1]=line}
                 END {n=NR-1; start=(n>20)?n-19:1; for (i=n; i>=start && i>=1; i--) printf "  [%d] %s\n", i, a[i]}' "$_C_HIST"
            echo ""
            echo "  Kopieren: meister clip <nr>   Loeschen: meister clip --purge"
            ;;
    esac
    exit 0
fi

# ── Key Remapping (meister keys) — Karabiner-light via hidutil ──
if [ "${1:-}" = "keys" ]; then
    _K_AGENT="$HOME/Library/LaunchAgents/com.meister.keys.plist"
    _K_MODE="${2:-status}"
    _k_map() {  # $1: JSON UserKeyMapping array
        hidutil property --set "{\"UserKeyMapping\":$1}" >/dev/null 2>&1
    }
    _k_persist() {  # $1: JSON array — LaunchAgent re-applies after reboot
        cat > "$_K_AGENT" <<KEYSEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>com.meister.keys</string>
    <key>ProgramArguments</key><array>
        <string>/usr/bin/hidutil</string>
        <string>property</string>
        <string>--set</string>
        <string>{"UserKeyMapping":$1}</string>
    </array>
    <key>RunAtLoad</key><true/>
</dict></plist>
KEYSEOF
        launchctl bootout "gui/$(id -u)/com.meister.keys" 2>/dev/null
        launchctl bootstrap "gui/$(id -u)" "$_K_AGENT" 2>/dev/null
    }
    # HID usage IDs: CapsLock 0x39, Escape 0x29, LeftCtrl 0xE0 (+0x700000000)
    case "$_K_MODE" in
        caps2esc)
            _K_JSON='[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x700000029}]'
            _k_map "$_K_JSON" && _k_persist "$_K_JSON" && echo "  Caps Lock → Escape (persistent via LaunchAgent)" ;;
        caps2ctrl)
            _K_JSON='[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000E0}]'
            _k_map "$_K_JSON" && _k_persist "$_K_JSON" && echo "  Caps Lock → Control (persistent via LaunchAgent)" ;;
        reset)
            _k_map '[]'
            launchctl bootout "gui/$(id -u)/com.meister.keys" 2>/dev/null
            rm -f "$_K_AGENT"
            echo "  Key-Mapping zurueckgesetzt" ;;
        status)
            echo -e "\033[1;34m  MEISTER KEYS — Tastatur-Remapping (hidutil)\033[0m"
            echo ""
            _K_ACTIVE=$(hidutil property --get "UserKeyMapping" 2>/dev/null | grep -v '(null)' | grep -E 'Mapping(Src|Dst)|^\(' | head -15)
            if [ -n "$_K_ACTIVE" ]; then
                echo "  Aktives Mapping:"
                echo "$_K_ACTIVE" | sed 's/^/    /'
            else
                echo "  Kein Mapping aktiv"
            fi
            [ -f "$_K_AGENT" ] && echo "  Persistent: ja (com.meister.keys LaunchAgent)"
            echo ""
            echo "  Befehle: meister keys caps2esc | caps2ctrl | reset" ;;
        *) echo "Usage: meister keys [caps2esc|caps2ctrl|reset|status]"; exit 1 ;;
    esac
    exit 0
fi

# ── Touch ID for sudo (meister touchid) ──
# Writes pam_tid.so into /etc/pam.d/sudo_local (Sonoma+: survives macOS updates,
# unlike editing /etc/pam.d/sudo directly). One sudo password — then fingerprint.
if [ "${1:-}" = "touchid" ]; then
    echo -e "\033[1;34m  MEISTER TOUCHID — Touch ID for sudo\033[0m"
    echo ""
    _PAM_LOCAL="/etc/pam.d/sudo_local"
    _PAM_TEMPLATE="/etc/pam.d/sudo_local.template"

    if [ "${2:-}" = "--off" ]; then
        if [ -f "$_PAM_LOCAL" ] && grep -q pam_tid "$_PAM_LOCAL" 2>/dev/null; then
            sudo sed -i '' '/pam_tid/d' "$_PAM_LOCAL" && echo "  Touch ID for sudo DISABLED"
        else
            echo "  Touch ID for sudo was not enabled"
        fi
        exit 0
    fi

    if grep -qE '^auth.*pam_tid' "$_PAM_LOCAL" 2>/dev/null; then
        echo "  Already enabled ($_PAM_LOCAL)"
        echo "  Test: sudo -k && sudo true   → Touch ID prompt instead of password"
        exit 0
    fi

    if ! bioutil -rs 2>/dev/null | grep -qiE 'Touch ID|functionality: 1'; then
        echo "  NOTE: no Touch ID sensor detected on this Mac."
        echo "  On a desktop Mac this needs a Magic Keyboard with Touch ID."
        echo "  Enabling is safe anyway — sudo falls back to password without a sensor."
        echo ""
    fi

    echo "  Writing $_PAM_LOCAL (needs sudo once)..."
    if [ -f "$_PAM_TEMPLATE" ]; then
        sed 's/^#auth/auth/' "$_PAM_TEMPLATE" | sudo tee "$_PAM_LOCAL" >/dev/null
    else
        printf 'auth       sufficient     pam_tid.so\n' | sudo tee "$_PAM_LOCAL" >/dev/null
    fi

    if grep -qE '^auth.*pam_tid' "$_PAM_LOCAL" 2>/dev/null; then
        echo "  Touch ID for sudo ENABLED ($_PAM_LOCAL — survives macOS updates)"
        echo "  Test: sudo -k && sudo true"
        echo "  Undo: meister touchid --off"
    else
        echo "  [ERROR] Write failed — check $_PAM_LOCAL manually"
        exit 1
    fi
    exit 0
fi

# ── Time Machine setup (meister backup) ──
if [ "${1:-}" = "backup" ]; then
    echo -e "\033[1;34m  MEISTER BACKUP — Time Machine status & setup\033[0m"
    echo ""
    if ! command_exists tmutil; then echo "  tmutil not available"; exit 1; fi

    # destinationinfo exits 0 even with no destination — check the output
    if ! tmutil destinationinfo 2>&1 | grep -qi "No destinations"; then
        echo "  Destination configured:"
        tmutil destinationinfo 2>/dev/null | sed -n 's/^Name[[:space:]]*: */    Name: /p; s/^Mount Point[[:space:]]*: */    Mount: /p; s/^URL[[:space:]]*: */    URL:  /p'
        _latest=$(tmutil latestbackup 2>/dev/null | tail -1)
        if [ -n "$_latest" ]; then
            echo "    Latest backup: $(basename "$_latest")"
        else
            echo "    Latest backup: NONE yet"
        fi
        if [ "${2:-}" = "--now" ]; then
            echo ""
            echo "  Starting backup..."
            tmutil startbackup --auto 2>/dev/null && echo "  Backup started (runs in background)"
        else
            echo ""
            echo "  Start one now with: meister backup --now"
        fi
        exit 0
    fi

    echo "  No Time Machine destination configured — this Mac is a SINGLE COPY."
    echo ""
    _candidates=$(tm_candidate_volumes)
    if [ -z "$_candidates" ]; then
        echo "  No suitable local volume attached (APFS/HFS, writable, non-boot)."
        echo "  Plug in an external disk and re-run: meister backup"
        exit 0
    fi

    echo "  Attached volumes usable as TM destination:"
    _i=0
    while IFS='|' read -r _cvol _cfree; do
        _i=$((_i + 1))
        printf '    [%d] %s (%s free)\n' "$_i" "$_cvol" "$_cfree"
        eval "_CAND_${_i}=\$_cvol"
    done <<EOF
$_candidates
EOF
    echo ""
    if [ ! -t 0 ]; then
        echo "  (non-interactive — pick a volume and run: sudo tmutil setdestination -a '<volume>')"
        exit 0
    fi
    printf '  Choose volume [1-%d, Enter=abort]: ' "$_i"
    read -r _choice
    case "$_choice" in
        ''|*[!0-9]*) echo "  Aborted"; exit 0 ;;
    esac
    [ "$_choice" -ge 1 ] && [ "$_choice" -le "$_i" ] || { echo "  Invalid choice"; exit 1; }
    eval "_target=\$_CAND_${_choice}"
    echo ""
    echo "  Setting '$_target' as Time Machine destination (needs sudo)..."
    if sudo tmutil setdestination -a "$_target"; then
        sudo tmutil enable 2>/dev/null
        echo "  Destination set + automatic backups enabled."
        printf '  Start first backup now? [y/N]: '
        read -r _go
        [ "$_go" = "y" ] || [ "$_go" = "Y" ] && tmutil startbackup --auto && echo "  First backup started (background)"
    else
        echo "  [ERROR] setdestination failed — is the volume APFS/HFS+ and writable?"
        exit 1
    fi
    exit 0
fi

# ── Run-History Report (meister report) ──
if [ "${1:-}" = "report" ]; then
    _N="${2:-10}"
    case "$_N" in *[!0-9]*) echo "Usage: meister report [N]"; exit 1 ;; esac
    _hist="$MEISTER_DIR/history.log"
    [ -f "$_hist" ] || { echo "  No history yet ($_hist)"; exit 0; }
    echo -e "\033[1;34m  MEISTER REPORT — last ${_N} runs\033[0m"
    echo ""
    printf '  %-19s %9s %4s %4s %5s %4s %5s  %s\n' "Date" "Duration" "OK" "FIX" "WARN" "ERR" "HEAL" "Slowest modules"
    printf '  '; printf '─%.0s' $(seq 1 76); echo ""
    tail -n "$_N" "$_hist" | awk -F' \\| ' '{
        ok=fix=warn=err=heal="-"
        n=split($3, a, " ")
        for (i=1; i<=n; i++) {
            split(a[i], kv, ":")
            if (kv[1]=="OK") ok=kv[2]; else if (kv[1]=="FIX") fix=kv[2]
            else if (kv[1]=="WARN") warn=kv[2]; else if (kv[1]=="ERR") err=kv[2]
            else if (kv[1]=="HEAL") heal=kv[2]
        }
        top=$4; sub(/^top: /, "", top)
        printf "  %-19s %9s %4s %4s %5s %4s %5s  %s\n", $1, $2, ok, fix, warn, err, heal, top
    }'
    echo ""
    tail -n "$_N" "$_hist" | awk -F' \\| ' '
    function dur2s(d,   m, s) {
        if (match(d, /^[0-9]+m/)) { m = substr(d, 1, RLENGTH-1) + 0 }
        if (match(d, /[0-9]+s$/)) { s = substr(d, RSTART, RLENGTH-1) + 0 }
        return m*60 + s
    }
    {
        runs++; secs = dur2s($2); total += secs
        if (secs > maxs) { maxs = secs; maxd = $1 }
        n = split($3, a, " ")
        for (i=1; i<=n; i++) { split(a[i], kv, ":"); if (kv[1]=="ERR") errs += kv[2] }
    }
    END {
        if (!runs) exit
        printf "  Runs: %d   Avg duration: %dm%02ds   Longest: %dm%02ds (%s)   Total errors: %d\n", \
            runs, int(total/runs/60), int(total/runs)%60, int(maxs/60), maxs%60, maxd, errs
    }'
    exit 0
fi

if [ "${1:-}" = "free" ]; then
    echo -e "\033[1;34m  MEISTER FREE — Free up RAM & reset UI\033[0m"
    echo ""
    _ram_before=$(vm_stat | awk '/Pages free/ {gsub("\\.",""); printf "%d", $3 * 4 / 1024}')
    echo "  RAM free before: ${_ram_before} MB"
    echo "  Running sudo purge (may take 10-30s)..."
    if sudo -v && sudo purge; then
        _ram_after=$(vm_stat | awk '/Pages free/ {gsub("\\.",""); printf "%d", $3 * 4 / 1024}')
        echo "  RAM free after:  ${_ram_after} MB  (Δ +$((_ram_after - _ram_before)) MB)"
    else
        echo "  Purge needs sudo"
    fi
    if [ "${2:-}" = "--restart-ui" ]; then
        echo "  Restarting Finder + Dock..."
        killall Finder 2>/dev/null
        killall Dock 2>/dev/null
        killall SystemUIServer 2>/dev/null
    fi
    exit 0
fi

# ── Healer (meister heal) ──
if [ "${1:-}" = "heal" ]; then
    echo -e "\033[1;34m  MEISTER HEAL — Auto-Healing\033[0m"
    echo ""
    DRY_RUN=false
    [ "${2:-}" = "--dry-run" ] && DRY_RUN=true
    $DRY_RUN && echo "  [DRY-RUN MODE — no changes]" && echo ""
    # Cache sudo upfront so system-bin fixes don't fail mid-run
    if ! $DRY_RUN && [ "$(id -u)" -ne 0 ]; then
        if [ -t 0 ]; then
            sudo -v 2>/dev/null || log WARN "sudo unavailable — some fixes will skip"
        fi
    fi
    MODULE_TOTAL=1
    start_bw_monitor
    bw_set_status 1 1 "Healer"
    module_healer
    stop_bw_monitor
    exit 0
fi

# ── Speedtest (meister speed) ──
if [ "${1:-}" = "speed" ]; then
    echo -e "\033[1;34m  MEISTER SPEED — Network Speed Test\033[0m"
    echo ""

    # Latency
    echo -e "  \033[1mLatency\033[0m"
    for target in 1.1.1.1 8.8.8.8 apple.com; do
        ms=$(ping -c 3 -t 5 "$target" 2>/dev/null | tail -1 | awk -F'/' '{printf "%.1f", $5}')
        if [ -n "$ms" ] && [ "$ms" != "0.0" ]; then
            printf '  %-15s  %s ms\n' "$target" "$ms"
        else
            printf '  %-15s  timeout\n' "$target"
        fi
    done
    echo ""

    # Download speed (3x 10MB from Cloudflare, best of 3)
    echo -e "  \033[1mDownload\033[0m"
    echo "  Testing (3x 10MB from Cloudflare)..."
    dl_best=0
    for _i in 1 2 3; do
        _dl=$(curl -o /dev/null -w '%{speed_download}' -s --max-time 15 \
            "https://speed.cloudflare.com/__down?bytes=10485760" 2>/dev/null)
        _dl_cmp=$(echo "$_dl $dl_best" | awk '{if($1>$2) print 1; else print 0}')
        [ "$_dl_cmp" = "1" ] && dl_best="$_dl"
        _dl_mb=$(echo "$_dl" | awk '{printf "%.1f", $1/1048576}')
        printf '  Run %s: %s MB/s\n' "$_i" "$_dl_mb"
    done
    dl_speed=$(echo "$dl_best" | awk '{printf "%.1f", $1/1048576}')
    dl_mbps=$(echo "$dl_best" | awk '{printf "%.0f", $1/1048576 * 8}')
    echo "  Best: ${dl_speed} MB/s = ${dl_mbps} Mbps"
    echo ""

    # Upload speed (smaller payload)
    echo -e "  \033[1mUpload\033[0m"
    echo "  Testing (10MB to Cloudflare)..."
    ul_result=$(dd if=/dev/zero bs=1048576 count=10 2>/dev/null | \
        curl -o /dev/null -w '%{speed_upload} %{time_total}' -s --max-time 15 \
        -X POST --data-binary @- "https://speed.cloudflare.com/__up" 2>/dev/null)
    ul_speed=$(echo "$ul_result" | awk '{printf "%.1f", $1/1048576}')
    ul_time=$(echo "$ul_result" | awk '{printf "%.1f", $2}')
    echo "  Upload: ${ul_speed} MB/s (${ul_time}s)"
    ul_mbps=$(echo "$ul_speed" | awk '{printf "%.0f", $1 * 8}')
    echo "  = ${ul_mbps} Mbps"
    echo ""

    # Summary
    printf '  \033[1mSummary\033[0m\n'
    printf '  ↓ %s Mbps  ↑ %s Mbps\n' "$dl_mbps" "$ul_mbps"
    exit 0
fi

# Fix #117: Long-Options before getopts abfangen (getopts kann only Short-Options)
for arg in "$@"; do
    case "$arg" in
        --help)    set -- "-h"; break ;;
        --version) echo "meister v${MEISTER_VERSION}"; exit 0 ;;
        --dry-run) set -- "-n"; break ;;
        --menu)    set -- "menu"; break ;;
        --*)       echo "[ERROR] Unknown option: $arg (see meister -h)"; exit 1 ;;
    esac
done

# ── Args ──
while getopts ":aAXTSCLhcHnIPGNq" opt; do
  case $opt in
    a) CLEAN_XCODE=true; EMPTY_TRASH=true
       RUN_SUDO_TASKS=true; CLEAN_CACHES=true; LIST_LARGE_FILES=true; RUN_PERF_TUNE=true; RUN_GIT_REPOS=true; RUN_SNIFFNET=true ;;
    G) RUN_GIT_REPOS=true ;;
    N) RUN_SNIFFNET=true ;;
    P) RUN_PERF_TUNE=true ;;
    A) log WARN "ClamAV removed - XProtect runs in Security Suite" ;;
    X) CLEAN_XCODE=true ;;
    T) EMPTY_TRASH=true ;;
    S) RUN_SUDO_TASKS=true ;;
    C) CLEAN_CACHES=true ;;
    L) LIST_LARGE_FILES=true ;;
    c) log WARN "ClamAV removed - XProtect runs in Security Suite" ;;
    H) SHOW_HEALTH=true ;;
    n) DRY_RUN=true ;;
    q) QUIET_MODE=true ;;
    I) INSTALL_LAUNCHAGENT=true ;;
    h) cat << 'HELPEOF'
Meister - macOS Maintenance, Self-Healing & Dotfiles Sync

MAINTENANCE:
  meister              Auto-detect (default)
  meister menu         Interactive menu (TUI)
  meister -a           Force all modules
  meister -n           Dry-run
  meister -q           Quiet (warnings/fixes only)
  meister -H           Health dashboard
  meister -I           Install LaunchAgent

  OVERRIDES:  -X Xcode  -T Trash  -S Sudo  -C Caches
              -L Large files  -P Performance  -G Git
              -N Sniffnet (network monitor)

TOOLS:
  meister sniff [N]    Live network monitor (default: 3s refresh)
  meister ntop [N]     Live network traffic top 10 (default: 3s)
  meister disk [dir]   Disk space analyzer (default: ~)
  meister ports        Open ports & listeners
  meister dns          DNS leak test
  meister battery      Battery health report
  meister heal [--dry-run]  Proactive auto-healer (broken symlinks, orphans, DNS, casks)
  meister free [--restart-ui]  Free RAM (sudo purge) + optionally restart Finder/Dock
  meister simfix       Fix stuck iOS Simulator (kill stale procs, reset CoreSimulator)
  meister startup      Login items & launch agents audit
  meister wifi         Wi-Fi diagnostics & channel scan
  meister top [N]      Live process monitor (default: 3s refresh)
  meister certs [host] SSL certificate checker
  meister thermal [N]  Live temperature & fan monitor (default: 2s)
  meister speed        Download/upload speed test
  meister report [N]   Run-history report from history.log (default: last 10)
  meister score        Maintenance score 0-100 + trend history
  meister diff         What changed since the last run (apps/autostart/brew)
  meister undo [--do]  Revert the last run's reversible actions (--list)
  meister explain <x>  Ollama explains a warning in plain language
  meister fleet        Score/status of all Macs (FLEET_HOSTS in config)
  meister touchid [--off]  Touch ID for sudo (pam_tid in /etc/pam.d/sudo_local)
  meister backup [--now]   Time Machine status; set up destination if none
  meister dash [N]     Live system dashboard: CPU/RAM/Disk/Netz (Stats-style)
  meister files <x>    Who has port/file/process open (Sloth-style lsof)
  meister ai           AI system diagnosis via local Ollama (read-only)

SECURITY:
  meister pkg <file>   Inspect .pkg BEFORE install: signature, payload, scripts
  meister watch        Persistence watcher: notify on new LaunchAgents/Daemons
                       (--install / --uninstall / --check)
  meister tcc-clean [--do]  Remove privacy grants of DELETED apps (FDA list etc.)

SYSTEM:
  meister tweaks       Hidden macOS settings (OnyX-style): showhidden,
                       extensions, pathbar, keyrepeat, savepanel, dockfast
  meister adopt [--do] Bring unmanaged /Applications apps under brew (updates!)
  meister appupdates   ALL app updates in one list: brew + App Store + Sparkle
  meister win <pos>    Move frontmost window: left|right|max|center|tl|tr|bl|br
  meister clip         Clipboard history (Maccy-style): --install, <nr>, --purge
  meister keys <mode>  Key remapping: caps2esc | caps2ctrl | reset | status

APP MANAGEMENT:
  meister remove <App> [--dry-run] [--purge] [-y]
                       Uninstall app + all leftovers (caches, prefs, containers,
                       saved state, logs). Default: to Trash (reversible). --purge: rm.
  meister orphans [--dry-run] [--purge] [-y]
                       Scan ~/Library + /Library for leftovers of apps that are no
                       longer installed; pick which to remove. Default: Trash.

DOTFILES SYNC:
  meister push         Collect configs, commit, push
  meister pull         Pull latest, create symlinks
  meister setup [url]  Clone dotfiles repo (auto-detects from gh)
  meister init [name]  Create private GitHub repo + push
  meister scan         Auto-detect configs, generate manifest
  meister clone        Clone ~/Developer repos
  meister bootstrap    Full setup: pull + brew + npm + clone + defaults
  meister status       Check symlinks

Config: ~/.meister/config
HELPEOF
       exit 0 ;;
    \?) log ERROR "Unknown option: -$OPTARG"; exit 1 ;;
  esac
done

MANUAL_FLAGS_SET=false
$CLEAN_XCODE && MANUAL_FLAGS_SET=true
$EMPTY_TRASH && MANUAL_FLAGS_SET=true
$RUN_SUDO_TASKS && MANUAL_FLAGS_SET=true
$CLEAN_CACHES && MANUAL_FLAGS_SET=true
$LIST_LARGE_FILES && MANUAL_FLAGS_SET=true
$RUN_PERF_TUNE && MANUAL_FLAGS_SET=true
$RUN_GIT_REPOS && MANUAL_FLAGS_SET=true
$RUN_SNIFFNET && MANUAL_FLAGS_SET=true

auto_detect() {
    log INFO "Auto-Detect: Analyzing system..."
    local detected=0

    # 1. Xcode DerivedData
    local xcpath="$HOME/Library/Developer/Xcode/DerivedData"
    if [ -d "$xcpath" ]; then
        local xc_mb=$(du -sm "$xcpath" 2>/dev/null | awk '{print $1}')
        xc_mb=${xc_mb:-0}
        if [ "$xc_mb" -ge "$AUTO_XCODE_THRESHOLD_MB" ]; then
            CLEAN_XCODE=true
            detected=$((detected + 1))
            log STEP "   Xcode DerivedData: ${xc_mb}MB (>= ${AUTO_XCODE_THRESHOLD_MB}MB) → enabled"
        else
            log STEP "   Xcode DerivedData: ${xc_mb}MB (< ${AUTO_XCODE_THRESHOLD_MB}MB) → OK"
        fi
    fi

    # 2. Papierkorb
    if [ -d "$HOME/.Trash" ]; then
        local trash_items=$(( $(ls -1A "$HOME/.Trash" 2>/dev/null | wc -l) ))
        local trash_mb=$(du -sm "$HOME/.Trash" 2>/dev/null | awk '{print $1}')
        trash_mb=${trash_mb:-0}
        if [ "$trash_items" -ge "$AUTO_TRASH_THRESHOLD_ITEMS" ] || [ "$trash_mb" -ge "$AUTO_TRASH_THRESHOLD_MB" ]; then
            EMPTY_TRASH=true
            detected=$((detected + 1))
            log STEP "   Trash: ${trash_items} items, ${trash_mb}MB → enabled"
        else
            log STEP "   Trash: ${trash_items} items, ${trash_mb}MB → OK"
        fi
    fi

    # 3. User Caches
    if [ -d "$HOME/Library/Caches" ]; then
        local cache_mb=$(du -sm "$HOME/Library/Caches" 2>/dev/null | awk '{print $1}')
        cache_mb=${cache_mb:-0}
        if [ "$cache_mb" -ge "$AUTO_CACHE_THRESHOLD_MB" ]; then
            CLEAN_CACHES=true
            detected=$((detected + 1))
            log STEP "   User Caches: ${cache_mb}MB (>= ${AUTO_CACHE_THRESHOLD_MB}MB) → enabled"
        else
            log STEP "   User Caches: ${cache_mb}MB (< ${AUTO_CACHE_THRESHOLD_MB}MB) → OK"
        fi
    fi

    # 4. Disk Usage → grosse Files listen
    local disk_usage=$(df -H / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    disk_usage=${disk_usage:-0}
    if [ "$disk_usage" -ge "$DISK_USAGE_THRESHOLD" ]; then
        LIST_LARGE_FILES=true
        detected=$((detected + 1))
        log STEP "   Disk: ${disk_usage}% used (>= ${DISK_USAGE_THRESHOLD}%) → grosse Files listen"
    else
        log STEP "   Disk: ${disk_usage}% used → OK"
    fi

    # 5. periodic scripts (sudo tasks)
    local daily_log="/var/log/daily.out"
    if [ -f "$daily_log" ]; then
        local daily_age_days=$(( ( $(date +%s) - $(stat -f %m "$daily_log" 2>/dev/null || echo 0) ) / 86400 ))
        if [ "$daily_age_days" -ge "$AUTO_PERIODIC_INTERVAL_DAYS" ]; then
            RUN_SUDO_TASKS=true
            detected=$((detected + 1))
            log STEP "   periodic scripts: ${daily_age_days} days old (>= ${AUTO_PERIODIC_INTERVAL_DAYS}) → enabled"
        else
            log STEP "   periodic scripts: ${daily_age_days} days old → OK"
        fi
    else
        # No Log → wahrscheinlich still nie gelaufen
        RUN_SUDO_TASKS=true
        detected=$((detected + 1))
        log STEP "   periodic scripts: no log found → enabled"
    fi

    # 7. Performance + Git (bestehende Auto-Logik beibehalten)
    if $SELFHEAL_PERF_AUTO; then
        RUN_PERF_TUNE=true
        detected=$((detected + 1))
        log STEP "   Performance tuning: SELFHEAL_PERF_AUTO=true → enabled"
    fi
    log INFO "Auto-Detect: ${detected} modules auto-enabled"
}

if ! $MANUAL_FLAGS_SET && $AUTO_DETECT && ! $SHOW_HEALTH && ! $INSTALL_LAUNCHAGENT; then
    auto_detect
else
    # Manuelle Flags gesetzt or Auto-Detect disabled - bestehende Logik
    if $SELFHEAL_PERF_AUTO && ! $RUN_PERF_TUNE; then
        RUN_PERF_TUNE=true
    fi
fi

# ── START ──
rotate_logs
acquire_lock

echo -e "${BOLD}${BLUE}"
echo "  ╔══════════════════════════════════════════╗"
printf '  ║        MEISTER v%-24s║\n' "$MEISTER_VERSION"
echo "  ║   macOS Maintenance & Self-Healing           ║"
$DRY_RUN && echo "  ║   [DRY-RUN MODE]                        ║"
! $MANUAL_FLAGS_SET && $AUTO_DETECT && echo "  ║   [AUTO-DETECT]                          ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

start_bw_monitor
log INFO "Meister v${MEISTER_VERSION} started ($(date))"
$DRY_RUN && log WARN "DRY-RUN: No changes will be made"
log STEP "   Logfile: $LOGFILE"
[ -f "$MEISTER_CONFIG" ] && log STEP "   Config: $MEISTER_CONFIG loaded"
if ! $MANUAL_FLAGS_SET && $AUTO_DETECT; then
    log STEP "   Mode: AUTO-DETECT"
else
    log STEP "   Mode: MANUAL"
fi
log STEP "   Module: XCODE=$CLEAN_XCODE TRASH=$EMPTY_TRASH SUDO=$RUN_SUDO_TASKS CACHE=$CLEAN_CACHES LARGE=$LIST_LARGE_FILES PERF=$RUN_PERF_TUNE GIT=$RUN_GIT_REPOS DRY=$DRY_RUN"

if $SHOW_HEALTH; then health_dashboard; release_lock; exit 0; fi
if $INSTALL_LAUNCHAGENT; then install_launchagent; release_lock; exit 0; fi

# Fix #145: Get sudo FIRST - before Ollama and all modules
# Prevents password prompt mid-run (e.g. during brew cask upgrade)
if ! $DRY_RUN && $NEEDS_SUDO; then
    # Fix #161 (2026-05): seed sudo up-front via the CONTROLLING TERMINAL, not just stdin.
    # When meister is launched with stdin redirected (pipe / wrapper / launchd), [ -t 0 ]
    # is false, so the old code skipped the interactive `sudo -v` and never started
    # keep_sudo. `brew upgrade --cask --greedy` then hit sudo, which prompts on /dev/tty,
    # and blocked mid-run on "Password:". Prompt up-front whenever a tty is reachable.
    if sudo -n true 2>/dev/null; then
        keep_sudo
        log INFO "   Sudo OK (cached)"
    elif [ -t 0 ] || ( : < /dev/tty ) 2>/dev/null; then
        log INFO "Requesting Sudo (once — everything else runs non-interactive)..."
        if sudo -v < /dev/tty; then
            keep_sudo
            log INFO "   Sudo OK"
        else
            log WARN "Sudo denied or timeout - sudo tasks will be skipped (NO further prompts)"
            log INFO "   Sudo not available"
            NEEDS_SUDO=false
        fi
    else
        log WARN "No TTY + no Sudo-Cache - sudo-Operationen skipped"
        log INFO "   Sudo not available (non-interactive)"
        NEEDS_SUDO=false
    fi
fi

# Fix #41: Central Ollama startingr + Fix #45: Model check
if ollama_available || ensure_ollama_running ""; then
    log INFO "Ollama: online (${OLLAMA_MODEL})"
    local_models=$(ollama_list_cached | awk 'NR>1 {print $1}' | tr '\n' ', ')
    log STEP "   Models: ${local_models:-none}"
    ensure_ollama_model
else
    log WARN "Ollama: not available - no AI-Heal"
    OLLAMA_ENABLED=false
fi

# Modul-Anzahl berechnen (14 core + 10 extras + 1 healer + 5 maintenance + 6 killer + 1 simfix + 1 docs order)
MODULE_TOTAL=39
$RUN_SUDO_TASKS && MODULE_TOTAL=$((MODULE_TOTAL + 1))

# Preflight
section_header "Self-Healing Preflight"
module_timer_start
_pf_fix0=${#REPORT_FIXED[@]}; _pf_warn0=${#REPORT_WARNINGS[@]}; _pf_err0=${#REPORT_ERRORS[@]}
selfheal_preflight
module_timer_stop "Preflight"
ledger_add "Preflight" "$_pf_fix0" "$_pf_warn0" "$_pf_err0" 0

if check_net; then
    run_module_safe "Healer"         module_healer
    run_module_safe "Homebrew"       module_homebrew
    run_module_safe "App Store"      module_mas
    run_module_safe "Ollama Models"  module_ollama
    run_module_safe "Dev Updates"    module_universal_updates
    run_module_safe "macOS System"   module_system
    run_module_safe "Cleanup"        module_cleanup
    run_module_safe "Deep Clean"     module_deepclean
    run_module_safe "Spotlight Fix"  module_spotlight_fix
    run_module_safe "iCloud Fix"     module_icloud_fix
    run_module_safe "Performance"    module_performance
    run_module_safe "Git repos"      module_git_repos
    run_module_safe "Sniffnet"       module_sniffnet
    run_module_safe "Security Suite" module_security_suite
    run_module_safe "Benchmark"      module_benchmark
    run_module_safe "Time Machine"   module_tm_health
    run_module_safe "Battery"        module_battery
    run_module_safe "iOS Simulators" module_ios_sim
    run_module_safe "Docker Prune"   module_docker_prune
    run_module_safe "Kernel Panics"  module_panic_scan
    run_module_safe "SSH Keys"       module_ssh_audit
    run_module_safe "Broken Symlinks" module_broken_symlinks
    run_module_safe "Brew Bottle Age" module_brew_age
    run_module_safe "LaunchDaemons"  module_launchd_orphans
    run_module_safe "Shell History"  module_shell_history
    run_module_safe "APFS Snapshots" module_apfs_snapshots
    run_module_safe "Kext Audit"     module_kext_audit
    run_module_safe "Time Sync"      module_time_sync
    run_module_safe "Render Caches"  module_rendering_caches
    run_module_safe "Receipts Audit" module_receipts_audit
    run_module_safe "Dev Caches"     module_dev_caches
    run_module_safe "node_modules"   module_node_modules_aged
    run_module_safe "Sleep Blockers" module_sleep_blockers
    run_module_safe ".DS_Store"      module_dsstore_cleanup
    run_module_safe "Docs Order"     module_docs_order
    run_module_safe "LaunchServices" module_launchservices_rebuild
    run_module_safe "Privacy Audit"  module_tcc_privacy_audit
    run_module_safe "Simulator Fix"  module_simfix

    if $RUN_SUDO_TASKS; then
        section_header "System maintenance (sudo)"
        module_timer_start
        _sm_fix0=${#REPORT_FIXED[@]}; _sm_warn0=${#REPORT_WARNINGS[@]}; _sm_err0=${#REPORT_ERRORS[@]}
        log INFO "Starting periodic scripts..."
        log STEP "   periodic daily..."
        run_or_dry sudo -n periodic daily
        log STEP "   periodic weekly..."
        run_or_dry sudo -n periodic weekly
        log STEP "   periodic monthly..."
        run_or_dry sudo -n periodic monthly
        log INFO "   DNS cache flush..."
        run_or_dry sudo -n dscacheutil -flushcache
        report_add FIX "Ran periodic scripts & DNS flush"
        module_timer_stop "System maintenance"
        ledger_add "System maintenance" "$_sm_fix0" "$_sm_warn0" "$_sm_err0" 0
    fi
else
    log ERROR "Aborting: No internet"
fi

log_analysis

# v5.25: snapshot system state for `meister diff` (skip in dry-run — no changes)
$DRY_RUN || write_system_snapshot >/dev/null 2>&1

# Fix #141: Ollama stoppen bebefore Report (damit RAM-Info im Report stimmt)
shutdown_ollama

print_report
save_history
send_report_notification
release_lock

# Fix #38: Exit-Code 1 at Errors
[ ${#REPORT_ERRORS[@]} -gt 0 ] && exit 1
exit 0
