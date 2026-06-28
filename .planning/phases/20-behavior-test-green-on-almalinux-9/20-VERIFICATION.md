---
phase: 20-behavior-test-green-on-almalinux-9
verified: 2026-06-28T00:00:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
re_verification: null
gaps: []
deferred:
  - truth: "Six invocation modes pass under enforcing SELinux (real enforcement, not Docker AppArmor)"
    addressed_in: "Phase 22"
    evidence: "Phase 22 goal: QEMU release-gate + pipeline; REQUIREMENTS.md EL-06 note: Phase 22 QEMU row re-confirms under real enforcement on the cloud image"
  - truth: "PAR-01 QEMU half: full bats contract green on the QEMU row"
    addressed_in: "Phase 22"
    evidence: "REQUIREMENTS.md PAR-01: green on AlmaLinux 9 across both Docker (HARN-01) and QEMU (HARN-02) rows; QEMU half owned by Phase 22"
  - truth: "release.yml gate-2 almalinux-9 flipped from experimental to hard gate"
    addressed_in: "Phase 22"
    evidence: "20-07-SUMMARY: 'release.yml gate-2-docker left UNCHANGED (Phase 22 REL-01 owns that flip)'"
human_verification: []
---

# Phase 20: Behavior-Test-Green on AlmaLinux 9 — Verification Report

**Phase Goal:** The full existing behavior contract — BHV / RT / AGT / CLI / CAT / INST (v0.3.0) and DET / REUSE / REMEDIATE / UX (v0.3.4) — is green on the AlmaLinux 9 Docker row under enforcing SELinux, with Ubuntu-path assertions generalized to distro-aware helpers rather than weakened or skipped.
**Verified:** 2026-06-28
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | All six invocation modes pass on EL9; SSH paths follow with `restorecon -R -F`; `setenforce 0` / `SELINUX=disabled` never used | ✓ VERIFIED | `distro_restore_ssh_context` called at both SSH-seed sites (20-agent-user.bats:41, 50-agents.bats:64); zero `setenforce`/`SELINUX=disabled` in tests/ plugin/ packaging/; systemd-mode skips are Docker-generic (not EL9-specific); 257/257 authoritative run includes these tests |
| 2 | Complete bats contract green on the Alma Docker row; Ubuntu assertions generalized through distro.bash helpers (no assertion weakened or skipped) | ✓ VERIFIED | 257/257 PASS recorded in 20-06-SUMMARY authoritative run (exit 0, filename order, no hang); ubuntu-24.04 stays 257/257; distro.bash has 10 verbs covering all families; all `skip` statements are pre-existing conditional guards applying equally to both distros (systemd/CDN/fixture-state), none are EL9-specific dodges |
| 3 | Four-state brownfield flow (Reuse / Create / Remediate / Bail) produces correct per-component decisions on EL9; read-only detection snapshot invariant intact | ✓ VERIFIED | brownfield.bash routes through distro.bash; distro_pkg_is_installed routes dpkg-query → rpm -q on rhel; 52-agt02-brownfield-gate.bats:122 uses distro_pkg_is_installed; 13-reuse / 14-remediate / 15-detection all included in 257/257 |
| 4 | `agentlinux install --dry-run` non-mutating on EL9; single `--yes` flag + exit codes 64/65/1/0 behave as on Ubuntu | ✓ VERIFIED | 15-preflight-ux.bats covers this contract; included in 257/257 authoritative run; no product plugin/ code changed in Phase 20 (test-only phase) |

**Score:** 4/4 truths verified

### Deferred Items

Items not yet met but explicitly addressed in later milestone phases.

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | Six invocation modes under real enforcing SELinux (QEMU, not Docker AppArmor) | Phase 22 | Phase 22 goal; REQUIREMENTS.md EL-06 note explicitly calls out Phase 22 QEMU re-confirmation |
| 2 | PAR-01 QEMU half: full bats contract green on the QEMU row | Phase 22 | REQUIREMENTS.md PAR-01: "across both Docker (HARN-01) and QEMU (HARN-02) rows" |
| 3 | release.yml gate-2 almalinux-9 hard gate flip | Phase 22 | 20-07-SUMMARY: "release.yml gate-2-docker left UNCHANGED (Phase 22 REL-01 owns that flip)" |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `tests/bats/helpers/distro.bash` | 9-verb family-dispatch helper | ✓ VERIFIED | 206 lines, 10 verbs: distro_family, distro_locale_file, distro_assert_locale, distro_nodesource_repo_paths, distro_pkg_is_installed, distro_install_node22, distro_sudoers_pkg_line, distro_wrong_shell, distro_ssh_unit, distro_restore_ssh_context |
| `tests/bats/helpers/brownfield.bash` | Routes through distro.bash | ✓ VERIFIED | setup_brownfield_host_user_wrong_shell uses distro_wrong_shell; confirmed in 20-06-SUMMARY |
| `tests/bats/20-agent-user.bats` | SSH-seed site calls distro_restore_ssh_context | ✓ VERIFIED | Line 41: `distro_restore_ssh_context /home/agent/.ssh` |
| `tests/bats/50-agents.bats` | SSH-seed site calls distro_restore_ssh_context | ✓ VERIFIED | Line 64: `distro_restore_ssh_context /home/agent/.ssh` |
| `tests/bats/52-agt02-brownfield-gate.bats` | distro_pkg_is_installed (not inline dpkg-query) | ✓ VERIFIED | Line 122 routes through distro_pkg_is_installed nodejs |
| `tests/bats/15-preflight-ux.bats` | distro_wrong_shell for UX-04 alt-user fixture | ✓ VERIFIED | Test 13 assertion generalized through distro_wrong_shell; confirmed in 20-06-SUMMARY |
| `scripts/check-distro-leak.sh` | Cross-suite Debian-op leak guard | ✓ VERIFIED | 4.5K file, 14 apt/dpkg patterns guarded, with comment-strip and spec-file allowlist |
| `.github/workflows/test.yml` | almalinux-9 as hard PR gate (not experimental) | ✓ VERIFIED | almalinux-9 in matrix.target list with no `experimental: true` entry; `continue-on-error: ${{ matrix.experimental || false }}` resolves to false for almalinux-9 |
| `tests/docker/Dockerfile.almalinux-9` | diffutils + openssh-clients + iproute in dnf set | ✓ VERIFIED | 20-01-SUMMARY confirms Wave 1 substrate; must_haves frontmatter verified |
| `tests/docker/run.sh` | `--tmpfs /tmp:exec` for stub execve | ✓ VERIFIED | 20-01-PLAN must_haves key_links confirm pattern `/tmp:exec` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `distro_restore_ssh_context` | `sshd_t` can read .ssh (SELinux context) | `restorecon -R -F` guarded by `command -v` | ✓ WIRED | distro.bash:200-203; rhel arm: `if command -v restorecon >/dev/null 2>&1; then restorecon -R -F "$dir"; fi` — absence is no-op on Docker, real failure propagates on QEMU |
| `20-agent-user.bats setup` | `distro_restore_ssh_context` | line 41 direct call | ✓ WIRED | Confirmed by grep |
| `50-agents.bats setup` | `distro_restore_ssh_context` | line 64 direct call | ✓ WIRED | Confirmed by grep |
| `scripts/check-distro-leak.sh` | `.pre-commit-config.yaml` | local pre-commit hook | ✓ WIRED | 20-06-SUMMARY: `.pre-commit-config.yaml — local check-distro-leak hook (files: ^tests/bats/...)` |
| `almalinux-9 matrix entry` | `test.yml` bats-docker job | `matrix.experimental` absent → `false` | ✓ WIRED | almalinux-9 in matrix.target; no experimental flag; job is a hard gate |
| `distro_wrong_shell` | `brownfield.bash setup_brownfield_host_user_wrong_shell` | `useradd`/`usermod -s` | ✓ WIRED | Confirmed in 20-06-SUMMARY Files Modified section |

### Behavioral Spot-Checks

Step 7b: SKIPPED — authoritative runs are the gate per scope boundary. Re-running the full ~5 min Docker build is out of scope. The recorded authoritative runs (20-06-SUMMARY + 20-07-SUMMARY) are the acceptance evidence. Fast checks run:

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| No setenforce/SELINUX=disabled anywhere | `grep -rn setenforce\|SELINUX=disabled tests/ plugin/ packaging/` | No matches | ✓ PASS |
| No EL9-specific skip dodges | `grep -rn '^\s*skip' tests/bats/*.bats` | All skips are Docker-generic (systemd/CDN/fixture-state) | ✓ PASS |
| distro_restore_ssh_context wired at both SSH-seed sites | grep in 20-agent-user.bats + 50-agents.bats | Lines 41 and 64 confirmed | ✓ PASS |
| check-distro-leak.sh substantive | file size + grep count | 4.5K, 14 apt/dpkg patterns | ✓ PASS |
| almalinux-9 is hard gate in test.yml | grep matrix + experimental | No `experimental: true` for almalinux-9 entry | ✓ PASS |

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| EL-06 (Phase 20 surface) | Six modes green on Docker row; restorecon code landed at two SSH-seed sites | ✓ SATISFIED | distro_restore_ssh_context wired at both sites; no setenforce used; 257/257 includes BHV mode tests; QEMU/enforcing deferred to Phase 22 per documented scope |
| EL-08 | Four-state brownfield + dry-run non-mutating + exit codes 64/65/1/0 on EL9 | ✓ SATISFIED | 257/257 includes 13-reuse, 14-remediate, 15-preflight-ux; brownfield routes through distro.bash |
| PAR-01 (Docker half) | Full bats contract green on almalinux-9 Docker row; no assertion weakened or skipped | ✓ SATISFIED | 257/257 authoritative run in 20-06-SUMMARY; ubuntu-24.04 stays 257/257; QEMU half deferred to Phase 22 |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | No TODO/FIXME/placeholder stubs, no return null, no EL9-specific test dodges found | — | — |

The test-only nature of Phase 20 (zero plugin/ product code changed, confirmed by all SUMMARY key-files sections) eliminates the usual stub risk. The distro.bash rhel arms are substantive (guarded command checks, real rpm invocations, real restorecon guard).

### Human Verification Required

None. All observables are verifiable programmatically or substantiated by the recorded authoritative run logs in the SUMMARY files.

### Gaps Summary

No gaps. The phase achieves its goal:

- 257/257 bats tests pass on `almalinux-9` (recorded authoritative run, 20-06-SUMMARY).
- 257/257 bats tests pass on `ubuntu-24.04` with zero regression (recorded, 20-06-SUMMARY).
- All Ubuntu-path assertions are generalized through `tests/bats/helpers/distro.bash` (10 verbs), not weakened or skipped.
- `distro_restore_ssh_context` is wired at both SSH-seed sites (20-agent-user.bats:41, 50-agents.bats:64) with a guarded restorecon that propagates real failures on QEMU.
- No `setenforce 0` / `SELINUX=disabled` exists anywhere in the tree.
- `scripts/check-distro-leak.sh` enforces the Debian-op leak guard cross-suite via pre-commit hook.
- `almalinux-9` is a hard PR gate in test.yml (Phase 20 flip confirmed in 20-07-SUMMARY).
- Three items are correctly deferred to Phase 22: real enforcing-SELinux QEMU run, PAR-01 QEMU half, and release.yml gate-2 flip.

---

_Verified: 2026-06-28_
_Verifier: Claude (gsd-verifier)_
