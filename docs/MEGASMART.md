# SmartInbox in MeisterAI

A normal `MeisterAI` maintenance invocation runs SmartInbox by default in quick,
auto, deep and all profiles. It runs locally before network-dependent modules.
`MeisterAI -n` only includes it in the execution plan; it does not read Mail or
invoke the model. An explicit `MEGASMART_ENABLED=false` configuration opts out.
The twin `meister` shares the Mail module, which still uses Apple Foundation
Models rather than its general-purpose Ollama backend.

```sh
MeisterAI megasmart scan --json      # header candidates only
MeisterAI megasmart preview         # read and classify; persist a plan
MeisterAI megasmart run             # exactly one full cleanup (also alias default)
MeisterAI smartinbox status         # persisted jobs; no Mail/model access
MeisterAI smartinbox apply JOB_ID    # revalidate and execute an existing plan
MeisterAI smartinbox reconcile JOB_ID
```

The default account is the unique account with `foellmer@mac.com`. For another
account specify `--account NAME --mailbox INBOX --trash EXISTING_TRASH` explicitly.
Only existing same-account trash destinations are supported. No permanent delete,
trash emptying, sending, daemon, AufRaum GUI or direct IMAP connection is used.
Apple Mail starts hidden in the background when needed. Read failures can recover
its connection at most twice per run; moves are never automatically retried. The terminal/runner needs macOS Mail
Automation permission and read access to the local Mail index (Full Disk Access).

## Identification and classification

1. A read-only SQLite snapshot reads all older inbox headers, not merely subjects
   containing “newsletter”. The exact cutoff is seven days before this run.
2. Complete `.emlx` files are indexed once within the selected account and INBOX.
   The reader checks byte counts, MIME decoding, exact subject and index RFC identity.
   Missing, partial, ambiguous, attached or malformed content stays protected and
   is counted as `unavailable`. Preview never fetches it through Apple Mail.
   Local results can only establish KEEP. Every proposed move is re-read natively;
   changed model inputs receive a fresh FM classification and only native content
   fingerprints may authorize moves.
3. Saved keep decisions and fixed protections retain flagged, personal, financial,
   security and unclear mail. Eligible complete local bodies are decoded in batches of 25.
4. Apple Foundation Models reads complete subject, sender and body in isolated
   on-device sessions. Up to four isolated sessions share one helper process. Two helper processes run
   concurrently; results retain their original order. Typed
   categories are newsletter, personal, financial, security, other and uncertain.
   Only `newsletter` plus `safeToTrash=true` can become a move candidate.
5. No model tools or cloud fallback exist. Oversized content and uncertain model
   results stay. Unavailable runtimes or malformed results do not authorize moves.
6. A first move is verified before grouped moves of at most 100. Each packet has a
   durable pre-move journal. Current content fingerprint, age and flags are checked
   again before moving. Complete native ID/RFC snapshots establish source absence
   and unique target identity; only matched target bodies are fetched for verification.

Each scoped message read fetches its metadata and complete body as one Mail
properties record, avoiding seven separate property requests. Mailbox discovery
reads names without counting every mailbox. Reads of the next 25-message page overlap current classification. A shared native
queue serializes move-candidate confirmations and verification reads. Local file
decoding and the two FM workers remain parallel. At most
two pages are resident, one native read and two model processes are active.
Already-started work is drained before a failure releases the Mail lock. Only
read operations retry transient Apple-event connection errors (at most twice);
move operations are never retried automatically.

This removes per-message helper startup for native content reads and avoids fetching
full content/metadata for every unrelated message during verification. It does not
promise a wall-clock speedup until a complete live run is measured. The first model
pass can still be long. Only conservative KEEP decisions are cached against the complete content fingerprint.
They can never authorize a move; changed contents are classified again. Move approval
is never taken from this cache, and model availability is checked on every run.
Exact sender, subject and complete body matches can reuse KEEP across message IDs;
move decisions are always classified separately. Legacy ID-bound entries are
promoted only after their original contents match again.
The private SQLite cache updates only new or promoted KEEP entries in one
transaction per page. Existing JSON KEEP entries are migrated once without deleting
the old file. Neither message contents nor MOVE approvals enter the database.

## Runtime and state

Requires Python 3.9+, Node 22.13+ with `node:sqlite`, macOS 27+, a compatible selected Xcode 27 SDK,
and available Apple Intelligence. The dedicated Swift classifier is compiled locally
and its binary cached by source/toolchain/SDK hash. Mail content goes to it on stdin,
never in command arguments. Model preflight runs once per CLI invocation; every
Swift batch still independently rejects an unavailable model. The invariant schema
token count is calculated once per batch instead of once per message. Jobs are written privately under `~/.meister/mail`;
message bodies are not persisted. `--json` keeps stdout machine-readable, with
progress on stderr. Preview progress includes elapsed time and overlapping Mail/FM
stage durations, so these durations must not be added together. Results distinguish
`headersScanned`, `fmClassified`, `kept` and `unavailable`; completion does not imply
that unavailable contents were classified.

Only one CLI process owns the Mail journal at a time. Mutation also holds the
actual AufRaum bridge lock, preventing the desktop helper from starting concurrently. An existing AufRaum helper or
ambiguous AufRaum move blocks CLI mutation: finish/stop that workflow first. A stale CLI lock is recovered only under an exclusive recovery lock after its
PID is confirmed dead. The persisted move journal still fences unknown outcomes. Interrupted moving entries require `reconcile`; never retry them blindly.
Ctrl-C stops between packets and preserves uncertain outcomes.

## Verification and rollout

Use `bash scripts/check.sh` for twin parity, shell checks, offline Mail/CLI contracts,
and the existing maintenance/FM tests. Development commands can be run as
`bash ./MeisterAI.sh megasmart …`; the installed Homebrew binary is not changed by
editing this checkout. The existing Formula ships the Mail modules and declares Node.
The tested local source snapshot was installed through Homebrew on 2026-09-24.
The public release remains unchanged; reinstalling the public formula will replace
this local development snapshot. See `docs/verification/2026-09-24-megasmart-cli.md`.

Recap: Enabled by default; local Apple FM classifies contents; only verified moves
count as completed, and failures do not trigger a heuristic substitute.

## Small-page scheduling

Small classification pages are divided across both bounded FM workers (at most
four isolated sessions per helper). All fields, full bodies, prompt, schema and
source order remain unchanged. Native-protected candidates skip a redundant
second FM request; they remain KEEP without a stale local move classification.

Recap: Local CLI processing uses bounded concurrency and exact-content KEEP reuse;
only independently verified messages can move.
