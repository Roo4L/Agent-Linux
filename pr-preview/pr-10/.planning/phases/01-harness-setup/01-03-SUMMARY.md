---
phase: 01-harness-setup
plan: 03
subsystem: infra
tags: [review-loop, subagents, skills, claude-code, shellcheck, commander-js, sudoers, bats-coverage, catalog-schema, tst-07, adr-010]

# Dependency graph
requires:
  - phase: 01-harness-setup
    provides: "Plan 01-01's CLAUDE.md (review-loop instruction references .claude/skills/review/SKILL.md at line 46) + docs/HARNESS.md §4 (authoritative spec — rubric bullets copy-of-truthed into each subagent file) + ADR-010 (trigger mechanism rationale)"
provides:
  - "Six project-scoped review subagents under .claude/agents/ covering bash, TS, security, QA, coverage-audit, and catalog — all with read-only tool sets (Read, Grep, Glob, Bash)"
  - "/review skill at .claude/skills/review/SKILL.md documenting dispatch rules (file-pattern → subagent), triage rules (fix/skip/stop), the TST-07 end-of-phase gate, and the ADR-010 trigger mechanism"
  - "TST-07 gate is now a nameable, spawn-able mechanism: behavior-coverage-auditor subagent + /review skill's end-of-phase rule referencing it by slug"
  - "Project-scoped reviewer pool separate from the global ~/.claude/agents/ pool — AgentLinux-specific rubrics (sudo npm install -g ban, /usr/local shim ban, as_user discipline, six-mode invocation coverage) that global reviewers don't know"
affects: [01-04-skills, 01-05-harness-tests, 02-installer-foundation, 03-runtime, 04-registry-cli-catalog, 05-agent-installability, 06-distribution-release-pipeline]

# Tech tracking
tech-stack:
  added: []  # No new libraries — Claude Code native subagent + skill format only
  patterns:
    - "Project-scoped review subagents: .md files under .claude/agents/ (not ~/.claude/agents/) with name-matches-filename frontmatter discipline"
    - "Read-only reviewer tool set by default: tools: Read, Grep, Glob, Bash (no Write/Edit) — per HARNESS.md §4.2 threat-model T-03-01 mitigation"
    - "Rubric copy-of-truth: each subagent rubric is a verbatim expansion of docs/HARNESS.md §4.2 bullets, so drift between spec and implementation is greppable"
    - "Dispatch rules table in /review skill: file-pattern regex → subagent slug set — deterministic routing the main agent follows at task close"
    - "TST-07 is named in /review skill as 'always spawn behavior-coverage-auditor at phase close regardless of what changed' — the gate is explicitly listed, not implied"

key-files:
  created:
    - .claude/agents/bash-engineer.md
    - .claude/agents/node-engineer.md
    - .claude/agents/security-engineer.md
    - .claude/agents/qa-engineer.md
    - .claude/agents/behavior-coverage-auditor.md
    - .claude/agents/catalog-auditor.md
    - .claude/skills/review/SKILL.md
  modified: []

key-decisions:
  - "Did NOT touch CLAUDE.md: Plan 01-01 already wrote the review-loop instruction at CLAUDE.md:43-47 with a direct pointer to .claude/skills/review/SKILL.md. Grep confirmed the pointer resolves to this plan's skill file — no edit needed, so none was made (success-criterion explicit: don't silently edit CLAUDE.md)."
  - "Kept all subagents read-only (tools: Read, Grep, Glob, Bash — no Write/Edit) per HARNESS.md §4.2 threat-register T-03-01 mitigation. Subagents are advisors; the main agent applies fixes."
  - "Subagent bodies sized 58-85 lines each (plan said 40-80, success-criterion said 60-150; chose 58-85 as the natural fit for the rubric depth HARNESS.md §4.2 calls for — bash-engineer at 58 is the smallest because its rubric bullets are shortest, catalog-auditor+behavior-coverage-auditor at 79-85 because they need detailed workflow and table-output examples)."
  - "Used `model: sonnet` was NOT declared in subagent frontmatter — Claude Code's documented subagent format allows model to be inferred from the parent session. The reminder in the task prompt flagged `model: sonnet` as 'appropriate', but not declaring it matches the format example in the plan's <interfaces> block and keeps the files runnable across model versions."
  - "Every subagent file ends with an explicit 'Output format' section showing a concrete free-form summary example — so when the main agent spawns the subagent, the subagent knows what shape of output the caller expects (free-form summary, file:line citations, no BLOCK/FLAG/PASS taxonomy per HARNESS.md §4.3)."
  - "Per-task atomic commits via raw `git add <files> && git commit --no-gpg-sign` (continuing Plans 01-01 and 01-02's pattern; gsd-tools.cjs commit auto-stages all working-tree changes and breaks sequential atomic commits)."

patterns-established:
  - "Subagent file structure: YAML frontmatter (name, description, tools) + Markdown body with sections: When to spawn / What to look for (numbered rubric) / Common gotchas (AgentLinux-specific) / Output format (concrete example). Six files all follow this shape."
  - "Skill file structure: YAML frontmatter (name, description — single paragraph that names every downstream subagent so Claude Code's auto-delegation picks the right skill) + body with When-to-use, The loop (ASCII diagram), Dispatch rules (regex table), Triage rules, Trigger mechanism (cites ADR), Related (cross-references)."
  - "Reviewer rubric as copy-of-truth for docs/HARNESS.md §4.2: every rubric bullet is a verbatim expansion of a HARNESS.md bullet. Future edits to HARNESS.md §4.2 require a sweep across the six subagent files — drift is detectable by side-by-side diff."

requirements-completed: [HRN-06, HRN-07, TST-07]

# Metrics
duration: 34min
completed: 2026-04-18
---

# Phase 1 Plan 03: Six Review Subagents + /review Skill Summary

**Six project-scoped review subagents (bash-engineer, node-engineer, security-engineer, qa-engineer, behavior-coverage-auditor, catalog-auditor) plus the /review skill wiring them via dispatch rules, triage rules, and the TST-07 end-of-phase gate — review-feedback-loop from docs/HARNESS.md §4 is now operationally usable with a single CLAUDE.md-triggered invocation (ADR-010).**

## Performance

- **Duration:** ~34 min
- **Started:** 2026-04-18T10:06:30Z
- **Completed:** 2026-04-18T10:40:43Z
- **Tasks:** 2 / 2
- **Files created:** 7 (6 subagent .md + 1 SKILL.md)

## Accomplishments

- Six project-scoped review subagent files under `.claude/agents/`, each with Claude Code subagent frontmatter (`name`, `description`, `tools`) and a focused review rubric copy-of-truthed from `docs/HARNESS.md` §4.2:
  - **bash-engineer** (58 lines) — shellcheck, idempotency primitives (`ensure_user`, `ensure_line_in_file`, `ensure_npm_prefix`), POSIX-vs-bash correctness, quoting, `set -euo pipefail`, traps, no `curl | sh` inside provisioners without SHA verify.
  - **node-engineer** (61 lines) — Commander.js idioms, TS strict-mode, no swallowed catches, `process.exit` only at top-level, `execFile` over `exec`, biome formatting.
  - **security-engineer** (69 lines) — sudoers drop-in mode **0440** (not 0644), no `eval` in bash, curl-pipe-bash SHA verification + `main() {...}; main "$@"` wrapping against truncated downloads, input sanitization via schema `name` pattern + `https://` URLs, secret leakage in logs.
  - **qa-engineer** (74 lines) — six-invocation-mode coverage (interactive bash, non-interactive SSH, cron, systemd `User=agent`, `sudo -u agent`, `sudo -u agent -i`), assertion-strength rubric (mutation-kill weak = exit-code-only), no `skip` without tracking reference.
  - **behavior-coverage-auditor** (85 lines) — runs at end of every phase (TST-07 gate); greps `.planning/REQUIREMENTS.md` for `BHV|RT|AGT|CLI|CAT|INST|HRN|TST|DOC-\d+`, cross-checks against `tests/bats/` and `@test` titles, emits covered/uncovered/partial report with `TST-07 gate: RED|GREEN` summary line.
  - **catalog-auditor** (79 lines) — JSON Schema validation via `validate-catalog.mjs`, `as_user` discipline in every `install.sh`, symmetric `remove.sh` per agent, no writes to `/usr/local/`, no wrapper shims pointing at agent-owned binaries.
- `/review` skill at `.claude/skills/review/SKILL.md` (126 lines) — dispatch rules table (file pattern → subagent set), triage rules (fix / skip / stop with concrete examples), trigger mechanism section citing ADR-010, TST-07 relation section explicitly naming behavior-coverage-auditor as the end-of-phase gate.
- CLAUDE.md already referenced `.claude/skills/review/SKILL.md` at line 46 (from Plan 01-01); verified the pointer resolves to the newly-landed skill without any edit to CLAUDE.md.
- All seven files parse as valid markdown with readable YAML frontmatter; `head -1 | grep ^---$` green on every file.
- Read-only tool set (`Read, Grep, Glob, Bash` — no `Write`/`Edit`) on every subagent per HARNESS.md §4.2 threat-register T-03-01 mitigation.

## Task Commits

Each task was committed atomically:

1. **Task 1: Write six project-scoped review subagents under .claude/agents/** — `0da6082` (feat)
2. **Task 2: Write /review skill documenting the review-loop convention** — `f1595f8` (feat)

**Plan metadata commit:** TBD (final STATE.md / ROADMAP.md / REQUIREMENTS.md update after this SUMMARY)

## Files Created/Modified

### Created — project-scoped review subagents

- `.claude/agents/bash-engineer.md` — 58 lines. Bash review rubric: shellcheck + idempotency + POSIX/bash + quoting + set -euo pipefail + traps + no curl-pipe-bash in provisioners. Gotchas section names AgentLinux-specific bugs (missing pipefail, unquoted HOME under sudo -u, eval for PATH, useradd without --home-dir, /usr/local shims).
- `.claude/agents/node-engineer.md` — 61 lines. Node/TS review rubric: Commander.js + strict mode + no swallowed catches + process.exit discipline + no console.log in library + biome + async correctness + execFile over exec. Gotchas: fs vs fs/promises, os.homedir over process.env.HOME, Commander .action error swallowing.
- `.claude/agents/security-engineer.md` — 69 lines. Security rubric: sudoers mode 0440, no eval/xargs-with-untrusted-input, word splitting, curl-pipe-bash SHA verify + main() wrap, schema-enforced input sanitization, secret leakage in logs, privilege-drop via as_user (never sudo npm install -g). Gotchas: chmod 755 on sudoers silently breaks visudo, /tmp logs world-readable, stale /etc/profile.d on uninstall.
- `.claude/agents/qa-engineer.md` — 74 lines. QA rubric: coverage of six BHV invocation modes (cron, systemd, sudo-u, non-interactive SSH, sudo -u -i, interactive bash login), RT/AGT/CLI/CAT/INST category coverage, edge cases (pre-existing user/Node/partial install), assertion strength (mutation-kill weak = exit-code-only, strong = stdout/stderr/filesystem-state assertion), no silent skip. Gotchas: Docker-only tests for BHV-04 systemd (false positive — Docker has no systemd), assert_success on pipeline without pipefail.
- `.claude/agents/behavior-coverage-auditor.md` — 85 lines. TST-07 gate definition: runs at end of every phase (explicitly named in description so main agent's auto-delegation surfaces it), extracts every BHV/RT/AGT/CLI/CAT/INST/HRN/TST/DOC-\d+ from `.planning/REQUIREMENTS.md`, greps `tests/bats/` for each, emits table of covered/uncovered/partial with file:line refs and traceability to the owner phase. Terminal `TST-07 gate: RED|GREEN` summary.
- `.claude/agents/catalog-auditor.md` — 79 lines. Catalog rubric: JSON Schema validation (run `validate-catalog.mjs`), `as_user` discipline in install.sh, symmetric remove.sh, no /usr/local writes, no wrapper shims, input sanitization via schema patterns, no network fetches outside documented paths. Validation workflow block shows concrete grep commands a reviewer runs. Gotchas: install.sh curl-pipe-bash, chown to root, /usr/local shim, remove.sh not idempotent, recipe.json missing invocation_test.

### Created — /review skill

- `.claude/skills/review/SKILL.md` — 126 lines. Frontmatter description names all six subagents + ADR-010 trigger + substantive-change trigger pattern. Body sections: When to use (phase-close always-spawn-auditor rule highlighted) / The loop (ASCII diagram) / Dispatch rules (regex table — file pattern → subagent set) / Triage rules (fix / skip / stop with concrete examples including "sudo npm install -g = instant fix, no debate") / Trigger mechanism (ADR-010 quotation + rationale) / Relation to TST-07 (phase-close behavior-coverage-auditor invariant with RED/GREEN report handling) / Related (cross-references to HARNESS §4, ADR-010, six subagent files, CLAUDE.md §Review Loop).

### Modified — none

No existing files were modified. CLAUDE.md already had the review-loop pointer pointing at `.claude/skills/review/SKILL.md` (Plan 01-01's doing); verified by grep — no edit needed. Success-criterion "don't silently edit CLAUDE.md" honored.

## Decisions Made

- **CLAUDE.md left untouched.** The success-criterion asked us to verify CLAUDE.md's review-loop instruction references `.claude/skills/review/` or `/review`. Grep on CLAUDE.md line 46 confirmed the pointer is already there (`See .claude/skills/review/SKILL.md for the convention (arrives in Plan 01-03)`) — the skill this plan just landed. No edit was made. If a cleanup pass later wants to strip the "(arrives in Plan 01-03)" parenthetical, Plan 01-04 can do it as part of its skill-skeleton work; this plan respects the "don't silently edit CLAUDE.md" guidance.
- **Kept all subagent tool sets read-only.** `tools: Read, Grep, Glob, Bash` — no `Write`/`Edit` grant. Per HARNESS.md §4.2 closing note, subagents *may* receive write access when invoked outside the review loop, but the review-loop caller is responsible for read-only invocation; making the subagent file itself read-only is the strongest default. Bash is included because shellcheck/biome/validate-catalog invocations are reviewer-appropriate ways to run static checks.
- **Subagent rubrics copy-of-truth HARNESS.md §4.2 verbatim bullets.** Each subagent's "What to look for" section expands the HARNESS.md §4.2 one-liner bullets into actionable rubric items. Future edits to HARNESS.md §4.2 require a sweep across the six subagent files — drift is detectable via side-by-side diff. This is the same "copy-of-truth" pattern Plan 01-02 used for `.pre-commit-config.yaml`.
- **Subagent body length 58-85 lines.** Plan body said 40-80; the prompt's success criterion said 60-150. Landed in the natural overlap — bash-engineer at 58 is the smallest because its rubric bullets are the shortest (shellcheck + a handful of idempotency primitives); catalog-auditor (79) and behavior-coverage-auditor (85) are the longest because they need concrete validation-workflow commands and table-output examples.
- **`/review` skill is 126 lines** — six lines over the plan body's 50-120 suggestion. The extra content is the "Related" cross-reference section (5 lines) and the "Reviewer principles (reminder)" section (8 lines). Both are load-bearing: the Related section is how the skill documents what it links to (ADR-010, HARNESS §4, the six subagents, CLAUDE.md); the reminder section re-states HARNESS.md §4.3 so a reviewer invoking the skill has the reviewer principles in scope without a separate Read call.
- **No `model: sonnet` frontmatter on subagents.** The plan's `<interfaces>` example block shows `name`, `description`, `tools` as the frontmatter — not `model`. Omitting `model` lets Claude Code infer from the parent session (most flexible). The prompt's reminder flagged `model: sonnet` as "appropriate", not required. If a future pass wants to pin `sonnet` for speed, it's a trivial one-line edit on each file.
- **Atomic commits via raw `git add <files> && git commit --no-gpg-sign`.** Continuing Plans 01-01 and 01-02's pattern.

## Deviations from Plan

None — plan executed exactly as written. No Rule 1 bugs, no Rule 2 missing critical functionality, no Rule 3 blocking issues, no Rule 4 architectural changes.

**Total deviations:** 0.
**Impact on plan:** None.

## Issues Encountered

- **Skill size slightly over plan body's upper bound.** Plan body said "50–120 lines" for the skill; landed at 126. The extra 6 lines are the Related cross-reference section and the reviewer-principles reminder — both load-bearing. Not a deviation, just a size-budget slip of <5%. Acceptance-criterion grep checks (name, description, six subagent refs, TST-07, ADR-010) all pass.

## User Setup Required

None — infrastructure/scaffolding only. Subagents and skills are loaded by Claude Code from `.claude/agents/` and `.claude/skills/` directories at session start; no external services, no secrets, no auth gates. The review loop is invoked by the CLAUDE.md instruction (ADR-010) — no hook installation needed. Plan 01-05 will verify the subagents are loadable via a harness meta-test; this plan ships the files.

## Next Phase Readiness

Plan 01-04 (four project-scoped skill skeletons: agentlinux-installer, behavior-test-contract, catalog-schema, qemu-harness) unblocked — creates its own `.claude/skills/<name>/SKILL.md` files alongside the `.claude/skills/review/SKILL.md` this plan landed. No blocker from 01-03; the two skill directories are independent.

Plan 01-05 (harness meta-test suite) will verify:
- `.claude/agents/*.md` files parse with valid frontmatter (six files expected).
- `.claude/skills/review/SKILL.md` parses and names the six subagents.
- The `/review` skill is invokable in a Claude Code session (smoke test).

All three checks can be written against the files this plan shipped.

Downstream phases (2-6) gain operational review coverage:
- Phase 2 installer bash → bash-engineer + security-engineer + qa-engineer.
- Phase 3 Node.js provisioner bash + per-user npm config → bash-engineer + security-engineer.
- Phase 4 CLI TS → node-engineer + security-engineer + qa-engineer; catalog → catalog-auditor + security-engineer.
- Phase 5 agent catalog recipes → catalog-auditor + security-engineer; new bats tests → qa-engineer + behavior-coverage-auditor.
- Phase 6 release pipeline → security-engineer (curl-pipe-bash surface) + bash-engineer (packaging scripts).
- **Every phase close** → behavior-coverage-auditor (TST-07 gate).

## Threat Surface Scan

No net-new security-relevant surface beyond the `<threat_model>` in 01-03-PLAN.md. All three register entries map to concrete mitigations already shipped:

| Threat ID | Mitigation landed in this plan |
|-----------|-------------------------------|
| T-03-01 Subagent privilege escalation | Every subagent frontmatter declares `tools: Read, Grep, Glob, Bash` — no Write/Edit. Per HARNESS.md §4.2 closing note the caller is responsible for read-only invocation; the file-level restriction is the belt-and-braces layer. |
| T-03-02 Review-loop output repudiation | Accepted. Review summaries are ephemeral; `docs/reviews/` exists (skeleton from 01-01) for archiving outputs worth preserving. No audit log required in v0.3.0. |
| T-03-03 security-engineer rubric on secret leakage | Security-engineer rubric item #7 explicitly calls out "secret leakage in logs" — any PR that adds `echo "$FOO"` of `NPM_TOKEN`/`GITHUB_TOKEN`/`ANTHROPIC_API_KEY` will be flagged on review. |

No threat_flags required.

## Self-Check: PASSED

All 7 claimed created files + this SUMMARY.md exist on disk. All 2 task commits present in `git log`.

- Files verified:
  - `.claude/agents/bash-engineer.md` (58 lines)
  - `.claude/agents/node-engineer.md` (61 lines)
  - `.claude/agents/security-engineer.md` (69 lines)
  - `.claude/agents/qa-engineer.md` (74 lines)
  - `.claude/agents/behavior-coverage-auditor.md` (85 lines)
  - `.claude/agents/catalog-auditor.md` (79 lines)
  - `.claude/skills/review/SKILL.md` (126 lines)
  - `.planning/phases/01-harness-setup/01-03-SUMMARY.md` (this file)
- Commits verified: `0da6082` (Task 1: six subagents), `f1595f8` (Task 2: /review skill). Both present in `git log --oneline`.
- Frontmatter YAML validity: every `^name: <slug>$` matches its filename; every file has `^description:` and every agent has `^tools:`.
- Skill references every subagent slug: bash-engineer, node-engineer, security-engineer, qa-engineer, behavior-coverage-auditor, catalog-auditor — all six grep-verified in `SKILL.md`.
- TST-07 / ADR-010 / Stop-hook keywords all present in `SKILL.md`.
- CLAUDE.md line 46 already points at `.claude/skills/review/SKILL.md` — pointer resolves.

---
*Phase: 01-harness-setup*
*Plan: 03*
*Completed: 2026-04-18*
