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

ai_update_brew() {
    local kind installed token outdated failed=0 sudo_checked=false
    command -v brew >/dev/null 2>&1 || return 0
    if ${DRY_RUN:-false}; then
        log STEP "[DRY-RUN] AI Updates: refresh Homebrew; upgrade installed AI clients (--greedy)"
        return 0
    fi
    # Do not inherit daily metadata TTL or skip auto-updating casks.
    if ! ai_update_attempt brew update; then
        ai_update_error "AI Updates: Homebrew metadata refresh failed"
        return 1
    fi
    for kind in cask formula; do
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
                if ! $sudo_checked && command -v ensure_sudo >/dev/null 2>&1; then
                    ensure_sudo "AI client cask updates" 2>/dev/null || log WARN "AI Updates: no sudo ticket; admin-owned apps may fail"
                    sudo_checked=true
                fi
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

# Native desktop installers do not expose a supported unattended updater.
# Identify bundles, not display names (a renamed Codex app can be ChatGPT.app).
ai_update_unmanaged_apps() {
    local app bundle installed failed=0
    ${DRY_RUN:-false} && return 0
    installed=$(timeout 60 brew list --cask 2>/dev/null) || installed=""
    for app in /Applications/*.app "$HOME"/Applications/*.app; do
        [ -f "$app/Contents/Info.plist" ] || continue
        bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null) || continue
        case "$bundle" in
            com.anthropic.claudefordesktop|com.openai.chat|com.openai.codex|com.electron.ollama|com.todesktop.230313mzl4w4u92) : ;;
            *) continue ;;
        esac
        if ! ai_brew_owns_installed_app "$app" "$installed"; then
            report_add WARN "AI Updates: ${app##*/} ($bundle) has no verified unattended updater; update in the app"
            failed=1
        fi
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
        case "$seen" in *"|$npm_bin|"*) continue ;; esac
        seen="$seen$npm_bin|"
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
