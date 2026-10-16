#!/usr/bin/env bats
# These fixtures replace Brew, Git and both CLIs. No host package operation runs.
setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export TEST_ROOT="$BATS_TEST_TMPDIR/install"
  export TARGET_VERSION=9.99
  export STUB_FAIL="" STUB_VERSION_AFTER="" STUB_BUNDLE_VERSION=""
  mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/tap/.git"
  printf 'retained download\n' > "$TEST_ROOT/download-cache"
  export PATH="$TEST_ROOT/bin:$PATH"
  cat > "$TEST_ROOT/bin/brew" <<'PY'
#!/usr/bin/env python3
import json, os, plistlib, sys
from pathlib import Path
root = Path(os.environ['TEST_ROOT'])
args = sys.argv[1:]
def seed(kind, version):
    (root / (kind + '-version')).write_text(version)
    if kind == 'formula':
        keg = root / 'Cellar/meister' / version
        for folder in ('bin', 'libexec'):
            (keg / folder).mkdir(parents=True, exist_ok=True)
        for name in ('meister', 'MeisterAI'):
            # Public wrappers must not be executed just to verify a release:
            # they own normal startup updates, which are tested separately.
            public = keg / 'bin' / name
            public.write_text('#!/bin/bash\necho unexpected-wrapper >> "$TEST_ROOT/events"\nexit 98\n')
            public.chmod(0o755)
            runtime = keg / 'libexec' / name
            runtime.write_text(f'#!/bin/bash\n[ "$*" = --version ] || exit 97\nprintf "%s\\n" "{name} v{version} (fixture)"\n')
            runtime.chmod(0o755)
            link = root / 'bin' / name
            if link.is_symlink(): link.unlink()
            link.symlink_to(public)
        (root / 'opt').mkdir(exist_ok=True)
        link = root / 'opt/meister'
        if link.is_symlink(): link.unlink()
        link.symlink_to(keg)
    else:
        app = root / 'Caskroom/meister-mac' / version / 'MeisterAI.app/Contents'
        app.mkdir(parents=True, exist_ok=True)
        with (app / 'Info.plist').open('wb') as stream:
            plistlib.dump({'CFBundleShortVersionString': os.environ.get('STUB_BUNDLE_VERSION') or version + '.0'}, stream)
if args[0] == 'fixture-seed':
    seed(args[1], args[2]); sys.exit(0)
with (root / 'events').open('a') as stream: stream.write(' '.join(args) + '\n')
failure = os.environ.get('STUB_FAIL')
if args[0] == failure or failure == 'package' and args[0] in ('install', 'upgrade'):
    sys.exit(7)
if args[0] == 'list':
    assert args[:2] == ['list', '--versions'] and args[2] in ('--formula', '--cask'), args
    kind = args[2][2:]
    path = root / (kind + '-version')
    if path.exists(): print(('meister' if kind == 'formula' else 'meister-mac') + ' ' + path.read_text())
elif args[0] in ('install', 'upgrade'):
    assert args[1] in ('--formula', '--cask'), args
    seed(args[1][2:], os.environ.get('STUB_VERSION_AFTER') or os.environ['TARGET_VERSION'])
elif args[0] == 'update': pass
elif args[0] == '--prefix': print(root if len(args) == 1 else root / 'opt/meister')
elif args[0] == '--cellar': print(root / 'Cellar/meister')
elif args[0] == '--caskroom': print(root / 'Caskroom/meister-mac')
elif args[0] == '--repo': print(root / 'tap')
else: raise SystemExit('Unexpected Brew operation: ' + json.dumps(args))
PY
  cat > "$TEST_ROOT/bin/git" <<'SH'
#!/bin/bash
printf 'git %s\n' "$*" >> "$TEST_ROOT/events"
[ "${STUB_GIT_FAIL:-false}" != true ]
SH
  chmod +x "$TEST_ROOT/bin/brew" "$TEST_ROOT/bin/git"
}

@test "current CLI release only verifies and preserves public links and downloads" {
  brew fixture-seed formula "$TARGET_VERSION"
  brew fixture-seed cask 6.32
  before=$(readlink "$TEST_ROOT/bin/MeisterAI")
  run bash "$ROOT/scripts/install-release.sh" "$TARGET_VERSION"
  [ "$status" = 0 ]
  [[ "$output" == *'already installed; verifying without reinstall'* ]]
  [[ "$output" == *'CLI-only release: existing app installation left unchanged'* ]]
  ! grep -Eq '^(update|install|upgrade|reinstall|git)|--cask|unexpected-wrapper' "$TEST_ROOT/events"
  [ "$(readlink "$TEST_ROOT/bin/MeisterAI")" = "$before" ]
  [ "$(cat "$TEST_ROOT/download-cache")" = 'retained download' ]
  [ "$(cat "$TEST_ROOT/cask-version")" = 6.32 ]
}

@test "missing formula installs once and a repeated invocation only verifies" {
  run bash "$ROOT/scripts/install-release.sh" "$TARGET_VERSION"
  [ "$status" = 0 ]
  run bash "$ROOT/scripts/install-release.sh" "$TARGET_VERSION"
  [ "$status" = 0 ]
  [ "$(grep -c '^install --formula maf4711/meister/meister$' "$TEST_ROOT/events")" = 1 ]
  [ "$(grep -c '^update$' "$TEST_ROOT/events")" = 1 ]
  ! grep -Eq '^upgrade|^reinstall|--cask|unexpected-wrapper' "$TEST_ROOT/events"
}

@test "outdated formula upgrades through its existing Homebrew owner" {
  brew fixture-seed formula 9.98
  run bash "$ROOT/scripts/install-release.sh" "$TARGET_VERSION"
  [ "$status" = 0 ]
  grep -q '^upgrade --formula maf4711/meister/meister$' "$TEST_ROOT/events"
  ! grep -Eq '^install|^reinstall|--cask' "$TEST_ROOT/events"
  [ "$(cat "$TEST_ROOT/formula-version")" = "$TARGET_VERSION" ]
}

@test "new app asset installs missing cask and upgrades older cask without reinstalling" {
  brew fixture-seed formula "$TARGET_VERSION"
  run bash "$ROOT/scripts/install-release.sh" "$TARGET_VERSION" --app-version "$TARGET_VERSION"
  [ "$status" = 0 ]
  grep -q '^install --cask maf4711/meister/meister-mac$' "$TEST_ROOT/events"
  brew fixture-seed cask 9.98
  run bash "$ROOT/scripts/install-release.sh" "$TARGET_VERSION" --app-version "$TARGET_VERSION"
  [ "$status" = 0 ]
  grep -q '^upgrade --cask maf4711/meister/meister-mac$' "$TEST_ROOT/events"
  ! grep -q '^reinstall' "$TEST_ROOT/events"
}

@test "already current app and formula need no metadata refresh or package writes" {
  brew fixture-seed formula "$TARGET_VERSION"
  brew fixture-seed cask "$TARGET_VERSION"
  run bash "$ROOT/scripts/install-release.sh" "$TARGET_VERSION" --app-version "$TARGET_VERSION"
  [ "$status" = 0 ]
  [[ "$output" == *"MeisterAI.app: $TARGET_VERSION.0"* ]]
  ! grep -Eq '^(update|install|upgrade|reinstall|git)' "$TEST_ROOT/events"
}

@test "failed upgrade stops without a second alias attempt or deleting existing installation" {
  brew fixture-seed formula 9.98
  export STUB_FAIL=package
  before=$(readlink "$TEST_ROOT/bin/MeisterAI")
  run bash "$ROOT/scripts/install-release.sh" "$TARGET_VERSION"
  [ "$status" != 0 ]
  [[ "$output" == *'upgrade failed'*'no reinstall attempted'* ]]
  [ "$(grep -c '^upgrade ' "$TEST_ROOT/events")" = 1 ]
  [ "$(readlink "$TEST_ROOT/bin/MeisterAI")" = "$before" ]
  [ -f "$TEST_ROOT/download-cache" ]
  ! grep -q '^reinstall' "$TEST_ROOT/events"
}

@test "successful Brew exit with wrong installed version is a release failure" {
  brew fixture-seed formula 9.98
  export STUB_VERSION_AFTER=9.98
  run bash "$ROOT/scripts/install-release.sh" "$TARGET_VERSION"
  [ "$status" != 0 ]
  [[ "$output" == *'has version(s) 9.98; expected 9.99'* ]]
  ! grep -q '^reinstall' "$TEST_ROOT/events"
}

@test "inventory failures cannot be mistaken for a missing installation" {
  export STUB_FAIL=list
  run bash "$ROOT/scripts/install-release.sh" "$TARGET_VERSION"
  [ "$status" != 0 ]
  [[ "$output" == *'Cannot read installed formula packages'* ]]
  ! grep -Eq '^(update|install|upgrade|reinstall)' "$TEST_ROOT/events"
}

@test "wrong app bundle version fails even when the cask receipt is current" {
  brew fixture-seed formula "$TARGET_VERSION"
  export STUB_BUNDLE_VERSION=6.32.0
  brew fixture-seed cask "$TARGET_VERSION"
  run bash "$ROOT/scripts/install-release.sh" "$TARGET_VERSION" --app-version "$TARGET_VERSION"
  [ "$status" != 0 ]
  [[ "$output" == *'Installed app version does not match'* ]]
  ! grep -Eq '^(update|install|upgrade|reinstall)' "$TEST_ROOT/events"
}

@test "failed metadata fallback stops before package writes" {
  export STUB_FAIL=update STUB_GIT_FAIL=true
  run bash "$ROOT/scripts/install-release.sh" "$TARGET_VERSION"
  [ "$status" != 0 ]
  [[ "$output" == *'Cannot refresh the Meister tap'* ]]
  ! grep -Eq '^(install|upgrade|reinstall)' "$TEST_ROOT/events"
}

@test "release Step 6 passes an app only after publication recorded its version" {
  brew fixture-seed formula "$TARGET_VERSION"
  # Execute the actual installation step, without running GitHub/Git publishing.
  step=$(sed -n '/^# 6\. ALWAYS install locally/,/^echo "=== Release /p' "$ROOT/release.sh" | sed '$d')
  export SCRIPT_DIR="$ROOT" VERSION="$TARGET_VERSION" APP_RELEASED_VERSION=""
  run bash -c "$step"
  [ "$status" = 0 ]
  ! grep -q -- '--cask' "$TEST_ROOT/events"
  export APP_RELEASED_VERSION="$TARGET_VERSION"
  run bash -c "$step"
  [ "$status" = 0 ]
  grep -q '^install --cask maf4711/meister/meister-mac$' "$TEST_ROOT/events"
}

@test "stale app ZIP blocks release before GitHub Git or Brew side effects" {
  fixture="$TEST_ROOT/release"
  mkdir -p "$fixture/app/MeisterAI/dist"
  cp "$ROOT/release.sh" "$fixture/release.sh"
  printf '# Version: %s\n' "$TARGET_VERSION" > "$fixture/meister.sh"
  python3 - "$fixture/app/MeisterAI/dist/MeisterAI-macOS.zip" <<'PY'
import plistlib, sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as archive:
    archive.writestr('MeisterAI.app/Contents/Info.plist', plistlib.dumps({'CFBundleShortVersionString': '6.32.0'}))
PY
  cat > "$TEST_ROOT/bin/gh" <<'SH'
#!/bin/bash
echo unexpected-gh >> "$TEST_ROOT/events"
exit 99
SH
  chmod +x "$TEST_ROOT/bin/gh"
  run bash "$fixture/release.sh"
  [ "$status" != 0 ]
  [[ "$output" == *"App ZIP version '6.32.0'; expected $TARGET_VERSION"* ]]
  [ ! -e "$TEST_ROOT/events" ]
}

@test "app ZIP version check accepts matching marketing version and rejects malformed metadata" {
  eval "$(awk '$0=="release_verify_app_zip() {" {on=1} on {print} on && /^}$/ {exit}' "$ROOT/release.sh")"
  python3 - "$TEST_ROOT" "$TARGET_VERSION" <<'PY'
import plistlib, sys, zipfile
from pathlib import Path
for name, content in [('matching', plistlib.dumps({'CFBundleShortVersionString': sys.argv[2]+'.0'})), ('malformed', b'invalid plist')]:
    with zipfile.ZipFile(Path(sys.argv[1]) / (name+'.zip'), 'w') as archive:
        archive.writestr('MeisterAI.app/Contents/Info.plist', content)
PY
  run release_verify_app_zip "$TEST_ROOT/matching.zip" "$TARGET_VERSION"
  [ "$status" = 0 ]
  run release_verify_app_zip "$TEST_ROOT/malformed.zip" "$TARGET_VERSION"
  [ "$status" != 0 ]
}
