---
gsd_state_version: 1.0
milestone: v0.3.0
milestone_name: AgentLinux Plugin (Ubuntu)
status: in_progress
stopped_at: Plan 01-02 complete (.pre-commit-config.yaml + four GH Actions workflows + mutation scaffolding). Next plan 01-03 (six review subagents + /review skill).
last_updated: "2026-04-18T10:00:32.000Z"
last_activity: 2026-04-18 — Plan 01-02 complete; HRN-02, HRN-08, TST-06 (scaffolded) satisfied.
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 5
  completed_plans: 2
  percent: 6
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-18)

**Core value:** An agent can be dropped into any supported Linux system and just work — a dedicated agent user with correctly-owned Node.js, agent binaries, and config paths, so self-updates, global npm installs, and tool provisioning happen without permission fights.
**Current focus:** Phase 1 — Harness Setup (project skeleton, pre-commit, CLAUDE.md, ADRs, review subagents, skills, GH Actions scaffolding)

## Current Position

Phase: 1 of 6 (Harness Setup)
Plan: 01-02 ✓ complete — next plan 01-03 (six review subagents + /review skill)
Status: In progress
Last activity: 2026-04-18 — Plan 01-02 complete (3 tasks, 3 atomic commits, ~3 min). Pre-commit config + four GH Actions workflows + mutation scaffolding landed.

Progress: [▓░░░░░░░░░] 6% (2 of ~32 plans done)

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
| 1. Harness Setup (partial) | v0.3.0 | 2/5 | ~7min | ~3.5min |

**v0.3.0 plan metrics:**

| Plan | Tasks | Files | Duration | Commit |
|------|-------|-------|----------|--------|
| 01-01 Skeleton + CLAUDE.md + ADRs + research | 3 | 47 created | ~4 min | 3d65cb2, fa49675, d2ca481 |
| 01-02 Pre-commit + GH workflows + mutation scaffolding | 3 | 9 created | ~3 min | d428627, 6997474, 82abda0 |

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

Last session: 2026-04-18T10:00:32Z
Stopped at: Plan 01-02 complete. HRN-02 (pre-commit config wires shellcheck + shfmt + biome + catalog JSON Schema), HRN-08 (four GH Actions workflows — test, nightly-qemu, nightly-mutation, release), TST-06 (mutation scaffolding: stryker config + bash-mutator.sh, both advisory) satisfied. Summary at `.planning/phases/01-harness-setup/01-02-SUMMARY.md`. Next: execute Plan 01-03 (six review subagents + /review skill).
Resume file: `.planning/phases/01-harness-setup/01-03-PLAN.md`
