# MeisterAI: Start und SmartInbox optimieren

Die Änderungen liegen auf `codex/meister-performance-20261004` im isolierten
Worktree `/Users/a321/Developer/.worktrees/meister-performance-20261004`.
Ausgangsbasis ist der saubere Homebrew-Tap-Stand `2b014b8` mit v6.36.
Die installierte Version wurde nicht ersetzt; es gab keinen Release und keine
echten Mail-Verschiebungen während Entwicklung und Messung.

## Ursachen und Änderungen

| Bereich | v6.36 | Vorbereitete Änderung |
|---|---|---|
| Starter | Vollständiges Homebrew-Update und Meister-Upgrade bei jedem Aufruf | Erfolgreichen Check 12 Stunden cachen; direkter Start über Homebrew `opt/meister` |
| Metadaten | Starter, AI Updates und Homebrew-Modul können separat aktualisieren | Erfolgreichen Check innerhalb derselben Prozessausführung wiederverwenden |
| SmartInbox | 32 neue KI-Prüfungen / 60 Sekunden begrenzen nur die KI; restliche Durchsicht läuft weiter | Höchstens 500 Nachrichten und 60 Sekunden weiches Budget für die Durchsicht |
| Fortsetzung | Ohne neue KI-Prüfung bleibt der Cursor häufig am Anfang | Hinter durchgesehene Seiten springen; erste zurückgestellte Prüfung hat Vorrang |
| Native Nachprüfung | Lokale KI-Prüfungen können das gesamte Budget aufbrauchen | Kleine Gruppen lokal prüfen und nativ bestätigen, bevor weitere Kandidaten starten |

Der Starter ändert bewusst die Aktualisierungsfrequenz. `--deep`, `-a` und
`BREW_UPDATE_MAX_AGE_SEC=0` erzwingen weiterhin eine neue Aktualisierung.
AI-Clients werden in jeder Wartung geprüft und nach Installation verifiziert;
ihre Registry- und nativen Updater bekommen keinen neuen Cache.

Eine begrenzte Durchsicht meldet `unscanned` und `previewComplete` ausdrücklich.
`completed` bestätigt die Ausführung des vorbereiteten Teilplans. Es behauptet
keine vollständige Durchsicht des Postfachs. Tatsächlich unvollständige
Quellauflistungen verhindern weiterhin die Ausführung. Jede geplante Verschiebung
benötigt dieselben aktuellen Inhalts-, Identitäts-, Schutz- und Zielprüfungen.

Das Budget ist weich: bereits gestartete Modellanfragen und eine vorausgelesene
Seite werden abgewartet. Preflight, native Bestätigung und verifizierte
Verschiebungen können die Gesamtzeit des Moduls verlängern. Für eine vollständige
Durchsicht bleibt `MeisterAI megasmart run --full` verfügbar.

## Messung

Reproduzierbarer Offline-Vergleich mit 13.424 künstlichen Nachrichten:

```sh
node scripts/benchmark-mail-maintenance.mjs BASELINE_CHECKOUT
```

Die Daten und SHA-256-Werte der verglichenen Laufzeitquellen liegen in
[offline-work.json](offline-work.json). Sowohl beim ausschließlich unlesbaren
Postfach als auch bei gemischten vollständigen/unvollständigen Inhalten ergeben
sich 500 statt 13.424 gelesene Nachrichten und 20 statt 537 Lesebatches:
**96,28 % weniger Arbeit bei der Inhaltsdurchsicht pro Wartung**.
Die Entscheidungen für die ersten 500 Nachrichten stimmen mit der Baseline
überein; der Folgelauf startet bei Nachricht 501.

Die Fixture verwendet keine echte Mail-App und kein echtes Modell. Ihre
Millisekundenwerte messen nur den Testaufbau. Eine entsprechende Beschleunigung
der realen Gesamtwartung ist damit nicht nachgewiesen.

## Prüfung

`bash scripts/check.sh` prüft Shellcheck, Bash-Syntax, Gleichstand der beiden
CLIs, Bats, Mail-/CLI-Tests, Starttests und die bestehenden FM-Fixtures.
Ergebnis: 202 Bats-, 124 Mail-/CLI-, 13 Start- und 22 Python-FM-Tests grün;
außerdem bestehen beide Offline-Fixtures mit 14/14 und 10/10 Fällen.
Zusätzliche Fälle decken Budgetende während Vorbereitung und Modellarbeit,
unvollständige Inhalte, unveränderte Vollprüfung, kombinierte Optionen,
fehlerhafte Cache-Zeitstempel und fortgesetzte native Nachprüfungen ab.
Ein Teilplan-Test prüft echte Zustandsänderungen im Mail-Mock und stellt sicher,
dass ein nachträglich gesetztes Flag die Verschiebung verhindert.

## Recap

- Optimierung im lokalen Worktree vorbereitet; installierte v6.36 unverändert.
- Offline: 96,28 % weniger Inhaltsdurchsicht; echte Gesamtlaufzeit noch ungemessen.
- Release und Installation sind noch offen.
