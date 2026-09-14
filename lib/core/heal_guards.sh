# shellcheck shell=bash
# lib/core/heal_guards.sh — pure AI-Heal allowlist (no side effects)
# Sourced by meisterSiri / meister. Safe to unit-test with bats.

# Allowlisted verbs for AI-Heal / Learned-Fix execution
: "${FM_HEAL_ALLOW:= killall pkill qlmanage mdutil mdimport dscacheutil atsutil defaults launchctl lsregister tccutil purge fc-cache dot_clean }"

# Return 0 if $1 is a single simple allowlisted command (no shell metacharacters).
heal_command_allowed() {
    local cmd="$1"
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"; cmd="${cmd%"${cmd##*[![:space:]]}"}"
    [ -z "$cmd" ] && return 1
    case "$cmd" in
        *sudo*|*';'*|*'&'*|*'|'*|*'>'*|*'<'*|*'$'*|*'`'*|*'\'*) return 1 ;;
        'rm '*|*' rm '*|*chmod*|*chown*|'dd '*|*' dd '*|*mkfs*|*'-rf'*) return 1 ;;
    esac
    local verb="${cmd%%[[:space:]]*}"; verb="${verb##*/}"
    case "$FM_HEAL_ALLOW" in *" $verb "*) return 0 ;; *) return 1 ;; esac
}

# True if response looks like a model placeholder (INSIGHTS 2026-07-04 #1)
heal_is_placeholder() {
    local s="$1"
    echo "$s" | grep -qiE '/path/to|<[a-zA-Z0-9_.-]+>|\$\{?[A-Z_]+\b|your_|/example|example\.(com|txt)|placeholder|TODO|FIXME|changeme|xxx|dummy'
}

# Normalize a model reply to a single command or NO_FIX.
# Accepts macOS 27 @Generable JSON ({"noFix":bool,"command":...}) and legacy
# free-text (fenced markdown / first lines). Always prints one line; exit 0.
heal_parse_suggestion() {
    local raw="${1-}"
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$raw" | python3 -c '
import json, sys
s = sys.stdin.read()
start, end = s.find("{"), s.rfind("}")
if start != -1 and end > start:
    try:
        o = json.loads(s[start:end + 1])
        if isinstance(o, dict) and ("noFix" in o or "command" in o):
            cmd = str(o.get("command") or "").strip()
            if o.get("noFix") is True or not cmd:
                print("NO_FIX")
            else:
                print(cmd)
            raise SystemExit(0)
    except json.JSONDecodeError:
        pass
lines = []
for line in s.splitlines():
    t = line.strip().strip("`")
    if not t or t.startswith("```"):
        continue
    if t in ("json", "bash", "sh", "zsh", "shell"):
        continue
    lines.append(t)
text = "\n".join(lines[:3]).strip()
print(text if text else "NO_FIX")
'
        return 0
    fi
    local t
    t=$(printf '%s\n' "$raw" | sed -e '/^```/d' -e 's/^`//; s/`$//' | head -3)
    t="${t#"${t%%[![:space:]]*}"}"; t="${t%"${t##*[![:space:]]}"}"
    [ -n "$t" ] && printf '%s\n' "$t" || printf '%s\n' "NO_FIX"
}

# First absolute path token in $1 that does not exist (empty = ok).
# Another form of placeholder: model invents /Users/foo/bar that isn't real.
heal_missing_path() {
    local s="$1" tok
    # shellcheck disable=SC2086
    for tok in $s; do
        case "$tok" in
            -*|*[=:,]*|'') continue ;;
            ~/*) tok="${tok/#\~/$HOME}" ;;
            /*) ;;
            *) continue ;;
        esac
        tok="${tok%%[;,)]*}"
        if [ ! -e "$tok" ]; then
            printf '%s' "$tok"
            return 0
        fi
    done
    return 1
}
