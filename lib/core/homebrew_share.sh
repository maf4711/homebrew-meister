# shellcheck shell=bash
# Share one Homebrew prefix with every admin user.
# Do not chown the tree. Group admin + setgid + an inherited ACL, and
# git safe.directory for /usr/bin/git and Homebrew's own git.

homebrew_share_acl_ace() {
    printf '%s\n' \
        'group:admin allow read,write,execute,append,delete,add_file,add_subdirectory,delete_child,file_inherit,directory_inherit'
}

# $1 = prefix  $2 = newline-separated safe.directory values already set.
# Prints missing entries. Returns 1 when anything is missing.
homebrew_share_missing_entries() {
    local prefix="$1" have="${2-}" want missing=0
    [ -n "$prefix" ] || return 0
    for want in "$prefix" "${prefix}/*"; do
        if ! printf '%s\n' "$have" | grep -Fxq -- "$want"; then
            printf '%s\n' "$want"
            missing=1
        fi
    done
    return "$missing"
}

# $1 = stat -f %Sp mode, e.g. drwxrwsr-x. Group write and setgid.
homebrew_share_mode_ok() {
    local mode="$1"
    [ "${#mode}" -ge 7 ] || return 1
    [ "${mode:5:1}" = "w" ] || return 1
    case "${mode:6:1}" in
        s|S) return 0 ;;
    esac
    return 1
}

# $1 = `ls -led` text for the prefix.
homebrew_share_acl_text_ok() {
    local text="$1"
    printf '%s\n' "$text" | grep -q 'group:admin' || return 1
    printf '%s\n' "$text" | grep -q 'file_inherit' || return 1
    printf '%s\n' "$text" | grep -q 'directory_inherit' || return 1
}

# Prints one "gap <what>" line per problem. Returns 1 when the prefix
# is not shared. Quiet and read-only.
homebrew_share_gaps() {
    local prefix="$1" mode acl have gitbin missing gap=0
    [ -d "$prefix" ] || return 0
    mode=$(/usr/bin/stat -f '%Sp' "$prefix" 2>/dev/null || true)
    if ! homebrew_share_mode_ok "$mode"; then
        printf '%s\n' "gap mode"
        gap=1
    fi
    acl=$(/bin/ls -led "$prefix" 2>/dev/null || true)
    if ! homebrew_share_acl_text_ok "$acl"; then
        printf '%s\n' "gap acl"
        gap=1
    fi
    for gitbin in /usr/bin/git "${prefix}/bin/git"; do
        [ -x "$gitbin" ] || continue
        have=$("$gitbin" config --system --get-all safe.directory 2>/dev/null || true)
        if ! homebrew_share_missing_entries "$prefix" "$have" >/dev/null; then
            printf '%s\n' "gap safe ${gitbin}"
            gap=1
        fi
    done
    return "$gap"
}

# Apply the share. Caller must already have a sudo ticket.
# $2/$3/$4 = true|false for mode, acl, safe.directory.
homebrew_share_apply() {
    local prefix="$1" do_mode="${2:-true}" do_acl="${3:-true}" do_safe="${4:-true}"
    [ -d "$prefix" ] || return 1
    /usr/bin/sudo -n /bin/bash -s -- "$prefix" "$do_mode" "$do_acl" "$do_safe" <<'EOS'
prefix="$1"
do_mode="$2"
do_acl="$3"
do_safe="$4"
run() {
    set +e
    "$@"
    set -e
    return 0
}
if [ "$do_mode" = "true" ]; then
    run /usr/bin/chgrp -R admin "$prefix"
    run /bin/chmod -R u+rwX,g+rwX,o-w "$prefix"
    run /usr/bin/find "$prefix" -type d -exec /bin/chmod g+s {} +
    if [ -d "$prefix/share/zsh" ]; then
        run /usr/sbin/chown -R root:admin "$prefix/share/zsh"
        run /usr/bin/find "$prefix/share/zsh" -type d -exec /bin/chmod g+rwxs {} +
    fi
fi
if [ "$do_acl" = "true" ]; then
    ace='group:admin allow read,write,execute,append,delete,add_file,add_subdirectory,delete_child,file_inherit,directory_inherit'
    run /usr/bin/find "$prefix" -type d -exec /bin/chmod +a "$ace" {} +
fi
if [ "$do_safe" = "true" ]; then
    mark() {
        local gitbin="$1" dir="$2"
        [ -x "$gitbin" ] || return 0
        if "$gitbin" config --system --get-all safe.directory 2>/dev/null | /usr/bin/grep -Fxq -- "$dir"; then
            return 0
        fi
        "$gitbin" config --system --add safe.directory "$dir"
    }
    for gitbin in /usr/bin/git "$prefix/bin/git"; do
        mark "$gitbin" "$prefix"
        mark "$gitbin" "$prefix/*"
    done
fi
EOS
}

# Heal a Darwin admin prefix. No-op when already shared.
# Needs log, report_add, ensure_sudo from the CLI. Skips without a sudo
# ticket instead of prompting forever (LaunchAgents have no TTY).
homebrew_share_ensure() {
    local prefix gaps do_mode=false do_acl=false do_safe=false
    [ "$(uname -s)" = "Darwin" ] || return 0
    command -v brew >/dev/null 2>&1 || return 0
    prefix=$(brew --prefix 2>/dev/null || true)
    [ -n "$prefix" ] && [ -d "$prefix" ] || return 0
    if gaps=$(homebrew_share_gaps "$prefix"); then
        command -v log >/dev/null 2>&1 && log STEP "   Homebrew prefix shared for admin users"
        return 0
    fi
    printf '%s\n' "$gaps" | grep -qx 'gap mode' && do_mode=true
    printf '%s\n' "$gaps" | grep -qx 'gap acl' && do_acl=true
    printf '%s\n' "$gaps" | grep -q '^gap safe ' && do_safe=true
    if [ "${DRY_RUN:-false}" = "true" ]; then
        command -v log >/dev/null 2>&1 && log STEP "   [DRY-RUN] would share $prefix ($gaps)"
        command -v report_add >/dev/null 2>&1 && report_add WOULD "Share Homebrew prefix for admin users"
        return 0
    fi
    if ! command -v ensure_sudo >/dev/null 2>&1 || ! ensure_sudo "Homebrew share for admin users"; then
        command -v log >/dev/null 2>&1 && log WARN "   Homebrew is not shared for every admin user (sudo once: homebrew-share)"
        command -v report_add >/dev/null 2>&1 && report_add WARN "Homebrew share skipped (no sudo)"
        return 0
    fi
    if homebrew_share_apply "$prefix" "$do_mode" "$do_acl" "$do_safe"; then
        command -v log >/dev/null 2>&1 && log FIX "   Homebrew prefix shared for admin users"
        command -v report_add >/dev/null 2>&1 && report_add FIX "Shared Homebrew prefix for admin users"
        return 0
    fi
    command -v log >/dev/null 2>&1 && log WARN "   Homebrew share failed"
    command -v report_add >/dev/null 2>&1 && report_add WARN "Homebrew share failed"
    return 0
}
