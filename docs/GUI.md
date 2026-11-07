# GUI decision (P1 #10)

**Canonical:** `homebrew-meister/app/MeisterAI/` → MeisterAI.app
**Legacy:** `~/Developer/meister-app` (AddressBook + older shell-out matrix)

## Why one surface

- Twin CLI already has two binaries; a second full GUI doubles release cost.
- MeisterAI.app is built next to the CLI formula and matches keep-current agents.
- meister-app’s hard dependency on `meradOS-Design4` sibling is a contributor blocker.

## What to do with meister-app

1. Keep AddressBook-specific Swift packages if still needed as a **library** path.
2. Mark README: “Legacy — prefer MeisterAI.app from homebrew-meister”.
3. Do not ship parallel App Store listings.

## Cask

`Casks/meister-mac.rb` installs **MeisterAI.app** (Developer ID + notarized zip
on the GitHub release). Legacy `Meister.app` from meister-app is retired.

```bash
brew tap maf4711/meister
brew install meister
brew install --cask meister-mac
```

Local unsigned build (dev only):

```bash
cd app/MeisterAI && ./scripts/build.sh --install
```
