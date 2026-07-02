---
phase: 20-behavior-test-green-on-almalinux-9
plan: 03
subsystem: testing
tags: [bats, almalinux, el9, distro-dispatch, selinux, restorecon, ssh, locale, bhv-01, el-06, par-01]

# Dependency graph
requires:
  - phase: 20-01
    provides: EL9 substrate (openssh-clients + iproute + exec-able /tmp) so the six invocation modes (incl non-interactive SSH) and the ss readiness poll run on the EL9 Docker row
  - phase: 20-02
    provides: tests/bats/helpers/distro.bash verbs — distro_assert_locale, distro_locale_file, distro_ssh_unit, distro_restore_ssh_context (the Wave-3 SSH/locale fork points, interface-first)
provides:
  - "20-agent-user.bats BHV-01 locale asserts route through distro_assert_locale — same observable (LANG/LC_ALL=C.UTF-8) at the family-correct path (/etc/locale.conf on EL9, /etc/default/locale on Ubuntu), never skipped/weakened"
  - "Both harness SSH-seed sites (20-agent-user setup, 50-agents setup_file) follow the authorized_keys write with a guarded distro_restore_ssh_context /home/agent/.ssh"
  - "Both setup sites start the family-correct ssh unit via systemctl start \"$(distro_ssh_unit)\" (sshd on EL9, ssh on Ubuntu)"
  - "EL9 verification: 20-agent-user 14/14 + 50-agents 11/11 green (six invocation modes incl non-interactive SSH); Ubuntu stays 257/257"
affects: [20-05 full-suite-in-order EL9 (gated by the Plan-20-05 tty-driver hang), 22-qemu-enforcing-selinux (real restorecon proof under enforcing SELinux)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Generalize-never-weaken: BHV-01 asserts the SAME locale observable at the family-correct path via distro_assert_locale — no skip on EL9, no fallback to a locale-a-only check"
    - "Guarded SELinux relabel: distro_restore_ssh_context follows every harness authorized_keys write; rhel arm is command-v-guarded so it is a clean no-op where restorecon is absent (the Docker row), real under Phase 22 enforcing SELinux; debian arm is `:`"
    - "SELinux stays enforcing: no setenforce/SELINUX=disabled anywhere — even prohibition comments avoid the literal token so the security grep guard stays clean"

key-files:
  created:
    - .planning/phases/20-behavior-test-green-on-almalinux-9/20-03-SUMMARY.md
  modified:
    - tests/bats/20-agent-user.bats
    - tests/bats/50-agents.bats
    - tests/bats/helpers/distro.bash

key-decisions:
  - "BHV-01 @test names renamed from the Debian-only '/etc/default/locale has …' to the observable-named 'system locale file has …' so the test description names the asserted observable, not the family path"
  - "Reworded the three 'NEVER setenforce 0' prohibition comments (incl. the pre-existing distro_restore_ssh_context verb header from Wave 2) off the literal token to 'SELinux enforcement is never disabled' so the plan's own security grep guard (no setenforce/SELINUX=disabled in tests/ plugin/ packaging/) returns zero — Rule 3 blocking fix"
  - "No installer-side restorecon invented: the installer does not seed ~agent/.ssh (keys arrive via cloud-init/external), so both restorecon sites live in the test harness only (RESEARCH §SELinux-in-Docker Verdict)"

requirements-completed: []  # EL-06/PAR-01 are multi-wave phase requirements; Wave 3 lands the six-modes + restorecon + BHV-01 locale half. Full PAR-01 green-suite-in-order closure is still gated by the Plan-20-05 tty-driver hang; the real enforcing-SELinux EL-06 proof is Phase 22 QEMU.

# Metrics
duration: 55min
completed: 2026-06-28
---

# Phase 20 Plan 03: Wave 3 — Six-Mode SSH + Guarded restorecon + BHV-01 Locale Summary

**The BHV-01 locale asserts route through `distro_assert_locale` (same LANG/LC_ALL=C.UTF-8 observable at `/etc/locale.conf` on EL9, `/etc/default/locale` on Ubuntu — never skipped), both harness SSH-seed sites gain a guarded `distro_restore_ssh_context` after the key write and start the family-correct ssh unit (`sshd`/`ssh`), and on EL9 all six invocation modes go green: 20-agent-user 14/14 + 50-agents 11/11, with Ubuntu held at 257/257.**

## Performance

- **Duration:** ~55 min (dominated by EL9 + Ubuntu Docker boot/install/bats cycles — minutes each)
- **Started:** 2026-06-28T19:50:17Z
- **Tasks:** 2
- **Files modified:** 3 (2 in plan scope + 1 Rule-3 comment reword in distro.bash)

## Accomplishments

- **BHV-01 locale generalized (Task 1).** The two BHV-01 locale `@test`s in `20-agent-user.bats` now call `distro_assert_locale LANG` / `distro_assert_locale LC_ALL`, which greps `^LANG=C.UTF-8` / `^LC_ALL=C.UTF-8` at the family-correct path (`/etc/locale.conf` on EL9, `/etc/default/locale` on Ubuntu). Same observable, two paths, **no skip and no weakening** to a `locale -a`-only check. The portable `locale -a` test was left untouched. The `@test` names were updated from the Debian-only path to the observable ("system locale file has …").
- **Family-correct ssh unit at both setup sites.** `systemctl start ssh` → `systemctl start "$(distro_ssh_unit)"` in both `20-agent-user.bats` `setup()` and `50-agents.bats` `setup_file()` (EL9 unit = `sshd`, Ubuntu = `ssh`). `50-agents.bats` gained `load 'helpers/distro'`.
- **Guarded restorecon at BOTH harness SSH-seed sites (Task 2).** `distro_restore_ssh_context /home/agent/.ssh` is inserted immediately after the `authorized_keys` write and before the ssh-unit start in both `20-agent-user.bats` `setup()` and `50-agents.bats` `setup_file()`. The verb's rhel arm is `command -v restorecon`-guarded so it is a **clean no-op where restorecon is absent** (the Docker image) and the real relabel under Phase 22 enforcing SELinux; the debian arm is `:`.
- **SELinux never disabled.** No `setenforce` / `SELINUX=disabled` anywhere in `tests/ plugin/ packaging/` (grep-verified zero). The three prohibition comments were reworded off the literal token so the security grep guard stays clean.
- **No installer-side restorecon invented.** `grep -rn restorecon plugin/` → zero. Keys arrive via cloud-init/external, so both restorecon sites are harness-only (per RESEARCH §SELinux-in-Docker Verdict).

## Task Commits

1. **Task 1: BHV-01 locale via distro_assert_locale + family ssh unit** — `6b0563a` (feat)
2. **Task 2: guarded restorecon at both SSH-seed sites + family ssh unit (50-agents)** — `4386f23` (feat)

**Plan metadata:** this commit (`docs(20-03): complete Wave 3 …`).

## Files Created/Modified

- `tests/bats/20-agent-user.bats` — `load 'helpers/distro'`; two BHV-01 locale `@test`s → `distro_assert_locale LANG`/`LC_ALL` (renamed to name the observable); `setup()` starts `"$(distro_ssh_unit)"` and runs `distro_restore_ssh_context /home/agent/.ssh` after the key write; header precondition comment generalized off the Debian-only locale path.
- `tests/bats/50-agents.bats` — `load 'helpers/distro'`; `setup_file()` re-seed site runs `distro_restore_ssh_context /home/agent/.ssh` after the key write and starts `"$(distro_ssh_unit)"`.
- `tests/bats/helpers/distro.bash` — comment-only reword of the `distro_restore_ssh_context` verb header ("NEVER `setenforce 0`" → "SELinux enforcement is never disabled …") so the plan's security grep guard returns zero. No behavior change.

## Verification Evidence

### EL9 — targeted runs (booted `almalinux:9`, installer exit 0, exec-able /tmp)

Methodology: the authoritative full-suite-in-order EL9 run is still blocked by the Plan-20-05-owned `tty-driver.py` pexpect hang at `15-preflight-ux` (documented in 20-02-SUMMARY, file 15 sorts before 20/50). Per RESEARCH §Methodology, I verified my changed files via targeted runs in a fresh container after `agentlinux-install` — running them in filename order (`20-agent-user` first, so its `setup()` seeds the SSH keypair the later SSH modes need), exactly the methodology Wave 2 used.

Environment sanity inside the EL9 container (proves the guard is exercised, not skipped):
- `restorecon: ABSENT` → `distro_restore_ssh_context` takes the guarded no-op path; the harness does **not** abort (RESEARCH §Pitfall 3 avoided).
- `ssh client: PRESENT` (Wave 1 `openssh-clients`); `getenforce: absent` → no enforcing SELinux on the Docker row (RESEARCH §SELinux-in-Docker Verdict — AppArmor host kernel).

| File | EL9 result | Notes |
|------|-----------|-------|
| `20-agent-user.bats` | **14/14 green** | BHV-01 LANG (test 2) + LC_ALL (test 3) green at `/etc/locale.conf` via `distro_assert_locale`; BHV-02 non-interactive SSH (tests 5-6) green; BHV-03 cron, BHV-04 systemd User=agent, BHV-05 sudo -u agent[/-i], BHV-06 interactive login all green — **all six invocation modes**. |
| `30-runtime.bats` | RT-01/RT-02/RT-04 green incl SSH mode; RT-03 green | First run (correct order, after 20-agent-user seeds SSH): RT-01 node-v22-every-mode, RT-04 npm-prefix-every-mode, RT-02 cowsay green (tests 1-4); RT-03 (test 5) hit my 300s targeted budget. Isolated re-run with a 600s budget: **RT-03 green** — confirming the exit-124 was budget, not a hang. |
| `50-agents.bats` | **11/11 green** | AGT-01 six-mode loops (incl SSH) green for claude-code/gsd/playwright-cli; AGT-02b/02c, AGT-03, AGT-04 (+skills), AGT-05 (+skills, idempotency) green. `setup_file` re-seed + guarded restorecon worked. |

### Ubuntu no-regression

- `bash tests/docker/run.sh ubuntu-24.04` → **257/257 green, 0 failures, `== PASS ==`**. Debian arms are byte-equivalent (the `distro_*` debian arms are the prior hardcoded lines); only the `case` selector is new. Ubuntu also sailed through the `15-preflight-ux` TTY tests (133-139) without hanging, confirming the EL9 hang is family-specific (Plan 20-05's `tty-driver.py` issue on EL9 brownfield fixtures), not an Ubuntu problem.

### Static guards

- `grep -c 'distro_restore_ssh_context /home/agent/.ssh'` → **1** in each of `20-agent-user.bats` and `50-agents.bats`.
- `load 'helpers/distro'` present in both files; `distro_ssh_unit` used in both; **no** bare `/etc/default/locale` or `systemctl start ssh` remaining.
- `grep -rE 'setenforce|SELINUX=disabled' tests/ plugin/ packaging/` → **zero**.
- `grep -rn restorecon plugin/` → **zero** (no installer-side restorecon).
- `bats --count` parses both files (20-agent-user: 14, 50-agents: 11). (`bash -n` is not a valid syntax check for `.bats` files — bats `@test` blocks are not POSIX-sh; the original files fail `bash -n` identically.)

## Post-Wave-3a EL9 Inventory

Wave 3 (this plan) cleared the six-mode-SSH + BHV-01-locale + restorecon bucket on EL9. Remaining EL9 residue, all owned by later plans:

| Residual | File | Owner | Note |
|----------|------|-------|------|
| `15-preflight-ux` `tty-driver.py` hang (test 13+) | `tty-driver.py` | Plan 20-05 | bounded pexpect timeout — the gating item for the authoritative full-suite-in-order EL9 run (and therefore final PAR-01 green-suite closure) |
| DET-03 npm-prefix probe | `15-detection.bats` | Plan 20-05 | spike: assertion/fixture fix vs `as_user.sh` escalation |
| REUSE-01 `can_sudo_apt=false` | `13-reuse.bats` | Plan 20-04/05 | seed `AGENTLINUX_DISTRO_FAMILY` so the product probe picks the rhel `/usr/bin/dnf` arm |
| INST-02 idempotency snapshot | `10-installer.bats` | Plan 20-03/04 residue | swap literal nodesource path for `distro_nodesource_repo_paths` (verb ready) — NOTE: not in *this* plan's file scope (20-agent-user/50-agents); tracked for the 10-installer assertion plan |
| Enforcing-SELinux six-modes proof | QEMU | Phase 22 | the genuine restorecon-under-real-SELinux confirmation; Docker is structurally unable to enforce (no double-counting) |

## SELinux-on-Docker / Phase-22 split (documented per plan)

Enforcing SELinux is **structurally unavailable on the Docker row** (the host kernel is Ubuntu/AppArmor; a container shares the host kernel, so no `selinuxfs`/`getenforce`; `policycoreutils`/`restorecon` is absent from the image — RESEARCH §SELinux-in-Docker Verdict, re-confirmed live this plan: `restorecon: ABSENT`, `getenforce: absent`). The `restorecon -R -F ~agent/.ssh` **code lands here** at both harness seed sites as a guarded no-op, and on Docker the six modes go green via Wave-1 `openssh-clients` + `sshd`. The **genuine enforcing-SELinux six-modes proof is Phase 22 QEMU** (real cloud image, real kernel SELinux, stock shadow) — EL-06 maps the restorecon-code + six-modes-on-Docker deliverable to Phase 20 and the enforcement re-confirmation to Phase 22, with no double-counting. `setenforce 0` is never used.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded three "NEVER setenforce 0" prohibition comments off the literal token**
- **Found during:** Task 2 verification (the security grep guard).
- **Issue:** Task 2's acceptance requires `grep -rE 'setenforce|SELINUX=disabled' tests/ plugin/ packaging/` to return nothing. My two new prohibition comments *and the pre-existing `distro_restore_ssh_context` verb header in `distro.bash` (from Wave 2)* contained the literal phrase "NEVER `setenforce 0`", which tripped the guard even though they document the prohibition, not a command.
- **Fix:** Reworded all three comments to "SELinux enforcement is never disabled — the guarded restorecon is the only sanctioned fix." The `distro.bash` edit is comment-only with no behavior change; it was necessary because the guard spans `tests/` which includes that Wave-2 file.
- **Files modified:** `tests/bats/20-agent-user.bats`, `tests/bats/50-agents.bats`, `tests/bats/helpers/distro.bash`.
- **Commit:** `4386f23` (Task 2).

### Non-deviations (per-file-isolation artifacts, not defects)

- The isolated 30-runtime re-run showed `RT-02 (ssh)` failing with "Identity file /root/.ssh/id_ed25519 not accessible". This is the documented RESEARCH §Methodology per-file-isolation artifact: 30-runtime's SSH mode depends on the keypair that `20-agent-user.bats` `setup()` seeds earlier in filename order. In the **correct-order** targeted run (20-agent-user first), RT-01/RT-02/RT-04 SSH modes are all green. Not a defect; no edit made.
- RT-03's initial exit-124 was my 300s targeted-budget limit (three `INVOKE_MODES` loops each include a cron mode that waits up to 70s), not a hang — confirmed green on the 600s re-run.

## Threat Surface

No new shipped product surface — all edits are test-harness-only, confined to the ephemeral (`--rm`) read-only-bind-mounted test container. Threat register dispositions held:
- **T-20-07 (Tampering — disabling SELinux):** locked-rejected; the guarded `restorecon` is the only fix. CI grep asserts no `setenforce`/`SELINUX=disabled` anywhere (verified zero across `tests/ plugin/ packaging/`).
- **T-20-08 (Info Disclosure — committed SSH keypair):** accept; keys generated per-container in `setup`, never reach the repo; the bind mount is `:ro`.
- **T-20-09 (DoS — unguarded restorecon aborts harness):** mitigated; `distro_restore_ssh_context` guards on `command -v restorecon` (verified `restorecon: ABSENT` → clean no-op on the Docker row, no abort).

No plugin/ product code touched; no installer-side restorecon; no `setenforce 0`.

## Next Phase Readiness

- **EL-06 Docker deliverable landed:** all six invocation modes green on EL9 (20-agent-user 14/14, 50-agents 11/11, 30-runtime RT-01/02/04 + RT-03), guarded restorecon at both harness seed sites, BHV-01 locale at the family path. Ubuntu held at 257/257.
- **Full-suite-in-order EL9 remains gated** by the `tty-driver.py` hang at `15-preflight-ux` → **Plan 20-05** bounded-timeout is the gating item for authoritative PAR-01 green-suite verification.
- **Phase 22 QEMU** owns the real enforcing-SELinux six-modes proof (the restorecon relabel under stock `0000` shadow + confined `sshd_t`).

## Self-Check: PASSED

- `tests/bats/20-agent-user.bats` — FOUND (distro_assert_locale, distro_ssh_unit, distro_restore_ssh_context present)
- `tests/bats/50-agents.bats` — FOUND (load distro, distro_ssh_unit, distro_restore_ssh_context present)
- `tests/bats/helpers/distro.bash` — FOUND
- `.planning/phases/20-behavior-test-green-on-almalinux-9/20-03-SUMMARY.md` — FOUND
- commit `6b0563a` (Task 1) — FOUND
- commit `4386f23` (Task 2) — FOUND

---
*Phase: 20-behavior-test-green-on-almalinux-9*
*Completed: 2026-06-28*
