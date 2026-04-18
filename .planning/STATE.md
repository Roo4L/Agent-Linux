---
gsd_state_version: 1.0
milestone: v0.3.0
milestone_name: AgentLinux Plugin (Ubuntu)
status: in_progress
stopped_at: Plan 01-04 complete (four project-scoped skill skeletons: agentlinux-installer, behavior-test-contract, catalog-schema, qemu-harness). Next plan 01-05 (harness meta-test suite — closes Phase 1 acceptance gate).
last_updated: "2026-04-18T10:51:25.000Z"
last_activity: 2026-04-18 — Plan 01-04 complete; HRN-09 satisfied.
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 5
  completed_plans: 4
  percent: 12
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-18)

**Core value:** An agent can be dropped into any supported Linux system and just work — a dedicated agent user with correctly-owned Node.js, agent binaries, and config paths, so self-updates, global npm installs, and tool provisioning happen without permission fights.
**Current focus:** Phase 1 — Harness Setup (project skeleton, pre-commit, CLAUDE.md, ADRs, review subagents, skills, GH Actions scaffolding)

## Current Position

Phase: 1 of 6 (Harness Setup)
Plan: 01-04 ✓ complete — next plan 01-05 (harness meta-test suite — closes Phase 1 acceptance gate)
Status: In progress
Last activity: 2026-04-18 — Plan 01-04 complete (2 tasks, 2 atomic commits, ~4 min). Four project-scoped skill skeletons (agentlinux-installer, behavior-test-contract, catalog-schema, qemu-harness) landed under .claude/skills/<name>/SKILL.md — each with valid Claude Code frontmatter, non-negotiable rules codified, and an explicit growth plan for the phase that absorbs it (Phase 2+/Phase 4/Phase 6). HRN-09 satisfied.

Progress: [▓░░░░░░░░░] 12% (4 of ~32 plans done)

## Performance Metrics

**Velocity:**
- Total plans completed: 10 (5 v0.1.0, 5 v0.2.0)
- Average duration: ~3 min per plan

**By Phase (historical):**

| Phase | Milestone | Plans | Total | Avg/Plan |
|-------|-----------|-------|-------|----------|
| 1. Complete Website | v0.1.0 | 3 | ~6min | ~2min |
| 2. Deploy to Public | v0.1.0 | 2 | ~3min | ~1.5min |
| 3. Bootable Image | v0.2.0 | 3 | ~14min | ~4.7min |
| 4. Agent Tool Packages | v0.2.0 | 2 | ~5min | ~2.5min |
| 1. Harness Setup (partial) | v0.3.0 | 4/5 | ~45min | ~11.3min |

**v0.3.0 plan metrics:**

| Plan | Tasks | Files | Duration | Commit |
|------|-------|-------|----------|--------|
| 01-01 Skeleton + CLAUDE.md + ADRs + research | 3 | 47 created | ~4 min | 3d65cb2, fa49675, d2ca481 |
| 01-02 Pre-commit + GH workflows + mutation scaffolding | 3 | 9 created | ~3 min | d428627, 6997474, 82abda0 |
| 01-03 Review subagents + /review skill | 2 | 7 created | ~34 min | 0da6082, f1595f8 |
| 01-04 Four project-scoped skill skeletons | 2 | 4 created | ~4 min | d46f2dd, 53db3ec |

## Accumulated Context

### Decisions

Full decision log in PROJECT.md Key Decisions table. ADR-001..ADR-010 ✓ seeded in `docs/decisions/` during Plan 01-01 (2026-04-18), each Accepted:
- ADR-001: Pivot from custom distro to installable Ubuntu plugin (v0.2.0 → v0.3.0) ✓
- ADR-002: Behavior-contract framing — requirements are BHV-XX, not INST-XX; tests are the spec ✓
- ADR-003: No default agents installed in v0.3.0 ✓
- ADR-004: Per-user npm prefix as the keystone ownership decision ✓
- ADR-005: System Node.js (NodeSource) over version managers (nvm/fnm/volta) ✓
- ADR-006: curl-pipe-bash primary + optional .deb distribution ✓
- ADR-007: Docker (fast) + QEMU (release gate) test harness; Docker-only is disqualified ✓
- ADR-008: Commander.js for the registry CLI ✓
- ADR-009: Snap is structurally disqualified as a distribution mechanism ✓
- ADR-010: Review loop triggered by CLAUDE.md instruction, not a Stop hook ✓

**New decisions from Plan 01-01 execution:**
- Copy research rather than move: `.planning/research/` and `.planning/milestones/v0.2.0-research/` kept intact; `docs/research/vX.Y.Z/` copies are byte-exact (`diff -q` verified). Archive sweep deferred to Phase 6.
- Per-task atomic commits via raw `git add <files> && git commit --no-gpg-sign`, not `gsd-tools.cjs commit` (which auto-stages all working-tree changes and breaks atomic per-task commits in sequential mode).
- CLAUDE.md deliberately references skills that arrive later in the phase (`.claude/skills/review/` in Plan 01-03, four more in Plan 01-04); flagged with "arrives in Plan 01-0X" to set reader expectations.

**New decisions from Plan 01-02 execution:**
- `.pre-commit-config.yaml` is a **verbatim copy** of `docs/HARNESS.md` §1.2; drift is detectable by a single `diff` command, making HARNESS.md the authoritative spec.
- `validate-catalog.mjs` is kept strictly zero-dep (Node built-in `fs` + `JSON.parse`); ajv swap-in deferred to Phase 4 via inline `// TODO Phase 4:` comment in the script header.
- Mutation scaffolding is non-blocking at **three independent layers**: `stryker.config.json` `thresholds.break: 0`, `nightly-mutation.yml` job-level `continue-on-error: true`, `bash-mutator.sh` always exits 0 on the current skeleton. No single layer can drag the release pipeline red.
- Every CI workflow is authored with a `compgen -G` / `[[ -x ... ]]` empty-plugin guard so skeleton-phase commits green-bar without fake test files. Guards skip jobs whose sources (tests/, bats/, CLI source) do not yet exist.
- Legacy `.github/workflows/deploy.yml` (v0.1.0 website) left completely untouched; the new `test.yml` uses `paths-ignore` for website files so the two workflows do not double-fire.

**New decisions from Plan 01-04 execution:**
- CLAUDE.md left untouched (same posture as Plan 01-03): Plan 01-01's Pointers section at lines 77-79 already lists all four skill directories; grep over each slug confirmed references resolve. Success-criterion "No overlap with /review skill from 01-03" honored — all four new skills live in their own subdirectories alongside `.claude/skills/review/`.
- Skeleton body size 93-116 lines each (plan body suggested 30-80 per section / 40-80 per body; prompt's success-criterion said 50-120). Landed in the 93-116 band because every skeleton has three uncompressible parts: (1) frontmatter description naming every trigger for Claude Code's skill auto-delegation, (2) the non-negotiable rules that will not drift as later phases fill in detail (strict mode, `as_user`, mode 0440, six-mode PATH matrix, no-EACCES contract, CAT-02 invariant, SHA-verified cloud images), (3) the growth-plan section naming which artifacts absorb in which phase. Trimming any of these would either weaken the "locked rules before code exists" property or break future agents' ability to find what they need without a separate Read.
- Growth phases named in BOTH description and body (`## Growth plan` section). A future agent opening the skill knows immediately whether each section is a locked contract or placeholder awaiting Phase N.
- Requirement-ID linkage in each skill's opening paragraph — the linkage the `behavior-coverage-auditor` needs at phase-close to trace "skill X → requirement Y → test Z".
- Per-task atomic commits via raw `git add <files> && git commit --no-gpg-sign` (continuing Plans 01-01, 01-02, 01-03 pattern).

**New decisions from Plan 01-03 execution:**
- CLAUDE.md left untouched: line 46 already pointed at `.claude/skills/review/SKILL.md` (Plan 01-01's doing). Success-criterion was to verify the pointer resolves — it does, so no silent edit was made.
- All six subagents ship with read-only tool sets (`tools: Read, Grep, Glob, Bash` — no Write/Edit) per HARNESS.md §4.2 threat-register T-03-01 mitigation. Write access can be granted when spawned outside the review loop, but the file-level restriction is the belt-and-braces layer.
- Subagent rubrics are copy-of-truth for `docs/HARNESS.md` §4.2: every rubric bullet expands a HARNESS.md §4.2 one-liner. Same pattern Plan 01-02 used for `.pre-commit-config.yaml`. Future HARNESS.md §4.2 edits require a sweep across the six subagent files — drift is detectable via diff.
- Subagent files omit `model:` frontmatter (let Claude Code infer from parent session); the plan's `<interfaces>` example only declared `name`, `description`, `tools`. Pinning `sonnet` is a trivial one-line edit if future tuning wants it.
- `/review` skill explicitly names `behavior-coverage-auditor` as the "always spawn at phase close regardless of what changed" TST-07 gate — the rule is in the dispatch-rules table (last row) and in a dedicated "Relation to TST-07" section, so no phase can close without the report.

**Carried forward from v0.2.0 (still relevant for plugin installer):**
- Node.js 22 LTS from NodeSource as the runtime baseline (install path proven)
- npm install -g for Claude Code / GSD packages (but now as the agent user, not root)
- MCP config merged into ~/.claude.json via jq (works for default-agent setup)
- Chrome install pattern for browser-access tool (now under Playwright in the v0.3.0 catalog)
- Provisioner script chain pattern (ordered numbered scripts) translates to installer phases

**Retired with pivot:**
- Debian 12 Bookworm base — superseded by "target user's existing Ubuntu"
- Packer + QEMU image build — replaced by Docker (fast) + QEMU (release gate) test harnesses
- fpm-built `.deb`s as distribution artifacts — superseded by in-installer npm install (fpm may return as the plugin's own optional .deb packaging)
- Local apt repo in image — N/A
- OpenNebula contextualization — N/A
- one-context-based agent user creation — replaced by direct useradd in installer
- chrome-devtools-mcp as the canonical browser tool — replaced by Playwright per locked decision

**New for v0.3.0:**
- Ubuntu as initial target distro (22.04 + 24.04)
- Canonical acceptance test: agent user can self-update Claude Code without sudo/EACCES (AGT-02)
- Behavior-contract framing: bats test suite is the spec
- No default agents — catalog ships claude-code, gsd, playwright as *available*; users opt in
- Phase 1 is Harness Setup (non-negotiable); restart phase numbering at 1
- Mutation testing is advisory in v0.3.0; promotion to release gate is a v0.4 decision

### Key Infrastructure Details

OpenNebula API and target VM details from v0.2.0 are no longer load-bearing. Test infrastructure for v0.3.0:
- Docker matrix (ubuntu:22.04, ubuntu:24.04) — fast, every PR (lands in Phase 2)
- QEMU with fresh Ubuntu cloud images — nightly + release gate (lands in Phase 6)

### Pending Todos

- [ ] Add PR preview deployments for website (tooling)
- [ ] Convert OG image from SVG to PNG for broader social platform support

### Blockers/Concerns

None. Roadmap created; all 46 requirements mapped; Phase 1 is ready to plan.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-04-18T10:51:25Z
Stopped at: Plan 01-04 complete. HRN-09 (four project-scoped skill skeletons under `.claude/skills/` — `agentlinux-installer` (93 lines, bash installer conventions, grows Phase 2+), `behavior-test-contract` (104 lines, bats test authoring, grows Phase 2+), `catalog-schema` (103 lines, catalog entry format + install-recipe contract, grows Phase 4), `qemu-harness` (116 lines, QEMU release-gate flow, grows Phase 6)) satisfied. Every skeleton has valid YAML frontmatter matching its directory slug, a description engineered for Claude Code's skill auto-delegation, non-negotiable rules that will not drift (set -euo pipefail, idempotency primitives, as_user keystone, sudoers mode 0440, six-invocation-mode PATH matrix, no-EACCES contract, CAT-02 no-default-agents invariant, ADR-007 Docker-only-disqualified rationale), and an explicit growth plan. Summary at `.planning/phases/01-harness-setup/01-04-SUMMARY.md`. Next: execute Plan 01-05 (harness meta-test suite — closes Phase 1 acceptance gate).
Resume file: `.planning/phases/01-harness-setup/01-05-PLAN.md`
