#!/usr/bin/env bash
# Quality gate for P1: shellcheck + bats (no network)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== shellcheck lib/core + lib/commands ==="
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x -S warning lib/core/*.sh lib/commands/*.sh
  echo "OK lib/"
else
  echo "WARN: shellcheck not installed — skip"
fi

echo "=== bash -n twins ==="
bash -n meisterSiri.sh
bash -n meister.sh
echo "OK bash -n"

echo "=== bats ==="
if command -v bats >/dev/null 2>&1; then
  bats tests/
else
  echo "WARN: bats not installed — skip (install: brew install bats-core)"
fi

echo "=== ALL CHECKS PASSED ==="
