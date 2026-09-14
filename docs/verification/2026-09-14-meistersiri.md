# MeisterSiri implementation verification — 2026-09-14

All six approved improvements are implemented in the isolated branch
`codex/meister-improvements-20260914`, based on `380b1af`. The source remains
uncommitted for review. No release, remote workflow dispatch, installation into
Applications/Homebrew, or real maintenance run was performed.

## Delivered behavior

1. A persisted global preview setting reaches one command policy. Supported
   actions receive their preview flag; unsupported mutations are blocked.
   Full-profile previews return an explicit module plan without executing
   maintenance modules. CLI contract checks happen before running the script.
2. The new results dashboard distinguishes actual, preview, legacy and
   interrupted reports. It shows repair messages, verified module retests,
   open issues, measured file removals and compatible previous-run comparisons.
3. Process execution drains output concurrently, keeps probes off the main
   actor, enforces deadlines and signals the process group on cancellation.
   The UI stays busy until the CLI exits. GNU timeout uses the inherited group
   in GUI runs. Nested observable services now update SwiftUI correctly.
4. Repair evidence is scoped to module, normalized failure and OS context.
   Only successful module retests establish reusable repairs; three consecutive
   failures suspend a candidate. Legacy and preview evidence is not trusted.
5. Two native App Intents read the same saved reports as the dashboard:
   Mac health and the last maintenance report. Missing, old and incomplete
   evidence is explained rather than presented as a live check.
6. CI contains Linux/macOS shell gates plus macOS unit tests and a universal
   Release build. The gates fail when required tools are missing. Twin parity
   checks no longer execute the maintenance CLI.

## Local validation

- CLI gate: 89 Bats tests passed, including all-profile preview isolation,
  report serialization, changing-failure repair contexts, and concurrent lock
  recovery after forced termination. ShellCheck, syntax and twin parity passed.
- Native gate: 36 XCTest tests passed; Release build succeeded for arm64 and
  x86_64. Focused coverage includes policy bypass prevention, legacy CLI
  blocking, changed-source invalidation, output streaming, timeout, cancellation
  of GNU timeout descendants, corrupt/legacy reports and Siri responses.
- Cross-component test: the real Bash report serializer writes only temporary
  data, then the Swift repository, dashboard and Siri consume it. No maintenance
  operation runs. The dashboard was rendered in an AppKit host and visually
  inspected; an empty ImageRenderer output was replaced with a real view capture.
- App bundle: ad-hoc signature verified; German development language and
  extracted metadata contain both intents and four German shortcut phrases.
- Workflow: actionlint and `git diff --check` passed. Remote GitHub CI has not
  run for this unpushed branch.
- Responsiveness experiment: the same 0.4-second subprocess delayed a 50 ms
  main-actor heartbeat to 0.468 seconds in the baseline, versus 0.050 seconds
  with the new runner. This is one controlled local measurement, not an
  end-to-end maintenance speed claim.

Reproduction commands from the repository root:

```bash
bash scripts/check.sh
bash scripts/check-app.sh
actionlint
git diff --check
```

Environment: Xcode 26.6 (`17F113`), macOS SDK 26.5, XcodeGen 2.46.0.
No iOS Simulator was started. Test fixtures use temporary report directories,
explicit harmless commands and disabled automatic startup checks.

## Evidence and limits

Local evidence is retained under `app/MeisterSiri/build/verification/`:
`shell-check.log`, `native-check.log`, `dashboard.png`, `responsiveness.json`,
`source-snapshot.tar.gz` and `source-receipt.json`. The receipt binds final changed and untracked source
files by SHA-256 rather than claiming the baseline commit contains the changes.
The source snapshot contains those files; together with the recorded baseline
commit it identifies the tested source state.
The built app is available at `app/MeisterSiri/dist/MeisterSiri.app`.

Spoken Siri dispatch was not exercised. The test host logged an unavailable
`com.apple.linkd.autoShortcut` connection; metadata extraction and response
tests passed, but actual Siri discovery must be checked in a normal installed
app session. The local app requires the corresponding updated CLI; an older
installed CLI is blocked with an update message.

Structured reports cover profiles, autofix, ai and heal. Other legacy commands
retain their prior output. Measured file removals are a subset, not total free
APFS capacity. Process tests cover controlled descendants; independently
daemonized services have their own lifecycle. Format and evidence semantics
are documented in [REPORTS.md](../REPORTS.md).
