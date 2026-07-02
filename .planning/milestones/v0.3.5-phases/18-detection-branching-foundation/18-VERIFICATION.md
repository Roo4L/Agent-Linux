---
phase: 18-detection-branching-foundation
verified: 2026-06-28T16:00:00Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
re_verification: null
gaps: []
deferred:
  - truth: "Running the installer on AlmaLinux 9 passes the distro gate and reaches agentlinux-install complete (live end-to-end EL9 run)"
    addressed_in: "Phase 19"
    evidence: "Phase 19 goal: 'A fast-feedback almalinux:9 Docker substrate that runs the bats suite, so the Phase 18 branch can be validated on a real EL9 environment'; Phase 20 success criteria confirm full bats contract green on EL9"
  - truth: "rpm -q nodejs shows a nodesource release; node --version is v22.x (live Node 22 install on EL9)"
    addressed_in: "Phase 19/20"
    evidence: "Phase 19 runs agentlinux-install to completion inside almalinux:9 container; Phase 20 SC 2 confirms the full behavior contract green on EL9"
  - truth: "Exact %{RELEASE} string from rpm -q nodejs on a real AlmaLinux 9 host confirms the nodesource substring key"
    addressed_in: "Phase 19"
    evidence: "detect/nodejs.sh comment explicitly notes 'the exact %{RELEASE} string (e.g. ...nodesource.el9) is not pinned — live-verified on almalinux:9 in Phase 19'"
human_verification: []
---

# Phase 18: Detection + Branching Foundation Verification Report

**Phase Goal**: AgentLinux's installer recognizes AlmaLinux 9 and routes every package-manager, locale, NodeSource, sudoers, and brownfield-detection operation through a single `AGENTLINUX_DISTRO_FAMILY` abstraction (`lib/distro_detect.sh` + new `lib/pkg.sh`), so a fresh install runs end-to-end on EL9 instead of dying at the Ubuntu-only gate or on a hardcoded `apt-get`.
**Verified**: 2026-06-28
**Status**: passed
**Re-verification**: No — initial verification

## Scope Note

Per the roadmap, live EL9 acceptance is **intentionally deferred**: the `almalinux:9` Docker substrate is Phase 19; bats-green-on-EL9 under enforcing SELinux is Phase 20; QEMU release gate is Phase 22. Phase 18 must-haves are **code properties** verifiable on this Ubuntu dev host: the family abstraction exists and is wired, all ~13 apt-get/dpkg call sites route through `pkg.sh` verbs, Ubuntu behavior is preserved, shellcheck is clean, and the phase-18 bats unit suites are green.

## Goal Achievement

### Observable Truths (Code Properties — Phase 18 scope)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `distro_detect.sh` accepts almalinux 9/9.x (FAMILY=rhel), rejects alma 8/10/rocky/rhel/centos/fedora with ID-exact matching, and ubuntu 22.04/24.04/26.04 accepted with FAMILY=debian | VERIFIED | bats 1–12 all pass; distro_detect.sh case "${ID:-}" arm confirmed; no ID_LIKE anywhere in plugin/ |
| 2 | AGENTLINUX_SKIP_DISTRO_CHECK=1 seeds AGENTLINUX_DISTRO_FAMILY (explicit override > os-release ID > debian default) | VERIFIED | bats 13–15 pass; escape-hatch code at distro_detect.sh:48–65 confirmed |
| 3 | pkg.sh exposes the full verb set (pkg_install, pkg_is_installed, pkg_remove, pkg_autoremove, nodesource_prereqs, nodesource_setup, nodesource_repo_paths, nodesource_module_reset, locale_ensure); each branches once on AGENTLINUX_DISTRO_FAMILY; debian arms byte-for-byte identical to prior call sites | VERIFIED | bats 16–35 all pass; code confirmed: 8 verbs, each two-arm case; no residual apt-get/dpkg in provisioners or entrypoint |
| 4 | All ~13 hardcoded apt-get/dpkg/locale-gen/NodeSource call sites route through pkg.sh verbs; no apt-get/dpkg remain in provisioner 10/20/30 or agentlinux-install; sourcing order correct (distro_detect → pkg → idempotency) | VERIFIED | `grep -rn 'apt-get\|dpkg' plugin/provisioner/ plugin/bin/agentlinux-install` returns nothing; awk sourcing-order check exits 0 (distro_detect.sh line 155 < pkg.sh line 161 < idempotency.sh line 163) |
| 5 | detect/nodejs.sh classifies pre-existing EL9 Node by real source (NodeSource-RPM via rpm dual-gate + nodesource_repo_paths lockstep, AppStream-module as distinct class, absent) using read-only probes; detect/user.sh probes /usr/bin/dnf on rhel while preserving can_sudo_apt field/export/accessor names | VERIFIED | bats 36–42 all pass; detect/nodejs.sh: rpm -q --qf, nodesource_repo_paths used (no hardcoded /etc/yum.repos.d path), 0 bare dnf invocations; detect/user.sh: /usr/bin/dnf + /usr/bin/apt-get both present, can_sudo_apt count=10, can_sudo_pkg count=0 |

**Score**: 5/5 truths verified

### Deferred Items

Items not yet met but explicitly addressed in later milestone phases (per REQUIREMENTS.md traceability; EL-06→Phase 20, EL-08→Phase 20, HARN-01→Phase 19, REL-01→Phase 22).

| # | Item | Addressed In | Evidence |
|---|------|-------------|---------|
| 1 | Live EL9 end-to-end run (agentlinux-install completes on almalinux:9) | Phase 19 | Phase 19 goal: run agentlinux-install to completion inside almalinux:9 Docker container |
| 2 | Live Node 22 install on EL9 (rpm -q nodejs shows nodesource release) | Phase 19/20 | Phase 19 SC 2: agentlinux-install runs to completion; Phase 20 SC 2: bats contract green |
| 3 | Exact %{RELEASE} substring confirmation on a real EL9 rpm DB | Phase 19 | Noted in detect/nodejs.sh comment; Phase 19 is the live-verify substrate |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `plugin/lib/distro_detect.sh` | almalinux arm + FAMILY export + escape-hatch seed + OS_RELEASE_PATH seam | VERIFIED | 4.9K, FAMILY=rhel (×2), FAMILY=debian (×2), AGENTLINUX_OS_RELEASE_PATH (×2), no ID_LIKE |
| `plugin/lib/pkg.sh` | full verb dispatch layer branching on AGENTLINUX_DISTRO_FAMILY | VERIFIED | 8.2K, 9 verbs defined, source-once guard, log precondition, write_file_atomic for locale, rpm.nodesource.com + deb.nodesource.com both present |
| `plugin/provisioner/10-agent-user.sh` | locale step via locale_ensure C.UTF-8; no locale-gen/apt-get | VERIFIED | locale_ensure C.UTF-8 present; 0 occurrences of locale-gen or apt-get |
| `plugin/provisioner/20-sudoers.sh` | sudo install via pkg_install sudo; drop-in logic intact | VERIFIED | pkg_install sudo present; ensure_dir /etc/sudoers.d present; 0 apt-get |
| `plugin/provisioner/30-nodejs.sh` | nodesource_prereqs/setup/module_reset/repo_paths; pkg_install nodejs; RT-01 preserved; no apt-transport-https | VERIFIED | all 4 verbs present; pkg_install nodejs present; node_major RT-01 check present; 0 apt-transport-https; 0 apt-get |
| `plugin/bin/agentlinux-install` | pkg.sh sourced; ensure_jq via pkg_install; run_purge via nodesource_repo_paths + pkg_remove/autoremove | VERIFIED | LIB_DIR/pkg.sh present; pkg_install jq present; nodesource_repo_paths loop in run_purge; pkg_remove nodejs; pkg_autoremove; 0 apt-get |
| `plugin/lib/detect/nodejs.sh` | rhel NodeSource-RPM + AppStream-module arms; nodesource_repo_paths lockstep; no bare dnf | VERIFIED | rpm -q --qf present; nodesource_repo_paths (×3); 0 hardcoded /etc/yum.repos.d path; 0 bare dnf invocations; -1nodesource debian arm intact |
| `plugin/lib/detect/user.sh` | /usr/bin/dnf probe on rhel; can_sudo_apt field/export/accessor preserved | VERIFIED | /usr/bin/dnf (×2) and /usr/bin/apt-get (×2) present; can_sudo_apt (×10); can_sudo_pkg (×0) |
| `packaging/curl-installer/install.sh` | detect_supported_distro accepting ubuntu + almalinux 9.*; no ID_LIKE | VERIFIED | detect_supported_distro function present; almalinux case arm at line 97; 9 | 9.* accepted; no ID_LIKE |
| `docs/decisions/017-distro-family-bucket.md` | ADR-017 with Status/Context/Decision/Consequences; AGENTLINUX_DISTRO_FAMILY; rejected alternatives | VERIFIED | 141 lines; Status: Accepted; all 4 sections present; AGENTLINUX_DISTRO_FAMILY (×3); pkg.sh (×7); localectl + module install + ID_LIKE all documented as rejected |
| `tests/bats/18-distro-detect.bats` | EL-01 accept/reject/escape-hatch fixtures; ≥6 tests | VERIFIED | 15 @tests; all tagged EL-01; AGENTLINUX_OS_RELEASE_PATH seam used (×5) |
| `tests/bats/18-pkg-dispatch.bats` | EL-02 verb-dispatch fixtures via PATH-stubbed apt-get/dnf/rpm; ≥6 tests | VERIFIED | 20 @tests; tagged EL-02/EL-03/EL-04/EL-05 |
| `tests/bats/18-detect-el9.bats` | EL-07 classification fixtures; ≥4 tests | VERIFIED | 7 @tests; all tagged EL-07; nodesource_repo_paths override used |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `packaging/curl-installer/install.sh` | `plugin/lib/distro_detect.sh` | identical ID/VERSION_ID allowlist (lockstep) | WIRED | Both accept ubuntu 22.04/24.04/26.04 and almalinux 9/9.*, reject all others; detect_supported_distro mirrors distro_detect case structure |
| `tests/bats/18-distro-detect.bats` | `distro_detect.sh::detect_distro` | AGENTLINUX_OS_RELEASE_PATH fixture override | WIRED | AGENTLINUX_OS_RELEASE_PATH used in 5 test fixture setups |
| `plugin/lib/pkg.sh` | `$AGENTLINUX_DISTRO_FAMILY` | two-arm case in every verb | WIRED | `case "$AGENTLINUX_DISTRO_FAMILY"` in all 9 verbs |
| `plugin/lib/pkg.sh::locale_ensure` | `idempotency.sh::write_file_atomic` | stdin-piped /etc/locale.conf write (rhel arm) | WIRED | `printf ... | write_file_atomic 0644 /etc/locale.conf` at pkg.sh line 214 |
| `plugin/provisioner/30-nodejs.sh` | `plugin/lib/pkg.sh::nodesource_repo_paths` | idempotency gate iterates the family repo paths | WIRED | nodesource_repo_paths (×3 in 30-nodejs.sh) |
| `plugin/provisioner/30-nodejs.sh` | `plugin/lib/pkg.sh::nodesource_module_reset` | rhel-only AppStream defuse before install | WIRED | nodesource_module_reset (×2 in 30-nodejs.sh) |
| `plugin/provisioner/10-agent-user.sh` | `plugin/lib/pkg.sh::locale_ensure` | single verb call replaces the locale block | WIRED | locale_ensure C.UTF-8 at 10-agent-user.sh line 76 |
| `plugin/bin/agentlinux-install` | `plugin/lib/pkg.sh` | `. "$LIB_DIR/pkg.sh"` after distro_detect.sh | WIRED | Sourcing order: distro_detect(155) < pkg.sh(161) < idempotency(163) |
| `plugin/bin/agentlinux-install::run_purge` | `plugin/lib/pkg.sh::nodesource_repo_paths` | purge iterates the family repo paths | WIRED | `while IFS= read -r repo_file; do rm -f "$repo_file"; done < <(nodesource_repo_paths)` at agentlinux-install line 405–407 |
| `plugin/lib/detect/nodejs.sh` | `plugin/lib/pkg.sh::nodesource_repo_paths` | rhel NodeSource gate (substring + repo-file dual gate) | WIRED | nodesource_repo_paths called (×3) in detect/nodejs.sh; no hardcoded /etc/yum.repos.d path |
| `plugin/lib/detect/user.sh` | `detect::user_can_sudo_apt` | preserved JSON field name over branched probe binary | WIRED | can_sudo_apt variable/export/JSON field/accessor all present; probe branches to /usr/bin/dnf or /usr/bin/apt-get |

### Data-Flow Trace (Level 4)

Not applicable: Phase 18 delivers shell library functions and bash provisioner scripts, not components that render dynamic data from a data source. Verb dispatch correctness is verified by bats PATH-stub tests which intercept and record the actual tool calls.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| distro_detect accepts almalinux 9 | `bats tests/bats/18-distro-detect.bats` | 15/15 pass | PASS |
| distro_detect rejects rocky/rhel/centos/fedora | bats tests 9–12 | all pass | PASS |
| pkg.sh verbs dispatch to dnf/rpm on rhel | `bats tests/bats/18-pkg-dispatch.bats` | 20/20 pass | PASS |
| detect/nodejs.sh classifies EL9 Node by real source | `bats tests/bats/18-detect-el9.bats` | 7/7 pass | PASS |
| shellcheck on all 9 modified files | `shellcheck --severity=warning <files>` | exit 0 | PASS |
| No apt-get/dpkg in provisioners or entrypoint | `grep -rn 'apt-get\|dpkg' plugin/provisioner/ plugin/bin/agentlinux-install` | 0 matches | PASS |
| pkg.sh sourcing order correct | `awk '/distro_detect/{d=NR} /pkg.sh/{p=NR} /idempotency/{i=NR} END{exit !(d<p && p<i)}'` | exit 0 | PASS |
| No ID_LIKE in plugin/ | `grep -rn 'ID_LIKE' plugin/` | 0 matches | PASS |
| No pkg_install curl in rhel arm | `grep -rn 'pkg_install curl' plugin/` | 0 matches | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| EL-01 | 18-01, 18-06 | distro_detect.sh recognizes almalinux 9, exports AGENTLINUX_DISTRO_FAMILY, ID-exact matching, escape-hatch seeds family | SATISFIED | distro_detect.sh code + bats 1–15 green; ADR-017 documents decision |
| EL-02 | 18-02, 18-04, 18-06 | pkg.sh dispatch layer; all ~13 apt-get/dpkg call sites route through verbs | SATISFIED | pkg.sh 9 verbs confirmed; 0 residual apt-get in provisioners/entrypoint; bats 16–35 green |
| EL-03 | 18-03 | Node 22 via NodeSource RPM; AppStream module defused; RT-01 preserved; no curl install on rhel | SATISFIED | nodesource_setup→rpm.nodesource.com; nodesource_module_reset defined; node_major RT-01 check preserved; no pkg_install curl; bats 23–25 green |
| EL-04 | 18-03 | C.UTF-8 via /etc/locale.conf on EL9; no locale-gen; locale -a gate preserved | SATISFIED | locale_ensure rhel arm writes /etc/locale.conf via write_file_atomic; no locale-gen in provisioners; bats 30–32 green |
| EL-05 | 18-03 | sudoers drop-in via pkg_install sudo; visudo-gated install/validate logic unchanged | SATISFIED | pkg_install sudo in 20-sudoers.sh; drop-in logic and ensure_dir /etc/sudoers.d intact; bats 33 green |
| EL-07 | 18-05 | brownfield detection EL9 arm; rpm dual-gate; AppStream distinct class; can_sudo_apt preserved | SATISFIED | detect/nodejs.sh rhel arm confirmed; nodesource_repo_paths lockstep; read-only; can_sudo_apt preserved; bats 36–42 green |

**Orphaned requirements check**: EL-06 and EL-08 map to Phase 20 in REQUIREMENTS.md traceability table — correctly out of scope for Phase 18.

### Anti-Patterns Found

No anti-patterns detected.

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | — |

Scans run on all 9 modified files: no TODO/FIXME/HACK/PLACEHOLDER, no `return null`/`return []`/`return {}`, no stubs, no hardcoded empty data flowing to rendered output.

### Human Verification Required

None. All Phase 18 must-haves are code properties verifiable programmatically on the dev host. Live EL9 acceptance is deferred to Phase 19/20 per roadmap.

### Gaps Summary

No gaps. All five observable truths are VERIFIED at the code-property level required for Phase 18:

- The `AGENTLINUX_DISTRO_FAMILY` abstraction exists, is correctly populated by `distro_detect.sh`, and is wired into every downstream consumer.
- `pkg.sh` provides all 9 verbs, each branching correctly on AGENTLINUX_DISTRO_FAMILY.
- All ~13 prior apt-get/dpkg/locale-gen call sites have been replaced by pkg.sh verb calls; none remain outside pkg.sh's debian arm.
- The curl-installer pre-gate is in lockstep.
- The brownfield detection layer has EL9 rpm arms with the can_sudo_apt contract preserved.
- All 42 bats unit tests are green; shellcheck is clean on all 9 files.

Three deferred items (live EL9 run, live Node 22 install, exact %{RELEASE} string) are explicitly Phase 19/20 scope per REQUIREMENTS.md traceability (EL-03/EL-04/EL-05 live acceptance → Phase 19/20 substrate).

---

_Verified: 2026-06-28_
_Verifier: Claude (gsd-verifier)_
