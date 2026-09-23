#!/usr/bin/env bats
# Homebrew prefix shared by every admin user — pure checks only.

setup() {
  # shellcheck source=../lib/core/homebrew_share.sh
  source "${BATS_TEST_DIRNAME}/../lib/core/homebrew_share.sh"
}

@test "lists safe.directory entries that are missing" {
  run homebrew_share_missing_entries /opt/homebrew $'/opt/homebrew\n'
  [ "$status" -eq 1 ]
  [ "$output" = "/opt/homebrew/*" ]
}

@test "complete safe.directory list is quiet" {
  run homebrew_share_missing_entries /opt/homebrew $'/opt/homebrew\n/opt/homebrew/*'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "empty safe.directory list needs both entries" {
  run homebrew_share_missing_entries /opt/homebrew ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"/opt/homebrew"* ]]
  [[ "$output" == *"/opt/homebrew/*"* ]]
}

@test "shared mode is group-write and setgid" {
  homebrew_share_mode_ok drwxrwsr-x
  run homebrew_share_mode_ok drwxrwxr-x
  [ "$status" -ne 0 ]
  run homebrew_share_mode_ok drwxr-xr-x
  [ "$status" -ne 0 ]
}

@test "acl text must inherit onto new files and directories" {
  homebrew_share_acl_text_ok "0: group:admin inherited allow list,add_file,search,delete,add_subdirectory,delete_child,file_inherit,directory_inherit"
  run homebrew_share_acl_text_ok "group:admin allow read,write"
  [ "$status" -ne 0 ]
}

@test "acl ace keeps file and directory inherit" {
  run homebrew_share_acl_ace
  [[ "$output" == *"file_inherit"* ]]
  [[ "$output" == *"directory_inherit"* ]]
  [[ "$output" == group:admin\ allow* ]]
}

@test "MeisterAI documents homebrew-share" {
  grep -q 'MeisterAI homebrew-share' "${BATS_TEST_DIRNAME}/../MeisterAI.sh"
}
