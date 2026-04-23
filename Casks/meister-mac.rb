cask "meister-mac" do
  version "1.0.0"
  sha256 "a2340ff5b85665ab309ec245fa7abe44bc03cc72e29b4b2b98eeb8519f863e85"

  url "https://github.com/maf4711/meister-app/releases/download/v#{version}/Meister-macOS-#{version}.zip",
      verified: "github.com/maf4711/meister-app/"
  name "Meister"
  desc "macOS GUI over the bash-meister CLI + AddressBook cleanup"
  homepage "https://github.com/maf4711/meister-app"

  depends_on formula: "maf4711/meister/meister"
  depends_on macos: ">= :sonoma"

  app "Meister.app"

  zap trash: [
    "~/Library/Preferences/com.merados.meister.macos.plist",
    "~/Library/Caches/com.merados.meister.macos",
  ]

  caveats <<~EOS
    Meister.app is the GUI companion to the #{Formatter.identifier("meister")} CLI.

    On first launch, grant access to Contacts when prompted — required for
    the AddressBook cleanup feature. All processing stays local.

    v1.0.0 is signed with an Apple Development certificate rather than a
    Developer ID. If Gatekeeper blocks the app, right-click Meister.app
    in Finder → Open → Open. The 1.0.1 build will be Developer-ID-signed
    and notarized.
  EOS
end
