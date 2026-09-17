#!/usr/bin/env bats
# Simulator modules must not call `simctl list` (mounts all runtime DMGs).

src_fn() {
  local name="$1"
  awk -v name="$name" '$0==name"() {" {on=1} on {print} on && /^}$/ {exit}' \
    "$BATS_TEST_DIRNAME/../MeisterAI.sh"
}

@test "module_simfix never invokes simctl list" {
  body=$(src_fn module_simfix)
  [ -n "$body" ]
  run grep -E 'simctl[[:space:]]+list' <<<"$body"
  [ "$status" -ne 0 ]
}

@test "module_ios_sim never invokes simctl list" {
  body=$(src_fn module_ios_sim)
  [ -n "$body" ]
  run grep -E 'simctl[[:space:]]+list' <<<"$body"
  [ "$status" -ne 0 ]
}

@test "explicit simfix command does not launch Simulator.app" {
  body=$(src_fn module_simfix)
  run grep -E 'open[[:space:]]+-a[[:space:]]+Simulator' <<<"$body"
  [ "$status" -ne 0 ]
}
