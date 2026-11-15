#!/bin/bash
# release.sh - Create a new Homebrew release (single-repo)
#
# 1. Reads version from meister.sh
# 2. Creates GitHub Release with tag
# 3. Updates SHA256 in Formula
# 4. Pushes everything
# 5. ALWAYS ensures the release is installed locally via brew (do not skip)
#
# Usage: ./release.sh
#
# MERKREGEL: Nach jedem Release IMMER lokal installieren
#   (install if missing, upgrade if outdated, verify if current). Sonst laufen Repo und
#   /opt/homebrew/bin auseinander. release.sh erledigt das in Step 6.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/meister.sh"
FORMULA="$SCRIPT_DIR/Formula/meister.rb"
REPO="maf4711/homebrew-meister"
APP_ZIP="$SCRIPT_DIR/app/MeisterAI/dist/MeisterAI-macOS.zip"
CASK="$SCRIPT_DIR/Casks/meister-mac.rb"
# shellcheck source=scripts/release-lib.sh
. "$SCRIPT_DIR/scripts/release-lib.sh"

release_verify_app_zip() {
    python3 - "$1" "$2" <<'PY'
import plistlib, re, sys, zipfile
def parts(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+)+', value):
        raise ValueError('Invalid app version')
    numbers = [int(part) for part in value.split('.')]
    while len(numbers) > 1 and numbers[-1] == 0:
        numbers.pop()
    return numbers
try:
    with zipfile.ZipFile(sys.argv[1]) as archive:
        path = 'MeisterAI.app/Contents/Info.plist'
        if archive.namelist().count(path) != 1 or archive.getinfo(path).file_size > 1_000_000:
            raise ValueError('Missing, duplicated or oversized app metadata')
        info = plistlib.loads(archive.read(path))
    actual = info.get('CFBundleShortVersionString')
    if parts(actual) != parts(sys.argv[2]):
        raise ValueError(f'App ZIP version {actual!r}; expected {sys.argv[2]}')
except (OSError, ValueError, KeyError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
    print(f'ERROR: {error}', file=sys.stderr)
    sys.exit(1)
PY
}

# Extract version from script
VERSION=$(grep -m1 '^# Version:' "$SOURCE" | awk '{print $3}')
if [[ -z "$VERSION" ]]; then
    echo "ERROR: Version not found in $SOURCE"
    exit 1
fi

# A leftover build is not a new app release. Reject it before any GitHub/Git
# publication, so CLI-only releases cannot republish or install an older app.
if [ -f "$APP_ZIP" ]; then
    release_verify_app_zip "$APP_ZIP" "$VERSION" || {
        echo "ERROR: App ZIP does not match this release; rebuild it or move it out of dist for a CLI-only release." >&2
        exit 1
    }
fi

# MERKREGEL: twins parallel — MeisterAI is source of truth
if [ -x "$SCRIPT_DIR/scripts/sync-twins.sh" ]; then
    echo "--- Twin sync (MeisterAI → meister) ---"
    "$SCRIPT_DIR/scripts/sync-twins.sh"
fi

# P1 quality gate (shellcheck lib + bats + bash -n)
if [ -x "$SCRIPT_DIR/scripts/check.sh" ]; then
    echo "--- Quality gate (scripts/check.sh) ---"
    "$SCRIPT_DIR/scripts/check.sh"
fi

echo "=== meister Release v${VERSION} ==="
echo ""

# 1. Commit and push all changes
echo "--- Step 1: Update repo ---"
cd "$SCRIPT_DIR"
git add meister.sh MeisterAI.sh tools/ Formula/ LICENSE .gitignore release.sh 2>/dev/null || true
git add meister.sh MeisterAI.sh Formula/ Casks/ release.sh scripts/ lib/ tests/ docs/ config.fast.example AGENTS.md README.md 2>/dev/null || true
git add -A -- app/ ":(glob)*.sh"
# tools/ LICENSE may not always change
git add tools/ LICENSE .gitignore 2>/dev/null || true
if git diff --cached --quiet; then
    echo "No staged changes"
else
    git commit -m "meister v${VERSION}: MeisterAI twin + release tooling"
fi
# Push regardless — there may be committed-but-unpushed commits.
# Bug history: skipping this push when nothing was staged caused
# `gh release create` to tag GitHub's HEAD (which lagged behind local),
# producing a v-tag pointing at the pre-fix commit.
git push origin main
echo "Pushed (HEAD = $(git rev-parse --short HEAD))"

# 2. Create GitHub Release pinned to local HEAD's exact SHA
echo ""
echo "--- Step 2: GitHub Release v${VERSION} ---"
TARGET_SHA=$(git rev-parse HEAD)
RELEASE_STATE=$(release_existing_state "$REPO" "$VERSION" "$TARGET_SHA")
if [ "$RELEASE_STATE" = conflict ]; then
    echo "ERROR: Release v${VERSION} already exists on another commit. Bump the version; published tags are immutable." >&2
    exit 1
fi
if [ "$RELEASE_STATE" = resume ]; then
    echo "Release v${VERSION} already exists at $TARGET_SHA — resuming with the remaining steps."
else
NOTES_FILE=$(mktemp)
if [ -f "$SCRIPT_DIR/docs/releases/${VERSION}.md" ]; then
    cat "$SCRIPT_DIR/docs/releases/${VERSION}.md" > "$NOTES_FILE"
else
    cat > "$NOTES_FILE" <<EOF
macOS Maintenance & Self-Healing Script v${VERSION}

## Install / upgrade
brew tap maf4711/meister
brew update && brew upgrade meister
# First installation: brew install meister
EOF
fi
gh release create "v${VERSION}" -R "$REPO" \
    --target "$TARGET_SHA" \
    --title "meister v${VERSION}" \
    --notes-file "$NOTES_FILE"
rm -f "$NOTES_FILE"
echo "Release created at $TARGET_SHA: https://github.com/$REPO/releases/tag/v${VERSION}"
fi

APP_RELEASED_VERSION=""
if [ -f "$APP_ZIP" ]; then
    echo ""
    echo "--- Step 2b: Upload MeisterAI.app zip ---"
    release_verify_app_zip "$APP_ZIP" "$VERSION" || exit 1
    gh release upload "v${VERSION}" "$APP_ZIP" -R "$REPO" --clobber
    CASK_SHA=$(shasum -a 256 "$APP_ZIP" | awk '{print $1}')
    sed -i '' "s|version \".*\"|version \"${VERSION}\"|" "$CASK"
    sed -i '' "s|sha256 \".*\"|sha256 \"${CASK_SHA}\"|" "$CASK"
    sed -i '' 's/MeisterSiri-macOS.zip/MeisterAI-macOS.zip/; s/app "MeisterSiri.app", target: "MeisterAI.app"/app "MeisterAI.app"/' "$CASK"
    git add "$CASK"
    if git diff --cached --quiet; then
        echo "Cask already current"
    else
        git commit -m "cask: MeisterAI.app v${VERSION}"
        git push origin main
    fi
    CASK_VERSION=$(awk -F'"' '/^[[:space:]]*version / {print $2; exit}' "$CASK")
    [ "$CASK_VERSION" = "$VERSION" ] || { echo "ERROR: Published app cask version does not match v$VERSION" >&2; exit 1; }
    APP_RELEASED_VERSION="$CASK_VERSION"
fi

# 3. Get SHA256 of tarball
echo ""
echo "--- Step 3: Calculate SHA256 ---"
TARBALL_URLS=()
while IFS= read -r url; do TARBALL_URLS+=("$url"); done < <(release_tarball_urls "$REPO" "$VERSION")
TARBALL_URL="${TARBALL_URLS[0]}"
TMPTAR=$(mktemp)
# GitHub can lag after release create, and the archive URL can 504 while codeload works.
release_fetch_tarball "$TMPTAR" "${TARBALL_URLS[@]}" || { echo "ERROR: Release tarball download failed; rerun ./release.sh to resume" >&2; exit 1; }
SHA=$(shasum -a 256 "$TMPTAR" | awk '{print $1}')
echo "URL:     $TARBALL_URL"
echo "SHA256:  $SHA"

# 4. Update Formula
echo ""
echo "--- Step 4: Update Formula ---"
sed -i '' "s|version \".*\"|version \"${VERSION}\"|" "$FORMULA"
sed -i '' "s|v[0-9][0-9]*\.[0-9][0-9]*\.tar\.gz|v${VERSION}.tar.gz|" "$FORMULA"
sed -i '' "s|sha256 \".*\"|sha256 \"${SHA}\"|" "$FORMULA"
echo "Formula updated"

# 5. Commit and push Formula update
echo ""
echo "--- Step 5: Push Formula update ---"
git add Formula/meister.rb
if git diff --cached --quiet; then
    echo "No changes"
else
    git commit -m "formula: update SHA256 for v${VERSION}"
    git push origin main
    echo "Pushed"
fi

# 6. ALWAYS install locally after release (mandatory)
echo ""
echo "--- Step 6: Local install (MERKREGEL: immer nach Release) ---"
release_seed_brew_cache "$TMPTAR" "$TARBALL_URL" "$VERSION" || echo "WARN: could not seed the Homebrew cache" >&2
rm -f "$TMPTAR"
INSTALL_ARGS=("$VERSION")
if [ -n "$APP_RELEASED_VERSION" ]; then
    INSTALL_ARGS+=(--app-version "$APP_RELEASED_VERSION")
fi
bash "$SCRIPT_DIR/scripts/install-release.sh" "${INSTALL_ARGS[@]}"

echo ""
echo "=== Release v${VERSION} done! ==="
echo ""
echo "Others install with:"
echo "  brew tap maf4711/meister"
echo "  brew install meister"
echo ""
echo "You already have the new version locally (Step 6)."
