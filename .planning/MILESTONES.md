# Milestones

## v0.1.0 AgentLinux Landing Page (Shipped: 2026-03-10)

**Phases completed:** 2 phases, 5 plans
**Timeline:** 2 days (2026-03-09 → 2026-03-10)
**LOC:** 1,045 (HTML/CSS/JS/SVG/XML)

**Key accomplishments:**
- Full landing page with dark terminal aesthetic, crab mascot SVG, and sticky navigation
- Problem/features/comparison content sections with 11 inline Lucide SVG icons
- Email signup form integrated with Buttondown API, FAQ accordion, responsive design
- OG/Twitter meta tags, crab favicon SVG, GA4 analytics snippet, robots.txt, sitemap.xml
- GitHub Actions auto-deploy to GitHub Pages with custom domain agentlinux.org and HTTPS

**Git range:** `5daab9e..133cfa0`
**Archived phases:** `.planning/milestones/v0.1.0-phases/`

---

## v0.2.0 First Distro Image (Retired: 2026-04-18 — pivoted)

**Status:** Partially shipped, then retired during pivot to installable plugin (v0.3.0).

**Phases completed:** 2 of 3 (phases 3 and 4); phase 5 dropped without execution.
**Plans completed:** 5 (3 in phase 3, 2 in phase 4)
**Timeline:** 2026-03-15 → 2026-03-18 active execution

**What shipped:**
- Packer + QEMU build infrastructure for Debian 12 QCOW2 images
- 6-script provisioner chain: base → one-context → Node.js → Chrome → agent-tools → cleanup
- Node.js 22 LTS install from NodeSource (carries forward)
- Chrome install pattern for Chrome DevTools MCP server dependency (carries forward)
- fpm-built `.deb` packages for Claude Code, GSD framework, Chrome DevTools MCP server (reference material)
- Local apt repo embedded in image
- /etc/skel-based Claude Code config with Chrome DevTools MCP pre-wired

**What was dropped:**
- Phase 5 (End-to-End OpenNebula Validation) — not started, retired with pivot
- The QCOW2-image-as-product distribution model
- OpenNebula deploy / contextualize / verify pipeline

**Why retired:** Building a custom distro forces users to migrate their OS to try AgentLinux — high adoption friction, narrow reach. Shipping an installable extension on top of users' existing distros (v0.3.0) delivers the same agent-user-provisioning value with near-zero install friction, broader reach, and reuses provisioner-script logic from this milestone.

**What carries forward into v0.3.0:** Node.js install patterns, Chrome install patterns, Claude Code / GSD / MCP install patterns, /etc/skel default-config approach, fpm packaging knowledge (may apply to plugin's own `.deb` packaging), and lessons about agent-user file ownership for clean self-update.

**Git range:** `5b1cdb4..44a7f03` (approximate; ends with `wip: pause between phases (04 done, 05 not started)`)
**Archived phases:** `.planning/milestones/v0.2.0-phases/`

---

## v0.3.0 AgentLinux Plugin (Ubuntu) — Feature-complete: 2026-04-20

**Phases completed:** 6 + 1 inserted (Phase 5.1)
**Plans completed:** 30
**Timeline:** 2026-04-18 → 2026-04-20 (~3 days active execution)

**Key accomplishments:**
- One-command installable Ubuntu plugin (curl-pipe-bash + optional `.deb` via fpm) with SHA256-verified release tarball
- Dedicated `agent` user provisioned with correctly-owned Node.js 22 LTS runtime, per-user npm prefix at `/home/agent/.npm-global/`, and six-mode PATH wiring (interactive, non-interactive SSH, cron, systemd `User=agent`, `sudo -u agent`, `sudo -u agent -i`)
- Passwordless sudo for agent user via `/etc/sudoers.d/agentlinux` (ADR-012) — required for Playwright `install --with-deps`
- Registry CLI `agentlinux list/install/remove/upgrade/pin` with JSON-Schema-validated catalog (3 real agents available, none installed by default)
- AGT-02 canonical acceptance test green: agent user can `claude update` against the live Anthropic CDN with zero EACCES / permission-denied lines, on both Ubuntu 22.04 + 24.04
- Behavior-test contract: 66/66 bats green on both Ubuntu versions; harness 104/104; 4-gate `release.yml` (pre-commit → Docker matrix → QEMU release gate → pinned-combo gate per ADR-011)

**v0.3.0 ships when:** First `v0.3.0-rc1` tag push exercises `release.yml` end-to-end against the live GitHub Release publish path. Static gates all green; the tag push is the runtime-shipping event.

**Archived planning:** `.planning/milestones/v0.3.0-REQUIREMENTS.md` + `.planning/milestones/v0.3.0-ROADMAP.md` (preserved for traceability; phase directories remain under `.planning/phases/01-*..06-*` until v0.3.0 ships).

---

## v0.4.0 Open-Source Release — IN PROGRESS

**Started:** 2026-04-26

**Goal:** Open-source the AgentLinux GitHub repository — establish OSS licensing, eliminate any leaked secrets from git history, clean up build artifacts and stale branches, verify CI/CD operates correctly under public-repo permissions, and flip visibility to public so AgentLinux can ride free GitHub Actions minutes and accept community contributions.

**Why now:** Private-repo CI/CD spend has become non-trivial as the QEMU release-gate matrix grew (Phase 6 of v0.3.0). Public repos get free Actions minutes. Public visibility also unblocks community contributions and outside marketing/outreach.

See: `.planning/PROJECT.md` and `.planning/ROADMAP.md` for active scope and phases.

---

## v0.3.4 Aware Installation Process — Feature-complete: 2026-05-27 (GATE: GREEN, release-ready)

**Phases completed:** 5 (Phase 12 Detection Layer → 13 Reuse Wiring → 14 Remediate + Consent Flag + Exit Codes → 15 Pre-flight UX → 16 Documentation + Brownfield Acceptance Gate)
**Plans completed:** 12
**Timeline:** 2026-05-10 → 2026-05-27 (~17 days)
**Git range:** `2031151..3d2e8db` (81 commits; 105 files changed, +26,831 / −341)
**Triggered by:** [AL-38](https://copiedwonder.atlassian.net/browse/AL-38) "Introduce proper migration pass for users with some AI setup already"

**Key accomplishments:**
- **Aware install pipeline (DECIDE-THEN-ACT):** the installer detects pre-existing `agent` user, Node.js (8 sources: NodeSource/distro-APT/nvm/fnm/volta/mise/asdf/manual), npm-global prefix + ownership, sudoers drop-in drift, and each catalog agent (claude-code/gsd/playwright — version + path + ownership + health), then dispatches per-component to Reuse / Create / Remediate / Bail. All decisions collected *before* any mutation.
- **Reuse short-circuit (REUSE-01..03):** compatible pre-existing state skips the corresponding provisioner/recipe instead of clobbering; AGGRESSIVE ownership — adopted binaries are managed by `agentlinux upgrade/remove` identically to AgentLinux-installed ones.
- **Remediate paths (REMEDIATE-01..04):** chown npm prefix, refresh PATH wiring, install missing/drifted sudoers, reinstall broken catalog agent — each gated by the single `--yes` consent flag in non-TTY mode; preserve_paths catalog data keeps user config across reinstalls.
- **Pre-flight UX (UX-01..05):** `--dry-run` non-mutating preview (exits 0); TTY per-action `Proceed? [Y/n]` prompts with skip-and-continue (declined → `reused-with-warning` sentinel); alt-user numeric-suffix flow for incompatible existing user; structured exit codes 64 EX_USAGE / 65 EX_DATAERR / 1 runtime / 0 success.
- **Documentation (DOC-01..02):** README "Brownfield install" section linked from main Install; `docs/MIGRATION.md` with 4 worked scenarios (manual `useradd`, NodeSource Node, root-Claude reinstall, broken Playwright cache).
- **Milestone-close gate (brownfield-AGT-02):** on a host pre-populated with a manual `agent` user + NodeSource Node 22 + claude-code/gsd/playwright globals, `agentlinux install --yes` completes and `claude update` against the live Anthropic CDN exits 0 with zero EACCES, version monotonicity holds (2.1.98 → 2.1.150). Transcript at `docs/audits/v0.3.4/AGT-02-brownfield-acceptance.md`.

**Test surface:** 204/204 bats green on Ubuntu 22.04 + 24.04; 165/165 TS unit tests green; greenfield invariant preserved (v0.3.0 baseline + `51-agt02-release-gate.bats` untouched). All 20 requirements satisfied (3-source cross-reference); 0 orphaned.

**v0.3.4 ships when:** First `v0.3.4-rc1` tag push exercises `release.yml` end-to-end. Static gates all green; the tag push is the runtime-shipping event (not yet pushed — held per maintainer).

**Known deferred items at close:** 5 (pre-existing, all predate v0.3.4 — Phase 05 v0.3.0 verification gap [human_needed], 3 legacy quick-task stubs, 1 tooling todo for website PR-preview deploys). See `.planning/STATE.md` § Deferred Items.

**Numbering note:** v0.3.4 was scoped and executed after v0.4.0's feature-complete work (a milestone-rename pass placed the brownfield milestone at v0.3.4); phase directories land under `.planning/phases/12-*..16-*` alongside the v0.3.0/v0.4.0 phases (1-11). The formal `MILESTONES.md` ordering reconciliation rides with v0.4.0's pending closeout.

**Archived planning:** `.planning/milestones/v0.3.4-ROADMAP.md` + `.planning/milestones/v0.3.4-REQUIREMENTS.md`; milestone audit at `.planning/v0.3.4-MILESTONE-AUDIT.md`; per-phase AUDITs under `.planning/phases/{12..16}-*/`.

---
