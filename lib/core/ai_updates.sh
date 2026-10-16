# shellcheck shell=bash
# Mandatory maintenance step. Update installed clients through their existing
# owners; never install absent clients, kill sessions or silently migrate owners.

ai_brew_client() {
    case "${1##*/}" in
        claude|claude-code|claude-code@latest|codex|codex-app|chatgpt|cursor|windsurf|ollama|ollama-app|jan|lm-studio|aichat|aider|aider-chat|gemini-cli|opencode|goose|github-copilot|llama.cpp) return 0 ;;
        *) return 1 ;;
    esac
}

ai_npm_client() {
    case "$1" in
        @anthropic-ai/claude-code|@openai/codex|@google/gemini-cli|@github/copilot|@qwen-code/qwen-code|@vibe-kit/grok-cli|@kilocode/cli|@sourcegraph/amp|@augmentcode/auggie|opencode-ai) return 0 ;;
        *) return 1 ;;
    esac
}

# Bounded retry, no raw updater output (it can contain account information).
ai_update_attempt() {
    local rc command_label="${1##*/} ${2:-}"
    # Identify the failed operation without exposing arbitrary updater output.
    if timeout 300 "$@" </dev/null >/dev/null 2>&1; then
        return 0
    else
        rc=$?
    fi
    log WARN "AI Updates: $command_label failed (exit $rc); retrying once"
    if timeout 300 "$@" </dev/null >/dev/null 2>&1; then
        return 0
    else
        rc=$?
    fi
    log ERROR "AI Updates: $command_label failed after retry (exit $rc)"
    return "$rc"
}

# The report ledger is not the log. AI-Heal reads the log, so failures must
# reach both to retain the affected client in its evidence.
ai_update_error() {
    log ERROR "$1"
    report_add ERROR "$1"
}

ai_update_native() {
    local label="$1" binary="$2" action="$3" version
    if ${DRY_RUN:-false}; then
        log STEP "[DRY-RUN] AI Updates: $label ($action)"
        return 0
    fi
    if ai_update_attempt "$binary" "$action"; then
        version=$(timeout 30 "$binary" --version </dev/null 2>/dev/null) || version=""
        if [ -n "$version" ]; then
            report_add SUCCESS "AI Updates: $label updater completed; executable verified"
            return 0
        fi
    fi
    ai_update_error "AI Updates: $label update/verification failed"
    return 1
}

# The public starter execs this runtime, preserving its PID. Only its successful
# refresh/cache check can avoid another metadata refresh in this invocation.
ai_brew_metadata_current() {
    [ "${MEISTER_BREW_UPDATE_PID:-}" = "$$" ] || return 1
    [[ "${MEISTER_BREW_UPDATE_AT:-}" =~ ^[0-9]{1,10}$ ]] || return 1
    local age ttl="${BREW_UPDATE_MAX_AGE_SEC:-43200}"
    [[ "$ttl" =~ ^[0-9]{1,10}$ ]] || return 1
    age=$(( $(date +%s) - 10#$MEISTER_BREW_UPDATE_AT ))
    [ "$age" -ge 0 ] || return 1
    [ "${MEISTER_BREW_UPDATE_FRESH:-false}" = true ] || [ "$age" -lt "$((10#$ttl))" ]
}

ai_update_brew() {
    local kind installed token outdated pending checked failed=0 sudo_checked=false
    command -v brew >/dev/null 2>&1 || return 0
    if ${DRY_RUN:-false}; then
        log STEP "[DRY-RUN] AI Updates: refresh Homebrew; upgrade installed AI clients (--greedy)"
        return 0
    fi
    if ai_brew_metadata_current; then
        log STEP "AI Updates: reuse successful Homebrew metadata check from this invocation"
    else
        if ! ai_update_attempt brew update; then
            ai_update_error "AI Updates: Homebrew metadata refresh failed"
            return 1
        fi
        MEISTER_BREW_UPDATE_PID="$$"
        MEISTER_BREW_UPDATE_AT=$(date +%s)
        MEISTER_BREW_UPDATE_FRESH=true
        if [ -n "${MEISTER_DIR:-}" ] && [ -d "$MEISTER_DIR" ]; then
            printf '%s\n' "$MEISTER_BREW_UPDATE_AT" > "$MEISTER_DIR/brew_last_update" 2>/dev/null || :
        fi
    fi
    export HOMEBREW_NO_AUTO_UPDATE=1
    for kind in cask formula; do
        checked=false
        if ! installed=$(timeout 60 brew list "--$kind" 2>/dev/null); then
            ai_update_error "AI Updates: cannot enumerate Homebrew $kind clients"
            failed=1
            continue
        fi
        while IFS= read -r token; do
            ai_brew_client "$token" || continue
            local -a flags=("--$kind")
            if [ "$kind" = cask ]; then
                flags+=(--greedy)
            fi
            if ! $checked; then
                # Without package arguments, outdated returns 0 for a successful
                # list; a named outdated package returns 1, like a probe error.
                if ! pending=$(timeout 60 brew outdated "${flags[@]}" 2>/dev/null); then
                    ai_update_error "AI Updates: cannot check outdated Homebrew $kind clients"
                    failed=1
                    break
                fi
                # brew list uses short names; outdated may qualify tap formulae.
                pending=$(printf '%s\n' "$pending" | sed 's|.*/||')
                checked=true
            fi
            if ! printf '%s\n' "$pending" | grep -Fxq -- "${token##*/}"; then
                report_add SUCCESS "AI Updates: $token current in Homebrew"
                continue
            fi
            if [ "$kind" = cask ] && ! $sudo_checked && command -v ensure_sudo >/dev/null 2>&1; then
                ensure_sudo "AI client cask updates" 2>/dev/null || log WARN "AI Updates: no sudo ticket; admin-owned apps may fail"
                sudo_checked=true
            fi
            if ai_update_attempt brew upgrade "${flags[@]}" "$token" &&
                outdated=$(timeout 60 brew outdated "${flags[@]}" "$token" 2>/dev/null) &&
                [ -z "$outdated" ]; then
                report_add SUCCESS "AI Updates: $token current in Homebrew"
            else
                ai_update_error "AI Updates: $token update/verification failed"
                failed=1
            fi
        done <<< "$installed"
    done
    return "$failed"
}

# npm's shebang uses env node: bind it to the same Node installation, also in
# LaunchAgents. Scan every installed nvm prefix, not just Homebrew's npm.
ai_update_npm() {
    local npm_bin="$1" root package version installed failed=0 dir
    local node_path
    node_path="$(dirname "$npm_bin"):$PATH"
    local PATH="$node_path"
    export PATH
    if ${DRY_RUN:-false}; then
        log STEP "[DRY-RUN] AI Updates: installed AI npm packages via $npm_bin (@latest)"
        return 0
    fi
    if ! root=$(timeout 30 "$npm_bin" root -g 2>/dev/null) || [ ! -d "$root" ]; then
        ai_update_error "AI Updates: cannot discover npm prefix ($npm_bin)"
        return 1
    fi
    for dir in "$root"/* "$root"/@*/*; do
        [ -f "$dir/package.json" ] || continue
        package="${dir#"$root"/}"
        ai_npm_client "$package" || continue
        # Resolve latest explicitly (npm update -g may retain a major version).
        if ! version=$(timeout 60 "$npm_bin" view "$package@latest" version 2>/dev/null) ||
            [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][a-zA-Z0-9.+-]+)?$ ]]; then
            ai_update_error "AI Updates: $package latest version unavailable ($npm_bin)"
            failed=1
            continue
        fi
        installed=$(node -p 'require(process.argv[1]).version' "$dir/package.json" 2>/dev/null) || installed=""
        if [ "$installed" != "$version" ]; then
            if ! ai_update_attempt "$npm_bin" install -g "$package@$version"; then
                ai_update_error "AI Updates: $package installation failed ($npm_bin)"
                failed=1
                continue
            fi
        fi
        installed=$(node -p 'require(process.argv[1]).version' "$dir/package.json" 2>/dev/null) || installed=""
        if [ "$installed" = "$version" ]; then
            report_add SUCCESS "AI Updates: $package $version verified ($npm_bin)"
        else
            ai_update_error "AI Updates: $package version mismatch ($npm_bin)"
            failed=1
        fi
    done
    return "$failed"
}

# Caskroom app artifacts are symlinks to their actual installed location.
# A bundle ID match alone does not make a second, renamed copy managed.
ai_brew_owns_app() {
    local token="$1" app="$2" artifacts artifact target resolved
    artifacts=$(timeout 60 brew list --cask "$token" 2>/dev/null) || return 1
    target=$(realpath "$app" 2>/dev/null) || return 1
    while IFS= read -r artifact; do
        case "$artifact" in *.app)
            resolved=$(realpath "$artifact" 2>/dev/null) || continue
            [ "$resolved" = "$target" ] && return 0 ;;
        esac
    done <<< "$artifacts"
    return 1
}

# Bundle IDs can change or be shared across products. The installed artifact
# path decides ownership, including ChatGPT packages using com.openai.codex.
ai_brew_owns_installed_app() {
    local app="$1" installed="$2" token
    while IFS= read -r token; do
        ai_brew_client "$token" || continue
        ai_brew_owns_app "$token" "$app" && return 0
    done <<< "$installed"
    return 1
}

# Claude's native installation retains its updater; the public release feed
# permits a read-only version check. Never migrate ownership or invoke an updater.
ai_check_claude_desktop() {
    local app="$1" label="${1##*/}" installed feed current
    ${DRY_RUN:-false} && return 0
    if ! timeout 30 /usr/bin/codesign --verify --deep --strict --test-requirement \
        '=anchor apple generic and identifier "com.anthropic.claudefordesktop" and certificate leaf[subject.OU] = "Q6L2SF6YDW"' \
        "$app" >/dev/null 2>&1; then
        report_add WARN "AI Updates: $label Anthropic signature verification failed; current version unverified"
        return 1
    fi
    if ! installed=$(timeout 10 /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null) ||
        [[ ! "$installed" =~ ^[0-9]{1,9}(\.[0-9]{1,9}){2}$ ]]; then
        report_add WARN "AI Updates: $label installed version unavailable or invalid; check for updates in the app"
        return 1
    fi
    if ! feed=$(timeout 25 /usr/bin/curl --disable --fail --silent --show-error --proto '=https' \
        --connect-timeout 10 --max-time 20 --max-filesize 1048576 \
        'https://downloads.claude.ai/releases/darwin/universal/RELEASES.json' 2>/dev/null); then
        report_add WARN "AI Updates: $label Anthropic release feed unavailable; current version unverified"
        return 1
    fi
    # Require a valid current release and its matching update record. Unexpected
    # schema, duplicate JSON keys or partial responses must never mean current.
    if ! current=$(printf '%s' "$feed" | timeout 10 python3 -c '
import json, re, sys
def unique_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate key")
        result[key] = value
    return result
try:
    feed = json.load(sys.stdin, object_pairs_hook=unique_keys)
    if not isinstance(feed, dict):
        raise ValueError("invalid feed")
    current = feed.get("currentRelease")
    releases = feed.get("releases")
    if not isinstance(current, str) or not re.fullmatch(r"[0-9]{1,9}(\.[0-9]{1,9}){2}", current):
        raise ValueError("invalid version")
    if not isinstance(releases, list) or not all(isinstance(item, dict) for item in releases):
        raise ValueError("invalid releases")
    if not any(item.get("version") == current and isinstance(item.get("updateTo"), dict)
               and item["updateTo"].get("version") == current for item in releases):
        raise ValueError("missing current release")
    print(current)
except (ValueError, TypeError):
    sys.exit(1)
' 2>/dev/null); then
        report_add WARN "AI Updates: $label Anthropic release feed invalid; current version unverified"
        return 1
    fi
    if [ "$installed" != "$current" ]; then
        report_add WARN "AI Updates: $label $installed differs from Anthropic current $current; check for updates in the app"
        return 1
    fi
    report_add SUCCESS "AI Updates: $label $installed current (Anthropic release feed; signature verified)"
}

# Identify bundles, not display names (a renamed Codex app can be ChatGPT.app).
ai_update_unmanaged_app() {
    local app="$1" installed="$2" bundle
    ${DRY_RUN:-false} && return 0
    [ -f "$app/Contents/Info.plist" ] || return 0
    bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null) || return 0
    case "$bundle" in
        com.anthropic.claudefordesktop|com.openai.chat|com.openai.codex|com.electron.ollama|com.todesktop.230313mzl4w4u92) : ;;
        *) return 0 ;;
    esac
    ai_brew_owns_installed_app "$app" "$installed" && return 0
    if [ "$bundle" = com.anthropic.claudefordesktop ]; then
        ai_check_claude_desktop "$app"
        return $?
    fi
    report_add WARN "AI Updates: ${app##*/} ($bundle) has no verified unattended updater; update in the app"
    return 1
}

ai_update_unmanaged_apps() {
    local app installed failed=0
    ${DRY_RUN:-false} && return 0
    installed=$(timeout 60 brew list --cask 2>/dev/null) || installed=""
    for app in /Applications/*.app "$HOME"/Applications/*.app; do
        ai_update_unmanaged_app "$app" "$installed" || failed=1
    done
    return "$failed"
}

module_ai_updates() {
    local failed=0 npm_bin seen="|" candidate resolved name
    log INFO "AI Updates: mandatory check of installed AI clients"
    if ! command -v timeout >/dev/null 2>&1; then
        ai_update_error "AI Updates: timeout unavailable; install coreutils to run bounded updates"
        return 1
    fi
    ai_update_brew || failed=1
    for npm_bin in "$(command -v npm 2>/dev/null)" /opt/homebrew/bin/npm /usr/local/bin/npm "$HOME"/.nvm/versions/node/*/bin/npm; do
        [ -x "$npm_bin" ] || continue
        resolved=$(realpath "$npm_bin" 2>/dev/null) || resolved="$npm_bin"
        case "$seen" in *"|$resolved|"*) continue ;; esac
        seen="$seen$resolved|"
        ai_update_npm "$npm_bin" || failed=1
    done
    # Known native install locations. Package-manager copies stay with owner.
    for candidate in "$HOME/.local/bin/claude" "$HOME/.grok/bin/grok" \
        "$HOME/.local/bin/cursor-agent" "$HOME/.opencode/bin/opencode"; do
        [ -x "$candidate" ] || continue
        resolved=$(realpath "$candidate" 2>/dev/null) || resolved="$candidate"
        case "$resolved" in */node_modules/*|*/Cellar/*|*/Caskroom/*) continue ;; esac
        name="${candidate##*/}"
        case "$name" in
            opencode) ai_update_native "$name" "$candidate" upgrade || failed=1 ;;
            *) ai_update_native "$name" "$candidate" update || failed=1 ;;
        esac
    done
    # A documented missing desktop updater is not a repairable CLI failure.
    ai_update_unmanaged_apps || :
    return "$failed"
}
