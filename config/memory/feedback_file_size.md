---
name: Kleine modulare Dateien
description: Claude-Code soll Dateien klein und modular halten, max ~300 Zeilen pro Datei, immer aufteilen
type: feedback
---

Dateien die Claude-Code erstellt muessen klein und modular bleiben. Max ~300 Zeilen pro Source-Datei.

**Why:** Jakob (App-Partner) hat bemängelt, dass Claude-generierte Dateien konsistent zu gross sind. Scan zeigt 47 Dateien >500 Zeilen, schlimmster Fall 4.556 Zeilen in einer Datei. Monolithische Dateien sind schwer zu reviewen, testen und maintainen.

**How to apply:**
- Neue Dateien: Max ~300 Zeilen. Bei Überschreitung sofort in Module aufteilen
- React-Komponenten: Eine Komponente pro Datei, Composition über Unter-Komponenten
- Services/Utils: Pro Domain eine Datei (z.B. slack/ranking.ts, slack/alerts.ts statt ein riesiges slack.ts)
- Python: Klassen in eigene Module, CLI-Logic getrennt von Business-Logic
- Bei bestehenden Dateien: Vor dem Hinzufügen prüfen ob die Datei schon >250 Zeilen hat → dann zuerst aufteilen
- Keine minified Libraries committen → npm/pip Dependencies nutzen
- Lieber 5 kleine Dateien als 1 grosse
