---
phase: 18
slug: detection-branching-foundation
status: approved
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-28
---

# Phase 18 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Phase 18 verification is dev-host unit-sourcing + Ubuntu byte-for-byte regression.
> Live EL9 acceptance (Node 22, locale, sudoers, six modes) is owned by the
> co-developed Phase 19 Docker substrate + Phase 20 bats sweep — NOT this phase.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats 1.10.0 (behavior-contract suite under `tests/bats/`) + shellcheck 0.9.0 |
| **Config file** | none — bats unit files run directly on the dev host; full suite runs via `tests/docker/run.sh <target>` |
| **Quick run command** | `bats tests/bats/18-distro-detect.bats tests/bats/18-pkg-dispatch.bats tests/bats/18-detect-el9.bats` |
| **Full suite command** | `bash tests/docker/run.sh ubuntu-24.04` (Ubuntu regression — byte-for-byte preserved) |
| **Estimated runtime** | ~5s (unit bats + shellcheck) / ~90s (Ubuntu Docker row) |

---

## Sampling Rate

- **After every task commit:** Run the plan's `bats tests/bats/18-*.bats` unit file + `shellcheck` on the edited file(s); `pre-commit run --all-files`.
- **After every plan wave:** Wave 1 → run all three 18-*.bats unit files green. Wave 2 → `bash tests/docker/run.sh ubuntu-24.04` (Ubuntu regression: no apt-path behavior change).
- **Before `/gsd-verify-work`:** All 18-*.bats green on dev host + Ubuntu Docker row green; `grep -rn 'apt-get\|dpkg' plugin/` matches only inside pkg.sh's debian arm.
- **Max feedback latency:** ~90 seconds (Ubuntu Docker row).

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 18-01-01 | 01 | 1 | EL-01 | T-18-04 | os-release seam test-only; defaults to /etc/os-release | unit (bats RED) | `bats tests/bats/18-distro-detect.bats` (expect fail) | ❌ W0 | ⬜ pending |
| 18-01-02 | 01 | 1 | EL-01 | T-18-01 / T-18-02 | ID-exact match; quoted interpolation into log only | unit (bats GREEN) | `bats tests/bats/18-distro-detect.bats && shellcheck plugin/lib/distro_detect.sh` | ✅ (W0 18-01-01) | ⬜ pending |
| 18-01-03 | 01 | 1 | EL-01 | T-18-03 | lockstep allowlist; ID-exact | static + lint | `shellcheck packaging/curl-installer/install.sh && grep -q almalinux packaging/curl-installer/install.sh` | ✅ | ⬜ pending |
| 18-02-01 | 02 | 1 | EL-02 | T-18-05 | static-literal pkg args | unit (bats RED) | `bats tests/bats/18-pkg-dispatch.bats` (expect fail) | ❌ W0 | ⬜ pending |
| 18-02-02 | 02 | 1 | EL-02 | T-18-06 / T-18-07 | HTTPS+gpgcheck fetch; atomic locale write | unit (bats GREEN) | `bats tests/bats/18-pkg-dispatch.bats && shellcheck plugin/lib/pkg.sh` | ✅ (W0 18-02-01) | ⬜ pending |
| 18-03-01 | 03 | 2 | EL-04 | T-18-07 | locale via atomic verb; no apt/locale-gen residue | static + lint | `shellcheck plugin/provisioner/10-agent-user.sh && test "$(grep -c 'locale-gen\|apt-get' plugin/provisioner/10-agent-user.sh)" = 0` | ✅ | ⬜ pending |
| 18-03-02 | 03 | 2 | EL-05 | T-18-09 | visudo-gated drop-in unchanged; only verb branches | static + lint | `shellcheck plugin/provisioner/20-sudoers.sh && grep -q 'pkg_install sudo' plugin/provisioner/20-sudoers.sh` | ✅ | ⬜ pending |
| 18-03-03 | 03 | 2 | EL-03 | T-18-10 / T-18-11 / T-18-12 | GPG-verified NodeSource RPM; module reset; no curl install | static + lint (live: Phase 19) | `shellcheck plugin/provisioner/30-nodejs.sh && grep -q 'pkg_install nodejs' plugin/provisioner/30-nodejs.sh && test "$(grep -c apt-get plugin/provisioner/30-nodejs.sh)" = 0` | ✅ | ⬜ pending |
| 18-04-01 | 04 | 2 | EL-02 | — | sourcing order distro_detect→pkg→idempotency | static + lint | `shellcheck plugin/bin/agentlinux-install && awk '/distro_detect.sh/{d=NR}/pkg.sh/{p=NR}/idempotency.sh/{i=NR}END{exit !(d<p&&p<i)}' plugin/bin/agentlinux-install` | ✅ | ⬜ pending |
| 18-04-02 | 04 | 2 | EL-02 | T-18-13 / T-18-14 | purge via static repo-path list; install/purge symmetry | static + lint | `shellcheck plugin/bin/agentlinux-install && test "$(grep -c apt-get plugin/bin/agentlinux-install)" = 0` | ✅ | ⬜ pending |
| 18-05-01 | 05 | 2 | EL-07 | T-18-17 | read-only probes; no non-query dnf | unit (bats RED) | `bats tests/bats/18-detect-el9.bats` (expect fail) | ❌ W0 | ⬜ pending |
| 18-05-02 | 05 | 2 | EL-07 | T-18-17 / T-18-18 | rpm -q + repo-file dual gate; read-only | unit (bats GREEN) | `shellcheck plugin/lib/detect/nodejs.sh && test "$(grep -c 'dnf ' plugin/lib/detect/nodejs.sh)" = 0` | ✅ (W0 18-05-01) | ⬜ pending |
| 18-05-03 | 05 | 2 | EL-07 | T-18-16 / T-18-19 | absolute-path probe; can_sudo_apt field preserved | unit (bats GREEN) | `bats tests/bats/18-detect-el9.bats && ! grep -q can_sudo_pkg plugin/lib/detect/user.sh` | ✅ | ⬜ pending |
| 18-06-01 | 06 | 2 | EL-01, EL-02 | T-18-20 | docs-only; no executable surface | doc-presence | `test -f docs/decisions/017-distro-family-bucket.md && grep -q '## Consequences' docs/decisions/017-distro-family-bucket.md` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/bats/18-distro-detect.bats` — EL-01 fixtures (accept almalinux 9.*, reject Alma 8/10/Rocky/RHEL, escape-hatch seeds FAMILY); requires the `AGENTLINUX_OS_RELEASE_PATH` seam (plan 01 task 2).
- [ ] `tests/bats/18-pkg-dispatch.bats` — EL-02 verb dispatch via PATH-stubbed apt-get/dnf/rpm/curl.
- [ ] `tests/bats/18-detect-el9.bats` — EL-07 rhel classification (NodeSource-RPM vs AppStream-module vs absent) + can_sudo_apt field preservation, via stubbed rpm/dnf.
- [ ] CI grep guard (verification step, no new file): `grep -rn 'apt-get\|dpkg\|locale-gen' plugin/` matches only inside pkg.sh's debian arm.

*Each Wave 0 bats file is authored as the RED task inside its plan (TDD), then made green by the implementation task in the same plan.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Exact `rpm -q --qf '%{VERSION}-%{RELEASE}' nodejs` release string contains `nodesource` | EL-07 (Open Q1) | Not reproducible on the Ubuntu dev host; needs the real `almalinux:9` image | On the Phase 19 Docker arm: `dnf install -y nodejs && rpm -q --qf '%{VERSION}-%{RELEASE}\n' nodejs` — confirm the `nodesource` substring before locking the DET-02 classifier |
| Node 22 / C.UTF-8 / passwordless sudo on a live EL9 host | EL-03/04/05 | Live install outcomes; deferred to the co-developed Docker substrate | Phase 19: `bash tests/docker/run.sh almalinux-9` reaches `agentlinux-install complete` |

*All Phase-18 CODE behaviors have dev-host automated verification (unit bats + shellcheck + grep guards). The two rows above are EL9 RUNTIME acceptances explicitly owned by Phases 19/20 per the roadmap.*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (3 new bats files, each RED-authored in its plan)
- [x] No watch-mode flags
- [x] Feedback latency < 90s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-06-28
