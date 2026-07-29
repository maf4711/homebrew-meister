# shellcheck shell=bash
# lib/core/last_json.sh — heald handshake + machine-readable last run
# Writes ~/.meister/last.json after a maintenance run.

# $1=score $2=ok $3=fix $4=warn $5=err $6=heal $7=duration_secs $8=profile $9=version
write_last_json() {
    local score="${1:-}"
    local ok="${2:-0}" fix="${3:-0}" warn="${4:-0}" err="${5:-0}" heal="${6:-0}"
    local dur="${7:-0}" profile="${8:-auto}" version="${9:-unknown}"
    local out="${MEISTER_DIR:-$HOME/.meister}/last.json"
    local ts host
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    host=$(scutil --get LocalHostName 2>/dev/null || hostname -s 2>/dev/null || echo unknown)
    local ai_mode="suggest-only"
    [ "${AI_HEAL_EXECUTE:-false}" = "true" ] && ai_mode="execute"
    # Minimal JSON without jq dependency
    cat > "$out" <<EOF
{
  "schema": "meister.last/v1",
  "ts": "$ts",
  "host": "$host",
  "version": "$version",
  "profile": "$profile",
  "score": ${score:-null},
  "ok": $ok,
  "fix": $fix,
  "warn": $warn,
  "err": $err,
  "heal": $heal,
  "duration_sec": $dur,
  "ai_heal_mode": "$ai_mode",
  "product": "meister",
  "role": "batch-maintain",
  "heald_contract": "observe-continuous; meister=batch-maintain"
}
EOF
}

# Optional macOS notification after scheduled / completed run
# $1=title $2=body
meister_notify() {
    local title="${1:-Meister}" body="${2:-Done}"
    [ "${MEISTER_NOTIFY:-true}" = "true" ] || return 0
    # Skip if no GUI session
    [ -n "${TERM_PROGRAM:-}" ] || [ -n "${SSH_CONNECTION:-}" ] || true
    osascript -e "display notification \"${body//\"/\\\"}\" with title \"${title//\"/\\\"}\"" 2>/dev/null || true
}
