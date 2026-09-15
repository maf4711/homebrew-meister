#!/usr/bin/env bats
# Apple Foundation Models helper contract (macOS 27)

ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SIRI="$ROOT/meisterSiri.sh"

extract_helper() {
  awk '
    $0 == "import FoundationModels" { p=1 }
    p { print }
    p && $0 == "SWIFT_EOF" { exit }
  ' "$SIRI" | sed '/^SWIFT_EOF$/d'
}

xcode27_swiftc() {
  if [ -d /Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk ]; then
    env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc "$@"
    return
  fi
  xcrun swiftc "$@"
}

@test "helper source uses PrivateCloudComputeLanguageModel" {
  extract_helper | grep -q PrivateCloudComputeLanguageModel
}

@test "helper source uses Generable HealFix" {
  extract_helper | grep -q '@Generable'
  extract_helper | grep -q 'struct HealFix'
}

@test "helper source counts tokens and sets reasoning" {
  extract_helper | grep -q tokenCount
  extract_helper | grep -q reasoningLevel
}

@test "helper source takes --purpose and --model" {
  extract_helper | grep -q -- '--purpose'
  extract_helper | grep -q -- '--model'
}

@test "helper source uses allowlisted ProposeFixTool" {
  extract_helper | grep -q 'struct ProposeFixTool'
  extract_helper | grep -q 'propose_fix'
  extract_helper | grep -q 'toolCallingMode: heal ? .allowed'
  extract_helper | grep -q 'ProposeFixTool()'
}

@test "ensure_fm_helper compiles with parse-as-library and Xcode 27 SDK" {
  grep -q 'parse-as-library' "$SIRI"
  grep -q 'MacOSX27' "$SIRI"
}

@test "fm swiftc prefers selected SDK 27 over Xcode-beta" {
  awk '/^_fm_swiftc\(\)/,/^}/' "$SIRI" > "${TMPDIR:-/tmp}/fm-swiftc-fn.$$"
  sdk=$(grep -n 'show-sdk-version' "${TMPDIR:-/tmp}/fm-swiftc-fn.$$" | head -1 | cut -d: -f1)
  beta=$(grep -n 'Xcode-beta.app' "${TMPDIR:-/tmp}/fm-swiftc-fn.$$" | head -1 | cut -d: -f1)
  [ -n "$sdk" ]
  [ -n "$beta" ]
  [ "$sdk" -lt "$beta" ]
  rm -f "${TMPDIR:-/tmp}/fm-swiftc-fn.$$"
}

@test "helper compiles and --check --model system succeeds" {
  src="${TMPDIR:-/tmp}/meister-fm-test-$$.swift"
  bin="${TMPDIR:-/tmp}/meister-fm-test-$$"
  extract_helper > "$src"
  run xcode27_swiftc -parse-as-library -O "$src" -o "$bin"
  [ "$status" -eq 0 ]
  [ -x "$bin" ]
  run "$bin" --check --model system
  [ "$status" -eq 0 ]
  rm -f "$src" "$bin"
}

@test "Ollama twin does not embed the Apple helper" {
  ! grep -q 'PrivateCloudComputeLanguageModel()' "$ROOT/meister.sh"
}

@test "helper --check --model pcc succeeds on this Mac" {
  src="${TMPDIR:-/tmp}/meister-fm-pcc-$$.swift"
  bin="${TMPDIR:-/tmp}/meister-fm-pcc-$$"
  extract_helper > "$src"
  xcode27_swiftc -parse-as-library -O "$src" -o "$bin"
  run "$bin" --check --model pcc
  [ "$status" -eq 0 ]
  rm -f "$src" "$bin"
}
