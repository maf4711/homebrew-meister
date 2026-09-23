# macOS maintenance repair — 2026-09-23

Observed on macOS 27.2: periodic is absent; historical maintenance logs contain failed attempts to quarantine protected Apple preferences. Doctor reported 2% root-volume use while the writable Data volume was 83% used. SIP, FileVault and firewall were enabled; no thermal warning was reported.

Changes: preference lint failures now warn without moving settings; Apple preferences are excluded from the healer probe. Missing periodic is not auto-scheduled or invoked; explicit system maintenance can still flush DNS, reports only completed operations, and remains non-mutating in preview. Doctor text and JSON inspect the writable Data volume when present. Both CLI twins share these corrections.

Follow-up: missing Time Machine destinations are silent in maintenance, doctor and briefing. Autofix no longer opens backup settings. Explicit backup setup remains available. Existing configured destinations retain backup-health checks.

Validation: full quality gate passed 172 Bats tests, 22 Python tests and 24 offline evaluation fixtures; shellcheck, Bash syntax, twin parity and diff checks passed. Local Homebrew reinstall and formula tests passed; installed CLIs matched source byte-for-byte. Offline fixtures do not measure live model quality.

Authorization: initial request covers local repairs; subsequent cpr explicitly authorizes commit, merge, push, production release and local release installation. Release scope is these CLI corrections and regression tests; no unrelated system or user-data changes.

## Recap
- Three maintenance defects corrected; missing-backup-destination notices removed.
- Both CLI variants verified; v6.31 is the release version for these changes.
