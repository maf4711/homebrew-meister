# shellcheck shell=bash
# Publish a fully populated ownership directory atomically. No empty-owner or
# persistent reaper-lock window; read-only EXIT never releases another owner.

meister_lock_publish() {
    # POSIX rename replaces an EMPTY directory, and refuses any populated lock.
    # macOS ships system Perl; never install dependencies in a locking path.
    /usr/bin/perl -e 'exit(rename($ARGV[0], $ARGV[1]) ? 0 : 1)' "$1" "$2"
}

meister_lock_discard_candidate() {
    rm -f "$1/owner-$2"
    rmdir "$1" 2>/dev/null || true
}

acquire_lock() {
    local lock_dir="${LOCKFILE}.d" old_pid token candidate owner record
    [ -x /usr/bin/perl ] || { log ERROR 'Maintenance locking requires /usr/bin/perl'; return 1; }
    # Honor running legacy versions that only publish the compatibility PID file.
    if [ -f "$LOCKFILE" ]; then
        old_pid=$(cat "$LOCKFILE" 2>/dev/null)
        case "$old_pid" in ''|*[!0-9]*) ;; *)
            if kill -0 "$old_pid" 2>/dev/null; then
                log ERROR "Maintenance is already running (PID: $old_pid)"; return 1
            fi ;;
        esac
    fi
    candidate=$(mktemp -d "${LOCKFILE}.candidate.XXXXXX") || return 1
    token="$$:${candidate##*.}"
    if ! printf '%s\n' "$token" > "$candidate/owner-$token"; then
        meister_lock_discard_candidate "$candidate" "$token"; return 1
    fi
    if ! meister_lock_publish "$candidate" "$lock_dir"; then
        # Each immutable owner has a UNIQUE filename. A stale contender may only
        # unlink that captured owner: it cannot erase a replacement owner's file.
        # rmdir likewise refuses any concurrently published nonempty replacement.
        # The final /owner path is only for migration from the old lock format.
        for owner in "$lock_dir"/owner-* "$lock_dir/owner"; do
            [ -f "$owner" ] && [ ! -L "$owner" ] || continue
            record=$(cat "$owner" 2>/dev/null)
            old_pid="${record%%:*}"
            case "$old_pid" in ''|*[!0-9]*) continue ;; esac
            # A live/reused PID is conservatively treated as active. Do not infer
            # ownership or staleness from age, executable names, or PID reuse.
            if ! kill -0 "$old_pid" 2>/dev/null; then rm -f "$owner"; fi
        done
        rmdir "$lock_dir" 2>/dev/null || true
        if ! meister_lock_publish "$candidate" "$lock_dir"; then
            meister_lock_discard_candidate "$candidate" "$token"
            log ERROR 'Maintenance is already running; shared lock is held'; return 1
        fi
    fi
    RUN_LOCK_TOKEN="$token"
    if ! printf '%s\n' "$$" > "$LOCKFILE"; then release_lock; return 1; fi
    # Interrupted legacy reapers no longer control acquisition; remove only empty
    # metadata when possible, leaving any unknown contents untouched.
    rmdir "${lock_dir}.reap" 2>/dev/null || true
}

release_lock() {
    [ -n "${RUN_LOCK_TOKEN:-}" ] || return 0
    local owner="${LOCKFILE}.d/owner-${RUN_LOCK_TOKEN}"
    [ "$(cat "$owner" 2>/dev/null)" = "$RUN_LOCK_TOKEN" ] || return 0
    rm -f "$LOCKFILE" "$owner"
    rmdir "${LOCKFILE}.d" 2>/dev/null || true
    RUN_LOCK_TOKEN=''
}
