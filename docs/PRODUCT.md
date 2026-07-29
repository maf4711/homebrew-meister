# Meister product surface (v6.13+)

## Brand

| Binary | AI backend | Role |
|--------|------------|------|
| **`meisterSiri`** | Apple Intelligence (on-device) | **Primary** daily CLI + LaunchAgents |
| **`meister`** | Ollama | Twin for offline / Ollama preference |

Both share `~/.meister/` (config, logs, last.json, undo journal).

Marketing name: **Meister**. Implementation twins differ only in AI backend.

## GUI (one surface)

| Surface | Status | Notes |
|---------|--------|-------|
| **`app/MeisterSiri/`** (this repo) | **Canonical GUI** | SwiftUI over `meisterSiri` CLI |
| `~/Developer/meister-app` | **Legacy / AddressBook track** | Older multi-platform shell-out; not the release path |
| Homebrew Cask `meister-mac` | Points at legacy meister-app zip | Prefer building MeisterSiri.app from this repo until a new cask ships |

Do not invest in feature-parity for two GUIs.

## Contract with heald

| Tool | Responsibility |
|------|----------------|
| **heald** | Continuous observe: metrics, daemons, live remediation |
| **Meister** | Batch maintain: brew, cleanup, scheduled deep, git hygiene |

Handshake file: `~/.meister/last.json` (`schema: meister.last/v1`).

heald may:
- read `last.json` for last score / err count
- trigger `meisterSiri --quick -q` on disk pressure or stale score

Meister does **not** replace heald’s always-on daemon.

## Trust defaults (v6.12+)

- `AI_HEAL_EXECUTE=false` — suggest-only
- Verify-after-heal before FIX
- Cleanup tallies (found/removed/skipped_perm)

## License

CLI: GPL-3.0-only. Keep proprietary design systems out of this repo; GUI uses local assets.
