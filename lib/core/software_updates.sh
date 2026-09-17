# shellcheck shell=bash
# lib/core/software_updates.sh — inventory + apply across every present source
#
# Scan TSV: source<TAB>item<TAB>current<TAB>available<TAB>action
# action: apply | report
# SOFTWARE_APPS_DIR defaults to /Applications (overridable in tests).
# SOFTWARE_DRY_RUN=true logs would-apply without running updaters.

software_source_list() {
    printf '%s\n' \
        brew-formula brew-cask mas macos \
        npm-g pnpm-g bun pipx rustup cargo uv gem \
        mise macports \
        vscode cursor msupdate sparkle \
        tldr omz gcloud
}

software_source_group() {
    case "$1" in
        brew-formula|brew-cask|mas|macos) printf '%s\n' platform ;;
        sparkle) printf '%s\n' apps-report ;;
        vscode|cursor|msupdate) printf '%s\n' apps ;;
        *) printf '%s\n' toolchain ;;
    esac
}

software_source_present() {
    case "$1" in
        brew-formula|brew-cask) command -v brew >/dev/null 2>&1 ;;
        mas) command -v mas >/dev/null 2>&1 ;;
        macos) command -v softwareupdate >/dev/null 2>&1 ;;
        npm-g) command -v npm >/dev/null 2>&1 ;;
        pnpm-g) command -v pnpm >/dev/null 2>&1 ;;
        bun) command -v bun >/dev/null 2>&1 ;;
        pipx) command -v pipx >/dev/null 2>&1 ;;
        rustup) command -v rustup >/dev/null 2>&1 ;;
        cargo) command -v cargo >/dev/null 2>&1 ;;
        uv) command -v uv >/dev/null 2>&1 ;;
        gem) command -v gem >/dev/null 2>&1 ;;
        mise) command -v mise >/dev/null 2>&1 ;;
        macports) command -v port >/dev/null 2>&1 ;;
        vscode) command -v code >/dev/null 2>&1 ;;
        cursor) command -v cursor >/dev/null 2>&1 ;;
        msupdate)
            [ -x "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate" ] \
                || command -v msupdate >/dev/null 2>&1
            ;;
        sparkle) return 0 ;;
        tldr) command -v tldr >/dev/null 2>&1 ;;
        omz) [ -d "${HOME}/.oh-my-zsh/.git" ] ;;
        gcloud) command -v gcloud >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

software_emit() {
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"
}

# stdin: brew outdated lines ("name" or "name (cur) < new")
software_parse_outdated() {
    local source="$1" action="${2:-apply}" line name cur avail
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        case "$line" in *'(latest)'*) continue ;; esac
        name="${line%% *}"
        cur="?"
        avail="installed-outdated"
        if [[ "$line" == *"("*")"* ]]; then
            cur="${line#*(}"
            cur="${cur%%)*}"
            if [[ "$line" == *" < "* ]]; then
                avail="${line##* < }"
                avail="${avail%% *}"
            fi
        fi
        software_emit "$source" "$name" "$cur" "$avail" "$action"
    done
}

# stdin: mas outdated ("id Name (cur -> new)")
software_parse_mas() {
    local line rest name ver cur avail
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        rest="${line#* }"
        if [[ "$rest" == *"("* ]]; then
            name="${rest% (*}"
            ver="${rest##*(}"
            ver="${ver%)}"
            cur="${ver%% -> *}"
            avail="${ver##* -> }"
        else
            name="$rest"
            cur="?"
            avail="outdated"
        fi
        software_emit "mas" "$name" "$cur" "$avail" "apply"
    done
}

software_sparkle_fetch() {
    curl -sfL --max-time 8 "$1" 2>/dev/null
}

software_scan_sparkle() {
    local root="${SOFTWARE_APPS_DIR:-/Applications}"
    local app plist feed cur latest
    for app in "$root"/*.app; do
        [ -d "$app" ] || continue
        plist="$app/Contents/Info.plist"
        [ -f "$plist" ] || continue
        feed=$(defaults read "$plist" SUFeedURL 2>/dev/null) || continue
        [ -z "$feed" ] && continue
        cur=$(defaults read "$plist" CFBundleShortVersionString 2>/dev/null) || continue
        [ -z "$cur" ] && continue
        latest=$(software_sparkle_fetch "$feed" | grep -oE 'sparkle:shortVersionString="[^"]+"' | head -1 | cut -d'"' -f2)
        [ -z "$latest" ] && continue
        [ "$cur" = "$latest" ] && continue
        software_emit "sparkle" "$(basename "$app" .app)" "$cur" "$latest" "report"
    done
}

software_timeout() {
    local sec="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$sec" "$@"
    else
        "$@"
    fi
}

software_scan_source() {
    local id="$1"
    software_source_present "$id" || return 0
    case "$id" in
        brew-formula)
            software_parse_outdated brew-formula apply < <(brew outdated --formula --verbose 2>/dev/null)
            ;;
        brew-cask)
            software_parse_outdated brew-cask apply < <(brew outdated --cask --greedy --verbose 2>/dev/null)
            ;;
        mas)
            software_parse_mas < <(mas outdated 2>/dev/null)
            ;;
        macos)
            if softwareupdate -l 2>&1 | grep -q "Label:"; then
                software_emit macos macOS "?" "recommended" report
            fi
            ;;
        npm-g)
            local n
            n=$(software_timeout 60 npm outdated -g --parseable 2>/dev/null | grep -c . || true)
            [ "${n:-0}" -gt 0 ] && software_emit npm-g globals installed "${n}-outdated" apply
            ;;
        pnpm-g)
            software_emit pnpm-g globals installed check-on-apply apply
            ;;
        bun)
            software_emit bun runtime installed check-on-apply apply
            ;;
        pipx)
            software_emit pipx tools installed check-on-apply apply
            ;;
        rustup)
            software_emit rustup toolchain installed check-on-apply apply
            ;;
        cargo)
            command -v cargo-install-update >/dev/null 2>&1 \
                && software_emit cargo binaries installed check-on-apply apply
            ;;
        uv)
            brew list uv >/dev/null 2>&1 || software_emit uv self installed check-on-apply apply
            ;;
        gem)
            if gem outdated 2>/dev/null | grep -q .; then
                software_emit gem user-gems installed outdated apply
            fi
            ;;
        mise)
            software_emit mise tools installed check-on-apply apply
            ;;
        macports)
            if port outdated 2>/dev/null | grep -q .; then
                software_emit macports ports installed outdated apply
            fi
            ;;
        vscode)
            software_emit vscode extensions installed update-on-apply apply
            ;;
        cursor)
            software_emit cursor extensions installed update-on-apply apply
            ;;
        msupdate)
            software_emit msupdate office installed check-on-apply apply
            ;;
        sparkle)
            software_scan_sparkle
            ;;
        tldr)
            software_emit tldr pages installed refresh apply
            ;;
        omz)
            software_emit omz ~/.oh-my-zsh installed check-on-apply apply
            ;;
        gcloud)
            [ "${UPDATE_GCLOUD:-true}" = "true" ] && software_emit gcloud components installed check-on-apply apply
            ;;
    esac
}

software_scan_all() {
    local id
    while IFS= read -r id; do
        [ -z "$id" ] && continue
        software_scan_source "$id"
    done < <(software_source_list)
}

software_msupdate_bin() {
    if command -v msupdate >/dev/null 2>&1; then
        command -v msupdate
        return
    fi
    local p="/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"
    [ -x "$p" ] && printf '%s\n' "$p"
}

software_apply_row() {
    local source="$1" item="$2" current="$3" available="$4" action="$5"
    if [ "$action" != "apply" ]; then
        printf 'report-only %s %s (%s → %s)\n' "$source" "$item" "$current" "$available"
        return 0
    fi
    if [ "${SOFTWARE_DRY_RUN:-false}" = "true" ]; then
        printf 'would-apply %s %s (%s → %s)\n' "$source" "$item" "$current" "$available"
        return 0
    fi
    case "$source" in
        brew-formula) software_timeout 180 brew upgrade --formula "$item" ;;
        brew-cask) software_timeout 180 brew upgrade --cask "$item" ;;
        mas) software_timeout 300 mas upgrade ;;
        npm-g) software_timeout 300 npm update -g ;;
        pnpm-g) software_timeout 300 pnpm update -g ;;
        bun) software_timeout 120 bun upgrade ;;
        pipx) software_timeout 300 pipx upgrade-all ;;
        rustup) software_timeout 300 rustup update ;;
        cargo) software_timeout 600 cargo install-update -a ;;
        uv) software_timeout 120 uv self update ;;
        gem) software_timeout 300 gem update ;;
        mise) software_timeout 300 mise upgrade --yes ;;
        macports) software_timeout 600 port upgrade outdated ;;
        vscode) software_timeout 180 code --update-extensions ;;
        cursor) software_timeout 180 cursor --update-extensions ;;
        msupdate)
            local bin
            bin=$(software_msupdate_bin)
            [ -n "$bin" ] && software_timeout 300 "$bin" --install
            ;;
        tldr) software_timeout 60 tldr --update ;;
        omz) software_timeout 60 git -C "${HOME}/.oh-my-zsh" pull --ff-only --quiet ;;
        gcloud) software_timeout 600 gcloud components update --quiet ;;
        *) return 1 ;;
    esac
}

# SOFTWARE_APPLY_GROUPS=platform,toolchain,apps (comma-separated). Default: all.
software_apply_all() {
    local groups="${SOFTWARE_APPLY_GROUPS:-platform,toolchain,apps}"
    local source item current available action grp seen=" "
    while IFS=$'\t' read -r source item current available action; do
        [ -z "$source" ] && continue
        grp=$(software_source_group "$source")
        case ",$groups," in
            *",$grp,"*) ;;
            *) continue ;;
        esac
        case "$source" in
            mas|npm-g|pnpm-g|bun|pipx|rustup|cargo|uv|gem|mise|macports|vscode|cursor|msupdate|tldr|omz|gcloud)
                case "$seen" in *" $source "*) continue ;; esac
                seen="$seen$source "
                ;;
        esac
        software_apply_row "$source" "$item" "$current" "$available" "$action" || true
    done < <(software_scan_all)
}

software_print_inventory() {
    local source item current available action n=0 present=""
    while IFS= read -r source; do
        software_source_present "$source" || continue
        present="${present}${source} "
    done < <(software_source_list)
    printf 'Present sources: %s\n' "$present"
    printf '%-14s %-28s %-16s %-16s %s\n' "SOURCE" "ITEM" "CURRENT" "AVAILABLE" "ACTION"
    while IFS=$'\t' read -r source item current available action; do
        [ -z "$source" ] && continue
        printf '%-14s %-28s %-16s %-16s %s\n' "$source" "$item" "$current" "$available" "$action"
        n=$((n + 1))
    done < <(software_scan_all)
    printf '%s outdated item(s)\n' "$n"
}

cmd_software_updates() {
    local apply=false json=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --apply|-a) apply=true ;;
            --json) json=true ;;
            --dry-run) SOFTWARE_DRY_RUN=true ;;
            --scan|"") ;;
            *) echo "Usage: updates [--scan] [--apply] [--dry-run] [--json]" >&2; return 2 ;;
        esac
        shift
    done
    if $json; then
        software_scan_all | python3 -c '
import json,sys
rows=[]
for line in sys.stdin:
    line=line.rstrip("\n")
    if not line: continue
    p=line.split("\t")
    if len(p)<5: continue
    rows.append({"source":p[0],"item":p[1],"current":p[2],"available":p[3],"action":p[4]})
print(json.dumps({"outdated":rows,"count":len(rows)}, indent=2))
'
        $apply || return 0
    else
        software_print_inventory
    fi
    if $apply; then
        echo ""
        echo "Applying auto-updatable sources (Sparkle/macOS stay report-only)..."
        SOFTWARE_APPLY_GROUPS="${SOFTWARE_APPLY_GROUPS:-platform,toolchain,apps}"
        software_apply_all
    fi
}
