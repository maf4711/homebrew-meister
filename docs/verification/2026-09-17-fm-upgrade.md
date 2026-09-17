# MeisterAI Foundation Models implementation — 2026-09-17

Implemented on top of the preceding local log fixes; no release, installation or
real maintenance run was performed. The earlier unrelated Meister app release
work remains isolated and is not part of these changes.

## Delivered

- Structured diagnosis: cause, supplied evidence references, missing facts,
  next read-only check, fixed action ID and no arbitrary parameters.
- Three approved actions: reset QuickLook cache, restart Finder, restart Dock.
  Mapping to absolute executables is outside the model. Unknown/free-shell
  responses fail closed. Learned AI commands must pass the same catalog.
- Four read-only context tools expose collected Brew-path, session-permission,
  selected service and saved-report facts. Missing observations remain unknown.
- Bounded redacted evidence preserves module, exit information, previous failed
  attempt and OS. Token budgeting includes instructions, schema, tools, probe
  results and response. A failed prior action cannot be repeated.
- Local-first AI-Heal routing, targeted PCC escalation for unresolved complete
  evidence, explicit local/PCC configuration, bounded deadlines, typed errors,
  actual-model/token/latency audit metadata. Guardrail failures do not escalate.
- `ai report` renders factual saved outcomes with references, distinguishing
  reported actions from verified repairs. Reports link saved diagnosis artifacts.
- Offline and opt-in live evaluation with a sanitized 14-case corpus. No model
  output is accepted as evidence of an executed or verified repair.

## Evidence

- Full CLI gate: **145 Bats tests passed**, including Swift 6 helper compilation,
  eight native helper contract tests, preview isolation, mapped-action execution
  with mocked commands, reporting, typed errors and twin parity.
- Python evaluation transport regression: passed.
- Offline corpus validation: **14/14**. These are reference responses, not model
  quality measurements. Included in `scripts/check.sh` for future regressions.
- Real on-device evaluation: **14/14** valid schemas, evidence-ID checks and
  expected action/no-fix decisions; **12/14** diagnosis-term checks passed.
  Results are retained in [live-system.json](fm-20260917/live-system.json) and
  [offline-harness.json](fm-20260917/offline-harness.json).
- ShellCheck, Bash syntax and `git diff --check` passed.

The live failures were `brew_outside_path` and `model_unavailable`: the first
explained the missing command but introduced unnecessary permission uncertainty;
the second invented a security restriction. Correct reference IDs establish that
cited records exist, not that the model's interpretation is true. Keyword matching
is a limited regression signal, not a semantic accuracy benchmark. These findings
are retained rather than counted as passing or hidden through retries.

PCC capability and routing were tested without transmitting fixtures to PCC.
No cloud-generation quality claim is made. No repair was executed on the real
machine, so live repair-success outcomes remain unmeasured. Suggest-only remains
the default; execution still requires opt-in and subsequent module verification.

## Reproduce

```sh
bash scripts/check.sh
xcrun swiftc -swift-version 6 -parse-as-library -O lib/fm/MeisterFM.swift -o /tmp/meister-fm-review
python3 scripts/evaluate-fm.py --live --helper /tmp/meister-fm-review \
  --include-responses --output /tmp/meister-fm-live-review.json
```

The second command requires the macOS 27 SDK, and live evaluation requires an
available on-device Apple Intelligence model. Model answers can vary between runs
and OS/model updates. Re-run live evaluation after updates; do not equate successful
API calls with useful diagnoses.

Recap: all proposed capabilities implemented; deterministic checks pass, with
explicitly recorded limits on live diagnosis quality and untested real repairs.
