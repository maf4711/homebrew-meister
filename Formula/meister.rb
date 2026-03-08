# typed: false
# frozen_string_literal: true

# Homebrew Formula for meister2026.sh
# macOS Maintenance, Update & Self-Healing Script
#
# Installation:
#   brew tap a321/meister /Users/a321/Documents/Tech/Scripts/homebrew-meister
#   brew install meister
#
# Update:
#   cd /Users/a321/Documents/Tech/Scripts/homebrew-meister
#   ./release.sh   # Neues Archiv + SHA aktualisieren
#   brew upgrade meister

class Meister < Formula
  desc "macOS Maintenance, Update & Self-Healing Script mit Ollama AI"
  homepage "file:///Users/a321/Documents/Tech/Scripts/bin"
  version "0.01"
  license "MIT"

  url "file:///Users/a321/Documents/Tech/Scripts/homebrew-meister/dist/meister-0.01.tar.gz"
  sha256 "00022a2263ec559ddc575bca8d4d669c9c3d3dce53a0358e0651eb6826e23233"

  depends_on "jq"
  depends_on "mas"
  depends_on "clamav"
  depends_on "ollama"
  depends_on "terminal-notifier"
  depends_on :macos

  def install
    bin.install "meister2026.sh" => "meister"
  end

  def post_install
    ohai "Konfiguration: ~/.meister/config"
    ohai "Logs:          ~/.meister/meister.log"
    ohai "Starte mit:    meister -h"
  end

  def caveats
    <<~EOS
      meister v#{version} wurde installiert!

      Verwendung:
        meister          Standard-Wartung (Brew, macOS, Ollama AI)
        meister -a       Alle optionalen Module
        meister -n       Dry-Run (nur Vorschau)
        meister -h       Hilfe anzeigen

      Alle Abhaengigkeiten wurden automatisch installiert:
        jq, mas, clamav, ollama, terminal-notifier

      Konfiguration:
        ~/.meister/config              # Einstellungen anpassen
        meister -I                     # LaunchAgent fuer taegl. Ausfuehrung

      Deinstallation:
        brew uninstall meister
        rm -rf ~/.meister              # Config + Logs entfernen (optional)
    EOS
  end

  test do
    assert_match "meister2026", shell_output("#{bin}/meister -h 2>&1", 0)
  end
end
