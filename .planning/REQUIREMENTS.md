# Requirements: AgentLinux v0.3.5 — AlmaLinux 9 Support

**Defined:** 2026-06-28
**Milestone:** v0.3.5 AlmaLinux 9 Support
**Triggered by:** [AL-47 "Add AlmaLinux support — first distro expansion past Ubuntu"](https://copiedwonder.atlassian.net/browse/AL-47) (Epic [AL-48](https://copiedwonder.atlassian.net/browse/AL-48); blocker [AL-38](https://copiedwonder.atlassian.net/browse/AL-38) Done)
**Core Value (carried from PROJECT.md):** An agent can be dropped into any supported Linux system and just work — provisioned correctly the first time. v0.3.5 extends "any supported Linux system" past Ubuntu to **AlmaLinux 9**, the maintainer's daily work environment, so a `curl … | bash` install yields the same agent environment EL9 users get that Ubuntu users already have.

## Design Philosophy (read first)

**The behavior contract is the invariant; the implementation may diverge.** AgentLinux on AlmaLinux 9 must deliver the same *observable* behavior as on Ubuntu — the six invocation modes (interactive bash login, non-interactive SSH, cron, systemd `User=agent`, `sudo -u agent`, `sudo -u agent -i`), the zero-EACCES Claude Code self-update (AGT-02), and the v0.3.4 brownfield Reuse / Create / Remediate / Bail flow. The *implementation* branches (`apt`→`dnf`, `dpkg`→`rpm`, `locale-gen`→`/etc/locale.conf`, NodeSource APT→NodeSource RPM), but every existing `BHV` / `RT` / `AGT` / `CLI` / `CAT` / `INST` + `DET` / `REUSE` / `REMEDIATE` / `UX` bats test must pass on EL9. **This is a port, not a feature milestone — no new product capabilities.**

**First-person friction drives scope.** AlmaLinux 9 is the maintainer's daily work environment; v0.3.5 is the gate for AgentLinux becoming his daily-driver tool (the diagnosis test in `docs/STRATEGY.md`). Scope is **AlmaLinux 9 ONLY** — the same first-person-friction rule that scoped Ubuntu to two LTS versions in v0.3.0. EL8, EL10, RHEL, Rocky, Fedora, and any other dnf-based distro wait until AlmaLinux 9 is the daily driver for a release cycle.

**One distro abstraction, not scattered conditionals.** The `apt`/`dpkg`/locale coupling is exactly **13 hardcoded call sites across 5 files** (entrypoint `plugin/bin/agentlinux-install`, provisioners `10`/`20`/`30`, and brownfield detectors `plugin/lib/detect/nodejs.sh` + `detect/user.sh`). The port consolidates these into a single `plugin/lib/pkg.sh` dispatch layer (`pkg_install` / `pkg_is_installed` / `pkg_remove` / `nodesource_setup` / `locale_ensure`) branched on a new `AGENTLINUX_DISTRO_FAMILY` export from `distro_detect.sh`. Inline per-site `if [[ $FAMILY == rhel ]]` is the wrong shape. The behavior contract survives because the bats suite asserts **outcomes** (node ≥ 22, sudo works, `C.UTF-8` in `locale -a`), not which package manager produced them.

**SELinux is respected, never disabled.** AlmaLinux 9 enforces SELinux by default. Any code path that writes into `~agent/.ssh` must restore contexts (`restorecon -R -F ~agent/.ssh`) so confined `sshd_t` can read `authorized_keys` — otherwise **only** the non-interactive SSH mode silently fails with "Permission denied (publickey)" while su-/sudo-/cron/systemd stay green. `setenforce 0` is **rejected**: it greens the suite while shipping a product broken on every real enforcing EL9 host — the exact "paper over the environment" anti-pattern `CLAUDE.md` forbids.

**Docker proves fast, QEMU proves real.** Per ADR-007, Docker can't fully reproduce systemd, SELinux-enforcing, locale, and cloud-init paths — the AlmaLinux 9 QEMU cloud-image row is the release gate. The QEMU checksum integrity gate must be fixed for AlmaLinux's image layout: Alma's `CHECKSUM` lists only **versioned** filenames, so `sha256sum --ignore-missing --check` against `…-latest.qcow2` vacuously passes (zero rows matched, exits 0). The fix is to pin the dated filename and assert ≥ 1 checksum row actually verified.

**Behavior-test discipline carries over.** Every requirement closes with at least one verifiable check before its phase closes — bats `@test`, CI workflow citation, or an audit doc with command + output. The TST-07 phase-close behavior-coverage-auditor gate convention applies at every phase boundary, and the milestone-close gate is AGT-02 (zero-EACCES `claude update`) green on a real AlmaLinux 9 QEMU guest.

## v0.3.5 Requirements

Grouped by category. Each `XXX-NN` is a testable, verifiable outcome — auditable before the phase closes. Requirement IDs that diverge from Ubuntu only in *implementation* (same observable) reference the existing contract family they preserve.

### EL — AlmaLinux 9 installer support (distro layer)

- [ ] **EL-01**: `plugin/lib/distro_detect.sh` recognizes AlmaLinux 9 (`/etc/os-release` `ID=almalinux` + `VERSION_ID=9.*`) and exports a distro-family token `AGENTLINUX_DISTRO_FAMILY` ∈ `{debian, rhel}`. Detection matches on `ID` (not `ID_LIKE`) so Rocky / RHEL / CentOS / Fedora and AlmaLinux 8/10 are **not** silently accepted — an unsupported distro or EL major version bails with a clear, actionable message naming the supported set. The `AGENTLINUX_SKIP_DISTRO_CHECK` escape hatch also seeds a family so it does not crash the branch.
- [ ] **EL-02**: A `plugin/lib/pkg.sh` dispatch layer provides package-manager-neutral verbs (`pkg_install`, `pkg_is_installed`, `pkg_remove`, and supporting helpers) that branch on `AGENTLINUX_DISTRO_FAMILY`. All ~13 hardcoded `apt-get` / `dpkg` / `dpkg-query` call sites in the entrypoint, provisioners `10`/`20`/`30`, and the brownfield detectors route through it. On AlmaLinux 9 they resolve to `dnf` / `rpm`; on Ubuntu the existing `apt` behavior is byte-for-byte preserved. Targets full `dnf` (not `microdnf`); does **not** `dnf install curl` (avoids the EL9 `curl-minimal` conflict).
- [ ] **EL-03**: On AlmaLinux 9, Node.js 22 LTS installs via the NodeSource RPM path (`curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -` → `/etc/yum.repos.d/nodesource-nodejs.repo` + GPG key → `dnf install nodejs`) with the AppStream `nodejs` module conflict defused (`module_hotfixes=1` or `dnf module reset nodejs`). The RT-01 `node >= 22` guard in `30-nodejs.sh` catches the failure mode where AppStream's older module wins. Result satisfies the existing "agent owns its npm globals via a per-user prefix, no `sudo npm install -g`" contract identically to Ubuntu.
- [ ] **EL-04**: On AlmaLinux 9, locale provisioning guarantees `C.UTF-8` by writing `/etc/locale.conf` directly (EL9 glibc 2.34 ships `C.UTF-8` built-in — no `locales` package, no `locale-gen`, no `glibc-langpack`, and **no** `localectl`, which needs a D-Bus that may not run in Docker). The Debian-only `locale-gen` / `update-locale` / `/etc/default/locale` block in `10-agent-user.sh` is bypassed on EL; the existing `locale -a` correctness check passes unchanged.
- [ ] **EL-05**: On AlmaLinux 9, the `/etc/sudoers.d/agentlinux` drop-in installs via the existing `visudo`-gated path at mode `0440` root:root containing exactly `agent ALL=(ALL) NOPASSWD: ALL` (ADR-012). No EL9 `sudoers` `Defaults` (`requiretty`, `secure_path`) breaks passwordless sudo across the six invocation modes. Only the package-install verb (`sudo`) changes; the install/validate logic is distro-agnostic.
- [ ] **EL-06**: All six invocation modes work on an **enforcing-SELinux** AlmaLinux 9 host. In particular, any path that writes `~agent/.ssh/authorized_keys` (installer and test harness `setup`) follows with `restorecon -R -F ~agent/.ssh` so confined `sshd_t` can read it and the non-interactive SSH mode authenticates. SELinux remains enforcing — `setenforce 0` / `SELINUX=disabled` is never used to make a test pass.
- [ ] **EL-07**: The brownfield detection layer (`plugin/lib/detect/`) gains an EL9 arm at parity with DET-02/DET-03/DET-05: it classifies a pre-existing Node.js install on EL9 by its real source (NodeSource-RPM via `rpm -q` + `/etc/yum.repos.d/nodesource-nodejs.repo`, vs the AppStream `nodejs` module, vs absent) instead of assuming `dpkg-query`, and the `can_sudo_apt`-style capability probe is generalized to the detected package manager. Misclassification (the v0.3.4-class bug) does not reappear on EL.
- [ ] **EL-08**: The v0.3.4 four-state brownfield flow (Reuse / Create / Remediate / Bail, with `--dry-run`, the `--yes` consent flag, and exit codes 64/65/1/0) produces the same per-component decisions on AlmaLinux 9 as on Ubuntu, driven by the EL-07 EL9 evidence sources. `agentlinux install --dry-run` is observably non-mutating on EL9.

### HARN — AlmaLinux 9 test harness (ADR-007 two-tier)

- [ ] **HARN-01**: A new `almalinux-9` Docker matrix row runs the full bats suite in CI. A `tests/docker/Dockerfile.almalinux-9` (`FROM almalinux:9`) provisions the suite's prerequisites (including `bats`, which is not in AlmaLinux base repos — sourced via EPEL or vendored), keeps the hermetic CLI build, and `almalinux-9` is added to `tests/docker/run.sh` and the `test.yml` / `release.yml` matrices (currently `[ubuntu-22.04, 24.04, 26.04]`).
- [ ] **HARN-02**: A new AlmaLinux 9 QEMU cloud-image row runs the release-gate suite on a real VM (systemd + enforcing SELinux + cloud-init). The image is a **pinned dated** `AlmaLinux-9-GenericCloud-*.qcow2` (not `-latest`, which defeats the CI cache key and the integrity gate); checksum verification asserts **≥ 1 row actually matched** the `CHECKSUM` file (closing the `--ignore-missing` vacuous-pass); `boot.sh` is parameterized for the EL guest (default cloud-init user `almalinux`, service `sshd`, EL-specific seed). Distro-specific Ubuntu-path bats assertions (`/etc/default/locale`, `nodesource.sources`, `dpkg-query`) are made distro-aware via a `tests/bats/helpers/distro.bash` helper.

### PAR — behavior-contract parity on AlmaLinux 9

- [ ] **PAR-01**: The complete existing behavior contract — `BHV` / `RT` / `AGT` / `CLI` / `CAT` / `INST` (v0.3.0) **and** `DET` / `REUSE` / `REMEDIATE` / `UX` (v0.3.4) — is green on AlmaLinux 9 across both the Docker (HARN-01) and QEMU (HARN-02) rows. Where a test encodes a Debian-specific path or tool, it is generalized to assert the same observable on EL9 rather than weakened or skipped.
- [ ] **PAR-02**: AGT-02 — the canonical acceptance test — passes on a real AlmaLinux 9 guest: `claude update` self-updates with **zero EACCES / no sudo**, monotonic version bump, against the live Anthropic CDN. This is the v0.3.5 milestone-close gate (the EL9 analogue of v0.3.0's TST-07 / v0.3.4's brownfield-AGT-02 gate). The greenfield Ubuntu AGT-02 invariant remains unchanged and green.

### REC — catalog recipes verified on AlmaLinux 9

- [ ] **REC-01**: The three catalog agents install and pass their health checks on AlmaLinux 9. `claude-code` (distro-agnostic native installer → `~agent/.local/bin/claude`) and `gsd` (pure npm) port unchanged. For `playwright-cli`, a live install + health smoke runs on `almalinux:9`; **only if** an EL9 code path launches Chromium (Playwright's `install-deps` has no `dnf` path and dies on `apt-get`) does the recipe gain an explicit `dnf install` chromium-runtime-deps list. No dnf-deps work is pre-scoped before that smoke result is in hand.

### REL — release pipeline gate

- [ ] **REL-01**: `release.yml` gates the v0.3.5 tag on AlmaLinux 9 being green: the Docker matrix gate (HARN-01) **and** the QEMU release gate (HARN-02) must both pass for `almalinux-9` before a v0.3.5 tag publishes, alongside the existing Ubuntu gates and the pinned-combo gate. The pinned-combo / catalog-snapshot machinery (ADR-011) is unchanged.

## Future Requirements (not in this milestone)

Deferred — acknowledged, tracked, not in the v0.3.5 roadmap.

### EL family expansion

- **AlmaLinux 10**: deferred until the maintainer hits first-person friction on it; filed as a follow-up ticket then, not pre-emptively.
- **RHEL / Rocky / CentOS Stream / Fedora**: the EL family beyond AlmaLinux 9 waits until AlmaLinux 9 is the daily driver and stable for one release cycle. The `AGENTLINUX_DISTRO_FAMILY` abstraction is designed to make this a small follow-on, but no family-wide claim is made now.

### Adjacent carried-forward work

- **AL-59 alt-user hollow-install wiring**: the hardcoded `agent` user in `20-sudoers.sh` / `30-nodejs.sh` / `40-path-wiring.sh` is distro-independent and planned separately under Epic AL-48. Kept out of v0.3.5 to preserve the milestone boundary and the test matrix size, even though it touches the same provisioner files.

## Out of Scope

Explicitly excluded for v0.3.5. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| AlmaLinux 10 | First-person friction first; not on the maintainer's VMs today |
| RHEL / Rocky / CentOS / Fedora | EL-family expansion deferred until AlmaLinux 9 is the daily driver for a release cycle |
| AL-59 alt-user wiring | Distro-independent; separate AL-48 item; bundling would widen the matrix and blur the milestone boundary |
| New catalog agents | Port-only milestone; catalog churn happens in feature milestones |
| Snap / flatpak / alternative packaging | Out of the curl-pipe-bash + dnf/rpm install path |
| Multi-arch (ARM) | x86_64 only, carried forward |
| `setenforce 0` / disabling SELinux | Anti-pattern — ships a product broken on every real enforcing EL host |

## Traceability

Which phases cover which requirements. Mapped during roadmap creation (v0.3.5 ROADMAP, Phases 18–22).

| Requirement | Phase | Status |
|-------------|-------|--------|
| EL-01 | Phase 18 | Done |
| EL-02 | Phase 18 | Done |
| EL-03 | Phase 18 | Done |
| EL-04 | Phase 18 | Done |
| EL-05 | Phase 18 | Done |
| EL-06 | Phase 20 | Done |
| EL-07 | Phase 18 | Done |
| EL-08 | Phase 20 | Done |
| HARN-01 | Phase 19 | Done |
| HARN-02 | Phase 22 | Pending |
| PAR-01 | Phase 20 | Done |
| PAR-02 | Phase 22 | Pending |
| REC-01 | Phase 21 | Pending |
| REL-01 | Phase 22 | Pending |

**Coverage:**
- v0.3.5 requirements: 14 total
- Mapped to phases: 14 ✓ (Phase 18 ×6, Phase 19 ×1, Phase 20 ×3, Phase 21 ×1, Phase 22 ×3)
- Unmapped: 0 ✓

**Note on EL-06 (SELinux):** the `restorecon` *implementation* lands across Phases 18/20, but its primary acceptance — the six invocation modes green under enforcing SELinux on the Docker row — is owned by **Phase 20**; the **Phase 22** QEMU row re-confirms it under real enforcement on the cloud image (no double-counting — EL-06 maps to Phase 20).

---
*Requirements defined: 2026-06-28 — v0.3.5 AlmaLinux 9 Support, full brownfield parity (AL-47).*
*Last updated: 2026-06-28 — traceability mapped to Phases 18–22 (roadmap creation; 14/14 covered, 0 orphaned).*
