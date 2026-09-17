#!/usr/bin/env bats
# Unified software inventory / apply (all sources)

setup() {
  # shellcheck source=../lib/core/software_updates.sh
  source "${BATS_TEST_DIRNAME}/../lib/core/software_updates.sh"
  # shellcheck source=../lib/core/profiles.sh
  source "${BATS_TEST_DIRNAME}/../lib/core/profiles.sh"
}

@test "source list covers brew mas macos sparkle and toolchains" {
  run software_source_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew-formula"* ]]
  [[ "$output" == *"brew-cask"* ]]
  [[ "$output" == *"mas"* ]]
  [[ "$output" == *"macos"* ]]
  [[ "$output" == *"sparkle"* ]]
  [[ "$output" == *"npm-g"* ]]
  [[ "$output" == *"pipx"* ]]
  [[ "$output" == *"msupdate"* ]]
}

@test "parse brew outdated lines into TSV" {
  run software_parse_outdated brew-cask apply <<'EOF'
whatsapp (2.0) < 2.1
wget
EOF
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew-cask	whatsapp	2.0	2.1	apply"* ]]
  [[ "$output" == *"brew-cask	wget	?	installed-outdated	apply"* ]]
}

@test "parse mas outdated lines into TSV" {
  run software_parse_mas <<'EOF'
409183694 Keynote (14.0 -> 14.1)
EOF
  [ "$status" -eq 0 ]
  [[ "$output" == *"mas	Keynote	14.0	14.1	apply"* ]]
}

@test "sparkle scan finds newer appcast version" {
  apps=$(mktemp -d)
  mkdir -p "$apps/Fake.app/Contents"
  cat > "$apps/Fake.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>SUFeedURL</key><string>https://example.invalid/appcast.xml</string>
</dict></plist>
PLIST
  software_sparkle_fetch() { printf 'sparkle:shortVersionString="2.0"\n'; }
  SOFTWARE_APPS_DIR="$apps"
  run software_scan_sparkle
  rm -rf "$apps"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sparkle	Fake	1.0	2.0	report"* ]]
}

@test "dry-run apply emits would-apply and does not fail" {
  SOFTWARE_DRY_RUN=true
  run software_apply_row "npm-g" "leftpad" "1" "2" "apply"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would-apply"* ]]
}

@test "report-only rows are not applied" {
  SOFTWARE_DRY_RUN=false
  run software_apply_row "sparkle" "Fake" "1" "2" "report"
  [ "$status" -eq 0 ]
  [[ "$output" == *"report-only"* ]]
}

@test "auto profile includes Dev Updates by default" {
  RUN_PROFILE=auto
  unset UNIVERSAL_UPDATES
  module_in_profile "Dev Updates"
}

@test "auto profile can disable Dev Updates" {
  RUN_PROFILE=auto
  UNIVERSAL_UPDATES=false
  run module_in_profile "Dev Updates"
  [ "$status" -ne 0 ]
}
