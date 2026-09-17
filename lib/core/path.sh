# shellcheck shell=bash
# LaunchAgents get PATH=/usr/bin:/bin:/usr/sbin:/sbin — brew/mas live in
# /opt/homebrew/bin. Prepend known prefixes once per process.

meister_bootstrap_path() {
    local extra="" d
    for d in /opt/homebrew/bin /opt/homebrew/sbin /usr/local/bin "$HOME/.local/bin"; do
        [ -d "$d" ] || continue
        case ":$PATH:" in
            *":$d:"*) ;;
            *) extra="${extra:+$extra:}$d" ;;
        esac
    done
    [ -n "$extra" ] && PATH="$extra${PATH:+:}$PATH"
    export PATH
}

meister_find_brew() {
    if command -v brew >/dev/null 2>&1; then
        command -v brew
        return 0
    fi
    local cand
    for cand in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$cand" ]; then
            printf '%s\n' "$cand"
            return 0
        fi
    done
    return 1
}
