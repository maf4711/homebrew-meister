# lib/modules — extraction track

**Status (v6.13):** Core pure logic lives in `lib/core/`. Full module bodies
still live in `meisterSiri.sh` (feature source of truth for the twin sync).

## Contract

| Layer | Path | Rule |
|-------|------|------|
| Pure guards / tallies / profiles | `lib/core/*.sh` | No I/O beyond args; bats-tested |
| Module implementations | `meisterSiri.sh` → future `lib/modules/<name>.sh` | May use log/report globals |
| Feature source | `meisterSiri.sh` | Twins via `scripts/sync-twins.sh` |

## Extraction order (next tracks)

1. `module_broken_symlinks` / `module_dsstore_cleanup` (already tally-based)
2. `module_battery` / `module_ssh_audit` (read-only)
3. `module_homebrew` (largest, most timeouts)

Each extracted file must:
- define one `module_*` function
- be sourced after logging helpers
- keep `return 0` on permission noise
