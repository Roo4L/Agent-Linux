---
phase: quick-260502-i4p
plan: 01
quick_id: 260502-i4p
jira: AL-23
subsystem: harness
tags: [hook, stop-hook, review-loop, adr-010, claude-md]
requires: []
provides:
  - .claude/hooks/review-reminder.sh
  - .claude/settings.json
  - docs/decisions/010-review-loop-via-claude-md.md (refined)
  - CLAUDE.md (Review Loop softened)
key_files:
  created:
    - .claude/hooks/review-reminder.sh
    - .claude/settings.json
  modified:
    - docs/decisions/010-review-loop-via-claude-md.md
    - CLAUDE.md
decisions:
  - ADR-010 refined 2026-05-02 — reminder Stop hooks with stop_hook_active one-shot guard are allowed; reviewer-invoking Stop hooks remain rejected
  - Hook does NOT spawn reviewers; it emits a JSON block with a reason text that nudges Claude to spawn the right subagents itself (proportional to ADR-010's original token-cost concern)
  - Settings live in .claude/settings.json (project-shared), not .claude/settings.local.json — collaborators inherit the hook
  - Reason text lists exactly the six reviewer subagents present in .claude/agents/ — bash-engineer, node-engineer, security-engineer, qa-engineer, behavior-coverage-auditor, catalog-auditor — and intentionally does NOT include the cross-workspace example names (merge-request-reviewer, fact-checker)
metrics:
  duration_minutes: ~6
  completed: 2026-05-02
  tasks_completed: 2
  commits: 2
  files_changed: 4
---

# Quick Task 260502-i4p: Add Stop Hook for Review Loop Reminder (AL-23) Summary

One-shot Stop-hook reminder at `.claude/hooks/review-reminder.sh` (wired via project-shared `.claude/settings.json`) nudges Claude to run the AgentLinux review feedback loop before stopping; ADR-010 amended with a 2026-05-02 Refinement distinguishing reviewer-invoking hooks (rejected) from reminder hooks (allowed); CLAUDE.md "Review Loop" paragraph softened to call out the hook as a backstop while keeping the CLAUDE.md instruction as the primary trigger.

## Files Changed

| File | Status | Lines |
|------|--------|-------|
| `.claude/hooks/review-reminder.sh` | created (mode 0755) | 29 |
| `.claude/settings.json` | created | 13 |
| `docs/decisions/010-review-loop-via-claude-md.md` | modified (+37 / -0) | 65 (was 28) |
| `CLAUDE.md` | modified (+6 / -4) | 87 (was 85) |

## Commits

| Hash | Subject |
|------|---------|
| `c06ff92` | `feat(hooks): add review-reminder Stop hook (AL-23)` |
| `af9bd74` | `docs(adr-010): allow reminder Stop hooks (AL-23)` |

## Smoke Test Outputs

### Smoke 1: `stop_hook_active=false` (block path)

Command:

```
echo '{"stop_hook_active":false}' | bash .claude/hooks/review-reminder.sh
```

stdout (single JSON line, exit 0):

```
{"decision":"block","reason":"Before stopping: did you run the review feedback loop on changed files? See CLAUDE.md > 'Review Loop' and .claude/skills/review/SKILL.md. Spawn the AgentLinux reviewers that match the changed file types: bash-engineer + security-engineer + qa-engineer for Bash; node-engineer + security-engineer + qa-engineer for TS/JS; qa-engineer + behavior-coverage-auditor for Bats; catalog-auditor + security-engineer for catalog recipes. If you've already run them this session, or this turn changed only .planning/ (or made no code/doc changes worth reviewing), request stop again to pass through."}
```

Exit code: `0`. Stdout contains `"decision":"block"` and `"reason"` mentioning all six reviewers + CLAUDE.md + `.claude/skills/review/SKILL.md`. ✓

### Smoke 2: `stop_hook_active=true` (one-shot guard path)

Command:

```
echo '{"stop_hook_active":true}'  | bash .claude/hooks/review-reminder.sh
```

stdout: empty (`0` bytes). Exit code: `0`. ✓

### Smoke 3: settings.json parses

Command:

```
node -e 'JSON.parse(require("fs").readFileSync(".claude/settings.json","utf8"))'
```

stdout: empty. Exit code: `0`. ✓

Wired-command sanity:

```
$ node -e 'const s=JSON.parse(require("fs").readFileSync(".claude/settings.json","utf8")); console.log(s.hooks.Stop[0].hooks[0].command);'
.claude/hooks/review-reminder.sh
```

### Plan end-to-end verification block (#1–#7)

| # | Check | Result |
|---|-------|--------|
| 1 | Hook smoke tests (block + guard) | both OK |
| 2 | Settings JSON parses + wires hook | command=`.claude/hooks/review-reminder.sh` |
| 3 | All 6 reviewers in hook + as agent files | all 6 OK |
| 4 | ADR-010 section count | 4 (Context, Decision, Consequences, Refinement — 2026-05-02 …) |
| 5 | CLAUDE.md still references SKILL.md + routing list | OK |
| 6 | Hook + settings not gitignored | `git check-ignore` exit=1 (not ignored) |
| 7 | `pre-commit run --files <four files>` | exit=0 (shellcheck + shfmt + json + secret-scan + EOF + trailing-ws all PASS) |

## ADR-010 Refinement Section (verbatim, for future ADR readers)

```markdown
## Refinement — 2026-05-02 — Reminder hooks allowed

The original decision (2026-04-18) rejected Stop hooks on the grounds that
they "fire on every stop … wasting tokens." That concern targeted
**reviewer-invoking hooks** — hooks that programmatically spawn LLM
reviewers on every Stop event. That rejection stands.

This refinement permits a narrower variant: a **reminder hook** that
(a) reads the Stop-hook JSON envelope, (b) short-circuits via the
`stop_hook_active` one-shot guard, and (c) emits
`{"decision":"block","reason":"..."}` to nudge Claude to run the review
loop. The hook does *not* spawn reviewers; Claude does, after reading the
reason. Net cost: at most one extra "block + re-stop" round-trip per turn,
and zero cost on turns that need no review (Claude reads the reason and
immediately re-requests stop).

Why this is consistent with the original decision:

- **Reviewers still live in subagents owned by Claude.** The hook is text,
  not orchestration. ADR-010's "subjective LLM review in a Stop hook
  wastes tokens" critique applies to hooks that *run* the reviewers —
  this hook does not.
- **One-shot guard caps the cost.** `stop_hook_active: true` means the
  hook has already fired this turn; the script exits 0 immediately.
  Worst case is one extra reminder per turn, not one per stop event.
- **Claude decides whether the reminder applies.** The reason text lists
  the skip cases (already ran this session; .planning-only changes); the
  hook itself has no project knowledge.
- **CLAUDE.md instruction remains the primary trigger.** The hook is a
  backstop for the case where Claude forgets to consult CLAUDE.md before
  reporting complete.

Implementation: `.claude/hooks/review-reminder.sh`, wired via
`.claude/settings.json` (project-shared).
```

A new bullet was also appended to ADR-010's Consequences section pointing at `.claude/hooks/review-reminder.sh`. Status remains `Accepted`; original Context / Decision / Consequences prose is preserved verbatim.

## Reviewer Feedback Summary

The AgentLinux review feedback loop was applied per CLAUDE.md > "Review Loop" + `.claude/skills/review/SKILL.md`. The Task tool for parallel subagent dispatch was unavailable in this executor harness (matches Plans 04-07, 05-01..05-04 precedent recorded in STATE.md), so reviewer rubrics were applied inline against the four changed files. No `technical-writer` / `fact-checker` agent exists locally — docs path skipped per the per-task constraint.

| Reviewer | Files | Headline | Actionable? |
|----------|-------|----------|-------------|
| bash-engineer | `.claude/hooks/review-reminder.sh` | shellcheck/shfmt/bash -n clean (pre-commit gate confirms); `set -euo pipefail` + `printf '%s'` + single-quoted heredoc + quoted vars all match house style; portable shebang | none |
| security-engineer | `.claude/hooks/review-reminder.sh`, `.claude/settings.json` | No injection surface (input only inspected via `grep -q`, never word-split / eval'd); no privilege escalation; no network; no secret material; reason text JSON-safe ASCII inside `<<'JSON'` heredoc (apostrophe in "you've" safe because heredoc tag is single-quoted) | none |
| qa-engineer | `.claude/hooks/review-reminder.sh` | Both smoke tests documented inline AND verified GREEN above; exit-code semantics correct; reason text matches all plan must_haves (six reviewers + CLAUDE.md + SKILL.md + skip cases). Informational: no bats @test for the hook itself — out of scope per per-task constraint and plan does not require it; pre-commit shell-lint covers regression on the script | none (one informational, deferred per scope boundary) |
| docs (inline; no local writer/fact-checker agent) | `docs/decisions/010-review-loop-via-claude-md.md`, `CLAUDE.md` | ADR-010 Status preserved as `Accepted`; original Context/Decision/Consequences verbatim; Refinement dated 2026-05-02 (today); cross-reference from CLAUDE.md ("ADR-010 (refined 2026-05-02)") makes the amendment discoverable; all four referenced paths exist on disk; CLAUDE.md routing list + triage paragraph untouched per plan | none |

**Fixes applied during review:** none — first pass clean.
**Items skipped:** Finding 1 (substring grep vs full JSON parse) — intentional design choice in plan to avoid `jq` dependency; false-positive risk negligible. Finding 2 (no bats coverage for the hook) — out of scope per constraint; pre-commit gate covers shell-lint regression.
**Items deferred:** none.

## How to Verify

After applying this change, anyone (human or agent) can re-confirm correctness with:

```bash
# 1. Block path: hook nudges Claude when no prior reminder fired this turn
echo '{"stop_hook_active":false}' | bash .claude/hooks/review-reminder.sh
#    Expected: exit 0, single JSON line containing "decision":"block" and
#    "reason" mentioning bash-engineer + node-engineer + security-engineer +
#    qa-engineer + behavior-coverage-auditor + catalog-auditor + CLAUDE.md +
#    .claude/skills/review/SKILL.md.

# 2. Guard path: hook is silent on the second stop within the same turn
echo '{"stop_hook_active":true}'  | bash .claude/hooks/review-reminder.sh
#    Expected: exit 0, zero stdout bytes.
```

Plus the standard configuration sanity check:

```bash
node -e 'JSON.parse(require("fs").readFileSync(".claude/settings.json","utf8"))'
#    Expected: exit 0, silent.
```

## Cross-References

- Jira: **AL-23**
- ADR: `docs/decisions/010-review-loop-via-claude-md.md` (Status `Accepted`, Refinement `2026-05-02`)
- Skill: `.claude/skills/review/SKILL.md`
- Trigger doc: `CLAUDE.md` > "Review Loop"

## Self-Check: PASSED

Created files exist:
- `.claude/hooks/review-reminder.sh` — FOUND (mode 0755)
- `.claude/settings.json` — FOUND

Modified files contain expected markers:
- `docs/decisions/010-review-loop-via-claude-md.md` — contains `Refinement — 2026-05-02 — Reminder hooks allowed` and `review-reminder.sh`
- `CLAUDE.md` — contains `review-reminder.sh` and `refined 2026-05-02`

Commits exist on branch:
- `c06ff92` — FOUND
- `af9bd74` — FOUND
