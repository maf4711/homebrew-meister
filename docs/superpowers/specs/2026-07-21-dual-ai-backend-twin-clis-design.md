# Design: Twin CLIs — `meister.sh` (Ollama) + `meisterSiri.sh` (Apple FoundationModels)

Date: 2026-07-21
Repo: `homebrew-meister` (the tap)
Status: approved (2026-07-21) — orphan `~/bin/meisterSiri` **kept** per user decision

## Context / current state

- `meister.sh` **v6.0** is the full macOS maintenance CLI (~7,900 lines, 344 KB). Its AI
  backend is Apple Intelligence (FoundationModels) on-device, via an embedded Swift helper.
  The relevant seam is four functions — `_fm_helper_source()`, `ensure_fm_helper()`,
  `fm_available()`, `fm_query()` — plus ~6 call-sites (`ai_heal`, and lines ~1003, 4862,
  6703, 6757, 7857). Commit `7a91ab1` (v6.0) deleted the entire Ollama subsystem.
- A standalone orphan `~/bin/meisterSiri` (compiled Swift binary, "meisterSiri 1.0") plus
  `~/bin/meisterSiri.swift` (untracked, not in any repo) is a separate conversational REPL.
- `Formula/meister.rb` installs the script: `bin.install "meister.sh" => "meister"`.

## Goal

Provide **two twin CLIs, both versioned v6.0**, with identical maintenance functionality,
differing **only** in the AI backend:

| File | Installed as | AI backend |
|------|--------------|-----------|
| `meister.sh` | `meister` | **Ollama** (local, `localhost:11434`) |
| `meisterSiri.sh` | `meisterSiri` | **Apple FoundationModels** (on-device) |

The user explicitly chose two separate files over the DRY "one script + `MEISTER_AI_BACKEND`
flag" alternative. The DRY objection (344 KB maintained twice, drift risk) was raised once and
overruled — this is the accepted requirement.

## Non-goals (deliberate deletions — Elon)

- **No conversational REPL** in either twin. User chose "Zwillings-CLI", not "REPL drin".
  Both twins stay command-based (`meister ai`, `meister explain`), same as today.
- **No wholesale restore of the v5.26 Ollama subsystem.** Server lifecycle, model
  pull/cleanup, `module_ollama`, `PERF_CLEAN_OLLAMA` (~150 refs) stay deleted. Only the thin
  query path returns. meister does **not** manage the Ollama server — the user runs
  `ollama serve` (a background service) themselves.
- No change to any maintenance / heal / security / system module beyond the AI seam.

## Design — the only real delta is the AI backend

Both files are identical except the AI-backend section (~150 lines) and title/branding.
Crucially, **both twins keep the function names `fm_available` / `fm_query`**, so the ~6
call-sites need **zero** changes (minimal blast radius, Elon simplify).

### `meisterSiri.sh` (Apple) — near-verbatim copy of today's v6.0

Keeps `_fm_helper_source`, `ensure_fm_helper`, `fm_available`, `fm_query` unchanged.
Only branding differs (title line, `--version` label). This is essentially
`cp meister.sh meisterSiri.sh` + rebrand, since today's `meister.sh` is already the Apple
backend.

### `meister.sh` (Ollama) — replace the AI section with a thin HTTP path

```sh
MEISTER_OLLAMA_URL="${MEISTER_OLLAMA_URL:-http://localhost:11434}"
MEISTER_OLLAMA_MODEL="${MEISTER_OLLAMA_MODEL:-llama3.2}"

# same name → no call-site churn
fm_available() {
    curl -sf "$MEISTER_OLLAMA_URL/api/tags" >/dev/null 2>&1
}

fm_query() {                       # prompt on $1; response on stdout
    curl -sf "$MEISTER_OLLAMA_URL/api/generate" \
        -d "$(jq -Rn --arg m "$MEISTER_OLLAMA_MODEL" --arg p "$1" \
              '{model:$m, prompt:$p, stream:false}')" \
      | jq -r '.response'
}
```

`ai_heal`'s parsing contract is backend-neutral (it consumes plain text and gates commands
through the existing allowlist), so swapping Apple→Ollama needs no change there. The
allowlist / safety gate is untouched.

Removed from `meister.sh` (Ollama twin): `_fm_helper_source`, `ensure_fm_helper`, and the
`FM_ENABLED`/`FM_HELPER`/`xcrun swiftc` machinery — replaced by the two functions above.

New dependencies for the Ollama twin: `jq` (safe JSON encoding of arbitrary prompt text) and
`curl` (always present). Add `depends_on "jq"` in the Formula.

### Versioning

Both carry `v6.0` in the header and `--version`. Distinguished by the title line:
`meister v6.0 (Ollama)` vs `meisterSiri v6.0 (Apple Intelligence)`.

Note: v6.0's original headline was "Ollama replaced by Apple Intelligence", so labelling the
Ollama twin "v6.0" is semantically odd but is what was requested — honored as-is.

### Distribution

`Formula/meister.rb`: add `bin.install "meisterSiri.sh" => "meisterSiri"` next to the existing
`meister` install, and `depends_on "jq"`. Both land on PATH after `brew upgrade`.

## Resolved decision — orphan kept

The orphan `~/bin/meisterSiri` binary + `.swift` + shell alias stays **as-is**. It is a
distinct, working conversational REPL (multi-turn Apple-Intelligence chat) and is out of
scope for this change. No deletion, no touching `~/bin`. The twin CLIs do not replace it.

## Test plan (per twin)

- `--version` → shows `v6.0` + correct backend label.
- Availability: Apple → model availability check; Ollama → `curl /api/tags` (requires
  `ollama serve` running).
- One-shot: `ai` returns text; `explain <text>` returns an explanation.
- `ai_heal` dry-run exercises `fm_available` / `fm_query`.
- Graceful degrade: backend absent (Ollama down / Apple Intelligence off) → AI features skip,
  maintenance modules still run.
- Regression: `diff meister.sh meisterSiri.sh` → only the AI section + branding differ.

## Rollout

1. Worktree off the tap repo (`homebrew-meister`).
2. `meisterSiri.sh` = copy of current v6.0 Apple, rebranded.
3. Convert `meister.sh` AI section → thin Ollama path (keep `fm_*` names).
4. Update `Formula/meister.rb` (install + `depends_on "jq"`).
5. Test both twins.
6. Commit, bump the tap. (Orphan `~/bin/meisterSiri` left untouched.)
