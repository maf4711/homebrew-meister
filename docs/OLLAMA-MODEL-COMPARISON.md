# Welches Ollama-Modell für meister?

Empfehlung am 17.09.2026: **qwen3-coder:30b** für diesen Mac und Meisters
begrenzte Wartungsdiagnosen. Es bleibt der Standard. Unter den acht lokal
getesteten Modellen bietet es die überzeugendste Kombination aus erwarteter
Aktionswahl, verwertbaren Erklärungen, Antwortzeit und Ressourcenbedarf.
Das ist keine allgemeine Rangliste aller verfügbaren Ollama-Modelle.

Getestet auf Apple M5 Max mit 128 GiB, Ollama 0.34.1, vollständig lokal.
Keine Downloads, Reparaturen oder Änderung der installierten Ollama-Konfiguration.
Pro Modell zunächst 14 Fälle; die fünf stärksten Kandidaten anschließend mit
zehn unabhängig formulierten deutschen Fällen. Alle nutzten denselben finalen
Prompt, temperature=0, num_ctx=8192, num_predict=1024 und think=false.

| Modell | Erste 14 Fälle¹ | Unabhängige 10¹ | Gültige Diagnosen / erwartete Aktionen² | Median³ |
|---|---:|---:|---:|---:|
| **qwen3-coder:30b** | **14/14** | **9/10** | **24/24** | **1,33 s** |
| qwen3.6:latest | 12/14 | 9/10 | 24/24 | 1,77 s |
| qwen2.5-coder:14b | 12/14 | 8/10 | 23/24 | 2,58 s |
| qwen3:8b | 12/14 | 7/10 | 22/24 | 1,78 s |
| nemotron-3.5-lightning:30b-mlx | 12/14 | 7/10 | 21/24 | 1,26 s |
| eurollm:22b | 10/14 | nicht qualifiziert | 13/14 gültig, 12/14 Aktionen | 6,89 s |
| gemma4:latest | 9/14 | nicht qualifiziert | 10/14 | 1,67 s |
| llama3.2:latest | 6/14 | nicht qualifiziert | 9/14 gültig, 8/14 Aktionen | 0,75 s |

¹ Automatische Gesamtprüfung: Vertrag, Beleg-IDs, erwartete Aktion sowie ein
passendes Ursachenwort. Worttreffer sind ein grober Qualitätsindikator, kein
Beweis einer fachlich richtigen Diagnose. Bei Qwen3-Coder scheiterte nur die
Wortprüfung einer vorsichtigen Antwort auf fehlende Prozessdaten; die Aktion
blieb korrekt `none`. Die Auswahl für den unabhängigen Satz verlangte mindestens
12/14 Gesamtprüfungen und 13/14 gültige Diagnosen.

² „Erwartete Aktion“ umfasst ausdrücklich Nichtstun, wenn keine unterstützte
Reparatur belegt ist. Es wurde keine Aktion ausgeführt. Wo nur eine Zahl steht,
stimmen Anzahl gültiger Diagnosen und erwarteter Aktionen überein.

³ Median über alle versuchten Fälle des jeweiligen Modells, einschließlich
abgelehnter Antworten und anfänglicher Ladezeit. Unterschiedliche Satzgrößen
beachten; keine isolierte GPU-Leistungsmessung. Ein Durchlauf pro Konfiguration,
kleine Aufgabenstichprobe. Modell-Digests sind in den Artefakten festgehalten.

Qwen3-Coder benötigt lokal etwa **18,56 GB Modelldateien**. Nach dem echten
CLI-Diagnosetest meldete Ollama **19,36 GB size_vram** bei Kontextgröße 8192;
das ist nicht der gesamte Speicherverbrauch des Macs. Qwen3 8B ist mit
5,23 GB Modelldateien eine kleinere Alternative, in diesem Test aber weniger
zuverlässig und nicht schneller als Qwen3-Coder.

Qwen3.6 war bei sudo/TTY teilweise präziser, lieferte jedoch keinen überzeugenden
Gesamtvorteil. Nemotron war schnell, antwortete häufig englisch und empfahl
unter anderem einen QuickLook-Cache-Reset zur XProtect-Prüfung. Die kleine
Gemma-Version ist nicht mit den größeren Gemma-Modellen gleichzusetzen.
Nicht installierte Kandidaten wie Qwen3-Coder-Next wurden nicht getestet.

Die inhaltliche Prüfung fand auch beim empfohlenen Modell Fehler: fehlender
XProtect-Scannachweis wurde teilweise als Scanproblem interpretiert, Dock-Diagnose
verwendete eine falsche launchctl-Domain, Mail-Datenschutzhinweise blieben ungenau.
Deshalb bleiben Prüfvorschläge ausdrücklich ungeprüfter Text, Aktionskatalog und
Belegprüfung aktiv und tatsächliche Ausführung standardmäßig ausgeschaltet.
Siehe [qualitative Prüfung](verification/ollama-20260917/qualitative-review.md).

## Umgesetzte Verbesserungen

- Präzisere allgemeine Anweisungen zu aktuellen/historischen Belegen, unbekannten
  Fakten, Authentifizierung, Aktionskatalog und bereits gescheiterten Reparaturen.
- `MEISTER_OLLAMA_THINK=false` als Standard, mit expliziten Overrides. Qwen3.6
  lieferte zuvor 0/14 verwertbare Endantworten, danach 14/14; Nemotron 0/14 → 13/14.
  Prompt und Thinking wurden zusammen geändert; ihre Einzeleffekte sind nicht isoliert.
- Wiederholbarer Ollama-Evaluator und unabhängiger Testsatz.
- KI-Prüfvorschläge sichtbar als ungeprüft markiert; Diagnose-only zeigt keinen
  Auto-Fix-Titel mehr.

```bash
MEISTER_OLLAMA_MODEL="qwen3-coder:30b"
MEISTER_OLLAMA_THINK="false"
MEISTER_OLLAMA_NUM_CTX=8192
MEISTER_OLLAMA_NUM_PREDICT=1024
MEISTER_OLLAMA_TIMEOUT=90
MEISTER_OLLAMA_KEEP_ALIVE="5m"
```

Die frühere Konfiguration erreichte mit Qwen3-Coder 9/14 Gesamtprüfungen; die neue
14/14 im gleichen Satz und 9/10 im unabhängigen Satz. Diese Zahlen sind keine
Nachweise erfolgreicher Reparaturen.

[Methodik](verification/ollama-20260917/method.md),
[Basislauf](verification/ollama-20260917/baseline.json),
[optimierter Lauf](verification/ollama-20260917/tuned.json),
[unabhängiger Satz](verification/ollama-20260917/holdout.json),
[CLI-Test](verification/ollama-20260917/cli-smoke.json).
Offizielle Referenzen: [Qwen3-Coder](https://ollama.com/library/qwen3-coder),
[Qwen3.6](https://ollama.com/library/qwen3.6),
[Thinking-Konfiguration](https://docs.ollama.com/capabilities/thinking).

Abschlussprüfung im Hauptprojekt: **152 Bats-Tests, 22 Python-Tests und 24
Offline-Vertragsfälle bestanden**. Der echte CLI-Aufruf `meister ai --diagnose-only`
lieferte für einen synthetischen gesunden Bericht Exit 0 und Aktion `none`.
Temporärer Testserver beendet; Änderungen nicht veröffentlicht oder installiert.

Recap: Qwen3-Coder 30B bleibt für Meister auf diesem Mac die beste getestete
Gesamtlösung; Konfiguration verbessert, Grenzen und Messdaten dokumentiert.
