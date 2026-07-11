# Milestones

## v0.3.5 AlmaLinux 9 Support (Shipped: 2026-07-02)

**Phases completed:** 5 phases (18 Detection + Branching Foundation → 19 Docker AlmaLinux 9 Row → 20 Behavior-Test-Green on AlmaLinux 9 → 21 Catalog Verify on AlmaLinux 9 → 22 QEMU Release-Gate + Pipeline)

**Release:** `v0.3.5` — the plugin now installs and self-updates on AlmaLinux 9 with the identical behavior contract Ubuntu has. Full release gate green: pre-commit + Docker ×4 (Ubuntu 22.04 / 24.04 / 26.04 + **almalinux-9**, all 260/260) + nightly-QEMU (real EL9 GenericCloud guest under systemd + enforcing SELinux) + pinned-combo + build + publish.

**Key accomplishments:**

- **AlmaLinux 9 port without changing the behavior contract:** a distro-family fork point (`AGENTLINUX_DISTRO_FAMILY ∈ {debian,rhel}`) branches the *implementation* (apt→dnf, dpkg→rpm, NodeSource deb→rpm, `/etc/default/locale`→`/etc/locale.conf`, ssh→sshd) while every asserted observable — six-mode invocation contract, zero-EACCES self-update (AGT-02), correctly-owned Node/npm-prefix — holds identically on both families. SELinux stays enforcing (`restorecon`, never `setenforce 0`).
- **Real EL9 release gate:** AlmaLinux 9 is a hard gate in both Docker (fast, every PR) and nightly-QEMU (real GenericCloud VM, enforcing SELinux) — Docker proves fast, QEMU proves real (ADR-007).
- **Playwright on EL9 + Ubuntu 26.04:** browser-launch deps are family-dispatched (Playwright `install-deps` on Debian; an explicit dnf list on EL9); AGT-06 locks that Chromium actually launches headless (0 missing libs + DOM) on every row. Pinned `@playwright/cli` to 0.1.15 so Chromium installs on the newest Ubuntu 26.04.
- **Close-out hardening (found while validating the full matrix):** fixed a bats-1.2.1 `BATS_TEST_TMPDIR`-unset bug that clobbered `/usr/bin` on 22.04/26.04; made the QEMU harness self-heal a stale cloud-image cache; and prompt-synced the interactive-TTY driver to end EL9 flakiness (+ a pre-commit sentinel-drift guard).

**Test surface at ship:** Bats **260/260** on all four Docker rows (22.04 / 24.04 / 26.04 / almalinux-9); nightly-QEMU green (EL9 AGT-02 zero-EACCES + AGT-06 Chromium launch). 14/14 v0.3.5 requirements Done.

**Jira:** anchor [AL-47](https://copiedwonder.atlassian.net/browse/AL-47) (Epic AL-48); phase sub-tasks AL-64..68. **Carried forward:** AL-59 (alt-user hollow-install) and EL-family expansion (Alma 10 / RHEL / Rocky / Fedora) deferred until Alma 9 is daily-driver one cycle.

**Archived phases:** `.planning/milestones/v0.3.5-ROADMAP.md` · `.planning/milestones/v0.3.5-REQUIREMENTS.md` (14/14 complete) · `.planning/milestones/v0.3.5-phases/`

---

## v0.3.4 Aware Installation Process (Shipped: 2026-06-08)

**Phases completed:** 6 phases (12 Detection → 13 Reuse → 14 Remediate + Consent + Exit Codes → 15 Pre-flight UX → 16 Docs + Brownfield Gate → 17 Changes Delivery + Release Candidate)

**Release:** `v0.3.4` — published + marked Latest (https://github.com/Roo4L/Agent-Linux/releases/tag/v0.3.4). SHA256-verified tarball + sibling `.sha256` + `.deb`; full release gate green (pre-commit + Docker ×3 + QEMU ×3 + pinned-combo + build + publish). `/releases/latest` → v0.3.4, so unpinned `curl | sudo bash` installs it.

**Key accomplishments:**

- **Brownfield-aware installer (DECIDE-THEN-ACT):** a pre-flight detection pass classifies the existing host (install user, Node.js, npm prefix, sudoers, catalog agents), then per component decides reuse / create / remediate / bail — never mutating without consent. `--dry-run` previews non-destructively; TTY prompts per state-overwriting action with skip-and-continue; non-TTY uses a single `--yes`; structured exit codes (64/65/1/0) gate automation. 20/20 behavior requirements satisfied (DET/REUSE/REMEDIATE/UX/DOC).
- **Adopt-on-install + honest `list` (AL-61):** the installer adopts pre-existing reuse-eligible agents into managed sentinels after a successful apply, and `agentlinux list` shows present-but-unadopted tools as `present` (with their detected version) instead of the deceptive `not-installed`. New `agentlinux adopt` verb.
- **npm→native Claude Code migration (AL-62):** a Claude Code installed via npm (non-canonical path) is acknowledged as `present` with a migrate hint, and `agentlinux install claude-code` relocates it to the native install **preserving the user's version** — no second competing install, no PATH race.
- **npx-deployed GSD detection (AL-60):** GSD deployed by `npx get-shit-done-cc` (skills + a VERSION file, no global binary) is now classified healthy at its deployed-system canonical presence rather than misreported absent.
- **Maintainer-validated on a real brownfield VM across 4 rc checkpoints** — rc1→AL-60, rc2→AL-61, rc3→AL-62, rc4→LGTM→final. Each rc round surfaced a genuine bug that Docker/QEMU fixtures missed; the live install was the true acceptance gate.

**Test surface at ship:** Bats 215/215 (Ubuntu 24.04; Docker ×3 + QEMU ×3 green in the release gate); TypeScript 184/184; live AGT-02 zero-EACCES re-confirmed in production.

**Jira:** anchor [AL-38](https://copiedwonder.atlassian.net/browse/AL-38) Done; AL-58/AL-60/AL-61/AL-62 Done. **Carried forward:** AL-59 (alt-user hollow-install) under epic AL-48; release.yml `-rc` auto-prerelease; Docker-build-cache CI speedup.

**Known deferred items at close:** 1 (website PR-preview-deployments idea — out of installer scope, a genuine someday-idea kept in `.planning/todos/pending/`; not a v0.3.4 blocker). The 8 other open-artifact-audit hits at close were stale debris — resolved: 7 completed quick-tasks archived to `.planning/quick-archive/`, and the v0.3.0 Phase 05 verification flipped `human_needed → passed` (its network-dependent Docker/AGT-02 re-runs were re-confirmed by the v0.3.4 release gate).

**Archived phases:** `.planning/milestones/v0.3.4-ROADMAP.md` · `.planning/milestones/v0.3.4-REQUIREMENTS.md` (20/20 complete)

---

## v0.3.3 Agenda Redefinition (Shipped: 2026-05-24)

**Phases completed:** 5 phases, 7 plans, 20 tasks

**Key accomplishments:**

- Canonical pillar 2 verdict published with hard reframe (infrastructure, not agent product) + 8/8 EXPL-01 grep tokens + 3-times-stated next-milestone priority + voice-rule-clean Direction subsection — Phase 15's verbatim-lift target ready for consumption.
- Verdict (b) authored at `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md`: security is not a separate pillar in v0.3.3; the one substantive forward-looking commitment — active supply-chain monitoring + curated catalog admission — folds into Pillar 2; phase-close audit emits GREEN with all five EXPL-02 success criteria passing and 12 distinct named-reference tokens cited.
- Phase 15 gate: GREEN.
- Landed the canonical product strategy/roadmap document with the Rumelt-style 5-section spine; amended REQUIREMENTS.md STRATR-02 in the same commit window; captured pre-audit evidence for STRATR-01..06.
- Ran the reviewer pass on docs/STRATEGY.md (inline autonomous mode), triaged 3 LOW comments to skip, and authored 16-AUDIT.md emitting the Phase 16 GREEN gate with all 6 STRATR-XX requirements PASS.
- Repaired `index.html` to remove every contradiction with the post-Phase-14 vision and post-Phase-15 strategy — rewrote hero value-prop, OG/Twitter meta, 6 of 8 `#features` cards + intro, 3 `#comparison` blocks + intro + closing, FAQ #1 + #5; rendered OG card to PNG; amended REQUIREMENTS.md with the 2026-05-24 scope re-cut; and emitted the v0.3.3 milestone-close gate GREEN.

---

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

## v0.4.0 Open-Source Release — Shipped: 2026-05-09

**Started:** 2026-04-26 | **Phases completed:** 5 (Phases 7–11) | **Anchor:** Issue AGE-6

**Key accomplishments:**

- MIT OSS license (ADR-013); LICENSE at repo root, README license badge + section, SPDX headers on first-party source files (LIC-01..04)
- Secret scanning sweep: gitleaks (1 finding, triaged false positive) + trufflehog (0 verified) + targeted manual audit (8 patterns × 255 commits = 0 matches); SEC-04 closes as no-op (ADR-014); gitleaks gate live in pre-commit + CI (SEC-01..05)
- Repository hygiene: 0 stale branches, 0 blobs >500 KB anywhere in history, .gitignore hardened (CLEAN-01..04)
- Public CI/CD readiness: workflow `permissions:` blocks at least-privilege; 0 `pull_request_target` usage; branch protection on `master` applied (CIPUB-01..04)
- Repository visibility flipped to public; anonymous-clone + `curl | bash` smoke test against v0.3.0 release tag both green (PUB-01..04)

**What carries forward into v0.3.3:** Free GitHub Actions minutes (unblocks the broader benchmark + security work pillars 2 and 3 will eventually require). OSS license + CONTRIBUTING surface for external contributors. ADR-001..ADR-014 + behavior-test contract + per-phase TST-07-style phase-close gate convention.

**Archived planning:** `.planning/milestones/v0.4.0-REQUIREMENTS.md` + `.planning/milestones/v0.4.0-ROADMAP.md` (preserved for traceability; phase directories `.planning/phases/07-*..11-*` remain in place — formal archive happens via `/gsd-complete-milestone v0.4.0`).

---

## v0.3.3 Agenda Redefinition — IN PROGRESS

**Started:** 2026-05-09 | **Anchor:** Jira epic [AL-7 — Project agenda redefinition](https://copiedwonder.atlassian.net/browse/AL-7)

**Goal:** Broaden AgentLinux's mission from a single-pillar product ("separated, correctly-owned agent environment") to a three-pillar product, capture the new framing in a canonical product-strategy document, and propagate the framing to the public landing page at agentlinux.org.

**Three pillars (per AL-7):**

1. Separated, correctly-owned agent environment — the existing v0.3.0 core (foundational; not changing in v0.3.3)
2. Stability + best-tested setup with measurable benchmarks (token consumption, speed, task success rate vs vanilla)
3. Security hardening against supply-chain + prompt/tool-injection attacks

**Why now:** A single-pillar framing is too narrow to position AgentLinux against agent-environment competitors and to attract the right contributors. The strategy doc becomes a single source of truth that downstream surfaces (website, CONTRIBUTING, future milestone roadmaps) reference; pillar 2 + pillar 3 implementation lands in v0.6+ milestones with the framing locked.

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
