# shellcheck shell=bash
# lib/core/launchagent_keepcurrent.sh — keep-current agent labels/args + plist XML

keepcurrent_daily_label() { printf '%s\n' "com.meister.keepcurrent.daily"; }
keepcurrent_weekly_label() { printf '%s\n' "com.meister.keepcurrent.weekly"; }
keepcurrent_daily_args() { printf '%s\n' "--auto -q"; }
keepcurrent_weekly_args() { printf '%s\n' "--deep -q"; }

keepcurrent_legacy_labels() {
    printf '%s\n' "com.meister.maintenance"
}

keepcurrent_apple_cli_name() { printf '%s\n' "MeisterAI"; }

keepcurrent_apple_cli_path() {
    local name prefix
    name=$(keepcurrent_apple_cli_name)
    prefix="${HOMEBREW_PREFIX:-/opt/homebrew}"
    if [ -x "${prefix}/bin/${name}" ]; then
        printf '%s\n' "${prefix}/bin/${name}"
        return 0
    fi
    command -v "$name" 2>/dev/null || printf '%s\n' "${prefix}/bin/${name}"
}

# Rewrite leftover meisterSiri ProgramArguments.0 to MeisterAI. $1=plist path.
keepcurrent_rewrite_legacy_cli() {
    local plist="$1" current base apple
    [ -n "$plist" ] && [ -f "$plist" ] || return 0
    current=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$plist" 2>/dev/null || true)
    [ -n "$current" ] || return 0
    base=$(basename "$current")
    case "$base" in
        meisterSiri|MeisterSiri) ;;
        *) return 0 ;;
    esac
    apple=$(keepcurrent_apple_cli_path)
    /usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 ${apple}" "$plist" >/dev/null
}

# $1=label $2=script_path $3=args_line $4=hour $5=minute $6=weekday (empty=daily)
keepcurrent_plist_xml() {
    local label="$1" script_path="$2" args_line="$3" hour="$4" minute="$5" weekday="${6:-}"
    local args_xml="<string>${script_path}</string>" a
    # shellcheck disable=SC2086
    for a in $args_line; do
        args_xml="${args_xml}
        <string>${a}</string>"
    done
    local cal
    if [ -n "$weekday" ]; then
        cal="<key>StartCalendarInterval</key>
    <dict>
      <key>Weekday</key><integer>${weekday}</integer>
      <key>Hour</key><integer>${hour}</integer>
      <key>Minute</key><integer>${minute}</integer>
    </dict>"
    else
        cal="<key>StartCalendarInterval</key>
    <dict>
      <key>Hour</key><integer>${hour}</integer>
      <key>Minute</key><integer>${minute}</integer>
    </dict>"
    fi
    local path_env="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    cat << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        ${args_xml}
    </array>
    ${cal}
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${path_env}</string>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>
    <key>StandardOutPath</key>
    <string>${MEISTER_DIR:-$HOME/.meister}/launchagent.log</string>
    <key>StandardErrorPath</key>
    <string>${MEISTER_DIR:-$HOME/.meister}/launchagent_err.log</string>
    <key>RunAtLoad</key>
    <false/>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
PLISTEOF
}
