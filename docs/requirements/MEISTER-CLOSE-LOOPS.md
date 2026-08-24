# MEISTER-CLOSE-LOOPS — MeisterSiri daily runner

**Status:** in progress  
**Date:** 2026-08-24  
**Source:** log comparison meister vs meisterSiri (user: close the loops)

meradOS `requirements_registry` has no `desktop`/`meister` codebase_area
(prefixes are AI/AM/BE/BT/…). This requirement lives in the tap.

## Objective

MeisterSiri is the product default. Three log-driven loops:

1. **Git push gate** — `GIT_AUTO_PUSH=false` must stop Autofix, not only the Git module.
2. **AufRaum hook** — `_Inbox` WARN calls AufRaum dry-run (never live unless `AUFRAUM_APPLY=true`).
3. **LaunchAgent** — `meisterSiri -I` installs daily `--auto -q` + weekly `--deep -q` on `meisterSiri`, and retires legacy `com.meister.maintenance` (meister2026.sh).

## Acceptance

- Autofix does not `git push` when `GIT_AUTO_PUSH=false`.
- `.meister-nopush` and `git config meister.nopush true` skip that repo in Autofix.
- Docs-order Inbox: if unsorted > 0 and operator exists, log planned AufRaum moves from `apply --dry`.
- Live AufRaum only when `AUFRAUM_APPLY=true` and not dry-run.
- `meisterSiri -I` daily args are `--auto -q`; weekly `--deep -q`; bootout `com.meister.maintenance`.
- Twins stay in sync via `scripts/sync-twins.sh`.

## Test strategy

| Test | File | Proves |
|------|------|--------|
| `GIT_AUTO_PUSH=false` denies even if `AUTOFIX_GIT_PUSH=true` | `tests/git_push_policy.bats` | master switch |
| nopush marker / git config deny | same | per-repo opt-out |
| both true + no marker allows | same | happy path |
| default `AUFRAUM_APPLY` is false | `tests/aufraum_hook.bats` | no live sort |
| operator from `AUFRAUM_OPERATOR` | same | discoverability |
| `aufraum_count_planned` counts ` -> ` lines | same | dry-run parse |
| daily args `--auto -q` | `tests/launchagent_keepcurrent.bats` | product default |
| weekly `--deep -q` | same | weekly deep |
| legacy label list includes `com.meister.maintenance` | same | retire dead agent |
