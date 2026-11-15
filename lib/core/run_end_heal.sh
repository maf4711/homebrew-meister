# shellcheck shell=bash
# Run-end heal pass. After the modules have finished, review the report
# findings (REPORT_WARNINGS + REPORT_ERRORS) and the WARN/ERROR log lines of the
# current run, give every finding with a registered repairer exactly one
# attempt, and retract a finding only when its repairer verifies the repair.
#
# Deliberately NOT used here: known_fix (its patterns match ordinary warning
# text and can delete caches), ai_heal (Finder/Dock restarts only),
# heal_verify_module (exit 0 counts as verified) and module re-runs (repeat
# side effects). MODULE_LEDGER is never touched.
#
# State: $MEISTER_DIR/run_end_heal.tsv — "<key>\t<consecutive unresolved runs>\t<epoch>"
# for findings whose repair stayed unresolved; 2 consecutive unresolved runs
# suspend the repairer for 7 days.

RUN_END_HEAL_SUSPEND_RUNS=2
RUN_END_HEAL_SUSPEND_SEC=604800

# $1 report entry. stdout: the repair command line, empty when none is registered.
# Only registered repairer: a failed cask upgrade whose evidence capture shows a
# stale-artifact conflict for that cask → brew_cask_repair <cask> <path> true.
run_end_heal_repairer() {
    local finding="$1" re='^Homebrew: ([^ ]+) upgrade failed.*; log: (.+)$' cask path
    [[ "$finding" =~ $re ]] || return 0
    cask=${BASH_REMATCH[1]##*/}   # tap casks: Homebrew names the short token
    path=${BASH_REMATCH[2]}
    case "${path##*/}" in cask-*) ;; *) return 0 ;; esac
    [ -f "$path" ] && [ -r "$path" ] || return 0
    command -v brew_cask_repair >/dev/null 2>&1 || return 0
    command -v brew_cask_conflict_names >/dev/null 2>&1 || return 0
    ! grep -q 'Error: SIGTERM' "$path" 2>/dev/null || return 0
    brew_cask_conflict_names < "$path" | grep -Fxq -- "$cask" || return 0
    printf 'brew_cask_repair %q %q true\n' "$cask" "$path"
}

# Suspension key: the entry without its log path, every digit run → N.
_run_end_heal_key() {
    local key="${1%%; log: *}"
    key=${key//$'\t'/ }
    printf '%s\n' "$key" | sed -E 's/[0-9]+/N/g'
}

# $1 state file, $2 key. stdout: "<count> <epoch>" (base-10 integers) or nothing.
# A damaged row never aborts the pass; a future timestamp counts as 0.
_run_end_heal_state_get() {
    local k n ts
    [ -r "$1" ] || return 0
    while IFS=$'\t' read -r k n ts; do
        [ "$k" = "$2" ] || continue
        case "$n" in ''|*[!0-9]*) n=0 ;; esac
        case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
        [ "${#n}" -le 9 ] || n=0
        [ "${#ts}" -le 18 ] || ts=0
        n=$((10#$n)); ts=$((10#$ts))
        [ "$ts" -le "$(date +%s)" ] || ts=0
        printf '%s %s\n' "$n" "$ts"
        return 0
    done < "$1"
}

# WARN/ERROR lines from the last "… started (" line of the log onward.
_run_end_heal_log_lines() {
    awk '
        / - INFO - [Mm]eister(AI|Siri)? v[^ ]+ started / {n = 0; next}
        /^[0-9-]+ [0-9:]+ - (WARN|ERROR) - / {n++}
        END {print n + 0}
    ' "$1" 2>/dev/null || echo 0
}

# $1 newline-separated entries to drop from REPORT_WARNINGS and REPORT_ERRORS.
_run_end_heal_retract() {
    local drop=$'\n'"$1"$'\n' entry
    local -a keep=()
    for entry in ${REPORT_WARNINGS[@]+"${REPORT_WARNINGS[@]}"}; do
        case "$drop" in *$'\n'"$entry"$'\n'*) ;; *) keep+=("$entry") ;; esac
    done
    REPORT_WARNINGS=(${keep[@]+"${keep[@]}"})
    keep=()
    for entry in ${REPORT_ERRORS[@]+"${REPORT_ERRORS[@]}"}; do
        case "$drop" in *$'\n'"$entry"$'\n'*) ;; *) keep+=("$entry") ;; esac
    done
    REPORT_ERRORS=(${keep[@]+"${keep[@]}"})
}

run_end_heal() {
    RUN_END_HEAL_ATTEMPTED=0
    RUN_END_HEAL_VERIFIED=0
    RUN_END_HEAL_UNRESOLVED=0
    RUN_END_HEAL_SKIPPED=0
    RUN_END_HEAL_UNREPAIRABLE=0
    # A preview promises that no scans or repairs run.
    [ "${DRY_RUN:-false}" = true ] && return 0

    local logfile="${LOGFILE:-}"
    if [ -z "$logfile" ] || [ ! -f "$logfile" ] || [ ! -r "$logfile" ]; then
        log WARN "Run-end review: log file missing or unreadable (${logfile:-unset}) — run-end heal skipped"
        return 0
    fi

    local -a findings=(${REPORT_WARNINGS[@]+"${REPORT_WARNINGS[@]}"} ${REPORT_ERRORS[@]+"${REPORT_ERRORS[@]}"})
    log INFO "Run-end review: ${#findings[@]} report findings, $(_run_end_heal_log_lines "$logfile") WARN/ERROR log lines this run"

    if [ "${RUN_END_HEAL:-true}" != true ] || [ "${RUN_STATUS:-}" != completed ] ||
        [ "${INTERRUPTED:-false}" = true ]; then
        log STEP "   Run-end heal: off (RUN_END_HEAL=${RUN_END_HEAL:-true}, status ${RUN_STATUS:-unknown})"
        return 0
    fi

    # Classify: one entry per repair subject (repairer + target); every finding
    # without a repairer is reported once and never acted on.
    local -a subjects=() cmds=() keys=() names=() members=()
    local entry finding cmd fn arg subj i found
    for entry in ${findings[@]+"${findings[@]}"}; do
        finding=${entry%% (exit*}
        cmd=$(run_end_heal_repairer "$entry")
        if [ -z "$cmd" ]; then
            RUN_END_HEAL_UNREPAIRABLE=$((RUN_END_HEAL_UNREPAIRABLE + 1))
            log INFO "Run-end heal: no automatic repair — $finding"
            continue
        fi
        read -r fn arg _ <<< "$cmd"
        subj="$fn $arg"
        found=''
        for i in ${subjects[@]+"${!subjects[@]}"}; do
            if [ "${subjects[$i]}" = "$subj" ]; then
                members[i]="${members[i]}"$'\n'"$entry"
                found=1
                break
            fi
        done
        [ -n "$found" ] && continue
        subjects+=("$subj")
        cmds+=("$cmd")
        keys+=("$(_run_end_heal_key "$entry")")
        names+=("$finding")
        members+=("$entry")
    done

    local dir="${MEISTER_DIR:-$HOME/.meister}" max_sec="${RUN_END_HEAL_MAX_SEC:-300}"
    local max_att="${RUN_END_HEAL_MAX_ATTEMPTS:-5}" state row n ts now start new_state='' tmp
    case "$max_sec" in ''|*[!0-9]*) max_sec=300 ;; esac
    case "$max_att" in ''|*[!0-9]*) max_att=5 ;; esac
    state="$dir/run_end_heal.tsv"
    # Each repair stays inside the configured per-cask bound (brew_cask_repair).
    # shellcheck disable=SC2034  # read by brew_cask_repair (dynamic scope)
    local BREW_CASK_REPAIR_TIMEOUT="${BREW_CASK_TIMEOUT_SEC:-180}"
    start=$(date +%s)

    for i in ${subjects[@]+"${!subjects[@]}"}; do
        row=$(_run_end_heal_state_get "$state" "${keys[$i]}")
        n=0; ts=0
        [ -z "$row" ] || { n=${row%% *}; ts=${row#* }; }
        now=$(date +%s)
        if [ "$n" -ge "$RUN_END_HEAL_SUSPEND_RUNS" ] && [ $((now - ts)) -lt "$RUN_END_HEAL_SUSPEND_SEC" ]; then
            RUN_END_HEAL_SKIPPED=$((RUN_END_HEAL_SKIPPED + 1))
            log STEP "   Run-end heal: suspended after $n unresolved runs — ${names[$i]}"
            new_state+="${keys[$i]}"$'\t'"$n"$'\t'"$ts"$'\n'
            continue
        fi
        if [ $((now - start)) -ge "$max_sec" ] || [ "$RUN_END_HEAL_ATTEMPTED" -ge "$max_att" ]; then
            RUN_END_HEAL_SKIPPED=$((RUN_END_HEAL_SKIPPED + 1))
            log STEP "   Run-end heal: budget used — skipped ${names[$i]}"
            [ -z "$row" ] || new_state+="${keys[$i]}"$'\t'"$n"$'\t'"$ts"$'\n'
            continue
        fi
        RUN_END_HEAL_ATTEMPTED=$((RUN_END_HEAL_ATTEMPTED + 1))
        read -r fn arg _ <<< "${cmds[$i]}"
        # Like the module call site: pre-authenticate, attempt regardless.
        if command -v ensure_sudo >/dev/null 2>&1; then
            ensure_sudo "run-end cask reinstall: $arg" 2>/dev/null || true
        fi
        if eval "${cmds[$i]}"; then
            RUN_END_HEAL_VERIFIED=$((RUN_END_HEAL_VERIFIED + 1))
            VERIFIED_REPAIR_COUNT=$((${VERIFIED_REPAIR_COUNT:-0} + 1))
            _run_end_heal_retract "${members[$i]}"
            REPORT_FIXED+=("Run-end heal: verified — ${names[$i]}")
            log FIX "Run-end heal: verified — ${names[$i]}"
            ! command -v log_heal_event >/dev/null 2>&1 ||
                log_heal_event run-end "$arg" verified "${cmds[$i]}"
        else
            RUN_END_HEAL_UNRESOLVED=$((RUN_END_HEAL_UNRESOLVED + 1))
            REPORT_WARNINGS+=("Run-end heal: unresolved — ${names[$i]}")
            log WARN "Run-end heal: unresolved — ${names[$i]}"
            new_state+="${keys[$i]}"$'\t'"$((n + 1))"$'\t'"$(date +%s)"$'\n'
            ! command -v log_heal_event >/dev/null 2>&1 ||
                log_heal_event run-end "$arg" unresolved "${cmds[$i]}"
        fi
    done

    # Keep only findings still open in this run: a run without the finding
    # ends its streak of consecutive unresolved runs.
    if [ -z "$new_state" ]; then
        rm -f "$state" 2>/dev/null
    elif tmp=$(mktemp "$dir/.run_end_heal.XXXXXX" 2>/dev/null); then
        printf '%s' "$new_state" > "$tmp" && mv "$tmp" "$state" || rm -f "$tmp"
    fi
    return 0
}
