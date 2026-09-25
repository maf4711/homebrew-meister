# Local SmartInbox verification — 2026-09-24

Installed through Homebrew without commit, push or public release. Version remains
6.32; archive SHA256 identifies this local development build:
`a57b2b15d18b8cc92754b3d45a44ff9ab081edab47a9c84798d27f84e045fc51`.

Installed location: `/opt/homebrew/Cellar/meister/6.32`. Both CLI files, dispatcher
and all Mail modules match source, except Homebrew's expected Node shebang rewrite.
The temporary tap formula override was restored; tap checkout is clean.
Installed alias help and read-only status pass. No config opt-out exists.

Validation: `bash scripts/check.sh` passed shell checks, twin parity, Bats,
54 Node tests, 22 Python tests and both offline FM fixture suites. After renaming
the native resource to `.applescript`, all eight native tests passed again.

Component measurements:
- Local index: 16,923 inbox headers; 16,803 older candidates; 151 ms.
- Complete native identity snapshot: 16,923 messages; warm run 2,030 ms.
  The previous ranged projection timed out after 120 seconds.
- Two real messages: content read 2,547 ms; actual on-device Apple Foundation Models
  classification 3,766 ms. Both identified as newsletters. No moves executed.
- Offline engine fixture: 107 verified moves in batches of 1 + 100 + 6,
  with journaling, content revalidation and post-move identity checks.

These are component measurements, not a complete live cleanup benchmark. Neither
full live cleanup nor normal maintenance was executed. Initial model classification
can take time. Subsequent runs cache only KEEP decisions, never move authorization.

## Bounded parallel processing follow-up

The first full live run stopped after 275 older messages when Apple Mail exited
(connectionInvalid, -609); no moves had begun. Mail was restarted in the background.

The follow-up uses two classifier worker processes plus one native page read ahead.
63 Node tests passed, including worker bounds/order/draining, pipeline failure paths,
and read-only retry limits. Mutations retain the existing exclusive journal lock.

Actual on-device synthetic benchmark, eight identical gardening newsletters:
- Serial helper processes: 11,159 ms.
- Two concurrent helper processes: 8,523 ms (23.6% less elapsed time).
- Both runs returned eight newsletter classifications and conservative KEEP decisions.

This is a component benchmark; full real-inbox elapsed time remains unmeasured.

Parallel build installed through Homebrew from local archive SHA256
`cd8efcf73348c4584846978867c33e23d2795039ca1e80b6521544f940238219`.
Installed Mail module bytes match the tested source. The tap override was restored.
Full cleanup restarted with progress written privately to
`~/.meister/mail/parallel-run-progress.log` and final JSON to
`~/.meister/mail/parallel-run-result.json`; completion is not yet established.

## Native I/O efficiency follow-up

One scoped Mail properties request replaces seven individual property reads.
Three real messages, alternating baseline/candidate/candidate/baseline, with every
returned field privately compared for equality:
- Baseline: 886 ms and 893 ms.
- Candidate: 735 ms and 757 ms (about 16% lower mean elapsed time).
- Isolated two-message properties step: 463 ms versus 1,441 ms.

The fixed 25-ID OR query was not adopted: cold performance regressed despite a
warm-run improvement. Model workers remain capped at two: four workers improved
one 16-message synthetic contention test by only 3%.

Mailbox discovery omits unused per-mailbox message counts. Schema token counting
is once per batch; explicit model preflight is once per run. Every Swift batch
still checks actual model availability, with no cloud fallback. Preview progress
reports overlapping stage timings instead of implying their sum is elapsed time.

Optimized source installed through Homebrew from archive SHA256
`0bd8e47ece56be4b5a4e738c1ee24f10bcadb9e277611f55f3e01522004c6e6f`.
All installed Mail modules and dispatcher match source (Homebrew Node shebang
normalization only). 64 Node tests pass; AppleScript compiles. Full cleanup restarted
with private progress at `~/.meister/mail/fast-run-progress.log` and final result at
`~/.meister/mail/fast-run-result.json`. Completion remains to be established.

## Direct local content preview

Native content reads accounted for 150 seconds versus 3 seconds of FM time after
200 messages. A later native run stopped because Mail crashed: launchd recorded
SIGSEGV for Mail PID 98180 at 12:30:36. Moves had not begun.

Complete account/INBOX EMLX files now feed KEEP-only preview classification.
Each prospective move receives a native scoped reread, matching stable RFC ID,
current protection checks, and fresh FM classification if model inputs differ.
Only native fingerprints authorize moves. Partial, malformed, ambiguous or
attachment-bearing files fall back to native Mail. No bodies are persisted.
The shared native queue prevents fallback and confirmation from competing.
Read-only background recovery is capped at two restarts; mutations never retry.

Measured 25-message sample selected from complete-file candidates: 20 decoded
locally, five required real native fallback. All 25 IDs, RFC IDs and subjects
matched the native comparison. HTML/MIME text is intentionally not byte-identical
to Mail rendering, which is why native confirmation is mandatory before moves.

- Native first: 24,479 ms; hybrid second: 3,974 ms.
- Reverse order: hybrid first 2,678 ms; native second 18,526 ms.
- One-time local file map: 257 ms; decoding component: 103 ms for the sample.

This is a read-stage benchmark on a favorable complete-file sample, not an
end-to-end or whole-inbox speedup claim. 82 Node tests pass, including MIME decoding,
identity mismatch, fallback, local KEEP protection, native FM reclassification,
serialized native operations and recovery limits. Read-only independent review
found no blocking defect. Full live cleanup remains uncompleted.

Direct-content build installed through Homebrew from archive SHA256
`11d6311c07f7f072657ce6d29fa54884a62737534f6c8bd6b1eb83192a3354ad`.
Installed source bytes verified and tap formula restored. Full cleanup restarted;
private progress is `~/.meister/mail/direct-run-progress.log` and final JSON is
`~/.meister/mail/direct-run-result.json`. This receipt does not assert completion.

## Strict local preview and incremental KEEP cache

The direct-content run reached 525 older messages but timed out during native
preview fallback. Preview now never fetches missing/partial/invalid contents.
These entries remain protected, without a move-capable fingerprint, and are
reported separately as unavailable. Native confirmation before moving remains
mandatory. The original Apple-FM schema/policy was retained.

Actual mixed first-1,000-message metadata sample: 3,901 ms including file mapping
and decoding, with 435 complete local reads, 565 explicitly unavailable entries,
zero native content reads and no model calls. This is a reading/availability
measurement, not a classification or cleanup benchmark, and coverage differs
from native fallback because missing content is deliberately not fetched.

Private SQLite KEEP cache replaces repeated full-JSON rewrites. Synthetic
source-bound benchmark with 10,000 existing entries and 100 pages of 25:
JSON persistence 998 ms versus SQLite 109 ms; initial migration 26 ms.
276 existing live KEEP entries migrated successfully without model invocation.
No bodies or MOVE approvals are stored; prior JSON remains untouched.

Strict-local build installed through Homebrew from archive SHA256
`8ca5a95dfb3b5f8687568931e109bf65c435410c0a22e581af7b7c1e276c71a1`.
Installed modules, dispatcher and both CLI twins match the tested source. Tap
formula restored. Full `scripts/check.sh` passed: shell/twin checks, 183 Bats tests,
87 Node tests, 22 Python tests and both offline evaluation fixture sets.
Private progress: `~/.meister/mail/strict-run-progress.log`; final JSON:
`~/.meister/mail/strict-run-result.json`. Full completion is not asserted here.

## Exact-content KEEP reuse across message IDs

Source candidate keeps the unchanged Apple FM prompt/schema and reuses only KEEP
for exact sender + subject + complete body matches across IDs. Move decisions are
never cached. Legacy ID keys promote only after observing the matching contents.
Already cached content hits do not open write transactions.

Focused suite: 89 Node tests passed, including changed sender/subject/body cache
misses, restart persistence, and repeated move decisions always invoking the model.
Independent read-only review found no unsafe move reuse.

Synthetic cache benchmark: 2,000 rows with 20 distinct complete contents, all KEEP.
Baseline dispatched 2,000 model rows (85 ms cache/fixture time), candidate 20
(13 ms). The model was a fixture: these timings are NOT Apple FM throughput.
Baseline keep-cache.mjs SHA256:
`40a2cdfa0fa3196f7ecf4e37bdf7d2d562b0d2c82b4a60ad272dd234f53f7fd6`.
Candidate keep-cache.mjs SHA256:
`396ce4806607cb78a990d447af856069f5bc70cdafcb65c5a8b696bbebccc33c`.

Real read-only sample: first 1,000 local EMLX files yielded 629 complete decodes;
575 matched current INBOX index subject/RFC. Eleven repeated exact tuples give
an upper bound of 1.91% avoidable FM requests in that sample; KEEP subset unknown.
No repeated byte-identical MIME parts were found, so MIME dedup was not adopted.
No real overall speedup is asserted. Contents were neither logged nor persisted.

Candidate remains source-only while the installed strict-local run is active;
installation is deferred to avoid replacing executing helper resources. That run
continues with the previously verified installed snapshot.

Recap: Exact-content KEEP reuse implemented and tested; active cleanup left
running. Candidate not installed and complete-inbox cleanup not yet verified.

## Small-page efficiency follow-up

Completed installed baseline job: 16,812 older messages, 7,343 seconds, zero moves.
8,043 rule-protected; 6,090 unavailable; 2,679 final model KEEP decisions. Of 862
uncertain decisions, 357 context overflow, 22 generation failures, 32 cached and
451 model-authored. Ten local candidates reached native reclassification and all
lost move approval. No conclusion about deletion safety follows from model prose.

Candidate divides small pages across both existing workers instead of putting up
to four rows into one serial helper. No prompt, schema, context or content changes.
A native protection also avoids unnecessary reclassification and removes the stale
local decision. This latter optimization would have saved zero calls in the
observed baseline job; its behavior is covered by regression tests.

Actual Apple FM synthetic four-message evaluation in ABBA order:
baseline 4,085 / 4,171 ms; candidate 3,714 / 3,671 ms. Mean improvement 10.55%.
Categories and safeToTrash values matched across all four trials. Inputs covered
newsletter, personal, financial and adversarial security content. All decisions
were KEEP, including the newsletter: this is speed evidence, not proof of useful
newsletter recall or complete classifier quality. Whole-inbox speedup not measured.

Source hashes:
- fm-classifier.mjs: 904e5d55e3df57339a0c3159120fd6bfa73133142119dd0125311f08584bf5ca
- engine.mjs: d1af16cb325490e9bc4a16f6854fb855f4b955db8ba5a0617869e9e6248224ce
- keep-cache.mjs: 396ce4806607cb78a990d447af856069f5bc70cdafcb65c5a8b696bbebccc33c

Recap: Small-page scheduling measured faster; no Mail mutations performed during
this optimization. Newsletter approval quality remains unresolved.

Installed locally through Homebrew from snapshot SHA256
`fc8a10abc28d8004201c5e280bfd35a9dc14c7304f4d3334f896339b7b9967f9`.
All installed mail-module and CLI twin bytes verified; tap formula restored and
clean. Full checks passed: 183 Bats, 90 Node, 22 Python tests, shell/twin checks,
and both offline fixture sets. Installed read-only status command succeeded.

Recap: Performance candidate and prior content-cache improvement are installed.
No new full inbox run or Mail mutation was started; classifier recall remains an
explicit limitation.
