# MeisterAI: lokale Apple-KI und Siri geprüft

Stand: 14. Oktober 2026, auf diesem Mac. Ergebnis: MeisterAI verwendet nachweislich
Apples lokales Sprachmodell. AI-Heal ist standardmäßig lokal zuerst, kann aber auf
Private Cloud Compute (PCC) wechseln. Siri-Aktionen sind zusätzlich vorhanden.

## Geprüfte Installation

- macOS 27.2, Apple Silicon arm64, Xcode 27.0.
- PATH → `~/.local/bin/MeisterAI` → `/opt/homebrew/bin/MeisterAI` → Homebrew 6.37.
- Ausführender CLI-Code: `/opt/homebrew/Cellar/meister/6.37/libexec/MeisterAI`.
- Modell-Helper: `~/.meister/meister-fm`.
- `MeisterAI.app`: Version 6.32.0, Build 5, Bundle `com.maf4711.meisterai`.
- Zusätzlich `Meister.app`: Version 1.1.0, Build 39, Bundle `com.merados.meister.macos`.
- Beide macOS-Oberflächen bevorzugen die installierte MeisterAI-CLI.
- Täglicher und wöchentlicher Keep-current-LaunchAgent verwenden MeisterAI.

Die Swift-Helper-Quelle im Repository, in Homebrew und im lokalen Compile-Cache
war identisch: SHA-256
`d8d27360b7be6a5c51854fb4d696c06db3d05321cc569a8d8447f7471d7cc758`.

## Tatsächliche Modellausführung

`lib/fm/MeisterFM.swift` importiert `FoundationModels` und erzeugt eine
`LanguageModelSession` mit `SystemLanguageModel.default`. Apple bezeichnet diese
API ausdrücklich als [lokales Apple Foundation Model](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel).

1. Installierter Helper: `--selftest` und `--check --model system` jeweils Exit 0.
2. Echter Aufruf mit `--model system --purpose query`: Antwort auf die synthetische
   Frage nach einem Dateicache, Exit 0. Metadaten:
   `model=system purpose=query in=116 out=21 ctx=8192 latency_ms=965`.
3. Vollständiger installierter CLI-Pfad `explain` mit synthetischer Meldung und
   isoliertem Zustandsverzeichnis: Exit 0, nachvollziehbare deutsche Antwort.
   Metadaten: `model=system purpose=explain in=188 out=81 ctx=8192 latency_ms=2354`.
   Der Homebrew-Updater wurde für diesen Test durch direkten Aufruf des
   installierten libexec-Programms ausgelassen.
4. Bestehendes `~/.meister/ai_usage.log`: am 14.10.2026 um 09:42:05 bereits ein
   erfolgreicher AI-Heal-Aufruf mit `model=system`, 2140 Eingabe- und 191
   Ausgabetokens, 8296 ms; danach `diagnosis-valid` und `no-fix`.

Damit sind sowohl die API-Verwendung als auch echte lokale Antworten und eine
bereits protokollierte Nutzung belegt. Keine Netzwerksperre oder vollständige
Paketaufzeichnung durchgeführt; dies ist kein Nachweis, dass die gesamte
Wartungsanwendung ohne Netzwerk arbeitet.

## Lokalität und Routing

| Funktion | Standardroute |
| --- | --- |
| `explain`, `today`, `suggest`, einfache Textabfragen | `system`, lokal |
| strukturierte Diagnose | `FM_DIAGNOSE_MODEL`, Standard `system` |
| AI-Heal | `FM_HEAL_MODEL`, Standard `auto` |
| CLI `meister` | eigener Ollama-Backendpfad |

`auto` fragt zunächst das lokale Modell. Bei einer validierten Diagnose mit
`action=none`, leerem `missing_information` und verfügbarem PCC kann der Kontext
an `PrivateCloudComputeLanguageModel` gehen. Diese API läuft laut Apple auf
[Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel).
Die lokale PCC-Verfügbarkeitsprüfung lieferte Exit 0; keine PCC-Generierung
ausgeführt. Im ausgewerteten bestehenden Nutzungsprotokoll fand sich kein
`model=pcc` oder `escalation=pcc`. Das beweist keine vollständige historische
Cloud-Freiheit.

Zum Prüfzeitpunkt enthielt die Benutzerkonfiguration keinen der beiden
Modellschlüssel; auch die Prozessumgebung setzte sie nicht. Die bestehenden
Standards bleiben unverändert. Ausschließlich lokale Inferenz lässt sich nach
der unten beschriebenen Korrektur so konfigurieren:

```ini
FM_HEAL_MODEL=system
FM_DIAGNOSE_MODEL=system
```

Diese Einstellung wurde nicht in der Benutzerkonfiguration aktiviert.

## Siri-Anbindung

Die installierte `MeisterAI.app` enthält in
`Contents/Resources/Metadata.appintents/extract.actionsdata` zwei discoverable
App Intents samt Kurzbefehlsphrasen:

- `MacHealthIntent`: „Wie geht es meinem Mac mit MeisterAI“.
- `LastMaintenanceReportIntent`: „Zeige den letzten Wartungsbericht in MeisterAI“.

Der zugehörige Code in `app/MeisterAI/Sources/Intents/ReportIntents.swift` liest
gespeicherte Wartungsberichte und erstellt feste Textantworten. Diese Aktionen
starten weder eine neue Modellabfrage noch eine Wartung. Die generative KI im
Backend wird unabhängig davon über Foundation Models aufgerufen. Apple beschreibt
[App Intents](https://developer.apple.com/documentation/appintents) als Integration
für Siri und weitere Systemfunktionen. Eine gesprochene Siri-Aktivierung wurde
nicht getestet; installierte Metadaten belegen noch keinen erfolgreichen Sprachaufruf.

Die separate iOS-App im Repository `meister` hat ebenfalls Siri/App-Intent-Aktionen,
aber keinen eigenen `FoundationModels`-Aufruf im geprüften Quellcode.

## Gefundener und lokal behobener Fehler

Die dokumentierten Konfigurationsschlüssel `FM_HEAL_MODEL` und
`FM_DIAGNOSE_MODEL` fehlten in der Parser-Allowlist. Deshalb wurde ein Eintrag
`FM_HEAL_MODEL=system` bisher ignoriert und AI-Heal konnte weiter `auto` verwenden.

- Beide Schlüssel in `MeisterAI.sh` aufgenommen und `meister.sh` synchronisiert.
- Sieben Regressionstests in `tests/fm_config.bats` prüfen den echten Parser bis
  zur Modellauswahl, mit simuliertem Helper: lokale Auswahl, PCC-Auswahl,
  Anführungszeichen, Konfigurationsvorrang, Umgebungswerte, unveränderte Standards,
  ungültige Werte und lokale Textabfragen.
- Vor der Korrektur scheiterten vier der zunächst fünf Regressionstests; nach
  der Korrektur bestehen alle sieben.
- Gesamtes `scripts/check.sh` im isolierten Checkout erfolgreich: 186 Bats-Tests,
  22 Python-Tests, ShellCheck, Bash-Syntax, Twin-Parität und 14 + 10 Offline-Fälle.
  Die Offline-Fälle messen keine Modellqualität.
- Die identische Parser-Korrektur wurde mit Sicherung atomar auf beide lokal
  installierten 6.37-CLI-Dateien übertragen. Alle sieben Routingtests bestehen
  auch gegen den tatsächlich installierten Apple-Parser; beide Skripte bestehen
  die Bash-Syntaxprüfung.
- Die Quellcodekorrektur liegt uncommitted in `homebrew-meister`; fremde Änderungen
  wurden erhalten. Kein Release oder Push. Eine spätere Homebrew-Neuinstallation
  kann den lokalen Installationsfix überschreiben, solange er nicht veröffentlicht ist.

Sicherungen, Hash-Beleg und vollständiges Prüfprotokoll liegen unter
`/private/tmp/meisterai-local-ai-audit-20261014-evidence/`.
