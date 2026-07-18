# AgentLinux — Claude Code Guidance

@AGENTS.md

---

The shared, agent-neutral project context lives in `@AGENTS.md` above. This file
adds only the **Claude-Code-specific** mechanics. Codex CLI is supported
alongside Claude Code — see `docs/codex.md`.

## Review Loop — Claude Code reviewer dispatch

Run the review loop (per `AGENTS.md` > "Review Loop" and `@docs/HARNESS.md` §4)
by spawning the project-scoped reviewer subagents that match the changed file
types, via the `.claude/skills/review/` convention. Triggered by this instruction
(primary) plus a one-shot Stop-hook reminder at `.claude/hooks/review-reminder.sh`
(backstop). ADR-010 (refined 2026-05-02): reviewer-invoking hooks remain rejected;
reminder hooks with a `stop_hook_active` guard are allowed.

Reviewers applied by file type:

- Bash → `bash-engineer`, `security-engineer`, `qa-engineer`, `ai-deslop`, `dev-docs-auditor`
- TS/JS → `node-engineer`, `security-engineer`, `qa-engineer`, `ai-deslop`, `dev-docs-auditor`
- Bats spec (`tests/bats/*.bats`) → `qa-engineer`, `behavior-coverage-auditor`
  (the spec is the spec — no `ai-deslop`)
- Bats helpers + Docker/QEMU harness → `qa-engineer`, `bash-engineer`, `ai-deslop`
- Catalog recipes → `catalog-auditor`, `security-engineer`, `ai-deslop`, `dev-docs-auditor`
- Docs → `technical-writer`, `fact-checker`, `ai-deslop` (skip for ADRs and
  research summaries)
- Externally-facing artifacts (top-level `README.md`, `CONTRIBUTING.md`,
  `docs/internals/`, `docs/HARNESS.md`, `docs/STABILITY-MODEL.md`,
  `docs/README.md`, release notes, blog/email drafts, `agentlinux.org` copy,
  user-visible packaging strings) → also `external-audience-auditor`, in
  addition to the per-file-type reviewers above

`external-audience-auditor` flags internal vocabulary that leaks into copy a
public-repo reader (or a blog/email/website excerpt) cannot resolve: AL Jira
keys, GSD plan filenames, BHV/RT/AGT/CLI/CAT/INST/HRN/TST/DOC requirement IDs,
Phase/Plan numbering, bare ADR cross-refs, GSD orchestrator/executor/planner
vocabulary, Claude Code self-references. Skip for `.planning/`,
`docs/decisions/`, `docs/audits/`, `docs/research/`, `.claude/`, and source
comments under `plugin/`/`packaging/`/`tests/` (only user-visible *strings*
under `packaging/` are in scope).

`dev-docs-auditor` keeps `docs/internals/<component>.md` in sync when changes
touch `plugin/bin/`, `plugin/lib/`, `plugin/provisioner/`, `plugin/cli/src/`,
`plugin/catalog/`, or `packaging/curl-installer/`. Skips on pure refactors,
typos, or comment-only changes. See `.claude/skills/dev-docs/SKILL.md` for the
docs contract and the source-path → doc-path dispatch table.

Main agent owns triage: fix what's valid, skip what's noise, iterate until the
remaining comments are not actionable.

Before opening an MR, the global `pre-delivery-cleanup` skill provides a
self-review pass that pairs well with `ai-deslop` — invoke it when the
implementation is finished and tests pass but before the final commit.

## Session Tracking — Claude Code

Track deliverables in Jira project **AL** per `@.claude/skills/session-tracker/SKILL.md`
(details in `AGENTS.md` > "Session Tracking"). A one-shot Stop-hook reminder at
`.claude/hooks/session-tracker-reminder.sh` (backstop, same ADR-010 refinement
that allows the review-reminder hook) nudges Claude to invoke the skill before
stopping. Skip for research-only / Q&A / `.planning/`-only sessions — request
stop again to pass through.

---
*Last updated: 2026-07-18 — split shared context into `AGENTS.md`; this file now
carries Claude-Code-specific mechanics only.*
