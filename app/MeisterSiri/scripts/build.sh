#!/usr/bin/env bash
# Build MeisterSiri.app (OnyX-style GUI) and optionally install to /Applications
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

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

if [ "${1:-}" = "--install" ]; then
  echo "==> Installing to /Applications"
  rm -rf /Applications/MeisterSiri.app
  cp -R "$OUT/MeisterSiri.app" /Applications/
  echo "    open -a MeisterSiri"
fi

echo "OK"
