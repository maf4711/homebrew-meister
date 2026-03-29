# Documents Ordnerstruktur (Stand: 2026-03-03, nach Komplett-Reorganisation + Home-Cleanup)

## 16 Hauptkategorien

```
Documents/
├── Arbeit/          # Anstellung EBF, Gehalt, Kreditkarten-Abrechnungen
├── Backups/         # Alte Backups, iMyFone WhatsApp, Documents-Snapshots (196 GB)
├── Business/        # Eigene Firmen: MeradOS, TradeOS, Föllmer Ventures, Pitches
├── Fahrzeuge/       # BMW XM Label Docs + Finanzierung
├── Familie/         # Kinder, Eltern, Scheidung, Verwandte, Elterngeld
├── Finanzen/        # Steuern, Banking, Investments, IBKR, Rechnungen, TR, Revolut
├── Gesundheit/      # Befunde, Labor, Therapie, Supplements, Diäten
├── Haushalt/        # Wohnung, Geräte, Möbel, PV-Autarkie, Umzug
├── Immobilien/      # Alle Standorte (Köln, Kürten, Montenegro, Belgrad)
├── Kalender/        # .ics Kalender-Dateien
├── Medien/          # Akropolis Discographie, Bilder, Videos, Audio
├── Persönlich/      # Ausweise, Testament, Vollmachten, Apps
├── Projekte/        # Code-Repos (NICHT anfassen)
├── Reisen/          # Reiseplanung, Tickets, Wandern
├── Tech/            # Scripts, Configs, Prompts, Logs, GPT, SmartHome, icli, yara
└── Versicherung/    # Alle Policen (LVM, Ergo, Generali, HanseMerkur)
```

## Zuordnungsregeln

| Inhalt | Kategorie |
|--------|-----------|
| Gehaltsabrechnungen, Arbeitsverträge, EBF HR | Arbeit |
| Eigene Firmen, Pitches, VSOP, Unternehmensanteile | Business |
| Fahrzeugdokumente, Leasing, Fahrzeugschein | Fahrzeuge |
| Kinder, Eltern, Partner, Scheidung, Elterngeld | Familie |
| Steuern, Banking, Investments, Rechnungen, Krypto | Finanzen |
| Arztbriefe, Befunde, Labor, Therapie, Supplements | Gesundheit |
| Wohnung, Geräte, Möbel, Umzug, PV-Anlage | Haushalt |
| Immobilien-Standorte, Mietverträge, Exposés | Immobilien |
| Kalender-Dateien (.ics) | Kalender |
| Musik, Bilder, Videos, Audio | Medien |
| Ausweise, Testament, Vollmachten, persönliche Docs | Persönlich |
| Code-Repositories, Software-Projekte | Projekte |
| Reiseplanung, Tickets, Wanderrouten | Reisen |
| Scripts, Configs, Prompts, Logs, SmartHome | Tech |
| Versicherungspolicen, Kündigungen | Versicherung |

## Statistiken

~1.560.000 Dateien, ~269 GB
Größte: Backups (196 GB), Medien (41 GB), Familie (22 GB)
Vollständiger Katalog: Documents/KATALOG.md

## Bekannte Probleme
- iCloud Sync erstellt regelmäßig leere Duplikat-Ordner im Documents Root
- Korrupte iCloud-Stubs: 65535 Links, 0B - brauchen rm -rf
