# GUI decision (P1 #10)

**Canonical:** `homebrew-meister/app/MeisterSiri/` → MeisterSiri.app  
**Legacy:** `~/Developer/meister-app` (AddressBook + older shell-out matrix)

## Why one surface

- Twin CLI already has two binaries; a second full GUI doubles release cost.
- MeisterSiri.app is built next to the CLI formula and matches keep-current agents.
- meister-app’s hard dependency on `meradOS-Design4` sibling is a contributor blocker.

## What to do with meister-app

1. Keep AddressBook-specific Swift packages if still needed as a **library** path.
2. Mark README: “Legacy — prefer MeisterSiri.app from homebrew-meister”.
3. Do not ship parallel App Store listings.

## Cask

`Casks/meister-mac.rb` currently installs legacy Meister.app.  
Until MeisterSiri is notarized and casked, document:

```bash
# CLI
brew tap maf4711/meister && brew install meister

# GUI (from this repo)
cd app/MeisterSiri && ./scripts/build.sh
```
