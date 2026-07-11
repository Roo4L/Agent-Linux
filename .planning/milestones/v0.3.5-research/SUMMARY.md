# Project Research Summary

**Project:** AgentLinux v0.3.5 AlmaLinux 9 Support (AL-47, Epic AL-48)
**Domain:** Distro port — curl-pipe-bash installer (apt/Ubuntu → dnf/EL9)
**Researched:** 2026-06-27
**Confidence:** HIGH (all call sites verified in repo; EL9 facts verified against upstream sources)

## Executive Summary

v0.3.5 is a **port, not a redesign**. The behavior contract (BHV/RT/AGT/CLI/CAT/INST + the v0.3.4 DET/REUSE/REMEDIATE/UX families) is fixed; only the implementation under the contract branches. The entire porting surface reduces to eight `apt-get`/`dpkg` call sites across five files, one locale provisioning block, one distro-gate rejection, and one harness extension. Everything else — the agent-user model, six-mode PATH wiring (all four artefacts target identical paths on EL9), NOPASSWD sudoers drop-in, registry CLI, catalog design, and 90%+ of the bats assertions — carries over without modification.

The recommended approach centers on three artifacts: (1) a thin `lib/pkg.sh` dispatch library that routes all `apt-get`/`dpkg` call sites through distro-aware verbs (`pkg_install`, `pkg_remove`, `nodesource_setup`, `locale_ensure`), branched on a new `AGENTLINUX_DISTRO_FAMILY` export from `distro_detect.sh`; (2) an `almalinux:9` Docker matrix row for fast iteration; and (3) an AlmaLinux GenericCloud QEMU row as the release gate. NodeSource remains the Node 22 LTS delivery mechanism (same `-1nodesource` version marker the detect probe already keys on); the AppStream module collision is defused by the `module_hotfixes=1` flag the NodeSource setup script already sets. Locale provisioning gets simpler, not harder: `C.UTF-8` is a glibc 2.34 built-in on EL9 — no `locale-gen`, no langpack, just a direct write to `/etc/locale.conf`.

The sharpest risk is SELinux in enforcing mode silently denying sshd access to `authorized_keys` written by a root process — this breaks BHV-02 (non-interactive SSH mode) while every other invocation mode passes, making it look like flaky SSH tests. The fix is two `restorecon -R -F -v /home/agent/.ssh` calls (harness setup and provisioner guard), guarded by `command -v restorecon` so they are no-ops on Ubuntu. Disabling SELinux is rejected; the maintainer runs enforcing AlmaLinux daily and a disable would fail first-person friction immediately.

---

## Key Findings

### Recommended Stack

The porting surface is narrower than it looks. `dnf` (full, not `microdnf`) replaces `apt-get`; `rpm -q` replaces `dpkg-query`; NodeSource's rpm `setup_22.x` mirrors the deb `setup_22.x` path exactly (same Node 22 LTS, same `-1nodesource` version marker, same idempotency gate pattern). `glibc-langpack-en` and `locale-gen` are entirely absent from EL9: `C.UTF-8` is built into glibc 2.34. `cronie` replaces `cron` (BHV-03); `procps-ng` replaces `procps`; `iproute` replaces `iproute2`; `gnupg2` replaces `gnupg` (though dnf verifies NodeSource GPG natively and `gnupg2` is not a hard dep). `apt-transport-https` has no EL equivalent and is not needed — drop it.

**Core technologies (EL9 additions/swaps):**

- `dnf` (full): package install/query/remove — only `dnf` has the `module` subcommand; `microdnf` (`almalinux/9-minimal`) lacks it and is out of scope
- `rpm`: package presence/version/file-list queries — direct `dpkg-query` analogue; version format `2:22.x-1nodesource.el9`
- NodeSource rpm `setup_22.x` + `module_hotfixes=1`: Node 22 LTS on EL9, mirroring the Ubuntu deb path (ADR-005); the setup script writes `/etc/yum.repos.d/nodesource-nodejs.repo` and sets `module_hotfixes=1` (verified upstream), but does NOT disable the AppStream module
- `glibc C.UTF-8` built-in (glibc 2.34): BHV-01 locale — no package, no generation, just verify with `locale -a`; write LANG/LC_ALL to `/etc/locale.conf` directly
- `cronie` (provides `crond`): BHV-03 cron mode — not guaranteed on cloud/minimal images; must be ensured
- `almalinux:9` Docker image + AlmaLinux GenericCloud qcow2: fast-CI and release-gate harness rows

### Expected Features (Parity Surface)

This is a port milestone. "Features" = the observable behavior parity surface the bats contract must hold on EL9.

**Parity — unchanged (carries over as-is, ~90% of the contract):**

- Six-mode PATH wiring — all four artefacts (`/etc/profile.d/agentlinux.sh`, `~agent/.bashrc` marker, `/etc/agentlinux.env`, `/etc/cron.d/agentlinux`) target identical paths on EL9; `40-path-wiring.sh` needs no file re-targeting (only a distro-neutral comment reword on the `--top` rationale)
- BHV-02..06, RT-02/03/04, INST-02/05, BHV-07/INST-06, CLI-01..07, CAT-01..04, AGT-01/02/02b/03/04
- DET-01/03/04/05, REUSE-01/03, REMEDIATE-01..04, UX-01..05 (all use coreutils/npm/filesystem probes that are distro-neutral)
- AGT-02 (the milestone-close gate): `claude update` zero-EACCES on EL9 — the native installer and the EACCES guarantee are OS-neutral; EL9 only needs `curl` + `jq` present in the harness

**Parity — needs EL9 implementation (same behavior, branched impl):**

- Distro gate: accept `ID=almalinux` + `VERSION_ID=9.*`; export `AGENTLINUX_DISTRO_FAMILY=rhel`
- RT-01 (Node 22 LTS): NodeSource rpm `setup_22.x` + `dnf install nodejs`
- BHV-01 locale: write `/etc/locale.conf` directly; no `locale-gen`/`update-locale`/`locales` pkg
- DET-02 NodeSource arm: `rpm -q nodejs` (release contains `nodesource`) + `/etc/yum.repos.d/nodesource-nodejs.repo`
- DET-02 distro-pkg arm: AppStream `nodejs` module classification via `dnf module list` / `rpm -q` without nodesource release marker
- Package auto-install fallbacks: `dnf install -y sudo`, `dnf install -y jq`, `dnf install -y cronie`
- Harness: `Dockerfile.almalinux-9` + QEMU GenericCloud row

**Genuinely different on EL9 (expectation itself changes):**

- Login-shell user init file: `~/.bash_profile` (not `~/.profile`) — absorbed by profile.d + `~/.bashrc` marker design; no code change needed; `--top` rationale comment must be reworded to be distro-neutral
- Locale tooling: `localectl`/`/etc/locale.conf`/`localedef` instead of `locale-gen`/`update-locale`/`/etc/default/locale`

**Anti-features / explicitly out of scope:**

- AlmaLinux 10, RHEL, Rocky, Fedora, CentOS Stream (first-person-friction rule)
- AL-59 alt-user wiring (distro-independent; planned separately under Epic AL-48)
- New catalog agents beyond the existing three

### Architecture Approach

The integration follows pattern **(A)**: a new `plugin/lib/pkg.sh` thin dispatch library with exactly the verbs the 13 apt/dpkg/locale call sites need (`pkg_install`, `pkg_is_installed`, `pkg_remove`, `pkg_autoremove`, `nodesource_setup`, `nodesource_repo_paths`, `locale_ensure`), dispatched on `AGENTLINUX_DISTRO_FAMILY`. `distro_detect.sh` gains one new export (`AGENTLINUX_DISTRO_FAMILY`) and one new `case` arm for `almalinux`. Every provisioner and detect fragment inherits the verbs by sourcing `pkg.sh` after `distro_detect.sh`. The DECIDE-THEN-ACT flow, `RESOLUTIONS[...]` dispatch, idempotency primitives, and source order are untouched.

**Major components and their EL9 changes:**

1. `lib/distro_detect.sh` — add `AGENTLINUX_DISTRO_FAMILY` export + `almalinux` `case` arm; escape hatch must also seed the family
2. `lib/pkg.sh` (NEW) — the single place the apt/dnf branch lives; covers all 13 call sites; `locale_ensure` writes `/etc/locale.conf` directly on EL9 (never `localectl` — no D-Bus in Docker)
3. `provisioner/10-agent-user.sh` — locale block entirely replaced by `locale_ensure C.UTF-8`; verify via `locale -a | grep -Eiq '^c\.utf-?8$'` (already portable)
4. `provisioner/20-sudoers.sh` — `apt-get install sudo` → `pkg_install sudo`; everything else is identical on EL9
5. `provisioner/30-nodejs.sh` — pre-reqs, NodeSource gate, nodejs install all through `pkg.sh` verbs; drop `apt-transport-https`; add `dnf module reset nodejs` for brownfield robustness
6. `provisioner/40-path-wiring.sh`, `50-registry-cli.sh` — FULLY AGNOSTIC; no code change
7. `detect/nodejs.sh` — `dpkg-query` → `rpm -q --qf '%{VERSION}-%{RELEASE}'`; repo-file gate → `/etc/yum.repos.d/nodesource-nodejs.repo`; add AppStream module arm
8. `detect/user.sh` — `can_sudo_apt` probe → `/usr/bin/dnf --version` on EL9
9. `tests/docker/Dockerfile.almalinux-9` (NEW) — `FROM almalinux:9`; `cronie`, `openssh-server`, `sudo`, `jq`, `curl`; bats via EPEL or vendored
10. `tests/qemu/cloud-init/almalinux-9/user-data` (NEW) — `sshd` (not `ssh`); bundled bats (no EPEL in seed)
11. `tests/bats/helpers/distro.bash` (NEW) — `locale_conf_path`, `nodesource_repo_path`, `pkg_query_installed`; used by ~5 currently Ubuntu-path-hardcoded assertions

### Critical Pitfalls

1. **SELinux enforcing denies sshd `authorized_keys` written by root** — `restorecon -R -F -v /home/agent/.ssh` after writing (harness `setup()` + provisioner guard); `command -v restorecon` makes it a no-op on Ubuntu. `setenforce 0` / `SELINUX=disabled` is **EXPLICITLY REJECTED** — breaks every real enforcing EL9 host and fails maintainer first-person friction.

2. **Distro gate hard-rejects AlmaLinux 9** — everything depends on widening `distro_detect.sh` first. Match on `ID=almalinux` (not `ID_LIKE` — that would silently admit Rocky/RHEL/Fedora which are out of scope and untested).

3. **13 hardcoded `apt-get`/`dpkg` call sites each die with `command not found`** — build `lib/pkg.sh` FIRST; inline per-site `if [[ $FAMILY == rhel ]]` branches at all 13 sites are the wrong shape (13× duplicated drift, unauditable across 5 files).

4. **AppStream `nodejs` module collision on brownfield EL9 hosts** — NodeSource's `setup_22.x` sets `module_hotfixes=1` (greenfield safe) but does NOT reset an already-installed `nodejs:NN` stream. Add `dnf -y module reset nodejs` before the NodeSource install for brownfield robustness.

5. **QEMU checksum vacuous-pass via `-latest` filename** — `sha256sum --ignore-missing` against the `-latest` filename matches zero `CHECKSUM` rows and exits 0 silently. Pin the dated filename; add a `>=1 file validated` guard. Default SSH user is `almalinux` (not root) — drive install via `almalinux@` + sudo or inject root SSH in the cloud-init seed.

---

## Reconciled Decisions

### 1. Locale handling — LOCKED

**EL9 branch writes `/etc/locale.conf` directly.** Never use `localectl set-locale` — it talks to `systemd-localed` over D-Bus, which is not guaranteed in Docker test containers. `C.UTF-8` is a glibc 2.34 built-in on EL9 — no `locale-gen`, no `glibc-langpack-en`, no generation step. The `locale_ensure C.UTF-8` verb in `pkg.sh` (EL9 arm): skip the locale-gen block entirely; write `LANG=C.UTF-8` and `LC_ALL=C.UTF-8` to `/etc/locale.conf` via the existing atomic write primitive.

**BHV-01 test requires a per-distro path branch:** `/etc/default/locale` on Debian, `/etc/locale.conf` on EL9. Implement via a `locale_conf_path` helper in `tests/bats/helpers/distro.bash`. The `locale -a` assertions (lines 69-73 of `20-agent-user.bats`) are already portable and require no change.

### 2. Phase shape — LOCKED (5 phases, 18 to 22)

The ARCHITECTURE 18→22 proposal and PITFALLS P-DETECT/P-PROV/P-BROWN/P-CAT/P-HARNESS/P-REL buckets are reconciled into the following canonical structure:

| Phase | Name | PITFALLS buckets absorbed |
|-------|------|--------------------------|
| 18 | Detection + Branching Foundation | P-DETECT + P-PROV + P-BROWN (DET-02 rpm arm) |
| 19 | Docker EL9 Row | P-HARNESS (Docker) |
| 20 | Behavior-Test-Green on EL9 | P-HARNESS (bats) + remaining P-BROWN brownfield fixtures |
| 21 | Catalog Verify on EL9 | P-CAT |
| 22 | QEMU Release-Gate + Pipeline | P-HARNESS (QEMU) + P-REL |

The **DET-02 rpm arm** (detect/nodejs.sh: `rpm -q` + yum repo gate + AppStream module classification) belongs in **Phase 18** alongside the pkg.sh abstraction — it is detection infrastructure, not catalog work. The deeper brownfield EL9 fixtures (AppStream-Node / NodeSource-RPM / nvm-managed scenarios) land in **Phase 20** alongside the bats parameterization that exercises them.

### 3. Open questions and locked risks

| Item | Status | Answer |
|------|--------|--------|
| Playwright EL9 chromium system-libs | **OPEN** | Current `@playwright/cli` recipe does NOT download or launch a Chromium browser (confirmed — recipe runs `npm install -g @playwright/cli` + `playwright-cli install --skills` for skill wiring only). As written, AGT-05 ports unchanged. BUT: must be verified in Phase 21 against the live `tests/bats/50-agents.bats` AGT-05 assertion. If any EL9 code path launches Chromium, apt `install-deps` dies and an explicit `dnf install` list is required (`nss atk at-spi2-atk cups-libs libdrm libXcomposite libXdamage libXrandr mesa-libgbm alsa-lib pango cairo` — exact minimal set pinned by a headless-chromium smoke on `almalinux:9`). Phase 21 owns this resolution. |
| `bats` not in base AlmaLinux repos | **LOCKED** | For **QEMU**: use bundled bats from the second tarball boot.sh already scps (`node_modules/bats/bin/bats`, boot.sh lines 370-373/404-405 — boot.sh already prefers this path). Keep the EL9 cloud-init seed minimal (`jq`, `ca-certificates`, `curl`); no EPEL dependency in the release gate. For **Docker**: EPEL (`dnf install -y epel-release && dnf install -y bats`) or vendored bats in the Dockerfile — either acceptable; EPEL is simpler. |
| QEMU checksum vacuous-pass | **LOCKED** | Pin the dated/versioned AlmaLinux image filename in `cloud-images.txt` (NOT `-latest`); add a `>=1 file validated` guard to `sha256sum --check` (fail if zero rows matched). A deliberate-corruption test must exit non-zero to prove the gate is live. |
| QEMU default user `almalinux` | **LOCKED** | AlmaLinux GenericCloud default user is `almalinux` (verified), not root. Drive the in-guest install via `almalinux@localhost` + sudo, or inject root SSH via `write_files` to sshd_config in the cloud-init seed. SSH service name is `sshd` (not `ssh`); `runcmd` must use `systemctl enable --now sshd`. |
| SELinux `restorecon ~agent/.ssh` | **LOCKED** | `restorecon -R -F -v /home/agent/.ssh` REQUIRED after any code path writes into `~agent/.ssh`. Default `/home` location: no `semanage fcontext` needed (targeted policy maps `/home/[^/]+/\.ssh(/.*)?` → `ssh_home_t`). Apply in: (a) harness `setup()` after installing `authorized_keys`; (b) installer provisioner as a post-home-write guard, guarded by `command -v restorecon`. `setenforce 0` / `SELINUX=disabled` is **EXPLICITLY REJECTED**. |

---

## Implications for Roadmap

Phase numbering continues from v0.3.4 (last phase 17); v0.3.5 starts at Phase 18.

### Phase 18: Detection + Branching Foundation

**Rationale:** The foundation everything else depends on. Nothing installs on EL9 until `distro_detect.sh` accepts AlmaLinux and the provisioners branch. Parts can be unit-sourced on the Ubuntu dev host via `AGENTLINUX_SKIP_DISTRO_CHECK=1 AGENTLINUX_DISTRO_FAMILY=rhel`, but real validation requires Phase 19's Docker substrate — treat them as co-developed.

**Delivers:**
- `lib/distro_detect.sh`: `ID=almalinux` arm; `AGENTLINUX_DISTRO_FAMILY` export; escape hatch seeds family; AlmaLinux 10 / Rocky / RHEL still rejected explicitly
- `lib/pkg.sh` (NEW): `pkg_install`, `pkg_is_installed`, `pkg_remove`, `pkg_autoremove`, `nodesource_setup`, `nodesource_repo_paths`, `locale_ensure` — all 13 apt/dpkg/locale call sites routed through it
- `provisioner/10-agent-user.sh`: locale block → `locale_ensure C.UTF-8`; writes `/etc/locale.conf` directly on EL9; skips locale-gen/update-locale/apt-install-locales entirely
- `provisioner/20-sudoers.sh`: `apt-get install sudo` → `pkg_install sudo`
- `provisioner/30-nodejs.sh`: pre-reqs + NodeSource rpm `setup_22.x` gate + `dnf install nodejs`; drop `apt-transport-https`; add `dnf module reset nodejs` for brownfield; gate on `/etc/yum.repos.d/nodesource-nodejs.repo`
- `plugin/bin/agentlinux-install`: `ensure_jq` (EL: `pkg_install jq`) + purge cleanup (EL: yum repo paths + `dnf remove`)
- `lib/detect/nodejs.sh`: `rpm -q --qf '%{VERSION}-%{RELEASE}'` + yum repo gate + AppStream module arm
- `lib/detect/user.sh`: `can_sudo_apt` → `can_sudo_pkg` (probe `/usr/bin/dnf` on EL9)
- `provisioner/40-path-wiring.sh`: comment-only reword (no code change)
- `packaging/curl-installer/install.sh`: accept `almalinux` `9.*` in lockstep
- ADR-017: record family-bucket + dnf-branch decision

**Pitfalls addressed:** 10 (distro gate), 4 (apt/dpkg hardcode), 2 (locale tooling), 3 (dnf module collision greenfield), 5 (NodeSource rpm mechanism), 7 (package-name drift map), 9 (rpm-vs-dpkg detection)

### Phase 19: Docker AlmaLinux 9 Row

**Rationale:** Fast feedback substrate. Need the `almalinux:9` Docker row to validate Phase 18 on a real EL9 environment. Phase 19 is Phase 18's acceptance gate — they are co-developed (18 lands the branch; 19 proves it produces a green install).

**Delivers:**
- `tests/docker/Dockerfile.almalinux-9` (NEW): `FROM almalinux:9`; multi-stage with cli-builder unchanged; final stage `dnf install` set: `systemd cronie openssh-server sudo jq curl python3 file util-linux ca-certificates bash coreutils`; bats via EPEL or vendored
- `tests/docker/run.sh`: accept `almalinux-9` target; rename `UBUNTU_VERSION` → `TARGET`
- `.github/workflows/test.yml`: add `almalinux-9` to matrix; rename dimension `ubuntu` → `target`
- `.github/workflows/release.yml` gate-2: add `almalinux-9` to matrix

**Pitfalls addressed:** 7 (package-name drift verified by Docker build), 1 (SELinux harness `setup()` restorecon)

**Research flag:** Low — `almalinux:9` Docker tag is stable. One spot-check: NodeSource `setup_22.x` runs its own distro detection; verify it does not trip on `almalinux:9` (AlmaLinux is officially supported; `/etc/redhat-release` is present as a fallback — treat as a verification item, not a blocker).

### Phase 20: Behavior-Test-Green on AlmaLinux 9

**Rationale:** The Docker arm must produce a green bats suite before catalog work (Phase 21's tests run inside the suite). Approximately 5 bats assertions hardcode Ubuntu/apt paths; these need distro-aware helpers. Brownfield EL9 fixtures must classify correctly.

**Delivers:**
- `tests/bats/helpers/distro.bash` (NEW): `locale_conf_path`, `nodesource_repo_path`, `pkg_query_installed`, `is_selinux_enforcing` — mirrors `pkg.sh` at the test layer
- Parameterized assertions (verified file:line in ARCHITECTURE.md §4c): `20-agent-user.bats:59,64` (BHV-01 locale file path); `10-installer.bats:78,106` (INST-02 NodeSource repo path); `40-registry-cli.bats:656-659` (INST-04 purge yum repo path); `52-agt02-brownfield-gate.bats:122`, `helpers/brownfield.bash:86,139,503` (`dpkg-query`→`rpm -q`; `apt-get`→`dnf`); `helpers/brownfield.bash:78,285`, `14-remediate.bats:473,671`, `15-preflight-ux.bats:70` (sudoers fixtures `apt-get`→`dnf` probe)
- Brownfield EL9 fixtures: AppStream `nodejs:18` installed, NodeSource RPM installed, nvm-managed — each produces correct DET-02 classification; read-only snapshot invariant holds (use `rpm -q` / file probes, not bare `dnf` which writes `/var/cache/dnf`)
- Full BHV/RT/AGT/CLI/CAT/INST contract green in the Alma Docker arm
- SELinux harness guard: `restorecon -R -F -v /home/agent/.ssh` in `setup()` for SSH tests

**Pitfalls addressed:** 2 (BHV-01 assertion path), 5 (INST-02/INST-04 repo-path assertions), 9 (brownfield detection fixtures), 1 (SELinux ssh context in test harness)

**Research flag:** Low-medium — brownfield AppStream Node fixture (Pitfall 3) needs a real EL9 `dnf module install nodejs:18` scenario verified on the Docker arm. The read-only detection invariant (`15-detection.bats`) must stay green — prefer `rpm -q` / file probes over `dnf` queries in the detection layer.

### Phase 21: Catalog Verify on EL9

**Rationale:** claude-code and gsd are OS-neutral (confirmed); playwright-cli needs verification. AGT-02 EL9 green is the milestone-close gate and runs inside the bats suite that Phase 20 makes green. Phases 20 and 21 can overlap once the Docker arm is generally green.

**Delivers:**
- claude-code recipe verified on EL9: native installer OS-neutral; harness ensures `curl` + `jq` present; no change
- gsd recipe verified on EL9: `npm install -g` OS-neutral; no change
- playwright-cli recipe: run AGT-05 bats assertion on `almalinux:9` — if any EL9 code path launches Chromium, add `dnf install` chromium-deps block; exact minimal dep list pinned by on-box smoke result
- AGT-02 on EL9: `sudo -u agent -H bash --login -c 'claude update'` zero-EACCES — milestone-close gate

**Pitfalls addressed:** 6 (secure_path audit for any bare-sudo tool resolution in catalog recipes)

**Research flag:** MEDIUM — Playwright EL9 chromium question is the single highest-uncertainty item. Do not pre-scope a dnf-deps task until the Phase 21 smoke result is in hand. If the recipe currently does not launch a browser (most likely), no dnf-deps work is needed.

### Phase 22: QEMU Release-Gate + Pipeline

**Rationale:** QEMU is the authoritative gate (ADR-007: "Docker alone is disqualified"). Iterate everything in Docker (18-21), then prove it once in QEMU and wire the release-pipeline arm. AlmaLinux 9 must be green in `release.yml` gate-2 (Docker) AND gate-3 (QEMU) before the v0.3.5 tag.

**Delivers:**
- `tests/qemu/cloud-images.txt`: Alma row with dated/versioned image filename (NOT `-latest`); possibly a 4th column for the explicit cached filename
- `tests/qemu/boot.sh`: parameterized for EL9 — arg parse, codename-map skip, `IMG_NAME` from manifest column, `>=1 validated` checksum guard, drive guest via `almalinux@localhost` + sudo, SSH service name `sshd`
- `tests/qemu/cloud-init/almalinux-9/user-data` (NEW): `runcmd: systemctl enable --now sshd`; packages: `jq ca-certificates curl`; bundled bats (no EPEL); `disable_root: false` + `ssh_authorized_keys`
- `.github/workflows/nightly-qemu.yml` + `release.yml` gate-3: add `almalinux-9` Alma arm; rename dimension `ubuntu` → `target`
- `docs/HARNESS.md` + `.claude/skills/qemu-harness/SKILL.md`: Alma cloud-image row + non-Ubuntu target touchpoints

**Pitfalls addressed:** 8 (QEMU checksum vacuous-pass + dated-filename pin + almalinux default user), 1 (SELinux restorecon verified end-to-end on real enforcing cloud image)

**Research flag:** Low — cloud image boot path is well-documented; EL cloud-init differences are locked. The SELinux enforcing verification on the real cloud image is the one item that cannot be fully validated in Docker; this is exactly the work QEMU exists for.

### Phase Ordering Rationale

- **18 must come first** — `distro_detect.sh` + `pkg.sh` are consumed by every provisioner and detect fragment. DET-02 rpm arm belongs here (detection infrastructure stratum, not catalog work).
- **19 is 18's acceptance gate** — unit-sourcing `pkg.sh` on a Ubuntu dev host only validates the abstraction surface; the `almalinux:9` Docker row validates actual EL9 behavior. Co-develop 18+19.
- **20 before 21** — catalog/AGT-02 tests run inside the bats suite; the suite must be green-able before iterating recipe-level EL9 fixes.
- **21 can overlap 20** — once the Docker arm is generally green, catalog verification can proceed in parallel with any remaining bats edge cases.
- **22 last** — QEMU is the slow, authoritative gate. Iterate fast in Docker (18-21), then prove once in QEMU and wire the release-pipeline arm.

### Research Flags

**Phases needing focused investigation during planning:**

- **Phase 21 (Playwright):** Whether any EL9 code path launches Chromium is unresolved. Run the live AGT-05 bats assertion on `almalinux:9` before scoping a dnf-deps task. If a dep list is needed, verify the exact minimal set via an on-box smoke, not from spec lists alone.
- **Phase 19 (NodeSource distro-detect):** NodeSource `setup_22.x` runs its own distro detection; spot-check on the real `almalinux:9` image. AlmaLinux is officially supported; `/etc/redhat-release` is present as fallback — treat as verification, not blocker.

**Phases with standard, well-documented patterns (skip additional research):**

- **Phase 18 (pkg.sh abstraction):** Call sites are enumerated; the abstraction pattern is mechanical; ARCHITECTURE.md has the exact verb set.
- **Phase 18 (sudoers):** Confirmed byte-identical on EL9. Zero research needed.
- **Phase 22 (QEMU cloud-init):** EL cloud-init differences (`sshd` vs `ssh`, default user `almalinux`) are verified and locked.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All 13 call sites verified in repo; NodeSource rpm `setup_22.x` read verbatim upstream; `curl-minimal` conflict, `C.UTF-8` glibc built-in, `cronie` vs `cron` — all verified against current EL9 docs |
| Features | HIGH | Behavior contract read directly from bats files and requirement IDs; EL9 shell-init paths verified against Red Hat + multi-source community docs; `40-path-wiring.sh` distro-agnosticism verified at file:line |
| Architecture | HIGH | Every apt/dpkg call site verified at file:line in the repo; Docker/QEMU matrix definitions verified in workflows + run.sh/boot.sh; NodeSource rpm path, `almalinux:9` Docker tag, cloud-image URL verified upstream |
| Pitfalls | HIGH (SELinux-ssh/locale/dnf-module/apt-dpkg) / MEDIUM (SELinux-systemd, secure_path blast radius) | SELinux ssh context: verified against Red Hat solutions + Ansible issue tracker; dnf module collision: NodeSource setup_22.x read verbatim; secure_path: RH docs + reasoning |

**Overall confidence: HIGH**

The one area bounded by "cannot fully validate in Docker" is SELinux enforcing behavior under systemd `User=agent` (BHV-04) — the targeted policy leaves useradd-created users `unconfined_u` (execution of home binaries allowed), which is likely fine but must be confirmed by an AVC scan in Phase 22's QEMU run.

### Gaps to Address

- **Playwright EL9 chromium question (Phase 21):** Resolve by running the live AGT-05 bats assertion on `almalinux:9` before scoping any dnf browser-deps work.
- **NodeSource rpm version-string format (Phase 18/19):** The `*nodesource*` substring in `rpm -q --qf '%{VERSION}-%{RELEASE}'` output should be confirmed against actual `rpm -q nodejs` output on `almalinux:9` early in Phase 19. REUSE-02 and DET-02 classification depend on this pattern match.
- **AppStream `nodejs` module brownfield fixture (Phase 20):** `dnf module install nodejs:18` → installer runs → Node 22 lands requires a real EL9 bats fixture. Phase 20 owns this; do not defer to Phase 21.
- **QEMU checksum validated-count guard (Phase 22):** The `>=1 file validated` assertion needs implementation before the QEMU row is wired to the release gate. A flipped-byte corruption test must prove the guard is live.

---

## Sources

### Primary (HIGH confidence — verified against source)

- Repo (worktree, this session): `plugin/lib/distro_detect.sh`, `plugin/bin/agentlinux-install`, `plugin/provisioner/{10,20,30,40,50}-*.sh`, `plugin/lib/detect/{nodejs,user,agents}.sh`, `tests/docker/{run.sh,Dockerfile.ubuntu-24.04}`, `tests/qemu/{boot.sh,cloud-images.txt,cloud-init/user-data}`, `tests/bats/*.bats`, `tests/bats/helpers/{invoke_modes,brownfield}.bash`, `.github/workflows/{test,nightly-qemu,release}.yml`, `docs/decisions/007-docker-plus-qemu-harness.md`, `.planning/PROJECT.md`
- NodeSource `setup_22.x` (rpm) — https://github.com/nodesource/distributions/blob/master/scripts/rpm/setup_22.x — writes `/etc/yum.repos.d/nodesource-nodejs.repo`, sets `module_hotfixes=1`, does NOT disable AppStream module
- AlmaLinux GenericCloud qcow2 + CHECKSUM — https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/ + https://wiki.almalinux.org/cloud/Generic-cloud.html — dated filenames, GNU checksum format, default user `almalinux`
- SELinux ssh_home_t + restorecon — https://blog.tinned-software.net/ssh-key-authentication-is-not-working-selinux/ , https://access.redhat.com/solutions/3948421

### Secondary (MEDIUM-HIGH confidence)

- glibc `C.UTF-8` built-in on EL9 — https://github.com/osbuild/osbuild-composer/issues/2206 , https://linux.how2shout.com/how-to-install-and-configure-locale-on-almalinux-9/ , https://www.rosehosting.com/blog/how-to-set-up-system-locale-on-almalinux-9/
- dnf module streams / NodeSource EL9 install — https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/managing_software_with_the_dnf_tool , https://computingforgeeks.com/install-nodejs-rhel-rocky-almalinux/
- `curl-minimal` conflict — https://www.jeffgeerling.com/blog/2024/fixing-curl-install-failures-ansible-on-red-hat-derivative-oses/
- EL9 sudoers `secure_path` + `requiretty` removal — https://access.redhat.com/solutions/1298644
- EL9 shell init — https://access.redhat.com/solutions/452073 , https://www.golinuxcloud.com/bashrc-vs-bash-profile/
- Playwright `install-deps` no dnf path — https://github.com/microsoft/playwright/issues/41318 , https://github.com/microsoft/playwright/issues/29559
- `almalinux:9` Docker tag — https://hub.docker.com/_/almalinux , https://wiki.almalinux.org/containers/docker-images.html

---
*Research completed: 2026-06-27*
*Ready for roadmap: yes*
