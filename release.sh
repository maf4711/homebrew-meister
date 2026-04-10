#!/bin/bash
# release.sh - Create a new Homebrew release (single-repo)
#
# 1. Reads version from meister.sh
# 2. Creates GitHub Release with tag
# 3. Updates SHA256 in Formula
# 4. Pushes everything
#
# Usage: ./release.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/meister.sh"
FORMULA="$SCRIPT_DIR/Formula/meister.rb"
REPO="maf4711/meister"

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
git add meister.sh tools/ Formula/ LICENSE .gitignore
if git diff --cached --quiet; then
    echo "No changes"
else
    git commit -m "meister v${VERSION}"
    git push origin main
    echo "Pushed"
fi

# 2. Create GitHub Release
echo ""
echo "--- Step 2: GitHub Release v${VERSION} ---"
if gh release view "v${VERSION}" -R "$REPO" &>/dev/null; then
    echo "Release v${VERSION} already exists - deleting and recreating"
    gh release delete "v${VERSION}" -R "$REPO" --yes
    git tag -d "v${VERSION}" 2>/dev/null || true
    git push origin ":refs/tags/v${VERSION}" 2>/dev/null || true
fi
gh release create "v${VERSION}" -R "$REPO" \
    --title "meister v${VERSION}" \
    --notes "macOS Maintenance & Self-Healing Script v${VERSION}"
echo "Release created: https://github.com/$REPO/releases/tag/v${VERSION}"

# 3. Get SHA256 of tarball
echo ""
echo "--- Step 3: Calculate SHA256 ---"
TARBALL_URL="https://github.com/$REPO/archive/refs/tags/v${VERSION}.tar.gz"
TMPTAR=$(mktemp)
curl -sL "$TARBALL_URL" -o "$TMPTAR"
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

# 6. Invalidate local brew cache
CACHE_FILE=$(brew --cache meister 2>/dev/null || true)
[ -f "$CACHE_FILE" ] && rm -f "$CACHE_FILE"

echo ""
echo "=== Release v${VERSION} done! ==="
echo ""
echo "Others install with:"
echo "  brew tap maf4711/meister https://github.com/maf4711/meister"
echo "  brew install meister"
echo ""
echo "You upgrade locally with:"
echo "  brew update && brew upgrade meister"
