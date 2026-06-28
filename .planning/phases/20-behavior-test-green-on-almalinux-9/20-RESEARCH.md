# Phase 20: Behavior-Test-Green on AlmaLinux 9 - Research

**Researched:** 2026-06-28
**Domain:** Driving the full existing bats behavior contract GREEN on the `almalinux-9` Docker row (EL-06, EL-08, PAR-01)
**Confidence:** HIGH — every claim below was reproduced live inside a booted `almalinux:9` container this session (build, install, per-file + full-suite bats runs, root-cause experiments). The Phase 19 quick-attribution AND its code-review caveat were both wrong about the dominant RED mechanism; the real cause is proven here.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **Generalize, never weaken:** a Debian-specific assertion becomes a distro-aware helper asserting the **same observable** on EL9. No `skip` to make EL9 green.
- **SELinux stays enforcing;** the fix for non-interactive SSH is `restorecon -R -F ~agent/.ssh`, never disabling SELinux. `setenforce 0` / `SELINUX=disabled` is **rejected**.
- **The behavior contract is the invariant;** the implementation may branch (apt→dnf, dpkg→rpm, locale-gen→/etc/locale.conf) but the asserted observable must hold identically on both families.
- **Preserve Ubuntu green:** every change must keep all Ubuntu rows green byte-for-equivalent (the distro-aware helper dispatches on family).

### Claude's Discretion
- The helper design (new `tests/bats/helpers/distro.bash` vs extending the existing `assertions.bash` / `detection.bash` / `brownfield.bash` / `invoke_modes.bash`), the per-file generalization tactics, and the root-cause fixes — guided by the Phase 19 inventory + success criteria.

### Deferred Ideas (OUT OF SCOPE)
- None new. QEMU enforcing-SELinux re-confirmation + AGT-02 milestone gate are **Phase 22**; catalog agent install verification is **Phase 21**.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| EL-06 | All six invocation modes green on **enforcing-SELinux** EL9; any path writing `~agent/.ssh/authorized_keys` follows with `restorecon -R -F ~agent/.ssh`; SELinux never disabled. | §SELinux-in-Docker Verdict (enforcing is structurally unavailable on the Docker row → land restorecon guarded + six modes green on Docker via `openssh-clients`+`sshd`; **real enforcing proof is Phase 22 QEMU**). §Per-File Remediation rows BHV-02 / 30-runtime / restorecon sites. |
| EL-08 | v0.3.4 four-state brownfield flow (Reuse/Create/Remediate/Bail) produces same per-component decisions on EL9; `--dry-run` non-mutating; `--yes` consent + exit codes 64/65/1/0. | §`brownfield.bash` generalization (the single biggest work item); REUSE-01/REMEDIATE-01..04/UX-01/UX-03 rows; `diffutils` substrate gap for NO-MUTATION snapshots. |
| PAR-01 | Complete contract (BHV/RT/AGT/CLI/CAT/INST + DET/REUSE/REMEDIATE/UX) green on the Docker row; Debian-path assertions generalized, not weakened/skipped. | §Distro-Aware Helper Design; §Per-File Remediation Map (every RED categorized: substrate / harness-hermeticity / helper-generalization / product). |
</phase_requirements>

## Summary

Phase 20 is **overwhelmingly a test-harness + test-helper job, not a product-code job.** The Phase 18 product code (`pkg.sh`, `detect/user.sh`, `detect/nodejs.sh`, `locale_ensure`) is already correctly generalized for EL9 — I confirmed `agentlinux-install` runs end-to-end to exit 0 on real EL9 (NodeSource node `22.23.1-1nodesource`, agent user, sudoers, npm prefix, CLAUDE.md, /opt/agentlinux catalog all written). Of the RED failures, **the single largest bucket is not Ubuntu-path assertions at all — it is harness substrate gaps in `Dockerfile.almalinux-9` plus one Docker tmpfs default.** These produce false-RED across many files and were misdiagnosed by the Phase 19 inventory.

**The decisive finding:** `18-pkg-dispatch` (14 fail) and `18-detect-el9` (3 fail) go **fully green (20/20 and 7/7)** by a single change — running bats with an exec-able `TMPDIR`. Docker's `--tmpfs /tmp` mounts `noexec`; the PATH-stub harnesses write executable stubs under `BATS_TEST_TMPDIR` (= `/tmp/bats-run-*`), which then cannot `execve`. Bash falls through a noexec stub to the **real** binary later in PATH (so `dnf`/`rpm`/`curl` actually run, exit 0, write nothing to the capture file → grep fails) or dies `126 Permission denied` when no real binary exists (apt-get on EL9). This is **not EL9-specific** — the same `noexec /tmp` breaks the *debian* arm of those same files on the Ubuntu Docker rows; these new Phase-18 unit files were only ever validated by dev-host unit-sourcing (exec-able `/tmp`), never run green inside Docker. Neither the Phase 19 "real dnf/rpm shadows the stubs" guess nor the code-review "`$(id -un)`=root / system-Node PATH leak" guess is the cause; both files go green with the stubs intact once `/tmp` is exec-able.

Three more **substrate package gaps** in `Dockerfile.almalinux-9` each cause broad false-RED: `diffutils` is absent (`diff: command not found` fails every NO-MUTATION snapshot + idempotency test — DET-read-only, INST-02, UX-03×4, UX-01, REMEDIATE-02), `openssh-clients` is absent (`ssh: command not found` fails BHV-02 and **every** six-mode SSH assertion — 30-runtime RT-01/02/04, 40/50/51), and `iproute` is absent (`ss` missing → the sshd readiness poll is blind; non-fatal because the image already enables `sshd`). I proved that once `openssh-clients` is present, non-interactive SSH on EL9 propagates the agentlinux PATH (`/home/agent/.local/bin`, `.npm-global/bin`) and `LANG=C.UTF-8` correctly — there is no product/profile-wiring defect.

The **genuine Ubuntu-path-assertion generalization** work (the real PAR-01/EL-08 scope) is concentrated in: (a) `tests/bats/helpers/brownfield.bash` — hardcoded `dpkg-query`, `curl deb.nodesource.com`, `apt-get install nodejs`, and a NOPASSWD-for-**apt** sudoers fragment drive the REUSE-03 / REMEDIATE-01..04 / UX-03 / UX-01 / 15-preflight-ux family; (b) the `/etc/default/locale` BHV-01 assertions in `20-agent-user.bats`; (c) the INST-02 idempotency snapshot file-list referencing `/etc/apt/sources.list.d/nodesource.sources`; (d) the `systemctl start ssh` unit name (EL9 = `sshd`); and (e) the REUSE-01 `can_sudo_apt` probe defaulting to the debian arm because the test never runs `detect_distro` to seed `AGENTLINUX_DISTRO_FAMILY`.

**Primary recommendation:** Sequence the phase as **substrate-first, helpers-second, assertions-third**. Wave 1: fix `Dockerfile.almalinux-9` (+`diffutils` +`openssh-clients` +`iproute` +`policycoreutils`) and make bats run under an exec-able tmpdir (`--tmpfs /tmp:exec` in `run.sh`, the most faithful single-point fix) — this alone flips ~40 false-RED tests green with zero assertion edits and keeps Ubuntu byte-identical. Wave 2: build `tests/bats/helpers/distro.bash` (family-detect + verbs) and route `brownfield.bash` + `invoke_modes.bash` + the BHV-01/INST-02 assertions through it. Wave 3: land the guarded `restorecon` at the two SSH-seeding sites. Validate after each wave with the full `run.sh almalinux-9` suite **in order** (per-file isolation over-reports RED — see §Methodology).

## Architectural Responsibility Map

Single-tier system installer + its bats test harness. The "tiers" are the harness strata; mapping confirms each fix lands in the correct stratum (substrate vs helper vs assertion vs product).

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| EL9 tool/package availability for the suite | `tests/docker/Dockerfile.almalinux-9` | `tests/docker/run.sh` (tmpfs flags) | Missing `diff`/`ssh`/`ss`/`restorecon` + noexec `/tmp` are substrate, not test logic — fix once, many files green |
| Distro-aware fixture build (Node install, sudoers, pkg query) | `tests/bats/helpers/brownfield.bash` | NEW `tests/bats/helpers/distro.bash` | The brownfield fixtures hardcode apt/dpkg/deb — the family branch belongs in a shared helper, not per-@test |
| Six-mode invocation (incl. SSH unit name + restorecon) | `tests/bats/helpers/invoke_modes.bash` | `20-agent-user.bats` / `50-agents.bats` setup | `systemctl start ssh`→`sshd` + restorecon land where keys are seeded |
| Distro-aware observable assertions (locale path, repo path) | NEW `tests/bats/helpers/distro.bash` | `20-agent-user.bats`, `10-installer.bats` | `/etc/default/locale` vs `/etc/locale.conf` is one observable, two paths — dispatch on family |
| Family token seeding inside tests | `tests/bats/helpers/distro.bash` (or call `detect_distro`) | `13-reuse.bats`, `15-detection.bats` | REUSE-01 probe defaults to debian when `AGENTLINUX_DISTRO_FAMILY` is unset in the test subshell |
| Product detection/branch logic | `plugin/lib/pkg.sh`, `plugin/lib/detect/*` | — | **Already correct on EL9** (verified live); Phase 20 should NOT touch these except if §Open Q DET-03 surfaces a real defect |

## Methodology (why per-file isolation lies — read before trusting any RED count)

Per-file isolated bats runs on EL9 **over-report RED** because destructive tests mutate shared post-install state:
- `40-registry-cli.bats` INST-04 `--purge` runs `userdel -r agent` (deletes `/home/agent`, `/opt/agentlinux`, the npm-global symlink).
- `13-reuse`/`14-remediate` brownfield fixtures call `agentlinux-install --purge` then rebuild partial state.
I reproduced this directly: after running `13-reuse` in isolation, a later isolated `10-installer` showed INST-01/DOC-02/CAT-05 as RED (`/home/agent/CLAUDE.md`, `/opt/agentlinux` gone, agent home reset to skel, npm-prefix left root-owned). In the **full suite in filename order** (install once, then `bats tests/bats/`), `10-installer` runs first and those same tests **PASS** — only INST-02 (idempotency) stays RED. **Authoritative signal = `tests/docker/run.sh almalinux-9` (full suite, in order), exactly as CI runs it.** The Phase 19 per-file inventory inflated counts for this reason.

The full suite this session hung at test ~138 (a `15-preflight-ux` TTY-driver test — `python3` pexpect blocked ~13 min) before reaching files 18→60; I covered those by targeted clean-container runs. The hang itself is a Phase-20 item (see §Per-File Remediation, 15-preflight-ux).

## SELinux-in-Docker Verdict (the flagged open question — RESOLVED, forces a planning split)

**Verdict: enforcing SELinux is structurally UNAVAILABLE on the Docker row, on this dev host AND on GitHub `ubuntu-*` runners. Do not attempt to make Docker "enforce" SELinux.** Evidence, gathered live in the booted `almalinux:9` container:

- The host kernel is Ubuntu/**AppArmor**: `cat /sys/kernel/security/lsm` → `lockdown,capability,landlock,yama,apparmor` (no `selinux`). GitHub `ubuntu-latest` runners are identical AppArmor hosts.
- Inside the EL9 container: `/sys/fs/selinux` **does not exist**; `grep selinux /proc/filesystems` → **no `selinuxfs`**. SELinux is a kernel LSM — a container shares the host kernel, so an AppArmor-kernel host **cannot** present an enforcing SELinux to any container. `getenforce` would report `Disabled` if it were installed (it is not).
- `libselinux` is present but `policycoreutils` (`restorecon`, `setfiles`, `fixfiles`) and `libselinux-utils` (`getenforce`/`setenforce`) are **not installed** in the image.

**Consequences for EL-06 acceptance, split honestly Phase-20 vs Phase-22:**
1. The "non-interactive SSH silently fails because confined `sshd_t` can't read an unlabeled `authorized_keys`" scenario **cannot be reproduced on Docker** (no SELinux, no labels). On Docker, non-interactive SSH fails **only** for the mundane reason that the `ssh` client package is missing — fixed by adding `openssh-clients`. Once present, all six modes pass on Docker with `sshd` running.
2. The `restorecon -R -F ~agent/.ssh` code still **lands in Phase 20** at the harness SSH-seeding sites, but it must be **guarded** (`command -v restorecon >/dev/null && restorecon -R -F /home/agent/.ssh || true`) because `restorecon` is absent in the image and would otherwise abort. On the Docker row it is a deliberate **no-op**. (Optionally add `policycoreutils` to the image so the call exercises the real binary path even though there is no policy to apply.)
3. **The genuine enforcing-SELinux six-modes proof is Phase 22 QEMU** (real cloud image, real kernel SELinux, stock `0000` shadow), exactly as the REQUIREMENTS EL-06 note states ("the Phase 22 QEMU row re-confirms it under real enforcement"). EL-06 maps to Phase 20 for the restorecon-code + six-modes-on-Docker deliverable; Phase 22 owns the enforcement re-confirmation. **No double-counting.**
4. **NEVER `setenforce 0`** — moot here (no SELinux to disable) but the principle binds the Phase 22 work.

**Recommended Phase-20 EL-06 acceptance (Docker):** (a) guarded `restorecon` present at both SSH-seeding sites and in any installer path that writes `~agent/.ssh` (currently none — keys come from cloud-init/external, so the installer does not seed them); (b) all six modes green on the Docker row with `openssh-clients` + `sshd`; (c) a one-line documented note in the plan/summary that enforcing-SELinux is unavailable on Docker and is re-proven in Phase 22. State this reality plainly; do not pretend the Docker row enforces.

## Per-File Remediation Map (every RED categorized)

Categories: **[SUBSTRATE]** = `Dockerfile.almalinux-9`/`run.sh` fix, no assertion edit; **[HARNESS]** = test-hermeticity bug (family token, unit name, exec dir); **[HELPER-GEN]** = genuine Ubuntu-path assertion → distro-aware helper; **[PRODUCT]** = a real EL9 `plugin/` defect; **[INVESTIGATE]** = needs a Phase-20 root-cause spike. Counts are from the authoritative full-suite-in-order run unless noted.

| File | RED (authoritative) | Category | Root cause (verified) | Fix |
|------|---------------------|----------|------------------------|-----|
| `18-distro-detect` | 0 (15/15 green) | — | Positive anchor — Phase 18 abstraction correct on EL9 | none |
| `18-pkg-dispatch` | 14 → **0** with exec tmpdir | **[SUBSTRATE]** | `noexec /tmp`: stubs can't `execve`; bash falls through to real `dnf`/`rpm`/`curl` (exit 0, empty capture) or `126` on apt-get | exec-able tmpdir (see Wave 1) — stubs untouched |
| `18-detect-el9` | 3 → **0** with exec tmpdir | **[SUBSTRATE]** | Same noexec fallthrough: real `rpm` reports the actually-installed `22.23.1-1nodesource` instead of the stub's configured NEVR; real `sudo` runs instead of the logging stub | exec-able tmpdir — stubs untouched |
| `10-installer` | 1 (INST-02) | **[HELPER-GEN]** | INST-02 `find` snapshot list hardcodes `/etc/apt/sources.list.d/nodesource.sources`; `find` exits 1 on the missing path → test fails. (INST-01/DOC-02/CAT-04/CAT-05 PASS in order.) Also depends on `diff` (substrate). | snapshot file-list via `nodesource_repo_paths` + `/etc/locale.conf` on rhel; +`diffutils` |
| `13-reuse` | 3 (REUSE-01×2, REUSE-03 E2E) | **[HARNESS]** + **[HELPER-GEN]** | REUSE-01 `can_sudo_apt` probe returns false: the test sources `distro_detect.sh` but never runs `detect_distro`, so `AGENTLINUX_DISTRO_FAMILY` is unset → probe defaults to `apt-get` → missing on EL9. REUSE-03 E2E fails in `setup_brownfield_host` (apt/dpkg/deb fixture). | seed family token in test (call `detect_distro` / `distro.bash`); generalize `brownfield.bash` |
| `14-remediate` | ~14 (REMEDIATE-01/02/03/04 + UX-03 snapshots) | **[HELPER-GEN]** + **[SUBSTRATE]** | All E2E REMEDIATE fail in `_brownfield_baseline` setup (`dpkg-query`, `curl deb.nodesource.com`, `apt-get install nodejs`, NOPASSWD-for-apt). UX-03 NO-MUTATION snapshots also need `diff`. | generalize `brownfield.bash` fixtures; +`diffutils` |
| `15-detection` | 2 (DET-03, DET-read-only) | **[SUBSTRATE]** + **[INVESTIGATE]** | DET-read-only #118: `diff: command not found`. DET-03 #111: `effective_prefix`/`NPM_CONFIG_PREFIX` via `as_user_login` assertion — login PATH/locale proven to propagate on EL9, so likely a fixture/assertion detail, but verify. | +`diffutils`; spike DET-03 (§Open Questions) |
| `15-preflight-ux` | ≥3 (UX-01, UX-02 TTY, UX-04 TTY) + **hang** | **[HELPER-GEN]** + **[INVESTIGATE]** | UX TTY tests drive `tty-driver.py` against brownfield (apt) fixtures; when the fixture mis-sets EL9 state the installer takes an unexpected branch and pexpect blocks (the ~13-min hang). UX-01 NO-MUTATION needs `diff`. | generalize `brownfield.bash`; add a pexpect timeout to `tty-driver.py`; +`diffutils` |
| `20-agent-user` | 4 (BHV-01×2, BHV-02×2) | **[HELPER-GEN]** + **[SUBSTRATE]** | BHV-01 asserts `/etc/default/locale` (Debian path; EL9 uses `/etc/locale.conf`). BHV-02 `ssh: command not found` (no `openssh-clients`). `BHV-01: C.UTF-8 in locale -a` already PASSES (portable). | locale assertion via `distro.bash`; +`openssh-clients`; `systemctl start ssh`→`sshd` |
| `22-agent-sudo` | **0 (7/7 green)** | — | EL-05 passwordless sudo across modes works on EL9 (sudoers drop-in is family-agnostic) | none |
| `30-runtime` | 3 (RT-01, RT-02, RT-04) | **[SUBSTRATE]** | "every invocation mode" loops include the SSH mode → `ssh: command not found` (exit 127) short-circuits the whole loop. Proven: with `openssh-clients`, SSH delivers correct PATH + node + LANG. RT-02 cowsay is npm-installed by the fixture (not a substrate gap). | +`openssh-clients` (SSH-mode); re-verify cowsay fixture |
| `40-registry-cli` | not reached this session | **[SUBSTRATE]** likely | uses SSH modes + `diff` snapshots | +`openssh-clients` +`diffutils`; re-run in Wave 1 |
| `50-agents` / `51-agt02` / `52-agt02` | not reached this session | **[HARNESS]**+**[SUBSTRATE]** | `setup_file` re-seeds `authorized_keys` (restorecon site) + uses SSH; `51` is the AGT-02b gate | +`openssh-clients`; restorecon site; re-run Wave 1 |
| `60-curl-installer` | **0 (4/4 green)** | — | Phase-18 lockstep already accepts `almalinux 9.*`; `python3`/`file` present in image | none |

## Distro-Aware Helper Design (`tests/bats/helpers/distro.bash`)

**Recommendation: NEW `tests/bats/helpers/distro.bash`, then refactor `brownfield.bash` + `invoke_modes.bash` + the BHV-01/INST-02 assertions to call it.** A new file (vs extending `assertions.bash`) keeps the family-dispatch auditable in one place and mirrors the product-side `plugin/lib/pkg.sh` pattern HARN-02 already names (`tests/bats/helpers/distro.bash`). It must dispatch on `/etc/os-release` `ID` **inside the container** (the test process, not the product), so it works without sourcing product libs.

**Verbs the residue actually needs (each a two-arm `case` on a test-local `_distro_family`):**

| Verb | rhel arm | debian arm | Consumer(s) |
|------|----------|------------|-------------|
| `distro_family` | reads `/etc/os-release` `ID` → `rhel`/`debian`; caches | same | every other verb; `13-reuse`/`15-detection` to seed `AGENTLINUX_DISTRO_FAMILY` |
| `distro_locale_file` | `/etc/locale.conf` | `/etc/default/locale` | BHV-01 (`20-agent-user`) |
| `distro_assert_locale <LANG\|LC_ALL>` | grep `^LANG=C.UTF-8` in `/etc/locale.conf` | same in `/etc/default/locale` | BHV-01 |
| `distro_nodesource_repo_paths` | `/etc/yum.repos.d/nodesource-nodejs.repo` | `/etc/apt/sources.list.d/nodesource.sources` … | INST-02 snapshot list; brownfield gates (reuse the product `nodesource_repo_paths` verb where a product lib is already sourced) |
| `distro_pkg_is_installed <pkg>` | `rpm -q` | `dpkg-query -W -f='${Status}' … \| grep -q 'install ok installed'` | `brownfield.bash` Node-present gate |
| `distro_install_node22` | `curl rpm.nodesource.com/setup_22.x \| bash -; dnf module reset nodejs -y \|\| true; dnf install -y nodejs` | `curl deb.nodesource.com…; apt-get install -y nodejs` | `setup_brownfield_host`, `_brownfield_baseline` |
| `distro_sudoers_pkg_line <user>` | `agent ALL=(ALL) NOPASSWD: /usr/bin/dnf` | `…: /usr/bin/apt-get, /usr/bin/apt` | the NOPASSWD-for-pkg fixture (REUSE-01 narrow-grant case) |
| `distro_ssh_unit` | `sshd` | `ssh` | `invoke_modes.bash`/`20`/`50` setup `systemctl start <unit>` |
| `distro_restore_ssh_context <dir>` | guarded `command -v restorecon && restorecon -R -F "$dir" \|\| true` | `:` (no-op) | the two SSH-seeding sites (EL-06) |

**Dispatch pattern (container-side, no product libs required):**
```bash
# tests/bats/helpers/distro.bash — sourced via `load 'helpers/distro'`. No set -euo (sourced).
distro_family() {
  [[ -n "${_AGENTLINUX_TEST_FAMILY:-}" ]] && { printf '%s' "$_AGENTLINUX_TEST_FAMILY"; return 0; }
  local id=""; [[ -r /etc/os-release ]] && id=$(. /etc/os-release; printf '%s' "${ID:-}")
  case "$id" in almalinux) _AGENTLINUX_TEST_FAMILY=rhel ;; *) _AGENTLINUX_TEST_FAMILY=debian ;; esac
  printf '%s' "$_AGENTLINUX_TEST_FAMILY"
}
```
**Ubuntu-preservation guarantee:** every verb's `debian` arm is the *current* hardcoded line lifted byte-for-byte from `brownfield.bash`/`invoke_modes.bash`, so the Ubuntu rows execute the identical commands — only the `case` selector is new. Add a CI grep guard: `grep -rn 'apt-get\|dpkg-query\|deb.nodesource\|/etc/default/locale\|systemctl start ssh\b' tests/bats/*.bats tests/bats/helpers/*.bash` should only match inside the `debian` arm of `distro.bash` after the refactor.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Family detection inside tests | A second `case "$ID"` per test file | one `distro_family` verb in `distro.bash` | 1 fork point; mirrors `pkg.sh`; auditable by the grep guard |
| NodeSource repo path knowledge in tests | Re-hardcode yum/apt paths in `brownfield.bash` | the product `nodesource_repo_paths` verb (already family-correct) where a lib is sourced, else `distro_nodesource_repo_paths` | the product verb is the single source of truth (18-RESEARCH); duplicating it re-introduces drift |
| Making `/tmp` exec-able per test | `chmod`/remount inside each `setup()` | `--tmpfs /tmp:exec` in `run.sh` (one line) | one substrate fix flips all stub-exec tests on every row; per-test remounts need privilege + race-prone |
| restorecon presence | assume it exists on EL9 | guard `command -v restorecon` | `policycoreutils` is not in the image; an unguarded call aborts the installer/harness |
| TTY prompt waiting | longer manual sleeps | a bounded pexpect timeout in `tty-driver.py` | the EL9 hang is an unbounded wait; a timeout converts a 13-min hang into a fast, diagnosable failure |

**Key insight:** roughly two-thirds of the RED on EL9 is **substrate + tmpfs**, not assertion logic. Fixing the image/`run.sh` first (Wave 1) collapses the apparent PAR-01 surface to the genuine `brownfield.bash` + BHV-01/INST-02 generalization, which is a far smaller, well-bounded edit set.

## Runtime State Inventory

This phase edits tests + the test Dockerfile + (guarded) restorecon calls. It writes no new persistent product state. Divergences a planner must track:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — bats fixtures are ephemeral per container | None |
| Live service config | `sshd` unit name differs (EL9 `sshd.service`; Ubuntu `ssh.service`); the image already `enable`s `sshd` so it auto-starts | `systemctl start ssh`→`distro_ssh_unit` in 3 setup sites |
| OS-registered state | SELinux file contexts on `~agent/.ssh` — only meaningful under a real SELinux kernel (Phase 22 QEMU); a no-op on Docker | guarded `restorecon` at the 2 SSH-seeding sites |
| Secrets/env vars | Ephemeral per-container SSH keypair (`/root/.ssh/id_ed25519`, `~agent/.ssh/authorized_keys`) — never committed; seeded in `20-agent-user.bats` setup + re-seeded in `50-agents.bats` setup_file | restorecon must follow both seed sites |
| Build artifacts | `Dockerfile.almalinux-9` adds `diffutils`/`openssh-clients`/`iproute`/`policycoreutils` → image rebuild; `run.sh` tmpfs flag change | rebuild image; no `plugin/` rebuild |

**Canonical question — after every test is generalized, what still carries the old assumption?** The Docker image itself: missing `diff`/`ssh`/`ss`/`restorecon` and `noexec /tmp` are runtime substrate that no amount of assertion editing fixes. These MUST be Wave-1 tasks or the helper work will appear not to converge.

## Common Pitfalls

### Pitfall 1: "Fixing" the PATH stubs in 18-pkg-dispatch / 18-detect-el9
**What goes wrong:** chasing the Phase-19 "real dnf/rpm shadows the stubs" or "`$(id -un)`=root" theories and rewriting the stub harness.
**Why it happens:** the RED looks like a dispatch bug.
**How to avoid:** both files are byte-for-byte correct — they go 20/20 and 7/7 green with stubs **untouched** the instant `/tmp` is exec-able. Fix the tmpfs, not the stubs. Verify with `TMPDIR=/var/tmp/bt bats tests/bats/18-pkg-dispatch.bats` before editing anything.
**Warning signs:** a stub test passing on the dev host but failing only inside Docker = a `noexec`/exec-mount difference, not a logic bug.

### Pitfall 2: Trusting per-file isolated RED counts
**What goes wrong:** `--purge`/`userdel -r` in earlier-sorted files corrupt the post-install state, so a later isolated file shows false-RED (CLAUDE.md "missing", npm-prefix "wrong-owner").
**How to avoid:** always validate with the **full suite in filename order** via `run.sh almalinux-9`. Treat per-file runs as debugging only.
**Warning signs:** `/home/agent` reset to skel, `/opt/agentlinux` absent, re-run installer bails `npm-prefix wrong-owner` — these are teardown artifacts, not EL9 product bugs.

### Pitfall 3: Unguarded restorecon aborts the harness
**What goes wrong:** `restorecon -R -F ~agent/.ssh` with `set -e`/ERR-trap on an image lacking `policycoreutils` → `restorecon: command not found` → test/installer aborts.
**How to avoid:** `command -v restorecon >/dev/null && restorecon -R -F /home/agent/.ssh || true`. (Optionally add `policycoreutils` to the image.)

### Pitfall 4: Weakening instead of generalizing
**What goes wrong:** `skip` on EL9 for `/etc/default/locale`, or asserting only `locale -a`.
**How to avoid:** assert the **same observable** at the family-correct path (`/etc/locale.conf` on rhel) via `distro_assert_locale`. The locked decision forbids `skip`.

### Pitfall 5: Breaking the Ubuntu rows
**What goes wrong:** editing a shared assertion's debian path while generalizing.
**How to avoid:** the `debian` arm of every `distro.bash` verb is the current line verbatim; run `run.sh ubuntu-24.04` after each wave. The grep guard catches a stray apt/dpkg/`/etc/default/locale` outside the debian arm.

## Code Examples (verified live this session)

### Exec-able tmpdir flips the stub tests green (Wave 1 proof)
```bash
# Inside the booted almalinux:9 container, stubs UNCHANGED:
TMPDIR=/var/tmp/bt bats --tap tests/bats/18-pkg-dispatch.bats   # → 20/20 ok
TMPDIR=/var/tmp/bt bats --tap tests/bats/18-detect-el9.bats     # → 7/7 ok
# Default (/tmp noexec): 14/20 and 3/7 RED. /var/tmp is overlay (exec); /tmp is `rw,nosuid,nodev,noexec`.
```
Single-point fix in `tests/docker/run.sh` (line ~118) — the most faithful (tests still run under `/tmp`):
```bash
  --tmpfs /run --tmpfs /tmp:exec \
```
(Equivalent: `docker exec ... bash -c 'cd /opt/agentlinux-src && TMPDIR=/var/tmp bats tests/bats/'`.)

### Non-interactive SSH propagates correctly once openssh-clients is present
```bash
# After `dnf install -y openssh-clients` in the EL9 container:
ssh -i /root/.ssh/id_ed25519 agent@localhost 'echo PATH=$PATH; command -v node; echo LANG=$LANG'
# PATH=/home/agent/.local/bin:/home/agent/bin:/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:...
# /usr/bin/node
# LANG=C.UTF-8
# → no product/profile-wiring defect; BHV-02 RED is purely the missing client package.
```

### Generalized brownfield Node fixture (replaces brownfield.bash:139-141)
```bash
# distro.bash verb the fixture calls instead of the hardcoded dpkg/apt block:
distro_install_node22() {
  case "$(distro_family)" in
    rhel)
      command -v node >/dev/null && rpm -q nodejs >/dev/null 2>&1 && return 0
      curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
      dnf -y module reset nodejs >/dev/null 2>&1 || true
      dnf install -y nodejs >/dev/null 2>&1 ;;
    debian)
      dpkg-query -W -f='${Status}' nodejs 2>/dev/null | grep -q 'install ok installed' && return 0
      curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
      DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs >/dev/null 2>&1 ;;
  esac
}
```

## State of the Art

| Old (Phase-19 attribution) | Corrected (this session, verified) | Impact |
|----------------------------|-------------------------------------|--------|
| 18-pkg-dispatch/18-detect-el9 RED = harness hermeticity, "root-cause each" | RED = `noexec /tmp` (Docker `--tmpfs` default) + bash exec-fallthrough; both green with stubs intact | One `run.sh` tmpfs flag, not a stub rewrite |
| BHV-02/SSH RED = possibly SELinux/restorecon | RED = `openssh-clients` package absent in image | Add one package; restorecon is a no-op on Docker |
| Most RED = Ubuntu-path assertions to generalize | ~2/3 of RED = substrate (`diffutils`/`openssh-clients`/`iproute` + tmpfs); ~1/3 = genuine helper-gen (`brownfield.bash`, BHV-01, INST-02) | Substrate-first sequencing collapses the apparent PAR-01 surface |
| EL-06 enforcing-SELinux proven on Docker | Enforcing SELinux structurally impossible on Docker/CI (AppArmor kernel) | EL-06 Docker = restorecon-code + six-modes; enforcement proof is Phase 22 |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `40-registry-cli`/`50`/`51`/`52` RED is dominated by the same `openssh-clients`+`diffutils` substrate gaps (not reached in the full run before the TTY hang) | Per-File Map | LOW — re-run after Wave 1; any residue is a small named set, not a new class |
| A2 | DET-03 #111 (`effective_prefix`/`NPM_CONFIG_PREFIX` via `as_user_login`) is a fixture/assertion detail, not a product login-shell defect | 15-detection row, Open Q | MEDIUM — if `as_user_login` mis-exports on EL9 it's a `plugin/lib/as_user.sh` product fix; spike early |
| A3 | The 15-preflight-ux TTY hang resolves once `brownfield.bash` fixtures build correct EL9 state (installer then reaches the expected prompt) | 15-preflight-ux row | MEDIUM — may also need a `tty-driver.py` pexpect timeout regardless; add the timeout defensively |
| A4 | `policycoreutils` need not be installed if the restorecon call is guarded (Docker no-op) | SELinux Verdict, Pitfall 3 | LOW — installing it additionally is cheap and exercises the real binary path |
| A5 | `--tmpfs /tmp:exec` does not perturb the systemd-in-Docker recipe (PID-1 systemd still boots) | Wave 1 | LOW — exec on /tmp is the normal default outside Docker; verify the boot still reaches `running`/`degraded` |

## Open Questions

1. **DET-03 #111 — does `as_user_login` export `NPM_CONFIG_PREFIX` on EL9?**
   - Known: login-shell PATH + LANG propagate correctly on EL9 (proven via SSH and the passing 22-agent-sudo modes).
   - Unclear: whether the specific `effective_prefix` value the test reads reflects the user-shell export on EL9, or whether the test fixture assumed a Debian login-shell file.
   - Recommendation: early Wave-2 spike — run the DET-03 probe under `sudo -u agent -i` on EL9; if `NPM_CONFIG_PREFIX` is correct, it's an assertion/fixture fix; if not, it's an `as_user.sh` product fix (escalate).

2. **15-preflight-ux TTY hang — fixture-only or tty-driver?**
   - Known: a `tty-driver.py`/pexpect test blocked ~13 min on EL9 at test ~138.
   - Recommendation: add a bounded pexpect timeout to `tty-driver.py` (converts hang→fast failure), then fix the underlying brownfield fixture; re-run `15-preflight-ux` in isolation on a clean container.

3. **`40-registry-cli` snapshot diffs** — confirm they use `diff` (substrate) vs a Debian path; re-run after Wave 1.

## Environment Availability (EL9 Docker image — substrate audit)

Probed live in the booted `almalinux:9` test container (post-install):

| Dependency | Required by | Present | Fix |
|------------|-------------|---------|-----|
| exec-able `/tmp` | every PATH-stub test (18-pkg-dispatch, 18-detect-el9, parts of 13/14/60) | ✗ (`--tmpfs /tmp` = `noexec`) | `--tmpfs /tmp:exec` in `run.sh` |
| `diff` (`diffutils`) | NO-MUTATION snapshots, INST-02, DET-read-only, UX-01/03, REMEDIATE-02, 40-registry-cli | ✗ MISSING | `dnf install diffutils` in Dockerfile |
| `ssh` (`openssh-clients`) | BHV-02 + every six-mode SSH assertion (30/40/50/51) | ✗ MISSING (only `openssh-server`) | `dnf install openssh-clients` in Dockerfile |
| `ss` (`iproute`) | sshd readiness poll in setup() | ✗ MISSING | `dnf install iproute` (non-fatal; image auto-starts sshd) |
| `restorecon` (`policycoreutils`) | EL-06 restorecon call | ✗ MISSING | guard the call; optionally add `policycoreutils` |
| `dnf`/`rpm`/`curl`/`jq`/`python3`/`file`/`node`/`sudo`/`bats`/`sshd` | suite + installer | ✓ | none (Phase 19) |
| enforcing SELinux | EL-06 enforcement proof | ✗ structurally (AppArmor kernel) | **Phase 22 QEMU** — not achievable on Docker |

**Missing with no Docker fallback:** enforcing SELinux → deferred to Phase 22 (per EL-06 note). **Missing with substrate fix:** `diff`/`ssh`/`ss`/`restorecon` → all Dockerfile one-liners.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bats (EPEL `bats-1.8.0-1.el9`) — the behavior contract per CLAUDE.md |
| Config file | none — driven by `tests/docker/run.sh <target>` inside the matrixed image |
| Quick run command | `bash tests/docker/run.sh almalinux-9` (full suite in order — authoritative) |
| Per-file debug | `docker exec <cid> bash -c 'cd /opt/agentlinux-src && TMPDIR=/var/tmp/bt bats --tap tests/bats/<file>.bats'` (note exec-able TMPDIR) |
| Ubuntu regression | `bash tests/docker/run.sh ubuntu-22.04 && … 24.04 && … 26.04` (must stay byte-equivalent green) |

### Phase Requirements → Test Map
| Req | Behavior | Test Type | Automated command | Exists? |
|-----|----------|-----------|-------------------|---------|
| PAR-01 | full contract green on almalinux-9 | integration (Docker) | `bash tests/docker/run.sh almalinux-9` (exit 0) | ✅ rows exist; ❌ green (this phase) |
| EL-06 | six modes green + guarded restorecon at seed sites | integration | `20-agent-user.bats` BHV-02..06 + `30-runtime` modes on `almalinux-9`; grep restorecon at seed sites | ⚠️ needs `openssh-clients` + restorecon code |
| EL-08 | brownfield Reuse/Create/Remediate/Bail + `--dry-run` non-mutating + exit 64/65/1/0 | integration | `13-reuse` / `14-remediate` / `15-preflight-ux` on `almalinux-9` via generalized `brownfield.bash` | ⚠️ helper-gen this phase |
| EL-06 (enforce) | enforcing-SELinux six modes | integration (QEMU) | Phase 22 `run` against AlmaLinux-9 cloud image | ❌ Phase 22 (not Docker) |

### Sampling Rate
- **Per task commit:** the touched file under exec TMPDIR + `pre-commit run --all-files` (shellcheck) + `grep` guard for stray apt/dpkg/locale outside the debian arm.
- **Per wave merge:** `run.sh almalinux-9` (full, in order) **and** `run.sh ubuntu-24.04` (no regression).
- **Phase gate:** `run.sh almalinux-9` exits 0 (full contract green) + all three Ubuntu rows green + TST-07 behavior-coverage-auditor.

### Wave 0 Gaps
- [ ] `tests/bats/helpers/distro.bash` — NEW (family detect + the verbs in §Helper Design); covers PAR-01/EL-06/EL-08 generalization.
- [ ] `Dockerfile.almalinux-9` — add `diffutils openssh-clients iproute policycoreutils` to the dnf set.
- [ ] `tests/docker/run.sh` — `--tmpfs /tmp:exec`.
- [ ] `tty-driver.py` — bounded pexpect timeout (defensive; turns the EL9 hang into a fast failure).
- *(No new framework install — bats is already in the image.)*

## Security Domain

`security_enforcement` not disabled in config → included. This is a test-conformance phase (no new attack surface; no auth/crypto code added).

| ASVS Category | Applies | Standard control |
|---------------|---------|------------------|
| V2 Authentication | yes (indirect) | EL-06 non-interactive SSH uses pubkey auth; restorecon ensures confined `sshd_t` can read `authorized_keys` under real SELinux (Phase 22). Ephemeral per-container keypair, never committed. |
| V5 Input Validation | no | no new input surfaces |
| V6 Cryptography | no | no crypto added; NodeSource GPG verification unchanged (Phase 18) |
| V14 Config | yes | sudoers drop-in `0440 root:root` validated via `visudo` (22-agent-sudo green on EL9); SELinux stays **enforcing** — `setenforce 0` rejected |

| Threat | STRIDE | Mitigation |
|--------|--------|------------|
| Disabling SELinux to pass a test | Tampering/Repudiation | locked-rejected; restorecon (guarded) is the only sanctioned fix |
| Committed SSH keypair | Information Disclosure | keys generated per-container in `setup()`, never reach repo (existing design) |
| Broad sudoers via brownfield fixture | Elevation | fixtures install `0440` visudo-gated grants; NOPASSWD-for-pkg fixture is the narrow `/usr/bin/dnf` (rhel) / `/usr/bin/apt-get` (debian) grant only |

## Sources

### Primary (HIGH — reproduced live this session, 2026-06-28)
- Booted `almalinux:9` container (`tests/docker/Dockerfile.almalinux-9`): `getenforce`/`/sys/fs/selinux`/`/proc/filesystems` (no SELinux); `findmnt /tmp` (`noexec`); `18-pkg-dispatch` 14→0 + `18-detect-el9` 3→0 with exec TMPDIR; full-suite-in-order TAP (tests 1-137); targeted runs of `20-agent-user`/`22-agent-sudo`/`30-runtime`/`60-curl-installer`; live `dnf install openssh-clients` + SSH PATH/LANG probe; substrate tool audit (`diff`/`ssh`/`ss`/`restorecon` MISSING).
- Repo code at file:line — `tests/bats/18-pkg-dispatch.bats` (stub setup :50-92), `18-detect-el9.bats` (:49-93,186-214), `10-installer.bats` (INST-02 find :71-81), `helpers/brownfield.bash` (:74-90,131-154), `helpers/invoke_modes.bash` (:42-49 run_ssh), `20-agent-user.bats` (setup :28-44, BHV-01 :59-67), `50-agents.bats` (setup_file :41-64), `plugin/lib/pkg.sh`, `plugin/lib/detect/user.sh` (:52-61 probe branch).

### Secondary (HIGH)
- `.planning/REQUIREMENTS.md` (EL-06/EL-08/PAR-01, EL-06 Phase-20/22 note), `20-CONTEXT.md`, `18-RESEARCH.md`, `19-01-SUMMARY.md`.

## Metadata

**Confidence breakdown:**
- Substrate root causes (noexec /tmp, missing diff/ssh/ss, SELinux unavailability): **HIGH** — each reproduced and the fix verified live.
- Helper-generalization scope (`brownfield.bash`, BHV-01, INST-02, REUSE-01 family token): **HIGH** — failure mechanism read at file:line and confirmed in the live RED.
- Back-half files 40/50/51/52 exact counts: **MEDIUM** — not reached before the TTY hang; re-run after Wave 1 (A1).
- DET-03 product-vs-test, TTY-hang cause: **MEDIUM** — spikes recommended (A2/A3).

**Research date:** 2026-06-28
**Valid until:** ~2026-07-28 (stable; EL9 image + Docker tmpfs defaults are slow-moving). Re-run the full suite after the Wave-1 substrate fixes to lock the residual RED set.
