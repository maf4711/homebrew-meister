#!/usr/bin/env bats
# Profile contract tests — quick/auto/deep membership

setup() {
  # shellcheck source=../lib/core/profiles.sh
  source "${BATS_TEST_DIRNAME}/../lib/core/profiles.sh"
  ICLOUD_FIX_ENABLED=false
  UNIVERSAL_UPDATES=false
  DOCS_ORDER_ENABLED=true
  CLEAN_DOCKER=false
  CLEAN_DEV_CACHES=true
  RUN_GIT_REPOS=false
  RUN_SNIFFNET=false
  RUN_PERF_TUNE=false
}

@test "quick includes Healer and Homebrew" {
  RUN_PROFILE=quick
  module_in_profile "Healer"
  module_in_profile "Homebrew"
  module_in_profile "Cleanup"
}

@test "quick excludes Deep Clean and iCloud Fix" {
  RUN_PROFILE=quick
  run module_in_profile "Deep Clean"
  [ "$status" -ne 0 ]
  run module_in_profile "iCloud Fix"
  [ "$status" -ne 0 ]
  run module_in_profile "Benchmark"
  [ "$status" -ne 0 ]
}

@test "deep includes everything we check" {
  RUN_PROFILE=deep
  module_in_profile "Healer"
  module_in_profile "iCloud Fix"
  module_in_profile "Benchmark"
  module_in_profile "Deep Clean"
}

@test "auto excludes iCloud when gate false" {
  RUN_PROFILE=auto
  ICLOUD_FIX_ENABLED=false
  run module_in_profile "iCloud Fix"
  [ "$status" -ne 0 ]
}

@test "auto includes iCloud when gate true" {
  RUN_PROFILE=auto
  ICLOUD_FIX_ENABLED=true
  module_in_profile "iCloud Fix"
}

@test "auto excludes Benchmark and .DS_Store" {
  RUN_PROFILE=auto
  run module_in_profile "Benchmark"
  [ "$status" -ne 0 ]
  run module_in_profile ".DS_Store"
  [ "$status" -ne 0 ]
}

@test "profile_list_modules quick shape" {
  run profile_list_modules quick Healer Homebrew "Deep Clean" "iCloud Fix"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Healer"* ]]
  [[ "$output" == *"Homebrew"* ]]
  [[ "$output" != *"Deep Clean"* ]]
  [[ "$output" != *"iCloud Fix"* ]]
}
