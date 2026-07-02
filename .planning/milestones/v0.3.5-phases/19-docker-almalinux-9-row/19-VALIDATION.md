---
phase: 19
slug: docker-almalinux-9-row
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-28
---

# Phase 19 — Docker AlmaLinux 9 Row — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats (`tests/bats/` behavior-contract suite — the spec) run inside the EL9 image via `tests/docker/run.sh almalinux-9`; image installs `bats-1.8.0-1.el9` from EPEL |
| **Config file** | none — bats runs through `tests/docker/run.sh almalinux-9` |
| **Quick run command** | `bash tests/docker/run.sh almalinux-9` (local; Docker available on dev host) |
| **Full suite command** | gate-2 Docker matrix across all four targets in CI (`test.yml` bats-docker / `release.yml` gate-2-docker) |
| **Estimated runtime** | ~90s build+boot+install, then the bats suite |

---

## Sampling Rate

- **After every task commit:** Dockerfile/run.sh tasks → the task's `<automated>` grep/build check; CI tasks → YAML parse + grep assertions
- **After every plan wave:** `bash tests/docker/run.sh almalinux-9` (Wave 1 substrate) / CI matrix present (Wave 2)
- **Before `/gsd-verify-work`:** `run.sh almalinux-9` builds + boots + install exits 0 + bats EXECUTES (full bats green NOT required — Phase 20)
- **Max feedback latency:** ~90s (local Docker loop)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 19-01-01 | 01 | 1 | HARN-01 | T-19-01/02/03 | EL9 image builds; no curl/curl-minimal conflict; --privileged scoped to ephemeral CI | infra/build | `grep '^FROM almalinux:9' … && grep -c 'epel-release' ≥1 && curl-absent && docker build -f tests/docker/Dockerfile.almalinux-9 .` | ❌ W0 (new Dockerfile) | ⬜ pending |
| 19-01-02 | 01 | 1 | HARN-01 | — | run.sh rejects unknown target (exit 64); fixed allow-list | unit | `bash -n run.sh && case-accepts almalinux-9 && run.sh badtarget → 64 && no UBUNTU_VERSION` | ✅ run.sh exists; ❌ alma case | ⬜ pending |
| 19-01-03 | 01 | 1 | HARN-01 (+resolves A1) | T-19-04 | NodeSource HTTPS+gpgkey path exercised; nodesource substring confirmed | integration/smoke | `run.sh almalinux-9` → install exit 0 + bats executes; `rpm -q nodejs` contains nodesource; `node --version` v22 | ✅ suite+installer exist; first EL9 exercise | ⬜ pending |
| 19-02-01 | 02 | 2 | HARN-01 | T-19-05/06 | keep `permissions: contents: read`; no token scope added | CI/config | YAML parse + `almalinux-9` in target matrix + `${{ matrix.target }}` consumer + no `matrix.ubuntu` in test.yml | ❌ W0 (matrix edit) | ⬜ pending |
| 19-02-02 | 02 | 2 | HARN-01 | T-19-06 | gate-3-qemu / gate-4 unchanged (Phase 22 / ADR-011) | CI/config | YAML parse + `target: [...,almalinux-9]` in gate-2 + gate-3 `boot.sh ${{ matrix.ubuntu }}` survives + gate-4 `run.sh ubuntu-24.04` survives | ❌ W0 (matrix edit) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/docker/Dockerfile.almalinux-9` — new file (EL9 final stage; cli-builder reused byte-identical) — created by Task 19-01-01.
- [ ] `tests/docker/run.sh` — add `almalinux-9` case + generalize wording — Task 19-01-02.
- [ ] `.github/workflows/test.yml` — bats-docker matrix `ubuntu`→`target` + `almalinux-9` — Task 19-02-01.
- [ ] `.github/workflows/release.yml` — gate-2-docker matrix only `ubuntu`→`target` + `almalinux-9` — Task 19-02-02.
- [ ] No new bats files — the existing contract is reused; EL9-specific bats fixtures land in Phase 20.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| (none) | HARN-01 | — | All Phase-19 behaviors are automated via `run.sh almalinux-9` + grep/YAML checks |

*All phase behaviors have automated verification.*

> Note: individual bats files MAY be red on EL9 at Phase 19 close — that is NOT a
> Phase 19 failure. Phase 19's gate is a runnable bats INVOCATION + green install;
> driving the full contract green is Phase 20 (PAR-01). The alma bats red/green
> per-file list captured at Task 19-01-03 is the Phase 20 input inventory.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (new Dockerfile + matrix edits)
- [x] No watch-mode flags
- [x] Feedback latency < 120s (local Docker loop ~90s)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-06-28
