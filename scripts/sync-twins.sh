#!/usr/bin/env bash
# sync-twins.sh — Keep meister.sh feature-identical to meisterSiri.sh
#
# MERKREGEL: meisterSiri.sh ist die Feature-Quelle. Nach JEDER Feature-Änderung:
#   ./scripts/sync-twins.sh
# Dann version bump + ./release.sh
#
# Diff outside branding is a BUG. This script regenerates meister.sh completely.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/meisterSiri.sh"
DST="$ROOT/meister.sh"

if [ ! -f "$SRC" ]; then
  echo "ERROR: $SRC missing" >&2
  exit 1
fi

python3 - "$SRC" "$DST" <<'PY'
import re
import sys
from pathlib import Path

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
t = src.read_text()

# 1) Header / file identity
t = t.replace("# meisterSiri.sh\n", "# meister.sh\n", 1)
t = t.replace("# Usage: ./meisterSiri.sh [flags]", "# Usage: ./meister.sh [flags]", 1)

t = t.replace(
    "# Twin of meister.sh: same maintenance modules, branded as MeisterSiri.\n"
    "# AI backend = on-device Apple FoundationModels (Apple Intelligence).\n"
    "# Shares config/state with meister: ~/.meister/\n",
    "# Twin of meisterSiri.sh: same features (autofix, profiles, dry-run honesty).\n"
    "# AI backend = on-device Apple FoundationModels (Apple Intelligence).\n"
    "# Shares config/state: ~/.meister/\n"
    "# KEEP IN SYNC: edit meisterSiri.sh then run scripts/sync-twins.sh\n",
    1,
)

# Also handle already-siri twin note variants
if "KEEP IN SYNC" not in t[:2500]:
    # after Version block insert sync note once
    t = t.replace(
        "# Date:",
        "# KEEP IN SYNC: edit meisterSiri.sh then run scripts/sync-twins.sh\n# Date:",
        1,
    )

# 2) Branding (longer tokens first)
t = t.replace("MeisterSiri", "Meister")
t = t.replace("meisterSiri", "meister")

# 3) --version
t = re.sub(
    r'--version\) echo "meister v\$\{MEISTER_VERSION\}[^"]*"; exit 0 ;;',
    '--version) echo "meister v${MEISTER_VERSION}"; exit 0 ;;',
    t,
    count=1,
)

# 4) Help title soften
t = t.replace(
    "Meister - macOS Maintenance, Self-Healing & Dotfiles Sync (Apple Intelligence)",
    "Meister - macOS Maintenance, Self-Healing & Dotfiles Sync",
)

dst.write_text(t)
print(f"OK: wrote {dst.name} from {src.name} ({len(t)} bytes)")
PY

bash -n "$DST"
echo "=== feature check ==="
for pat in autofix_known_issues apply_run_profile ensure_sudo AUTOFIX_OLD_BOTTLES REPORT_WOULD_FIX; do
  if grep -q "$pat" "$DST"; then echo "  OK $pat"; else echo "  MISSING $pat"; exit 1; fi
done
if grep -E 'meisterSiri|MeisterSiri' "$DST" >/dev/null; then
  echo "WARN residual branding:"
  grep -nE 'meisterSiri|MeisterSiri' "$DST" | head -10
  exit 1
fi
echo "OK: branding clean"
"$DST" --version
echo "DONE: twins synced (meisterSiri → meister)"
