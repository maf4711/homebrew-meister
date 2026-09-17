# shellcheck shell=bash
# Structured model output is data. Only the contract maps action IDs to argv.
fm_diagnose() {
    local module="$1" failure="$2" previous="${3:-}" purpose="${4:-ai-heal}"
    local contract="${MEISTER_LIB_DIR}/fm/contract.py" work rc=0 permission_fact=unknown mode=readonly
    [ "$purpose" != ai-heal ] || mode=heal-candidate
    [ "${SUDO_AUTHED:-false}" != true ] || permission_fact=authenticated_this_session
    [ "${SUDO_AUTH_FAILED:-false}" != true ] || permission_fact=authentication_failed_this_session
    FM_DIAGNOSIS_COMMAND=NO_FIX
    FM_DIAGNOSIS_FILE=''
    command -v python3 >/dev/null 2>&1 && [ -f "$contract" ] || {
        ai_usage_record "$purpose" "$mode" unavailable "diagnosis contract/python3 missing"
        return 1
    }
    mkdir -p "$MEISTER_DIR/diagnoses" || return 1
    work=$(mktemp -d "$MEISTER_DIR/diagnoses/fm.XXXXXX") || return 1
    chmod 700 "$work"
    python3 "$contract" context --module "$module" --error "$failure" --previous "$previous" \
        --state-dir "$MEISTER_DIR" \
        --permissions "sudo_session=$permission_fact; tty=$([ -t 0 ] && echo yes || echo no)" \
        > "$work/context.json" || return 1
    fm_query "$(cat "$work/context.json")" "$purpose" > "$work/response.json" || rc=$?
    if [ "$rc" -ne 0 ]; then
        printf 'KI-Diagnose nicht verfügbar (Exit %s); keine Reparatur vorgeschlagen.\n' "$rc" >&2
        return "$rc"
    fi
    if ! python3 "$contract" validate --context "$work/context.json" < "$work/response.json" > "$work/diagnosis.json" 2> "$work/validation.txt"; then
        ai_usage_record "$purpose" "$mode" invalid-response "contract validation failed"
        printf 'KI-Antwort enthält keine gültige, belegte Diagnose; keine Ausführung.\n' >&2
        return 2
    fi
    FM_DIAGNOSIS_COMMAND=$(python3 "$contract" command --context "$work/context.json" < "$work/diagnosis.json") || return 2
    # shellcheck disable=SC2034 # consumed by callers and UI integration
    FM_DIAGNOSIS_FILE="$work/diagnosis.json"
    # shellcheck disable=SC2034 # serialized into the run report
    REPORT_AI_DIAGNOSES+=("$FM_DIAGNOSIS_FILE")
    python3 "$contract" render --context "$work/context.json" < "$work/diagnosis.json" >&2
    ai_usage_record "$purpose" "$mode" diagnosis-valid "action_command=$FM_DIAGNOSIS_COMMAND report=$work/diagnosis.json"
}

fm_report_summary() {
    local file="${1:-$MEISTER_DIR/last.json}"
    command -v python3 >/dev/null 2>&1 || return 1
    python3 "$MEISTER_LIB_DIR/fm/contract.py" summary "$file"
}
