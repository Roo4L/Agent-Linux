---
phase: 260524-ch1
plan: 01
subsystem: catalog/claude-code
tags: [catalog, claude-code, pinning, AL-51, AGT-02c]
requires: [AGT-02b, ADR-011]
provides: [AGT-02c]
affects: [plugin/catalog/agents/claude-code/install.sh, plugin/catalog/agents/claude-code/uninstall.sh, tests/bats/50-agents.bats, docs/internals/claude-code.md]
tech-stack:
  added: []
  patterns: [atomic write via temp-file + mv, jq deep-merge preserving user keys]
key-files:
  modified:
    - plugin/catalog/agents/claude-code/install.sh
    - plugin/catalog/agents/claude-code/uninstall.sh
    - tests/bats/50-agents.bats
    - docs/internals/claude-code.md
  created: []
decisions:
  - No new ADR — ADR-011's stability-first invariant already documents the WHY; this plan is the tactical mechanism for one consumer
  - No REQUIREMENTS.md edit — that file is v0.4.0-scoped at HEAD; AGT-02c recorded in @test docstring + SUMMARY, promote on next v0.3.x revision
  - No symmetric-uninstall bats @test — 50-agents.bats setup_file installs once per file; uninstall coverage is via `bash -n` + jq-filter inspection
metrics:
  duration: ~35min
  tasks_completed: 2
  commits: 3
  bats_tests_added: 1
  bats_tests_total_after: 75 (all green on ubuntu-24.04)
  completed: 2026-05-24
---

# Plan 260524-ch1: Disable Claude Code Background Auto-Updater Summary

**AL-51:** `agentlinux install claude-code` now stamps `~agent/.claude/settings.json` with `env.DISABLE_AUTOUPDATER="1"` (Anthropic's documented switch); `agentlinux remove claude-code` strips it symmetrically. ADR-011's `pinned_version` now holds at runtime, not just at install time. Manual `claude update` (AGT-02) is unaffected.

## What changed

1. **`plugin/catalog/agents/claude-code/install.sh`** — after the existing AGT-02b in-recipe version-lock assertion (lines 47-50, byte-identical), a new block writes the settings stamp atomically:
   - `mkdir -p ${AGENTLINUX_AGENT_HOME}/.claude`
   - If `settings.json` exists: `jq '. + {env: ((.env // {}) + {DISABLE_AUTOUPDATER:"1"})}'` — deep-merges, preserves user keys
   - Else: `jq -n '{env:{DISABLE_AUTOUPDATER:"1"}}'` — fresh file
   - Write to `${settings_file}.tmp.$$`, then `mv` (atomic on POSIX)
   - No `chown` — recipe runs as the `agent` user via runner.ts's `as_user` dispatch

2. **`plugin/catalog/agents/claude-code/uninstall.sh`** — between the existing `rm` calls and the "Intentionally NOT removed" comment block, a symmetric strip block:
   - If `settings.json` exists: run a jq filter that `del(.env.DISABLE_AUTOUPDATER)` and drops empty `env`
   - If the resulting JSON is `{}` (i.e. nothing of the user's remains): delete the whole file
   - Else: atomic `mv` of the stripped content
   - Malformed JSON: `rm -f "${tmp}"` and continue (idempotent + non-fatal, matching the file's `rm -f` idempotency idiom)

3. **`tests/bats/50-agents.bats`** — new `AGT-02c` @test in the AGT-02b section, asserting post-install:
   - `~agent/.claude/settings.json` exists
   - `.env.DISABLE_AUTOUPDATER == "1"` (parsed via `jq -r`)
   - Uses the AGT-02b dispatch idiom (`sudo -u agent -H bash --login -c '...'`)
   - Uses the standard `__fail` four-line diagnostic with `LOG=/var/log/agentlinux-install.log`
   - Does NOT re-install — `setup_file()` already installed claude-code once for the file
   - Docstring explains why a new ID (independent invariant from AGT-02b) and why not in REQUIREMENTS.md (v0.4.0-scoped)

4. **`docs/internals/claude-code.md`** — short paragraph appended to `## What AgentLinux does`, product-perspective lens ("AgentLinux also makes the version you installed stay the version you installed"), parenthetical mention of the `DISABLE_AUTOUPDATER` flag, acknowledges manual `claude update` still works.

## No-ADR rationale

CLAUDE.md feedback note "Avoid Ceremony" (memory `feedback_avoid_ceremony.md`): name a real consumer for an ADR today or drop it. The `DISABLE_AUTOUPDATER` mechanism has exactly one consumer (claude-code recipe); ADR-011 already establishes the stability-first invariant this implements. A second consumer would warrant promotion to a shared `plugin/lib/settings-merge.sh` helper + an ADR — neither exists today.

## No-REQUIREMENTS.md-edit rationale

`.planning/REQUIREMENTS.md` at HEAD documents v0.4.0 categories (LIC/SEC/CLEAN/CIPUB/PUB) plus the DOC addendum. AGT-02c is a v0.3.x post-milestone behavior; adding it mid-document would drift the file out of milestone scope. Recorded in the AGT-02c @test docstring and in this SUMMARY; promote into REQUIREMENTS.md when the next v0.3.x revision rolls.

## No symmetric-uninstall bats @test rationale

`50-agents.bats`'s `setup_file()` installs claude-code once per file (line 79). An uninstall-side @test in the same file would either re-install after removal (breaking the install-once model) or rely on `teardown_file()` ordering (untestable inside the suite). The symmetric uninstall is verified by:

1. `bash -n plugin/catalog/agents/claude-code/uninstall.sh` — parses clean
2. Eyeball: the jq filter `if (.env|type)=="object" then .env = (.env|del(.DISABLE_AUTOUPDATER)) else . end | if (.env=={}) then del(.env) else . end` strips only the env entry and drops empty `env`
3. Conditional whole-file delete is gated on `jq -e 'length == 0'` — only removes the file when nothing else remains
4. Malformed JSON tolerated by wrapping the jq call in `if … 2>/dev/null`

A future quick task could add a destructive uninstall @test in `tests/bats/51-agt02-release-gate.bats` (which already exercises an install→action→re-install cycle).

## Verification

```
== run bats suite (tests/bats/) ==
1..75
...
ok 63 AGT-02b: claude --version returns exactly pinned_version from catalog.json
ok 64 AGT-02c: claude-code install stamps DISABLE_AUTOUPDATER=1 in ~agent/.claude/settings.json
...
ok 71 AGT-02 (release-gate): claude update exits 0 with zero EACCES/permission-denied lines
...
== PASS: agentlinux-install + bats on ubuntu-24.04 ==
```

All 75 tests green. AGT-02 release-gate (manual `claude update` with zero EACCES) is also green — confirms the `DISABLE_AUTOUPDATER` stamp does not break the canonical self-update acceptance test.

`pre-commit run` clean on both task commits.

## Commits

| Hash      | Subject                                                                |
| --------- | ---------------------------------------------------------------------- |
| `c3e6ae6` | `fix(catalog): disable Claude Code background auto-updater (AL-51)`    |
| `c9c845d` | `test(bats): assert AGT-02c DISABLE_AUTOUPDATER stamp + dev-docs note (AL-51)` |
| `e65ba32` | `refactor(catalog): deslop AL-51 stamp comments — review nit`          |

## Review

Performed the per-file-type review pass myself (Task tool not available in this executor context; rubric files read and applied to the diff):

- **catalog-auditor** (`install.sh` + `uninstall.sh`) — schema/recipe-json not touched; no `sudo npm install`; symmetric uninstall present; no `/usr/local` writes; no curl-pipe-bash; inputs not interpolated. Pass.
- **security-engineer** (`install.sh` + `uninstall.sh`) — no sudoers/eval/xargs/word-splitting issues; all `${...}` quoted; no secret leakage; privilege boundary unchanged (still runs as `agent`). Pass.
- **qa-engineer** + **behavior-coverage-auditor** (`50-agents.bats`) — `@test` name carries `AGT-02c:` ID per TST-07; asserts on stdout content + jq-parsed value (not just exit 0); uses `__fail` diagnostic; single-mode is intentional and documented (the artefact is the assertion, not invocation-mode resolution). Pass.
- **ai-deslop** (all bash + docs) — caught two slop lines on first pass: a `# AL-51:` comment lede and `(DISABLE_AUTOUPDATER=1 — AL-51)` in the user-facing echo. Both are task-context (Jira-key) slop per `.claude/agents/ai-deslop.md` §2. Fixed in commit `e65ba32`; the legitimate WHY anchors (ADR-011, AGT-02, CLI-04) remain.
- **dev-docs-auditor** (`docs/internals/claude-code.md`) — `claude-code/{install,uninstall}.sh` correctly dispatches to `claude-code.md`; product-perspective lens preserved (value-first lede, `DISABLE_AUTOUPDATER` as supporting parenthetical); no source-line cross-refs; four-section spine intact. Pass.

Dispositions: one round of fixes (ai-deslop nits), no further iteration needed. Remaining unflagged surfaces are stylistic preferences with no concrete failure mode.

## Deviations from Plan

None — the plan's structural strip-and-cleanup design and atomic-write idiom were followed verbatim. One self-imposed cleanup (the deslop commit) sits inside the plan's `<constraints>` ("review pass after commits") rather than outside it.

## Self-Check: PASSED

Files exist:
- FOUND: `plugin/catalog/agents/claude-code/install.sh` (post-edit, contains `DISABLE_AUTOUPDATER`)
- FOUND: `plugin/catalog/agents/claude-code/uninstall.sh` (post-edit, contains `del(.DISABLE_AUTOUPDATER)`)
- FOUND: `tests/bats/50-agents.bats` (contains the `AGT-02c` @test)
- FOUND: `docs/internals/claude-code.md` (contains the `DISABLE_AUTOUPDATER` mention)
- FOUND: `.planning/quick/260524-ch1-al-51-disable-claude-code-background-aut/260524-ch1-SUMMARY.md` (this file)

Commits exist:
- FOUND: `c3e6ae6` (Task 1: catalog stamp/strip)
- FOUND: `c9c845d` (Task 2: bats @test + dev-docs note)
- FOUND: `e65ba32` (review-nit deslop)

End-to-end: `./tests/docker/run.sh ubuntu-24.04` → 75/75 bats tests pass, AGT-02c green, AGT-02 release-gate green, zero EACCES in log.
