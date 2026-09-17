class Meister < Formula
  desc "macOS Maintenance, Self-Healing & Dotfiles Sync (meister + MeisterAI)"
  homepage "https://github.com/maf4711/homebrew-meister"
  url "https://github.com/maf4711/homebrew-meister/archive/refs/tags/v6.26.tar.gz"
  sha256 "9fbc14d70fb0be57aadd496376751de2546ae43cd3c8cd931d64e5c9ca299c8a"
  license "GPL-3.0-only"
  version "6.26"
  revision 1

  depends_on :macos

  def install
    bin.install "meister.sh" => "meister"
    # Published 6.25 archives predate the rename; keep their checksum valid.
    apple_source = File.exist?("MeisterAI.sh") ? "MeisterAI.sh" : "meisterSiri.sh"
    bin.install apple_source => "MeisterAI"
    if apple_source != "MeisterAI.sh"
      inreplace bin/"MeisterAI", "MeisterSiri", "MeisterAI"
      inreplace bin/"MeisterAI", "meisterSiri", "MeisterAI"
    end
    # Compatibility only: installed pre-rename LaunchAgents can retain this path.
    bin.install_symlink "MeisterAI" => "meisterSiri"
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

      MeisterAI (same modules, Apple Intelligence branding):
        MeisterAI      Auto-detect maintenance
        MeisterAI ai   On-device AI diagnosis
        MeisterAI explain <text>
        MeisterAI -h   Help

      Both share config: ~/.meister/config

      Dotfiles Sync:
        meister push     Collect + commit + push
        meister pull     Pull + symlink
        meister setup    First-time clone (auto-detects repo)
        meister bootstrap Full machine setup

      v6.13+:
        MeisterAI why profile | storage | contacts doctor
        MeisterAI report --diff | doctor --json
        Handshake file: ~/.meister/last.json (for heald)
        GUI: brew install --cask meister-mac  (MeisterAI.app)
    EOS
  end

  test do
    assert_match "meister", shell_output("#{bin}/meister -h 2>&1", 0)
    assert_match "MeisterAI", shell_output("#{bin}/MeisterAI --version 2>&1", 0)
    assert_match "6.", shell_output("#{bin}/MeisterAI --version 2>&1", 0)
  end
end
