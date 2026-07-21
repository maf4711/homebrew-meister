#!/usr/bin/env bash
# tests/test_ollama_backend.sh — unit-tests the Ollama fm_available/fm_query by
# extracting them from meister.sh and stubbing curl. No live Ollama needed.
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$DIR/tests/helpers.sh"

lib="$(mktemp)"
{
    echo 'MEISTER_OLLAMA_URL="http://ollama.test"'
    echo 'MEISTER_OLLAMA_MODEL="testmodel"'
    extract_fn fm_available "$DIR/meister.sh"
    extract_fn fm_query     "$DIR/meister.sh"
} > "$lib"
# shellcheck source=/dev/null
. "$lib"

curl() {
    local args="$*"
    case "$args" in
        *"/api/tags"*)     [ "${CURL_TAGS_OK:-1}" = 1 ] && return 0 || return 22 ;;
        *"/api/generate"*) printf '%s' '{"response":"PONG"}'; return 0 ;;
    esac
    return 1
}

CURL_TAGS_OK=1 assert_ok   fm_available
CURL_TAGS_OK=0 assert_fail fm_available
out="$(fm_query 'ping')"
assert_eq "$out" "PONG" "fm_query returns .response"
echo "test_ollama_backend: PASS"
