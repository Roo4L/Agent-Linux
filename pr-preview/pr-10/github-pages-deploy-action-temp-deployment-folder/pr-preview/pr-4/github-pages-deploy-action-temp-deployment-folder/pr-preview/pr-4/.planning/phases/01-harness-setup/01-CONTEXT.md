# Phase 1: Harness Setup - Context

**Gathered:** 2026-04-18
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — smart discuss detected pure scaffolding work)

<domain>
## Phase Boundary

A green development harness is in place so every subsequent phase can ship implementation with its behavior-contract tests enforced by CI and review automation. This phase lands **no installer code** — only project skeleton, pre-commit plumbing, CLAUDE.md, ADRs, review subagents, project-scoped skills, and GitHub Actions scaffolding per `docs/HARNESS.md` §1–§8.

Covers HRN-01..HRN-09 plus the scaffolding subset of TST-06 (mutation-testing harness runnable but advisory) and TST-07 (review-loop hook exists and returns feedback).

Explicitly **out of scope:** any provisioner bash, Node CLI logic, catalog entries beyond the schema, QEMU VM harness runtime (only the workflow skeleton), and any agent-installability work — those ship in Phases 2–5.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — this is pure infrastructure/scaffolding work. The authoritative spec is `docs/HARNESS.md` (already merged). The phase's job is to realize that spec on disk: create every directory, stub file, CLAUDE.md, ADR, workflow YAML, skill skeleton, and pre-commit hook the harness doc calls for, in a way that passes a fresh `pre-commit run --all-files` on an empty plugin.

Key non-negotiables (locked by PROJECT.md and HARNESS.md, not up for debate here):
- Project layout matches `docs/HARNESS.md` §1 exactly (plugin/, tests/, packaging/, docs/, .claude/agents/, .claude/skills/).
- CLAUDE.md stays under 150 lines.
- ADR-001..ADR-010 are seeded verbatim from `docs/HARNESS.md` §2.3 (one file per ADR in `docs/decisions/`).
- Pre-commit covers shellcheck, shfmt, biome, catalog JSON Schema validation.
- Four GH Actions workflows exist as files: `test.yml`, `nightly-qemu.yml`, `nightly-mutation.yml`, `release.yml` — each must pass on an empty-plugin commit.
- Six review subagents exist under `.claude/agents/`: bash-engineer, node-engineer, security-engineer, qa-engineer, behavior-coverage-auditor, catalog-auditor.
- Four project-scoped skill skeletons exist under `.claude/skills/`: `agentlinux-installer`, `behavior-test-contract`, `catalog-schema`, `qemu-harness`.
- Mutation testing (stryker for Node, bash-mutator.sh for bash) is scaffolded and runnable but **advisory only** (does not block merge) — promotion is a v0.4 decision.
- Review loop is triggered by CLAUDE.md instruction, not a Stop hook (ADR-010).

### No Installer Code
No `plugin/provisioner/*.sh`, no `plugin/cli/src/commands/*.ts`, no `plugin/bin/agentlinux-install` beyond the stub entrypoint the HARNESS doc shows. That work is Phase 2+.

### Behavior-Test Contract Respected
No requirements are being re-framed in this phase. HRN-01..HRN-09, TST-06, TST-07 are the contract; tests for them live in `tests/harness/` and must be green at phase close.

</decisions>

<code_context>
## Existing Code Insights

### Repo State
- Empty plugin (no `plugin/`, no `tests/`, no `packaging/`, no `.claude/` directories yet).
- Legacy v0.1.0 site (`index.html`, `assets/`, `CNAME`, `sitemap.xml`, `robots.txt`) lives at repo root and is untouched — v0.3.0 plugin work goes into new top-level directories alongside it.
- Legacy v0.2.0 Packer config in `packer/` is retired (pivot to plugin model) but files remain pending the Phase 6 archive sweep; Phase 1 does **not** delete them.
- `.gitignore` exists but is minimal.
- `docs/HARNESS.md` already exists and is the authoritative spec for this phase.
- `.planning/` already holds PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, MILESTONES.md, RETROSPECTIVE.md, and prior milestone research under `research/`.

### Established Patterns (carry-forward)
- GSD planning layout already in use for this project — Phase 1 artifacts go under `.planning/phases/01-harness-setup/`.
- Commit message convention from git history: `docs(vX.Y.Z): ...` for planning docs, conventional-commit style for code.
- `.mcp.json` already exists at root (`playwright` MCP + GSD references).
- `.github/` directory already exists (workflows may or may not; Phase 1 adds the four required workflows).

### Integration Points
- Pre-commit config attaches to the existing git repo (no new repo init).
- GH Actions workflows land in `.github/workflows/` (existing dir).
- CLAUDE.md is new at repo root; no prior CLAUDE.md to merge with.
- Review subagents register under `.claude/agents/` (project-scoped) and are discoverable by Claude Code when the repo is opened.

</code_context>

<specifics>
## Specific Ideas

- `docs/HARNESS.md` §1 specifies the **exact** project layout — treat it as copy-of-truth. Every directory and file it names must exist by phase close.
- `docs/HARNESS.md` §2.3 lists ADR-001..ADR-010 titles and summaries — use them verbatim as ADR bodies; no research needed.
- `docs/HARNESS.md` §6 specifies CLAUDE.md contents — project identity, critical rules, review-loop instruction, command reference, pointers — under 150 lines.
- `docs/HARNESS.md` §7 specifies the six review subagents and what each looks for.
- `docs/HARNESS.md` §8 specifies the four workflows and their triggers.
- Mutation harness scaffolding only — stryker config for Node, a minimal `bash-mutator.sh` stub. Runnable, reports scores, does **not** block merge.
- GH Actions workflows must each pass on an empty-plugin commit (i.e., no test failures, no missing-file errors) — empty-matrix / skip-on-empty patterns are acceptable.
- Reference template for HARNESS.md patterns is ELS-OS (Python/API/DB) — adapt to bash + Node/TS, **not** copy verbatim.

</specifics>

<deferred>
## Deferred Ideas

- Mutation-testing promotion to release gate — deferred to v0.4 (ADR noted).
- Actual installer scripts, CLI commands, catalog entries — deferred to Phases 2–5.
- QEMU runtime harness (the actual VM boot + bats execution) — deferred to Phase 6; Phase 1 only lands the workflow skeleton.
- Rewriting or migrating the legacy v0.1.0 site at repo root — deferred indefinitely; it coexists with the plugin work.
- Removing the retired `packer/` v0.2.0 directory — deferred to Phase 6 archive sweep.

</deferred>
