# homebrew-meister — Agent notes

## MERKREGEL: Nach jedem Release IMMER lokal installieren

**User (2026-07-29): „installiere immer danach direkt auf dem mac“.**

Wenn du einen Release machst (`./release.sh` oder manuell tag + formula):

1. GitHub Release + Formula-SHA pushen
2. **Sofort lokal installieren** — nicht nur pushen und aufhören:
   ```bash
   brew update && brew reinstall maf4711/meister/meister
   meister --version
   meisterSiri --version
   # Symlink-Pfad (nicht nur Cellar):
   /opt/homebrew/bin/meisterSiri --version
   ```
3. Release erst melden, wenn die installierte Version mit dem Tag übereinstimmt.

`./release.sh` macht das automatisch in **Step 6**. Nie Step 6 skippen.
Auch bei manuellem Release: denselben brew-reinstall selbst ausführen.

Hintergrund: Repo (`~/Developer/homebrew-meister`) und Homebrew-Cellar
(`/opt/homebrew/Cellar/meister`) driften sonst. Keine Repo-Symlinks auf PATH
statt brew — brew muss Owner der Binaries sein.

Cross-session: `~/.grok/rules/meister-always-install-local.md` +
`~/.grok/memories/homebrew-meister-release.md`

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

## v6.17 Touch ID for sudo (always-on)

Default: `TOUCHID_SUDO=true` — `ensure_sudo` schreibt `pam_tid` nach `/etc/pam.d/sudo_local`
wenn fehlt. Einmal Passwort, danach Fingerprint. Opt-out: `TOUCHID_SUDO=false` in
`~/.meister/config` oder `meisterSiri touchid --off`.

```bash
meisterSiri touchid          # force enable / status message
meisterSiri touchid status   # enabled? sensor? auto flag?
meisterSiri touchid --off    # disable (set TOUCHID_SUDO=false to stop re-enable)
```

### Autofix (v6.7+)

```bash
meisterSiri ai            # Autofix + AI-Rest-Zusammenfassung
meisterSiri autofix       # nur deterministische Fixes
meister ai / meister autofix   # gleich (nach Sync)
```

Fixes: alte brew bottles, orphan LaunchDaemons, git push (clean), Firewall on,
Time Machine Settings öffnen, _Inbox Archive (>N Tage).

## v6.13 lib layout + quality gate

```
lib/core/          heal_guards, cleanup_tally, profiles, last_json  (bats-tested)
lib/commands/      extras.sh — why, storage, contacts, report diff/json, doctor json
lib/modules/       extraction track (README only until modules move)
tests/             bats
scripts/check.sh   shellcheck + bats + bash -n  (also run by release.sh)
docs/PRODUCT.md    brand + heald contract
docs/GUI.md        single GUI decision
```

Handshake: every full run writes `~/.meister/last.json` for heald.

New commands: `why`, `storage`, `contacts doctor`, `report --diff|--json`, `doctor --json`.

## v6.12 Trust defaults (AI-Heal + verify)

| Setting | Default | Meaning |
|---------|---------|---------|
| `AI_HEAL_EXECUTE` | **false** | AI-Heal / Learned-Fix only **suggest** after allowlist |
| `--ai-heal-execute` | CLI | Opt-in: allowlisted commands may **run** |
| verify-after-heal | always | FIX only if module retest passes; heal.log: `executed`/`verified`/`unverified`/`suggested` |
| cleanup tallies | always | found/removed/skipped_perm — perm noise ≠ module failure |

Config: `AI_HEAL_EXECUTE=true` in `~/.meister/config` or flag on the run.

## v6.8 Keep-current architecture

| Twin | AI backend | Use |
|------|------------|-----|
| `meisterSiri` | Apple Intelligence (on-device) | Default GUI + LaunchAgents |
| `meister` | Ollama (`qwen3-coder:30b` @ :11434) | When Ollama is preferred / offline Apple |

Shared: modules, autofix catalog, profiles, `~/.meister/`.

Every run: **Autofix first**, then Healer, then modules (AI-Heal on failures; default suggest-only since v6.12).

LaunchAgents (install: `meisterSiri -I`):
- Daily 09:15 `meisterSiri --auto -q`
- Sunday 10:30 `meisterSiri --deep -q`
- Retires legacy `com.meister.maintenance` (old meister2026.sh)

Ollama model override: `MEISTER_OLLAMA_MODEL=...` in `~/.meister/config`.
