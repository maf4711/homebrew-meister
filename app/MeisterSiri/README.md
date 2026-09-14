# MeisterSiri.app

Native **macOS GUI** (SwiftUI) im **OnyX-Stil** über die CLI `meisterSiri`.

## Sidebar

| Bereich | Inhalt |
|---------|--------|
| **Ergebnisse** | Letzter Wartungslauf, offene Punkte, geprüfte Reparaturen, Speicher und Verlauf |
| **Wartung** | Quick / Auto / Deep Profile, Doctor, Today, Score, AI, Health |
| **Reinigung** | Healer, RAM purge, Orphans, Disk, Simfix, App-Updates |
| **Parameter** | OnyX-Tweaks (Finder, Dock, Keyrepeat, Screenshots, …) |
| **Sicherheit** | Live-Status (SIP, FV, Sudo), Privacy, TCC, Touch ID, sudo-setup |
| **Automation** | LaunchAgent, Config, Log-Ordner |
| **Protokoll** | Live-Stream der CLI-Ausgabe |
| **Info** | Versionen & Pfade |

Der Vorschau-Schalter in der Toolbar gilt für alle Aktionen und bleibt zwischen
App-Starts gespeichert. Unterstützte Befehle erhalten ihre Vorschau-Option;
Änderungen ohne verlässliche Vorschau werden gesperrt und erklärt. Das gilt auch
für Systemeinstellungen und Automation.

Profil-Vorschauen (Quick, Auto, Deep) zeigen den geplanten Modulablauf; sie führen
keine Wartungsmodule aus und behaupten keine bereits erkannten Einzelprobleme.
Für die Ausführung benötigt die App eine CLI mit dem passenden
Ausführungsvertrag. Bei einer älteren Installation fordert sie ein CLI-Update
an; gespeicherte Berichte und direkte Statusabfragen bleiben zugänglich.

Die Übersicht liest `~/.meister/last.json` und das Archiv unter
`~/.meister/runs/`. Vorschauen und abgebrochene Läufe sind separat sichtbar.
Vergleiche verwenden abgeschlossene echte Läufe desselben Profils und Programms.
Nicht gemessener Speicher wird als unbekannt angezeigt. Ältere CLI-Berichte
bleiben lesbar, enthalten aber nicht alle Details.
Felder, Messgrenzen und Reparaturgedächtnis sind in [REPORTS.md](../../docs/REPORTS.md)
beschrieben.

## Siri und Kurzbefehle

Die App stellt zwei native Aktionen bereit: den gespeicherten Wartungsstatus
abfragen und den letzten Wartungsbericht anzeigen. Beide lesen ausschließlich
vorhandene Berichte und starten keine Wartung. Die in Kurzbefehle angebotenen
Siri-Formulierungen enthalten den App-Namen MeisterSiri. Ohne Bericht wird das
ausdrücklich zurückgemeldet; ein alter Bericht wird nicht als Live-Check ausgegeben.

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

Benötigt: vollständiges Xcode und [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). Command Line Tools allein reichen nicht aus.

## Prüfen

Vom Repository-Verzeichnis:

```bash
bash scripts/check.sh      # ShellCheck, Syntax, Twin-Abgleich, Bats
bash scripts/check-app.sh  # macOS-Unit-Tests und Release-Build
```

Die App-Tests verwenden temporäre Berichte und harmlose Prozess-Fixtures.
Im Test-Host deaktiviert `MEISTER_DISABLE_STARTUP_CHECKS=1` automatische
Systemabfragen. Der App-Check verwendet ausschließlich das macOS-Ziel.

## Architektur

- **UI:** SwiftUI `NavigationSplitView` (Sidebar + Detail)
- **Jobs:** asynchrone Prozesse mit laufend gelesener Ausgabe und bestätigtem Abbruch
- **Berichte:** ein gemeinsames Datenmodell für Übersicht und Siri-Aktionen
- **Tweaks:** `meisterSiri tweaks <name> on|off` (identisch zur CLI)
- **Kein** eigener Root-Daemon — Sudo/Touch ID wie bei der CLI (`ensure_sudo` / `sudo-setup`)

## Gatekeeper (lokal ad-hoc signiert)

```bash
# falls blockiert:
xattr -dr com.apple.quarantine /Applications/MeisterSiri.app
# oder Rechtsklick → Öffnen
```
