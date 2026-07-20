# AgentLinux

## What This Is

AgentLinux is an **installable extension for Linux distributions** that turns a user's existing system into an agent-ready environment. Instead of shipping a whole distro, AgentLinux installs on top of popular distros (Ubuntu first; Fedora / CentOS / Alma / Arch later) and provisions a dedicated agent user, a correctly-owned Node.js runtime, and a curated registry for installing additional agents. Users opt into catalog agents explicitly.

The project also maintains a landing page at **agentlinux.org** for validation and subscriber collection.

## Core Value

An agent can be dropped into any supported Linux system and *just work* — a dedicated agent user with correctly-owned Node.js, agent binaries, and config paths, so self-updates, global npm installs, and tool provisioning happen without permission fights, sudo prompts, or recursive-shim workarounds. Installing AgentLinux on your distro gives you an agent environment that was built right the first time.

## Current State

**Shipped:** v0.3.4 Aware Installation Process — **SHIPPED 2026-06-08** (final release `v0.3.4`, marked Latest; maintainer-validated on a real brownfield VM across 4 rc checkpoints — rc1→rc4 each fixed a found bug: AL-60 npx-GSD detection, AL-61 adopt-on-install + honest `list`, AL-62 npm→native Claude Code migration). Full release gate green (Docker ×3 + QEMU ×3 + pinned-combo + publish); `/releases/latest` → v0.3.4.

**What v0.3.4 delivers:** AgentLinux installation is now aware of pre-existing AI/agent setups on the host. The installer detects pre-existing `agent` user, Node.js, npm-global prefix, Claude Code, GSD, and Playwright, then either reuses (compatible state), creates (absent), remediates (fixable drift), or bails (incompatible) on a per-component basis. `agentlinux install --dry-run` provides a non-mutating preview; TTY mode prompts per state-overwriting action with skip-and-continue semantics; non-TTY mode uses the single `--yes` consent flag (Unix convention). Structured exit codes (64 EX_USAGE, 65 EX_DATAERR, 1 runtime, 0 success) gate downstream automation. The brownfield-AGT-02 milestone-close gate verified `claude update` succeeds with zero EACCES on a pre-populated host against the live Anthropic CDN.

**Test surface at ship:** 215/215 bats green on Ubuntu 24.04 (204 feature-complete baseline + 11 rc-fix additions for AL-61/AL-62); Docker ×3 + QEMU ×3 green in the v0.3.4 release gate; 184/184 TS unit tests green (165 baseline + 19 rc-fix); greenfield invariant preserved (v0.3.0 baseline @tests untouched); live AGT-02 zero-EACCES re-confirmed in production.

**Documentation:** README has a new `## Brownfield install` section linked from main Install; `docs/MIGRATION.md` walks 4 worked scenarios (manual `useradd`, NodeSource Node, root-Claude reinstall, broken Playwright); per-phase AUDITs at `.planning/phases/{12..16}-*/`-AUDIT.md`; milestone audit at `.planning/v0.3.4-MILESTONE-AUDIT.md`.

## Current Milestone: v0.3.6 Catalog Expansion — community agent tooling for first release

**Goal:** Grow the catalog from 3 entries to 26 of the most trusted/popular AI-agent-community tools (availability only — CAT-02 holds; nothing installed by default), so first-release users don't hit "I miss tool X."

**Target features:**
- Coding-agent CLIs (4): opencode, antigravity-cli, codex, qwen-code
- MCP servers (10): chrome-devtools, context7, github, sentry, gitlab, brave-search, firecrawl, slack, linear, jira-atlassian
- DevOps/git CLIs (5): gh, glab, sentry-cli, trivy, gitleaks
- Token/workflow tools (5): ccusage, rtk, spec-kit, claude-flow, BMAD
- AI assistants (2, new daemon-class category): openclaw, hermes-agent
- 4 machinery enablers — prebuilt-binary installer, MCP recipe pattern (npx + remote-http + secret convention), Python+uv bootstrap, AI-assistant daemon lifecycle — folded into first-consumer phases; plus self-updater coexistence, `list` category UX, and a contributor recipe template + selection-rubric doc.

**Structure:** one tool per phase (**27 phases, 23–49**; each phase ships one working, tested tool — enablers ride with their first consumer). Tools selected via a documented gates+scoring funnel (agent-relevance · clean per-user install + symmetric uninstall · free license · liveness ≤6mo release & ≤3mo commits · maturity).

**Parallel-milestone note:** v0.3.5 (AlmaLinux 9, phases 18–22, AL-64..68, Epic AL-48) is in flight on the `worktree-almalinux-support` branch. Catalog Expansion was deliberately numbered **v0.3.6 / phases 23–49** to avoid version + phase collision; PROJECT.md / MILESTONES.md / ROADMAP.md will need merge reconciliation between the two branches.

## Next Milestone Goals

- **v0.3.5 AlmaLinux support** (AL-47 / Epic AL-48): port the aware-install pipeline to AlmaLinux 9. Phase 12-15 detection layer is mostly distro-portable; brownfield-AGT-02 gate runs against a different baseline (DNF + EL8/EL9 idiom). *(Now in flight on a separate worktree as v0.3.5 / phases 18–22.)*
- **AL-59 alt-user hollow-install** (carried forward from v0.3.4, under Epic AL-48): the installer's alt-user path needs end-to-end wiring (20-sudoers.sh / 30-nodejs.sh / 40-path-wiring.sh still hardcode `agent`).

<details>
<summary>v0.3.4 Aware Installation Process — original goal (archived 2026-05-27)</summary>

**Goal:** Make AgentLinux installation aware of pre-existing AI/agent setups on the host — pre-existing `agent` user, Node.js, npm-global prefix, Claude Code, GSD, Playwright — and either reuse, remediate, or bail with a clear error rather than failing or silently overwriting user state. Triggered by [AL-38](https://copiedwonder.atlassian.net/browse/AL-38).

**Target features (all delivered):**
- Detection pass (DET-01..06): discovery layer catalogs pre-existing agent user, Node.js installs, npm-global prefix + ownership, sudoers drift, catalog agent state
- Reuse path (REUSE-01..03): compatible state → skip the corresponding provisioner / recipe
- Remediate path (REMEDIATE-01..04): mostly-correct state → fix in place, gated by `--yes` in non-TTY mode
- Pre-flight report (DET-06): text + JSON report before any mutation
- Dry-run mode (UX-01): `agentlinux install --dry-run` non-mutating preview
- Non-interactive default + `--yes` (UX-03, UX-05): cron/CI safe defaults; structured exit codes 64/65/1/0
- Interactive prompts (UX-02, UX-04): per-action prompts in TTY mode; alt-user-name prompt for incompatible existing user
- Documentation (DOC-01, DOC-02): README "Brownfield install" + `docs/MIGRATION.md`

Archived: `.planning/milestones/v0.3.4-ROADMAP.md`, `.planning/milestones/v0.3.4-REQUIREMENTS.md`.
</details>

## Previous Milestone: v0.4.0 Open-Source Release — feature-complete (formal closeout pending)

v0.4.0 (Open-Source Release) shipped Phases 7–11 (License + CONTRIBUTING; gitleaks/trufflehog history audit + scanner gate; repo hygiene + branch cleanup; public-CI/CD audit + branch protection; visibility flip + post-flip smoke). The status section of this document and `MILESTONES.md` are scheduled for a maintenance pass that reconciles the formal closeout. v0.3.4 numbering reflects a milestone-rename pass; the formal `MILESTONES.md` ordering will be updated in that same pass.

## Earlier Milestones

### v0.3.0 AgentLinux Plugin (Ubuntu) — feature-complete 2026-04-20 (preserved here pending v0.4.0 closeout reconciliation)

v0.3.0 shipped the installable Ubuntu plugin in 6 phases (Harness, Installer Foundation + Agent User, Node.js Runtime, Registry CLI + Catalog, Agent Installability, Distribution + Release Pipeline) plus one inserted phase (5.1 Agent User Sudo Drop-In). All 54 v0.3.0 requirements have observable bats coverage, both Ubuntu 22.04 + 24.04 Docker matrices and the QEMU release-gate suite are green, and AGT-02 (the canonical "Claude Code self-updates without sudo / EACCES" acceptance test) passes end-to-end against the live Anthropic CDN. The v0.3.0 release pipeline is wired (4-gate `release.yml`: pre-commit → Docker matrix → QEMU release gate → pinned-combo gate) and awaits its first `v0.3.0-rc1` tag push as the shipping event. v0.4.0 (open-sourcing) does not block on the rc1 tag — repo cleanup runs in parallel.

**What carries forward:** The behavior-test contract (bats suite as spec), curl-pipe-bash installer, catalog + registry CLI, ADR-001..ADR-012, and the phase-close TST-07 behavior-coverage-auditor gate. v0.4.0 phases follow the same per-phase TST-07 pattern: every requirement gets at least one verifiable check (bats @test, CI-gate citation, or auditable artifact) before the phase closes.

## Earlier Milestones

### v0.2.0 First Distro Image (retired 2026-04-18 — pivot)

The v0.2.0 milestone aimed to ship a custom Linux distribution (Debian 12 QCOW2 for OpenNebula/KVM) with agent tooling pre-baked as `.deb` packages. Phases 1–4 shipped (Packer infrastructure, Node.js install, Chrome install, Claude Code / GSD / Chrome DevTools MCP fpm packaging). Phase 5 (end-to-end OpenNebula validation) was dropped along with the distro-as-product approach.

**Why the pivot:** Building a distro forces users to migrate their OS to try AgentLinux — high adoption friction, narrow reach. Shipping an installable extension on top of their existing distro delivers the same agent-user-provisioning value with a fraction of the friction, and lets AgentLinux ride on top of the distro ecosystem's existing packaging/update infrastructure.

**What carries forward:** Provisioner script logic from v0.2.0 (Node.js install, Chrome install, Claude Code / GSD / MCP install patterns, correct-ownership-for-the-agent-user lessons) ports directly into the v0.3.0 plugin installer. fpm packaging experience may inform the plugin's own `.deb` packaging if that distribution mechanism is chosen.

## Requirements

### Validated

- ✓ Landing page with terminal/hacker aesthetic (dark theme, monospace, CLI feel) — v0.1.0
- ✓ Problem explainer section with current pain points (permissions, Docker-in-Docker, VM friction) — v0.1.0
- ✓ Feature showcase with 8 planned AgentLinux capabilities and SVG icons — v0.1.0
- ✓ Narrative comparison of AgentLinux vs alternatives (local, Docker, VMs) — v0.1.0
- ✓ Email subscription form integrated with Buttondown — v0.1.0
- ✓ Static site (HTML/CSS/JS) with no build step — v0.1.0
- ✓ Custom domain agentlinux.org with HTTPS on GitHub Pages — v0.1.0
- ✓ GitHub Actions auto-deploy on push to master — v0.1.0
- ✓ FAQ accordion section — v0.1.0
- ✓ Responsive design (mobile + desktop) — v0.1.0
- ✓ Crab mascot SVG and favicon — v0.1.0
- ✓ OG/Twitter meta tags for social sharing — v0.1.0
- ✓ GA4 analytics, robots.txt, sitemap.xml — v0.1.0
- ✓ Node.js 22 LTS from NodeSource install patterns — v0.2.0 (carries into v0.3.0 plugin installer)
- ✓ Claude Code / GSD / Chrome DevTools MCP install patterns via npm + /etc/skel config — v0.2.0 (carries forward)
- ✓ Chrome install pattern for MCP server dependency — v0.2.0 (carries forward)
- ✓ fpm-based `.deb` packaging workflow — v0.2.0 (reference material for plugin distribution)
- ✓ One-command Ubuntu installer (curl-pipe-bash + optional `.deb`) — v0.3.0
- ✓ Dedicated agent user with correctly-owned Node.js runtime + per-user npm prefix (no sudo for global installs) — v0.3.0
- ✓ Six-mode PATH wiring (interactive, non-interactive SSH, cron, systemd `User=agent`, `sudo -u agent`, `sudo -u agent -i`) — v0.3.0
- ✓ Passwordless sudo for the agent user via `/etc/sudoers.d/agentlinux` (ADR-012) — v0.3.0 phase 5.1
- ✓ Registry CLI `agentlinux list/install/remove/upgrade/pin` with JSON-Schema-validated catalog — v0.3.0
- ✓ Three catalog agents — claude-code, gsd, playwright — opt-in installable; no defaults — v0.3.0
- ✓ Canonical acceptance test AGT-02: Claude Code self-update without sudo / EACCES — v0.3.0 (live against Anthropic CDN, both Ubuntu 22.04 + 24.04)
- ✓ Bats behavior-test suite + Docker matrix + QEMU release-gate suite + 4-gate `release.yml` — v0.3.0
- ✓ Pinned-combo release gate (TST-08) + catalog snapshot publication (CAT-05) per ADR-011 — v0.3.0

### Active (v0.3.5 — AlmaLinux 9 Support)

See `.planning/REQUIREMENTS.md` for the full v0.3.5 requirement list (populated by the milestone roadmap — categories TBD at requirements time: e.g. DETECT, HARNESS, BEHAVE, CAT, REL). Headline outcome: `curl … | bash` installs the plugin on AlmaLinux 9 with the same six-mode contract and zero-EACCES self-update gate Ubuntu has.

### Validated (v0.3.4 — Aware Installation Process; SHIPPED 2026-06-08)

v0.3.4's DET / REUSE / REMEDIATE / UX / DOC requirements shipped end-to-end (maintainer-validated across rc1→rc4). Detail archived at `.planning/milestones/v0.3.4-REQUIREMENTS.md`. Headline outcomes (all delivered):

- [ ] Pre-flight detection pass identifies pre-existing agent user, Node.js, npm-global prefix, sudoers drop-in, and each catalog agent — surfaced as a Reuse / Create / Remediate / Bail report
- [ ] `agentlinux install --dry-run` prints the report and exits 0 without mutation
- [ ] Reuse path: compatible pre-existing components are reused; provisioners / recipes short-circuit instead of clobbering
- [ ] Remediate path: incompatible-but-fixable components (wrong ownership, missing PATH wiring, drifted sudoers, broken agent install) are fixed — overwrites of user state require an explicit flag in non-interactive mode
- [ ] Non-interactive default is reuse-or-bail; interactive mode prompts for alternate user name when `agent` clashes and for reinstall confirmation when an agent tool fails its health check
- [ ] README "Brownfield Install" section + `docs/MIGRATION.md` cover the common pre-existing-setup scenarios

### Validated (v0.4.0 — Open-Source Release; formal closeout pending)

The v0.4.0 requirement set (LIC / SEC / CLEAN / CIPUB / PUB) shipped end-to-end with audit evidence under `docs/audits/v0.4.0/`. Formal status reconciliation (move to Validated, fold into MILESTONES.md) is scheduled for the next maintenance pass alongside the milestone-rename. Detail preserved in `.planning/milestones/v0.4.0-REQUIREMENTS.md`.

### Out of Scope

**v0.3.5 out of scope:**
- AlmaLinux 10 — deferred until the maintainer hits first-person friction on it; filed as a follow-up ticket then, not pre-emptively
- RHEL, Rocky, Fedora, or any other dnf-based distro — until AlmaLinux 9 is the maintainer's daily driver and stable for one release cycle (first-person friction first; family-wide claims later)
- AL-59 alt-user hollow-install wiring — distro-independent; planned separately under Epic AL-48 (kept out to preserve the milestone boundary and matrix size)
- Snap, flatpak, or any alternative packaging path
- New catalog agents beyond the existing three (claude-code, gsd, playwright) — port-only milestone

**v0.3.4 out of scope:**
- New distro targets (Fedora / CentOS / Alma / Arch / openSUSE) — still deferred; brownfield-aware install is Ubuntu-only for v0.3.4
- New catalog agents beyond the existing three (claude-code, gsd, playwright) — catalog churn happens in feature milestones, not the brownfield-aware one
- Auto-detection of arbitrary user-installed npm globals outside the catalog (e.g. `npx`, `tsx`, `vercel`) — out of scope; AgentLinux only owns its catalog
- Auto-migration of nvm / fnm / volta / mise managed Node.js installs to a system Node.js install — surfaced as "Bail" with a clear remediation hint, not auto-rewritten
- Replacing or migrating an existing user's shell init files (`.bashrc`, `.profile`) — additive `ensure_marker_block` only; never edit pre-existing lines
- Multi-arch (ARM) — x86_64 only for now (carried forward)

**v0.4.0 out of scope (carried forward):**
- New distro targets (Fedora / CentOS / Alma / Arch / openSUSE) — deferred to a later milestone
- Mutation testing promotion to release gate — still v0.5+ per ADR-010
- Repo migration to a different GitHub organization or rename — out of scope

**v0.3.0 out of scope (carried forward):**
- Fedora / CentOS / Alma / Arch / openSUSE targets (deferred to a later feature milestone)
- GUI or TUI installer (CLI only)
- Public PPA / package-signing infrastructure beyond curl-installer + GitHub Releases
- Multi-user provisioning (one agent user per host for now)
- Sandboxing / rootless containers inside the installer
- Custom distro / ISO / QCOW2 image build path — retired with the v0.2.0 → v0.3.0 pivot
- OpenNebula contextualization, deploy, and E2E test pipeline — retired with the v0.2.0 → v0.3.0 pivot
- `.deb` packages for Claude Code / GSD / MCP as standalone distro artifacts — superseded by in-installer npm install

**Permanently out of scope:**
- User accounts or login functionality on website
- Blog or content management system
- Mobile app
- E-commerce / payments
- Multi-arch (ARM) — x86_64 only for now
- Docker-in-Docker inside the agent environment

## Context

**Website (v0.1.0, shipped 2026-03-10):** Landing page at agentlinux.org, 1,045 LOC HTML/CSS/JS/SVG/XML, deployed via GitHub Actions. Continues to serve as top-of-funnel validation channel.

**Distro experiment (v0.2.0, retired 2026-04-18):** Packer + QEMU + fpm stack produced bootable Debian 12 QCOW2 images with three agent tools pre-packaged. Useful provisioner-script learnings. Retired because distro-as-product has too much adoption friction vs. an installable extension.

**Plugin (v0.3.0, feature-complete 2026-04-20):** All 6 phases plus inserted phase 5.1 shipped. 54/54 requirements covered. Awaits the first `v0.3.0-rc1` tag push as the runtime-shipping event.

**Open-Source Release (v0.4.0, feature-complete; formal closeout pending):** Phases 7–11 shipped end-to-end (license + CONTRIBUTING; gitleaks/trufflehog history audit + scanner gate; repo hygiene + branch cleanup; public-CI/CD audit + branch protection; visibility flip + post-flip smoke). Audit evidence under `docs/audits/v0.4.0/`. The formal `MILESTONES.md` reconciliation + the milestone-rename pass (which makes v0.3.4 numerically subsequent in the project's revised cadence) are scheduled for the next maintenance pass.

**Aware Installation (v0.3.4, current):** AgentLinux's installer was designed assuming a fresh host. In practice agents run on long-lived VMs that already have an `agent` user, Node.js, and one or more catalog tools installed — often partially, often with permission drift. v0.3.4 introduces a detection-driven path through the installer: pre-flight discovery of every component AgentLinux owns, a Reuse / Create / Remediate / Bail decision per component, a dry-run mode, and a non-interactive default that never overwrites user state without an explicit flag. The bug class is the same one v0.3.0 exists to eliminate — surprise privilege fights — but viewed from the brownfield direction. Triggered by AL-38; the canonical acceptance test is "agent installation completes cleanly on a host with Claude Code, GSD, and Playwright already present, AGT-02 self-update still green afterwards."

Known minor issue: OG image (SVG format) doesn't render on all social platforms — convert to PNG for broader support (website todo).

## Constraints

- **Target OS (v0.3.0):** Ubuntu LTS — 22.04 (Jammy), 24.04 (Noble), 26.04 (Resolute Raccoon, added 2026-04-26 per AGE-11). Fedora/CentOS/Alma/Arch deferred.
- **Install UX:** one-command from user perspective; internally may chain apt / curl / npm / fpm.
- **Node.js ownership:** must be owned by the agent user or use a writable global prefix under the agent user's home — no `sudo npm install -g`.
- **Test harness:** containerized or QEMU-based; no real-hardware / cloud-VM deploy step.
- **Website stack:** Static HTML/CSS/JS — no frameworks, no build step (unchanged from v0.1.0).
- **Hosting:** GitHub Pages for website. Plugin distribution TBD.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Validate before building | De-risk with a landing page first | ✓ Good — site shipped |
| Static site over framework | Simplicity, no build tooling | ✓ Good — 1,045 LOC, 2-day build |
| Buttondown for email | Simple API, free tier | ✓ Good — working form |
| Terminal/hacker aesthetic | Matches target audience | ✓ Good — cohesive dark theme |
| SVG for OG image | Simpler than generating PNG | ⚠️ Revisit — doesn't render on all platforms |
| Inline CSS (no separate stylesheet) | Single-file simplicity | ✓ Good |
| GitHub Pages + Actions | Free hosting, auto-deploy, HTTPS | ✓ Good |
| **v0.2.0 → v0.3.0 pivot** (2026-04-18) | Distro-as-product has high adoption friction; extension-on-top-of-distro delivers same agent-user-provisioning value with near-zero install friction and broader reach | — Active |
| Debian 12 Bookworm as distro base | Stable, widely deployed, strong apt ecosystem | Retired with pivot |
| Packer + QEMU for image build | Reproducible, industry-standard | Retired with pivot |
| fpm for .deb packaging | Pragmatic, not Debian-policy-compliant | Retired as a distribution mechanism; may return as plugin packaging |
| Node.js 22 LTS from NodeSource | LTS, stable install path | Carries forward into plugin installer |
| Local apt repo in image (no public PPA) | Sufficient for PoC | Retired with pivot |
| Ubuntu as v0.3.0 target | Largest developer Linux audience; apt-based (leverages v0.2.0 learnings) | ✓ Good — v0.3.0 shipped on Ubuntu 22.04 + 24.04 |
| Canonical acceptance test: Claude Code self-update | Directly tests the motivating bug class (EACCES / recursive shim) | ✓ Good — AGT-02 green end-to-end against Anthropic CDN |
| **Open-source the repo (v0.4.0)** (2026-04-26) | Private-repo CI/CD spend is non-trivial; public repos get free Actions minutes; unblocks community contributions and outside marketing | — Active |
| MIT as recommended OSS license | Permissive, dependency-friendly, low-friction for community adoption (vs. Apache-2.0 patent grant or GPL copyleft) | — Active (final pick confirmed in Phase 7) |
| Visibility flip is irreversible-in-practice | Re-private is possible but third parties may have already cloned/forked; treat as one-way | — Active (drove Phase 11 pre-flight checklist) |
| **Aware Installation milestone (v0.3.4)** (2026-05-09) | AL-38: real-world hosts already have partial agent toolchains; the v0.3.0 installer's "fresh-host" assumption fails them. Detection + Reuse/Remediate/Bail makes AgentLinux usable on brownfield hosts without changing the v0.3.0 contract for fresh hosts | — Active |
| Reuse-or-bail as the non-interactive default | Non-interactive contexts (cron, CI, ssh-non-interactive, `curl \| sudo bash`) cannot safely make policy decisions about pre-existing user state; default to the conservative path; require an explicit flag for any overwrite | — Active (drives v0.3.4 UX-03..05) |
| Detection layer is read-only | Discovery never mutates host state; mutation is the Reuse / Remediate path's responsibility, gated by the pre-flight report. This keeps `--dry-run` trivially correct | — Active (drives v0.3.4 DET-XX) |
| Brownfield acceptance test: AGT-02 still green after install on a pre-populated host | Same canonical bug class as v0.3.0; the brownfield path must not regress the green-field path | — Active (locks v0.3.4 phase-close gate) |
| **AlmaLinux 9 support milestone (v0.3.5)** (2026-06-27) | AL-47: AlmaLinux 9 is the maintainer's daily work environment and the next first-person-friction priority after the v0.3.4 brownfield installer. Extends the plugin past Ubuntu without changing the behavior contract — the implementation branches (apt→dnf, dpkg→rpm), the BHV/RT/AGT/CLI/CAT/INST contract does not | — Active |
| AlmaLinux 9 ONLY (no Alma 10 / RHEL / Rocky / Fedora) for v0.3.5 | Maintainer runs AlmaLinux 9 and nothing else from the EL family; single-version scope keeps the test matrix small and shortens the path to a working release. Same first-person-friction rule that scoped Ubuntu in v0.3.0. Family expansion waits until AlmaLinux 9 is the daily driver for a release cycle | — Active |
| AL-59 alt-user wiring kept OUT of v0.3.5 | AL-59 (hardcoded `agent` in 20-sudoers/30-nodejs/40-path-wiring) is distro-independent; bundling it would widen the v0.3.5 test matrix and blur the milestone boundary. Planned separately under Epic AL-48 | — Active |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-27 — v0.3.5 (AlmaLinux 9 Support) milestone started via /gsd-new-milestone (AL-47, Epic AL-48; blocker AL-38 Done). Previous milestone v0.3.4 (Aware Installation Process) SHIPPED 2026-06-08. v0.4.0 (Open-Source Release) feature-complete; formal closeout reconciliation pending.*
