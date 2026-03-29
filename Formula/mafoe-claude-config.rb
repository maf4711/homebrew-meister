class MafoeClaudeConfig < Formula
  desc "Portable Claude Code configuration - settings, skills, agents, hooks, GSD"
  homepage "https://github.com/maf4711/homebrew-meister"
  url "https://github.com/maf4711/homebrew-meister.git", tag: "v1.0.0-claude"
  head "https://github.com/maf4711/homebrew-meister.git", branch: "main"
  license "MIT"
  version "1.0.0"

  def install
    bin.install "config/install.sh" => "mafoe-claude-install"
    (prefix/"config").install Dir["config/*"]
  end

  def caveats
    <<~EOS
      Jetzt ausfuehren um die Config zu installieren:

        mafoe-claude-install #{prefix}/config

      Danach Claude Code neu starten.
    EOS
  end
end
