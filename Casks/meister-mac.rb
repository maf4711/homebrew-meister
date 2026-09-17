cask "meister-mac" do
  version "6.25"
  sha256 "4d5d2dc37b89835f3874a36e4232476337b466ef7b4e9f18bffa8dde0c3f689b"

  url "https://github.com/maf4711/homebrew-meister/releases/download/v#{version}/MeisterSiri-macOS.zip"
  name "MeisterSiri"
  desc "macOS GUI over the meisterSiri CLI (Apple Intelligence maintenance)"
  homepage "https://github.com/maf4711/homebrew-meister"

  depends_on formula: "maf4711/meister/meister"
  depends_on macos: :sonoma

  app "MeisterSiri.app"

  zap trash: [
    "~/Library/Preferences/com.maf4711.meistersiri.plist",
    "~/Library/Caches/com.maf4711.meistersiri",
  ]

  caveats <<~EOS
    MeisterSiri.app talks to the meisterSiri CLI from formula `meister`.

    Legacy Meister.app (meister-app track) is no longer this cask.
    Remove it with: rm -rf /Applications/Meister.app
  EOS
end
