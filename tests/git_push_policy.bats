#!/usr/bin/env bats
# bats tests for lib/core/git_push_policy.sh

setup() {
  # shellcheck source=../lib/core/git_push_policy.sh
  source "${BATS_TEST_DIRNAME}/../lib/core/git_push_policy.sh"
  TEST_REPO=$(mktemp -d)
  git -C "$TEST_REPO" init -q
  git -C "$TEST_REPO" config user.email "t@t"
  git -C "$TEST_REPO" config user.name "t"
}

teardown() {
  rm -rf "$TEST_REPO"
}

@test "GIT_AUTO_PUSH=false denies even when AUTOFIX_GIT_PUSH=true" {
  GIT_AUTO_PUSH=false
  AUTOFIX_GIT_PUSH=true
  run git_repo_may_push "$TEST_REPO"
  [ "$status" -eq 1 ]
}

@test "AUTOFIX_GIT_PUSH=false denies even when GIT_AUTO_PUSH=true" {
  GIT_AUTO_PUSH=true
  AUTOFIX_GIT_PUSH=false
  run git_repo_may_push "$TEST_REPO"
  [ "$status" -eq 1 ]
}

@test "meister-nopush marker denies" {
  GIT_AUTO_PUSH=true
  AUTOFIX_GIT_PUSH=true
  touch "$TEST_REPO/.meister-nopush"
  run git_repo_may_push "$TEST_REPO"
  [ "$status" -eq 1 ]
}

@test "git config meister.nopush true denies" {
  GIT_AUTO_PUSH=true
  AUTOFIX_GIT_PUSH=true
  git -C "$TEST_REPO" config meister.nopush true
  run git_repo_may_push "$TEST_REPO"
  [ "$status" -eq 1 ]
}

@test "both switches true and no opt-out allows" {
  GIT_AUTO_PUSH=true
  AUTOFIX_GIT_PUSH=true
  run git_repo_may_push "$TEST_REPO"
  [ "$status" -eq 0 ]
}

@test "git_push_enabled false when GIT_AUTO_PUSH unset" {
  unset GIT_AUTO_PUSH
  unset AUTOFIX_GIT_PUSH
  run git_push_enabled
  [ "$status" -eq 1 ]
}
