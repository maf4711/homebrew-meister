# homebrew-meister — Agent notes

## MERKREGEL: Nach jedem Release IMMER lokal installieren

Wenn du einen Release machst (`./release.sh` oder manuell tag + formula):

1. GitHub Release + Formula-SHA pushen
2. **Sofort lokal installieren** — nicht nur pushen und aufhören:
   ```bash
   brew update && brew reinstall maf4711/meister/meister
   meister --version
   meisterSiri --version   # ab v6.1
   ```

`./release.sh` macht das automatisch in **Step 6**. Nie Step 6 skippen.

Hintergrund: Repo (`~/Developer/homebrew-meister`) und Homebrew-Cellar
(`/opt/homebrew/Cellar/meister`) driften sonst. Keine Repo-Symlinks auf PATH
statt brew — brew muss Owner der Binaries sein.

## Binaries

| Command | File | Role |
|---------|------|------|
| `meister` | `meister.sh` | Main CLI (leave as-is unless intentional) |
| `meisterSiri` | `meisterSiri.sh` | Same modules, MeisterSiri branding, Apple Intelligence |

Both share `~/.meister/` config and state.

## v6.2 MeisterSiri commands

| Command | Purpose |
|---------|---------|
| `meisterSiri today` | Morning briefing |
| `meisterSiri doctor` | Read-only checklist |
| `meisterSiri suggest <x>` | AI fix idea, never executes |
| `meisterSiri privacy` | Privacy / persistence audit |
| `meisterSiri selftest` | Smoke-test CLI |
| `meisterSiri -n` | Dry-run: shows WOULD-FIX + "Would free", never FIXED/Freed |

Dry-run honesty is implemented in `report_add` / report footer — do not reintroduce `report_add FIX` that bypasses it.

## v6.6 Speed profiles

| Command | Intent | Typical time |
|---------|--------|--------------|
| `meisterSiri` / `--auto` | Daily-fast defaults | 1–4 min |
| `meisterSiri --quick` | Minimal (healer+brew+cleanup+security) | ~1–2 min |
| `meisterSiri --deep` | Weekly full (iCloud, dev, docs, audits) | 5–15 min |
| `meisterSiri -a` | Force all modules | longest |

Brew: `~/.meister/brew_last_update` — delete to force `brew update`.
Config template: `config.fast.example` → merge into `~/.meister/config`.

## MERKREGEL: meister + meisterSiri parallel halten

**Feature-Quelle:** `meisterSiri.sh`  
**Zwilling:** `meister.sh` (nur Branding anders)

Nach **jeder** Feature-Änderung an der CLI:

```bash
./scripts/sync-twins.sh   # regeneriert meister.sh aus meisterSiri.sh
./release.sh              # tag + formula + local brew install
```

`release.sh` ruft `sync-twins.sh` automatisch auf.

Niemals Features nur in `meister.sh` bauen — die gehen beim nächsten Sync verloren.
Beide teilen `~/.meister/` und dasselbe Autofix/Profile/Sudo-Verhalten.

### Autofix (v6.7+)

```bash
meisterSiri ai            # Autofix + AI-Rest-Zusammenfassung
meisterSiri autofix       # nur deterministische Fixes
meister ai / meister autofix   # gleich (nach Sync)
```

Fixes: alte brew bottles, orphan LaunchDaemons, git push (clean), Firewall on,
Time Machine Settings öffnen, _Inbox Archive (>N Tage).
