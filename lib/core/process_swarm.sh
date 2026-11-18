# shellcheck shell=bash
# Report-only load / process-swarm / fsmonitor checks for module_performance.
# Never signals, stops or unloads anything: the user decided (2026-11-18) that
# Meister only reports these; producers are fixed at their source.
# Snapshot input on stdin: "pid uid stat comm" (ps -axo pid=,uid=,stat=,comm=),
# where comm may be a full path and may contain spaces.

# Prints "name<TAB>count" per command basename, most frequent first.
# $1 = only rows whose stat starts with R (1) or all rows (0).
_meister_proc_group() {
    awk -v runnable="$1" '
        NF >= 4 {
            if (runnable == 1 && substr($3, 1, 1) != "R") next
            line = $0
            sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]+[^ \t]+[ \t]+/, "", line)
            sub(/.*\//, "", line)
            if (line != "") n[line]++
        }
        END { for (c in n) printf "%s\t%d\n", c, n[c] }
    ' | sort -t "$(printf '\t')" -k2,2nr -k1,1
}

# Joins "name<TAB>count" lines to "name (count), ...".
_meister_proc_join() {
    awk -F '\t' '{ printf "%s%s (%s)", (NR > 1 ? ", " : ""), $1, $2 }'
}

# WARN when load1 exceeds 2x the core count, naming the top 5 runnable commands.
meister_load_check() {
    local load1="$1" ncpu="$2" verdict top msg
    case "$ncpu" in ''|*[!0-9]*) ncpu=1 ;; esac
    [ "$ncpu" -gt 0 ] 2>/dev/null || ncpu=1
    verdict=$(awk -v l="$load1" -v c="$ncpu" 'BEGIN {
        if (l !~ /^[0-9]+(\.[0-9]+)?$/) { print "na"; exit }
        if (l + 0 > 2 * c) printf "%.1f\n", l / c; else print "ok"
    }')
    case "$verdict" in
        na) log INFO "   Load check: load unavailable"; return 0 ;;
        ok|'') return 0 ;;
    esac
    top=$(_meister_proc_group 1 | head -5 | _meister_proc_join)
    msg="Load ${load1} on ${ncpu} cores (${verdict}x) — runnable: ${top:-none}"
    log WARN "   $msg"
    report_add WARN "$msg"
    return 0
}

# One WARN listing every command with at least $1 (default 20) instances.
meister_proc_swarm_counts() {
    local threshold="$1" list msg
    case "$threshold" in ''|*[!0-9]*) threshold=20 ;; esac
    list=$(_meister_proc_group 0 | awk -F '\t' -v t="$threshold" '$2 >= t' | _meister_proc_join)
    [ -n "$list" ] || return 0
    msg="Process swarm: $list"
    log WARN "   $msg"
    report_add WARN "$msg"
    return 0
}

# One WARN when at least $1 (default 20) git fsmonitor daemons run, split by
# gitdir kind from their IPC socket path (one lsof call for all PIDs).
meister_fsmonitor_report() {
    local threshold="$1" pids total split msg
    case "$threshold" in ''|*[!0-9]*) threshold=20 ;; esac
    pids=$(ps -axo pid=,command= 2>/dev/null | awk '/fsmonitor--daemon run/ && $2 !~ /awk$/ { print $1 }')
    total=$(printf '%s\n' "$pids" | grep -c '[0-9]')
    [ "$total" -ge "$threshold" ] || return 0
    split=$( { lsof -a -p "$(printf '%s\n' "$pids" | paste -sd, -)" -U -Fpn 2>/dev/null || true; } | awk -v total="$total" '
        /^p/ { pid = substr($0, 2); next }
        /^n/ {
            path = substr($0, 2)
            if (path !~ /fsmonitor--daemon\.ipc$/ || seen[pid]++) next
            if (path ~ /\/\.git\/worktrees\//) w++
            else if (path ~ /\/\.git\/modules\//) s++
            else if (path ~ /^\/.*\/\.git\/fsmonitor--daemon\.ipc$/) m++
        }
        END { printf "%d/%d/%d/%d", m, w, s, total - m - w - s }
    ')
    msg="git fsmonitor: ${total} daemons (${split} main/worktree/submodule/unresolved) — set core.fsmonitor=false for batch git runs"
    log WARN "   $msg"
    report_add WARN "$msg"
    return 0
}
