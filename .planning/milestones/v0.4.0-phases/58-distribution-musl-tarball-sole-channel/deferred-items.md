# Phase 58 — Deferred / Out-of-Scope Items

Discovered during 58-01 (Wave 1) execution. These are pre-existing failures
NOT caused by this wave's changes; they are logged here per the executor
SCOPE BOUNDARY rule and left unfixed.

## Pre-existing harness (`tests/harness/run.sh`) reds — unrelated to DIST-02

Both failures reference files this wave never touched; the DIST-02-relevant
layout test (`tests/harness/00-layout.bats`, HRN-01) is fully green (19/19,
the `packaging/deb` assertion correctly removed).

1. **HRN-05 red** — `tests/harness/40-adrs-and-research.bats:88`
   `diff -q .planning/research/SUMMARY.md docs/research/v0.3.0/SUMMARY.md`
   fails: `.planning/research/SUMMARY.md: No such file or directory`.
   Cause: the `.planning/research/SUMMARY.md` source file is absent in this
   branch's `.planning/` (byte-match test has no left-hand file). Unrelated to
   the musl/tarball/deb swap.

2. **HRN-06 red** — `tests/harness/50-agents-and-skills.bats:71`
   `grep -qEi "0440|sudoers" .claude/agents/security-engineer.md` fails: the
   reviewer rubric does not mention sudoers mode 0440. Unrelated to Phase 58.

These predate Wave 1 and are candidates for a separate harness-hygiene fix.
