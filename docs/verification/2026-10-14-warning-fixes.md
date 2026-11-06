# Local maintenance warning fixes — 2026-10-14

Installed locally over Meister 6.38, based on commit `d3aa3712aeca2a2a20035770e48c78783c27ba1c`. Source changes are uncommitted; no new release was published. The five unrelated FM/Ollama working-tree edits were preserved and hash-checked.

| Reported warning | Change and observed result |
| --- | --- |
| Claude.app has no verified unattended updater | Replaced the unconditional warning with a bounded, read-only check of the installed Anthropic signature and official release feed. Installed **2.37337.1** matches the feed. Invalid signatures, unknown versions, unavailable feeds and version differences remain warnings. App ownership and updater settings were preserved. |
| SmartInbox: 16,176 not reviewed | This was the remainder of one 500-message maintenance run, not cumulative review history. Budget continuation is now progress information. New jobs also record identity-scoped cumulative traversal coverage. Live inventory: **16,676** eligible messages, **12,231** previously traversed, **4,445** never traversed under the current policy. Traversal does not imply complete content review. |
| SmartInbox: 256 incomplete local contents | Fixed a subject-header folding mismatch; comparison against the old reader confirmed one parser recovery. A second message became locally readable during the investigation. Final installed-reader check: **2 readable, 254 still partial**, all 256 identities matched the current inventory. Partial content remains an explicit warning and cannot authorize moving mail. |
| Four sleep blockers | Short, specifically recognized Contacts/Siri and Apple account-storage assertions are explained as transient; persistent assertions remain warnings. OpenClaw's intentional caffeinate process is recognized only after matching its PID, executable and KeepAlive LaunchAgent. Unknown assertions and failed queries remain visible. Later checks observed additional transient RunningBoard and Handoff assertions; no system services were terminated. |
| 32 new Documents root entries | Reviewed 47 current root entries against a July baseline of 21 names. Accepted the current layout explicitly after verifying that the reviewed snapshot still matched. Saved the previous baseline at `/Users/a321/.meister/docs_order.baseline.backup.MfYkF6`. No documents were moved or deleted. |

The original native Mail read timed out. The new read-only `inspect JOB` command limits native helper execution to 15 seconds, stops on the first timeout, supports bounded batches and cancellation, and never creates move approvals. An installed diagnostic completed, but its native identity check did not match; that message remained protected. Apple Mail accepted a synchronization request for the selected account. A subsequent local check still found 254 partial messages, so synchronization was not reported as completed content recovery.

Current cumulative saved-history coverage also contains 6,780 unresolved previously traversed messages (unavailable, deferred or uncertain); the 254 count concerns only the original reported batch. No full mailbox review was claimed. Saved historical maintenance reports were not rewritten. The corrected reporting applies to subsequent runs.

Verification: `scripts/check.sh` passed **241 Bats, 136 Node and 35 Python tests**, plus **24 offline evaluation fixtures**, shellcheck, syntax and generated-twin parity checks. These fixture checks do not establish live model quality. Eight installed runtime files were backed up, replaced atomically per file, and hash-verified. Homebrew's Node shebang was preserved. Installed CLI help, syntax, Claude status, Documents baseline and local Mail reading were checked.

Backup and exact installation receipt: `/private/tmp/meister-warnings-backup-20261014/receipt.json`.
Test log: `/private/tmp/meister-warnings-check-20261014.log`.
Local Mail recheck: `/private/tmp/meister-warnings-installed-local-recheck.json`.

Recap: Local code and reporting defects are corrected and installed. Claude and Documents checks pass; genuine incomplete Mail content and active unexplained sleep assertions remain visible.
