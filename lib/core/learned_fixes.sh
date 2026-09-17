# shellcheck shell=bash
# Evidence cache v2: module/failure fingerprint/OS/command -> verified outcomes.
# Legacy entries have no context or proof: retained as quarantined evidence only.
# TSV: module fingerprint os command successes failures consecutive suspended updated

heal_context_os() {
    printf '%s' "${MEISTER_OS_VERSION:-$(sw_vers -productVersion 2>/dev/null)-$(sw_vers -buildVersion 2>/dev/null)-$(uname -m)}"
}

heal_failure_fingerprint() {
    # Normalize incidental runtime IDs, but preserve paths, exit codes and versions.
    printf '%s' "${1:-}" | LC_ALL=C sed -E \
        -e $'s/\033\\[[0-9;]*[[:alpha:]]//g' \
        -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ]+[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z?/<time>/g' \
        -e 's/[Pp][Ii][Dd][=: ]+[0-9]+/pid=<pid>/g' \
        -e 's/0x[0-9a-fA-F]+/<address>/g' | \
        awk '{$1=$1; if (length) printf "%s ",$0}' | \
        shasum -a 256 | awk '{print $1}'
}

heal_context_begin() {
    HEAL_FAILURE_FINGERPRINT=$(heal_failure_fingerprint "$2")
    HEAL_CONTEXT_MODULE="$1"
    HEAL_CONTEXT_OS=$(heal_context_os)
}

learned_fix_safe_field() {
    case "$1" in ''|*$'\t'*|*$'\n'*|*$'\r'*) return 1 ;; *) return 0 ;; esac
}

learned_fix_lookup() {
    local module="$1" file="${MEISTER_DIR}/learned_fixes.v2.tsv"
    [ "${HEAL_CONTEXT_MODULE:-}" = "$module" ] || return 1
    [ -f "$file" ] || return 1
    awk -F'\t' -v m="$module" -v f="${HEAL_FAILURE_FINGERPRINT:-}" -v os="${HEAL_CONTEXT_OS:-}" '
        NF==9 && $1==m && $2==f && $3==os && $5~/^[0-9]+$/ && $5>0 && $8==0 {
            if (!found || $5>best) {cmd=$4; best=$5; found=1}
        } END {if (found) print cmd; else exit 1}' "$file"
}

learned_fix_suspended() {
    local module="$1" cmd="$2" file="${MEISTER_DIR}/learned_fixes.v2.tsv"
    [ -f "$file" ] || return 1
    awk -F'\t' -v m="$module" -v c="$cmd" -v f="${HEAL_FAILURE_FINGERPRINT:-}" -v os="${HEAL_CONTEXT_OS:-}" '
        NF==9 && $1==m && $2==f && $3==os && $4==c && $8==1 {found=1}
        END {exit !found}' "$file"
}

# $3 = verified|failed. Suggestions, previews and missing context never learn.
learned_fix_record() {
    local module="$1" cmd="$2" outcome="$3" dir="${MEISTER_DIR}"
    [ "${DRY_RUN:-false}" != true ] || return 0
    [ "${AI_HEAL_EXECUTE:-false}" = true ] || return 0
    [ "${HEAL_CONTEXT_MODULE:-}" = "$module" ] || return 1
    local field
    for field in "$module" "$cmd" "${HEAL_FAILURE_FINGERPRINT:-}" "${HEAL_CONTEXT_OS:-}"; do
        learned_fix_safe_field "$field" || return 1
    done
    heal_command_allowed "$cmd" || return 1
    case "$outcome" in verified|failed) ;; *) return 1 ;; esac
    mkdir -p "$dir" || return 1
    local file="$dir/learned_fixes.v2.tsv" tmp input
    # Dynamic-scoped ownership keeps the main run token intact while reusing the
    # atomic lock and dead-owner recovery for short evidence transactions.
    # shellcheck disable=SC2034
    local LOCKFILE="$dir/learned_fixes.v2.lock" RUN_LOCK_TOKEN=''
    acquire_lock || return 1
    tmp=$(mktemp "$dir/.learned.XXXXXX") || { release_lock; return 1; }
    input="$file"
    [ -f "$file" ] || input=/dev/null
    # Reject malformed rows while recovering remaining valid evidence.
    awk -F'\t' -v OFS='\t' -v m="$module" -v c="$cmd" \
        -v f="$HEAL_FAILURE_FINGERPRINT" -v os="$HEAL_CONTEXT_OS" \
        -v outcome="$outcome" -v ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" '
        NF==9 && $5~/^[0-9]+$/ && $6~/^[0-9]+$/ && $7~/^[0-9]+$/ && $8~/^[01]$/ {
            if ($1==m && $2==f && $3==os && $4==c) {ok=$5; fail=$6; streak=$7}
            else print
        }
        END {
            if (outcome=="verified") {ok++; streak=0} else {fail++; streak++}
            print m,f,os,c,ok+0,fail+0,streak+0,(streak>=3 ? 1 : 0),ts
        }' "$input" > "$tmp"
    local rc=$?
    # Migration never upgrades a legacy command to trusted: context is unknown.
    if [ "$rc" -eq 0 ] && [ ! -f "$file" ] && [ -f "$dir/learned_fixes" ]; then
        awk -F'\t' -v OFS='\t' 'NF==2 {print $1,"legacy-unscoped","unknown",$2,0,0,0,1,"legacy"}' \
            "$dir/learned_fixes" >> "$tmp" || rc=$?
    fi
    if [ "$rc" -eq 0 ]; then mv "$tmp" "$file" || rc=$?; fi
    rm -f "$tmp"
    release_lock
    return "$rc"
}

try_learned_fix() {
    local module_name="$1" cmd
    cmd=$(learned_fix_lookup "$module_name") || return 1
    heal_catalog_command_allowed "$cmd" || return 1
    heal_command_allowed "$cmd" || return 1
    # Consumed by the caller after execution.
    # shellcheck disable=SC2034
    AI_LAST_CMD="$cmd"
    ai_usage_record learned-fix heal-candidate no-model "module=$module_name (matching context)"
    if [ "${AI_HEAL_EXECUTE:-false}" != true ]; then
        log HEAL "Learned-Fix suggestion (AI_HEAL_EXECUTE=false): $cmd"
        log_heal_event learned-fix "$module_name" suggested "$cmd"
        report_add WARN "Learned-Fix suggestion (not executed): $module_name → $cmd"
        return 1
    fi
    if [ "${DRY_RUN:-false}" = true ]; then
        log STEP "[DRY-RUN] Would execute: $cmd"
        report_add WOULD "$module_name: $cmd"
        log_heal_event learned-fix "$module_name" suggested "$cmd"
        return 1
    fi
    local argv=()
    read -ra argv <<< "$cmd"
    if timeout 30 "${argv[@]}" >/dev/null 2>&1; then
        log_heal_event learned-fix "$module_name" executed "$cmd"
        return 0
    fi
    learned_fix_record "$module_name" "$cmd" failed || true
    log_heal_event learned-fix "$module_name" failed "$cmd"
    return 1
}

remember_fix() { learned_fix_record "$1" "$2" verified; }
