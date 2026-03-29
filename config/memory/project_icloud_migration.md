---
name: iCloud Migration Status 2026-03-15
description: Documents stecken im iCloud-Container, fileproviderd festgefahren, Neustart noetig
type: project
---

## Status 2026-03-15 18:00

**Developer: ERLEDIGT** — 51 Projekte in ~/Developer/, alle committed + gepusht auf GitHub

**Documents: OFFEN** — ~/Documents/ ist leer, Dateien stecken in iCloud-Container:
- `~/Library/Mobile Documents/com~apple~CloudDocs/Documents/` hat 1 Eintrag (Dokumente – CM-...)
- `~/Library/Mobile Documents/com~apple~CloudDocs/Downloads/` hat ALLE 16 Kategorien (Arbeit, Backups, Business, Fahrzeuge, Familie, Finanzen, Gesundheit, Haushalt, Immobilien, KATALOG, Medien, Persönlich, Reisen, + Caro-Ordner)
- fileproviderd haengt bei ~100-130% CPU seit 40+ Min, blockiert mv/cp

**Why:** iCloud Drive "Schreibtisch & Dokumente" wurde bei Apple-ID Neuanmeldung automatisch reaktiviert und hat Documents verschluckt. Dann deaktiviert, aber fileproviderd haengt seitdem.

**How to apply:**
1. Nach Neustart: prüfe ob fileproviderd idle ist (< 5% CPU)
2. Verschiebe Dateien aus iCloud-Container nach ~/Documents/:
   - `mv ~/Library/Mobile Documents/com~apple~CloudDocs/Downloads/Arbeit ~/Documents/`
   - Gleiches fuer: Backups, Business, Fahrzeuge, Familie, Finanzen, Gesundheit, Haushalt, Immobilien, Medien, Persönlich, Reisen
   - KATALOG_2026-03-13.md ebenfalls
3. Prüfe dass FXICloudDriveDocuments=0 und FXICloudDriveDesktop=0 bleibt
4. Migration Bundle liegt in ~/Developer/_mac-migration/ (Brewfile, SSH, dotfiles, setup-script)
