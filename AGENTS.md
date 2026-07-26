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
