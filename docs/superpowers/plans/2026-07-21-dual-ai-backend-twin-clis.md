# Dual AI-Backend Twin CLIs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship two v6.0 twin CLIs in the `homebrew-meister` tap — `meister.sh` (AI backend = Ollama) and `meisterSiri.sh` (AI backend = Apple FoundationModels) — that are byte-identical outside two clearly-marked divergent regions.

**Architecture:** Both twins keep the function names `fm_available` / `fm_query`, so the ~6 existing call-sites (`ai_heal` etc.) are untouched. The Apple twin (`meisterSiri.sh`) is today's `meister.sh` verbatim + rebrand. The Ollama twin (`meister.sh`) swaps the embedded-Swift-helper block for a thin `curl localhost:11434` path. Two `# ===== TWIN: … =====` marker regions (branding + AI backend) fence off every intended difference; a symmetry test asserts nothing else diverges (drift guard for the accepted duplication).

**Tech Stack:** Bash, `curl`, `jq`, `shellcheck`. On-device Apple FoundationModels (Apple twin, unchanged). Local Ollama HTTP API (Ollama twin).

**Spec:** `docs/superpowers/specs/2026-07-21-dual-ai-backend-twin-clis-design.md`

---

## File structure

- Modify: `meister.sh` — becomes the **Ollama** twin. Add TWIN markers; replace vars `221-222` and the AI block `658-720` with the thin Ollama backend.
- Create: `meisterSiri.sh` — the **Apple** twin. Copy of current `meister.sh` (Apple) + TWIN markers + branding.
- Modify: `Formula/meister.rb` — install `meisterSiri.sh`; `depends_on "jq"`.
- Create: `tests/helpers.sh` — tiny assert + function-extraction helpers.
- Create: `tests/test_ollama_backend.sh` — unit-tests the Ollama `fm_available`/`fm_query` with a stubbed `curl`.
- Create: `tests/test_twin_symmetry.sh` — asserts the twins differ ONLY inside TWIN regions.
- Create: `tests/run.sh` — runs all tests + shellcheck.

**Marker convention** (identical in both files; the region *content* differs):

```sh
# ===== TWIN:AI-BACKEND (divergent — do NOT sync between twins) =====
... backend code ...
# ===== /TWIN:AI-BACKEND =====
```

Two region names are used: `TWIN:BRANDING` and `TWIN:AI-BACKEND`. The symmetry test strips every line from `# ===== TWIN:` to the matching `# ===== /TWIN:` (inclusive) out of both files and diffs the remainder — it must be empty.

---

## Task 0: Worktree + branch

**Files:** none (setup only)

- [ ] **Step 1: Create an isolated worktree off the tap repo**

Run:
```bash
cd ~/Developer/homebrew-meister
git worktree add ../homebrew-meister-twins -b feat/dual-ai-backend-twins
cd ../homebrew-meister-twins
```
Expected: new worktree on branch `feat/dual-ai-backend-twins`. All remaining paths are relative to this worktree root.

- [ ] **Step 2: Confirm baseline is green**

Run: `shellcheck -x meister.sh && echo OK`
Expected: `OK` (baseline lints clean before we touch anything).

---

## Task 1: Test harness

**Files:**
- Create: `tests/helpers.sh`
- Create: `tests/run.sh`

- [ ] **Step 1: Write `tests/helpers.sh`**

```sh
# tests/helpers.sh — minimal assert + extraction helpers (no bats dependency)
# shellcheck shell=bash

# extract_fn NAME FILE — prints the shell function NAME's definition from FILE.
# Assumes `name() {` on one line and a closing `}` at column 0.
extract_fn() {
    awk -v fn="$1" '
        $0 ~ "^"fn"\\(\\) \\{" { inside=1 }
        inside { print }
        inside && /^\}/ { exit }
    ' "$2"
}

assert_eq()   { [ "$1" = "$2" ] || { echo "FAIL: '$1' != '$2'  ($3)"; exit 1; }; echo "ok: $3"; }
assert_ok()   { if "$@"; then echo "ok: $* → success"; else echo "FAIL: expected success: $*"; exit 1; fi; }
assert_fail() { if "$@"; then echo "FAIL: expected failure: $*"; exit 1; else echo "ok: $* → failure"; fi; }
assert_empty(){ [ -z "$1" ] || { echo "FAIL: expected empty, got '$1'  ($2)"; exit 1; }; echo "ok: $2"; }
```

- [ ] **Step 2: Write `tests/run.sh`**

```sh
#!/usr/bin/env bash
# tests/run.sh — run all twin tests + shellcheck
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR" || exit 1

fail=0
echo "== shellcheck =="
shellcheck -x meister.sh || fail=1
[ -f meisterSiri.sh ] && { shellcheck -x meisterSiri.sh || fail=1; }

for t in tests/test_*.sh; do
    [ -e "$t" ] || continue
    echo "== $t =="
    bash "$t" || fail=1
done

[ "$fail" = 0 ] && echo "ALL GREEN" || { echo "SOME RED"; exit 1; }
```

- [ ] **Step 3: Make runnable + smoke it**

Run:
```bash
chmod +x tests/run.sh
bash tests/run.sh
```
Expected: shellcheck section runs clean; no `test_*.sh` yet so it prints `ALL GREEN`.

- [ ] **Step 4: Commit**

```bash
git add tests/helpers.sh tests/run.sh
git commit -m "test: add minimal bash test harness for twin CLIs"
```

---

## Task 2: Symmetry test (RED) → create Apple twin `meisterSiri.sh` (GREEN)

**Files:**
- Create: `tests/test_twin_symmetry.sh`
- Create: `meisterSiri.sh`
- Modify: `meister.sh` (add TWIN markers only — still Apple in this task)

- [ ] **Step 1: Write the failing symmetry test**

```sh
#!/usr/bin/env bash
# tests/test_twin_symmetry.sh — twins may differ ONLY inside TWIN regions.
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"

[ -f "$DIR/meisterSiri.sh" ] || { echo "FAIL: meisterSiri.sh missing"; exit 1; }

strip_twin() {  # remove every TWIN region (markers inclusive) from stdin
    awk '
        /^# ===== TWIN:/      { skip=1; next }
        /^# ===== \/TWIN:/    { skip=0; next }
        !skip                 { print }
    ' "$1"
}

a="$(strip_twin "$DIR/meister.sh")"
b="$(strip_twin "$DIR/meisterSiri.sh")"
if [ "$a" = "$b" ]; then
    echo "ok: twins identical outside TWIN regions"
else
    echo "FAIL: twins diverge outside TWIN regions:"
    diff <(printf '%s' "$a") <(printf '%s' "$b") | head -40
    exit 1
fi
```

- [ ] **Step 2: Run it — expect RED**

Run: `bash tests/test_twin_symmetry.sh`
Expected: FAIL — `meisterSiri.sh missing`.

- [ ] **Step 3: Create `meisterSiri.sh` as a copy of the current (Apple) `meister.sh`**

Run:
```bash
cp meister.sh meisterSiri.sh
```

- [ ] **Step 4: Add the `TWIN:BRANDING` region to BOTH files**

In `meister.sh`, immediately below the shebang line, insert:
```sh
# ===== TWIN:BRANDING (divergent — do NOT sync between twins) =====
MEISTER_LABEL="meister v6.0 (Ollama)"
# ===== /TWIN:BRANDING =====
```
In `meisterSiri.sh`, at the identical location, insert:
```sh
# ===== TWIN:BRANDING (divergent — do NOT sync between twins) =====
MEISTER_LABEL="meisterSiri v6.0 (Apple Intelligence)"
# ===== /TWIN:BRANDING =====
```

- [ ] **Step 5: Wrap the Apple backend in a `TWIN:AI-BACKEND` region in BOTH files**

The Apple backend spans two spots. In BOTH `meister.sh` and `meisterSiri.sh`, wrap them identically (both are still Apple at this point):

Around the vars (currently `FM_ENABLED=true` / `FM_HELPER=…`, lines ~221-222) — put the opening marker on the line above `FM_ENABLED=true` and the closing marker on the line below `FM_HELPER=…`:
```sh
# ===== TWIN:AI-BACKEND (divergent — do NOT sync between twins) =====
FM_ENABLED=true
FM_HELPER="$MEISTER_DIR/meister-fm"          # compiled Swift helper (lazy-built, cached)
# ===== /TWIN:AI-BACKEND =====
```

Around the function block (currently the `# 3. APPLE INTELLIGENCE …` header at ~658 through the end of `fm_query()` at ~720) — opening marker on the line above `# 3. APPLE INTELLIGENCE`, closing marker on the line below `fm_query`'s closing `}`:
```sh
# ===== TWIN:AI-BACKEND (divergent — do NOT sync between twins) =====
# 3. APPLE INTELLIGENCE (FoundationModels) — replaces Ollama
# ... entire existing block: _fm_helper_source, ensure_fm_helper,
#     fm_available, fm_query — UNCHANGED ...
fm_query() {
    ensure_fm_helper || return 1
    printf '%s' "$1" | "$FM_HELPER" 2>/dev/null
}
# ===== /TWIN:AI-BACKEND =====
```

Both files receive byte-identical marker lines and (for now) byte-identical content.

- [ ] **Step 6: Run symmetry test — expect GREEN**

Run: `bash tests/test_twin_symmetry.sh`
Expected: `ok: twins identical outside TWIN regions` (only the BRANDING region differs; it's stripped).

- [ ] **Step 7: Lint both**

Run: `shellcheck -x meister.sh meisterSiri.sh && echo OK`
Expected: `OK`.

- [ ] **Step 8: Commit**

```bash
git add meister.sh meisterSiri.sh tests/test_twin_symmetry.sh
git commit -m "feat: add meisterSiri.sh (Apple twin) + TWIN markers + symmetry test"
```

---

## Task 3: Ollama backend unit test (RED)

**Files:**
- Create: `tests/test_ollama_backend.sh`

- [ ] **Step 1: Write the Ollama backend unit test**

```sh
#!/usr/bin/env bash
# tests/test_ollama_backend.sh — unit-tests the Ollama fm_available/fm_query
# by extracting them from meister.sh and stubbing curl. No live Ollama needed.
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$DIR/tests/helpers.sh"

# Load the two backend functions from the real script into this shell.
lib="$(mktemp)"
{
    echo 'MEISTER_OLLAMA_URL="http://ollama.test"'
    echo 'MEISTER_OLLAMA_MODEL="testmodel"'
    extract_fn fm_available "$DIR/meister.sh"
    extract_fn fm_query     "$DIR/meister.sh"
} > "$lib"
# shellcheck source=/dev/null
. "$lib"

# Stub curl: /api/tags honours $CURL_TAGS_OK; /api/generate echoes canned JSON.
curl() {
    local args="$*"
    case "$args" in
        *"/api/tags"*)     [ "${CURL_TAGS_OK:-1}" = 1 ] && return 0 || return 22 ;;
        *"/api/generate"*) printf '%s' '{"response":"PONG"}'; return 0 ;;
    esac
    return 1
}

# fm_available: true when the tags endpoint is reachable, false otherwise.
CURL_TAGS_OK=1 assert_ok   fm_available
CURL_TAGS_OK=0 assert_fail fm_available

# fm_query: returns the model's .response text.
out="$(fm_query 'ping')"
assert_eq "$out" "PONG" "fm_query returns .response"

echo "test_ollama_backend: PASS"
```

- [ ] **Step 2: Run it — expect RED**

Run: `bash tests/test_ollama_backend.sh`
Expected: FAIL. `meister.sh` is still the Apple twin, so the extracted `fm_available`/`fm_query` don't call `curl` — `fm_query 'ping'` does not return `PONG` (assert_eq fails), and `fm_available` ignores the curl stub.

---

## Task 4: Swap `meister.sh` AI backend → Ollama (GREEN)

**Files:**
- Modify: `meister.sh` (content INSIDE the two `TWIN:AI-BACKEND` regions only)

- [ ] **Step 1: Replace the vars region content in `meister.sh`**

Replace the vars `TWIN:AI-BACKEND` region body (the `FM_ENABLED` / `FM_HELPER` lines) with:
```sh
# ===== TWIN:AI-BACKEND (divergent — do NOT sync between twins) =====
MEISTER_OLLAMA_URL="${MEISTER_OLLAMA_URL:-http://localhost:11434}"
MEISTER_OLLAMA_MODEL="${MEISTER_OLLAMA_MODEL:-llama3.2}"
# ===== /TWIN:AI-BACKEND =====
```

- [ ] **Step 2: Replace the function region content in `meister.sh`**

Replace the function `TWIN:AI-BACKEND` region body (the whole `# 3. APPLE INTELLIGENCE …` block: `_fm_helper_source`, `ensure_fm_helper`, `fm_available`, `fm_query`) with:
```sh
# ===== TWIN:AI-BACKEND (divergent — do NOT sync between twins) =====
# 3. OLLAMA (local HTTP) — on-device LLM via a running `ollama serve`.
# meister does NOT manage the server lifecycle; it only queries it.
fm_available() {
    curl -sf --max-time 2 "$MEISTER_OLLAMA_URL/api/tags" >/dev/null 2>&1
}

# Prompt on $1 (or stdin if $1 is empty); model response on stdout, empty on error.
fm_query() {
    local prompt="$1"
    [ -z "$prompt" ] && prompt="$(cat)"
    curl -sf --max-time 120 "$MEISTER_OLLAMA_URL/api/generate" \
        -d "$(jq -Rn --arg m "$MEISTER_OLLAMA_MODEL" --arg p "$prompt" \
              '{model:$m, prompt:$p, stream:false}')" \
      | jq -r '.response // empty'
}
# ===== /TWIN:AI-BACKEND =====
```

Note: `_fm_helper_source` and `ensure_fm_helper` are intentionally gone from the Ollama twin. Verify no *other* reference survives (next step).

- [ ] **Step 3: Verify no dangling Apple-helper references in `meister.sh`**

Run: `grep -nE "ensure_fm_helper|_fm_helper_source|FM_HELPER|FM_ENABLED" meister.sh`
Expected: **no output**. If any line prints, it's a call-site that must move to `fm_available`/`fm_query` or be deleted (e.g. an `ensure_fm_helper` guard). Fix until empty.

- [ ] **Step 4: Run the Ollama unit test — expect GREEN**

Run: `bash tests/test_ollama_backend.sh`
Expected: `test_ollama_backend: PASS`.

- [ ] **Step 5: Symmetry still holds (only AI region diverged)**

Run: `bash tests/test_twin_symmetry.sh`
Expected: `ok: twins identical outside TWIN regions`.

- [ ] **Step 6: Lint**

Run: `shellcheck -x meister.sh meisterSiri.sh && echo OK`
Expected: `OK`.

- [ ] **Step 7: Commit**

```bash
git add meister.sh tests/test_ollama_backend.sh
git commit -m "feat: meister.sh AI backend → thin Ollama HTTP path (keeps fm_* names)"
```

---

## Task 5: Formula — install both twins + `jq` dependency

**Files:**
- Modify: `Formula/meister.rb`

- [ ] **Step 1: Add the twin install line + jq dependency**

In `Formula/meister.rb`, inside `def install`, directly below the existing
`bin.install "meister.sh" => "meister"` line, add:
```ruby
    bin.install "meisterSiri.sh" => "meisterSiri"
```
And near the top of the class (below `homepage`/`url`/`sha256`, above `def install`), add:
```ruby
  depends_on "jq"
```

- [ ] **Step 2: Verify Ruby syntax**

Run: `ruby -c Formula/meister.rb`
Expected: `Syntax OK`.

- [ ] **Step 3: Assert both installs + dependency are present**

Run:
```bash
grep -q 'bin.install "meister.sh" => "meister"'         Formula/meister.rb && \
grep -q 'bin.install "meisterSiri.sh" => "meisterSiri"' Formula/meister.rb && \
grep -q 'depends_on "jq"'                               Formula/meister.rb && echo OK
```
Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add Formula/meister.rb
git commit -m "build(formula): install meisterSiri twin + depend on jq"
```

---

## Task 6: Full run + optional live smoke

**Files:** none (verification)

- [ ] **Step 1: Run the whole suite**

Run: `bash tests/run.sh`
Expected: `ALL GREEN` (shellcheck both twins + symmetry + ollama unit test).

- [ ] **Step 2 (optional, needs a running Ollama): live one-shot smoke of the Ollama twin**

Run:
```bash
ollama serve >/dev/null 2>&1 &   # if not already running
bash -c 'MEISTER_OLLAMA_MODEL=llama3.2; . <(sed -n "/^fm_query()/,/^}/p; /^MEISTER_OLLAMA/p" meister.sh); fm_available && fm_query "Say PONG"'
```
Expected: reachable → prints a short model response. If Ollama is not installed/running, `fm_available` fails and AI features degrade gracefully — this step is skippable.

- [ ] **Step 3 (optional): live smoke of the Apple twin availability**

Run: `bash -c '. <(sed -n "/^fm_available()/,/^}/p; /^FM_/p" meisterSiri.sh); fm_available && echo "apple-available"'`
Expected: on Apple-Intelligence-enabled hardware → `apple-available`; otherwise silent (degrades).

- [ ] **Step 4: Final commit (if run.sh changed) + push branch**

```bash
git add -A && git commit -m "test: green full twin suite" --allow-empty
git push -u origin feat/dual-ai-backend-twins
```

---

## Self-review notes

- **Spec coverage:** twin files (T2, T4) ✓; Ollama thin path keeping `fm_*` names (T4) ✓; no REPL / no v5.26 subsystem restore (never added) ✓; Formula install + jq (T5) ✓; both v6.0 labels via `MEISTER_LABEL` (T2) ✓; graceful degrade (T6 steps 2-3) ✓; drift guard = symmetry test (T2/T4) ✓; orphan untouched (never referenced) ✓.
- **Placeholders:** none — every code/step is concrete.
- **Name consistency:** `fm_available` / `fm_query` used identically in the script, unit test, and smoke steps; `MEISTER_OLLAMA_URL` / `MEISTER_OLLAMA_MODEL` consistent across T4 and tests; TWIN marker strings identical everywhere.
- **Open follow-up (out of scope, do NOT do here):** the `meister-app` README still says CLI "v5.6" — stale, track separately.
