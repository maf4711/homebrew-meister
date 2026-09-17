# Qualitative review

The automated score is a lexical/evidence/action proxy, not an expert diagnosis
verdict. Examples that passed automated checks but still need improvement:

- Qwen3-Coder inferred an incomplete/failed XProtect check from absent scan
  evidence. Its Dock next-check used the system domain instead of the GUI session.
  Mail access advice mentioned Mail app permissions rather than the invoking
  process's privacy authorization.
- Qwen3.6 handled sudo/TTY clearly, but invented a Dock-Finder subprocess and
  mentioned SIP without a supporting observation. It placed a QuickLook cache
  reset in the supposedly read-only next-check field.
- Qwen2.5-Coder and Qwen3 sometimes proposed installation, process restart,
  `visudo` or cache reset as a next check.
- Nemotron produced many English responses despite the German request and
  suggested a QuickLook reset when investigating missing XProtect scan evidence.
- Gemma's plausible German paraphrases sometimes failed narrow word checks,
  but several positive repair cases were rejected by the output contract.

Contract rejection means no accepted proposal, not proof the model generated a
specific dangerous action: rejected raw answers were not retained. Read-only
next-check prose is advisory model text, not a verified executable operation.
Only catalog actions enter the guarded execution path, and execution is opt-in.
No proposed repair or model-generated next-check was executed in this benchmark.

These limitations are reasons to keep the fixed action catalog, evidence checks,
suggest-only default and verification of any actual repair. They also prevent a
claim that the highest automatic score is error-free or universally best.

Recap: retain human review of explanations; select the strongest task-specific
tradeoff while preserving deterministic execution guards.
