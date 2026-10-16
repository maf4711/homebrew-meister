#!/bin/bash
# Ensure a published release is installed through Homebrew. Never reinstall an
# already current package. --app-version is only for a newly published app asset.
set -euo pipefail

fail() { printf 'Release install: %s\n' "$*" >&2; exit 1; }
version="${1:-}"
[[ "$version" =~ ^[0-9]+(\.[0-9]+)+$ ]] || fail 'Expected the published CLI version'
shift
app_version=""
if [ "$#" -gt 0 ]; then
    [ "$#" -eq 2 ] && [ "$1" = --app-version ] || fail 'Usage: install-release.sh VERSION [--app-version VERSION]'
    app_version="$2"
    [ "$app_version" = "$version" ] || fail 'Published app and CLI release versions must match'
fi
formula=maf4711/meister/meister
cask=maf4711/meister/meister-mac
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1
refreshed=false

installed_versions() {
    local kind="$1" token="$2" inventory
    # A successful full inventory distinguishes an absent package from a failed
    # Homebrew query. Do not treat a lookup error as permission to install.
    inventory=$(brew list --versions "--$kind") || fail "Cannot read installed $kind packages"
    printf '%s\n' "$inventory" | awk -v name="${token##*/}" '$1==name {for(i=2;i<=NF;i++) print $i}'
}

has_version() {
    local versions="$1" wanted="$2" installed
    while IFS= read -r installed; do
        [ "$installed" != "$wanted" ] || return 0
    done <<< "$versions"
    return 1
}

refresh_brew() {
    $refreshed && return 0
    if ! brew update; then
        printf '%s\n' 'WARN: brew update failed; refreshing the Meister tap directly' >&2
        local tap
        tap=$(brew --repo maf4711/meister) || fail 'Cannot locate the Meister tap'
        [ -e "$tap/.git" ] || fail 'Meister tap is not a Git checkout'
        git -C "$tap" pull --ff-only || fail 'Cannot refresh the Meister tap'
    fi
    refreshed=true
}

ensure_package() {
    local kind="$1" token="$2" wanted="$3" versions action
    versions=$(installed_versions "$kind" "$token") || exit 1
    if has_version "$versions" "$wanted"; then
        printf '%s %s already installed; verifying without reinstall\n' "$token" "$wanted"
        return 0
    fi
    action=upgrade
    [ -n "$versions" ] || action=install
    refresh_brew
    brew "$action" "--$kind" "$token" || fail "$action failed for $token; no reinstall attempted"
    versions=$(installed_versions "$kind" "$token") || exit 1
    has_version "$versions" "$wanted" || fail "$token has version(s) ${versions:-none}; expected $wanted"
}

ensure_package formula "$formula" "$version"
prefix=$(brew --prefix) || fail 'Cannot locate the Homebrew prefix'
keg=$(brew --prefix "$formula") || fail 'Cannot locate the Meister installation'
cellar=$(brew --cellar "$formula") || fail 'Cannot locate the Meister Cellar'
# Verify public links and PATH resolution before executing the installed runtime.
# Running the public auto-update wrapper merely to check --version would trigger
# another metadata refresh/upgrade when its regular maintenance cache is stale.
python3 - "$prefix" "$keg" "$cellar" "$version" <<'PY' || fail 'Homebrew ownership or executable verification failed; links were left unchanged'
import os, shutil, sys
from pathlib import Path
prefix, keg, cellar = map(Path, sys.argv[1:4])
expected = cellar / sys.argv[4]
if not expected.is_dir() or keg.resolve() != expected.resolve():
    raise SystemExit('Linked Meister installation does not match the requested release')
for name in ('meister', 'MeisterAI'):
    owned = expected / 'bin' / name
    public = prefix / 'bin' / name
    selected = shutil.which(name)
    runtime = expected / 'libexec' / name
    if not all(os.access(path, os.X_OK) for path in (owned, public, runtime)):
        raise SystemExit(f'Missing installed executable: {name}')
    if public.resolve() != owned.resolve() or not selected or Path(selected).resolve() != owned.resolve():
        raise SystemExit(f'{name} is shadowed or not linked to this Homebrew release')
    print(f'{name}: {public} -> {owned}')
PY
for executable in meister MeisterAI; do
    output=$("$keg/libexec/$executable" --version) || fail "$executable --version failed"
    read -r label installed_version _ <<< "$output"
    [ "$label" = "$executable" ] && [ "$installed_version" = "v$version" ] || fail "$executable reported '$output'; expected v$version"
    printf '%s\n' "$output"
done

if [ -n "$app_version" ]; then
    ensure_package cask "$cask" "$app_version"
    caskroom=$(brew --caskroom "$cask") || fail 'Cannot locate the app installation'
    python3 - "$caskroom/$app_version/MeisterAI.app/Contents/Info.plist" "$app_version" <<'PY' || fail 'Installed app version does not match the published release'
import plistlib, re, sys
def parts(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+)+', value):
        raise ValueError('Invalid app version')
    numbers = [int(part) for part in value.split('.')]
    while len(numbers) > 1 and numbers[-1] == 0:
        numbers.pop()
    return numbers
with open(sys.argv[1], 'rb') as stream:
    actual = plistlib.load(stream).get('CFBundleShortVersionString')
if parts(actual) != parts(sys.argv[2]):
    raise SystemExit(f'App version {actual!r}; expected {sys.argv[2]}')
print(f'MeisterAI.app: {actual}')
PY
else
    printf '%s\n' 'CLI-only release: existing app installation left unchanged'
fi
