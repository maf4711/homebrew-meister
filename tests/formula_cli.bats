#!/usr/bin/env bats
# Formula must ship MeisterAI as the Apple CLI and must not install meisterSiri.

FORMULA="${BATS_TEST_DIRNAME}/../Formula/meister.rb"

@test "formula installs the Apple CLI as MeisterAI" {
  grep -q 'bin.install apple_source => "MeisterAI"' "$FORMULA"
}

@test "formula does not install a meisterSiri command alias" {
  if grep -n 'install_symlink.*"meisterSiri"' "$FORMULA"; then
    echo "formula still ships a meisterSiri CLI alias" >&2
    return 1
  fi
  if grep -n 'bin.install .*"meisterSiri"' "$FORMULA"; then
    echo "formula still installs a meisterSiri binary" >&2
    return 1
  fi
}

@test "formula test probes MeisterAI not meisterSiri" {
  grep -q 'bin}/MeisterAI --version' "$FORMULA"
  if grep -n 'bin}/meisterSiri' "$FORMULA"; then
    echo "formula test still probes meisterSiri" >&2
    return 1
  fi
}
