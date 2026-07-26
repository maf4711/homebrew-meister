#!/bin/bash
# release.sh - Create a new Homebrew release (single-repo)
#
# 1. Reads version from meister.sh
# 2. Creates GitHub Release with tag
# 3. Updates SHA256 in Formula
# 4. Pushes everything
# 5. ALWAYS reinstalls locally via brew (mandatory — do not skip)
#
# Usage: ./release.sh
#
# MERKREGEL: Nach jedem Release IMMER lokal installieren
#   (brew update && brew reinstall meister). Sonst laufen Repo und
#   /opt/homebrew/bin auseinander. release.sh erledigt das in Step 6.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/meister.sh"
FORMULA="$SCRIPT_DIR/Formula/meister.rb"
REPO="maf4711/homebrew-meister"

# Extract version from script
VERSION=$(grep -m1 '^# Version:' "$SOURCE" | awk '{print $3}')
if [[ -z "$VERSION" ]]; then
    echo "ERROR: Version not found in $SOURCE"
    exit 1
fi

echo "=== meister Release v${VERSION} ==="
echo ""

# 1. Commit and push all changes
echo "--- Step 1: Update repo ---"
cd "$SCRIPT_DIR"
git add meister.sh meisterSiri.sh tools/ Formula/ LICENSE .gitignore release.sh 2>/dev/null || true
git add meister.sh meisterSiri.sh Formula/ release.sh
# tools/ LICENSE may not always change
git add tools/ LICENSE .gitignore 2>/dev/null || true
if git diff --cached --quiet; then
    echo "No staged changes"
else
    git commit -m "meister v${VERSION}: meisterSiri twin + release tooling"
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
if gh release view "v${VERSION}" -R "$REPO" &>/dev/null; then
    echo "Release v${VERSION} already exists - deleting and recreating"
    gh release delete "v${VERSION}" -R "$REPO" --yes --cleanup-tag
    git tag -d "v${VERSION}" 2>/dev/null || true
fi
gh release create "v${VERSION}" -R "$REPO" \
    --target "$TARGET_SHA" \
    --title "meister v${VERSION}" \
    --notes "$(cat <<NOTES
macOS Maintenance & Self-Healing Script v${VERSION}

## What's new
- **meisterSiri**: branded twin CLI (Apple Intelligence on-device), same modules as \`meister\`
- Shared config/state: \`~/.meister/\`
- Installs both binaries: \`meister\` + \`meisterSiri\`

## Install / upgrade
\`\`\`
brew tap maf4711/meister
brew update && brew reinstall meister
\`\`\`
NOTES
)"
echo "Release created at $TARGET_SHA: https://github.com/$REPO/releases/tag/v${VERSION}"

# 3. Get SHA256 of tarball
echo ""
echo "--- Step 3: Calculate SHA256 ---"
TARBALL_URL="https://github.com/$REPO/archive/refs/tags/v${VERSION}.tar.gz"
TMPTAR=$(mktemp)
# GitHub can lag briefly after release create
for i in 1 2 3 4 5; do
    if curl -fsSL "$TARBALL_URL" -o "$TMPTAR"; then
        break
    fi
    echo "Tarball not ready yet (try $i)..."
    sleep 2
done
SHA=$(shasum -a 256 "$TMPTAR" | awk '{print $1}')
rm -f "$TMPTAR"
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
# Drop any repo symlink so brew owns the binaries
if [[ -L /opt/homebrew/bin/meisterSiri ]]; then
    rm -f /opt/homebrew/bin/meisterSiri
fi
CACHE_FILE=$(brew --cache meister 2>/dev/null || true)
[ -n "${CACHE_FILE:-}" ] && [ -f "$CACHE_FILE" ] && rm -f "$CACHE_FILE"
# Refresh tap from GitHub (formula lives in this repo / tap)
brew update
# Reinstall from the tap so both meister + meisterSiri land in Cellar
brew reinstall maf4711/meister/meister || brew reinstall meister
echo ""
echo "Installed binaries:"
which meister meisterSiri
meister --version
meisterSiri --version

echo ""
echo "=== Release v${VERSION} done! ==="
echo ""
echo "Others install with:"
echo "  brew tap maf4711/meister"
echo "  brew install meister"
echo ""
echo "You already have the new version locally (Step 6)."
