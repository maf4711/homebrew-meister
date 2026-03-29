#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${1:-$(cd "$(dirname "$0")" && pwd)}"
CLAUDE_DIR="$HOME/.claude"

echo "=== mafoe-claude-config ==="
echo "Source: $SCRIPT_DIR"
echo "Target: $CLAUDE_DIR"
echo ""

mkdir -p "$CLAUDE_DIR"

# Einzeldateien
for f in CLAUDE.md package.json gsd-file-manifest.json; do
  [ -f "$SCRIPT_DIR/$f" ] && cp "$SCRIPT_DIR/$f" "$CLAUDE_DIR/$f" && echo "  + $f"
done

# settings.json - Pfade auf aktuellen User anpassen
sed "s|/Users/a321|$HOME|g" "$SCRIPT_DIR/settings.json" > "$CLAUDE_DIR/settings.json"
echo "  + settings.json (Pfade -> $HOME)"

# Verzeichnisse
for dir in skills agents commands hooks get-shit-done; do
  if [ -d "$SCRIPT_DIR/$dir" ]; then
    rm -rf "$CLAUDE_DIR/$dir"
    cp -R "$SCRIPT_DIR/$dir" "$CLAUDE_DIR/$dir"
    echo "  + $dir/"
  fi
done

# Ausfuehrbarkeit
chmod +x "$CLAUDE_DIR/hooks/"*.js 2>/dev/null || true
chmod +x "$CLAUDE_DIR/get-shit-done/bin/"*.cjs 2>/dev/null || true

echo ""
echo "Fertig. Claude Code neu starten."
