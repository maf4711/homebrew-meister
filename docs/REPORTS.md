# Local maintenance reports and repair evidence

MeisterAI and meister keep their shared state in `~/.meister`. The CLI can use
an absolute `MEISTER_DIR` override without parent-directory components for
isolated fixtures. The desktop app and Siri read the normal user directory.

## Reports

Profiles, `autofix`, `ai` and `heal` produce a report. Other legacy subcommands
retain their existing output and do not replace the previous structured report.
Read-only inspections never acquire or release another maintenance run's lock.

The writer publishes a complete file under `runs/<run_id>.json`, then atomically
replaces `last.json`. The schema remains `meister.last/v1`; existing fields are
preserved and readers must tolerate additional fields.

| Field | Meaning |
| --- | --- |
| `run_id`, `ts` | Run identity and UTC report timestamp |
| `profile`, `twin` | Action/profile and CLI program used for compatible comparisons |
| `status` | `completed`, `partial` or `interrupted`; completed does not mean error-free |
| `dry_run` | Explicit distinction between a preview and an actual run |
| `report_kind` | `maintenance` or `execution_plan` |
| `planned_modules` | Module names in a full-profile preview; not detected problems |
| `fix`, `warn`, `err` | Counts of repair, warning and error messages |
| `verified_repair_count` | Successful module checks after repair attempts |
| `fixes`, `warnings`, `errors`, `would_fix` | Corresponding explanatory messages |
| `freed_bytes` | Measured allocated bytes of successfully removed single-link files, or `null` |
| `freed_bytes_scope` | `measured_file_removals` for the measured subset, otherwise `unknown` |
| `modules` | Module name, result/status and elapsed seconds |

Full-profile previews emit a module plan without invoking module bodies or
claiming discovered problems. They have no score, completed repairs, verification
count or storage savings. Targeted previews can report supported suggestions.
Preview reports never enter the legacy history of real maintenance results.

Removed file data is not a measurement of newly available APFS space: open
handles, snapshots and unmeasured cleanup commands can change that relationship.
Unknown measurements remain unknown. Reports lacking explicit status or preview
fields are displayed as legacy evidence with unknown execution type, and cannot
be used as completed actual baselines.

The app loads at most 400 archive files, rejects oversized/invalid reports,
deduplicates identities, and explains unreadable or stale evidence. Siri uses
the same model and reads saved reports; it does not perform a fresh system scan.

## Repair evidence

`learned_fixes.v2.tsv` contains nine tab-separated fields:

```text
module fingerprint os command successes failures consecutive suspended updated
```

The fingerprint represents the failed module's normalized output; the OS scope
includes version, build and architecture. Commands remain subject to the
existing allowlist. A candidate is reusable only after a successful module
verification in the same context. Three consecutive failures suspend it.
Suggestions and previews do not create verified evidence. Legacy two-column
entries are retained as suspended, unscoped evidence and never silently trusted.

The app checks the CLI source for `GUI-Execution-Contract: 1` before execution,
and separately requires declared preview capabilities. An older CLI requires an
update. Cancellation signals the process group and waits for the CLI process to
end; the GUI environment keeps GNU timeout children in that group. Services
deliberately started as independent daemons have their own lifecycle.
