---
phase: 20
slug: behavior-test-green-on-almalinux-9
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-28
---

# Phase 20 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats (EPEL `bats-1.8.0-1.el9`) — the behavior contract per CLAUDE.md |
| **Substrate** | Docker matrix via `tests/docker/run.sh <target>` (the `almalinux-9` row is the Phase-20 gate; `ubuntu-24.04` is the no-regression row) |
| **Config file** | none — driven by `tests/docker/run.sh` inside the matrixed image |
| **Quick run command** | targeted single-file bats inside the container under an exec-able TMPDIR: `docker exec <cid> bash -c 'cd /opt/agentlinux-src && TMPDIR=/var/tmp/bt bats --tap tests/bats/<file>.bats'` |
| **Full suite command** | `bash tests/docker/run.sh almalinux-9` (full suite in filename order — authoritative) |
| **No-regression command** | `bash tests/docker/run.sh ubuntu-24.04` (must stay byte-equivalent green) |
| **Estimated runtime** | ~minutes per suite cycle (full `run.sh` per row); seconds for a targeted single-file run |

---

## Sampling Rate

- **After every task commit:** Run the task's `<automated>` command (below) — `bash -n`/`ast.parse` + grep on the touched file, plus the per-file targeted bats under exec TMPDIR where applicable.
- **After every plan wave:** Run `bash tests/docker/run.sh almalinux-9` (full, in order) **and** `bash tests/docker/run.sh ubuntu-24.04` (no regression).
- **Authoritative gate:** the full suite **in filename order** via `run.sh almalinux-9` — per-file isolation over-reports RED (destructive `--purge`/`userdel -r` in earlier files corrupt shared post-install state; see RESEARCH §Methodology). Per-file runs are debugging only.
- **Before `/gsd-verify-work`:** `run.sh almalinux-9` exits 0 (full contract green) + all Ubuntu rows green.
- **Max feedback latency:** ~minutes (one full-suite cycle per row).

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 20-01-01 | 01 | 1 | PAR-01 / EL-06 / EL-08 | T-20-02 | Stock AlmaLinux/EPEL pkgs only; no new privilege path | static (grep) + integration | `grep -c 'diffutils' tests/docker/Dockerfile.almalinux-9 \| grep -qv '^0$' && grep -q 'openssh-clients' tests/docker/Dockerfile.almalinux-9 && grep -q 'iproute' tests/docker/Dockerfile.almalinux-9 && echo OK` | ✅ | ⬜ pending |
| 20-01-02 | 01 | 1 | PAR-01 | T-20-01 / T-20-03 | systemd-in-Docker still boots running/degraded after tmpfs change | static (grep) + integration | `grep -q -- '--tmpfs /tmp:exec' tests/docker/run.sh && ! grep -qE -- '--tmpfs /tmp( \|$)' tests/docker/run.sh && echo OK` | ✅ | ⬜ pending |
| 20-02-01 | 02 | 2 | PAR-01 / EL-08 | T-20-06 | `distro_family` matches `ID=almalinux` exactly (mirrors product `detect_distro`) | unit (bash -n + verb presence) | `bash -n tests/bats/helpers/distro.bash && for v in distro_family distro_locale_file distro_assert_locale distro_nodesource_repo_paths distro_pkg_is_installed distro_install_node22 distro_sudoers_pkg_line distro_ssh_unit distro_restore_ssh_context; do grep -q "^${v}()" tests/bats/helpers/distro.bash \|\| { echo "MISSING $v"; exit 1; }; done && ! grep -qE '^set -euo' tests/bats/helpers/distro.bash && echo OK` | ❌ W0 | ⬜ pending |
| 20-02-02 | 02 | 2 | PAR-01 / EL-08 | T-20-04 / T-20-05 | Narrow per-family NOPASSWD grant; grep guard pins apt/dpkg strings to debian arm | unit (bash -n + grep guard) | `bash -n tests/bats/helpers/brownfield.bash && grep -q 'distro_install_node22' tests/bats/helpers/brownfield.bash && ! grep -qE 'apt-get\|dpkg-query\|deb\.nodesource' tests/bats/helpers/brownfield.bash && echo OK` | ✅ | ⬜ pending |
| 20-03-01 | 03 | 3 | EL-06 / PAR-01 | — | Locale observable asserted at family path; no skip/weaken | integration (bats) | `bash -n tests/bats/20-agent-user.bats && grep -q "load 'helpers/distro'" tests/bats/20-agent-user.bats && grep -q 'distro_assert_locale' tests/bats/20-agent-user.bats && grep -q 'distro_ssh_unit' tests/bats/20-agent-user.bats && ! grep -qE '/etc/default/locale\|systemctl start ssh\b' tests/bats/20-agent-user.bats && echo OK` | ✅ | ⬜ pending |
| 20-03-02 | 03 | 3 | EL-06 / PAR-01 | T-20-07 / T-20-09 | Guarded restorecon (no unguarded abort); SELinux never disabled | integration (bats) | `bash -n tests/bats/50-agents.bats && grep -c 'distro_restore_ssh_context /home/agent/.ssh' tests/bats/20-agent-user.bats tests/bats/50-agents.bats && grep -q "load 'helpers/distro'" tests/bats/50-agents.bats && ! grep -rqE 'setenforce\|SELINUX=disabled' tests/bats/ tests/docker/ && echo OK` | ✅ | ⬜ pending |
| 20-04-01 | 04 | 3 | EL-08 / PAR-01 | T-20-10 | Both pre/post snapshots use the same family-correct path (symmetric) | integration (bats) | `bash -n tests/bats/10-installer.bats && grep -q "load 'helpers/distro'" tests/bats/10-installer.bats && grep -q 'nodesource_repo_paths' tests/bats/10-installer.bats && ! grep -q '/etc/apt/sources.list.d/nodesource.sources' tests/bats/10-installer.bats && echo OK` | ✅ | ⬜ pending |
| 20-04-02 | 04 | 3 | EL-08 / PAR-01 | T-20-11 | Family token from product `detect_distro` (not a test literal) | integration (bats) | `bash -n tests/bats/13-reuse.bats && grep -q 'detect_distro' tests/bats/13-reuse.bats && echo OK` | ✅ | ⬜ pending |
| 20-05-01 | 05 | 3 | EL-08 / PAR-01 | T-20-12 | Spike-first; product defect escalated with evidence, never papered over | integration (bats) + spike | `bash -n tests/bats/15-detection.bats && echo OK` | ✅ | ⬜ pending |
| 20-05-02 | 05 | 3 | EL-08 / PAR-01 | T-20-13 | Bounded pexpect `timeout=` converts hang → fast non-zero failure | unit (ast.parse + grep) | `python3 -c "import ast,sys; ast.parse(open('tests/bats/helpers/tty-driver.py').read())" && grep -q 'timeout' tests/bats/helpers/tty-driver.py && echo OK` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*Note: the per-task grep/`bash -n` commands are fast gates proving the edit landed; the authoritative behavior signal for every task is the suite-level proof in each task's acceptance criteria, run via `bash tests/docker/run.sh almalinux-9` (full suite in filename order) per the Sampling Rate above.*

---

## Wave 0 Requirements

- [ ] `tests/bats/helpers/distro.bash` — NEW family-dispatch helper (created in Plan 20-02 Task 1; the 9-verb contract all Wave-3 plans consume). This is the only net-new test file; every other touched file already exists.

*All other phase requirements are covered by the existing bats suite + Docker harness — no framework install (bats is already in the `almalinux-9` image).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Enforcing-SELinux six-mode SSH proof | EL-06 (enforce) | Enforcing SELinux is structurally unavailable on the Docker row (AppArmor host kernel, no `selinuxfs`); cannot be reproduced in Docker | Deferred to **Phase 22 QEMU** (`run` against a fresh AlmaLinux-9 cloud image with real kernel SELinux). Phase 20 lands the guarded restorecon CODE + six modes green on Docker; Phase 22 owns the enforcement re-confirmation. No double-counting. |

*All other phase behaviors have automated verification via the bats suite on the `almalinux-9` Docker row.*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (`distro.bash` created in Plan 20-02 Task 1)
- [x] No watch-mode flags
- [x] Feedback latency ~minutes per suite cycle (acceptable for a Docker-matrix conformance phase)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
