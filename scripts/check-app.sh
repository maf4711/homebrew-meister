#!/usr/bin/env bash
# Build and test the native macOS application; never starts an iOS Simulator.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/app/MeisterAI"

if [ "$(uname -s)" != Darwin ]; then
  echo "ERROR: the app gate requires macOS and Xcode." >&2
  exit 1
fi
for tool in xcodegen xcodebuild; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool is required." >&2; exit 1; }
done

xcodegen generate
xcodebuild \
  -project MeisterAI.xcodeproj \
  -scheme MeisterAI \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/CheckDerivedData \
  -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  test

xcodebuild \
  -project MeisterAI.xcodeproj \
  -scheme MeisterAI \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/CheckDerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  build
