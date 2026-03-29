---
name: Terminal-Befehle als Datei
description: User will Terminal-Befehle immer als kopierbare Datei, nicht inline im Chat
type: feedback
---

Wenn der User Befehle auf einem anderen Rechner ausführen muss, IMMER eine Datei schreiben (z.B. /tmp/remote-commands.sh oder ähnlich), die er per AirDrop, USB-Stick oder Screen Sharing kopieren kann. Inline Copy-Paste aus dem Chat verursacht Encoding-Probleme (unsichtbare Zeichen, Bracketed Paste `[200~]`, Zeilenumbrüche).

**Why:** Copy-Paste aus Claude Code Terminal in andere Terminals erzeugt kaputte Sonderzeichen und zsh-Fehler.

**How to apply:** Bei jedem Remote-Befehl eine .sh Datei schreiben statt inline-Befehle im Chat.
