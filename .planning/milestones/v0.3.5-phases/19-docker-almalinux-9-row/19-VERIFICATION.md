---
phase: 19-docker-almalinux-9-row
verified: 2026-06-28T17:45:00Z
status: passed
score: 8/8 must-haves verified
overrides_applied: 0
---

# Phase 19: Docker AlmaLinux 9 Row — Verification Report

**Phase Goal:** A fast-feedback `almalinux:9` Docker substrate that runs the bats suite, so the Phase 18 branch can be validated on a real EL9 environment in the ~90s Docker loop. Phase 19 is Phase 18's acceptance gate. Delivers `Dockerfile.almalinux-9` + `run.sh almalinux-9` case + an `almalinux-9` CI matrix arm in `test.yml` + `release.yml` gate-2.

**Verified:** 2026-06-28T17:45:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `./tests/docker/run.sh almalinux-9` builds `Dockerfile.almalinux-9` (`FROM almalinux:9`) and boots under the systemd-in-Docker recipe | VERIFIED | Dockerfile.almalinux-9 exists (148 lines), `FROM almalinux:9` at line 64, `CMD ["/sbin/init"]` at line 148, EPEL+bats+systemd mask block present; run.sh case allowlist includes `almalinux-9` (line 48); 19-01-SUMMARY records live smoke build+boot |
| 2 | `agentlinux-install` completes exit 0 inside the almalinux:9 container | VERIFIED | 19-01-SUMMARY: "First composed EL9 install proven green — `agentlinux-install` runs end-to-end to exit 0 inside the booted `almalinux:9` container"; commits 1e9792e (Dockerfile), 1e90c2c (run.sh), ed55342 (shadow fix) present in git log |
| 3 | `bats tests/bats/` is INVOKABLE on the almalinux-9 row (exit code propagates; individual RED files are Phase 20) | VERIFIED | run.sh line 177: `docker exec "$CID" bash -c 'cd /opt/agentlinux-src && bats tests/bats/'`; 19-01-SUMMARY: "the suite is invokable end-to-end across these files…observed executing well past test #130 in a 10-minute run" |
| 4 | `rpm -q --qf '%{VERSION}-%{RELEASE}' nodejs` on live EL9 contains `nodesource` substring (resolves Phase 18 Open Q1) | VERIFIED | 19-01-SUMMARY verbatim transcript: `22.23.1-1nodesource` / `v22.23.1`; confirmed via `docker exec` against the kept post-install container |
| 5 | `test.yml` `bats-docker` job carries an `almalinux-9` arm in the matrix (`ubuntu`→`target`) with `fail-fast: false` and `continue-on-error` for the experimental arm | VERIFIED | test.yml lines 138–149: `fail-fast: false`, `target:` dimension, `- almalinux-9`, `include: - target: almalinux-9 / experimental: true`; line 123: `continue-on-error: ${{ matrix.experimental \|\| false }}`; line 167: `bash tests/docker/run.sh ${{ matrix.target }}`; YAML valid |
| 6 | `release.yml` `gate-2-docker` job carries an `almalinux-9` arm (`ubuntu`→`target`) with `fail-fast: false` and `continue-on-error` | VERIFIED | release.yml lines 141–152: `continue-on-error: ${{ matrix.experimental \|\| false }}`, `target: [ubuntu-22.04, ubuntu-24.04, ubuntu-26.04, almalinux-9]`, `experimental: true` for almalinux-9, `bash tests/docker/run.sh ${{ matrix.target }}`; YAML valid |
| 7 | Each renamed matrix dimension's `${{ matrix.<name> }}` consumer is renamed in lockstep (Ubuntu arms still get non-empty target) | VERIFIED | test.yml: zero `matrix.ubuntu` occurrences; `matrix.target` at line 167. release.yml gate-2: single Docker consumer at line 152 uses `matrix.target`. Ubuntu arms (22.04/24.04/26.04) receive their target strings unchanged |
| 8 | `gate-3-qemu` and `gate-4-pinned-combo` in `release.yml` are byte-for-byte unchanged | VERIFIED | `matrix.ubuntu` appears 4 times in release.yml (lines 214, 216, 219, 228 — all in gate-3-qemu); gate-4-pinned-combo retains hardcoded `bash tests/docker/run.sh ubuntu-24.04`; gate-3/gate-4 not touched by phase-19 commits |

**Score:** 8/8 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `tests/docker/Dockerfile.almalinux-9` | Two-stage EL9 test image: cli-builder (byte-identical to Ubuntu rows) + EL9 final stage via EPEL+dnf | VERIFIED | 148 lines; `FROM node:22-slim AS cli-builder` stage 1; `FROM almalinux:9` stage 2; EPEL-first install; `chmod 0640 /etc/shadow` substrate accommodation; COPY trio at lines 139–141 identical to Ubuntu rows; `CMD ["/sbin/init"]` |
| `tests/docker/run.sh` | `almalinux-9` in case allowlist; `UBUNTU_VERSION`→`TARGET` rename; distro-neutral flow unchanged | VERIFIED | `almalinux-9` at line 48; `TARGET=${1:-}` at line 42; `unsupported target:` at line 54; zero `UBUNTU_VERSION` occurrences; shellcheck clean (no warnings); build/boot/wait/splice/install/bats flow (lines 82–182) untouched |
| `.github/workflows/test.yml` | `bats-docker` matrix.target incl. almalinux-9; run step consumes matrix.target | VERIFIED | YAML valid; `target:` dimension; `- almalinux-9`; `continue-on-error: ${{ matrix.experimental \|\| false }}`; run step at line 167 |
| `.github/workflows/release.yml` | `gate-2-docker` matrix.target incl. almalinux-9; gate-3/gate-4 untouched | VERIFIED | YAML valid; `target: [ubuntu-22.04, ubuntu-24.04, ubuntu-26.04, almalinux-9]` at line 145; exactly one Docker `matrix.target` consumer; gate-3 `matrix.ubuntu` (4 refs) intact; gate-4 `ubuntu-24.04` hardcode intact |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `Dockerfile.almalinux-9` cli-builder stage | `run.sh` splice (lines 162–169) | `COPY --from=cli-builder /build/cli/{dist,node_modules,package.json}` → `/opt/cli-prebuilt/` | VERIFIED | Dockerfile lines 139–141 copy to `/opt/cli-prebuilt/dist`, `/opt/cli-prebuilt/node_modules`, `/opt/cli-prebuilt/package.json`; run.sh splice hard-depends on these exact paths and copies them to `/opt/agentlinux-src/plugin/cli/` |
| `run.sh` case allowlist | `Dockerfile.almalinux-9` | `DF="$HERE/Dockerfile.${TARGET}"` resolves once case accepts `almalinux-9` | VERIFIED | run.sh line 47–48: `almalinux-9` in accept arm; line 63: `DF="$HERE/Dockerfile.${TARGET}"`; line 65 guards missing Dockerfile (would exit 64, not silently succeed) |
| `test.yml` `matrix.target` | `run.sh almalinux-9` arm | `run: bash tests/docker/run.sh ${{ matrix.target }}` | VERIFIED | test.yml line 167; the run.sh case accepts `almalinux-9`; YAML parses |
| `release.yml` gate-2 `matrix.target` | `run.sh almalinux-9` arm | `run: bash tests/docker/run.sh ${{ matrix.target }}` | VERIFIED | release.yml line 152; exactly one Docker `matrix.target` consumer in the file |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED for the Docker build/boot path (requires ~5 min container build; per instructions, no re-running the documented smoke). The 19-01-SUMMARY constitutes the smoke evidence.

Static checks run instead:

| Behavior | Check | Result | Status |
|----------|-------|--------|--------|
| `run.sh` syntax-clean | `shellcheck --severity=warning tests/docker/run.sh` | No output (zero warnings) | PASS |
| `test.yml` YAML valid | `python3 yaml.safe_load(...)` | No exception | PASS |
| `release.yml` YAML valid | `python3 yaml.safe_load(...)` | No exception | PASS |
| `almalinux-9` in run.sh case | `grep 'almalinux-9' run.sh` | Line 48: `ubuntu-22.04 \| ubuntu-24.04 \| ubuntu-26.04 \| almalinux-9) ;;` | PASS |
| No `UBUNTU_VERSION` in run.sh | `grep -c 'UBUNTU_VERSION' run.sh` | 0 | PASS |
| `FROM almalinux:9` present | `grep 'FROM almalinux:9' Dockerfile.almalinux-9` | Line 64 | PASS |
| No Ubuntu-only artifacts in Dockerfile | `grep 'locale-gen\|DEBIAN_FRONTEND\|systemd-sysv' Dockerfile.almalinux-9` | 0 matches | PASS |
| No `curl` in dnf install set | `grep 'install.*curl' Dockerfile.almalinux-9` | 0 matches in RUN block (curl mentioned only in comments explaining its intentional absence) | PASS |
| COPY trio paths present | `grep '/opt/cli-prebuilt/' Dockerfile.almalinux-9` | Lines 139–141 | PASS |
| gate-3 `matrix.ubuntu` preserved | `grep 'matrix.ubuntu' release.yml` | 4 occurrences (lines 214, 216, 219, 228 — all gate-3-qemu) | PASS |
| gate-4 hardcoded `ubuntu-24.04` preserved | `grep 'run.sh ubuntu-24.04' release.yml` | 2 occurrences (line 14 comment + gate-4 run step) | PASS |
| `continue-on-error` on almalinux-9 arm | `grep 'continue-on-error' test.yml release.yml` | Both files: `${{ matrix.experimental \|\| false }}`; almalinux-9 flagged `experimental: true` | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description (abbreviated) | Status | Evidence |
|-------------|------------|--------------------------|--------|----------|
| HARN-01 | 19-01-PLAN, 19-02-PLAN | `almalinux-9` Docker matrix row runs bats suite in CI; `Dockerfile.almalinux-9` + `run.sh` + `test.yml`/`release.yml` matrices | SATISFIED | All three gates met: (a) build+boot+install-exit-0 documented in 19-01-SUMMARY; (b) bats invokable per run.sh line 177 + SUMMARY transcript; (c) CI arms wired with `continue-on-error` in both workflows |

Note: REQUIREMENTS.md still shows HARN-01 `Status: Pending` — this is a documentation tracking field that the phase execution did not update. It does not affect goal achievement.

---

### Anti-Patterns Found

None. No TODO/FIXME/placeholder in any Phase 19 artifact.

---

### Intentional Package Delta (for traceability)

The ROADMAP Phase 19 Success Criterion #1 lists `curl` in the EL9 package set. `Dockerfile.almalinux-9` intentionally omits `curl` (and `coreutils`). `curl-minimal` and `coreutils-single` are preinstalled on `almalinux:9` and already provide the required binaries; pulling the full packages triggers `curl/curl-minimal` and `coreutils/coreutils-single` file conflicts (verified live on first EL9 build). This is a correct-by-design deviation, documented explicitly in 19-01-SUMMARY §"Intentional package delta vs ROADMAP Phase 19 SC#1". Not a gap.

---

### Deferred Items

Per the scope boundary, the following items are correctly deferred to later phases and are not gaps for Phase 19:

| Item | Addressed In | Evidence |
|------|-------------|----------|
| Individual bats files red on EL9 | Phase 20 (PAR-01) | REQUIREMENTS.md: "PAR-01: The complete existing behavior contract is green on AlmaLinux 9 across both Docker (HARN-01) and QEMU (HARN-02) rows." Phase 20 drives this green. |
| QEMU EL9 row | Phase 22 (HARN-02) | REQUIREMENTS.md: "HARN-02: A new AlmaLinux 9 QEMU cloud-image row runs the release-gate suite on a real VM." |
| `gate-3-qemu` EL9 addition | Phase 22 (REL-01) | 19-02-PLAN: "DO NOT TOUCH gate-3-qemu (Phase 22 / ADR-011)." |
| Making almalinux-9 a hard release gate | Phase 22 (REL-01) | `continue-on-error` intentionally present; Phase 22 removes it when PAR-01/HARN-02 are green. |

---

### Human Verification Required

None. All must-haves are verifiable through code inspection and the documented live smoke run in 19-01-SUMMARY.

---

## Gaps Summary

No gaps. All 8 must-haves verified. Phase 19 goal fully achieved:

- `tests/docker/Dockerfile.almalinux-9` exists as a substantive, wired, non-stub 148-line two-stage EL9 test image.
- `tests/docker/run.sh` accepts `almalinux-9` with no `UBUNTU_VERSION` residue and a shellcheck-clean script.
- Both CI workflow files carry a proper `almalinux-9` matrix arm in `bats-docker` and `gate-2-docker`, with `continue-on-error: ${{ matrix.experimental || false }}` so the red-by-design EL9 arm (until Phase 20) does not block PRs or the release chain.
- Gate-3-qemu and gate-4-pinned-combo are byte-for-byte unchanged.
- The live smoke run documented in 19-01-SUMMARY satisfies HARN-01 gate (a) and (b): build + boot + `agentlinux-install` exit 0 + invokable bats, with NodeSource `22.23.1-1nodesource` transcript confirming Phase 18 Open Q1 resolved.

---

_Verified: 2026-06-28T17:45:00Z_
_Verifier: Claude (gsd-verifier)_
