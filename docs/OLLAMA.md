# meister with Ollama

`meister` keeps the same maintenance modules and repair guards as `MeisterAI`,
using Ollama instead of Apple Foundation Models. Edit the backend template in
`scripts/sync-twins.sh`, then regenerate `meister.sh`; do not edit the generated
backend directly.

Lokaler Modellvergleich: [Empfehlung und Messdaten](OLLAMA-MODEL-COMPARISON.md).

## Configuration

Set these in `~/.meister/config` (export is not required):

```bash
MEISTER_OLLAMA_URL="http://localhost:11434"
MEISTER_OLLAMA_MODEL="qwen3-coder:30b"
MEISTER_OLLAMA_TIMEOUT=90
MEISTER_OLLAMA_KEEP_ALIVE="5m"
MEISTER_OLLAMA_NUM_CTX=8192
MEISTER_OLLAMA_NUM_PREDICT=1024
MEISTER_OLLAMA_THINK="false"
```

The configured model must already be installed and the server running. Availability
checks match that model in `/api/tags`, including Ollama's `:latest` tag convention.
No model downloads, server startup, or silent model substitutions occur.
The default server is local. Setting a remote URL explicitly sends redacted
requests to that server. URLs containing credentials, query strings or fragments
are rejected.

Thinking defaults to `false` so supported models produce the final answer within
the bounded budget. Set `auto` to retain the model default, `true` to enable it,
or `low`/`medium`/`high` for models that require reasoning levels. Support depends
on the selected model; an unsupported mode is an error, never a silent fallback.
See Ollama's [thinking API](https://docs.ollama.com/capabilities/thinking).

Generation uses temperature zero, a bounded output budget and a configurable
keep-alive period to reuse loaded model weights. Timeout is 1–300 seconds;
context size 4096–32768; output budget 256–4096 tokens. Requests are limited to
32768 characters; responses to 1 MiB. No automatic retry doubles a slow inference.

## Diagnosis and safety

`meister ai --diagnose-only` and AI healing request `meister.diagnosis/v1` as a
JSON schema. The helper validates evidence references and the fixed action
catalog, then the shared contract validates again before mapping an action to
argv. Unknown actions, missing evidence, unsupported parameters and a repeated
failed action are rejected. No arbitrary model-generated shell code is executed.
The default remains suggest-only; opt-in execution still requires verification.

The textual next-check is explicitly labeled as an unverified AI suggestion;
it is never automatically executed. Models can propose an inaccurate or even
mutating check despite the read-only instruction, so inspect that advice first.

`explain`, `today` and `suggest` retain plain-text output. Prompts and returned
text are redacted. Audit/trace stores status and numeric token/timing metadata
rather than raw prompts or server error bodies. This redaction covers known
credential patterns, not every possible sensitive phrase.

Transport errors exit 69; timeouts 75; malformed, empty, incomplete or invalid
diagnoses 65; invalid input/configuration 64. A token-limit termination is not
accepted as a complete response. These errors propagate through diagnosis, explain and suggest. The optional AI
focus in today prints a failure notice while retaining the factual daily overview.

Implementation follows Ollama's [generate API](https://docs.ollama.com/api/generate)
and [API reference](https://github.com/ollama/ollama/blob/main/docs/api.md).

## Verification

`bash scripts/check.sh` includes shell integration tests and Python tests against
a local HTTP fixture server. They test the actual transport without requiring
model downloads or running maintenance. Model quality and real-world inference
latency require a live server and are not established by these fixtures.

Live comparison (read-only model queries):

```bash
MEISTER_OLLAMA_URL=http://localhost:11434 python3 scripts/evaluate-fm.py \
  --live --backend ollama --model qwen3-coder:30b --include-responses \
  --output /tmp/meister-ollama-evaluation.json
```

Repeat with `--fixtures tests/fixtures/ollama_holdout.json` for the independent
synthetic set. Reports separate contract validity, expected actions, evidence and
lexical diagnosis checks. They never certify an actual repair.

Recap: model-aware availability, structured diagnoses, bounded inference and
observable failures; the meister command and repair protections are preserved.
