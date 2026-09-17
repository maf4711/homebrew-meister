# MeisterAI: execution, reports and Siri

Authorized on 2026-09-14: implement all six improvements from the code review.
Baseline: `380b1af` in `homebrew-meister`; the existing 50 CLI tests passed.

## Acceptance criteria

1. A persisted global preview setting applies at one command boundary. Commands
   with a proven preview implementation use it; other mutations are blocked.
   System settings and automation actions follow the same rule.
2. The dashboard explains the last actual run, repairs, verified repairs, open
   issues and measured storage. Previews and incomplete runs remain distinct.
   Comparisons use compatible completed actual runs, never a preview baseline.
3. Status probes do not block the main actor. Output is drained while subprocesses
   run. Timeout and cancellation wait for process termination; an active run
   cannot be silently replaced. SwiftUI observes nested service changes.
4. Learned repairs are keyed by failure context and operating-system version.
   Only verified successes are eligible for reuse, repeated failures suspend a
   candidate, and previews do not change repair evidence.
5. Native App Intents expose health and the latest report to Siri and Shortcuts.
   Both read the same report model as the GUI and never start maintenance.
6. CI runs shell lint, syntax, twin consistency, behavioral shell tests, native
   macOS tests and a Release build. Missing tools fail the gate.

## Execution authority and ownership

The user authorized source changes and local validation. No commit, push,
release, remote workflow dispatch, production installation or actual maintenance
is part of this implementation gate. Existing application/configuration data is
not used as a test fixture. No iOS Simulator is started.

The integration owner handles CI, shared Xcode configuration, cross-component
wiring and validation. Three workers use separate worktrees for execution,
CLI/reporting and dashboard/Intents. Changes are integrated only after each
worker relinquishes its scope. Coordination ledger:
`swarm-1789404011222-hjwfsr`. Memory lookup returned no matching pattern.

## Verification

```bash
bash scripts/check.sh
bash scripts/check-app.sh
```

The CLI gate is offline and supports Linux/macOS. The native gate uses the macOS
destination. Tests use temporary report directories and harmless subprocess
fixtures, with startup probes disabled in the test host. Release publication is
a separate action; a local green build does not imply a green remote CI run.

## Recap

Six authorized improvements are tracked above. Final evidence is recorded in
`docs/verification/2026-09-14-meisterai.md` after integration.
