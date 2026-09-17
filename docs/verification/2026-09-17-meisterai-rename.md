# MeisterAI rename verification — 2026-09-17

The Apple CLI source/executable, native app, Swift target/module, bundle ID,
UI, build/release scripts, tests and documentation now use MeisterAI.
The meister executable, Ollama backend and shared ~/.meister state remain.

Validation:
- Root scripts/check.sh: 146 Bats tests, Python transport test, 14 offline fixtures passed.
- Native app: 40 tests passed; universal Release build and strict ad-hoc signature verification passed.
- CLI versions: MeisterAI v6.25 (Apple Intelligence); meister v6.25 (Ollama).
- Formula/cask Ruby syntax and release shell syntax passed.

Legacy names remain only for report/settings migration, published 6.25 artifact
compatibility and immutable prior verification receipts. The FM source receipt
records the pre-rename snapshot; it is historical evidence, not a hash manifest
of the renamed tree. No renewed live FM quality claim is made by this rename.

Published artifact URLs/checksums have not been invented or replaced. The formula
accepts the old archive under the new executable name and retains an alias only
for that old archive's app. The cask installs the published bundle as MeisterAI.app;
its embedded identity changes only after a new app release. release.sh switches
the cask to the new artifact when it uploads the newly built bundle.

No release, push or installation performed. Existing installed binaries/apps
remain at their published version until the next installation.

Recap: project rename complete; meister preserved; migration and build checks pass.
