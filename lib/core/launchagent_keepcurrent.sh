# shellcheck shell=bash
# lib/core/launchagent_keepcurrent.sh — keep-current agent labels/args + plist XML

keepcurrent_daily_label() { printf '%s\n' "com.meister.keepcurrent.daily"; }
keepcurrent_weekly_label() { printf '%s\n' "com.meister.keepcurrent.weekly"; }
keepcurrent_daily_args() { printf '%s\n' "--auto -q"; }
keepcurrent_weekly_args() { printf '%s\n' "--deep -q"; }

keepcurrent_legacy_labels() {
    printf '%s\n' "com.meister.maintenance"
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
