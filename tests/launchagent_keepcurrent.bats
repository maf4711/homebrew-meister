#!/usr/bin/env bats
# bats tests for lib/core/launchagent_keepcurrent.sh

setup() {
  # shellcheck source=../lib/core/launchagent_keepcurrent.sh
  source "${BATS_TEST_DIRNAME}/../lib/core/launchagent_keepcurrent.sh"
}

@test "daily args are --auto -q" {
  [ "$(keepcurrent_daily_args)" = "--auto -q" ]
}

@test "weekly args are --deep -q" {
  [ "$(keepcurrent_weekly_args)" = "--deep -q" ]
}

@test "legacy labels include com.meister.maintenance" {
  keepcurrent_legacy_labels | grep -qx "com.meister.maintenance"
}

@test "daily label is keepcurrent.daily" {
  [ "$(keepcurrent_daily_label)" = "com.meister.keepcurrent.daily" ]
}

@test "weekly label is keepcurrent.weekly" {
  [ "$(keepcurrent_weekly_label)" = "com.meister.keepcurrent.weekly" ]
}

@test "plist xml contains ProgramArguments for --auto" {
  xml=$(keepcurrent_plist_xml "com.meister.keepcurrent.daily" "/opt/homebrew/bin/meisterSiri" "$(keepcurrent_daily_args)" 9 15 "")
  echo "$xml" | grep -q "<string>/opt/homebrew/bin/meisterSiri</string>"
  echo "$xml" | grep -q "<string>--auto</string>"
  echo "$xml" | grep -q "<string>-q</string>"
  echo "$xml" | grep -q "<string>com.meister.keepcurrent.daily</string>"
}
