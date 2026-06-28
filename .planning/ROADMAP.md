# Roadmap

**Current milestone:** 🚧 **v0.3.5 AlmaLinux 9 Support** — Phases 18–22 (active, roadmap-ready 2026-06-28). Anchor [AL-47](https://copiedwonder.atlassian.net/browse/AL-47) under Epic [AL-48](https://copiedwonder.atlassian.net/browse/AL-48); blocker [AL-38](https://copiedwonder.atlassian.net/browse/AL-38) Done. Phase numbering continues from v0.3.4 (last phase 17).

## Milestones

- 🚧 **v0.3.5 AlmaLinux 9 Support** — Phases 18–22 (active)
- ✅ **v0.3.4 Aware Installation Process** — Phases 12–17 (SHIPPED 2026-06-08)
- ✅ **v0.4.0 Open-Source Release** — Phases 7–11 (feature-complete; formal closeout pending)
- ✅ **v0.3.3 Agenda Redefinition** — Phases 13–17 (shipped 2026-05-24)
- ✅ **v0.3.0 AgentLinux Plugin (Ubuntu)** — Phases 1–6 + 5.1 (shipped 2026-04-20)
- ⏏️ **v0.2.0 First Distro Image** — Phases 1–4 (retired 2026-04-18, pivot)
- ✅ **v0.1.0 Landing Page** (shipped 2026-03-10)

## Overview (v0.3.5)

v0.3.5 ports the AgentLinux plugin from Ubuntu to **AlmaLinux 9** — the maintainer's daily work environment. This is a **port, not a feature milestone**: the `BHV` / `RT` / `AGT` / `CLI` / `CAT` / `INST` + `DET` / `REUSE` / `REMEDIATE` / `UX` behavior contract is the invariant; only the implementation branches (`apt`→`dnf`, `dpkg`→`rpm`, `locale-gen`→`/etc/locale.conf`, NodeSource APT→NodeSource RPM). The journey runs foundation-first: Phase 18 lands the single distro-family abstraction every provisioner and detector reads; Phase 19 stands up the fast `almalinux:9` Docker substrate that validates it; Phase 20 drives the full bats contract green on that substrate **under enforcing SELinux**; Phase 21 verifies the three catalog agents install on EL9; and Phase 22 proves the whole thing once on a real AlmaLinux 9 QEMU cloud-image VM and gates the v0.3.5 release tag on it. The milestone-close gate is **AGT-02** — zero-EACCES `claude update` — green on a real enforcing-SELinux EL9 guest. Scope is **AlmaLinux 9 ONLY** (no Alma 10 / RHEL / Rocky / Fedora); SELinux is respected, never disabled.

## Phases

**Phase Numbering:**
- Integer phases (18, 19, 20…): planned milestone work, continuing from v0.3.4's last phase (17).
- Decimal phases (e.g. 18.1): urgent insertions (marked INSERTED), appearing between their surrounding integers.

- [x] **Phase 18: Detection + Branching Foundation** — Recognize AlmaLinux 9 and route every apt/dpkg/locale/NodeSource/sudoers/brownfield call through one distro-family abstraction so a fresh install runs end-to-end on EL9. ✅ 2026-06-28
- [x] **Phase 19: Docker AlmaLinux 9 Row** — Stand up the fast `almalinux:9` Docker substrate (+ CI matrix arm) that validates the Phase 18 branch in the ~90s loop. (completed 2026-06-28)
- [ ] **Phase 20: Behavior-Test-Green on AlmaLinux 9** — Drive the full existing bats contract green on the Alma Docker row under enforcing SELinux, with Ubuntu-path assertions generalized to distro-aware helpers.
- [ ] **Phase 21: Catalog Verify on AlmaLinux 9** — Verify the three catalog agents install and pass health checks on EL9; resolve the open Playwright-chromium dnf-deps question by on-box smoke.
- [ ] **Phase 22: QEMU Release-Gate + Pipeline** — Prove the port once on a real AlmaLinux 9 cloud-image VM, wire the release pipeline, and gate the v0.3.5 tag on EL9 Docker + QEMU green (AGT-02 milestone-close gate).

## Phase Details

### Phase 18: Detection + Branching Foundation
**Goal**: AgentLinux's installer recognizes AlmaLinux 9 and routes every package-manager, locale, NodeSource, sudoers, and brownfield-detection operation through a single `AGENTLINUX_DISTRO_FAMILY` abstraction (`lib/distro_detect.sh` + new `lib/pkg.sh`), so a fresh install runs end-to-end on EL9 instead of dying at the Ubuntu-only gate or on a hardcoded `apt-get`.
**Depends on**: Shipped v0.3.4 plugin baseline (Phase 17) — the foundation every later v0.3.5 phase reads. Co-developed with Phase 19 (its Docker acceptance substrate).
**Requirements**: EL-01, EL-02, EL-03, EL-04, EL-05, EL-07
**Success Criteria** (what must be TRUE):
  1. Running the installer on AlmaLinux 9 passes the distro gate and reaches `agentlinux-install complete` (no `apt-get: command not found`, no `unsupported distro` reject) — while AlmaLinux 8/10, Rocky, RHEL, and Fedora are still explicitly refused with a message naming the supported set, and the `AGENTLINUX_SKIP_DISTRO_CHECK` escape hatch seeds a family rather than crashing the branch.
  2. Node.js 22 LTS lands from the NodeSource RPM repo (`rpm -q nodejs` shows a `nodesource` release; `node --version` is `v22.x`) with the AppStream `nodejs` module defused — not the older AppStream stream — satisfying the per-user-prefix "no `sudo npm install -g`" ownership contract identically to Ubuntu.
  3. `locale -a` reports `C.UTF-8` on EL9 with the system locale written directly to `/etc/locale.conf` (no `locale-gen`, no `locales` package, no `localectl`).
  4. `sudo -u agent sudo -n true` succeeds — the `/etc/sudoers.d/agentlinux` drop-in installs at `0440 root:root` with exactly `agent ALL=(ALL) NOPASSWD: ALL` via the visudo-gated path (ADR-012), unbroken by any EL9 `Defaults`.
  5. On a brownfield EL9 host, the detection layer classifies a pre-existing Node.js by its real source (NodeSource-RPM via `rpm -q` + `/etc/yum.repos.d/nodesource-nodejs.repo`, vs the AppStream `nodejs` module, vs absent) using rpm/file probes — not a `dpkg-query` that would mis-report.
**Plans**: 6 plans (2 waves)
- [x] 18-01-PLAN.md — distro_detect.sh almalinux arm + AGENTLINUX_DISTRO_FAMILY export + escape-hatch seed + curl-installer lockstep gate (EL-01)
- [x] 18-02-PLAN.md — new lib/pkg.sh package-manager-neutral verb dispatch layer + EL-02 unit tests (EL-02)
- [x] 18-03-PLAN.md — provisioner 10/20/30 conversions: locale_ensure, pkg_install sudo, NodeSource RPM + AppStream module defuse (EL-03, EL-04, EL-05)
- [x] 18-04-PLAN.md — entrypoint wiring: source pkg.sh + ensure_jq + run_purge routed through verbs (EL-02)
- [x] 18-05-PLAN.md — brownfield detection EL9 arm: detect/nodejs.sh rpm classification + detect/user.sh probe (preserve can_sudo_apt) (EL-07)
- [x] 18-06-PLAN.md — ADR-017 distro-family-bucket decision record (EL-01, EL-02)

### Phase 19: Docker AlmaLinux 9 Row
**Goal**: A fast-feedback `almalinux:9` Docker substrate that runs the bats suite, so the Phase 18 branch can be validated on a real EL9 environment in the ~90s Docker loop (not the ~5min QEMU loop). Phase 19 is Phase 18's acceptance gate.
**Depends on**: Phase 18 (the branch it validates) — co-developed.
**Requirements**: HARN-01
**Success Criteria** (what must be TRUE):
  1. `./tests/docker/run.sh almalinux-9` builds `tests/docker/Dockerfile.almalinux-9` (`FROM almalinux:9`, EL9 package set — `systemd cronie openssh-server sudo jq curl python3 file util-linux ca-certificates`, plus `bats` via EPEL or vendored) and boots it under the systemd-in-Docker recipe.
  2. The hermetic CLI build stage is preserved and spliced into the Alma image exactly as in the Ubuntu rows, and `agentlinux-install` runs to completion inside the container.
  3. `.github/workflows/test.yml` and `release.yml` gate-2 carry an `almalinux-9` matrix arm beside the three Ubuntu arms (dimension generalized `ubuntu`→`target`), with `fail-fast: false` so a red Alma arm still reports the Ubuntu arms.
**Plans**: 2 plans (2 waves)
- [x] 19-01-PLAN.md — EL9 Docker substrate: Dockerfile.almalinux-9 + run.sh almalinux-9 case + local smoke (green install, runnable bats, nodesource transcript) [Wave 1]
- [x] 19-02-PLAN.md — CI Docker matrix arm: test.yml bats-docker + release.yml gate-2 ubuntu→target + almalinux-9 (gate-3/4 untouched) [Wave 2]


### Phase 20: Behavior-Test-Green on AlmaLinux 9
**Goal**: The full existing behavior contract — `BHV` / `RT` / `AGT` / `CLI` / `CAT` / `INST` (v0.3.0) and `DET` / `REUSE` / `REMEDIATE` / `UX` (v0.3.4) — is green on the AlmaLinux 9 Docker row **under enforcing SELinux**, with Ubuntu-path assertions generalized to distro-aware helpers rather than weakened or skipped.
**Depends on**: Phase 19 (needs a green install on the Docker substrate to iterate the suite against). Phase 21 may overlap once the Docker arm is generally green.
**Requirements**: EL-06, EL-08, PAR-01
**Success Criteria** (what must be TRUE):
  1. All six invocation modes (interactive bash login, non-interactive SSH, cron, systemd `User=agent`, `sudo -u agent`, `sudo -u agent -i`) pass on EL9 — in particular **non-interactive SSH authenticates** because any path writing `~agent/.ssh` follows with `restorecon -R -F`, and SELinux is left **enforcing** (`setenforce 0` / `SELINUX=disabled` is never used to green a test).
  2. The complete existing bats contract is green on the Alma Docker row; Ubuntu-specific path assertions (locale-conf path, NodeSource repo path, `dpkg-query`→`rpm -q`, sudoers fixtures) resolve through a `tests/bats/helpers/distro.bash` helper so the same `@test` passes on both families.
  3. On EL9, the v0.3.4 four-state brownfield flow (Reuse / Create / Remediate / Bail) produces the same per-component decisions as Ubuntu — verified by AppStream-Node, NodeSource-RPM, and nvm-managed fixtures each classifying correctly, with the read-only detection snapshot invariant intact.
  4. `agentlinux install --dry-run` is observably non-mutating on EL9 (exits 0, host snapshot byte-identical), and the single `--yes` consent flag plus structured exit codes 64/65/1/0 behave as on Ubuntu.
**Plans**: 5 plans
Plans:
- [ ] 20-01-PLAN.md — Wave 1 substrate: Dockerfile.almalinux-9 +diffutils/openssh-clients/iproute + run.sh `--tmpfs /tmp:exec` (flips ~40 false-RED green, stubs untouched) [Wave 1]
- [ ] 20-02-PLAN.md — Wave 2 helper foundation: NEW tests/bats/helpers/distro.bash (9-verb family dispatch) + brownfield.bash routed through it (the biggest item) [Wave 2]
- [ ] 20-03-PLAN.md — EL-06: BHV-01 locale via distro_assert_locale + distro_ssh_unit + guarded restorecon at both SSH-seed sites; six modes green (20-agent-user.bats, 50-agents.bats) [Wave 3]
- [ ] 20-04-PLAN.md — INST-02 snapshot via family-correct NodeSource repo path + REUSE-01 family-token seed (10-installer.bats, 13-reuse.bats) [Wave 3]
- [ ] 20-05-PLAN.md — Spikes: DET-03 npm-prefix root-cause (test-fix or product escalation) + tty-driver.py bounded pexpect timeout (15-detection.bats, tty-driver.py) [Wave 3]

### Phase 21: Catalog Verify on AlmaLinux 9
**Goal**: The three catalog agents install and pass their health checks on AlmaLinux 9, resolving the one open EL9 question — whether any Playwright code path launches Chromium and thus needs an explicit `dnf` runtime-deps block — by on-box smoke rather than pre-scoped guesswork.
**Depends on**: Phase 20 (catalog AGT @tests run inside the bats suite, which must be green-able first). Can overlap Phase 20 once the Docker arm is generally green.
**Requirements**: REC-01
**Success Criteria** (what must be TRUE):
  1. `agentlinux install claude-code` and `agentlinux install gsd` complete on EL9 and pass their health checks unchanged (claude-code's distro-agnostic native installer → `~agent/.local/bin/claude`; gsd's pure `npm install -g`).
  2. `agentlinux install playwright-cli` runs a live install + health smoke on `almalinux:9` and the AGT-05 bats assertion passes; a `dnf install` chromium-runtime-deps block is added **only if** an EL9 code path actually launches Chromium (resolved by the smoke result, not pre-scoped).
  3. The catalog AGT @tests (AGT-01..05) are green on the Alma Docker row; the authoritative AGT-02 self-update gate is re-confirmed on the real QEMU guest in Phase 22.
**Plans**: TBD

### Phase 22: QEMU Release-Gate + Pipeline
**Goal**: Prove the EL9 port once on a real AlmaLinux 9 cloud-image VM (systemd + enforcing SELinux + cloud-init), wire the AlmaLinux QEMU + Docker arms into the release pipeline, and gate the v0.3.5 tag on both being green — with AGT-02 zero-EACCES on the real guest as the milestone-close gate (ADR-007: "Docker alone is disqualified"). This phase also re-confirms EL-06's `restorecon` fix under real enforcement.
**Depends on**: Phase 20 + Phase 21 (iterate everything fast in Docker first, then prove once in QEMU). Milestone exit gate.
**Requirements**: HARN-02, PAR-02, REL-01
**Success Criteria** (what must be TRUE):
  1. The AlmaLinux 9 QEMU row boots a **pinned dated** `AlmaLinux-9-GenericCloud-*.qcow2` (not `-latest`) with checksum verification asserting **≥1 row actually matched** the `CHECKSUM` file (a flipped-byte corruption test makes the run exit non-zero), driven via `almalinux@` + sudo with service `sshd` and an EL-specific cloud-init seed.
  2. The full release-gate bats suite is green on the real enforcing-SELinux EL9 guest — all six modes including non-interactive SSH — with zero `sshd_t` / agent AVC denials (green-with-permissive is rejected as a false pass).
  3. AGT-02 passes on the real AlmaLinux 9 guest: `claude update` self-updates with **zero EACCES / no sudo**, monotonic version bump, against the live Anthropic CDN — the v0.3.5 milestone-close gate; the greenfield Ubuntu AGT-02 invariant remains unchanged and green.
  4. `release.yml` blocks the v0.3.5 tag until `almalinux-9` passes both the Docker matrix gate (HARN-01) and the QEMU release gate (HARN-02), alongside the existing Ubuntu gates and the unchanged pinned-combo / catalog-snapshot gate (ADR-011).
**Plans**: TBD

## Progress

**Execution Order:** Phases execute in numeric order: 18 → 19 → 20 → 21 → 22 (18+19 co-developed; 20+21 may overlap; 22 is the milestone exit gate).

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 18. Detection + Branching Foundation | 6/6 | Complete   | 2026-06-28 |
| 19. Docker AlmaLinux 9 Row | 2/2 | Complete    | 2026-06-28 |
| 20. Behavior-Test-Green on AlmaLinux 9 | 0/TBD | Not started | - |
| 21. Catalog Verify on AlmaLinux 9 | 0/TBD | Not started | - |
| 22. QEMU Release-Gate + Pipeline | 0/TBD | Not started | - |

---

## Last Completed Phase

<details>
<summary>Phase 17: Changes Delivery and Release Candidate ✓ COMPLETE (v0.3.4 shipped 2026-06-08)</summary>

**Goal:** Ship the feature-complete v0.3.4 "Aware Installation Process" to a maintainer-testable release candidate and gate the final release on live brownfield review. Polish the worktree branch diff (tests green, commit hygiene), merge to master, cut `v0.3.4-rc1` (tarball + sibling `.sha256` via `scripts/build-release.sh`; push the rc tag to exercise `release.yml` end-to-end — the shipping event), hand the maintainer concrete live-test instructions, then await maintainer feedback as an explicit checkpoint.

**Outcome:** 4 rc iterations (rc1→rc4) each fixing a maintainer-found bug (AL-60 npx-GSD detection / AL-61 adopt-on-install + honest `list` / AL-62 npm→native migration), then LGTM → promoted to final v0.3.4 (marked Latest). AL-38 Done.

**Plans:**
2/2 plans complete
- [x] 17-02-PLAN.md — DEL-01b/DEL-02b/DEL-03/DEL-04: push branch + PR → merge → rc tag + release watch → brownfield-VM runbook → VM validation
- [x] 17-03-PLAN.md — DEL-05: promote-or-iterate decision gate (rc1→rc4 → final v0.3.4)

</details>

## Shipped / Feature-Complete Milestones

| Version | Name | Phases | Status | Archive |
|---------|------|--------|--------|---------|
| v0.3.4 | Aware Installation Process | 6 (Phase 12-17) | **SHIPPED 2026-06-08** (final v0.3.4, Latest; rc1→rc4 maintainer-validated) | [v0.3.4-ROADMAP.md](milestones/v0.3.4-ROADMAP.md) · [v0.3.4-REQUIREMENTS.md](milestones/v0.3.4-REQUIREMENTS.md) · [v0.3.4-MILESTONE-AUDIT.md](v0.3.4-MILESTONE-AUDIT.md) |
| v0.3.3 | Agenda Redefinition | 5 (Phase 13-17) | shipped 2026-05-24 (docs/vision/website) | [v0.3.3-ROADMAP.md](milestones/v0.3.3-ROADMAP.md) · [v0.3.3-REQUIREMENTS.md](milestones/v0.3.3-REQUIREMENTS.md) · phases archived under [milestones/v0.3.3-phases/](milestones/v0.3.3-phases/) |
| v0.4.0 | Open-Source Release | 5 (Phase 7-11) | feature-complete (formal closeout pending) | [v0.4.0-ROADMAP.md](milestones/v0.4.0-ROADMAP.md) · [v0.4.0-REQUIREMENTS.md](milestones/v0.4.0-REQUIREMENTS.md) |
| v0.3.0 | AgentLinux Plugin (Ubuntu) | 6 + 1 inserted (Phase 1-6, 5.1) | shipped 2026-04-20 | [v0.3.0-ROADMAP.md](milestones/v0.3.0-ROADMAP.md) · [v0.3.0-REQUIREMENTS.md](milestones/v0.3.0-REQUIREMENTS.md) |
| v0.2.0 | First Distro Image | 4 (Phase 1-4) | retired 2026-04-18 (pivot) | [v0.2.0-ROADMAP.md](milestones/v0.2.0-ROADMAP.md) · [v0.2.0-REQUIREMENTS.md](milestones/v0.2.0-REQUIREMENTS.md) |
| v0.1.0 | (initial) | — | — | [v0.1.0-ROADMAP.md](milestones/v0.1.0-ROADMAP.md) · [v0.1.0-REQUIREMENTS.md](milestones/v0.1.0-REQUIREMENTS.md) |

> **Phase-numbering note (parallel-milestone overlap).** v0.3.3 (Agenda Redefinition, phases **13–17**) and v0.3.4 (Aware Installation, phases **12–17**) were developed concurrently on separate branches and **reused phase numbers** — both number sets are frozen in immutable git commit prefixes (`feat(13-…)` etc.) on their respective lineages, so renumbering is not possible without rewriting shipped history. Reconciliation: v0.3.3's completed phase dirs are **archived** under `milestones/v0.3.3-phases/`, leaving the active `phases/` dir to v0.3.4's 12–17. One residual number reuse remains in the active dir — **phase 12** is both v0.3.4's `12-detection-layer` and v0.4.0's AL-22 addendum `12-developer-documentation-…`; both are completed and distinguished by dir-slug. This mirrors the project's existing cross-milestone number reuse (v0.2.0's archived 1–4 vs v0.3.0's 1–6). **v0.3.5 avoids the overlap entirely by continuing past the highest used integer — it starts at Phase 18.**
