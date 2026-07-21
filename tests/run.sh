#!/usr/bin/env bash
# tests/run.sh — run all twin tests + shellcheck (error severity only)
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR" || exit 1

fail=0
echo "== shellcheck (error) =="
shellcheck -x -S error meister.sh || fail=1
[ -f meisterSiri.sh ] && { shellcheck -x -S error meisterSiri.sh || fail=1; }

for t in tests/test_*.sh; do
    [ -e "$t" ] || continue
    echo "== $t =="
    bash "$t" || fail=1
done

[ "$fail" = 0 ] && echo "ALL GREEN" || { echo "SOME RED"; exit 1; }
