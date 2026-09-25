#!/usr/bin/env bash
# Offline CLI quality gate. Missing tools are failures, never a green skip.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

for tool in shellcheck bats python3 node; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: $tool is required. Install shellcheck, bats-core and python3 before running checks." >&2
    exit 1
  fi
done

echo "=== shellcheck ==="
shellcheck -x -S warning lib/core/*.sh lib/commands/*.sh scripts/check.sh scripts/check-app.sh scripts/sync-twins.sh

echo "=== bash -n twins ==="
bash -n MeisterAI.sh
bash -n meister.sh
echo "OK bash -n"

echo "=== twin parity (read-only) ==="
bash scripts/sync-twins.sh --check

echo "=== bats ==="
bats tests/

echo "=== local Mail CLI tests ==="
node --test tests/*mail*.test.mjs

echo "=== FM evaluation harness ==="
python3 -m unittest discover -s tests -p 'test_fm*.py'
fm_result=$(mktemp "${TMPDIR:-/tmp}/meister-fm-evaluation.XXXXXX")
trap 'rm -f "$fm_result"' EXIT
python3 scripts/evaluate-fm.py --output "$fm_result"
python3 scripts/evaluate-fm.py --fixtures tests/fixtures/ollama_holdout.json --output "$fm_result"
echo "=== ALL CHECKS PASSED ==="
