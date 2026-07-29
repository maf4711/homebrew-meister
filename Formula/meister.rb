class Meister < Formula
  desc "macOS Maintenance, Self-Healing & Dotfiles Sync (meister + meisterSiri)"
  homepage "https://github.com/maf4711/homebrew-meister"
  url "https://github.com/maf4711/homebrew-meister/archive/refs/tags/v6.16.tar.gz"
  sha256 "5360547519ee96209a77ecebef2bed7d69b7e7ef996552c614f9a42bd72c13ed"
  license "GPL-3.0-only"
  version "6.16"

  depends_on :macos

  def install
    bin.install "meister.sh" => "meister"
    bin.install "meisterSiri.sh" => "meisterSiri"
    doc.install "config.fast.example" if File.exist?("config.fast.example")
    doc.install "AGENTS.md" if File.exist?("AGENTS.md")
    doc.install "docs/PRODUCT.md" if File.exist?("docs/PRODUCT.md")
    doc.install "docs/GUI.md" if File.exist?("docs/GUI.md")
    (libexec/"tools").install Dir["tools/*"] if Dir.exist?("tools")
    # v6.13: pure core + command helpers (heal guards, profiles, extras)
    (libexec/"lib").mkpath
    (libexec/"lib").install Dir["lib/*"] if Dir.exist?("lib")
    # twin-benchmark and helpers
    (libexec/"scripts").mkpath
    (libexec/"scripts").install Dir["scripts/*"] if Dir.exist?("scripts")
    # Symlink tools into bin with meister- prefix
    if (libexec/"tools").directory?
      (libexec/"tools").children.each do |tool|
        next if tool.directory?
        bin.install_symlink tool => "meister-#{tool.basename(".sh")}"
      end
    end
  end

  def caveats
    <<~EOS
      meister v#{version} installed!

      Maintenance:
        meister          Auto-detect maintenance
        meister -a       All modules
        meister -h       Help

      MeisterSiri (same modules, Apple Intelligence branding):
        meisterSiri      Auto-detect maintenance
        meisterSiri ai   On-device AI diagnosis
        meisterSiri explain <text>
        meisterSiri -h   Help

      Both share config: ~/.meister/config

      Dotfiles Sync:
        meister push     Collect + commit + push
        meister pull     Pull + symlink
        meister setup    First-time clone (auto-detects repo)
        meister bootstrap Full machine setup

      v6.13+:
        meisterSiri why profile | storage | contacts doctor
        meisterSiri report --diff | doctor --json
        Handshake file: ~/.meister/last.json (for heald)
        GUI: build app/MeisterSiri (canonical); cask meister-mac is legacy
    EOS
  end

  test do
    assert_match "meister", shell_output("#{bin}/meister -h 2>&1", 0)
    assert_match "meisterSiri", shell_output("#{bin}/meisterSiri --version 2>&1", 0)
    assert_match "6.", shell_output("#{bin}/meisterSiri --version 2>&1", 0)
  end
end
