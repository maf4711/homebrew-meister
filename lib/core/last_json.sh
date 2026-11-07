# shellcheck shell=bash
# Atomic heald-compatible reports. Preview archives are never repair evidence.

meister_json_string() {
    local text="${1:-}" ch code escaped
    text=${text//\\/\\\\}; text=${text//\"/\\\"}
    for code in {1..31}; do
        printf -v ch '\\%03o' "$code"
        printf -v ch '%b' "$ch"
        printf -v escaped '\\u%04x' "$code"
        text=${text//"$ch"/"$escaped"}
    done
    printf '"%s"' "$text"
}

meister_json_number() {
    [ "${#1}" -le 18 ] || { printf '%s' "${2:-0}"; return; }
    case "${1:-}" in ''|*[!0-9]*) printf '%s' "${2:-0}" ;; *) printf '%s' "$((10#$1))" ;; esac
}

meister_json_array() {
    local item sep=''
    printf '['
    for item in "$@"; do printf '%s' "$sep"; meister_json_string "$item"; sep=','; done
    printf ']'
}

meister_json_modules() {
    local row status name duration sep=''
    printf '['
    for row in "${MODULE_LEDGER[@]}"; do
        IFS='|' read -r status name duration <<< "$row"
        [ "${DRY_RUN:-false}" = true ] && [ "$status" = FIX ] && status=WOULD
        printf '%s{"name":' "$sep"; meister_json_string "$name"
        printf ',"status":'; meister_json_string "$status"
        printf ',"duration_sec":'; meister_json_number "$duration"; printf '}'
        sep=','
    done
    printf ']'
}

# $1=score $2=ok $3=fix $4=warn $5=err $6=heal $7=duration $8=profile $9=version
write_last_json() {
    local score="${1:-}" ok="${2:-0}" fix="${3:-0}" warn="${4:-0}" err="${5:-0}" heal="${6:-0}"
    local dur="${7:-0}" profile="${8:-auto}" version="${9:-unknown}"
    local dir="${MEISTER_DIR:-$HOME/.meister}" ts host twin preferred='' ai_mode=suggest-only
    local dry=false status="${RUN_STATUS:-completed}" verified="${VERIFIED_REPAIR_COUNT:-0}" freed="${FREED_BYTES:-}"
    local archive_tmp last_tmp archive run_id
    ts=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    host=$(scutil --get LocalHostName 2>/dev/null || hostname -s 2>/dev/null || echo unknown)
    [ "${AI_HEAL_EXECUTE:-true}" = true ] && ai_mode=execute
    [ "${DRY_RUN:-false}" = true ] && { dry=true; fix=0; heal=0; verified=0; freed=''; }
    fix=$(meister_json_number "$fix")
    verified=$(meister_json_number "$verified")
    [ "$verified" -le "$fix" ] || verified="$fix"
    case "$status" in completed|partial|interrupted) ;; *) status=partial ;; esac
    case "${AI_BACKEND_KIND:-}" in
        apple) twin=MeisterAI ;; ollama) twin=meister ;;
        *) case "${0##*/}" in MeisterAI*) twin=MeisterAI ;; meister*) twin=meister ;; *) twin=unknown ;; esac ;;
    esac
    [ ! -f "$dir/preferred_twin" ] || preferred=$(tr -d '[:space:]' < "$dir/preferred_twin")
    [ "$preferred" != meisterSiri ] || preferred=MeisterAI
    run_id="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}}"
    # Never allow report identity to choose a path outside runs/.
    case "$run_id" in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac
    mkdir -p "$dir/runs" || return 1
    archive="$dir/runs/$run_id.json"
    archive_tmp=$(mktemp "$dir/runs/.report.XXXXXX") || return 1
    {
        printf '{\n  "schema": "meister.last/v1",\n  "ts": '; meister_json_string "$ts"
        printf ',\n  "run_id": '; meister_json_string "$run_id"
        printf ',\n  "report_kind": '; meister_json_string "${REPORT_KIND:-maintenance}"
        printf ',\n  "planned_modules": '; meister_json_array "${REPORT_PLANNED[@]}"
        printf ',\n  "ai_diagnoses": '; meister_json_array "${REPORT_AI_DIAGNOSES[@]}"
        printf ',\n  "status": '; meister_json_string "$status"
        printf ',\n  "dry_run": %s,\n  "host": ' "$dry"; meister_json_string "$host"
        printf ',\n  "version": '; meister_json_string "$version"
        printf ',\n  "profile": '; meister_json_string "$profile"
        printf ',\n  "score": '; meister_json_number "$score" null
        printf ',\n  "ok": '; meister_json_number "$ok"
        printf ',\n  "fix": '; meister_json_number "$fix"
        printf ',\n  "warn": '; meister_json_number "$warn"
        printf ',\n  "err": '; meister_json_number "$err"
        printf ',\n  "heal": '; meister_json_number "$heal"
        printf ',\n  "duration_sec": '; meister_json_number "$dur"
        printf ',\n  "verified_repair_count": '; meister_json_number "$verified"
        printf ',\n  "freed_bytes": '; meister_json_number "$freed" null
        printf ',\n  "freed_bytes_scope": '; meister_json_string "${FREED_BYTES_SCOPE:-unknown}"
        printf ',\n  "fixes": '; if "$dry"; then printf '[]'; else meister_json_array "${REPORT_FIXED[@]}"; fi
        printf ',\n  "warnings": '; meister_json_array "${REPORT_WARNINGS[@]}"
        printf ',\n  "errors": '; meister_json_array "${REPORT_ERRORS[@]}"
        printf ',\n  "would_fix": '
        if "$dry"; then meister_json_array "${REPORT_WOULD_FIX[@]}" "${REPORT_FIXED[@]}"; else meister_json_array "${REPORT_WOULD_FIX[@]}"; fi
        printf ',\n  "modules": '; meister_json_modules
        printf ',\n  "ai_heal_mode": '; meister_json_string "$ai_mode"
        printf ',\n  "twin": '; meister_json_string "$twin"
        printf ',\n  "ai_backend": '; meister_json_string "${AI_BACKEND_KIND:-unknown}"
        printf ',\n  "preferred_twin": '; meister_json_string "$preferred"
        printf ',\n  "product": "meister",\n  "role": "batch-maintain",\n  "heald_contract": "observe-continuous; meister=batch-maintain"\n}\n'
    } > "$archive_tmp" || { rm -f "$archive_tmp"; return 1; }
    mv "$archive_tmp" "$archive" || { rm -f "$archive_tmp"; return 1; }
    last_tmp=$(mktemp "$dir/.last.XXXXXX") || return 1
    if ! cp "$archive" "$last_tmp" || ! mv "$last_tmp" "$dir/last.json"; then
        rm -f "$last_tmp"; return 1
    fi
}

meister_notify() {
    local title="${1:-Meister}" body="${2:-Done}"
    [ "${MEISTER_NOTIFY:-true}" = true ] || return 0
    osascript -e "display notification \"${body//\"/\\\"}\" with title \"${title//\"/\\\"}\"" 2>/dev/null || true
}
