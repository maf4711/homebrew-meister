cask "meister-mac" do
  version "6.26"
  sha256 "df1a93194ca48662161ec2efb348cb288b6ec718fad2c3b5aedd9879f9ab1f02"

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
