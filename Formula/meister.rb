class Meister < Formula
  desc "macOS Maintenance, Self-Healing & Dotfiles Sync"
  homepage "https://github.com/maf4711/meister"
  url "https://github.com/maf4711/meister/archive/refs/tags/v1.3.tar.gz"
  sha256 "f457dcbfb9a92a8b01d8da7d47338446a06cb2790377151854e0a2604185f1d1"
  license "GPL-3.0-only"
  version "1.3"

  depends_on :macos

  def install
    bin.install "meister.sh" => "meister"
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

      Dotfiles Sync:
        meister push     Collect + commit + push
        meister pull     Pull + symlink
        meister setup    First-time clone (auto-detects repo)
        meister bootstrap Full machine setup

      Config: ~/.meister/config
    EOS
  end

  test do
    assert_match "meister", shell_output("#{bin}/meister -h 2>&1", 0)
  end
end
