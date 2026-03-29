# Memory Index

## Documents Ordnerstruktur
- Details: [documents-structure.md](documents-structure.md)
- 16 Hauptkategorien: Arbeit, Backups, Business, Fahrzeuge, Familie, Finanzen, Gesundheit, Haushalt, Immobilien, Kalender, Medien, Persoenlich, Projekte, Reisen, Tech, Versicherung
- Vollstaendiger Katalog: Documents/KATALOG.md (~1.56M Dateien, ~269 GB)
- Home-Root aufgeraeumt: Backups/IBKR/Scripts/icli nach Documents verschoben, leere Ordner entfernt
- Verbleibend in Home-Root: Laufzeit-Tools (go, miniforge3, Parallels, Venvs, AI-Modelle, Cloud-Mounts)
- iCloud Sync erstellt regelmaessig leere Geister-Ordner im Root - rmdir entfernen
- Korrupte iCloud-Stubs zeigen 65535 Links, 0B Groesse - rm -rf noetig

## Feedback: Dateigrösse
- Regel: Max ~300 Zeilen pro Source-Datei, immer modular aufteilen → [feedback_file_size.md](feedback_file_size.md)
- Grund: Jakob (App-Partner) bemängelt zu grosse Claude-generierte Dateien

## User Preferences
- Sprache: Deutsch
- Ollama Default-Modell: qwen3-coder:30b (Benchmark-Sieger 100/100, Script: Tech/Scripts/bin/meister2026.sh)
- Remote-Befehle: IMMER als .sh Datei, nie inline Copy-Paste → [feedback_terminal_commands.md](feedback_terminal_commands.md)

## Node/NVM Fix (KRITISCH)
- Problem: zsh definiert `node`, `npm`, `npx` als Shell-Funktionen die `_nvm_lazy_load` aufrufen
- `_nvm_lazy_load` verursacht Endlosrekursion (FUNCNEST limit) wenn ueber Bash-Tool aufgerufen
- `export NVM_DIR=... && . nvm.sh` hilft NICHT - gleicher Fehler
- FIX: IMMER direkt die Binaries aufrufen, NIEMALS `node`/`npm`/`npx` als Kommando
  - Node: `/Users/a321/.nvm/versions/node/v22.22.0/bin/node`
  - NPM: `/Users/a321/.nvm/versions/node/v22.22.0/bin/npm`
  - NPX: `/Users/a321/.nvm/versions/node/v22.22.0/bin/npx`
- Beispiel: `/Users/a321/.nvm/versions/node/v22.22.0/bin/npx --prefix /pfad/zum/projekt tsc --noEmit`
- Aktuellste Version: v22.22.0 (auch v22.16.0 und v20.19.1 verfuegbar)

## Meister Script (Tech/Scripts/bin/meister2026.sh)
- Version: v0.04, ~4280 Zeilen
- v0.04 Fixes: git timeout (#105), benchmark timing (#106), git status cache (#107), version strings (#108)
- v0.04 Perf: strip_think 1 sed (#109), ps-cache (#110), wc-l trim (#111), log ts-cache (#112), net parallel (#114)
- Neue Module in v0.02: Memory-Hogs killen, Login Items, LaunchAgents, Ollama Cleanup, RAM Purge (16 Sub-Tasks)
- Neues Modul in v0.03: module_git_repos() - Git Auto-Push + iCloud Backup (-G Flag)
- Alle neuen Features nur mit -P bzw -G aktiv, ohne Flag nur Analyse/Warnung
- Config: ~/.meister/config, Logs: ~/.meister/meister.log
- merados-site Repo hat langsamen Remote (Timeout noetig bei git rev-parse)

## FO Dashboard (Projekte/alpha-merados)
- meradOS Family Office Dashboard v4, Next.js 14, TanStack Query, Supabase PG
- API Routes unter app/api/fo/, Komponenten unter components/fo/
- Server-Cache: lib/cache.ts (in-memory TTL)

## iCloud Migration 2026-03-15
- Details: [project_icloud_migration.md](project_icloud_migration.md)
- Projekte → Developer: ERLEDIGT (51 Projekte, alle gepusht)
- Documents: OFFEN (stecken im iCloud-Container, fileproviderd haengt)
- Nach Neustart: Documents aus iCloud-Container zurueckholen
- Migration Bundle: ~/Developer/_mac-migration/ (Brewfile, SSH, dotfiles, setup-script)
- Neuer Mac naechste Woche - Migration Assistant bereit
