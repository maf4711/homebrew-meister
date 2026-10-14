#!/bin/bash
# GUI-Preview-Capabilities: profiles ai
# GUI-Execution-Contract: 1
# Refresh on expiry, share successful metadata with this runtime invocation.
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
state_dir="${MEISTER_DIR:-$HOME/.meister}"
[[ "$state_dir" == /* && "$state_dir" != / && "$state_dir" != */../* && "$state_dir" != */.. ]] || fail 'Prüfen des Zustandsverzeichnisses'
max_age="${BREW_UPDATE_MAX_AGE_SEC:-43200}"
profile="${RUN_PROFILE:-auto}"
# Parse just the relevant values; configuration is never shell code.
if [[ -f "$state_dir/config" ]]; then
  while IFS='=' read -r key value; do
    key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"; value="${value%"${value##*[![:space:]]}"}"
    case "$value" in
      \"*\") value="${value#\"}"; value="${value%\"}" ;;
      \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    case "$key" in
      BREW_UPDATE_MAX_AGE_SEC) [[ "$value" =~ ^[0-9]{1,10}$ ]] && max_age="$value" ;;
      RUN_PROFILE) [[ "$value" =~ ^(auto|quick|deep|all)$ ]] && profile="$value" ;;
    esac
  done < "$state_dir/config"
fi
force_all=false
for argument in "$@"; do
  case "$argument" in
    --) break ;;
    --deep) profile=deep ;;
    --auto|--quick) profile=auto ;;
    -[^-]*) if [[ "${argument:1}" == *a* ]]; then force_all=true; fi ;;
    -*) : ;;
    *) break ;;
  esac
done
$force_all && profile=all
[[ "$max_age" =~ ^[0-9]{1,10}$ ]] || fail 'Prüfen des Update-Intervalls'
max_age=$((10#$max_age))
[[ "$profile" != deep && "$profile" != all ]] || max_age=0
prefix="@HOMEBREW_PREFIX@/opt/meister"
stamp="$state_dir/brew_launcher_last_update"
now=$(date +%s)
last_ts=""
if [[ -f "$stamp" ]]; then IFS= read -r last_ts < "$stamp" || last_ts=""; fi
fresh=false
if [[ "$last_ts" =~ ^[0-9]{1,10}$ ]]; then
  last_ts=$((10#$last_ts))
  age=$((now - last_ts))
  if [[ "$last_ts" -gt 0 && -x "$prefix/libexec/$executable" && "$age" -ge 0 && "$age" -lt "$max_age" ]]; then fresh=true; fi
fi
export HOMEBREW_NO_AUTO_UPDATE=1
if $fresh; then
  printf 'Meister: Homebrew-Check aus Cache (%ss alt).\n' "$age" >&2
  export MEISTER_BREW_UPDATE_FRESH=false
else
  printf 'Meister: Prüfe die aktuelle Homebrew-Version …\n' >&2
  "$brew" update >&2 || fail 'Homebrew-Update'
  if [[ -x "$prefix/libexec/$executable" ]] || "$brew" list --versions "$formula" >/dev/null 2>&1; then
    "$brew" upgrade --formula "$formula" >&2 || fail 'Meister-Upgrade'
  else
    "$brew" install --formula "$formula" >&2 || fail 'Meister-Installation'
  fi
  [[ -x "$prefix/libexec/$executable" ]] || prefix=$("$brew" --prefix "$formula") || fail 'Ermitteln der Installation'
  [[ -x "$prefix/libexec/$executable" ]] || fail 'Prüfen der ausführbaren Datei'
  last_ts=$(date +%s)
  # Atomic success-only stamp. A cache write failure must not block the runtime.
  if (umask 077; mkdir -p "$state_dir" && printf '%s\n' "$last_ts" > "$stamp.$$" && mv -f "$stamp.$$" "$stamp") 2>/dev/null; then :; fi
  export MEISTER_BREW_UPDATE_FRESH=true
fi
export MEISTER_BREW_UPDATE_AT="$last_ts" MEISTER_BREW_UPDATE_PID="$$"
exec "$prefix/libexec/$executable" "$@"
