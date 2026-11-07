# Meister product surface (v6.13+)

## Brand

| Binary | AI backend | Role |
|--------|------------|------|
| **`MeisterAI`** | Apple Intelligence (on-device) | **Primary** daily CLI + LaunchAgents |
| **`meister`** | Ollama | Twin for offline / Ollama preference |

Both share `~/.meister/` (config, logs, last.json, undo journal).

Marketing name: **Meister**. Implementation twins differ only in AI backend.

## GUI (one surface)

| Surface | Status | Notes |
|---------|--------|-------|
| **`app/MeisterAI/`** (this repo) | **Canonical GUI** | SwiftUI over `MeisterAI` CLI |
| `~/Developer/meister-app` | **Legacy / AddressBook track** | Older multi-platform shell-out; not the release path |
| Homebrew Cask `meister-mac` | **MeisterAI.app** (notarized GitHub zip) | `brew install --cask meister-mac` |

Do not invest in feature-parity for two GUIs.

## Contract with heald

| Tool | Responsibility |
|------|----------------|
| **heald** | Continuous observe: metrics, daemons, live remediation |
| **Meister** | Batch maintain: brew, cleanup, scheduled deep, git hygiene |

Handshake file: `~/.meister/last.json` (`schema: meister.last/v1`).

Fields for heald (`MeisterBridge` in heald ≥2.1):
- `score`, `err`, `warn`, `ts`, `twin` (`meister` \| `MeisterAI`), `preferred_twin`
- `~/.meister/preferred_twin` — set by `MeisterAI twins-bench`

heald may:
- read `last.json` every ~15 min
- trigger preferred twin `--quick -q` if missing / stale (>24h) / err with age >1h
- write `~/.heald/data/meister_bridge.json` for `heald doctor`

Twin benchmark:
```bash
MeisterAI twins-bench           # full (incl. dry-run --quick)
MeisterAI twins-bench --quick   # version/doctor/AI/lib only
MeisterAI twins-bench --json
```

Meister does **not** replace heald’s always-on daemon.

## Trust defaults (v6.12+)

- `AI_HEAL_EXECUTE=false` — suggest-only
- Verify-after-heal before FIX
- Cleanup tallies (found/removed/skipped_perm)

## License

CLI: GPL-3.0-only. Keep proprietary design systems out of this repo; GUI uses local assets.
