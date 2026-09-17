# Local Ollama comparison methodology

Host: Apple M5 Max, 128 GiB unified memory. Ollama client/server 0.34.1.
A temporary loopback server listens on 127.0.0.1:11435 with cloud disabled and
one inference slot. Only previously installed models are used; no downloads,
repairs, background service installation or host configuration changes.

Compare the same 14 maintenance fixture contexts in the same order, temperature
0, num_ctx 8192, num_predict 1024, per-call timeout 45 seconds. Include cold-load
time in per-case timings; median reduces its influence but is not a formal warm
latency benchmark. The default-model baseline first call may already be warm.
Models are unloaded between cohorts. Raw validated diagnoses and safe numeric
metadata are retained for qualitative review; internal reasoning is not saved.

The baseline uses the previous diagnostic instructions and model-default thinking.
The tuned cohort uses more explicit general evidence/action instructions and
think=false. These changes are tested together, so the comparison does not isolate
the effect of each change. The model identity includes the local digest in the
inventory because mutable latest tags can change between installations.

Contract acceptance is separate from automatic case success. Automatic success
requires reference evidence IDs, expected action/abstention, and a cause containing
at least one expected term. This lexical proxy can reject valid paraphrases and
can accept inadequate explanations. Manually review outputs before recommending.

Ten independently authored synthetic German holdout cases exercise abstention,
untrusted instructions, the three supported actions, historical/current evidence,
authentication, permissions and unsuccessful prior repair. No prompt changes based
on their outputs are made before finalist evaluation. This is a small task-specific
comparison, not a claim of overall model superiority or measured repair success.

Recap: equal task/configuration comparisons, disclosed lexical scoring and small
sample limitations, no repair execution or downloads.
