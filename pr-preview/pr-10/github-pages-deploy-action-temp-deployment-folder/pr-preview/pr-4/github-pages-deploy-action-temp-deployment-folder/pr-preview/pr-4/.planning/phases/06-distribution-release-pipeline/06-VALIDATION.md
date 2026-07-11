---
phase: 6
slug: distribution-release-pipeline
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-20
---

# Phase 6 — Validation Strategy

> Final phase — release pipeline, curl-installer, QEMU harness, README.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core (behavior tests) + github actions (release.yml) + pre-commit (shellcheck/shfmt/biome) + QEMU (cloud-image boot) |
| **Config files** | `.github/workflows/release.yml`, `scripts/build-release.sh`, `packaging/curl-installer/install.sh`, `tests/qemu/boot.sh` + `tests/qemu/cloud-init/` |
| **Quick run command** | `shellcheck packaging/curl-installer/install.sh scripts/build-release.sh tests/qemu/boot.sh` |
| **Full suite command** | `./tests/docker/run.sh ubuntu-22.04 && ./tests/docker/run.sh ubuntu-24.04` + `./tests/qemu/boot.sh ubuntu-24.04` (manual) + `scripts/build-release.sh v0.3.0 --dry-run` |
| **Estimated runtime** | Docker ~14min; QEMU ~8-12min per image (first cold-boot, cached subsequent); build-release ~30s |

---

## Sampling Rate

- Per commit: `shellcheck` on touched files (<5s).
- Per plan: Docker matrix smoke; `scripts/build-release.sh --dry-run`.
- Before phase close: full 4-gate chain green in `release.yml` dry-run (`workflow_dispatch`).
- Before tag push: all 4 gates green in `release.yml`.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Req | Threat | Test Type | Automated Command | Status |
|---------|------|------|-----|--------|-----------|-------------------|--------|
| 06-01-01 | 01 build-release | 1 | INST-03 CAT-05 | T-06-01 | unit | `scripts/build-release.sh v0.3.0 --dry-run` produces tarball + sha256 + catalog snapshot | ⬜ |
| 06-01-02 | 01 build-release | 1 | INST-03 | T-06-01 | unit | sha256sum -c against produced `.sha256` returns exit 0 | ⬜ |
| 06-01-03 | 01 build-release | 1 | INST-03 | T-06-01 | unit | re-run on same commit is byte-identical (reproducibility) | ⬜ |
| 06-02-01 | 02 curl-installer | 1 | INST-03 | T-06-02 | bats | `packaging/curl-installer/install.sh` fails fast on bad SHA256 | ⬜ |
| 06-02-02 | 02 curl-installer | 1 | INST-03 | T-06-02 | bats | good SHA256 → extracts + execs plugin/bin/agentlinux-install | ⬜ |
| 06-02-03 | 02 curl-installer | 1 | INST-03 | T-06-02 | bats | installer wrapped in `main(){}; main "$@"` (partial download safety) | ⬜ |
| 06-03-01 | 03 qemu harness | 2 | TST-03 | T-06-03 | integration | `tests/qemu/boot.sh ubuntu-22.04` exits 0 (cloud-init + ssh-in + installer + bats) | ⬜ |
| 06-03-02 | 03 qemu harness | 2 | TST-03 | T-06-03 | integration | `tests/qemu/boot.sh ubuntu-24.04` exits 0 | ⬜ |
| 06-03-03 | 03 qemu harness | 2 | TST-03 | T-06-03 | integration | AGT-02 bats runs inside QEMU and passes | ⬜ |
| 06-04-01 | 04 release.yml | 3 | TST-05 TST-08 | T-06-04 | CI | v* tag push triggers 4-gate pipeline | ⬜ |
| 06-04-02 | 04 release.yml | 3 | TST-05 | T-06-04 | CI | AGT-02 gate (bats tests/bats/51-*.bats) blocks on failure | ⬜ |
| 06-04-03 | 04 release.yml | 3 | TST-08 | T-06-04 | CI | pinned-combo gate (install all 3 agents + run 50-agents.bats) blocks on failure | ⬜ |
| 06-04-04 | 04 release.yml | 3 | INST-03 CAT-05 | T-06-04 | CI | softprops/action-gh-release@v2 publishes tarball + sha256 + catalog-<ver>.json | ⬜ |
| 06-05-01 | 05 README + STABILITY | 3 | DOC-01 | T-06-05 | docs | README.md has Install/Verify/Uninstall/Stability sections with exact commands | ⬜ |
| 06-05-02 | 05 README + STABILITY | 3 | DOC-01 | T-06-05 | docs | `<!-- VERSION_START -->v0.3.0<!-- VERSION_END -->` stamp present | ⬜ |

---

## Wave 0 Requirements

- [ ] `scripts/build-release.sh` — NEW; assembles tarball + sha256 + catalog snapshot; SOURCE_DATE_EPOCH reproducible
- [ ] `packaging/curl-installer/install.sh` — REPLACE stub with real SHA256-verified curl-pipe-bash
- [ ] `tests/qemu/boot.sh` — REPLACE scaffold with real cloud-init + qemu invocation + SSH-in + bats runner
- [ ] `tests/qemu/cloud-init/user-data.yaml` — NEW; minimal agent-capable seed
- [ ] `.github/workflows/release.yml` — REPLACE scaffold with real 4-gate pipeline
- [ ] `.github/workflows/nightly-qemu.yml` — REPLACE scaffold with real QEMU nightly (or fold into release.yml — planner decides)
- [ ] `README.md` — ADD Install/Verify/Uninstall/Stability sections (merge with existing v0.1.0 content if any)
- [ ] `docs/STABILITY-MODEL.md` — OPTIONAL; defer to v0.3.1 if tight
- [ ] `tests/bats/60-curl-installer.bats` — NEW; verifies curl-installer contract (dry-run against a local fixture)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Instructions |
|----------|-------------|------------|--------------|
| Real `curl | bash` from production URL on fresh Ubuntu cloud image | INST-03 | Staging environment has no redirect from agentlinux.org until production ships | Defer to post-release smoke |
| Full QEMU release-gate run on both Ubuntu 22.04 and 24.04 with KVM enabled | TST-03 | GitHub Actions runner first-time KVM-rule installation — needs real CI run to confirm | First tag push exercises this |
| Release publish via softprops/action-gh-release@v2 | INST-03 + CAT-05 | Requires real tag push | First tag push exercises this |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dep
- [ ] Sampling continuity
- [ ] Wave 0 covers 9 MISSING refs
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s quick, < 600s full QEMU
- [ ] nyquist_compliant: true after Wave 0

**Approval:** pending
