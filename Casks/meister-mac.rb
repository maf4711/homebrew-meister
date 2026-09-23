cask "meister-mac" do
  version "6.32"
  sha256 "d9f343f2adbefad7ccff2b2679c4f1aa503b0cf9b6133465c2ea8ce7a8820f07"

  url "https://github.com/maf4711/homebrew-meister/releases/download/v#{version}/MeisterAI-macOS.zip"
  name "MeisterAI"
  desc "macOS GUI over the MeisterAI CLI (Apple Intelligence maintenance)"
  homepage "https://github.com/maf4711/homebrew-meister"

  depends_on formula: "maf4711/meister/meister"
  depends_on macos: :sonoma

  app "MeisterAI.app"

  zap trash: [
    "~/Library/Preferences/com.maf4711.meisterai.plist",
    "~/Library/Caches/com.maf4711.meisterai",
  ]

  caveats <<~EOS
    MeisterAI.app talks to the MeisterAI CLI from formula `meister`.

    Legacy Meister.app (meister-app track) is no longer this cask.
    Remove it with: rm -rf /Applications/Meister.app
  EOS
end
