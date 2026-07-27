class Meister < Formula
  desc "macOS Maintenance, Self-Healing & Dotfiles Sync (meister + meisterSiri)"
  homepage "https://github.com/maf4711/homebrew-meister"
  url "https://github.com/maf4711/homebrew-meister/archive/refs/tags/v6.9.tar.gz"
  sha256 "ca9b16a1a4715f9c9cf6337e34adfdc63754543315f525ef5083456dcacfb606"
  license "GPL-3.0-only"
  version "6.9"

  depends_on :macos

  def install
    bin.install "meister.sh" => "meister"
    bin.install "meisterSiri.sh" => "meisterSiri"
    doc.install "config.fast.example" if File.exist?("config.fast.example")
    doc.install "AGENTS.md" if File.exist?("AGENTS.md")
    (libexec/"tools").install Dir["tools/*"]
    # Symlink tools into bin with meister- prefix
    (libexec/"tools").children.each do |tool|
      bin.install_symlink tool => "meister-#{tool.basename(".sh")}"
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
    EOS
  end

  test do
    assert_match "meister", shell_output("#{bin}/meister -h 2>&1", 0)
    assert_match "meisterSiri", shell_output("#{bin}/meisterSiri --version 2>&1", 0)
  end
end
