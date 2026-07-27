# MeisterSiri.app

Native **macOS GUI** (SwiftUI) im **OnyX-Stil** über die CLI `meisterSiri`.

## Sidebar

| Bereich | Inhalt |
|---------|--------|
| **Wartung** | Quick / Auto / Deep Profile, Doctor, Today, Score, AI, Health |
| **Reinigung** | Healer, RAM purge, Orphans, Disk, Simfix, App-Updates |
| **Parameter** | OnyX-Tweaks (Finder, Dock, Keyrepeat, Screenshots, …) |
| **Sicherheit** | Live-Status (SIP, FV, Sudo), Privacy, TCC, Touch ID, sudo-setup |
| **Automation** | LaunchAgent, Config, Log-Ordner |
| **Protokoll** | Live-Stream der CLI-Ausgabe |
| **Info** | Versionen & Pfade |

Dry-Run-Schalter in der Toolbar → hängt `-n` an Wartungs-/Clean-Läufe.

## Voraussetzung

```bash
brew install maf4711/meister/meister   # liefert meisterSiri CLI
```

Die App sucht (in dieser Reihenfolge):

1. `/opt/homebrew/bin/meisterSiri`
2. `/usr/local/bin/meisterSiri`
3. `~/Developer/homebrew-meister/meisterSiri.sh`
4. Fallback `meister`

## Bauen & installieren

```bash
cd app/MeisterSiri
./scripts/build.sh --install
open -a MeisterSiri
```

Nur bauen nach `dist/MeisterSiri.app`:

```bash
./scripts/build.sh
```

Benötigt: Xcode (CLTs), [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Architektur

- **UI:** SwiftUI `NavigationSplitView` (Sidebar + Detail)
- **Jobs:** `Process` → `meisterSiri` mit Live-Stdout/Stderr
- **Tweaks:** `meisterSiri tweaks <name> on|off` (identisch zur CLI)
- **Kein** eigener Root-Daemon — Sudo/Touch ID wie bei der CLI (`ensure_sudo` / `sudo-setup`)

## Gatekeeper (lokal ad-hoc signiert)

```bash
# falls blockiert:
xattr -dr com.apple.quarantine /Applications/MeisterSiri.app
# oder Rechtsklick → Öffnen
```
