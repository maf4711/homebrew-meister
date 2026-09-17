#!/usr/bin/env bash
# Build MeisterSiri.app (OnyX-style GUI) and optionally install to /Applications
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Prefer full Xcode; fall back to Xcode-beta (common on macOS betas).
# Without this, xcodebuild fails when only Command Line Tools are selected.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  elif [ -d "/Applications/Xcode-beta.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
  fi
fi
if [ -n "${DEVELOPER_DIR:-}" ]; then
  echo "==> DEVELOPER_DIR=$DEVELOPER_DIR"
else
  echo "ERROR: No Xcode found. Install Xcode (or Xcode-beta) from the App Store / developer.apple.com."
  echo "       Command Line Tools alone are not enough for this app build."
  exit 1
fi

echo "==> xcodegen"
xcodegen generate

echo "==> xcodebuild (Release)"
xcodebuild \
  -project MeisterSiri.xcodeproj \
  -scheme MeisterSiri \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  build

APP=$(find build/DerivedData/Build/Products/Release -name "MeisterSiri.app" -maxdepth 2 | head -1)
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "ERROR: MeisterSiri.app not found"
  exit 1
fi

echo "==> Built: $APP"
OUT="$ROOT/dist"
mkdir -p "$OUT"
rm -rf "$OUT/MeisterSiri.app"
cp -R "$APP" "$OUT/MeisterSiri.app"

# Ad-hoc sign for local Gatekeeper friendliness
codesign --force --deep --sign - "$OUT/MeisterSiri.app" 2>/dev/null || true

echo "==> dist: $OUT/MeisterSiri.app"

cask_release=false
do_install=false
for arg in "$@"; do
  case "$arg" in
    --install) do_install=true ;;
    --cask-release) cask_release=true ;;
  esac
done

if $cask_release; then
  # Hash, not the common name: two Developer ID certs share the same CN.
  SIGN_ID="${SIGN_ID:-B6EAF16C978F2AC019070F04C3B0C6052ED0342E}"
  ASC_KEY_ID="${ASC_KEY_ID:-5BXD2V69GS}"
  ASC_ISSUER_ID="${ASC_ISSUER_ID:-18daeaec-9343-4c57-9b01-481a7da981c6}"
  ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
  [ -f "$ASC_KEY_PATH" ] || { echo "ERROR: missing $ASC_KEY_PATH"; exit 1; }
  echo "==> Developer ID sign ($SIGN_ID)"
  codesign --force --deep --options runtime --timestamp \
    --sign "$SIGN_ID" "$OUT/MeisterSiri.app"
  codesign --verify --deep --strict "$OUT/MeisterSiri.app"
  ZIP="$OUT/MeisterSiri-macOS.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$OUT/MeisterSiri.app" "$ZIP"
  echo "==> notarytool submit"
  xcrun notarytool submit "$ZIP" \
    --key "$ASC_KEY_PATH" \
    --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" \
    --wait
  echo "==> staple"
  xcrun stapler staple "$OUT/MeisterSiri.app"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$OUT/MeisterSiri.app" "$ZIP"
  echo "==> zip: $ZIP"
  shasum -a 256 "$ZIP"
fi

if $do_install; then
  echo "==> Installing to /Applications"
  rm -rf /Applications/MeisterSiri.app
  cp -R "$OUT/MeisterSiri.app" /Applications/
  xattr -dr com.apple.quarantine /Applications/MeisterSiri.app 2>/dev/null || true
  echo "    open -a MeisterSiri"
fi

echo "OK"
