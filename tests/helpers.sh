# tests/helpers.sh — minimal assert + extraction helpers (no bats dependency)
# shellcheck shell=bash

# extract_fn NAME FILE — prints the shell function NAME's definition from FILE.
extract_fn() {
    awk -v fn="$1" '
        $0 ~ "^"fn"\\(\\) \\{" { inside=1 }
        inside { print }
        inside && /^\}/ { exit }
    ' "$2"
}

assert_eq()    { [ "$1" = "$2" ] || { echo "FAIL: '$1' != '$2'  ($3)"; exit 1; }; echo "ok: $3"; }
assert_ok()    { if "$@"; then echo "ok: $* → success"; else echo "FAIL: expected success: $*"; exit 1; fi; }
assert_fail()  { if "$@"; then echo "FAIL: expected failure: $*"; exit 1; else echo "ok: $* → failure"; fi; }
