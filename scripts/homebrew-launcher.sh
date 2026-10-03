#!/bin/bash
# GUI-Preview-Capabilities: profiles ai
# GUI-Execution-Contract: 1
# Refresh Homebrew before every invocation, then run the current keg.
set -euo pipefail
brew="@HOMEBREW_PREFIX@/bin/brew"
formula=maf4711/meister/meister
case "${0##*/}" in
  meister) executable=meister ;;
  meisterAI|MeisterAI) executable=MeisterAI ;;
  *) printf 'Unbekannter Meister-Starter: %s\n' "$0" >&2; exit 1 ;;
esac
fail() {
  printf 'Meister: %s fehlgeschlagen. Programmstart abgebrochen.\n' "$1" >&2
  exit 1
}
# Keep previous kegs available to already running Meister processes.
export HOMEBREW_NO_INSTALL_CLEANUP=1
printf 'Meister: Prüfe die aktuelle Homebrew-Version …\n' >&2
"$brew" update >&2 || fail 'Homebrew-Update'
export HOMEBREW_NO_AUTO_UPDATE=1
if "$brew" list --versions "$formula" >/dev/null 2>&1; then
  "$brew" upgrade --formula "$formula" >&2 || fail 'Meister-Upgrade'
else
  "$brew" install --formula "$formula" >&2 || fail 'Meister-Installation'
fi
prefix=$("$brew" --prefix "$formula") || fail 'Ermitteln der Installation'
[[ -x "$prefix/libexec/$executable" ]] || fail 'Prüfen der ausführbaren Datei'
exec "$prefix/libexec/$executable" "$@"
