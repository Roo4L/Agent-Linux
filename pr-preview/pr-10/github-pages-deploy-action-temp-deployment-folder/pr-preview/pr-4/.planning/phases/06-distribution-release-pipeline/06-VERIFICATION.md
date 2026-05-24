---
phase: 06-distribution-release-pipeline
verified: 2026-04-20
status: passed
score: 6/6 requirements verified (all structural; runtime deferred to first tag push per 06-VALIDATION Manual-Only Verifications)
re_verification:
  initial: true
goal: >
  Users can install AgentLinux v0.3.0 via a verified curl-pipe-bash installer;
  the release pipeline produces reproducible tarball + sha256 + catalog snapshot
  on v* tag push; QEMU release-gate ensures fresh-cloud-image correctness;
  README + STABILITY-MODEL make the stability model legible to users.
requirements_verified:
  - id: INST-03
    status: verified
    evidence:
      - packaging/curl-installer/install.sh (196 lines, main() wrapper + SHA256 gate before tar extract + main "$@" last line)
      - tests/bats/60-curl-installer.bats (3 INST-03 @tests — wrapper invariant, good-sha happy path, tampered-sha fail-fast)
      - scripts/build-release.sh (produces dist/agentlinux-<tag>.tar.gz + .sha256 sidecar via GNU sha256sum)
      - .github/workflows/release.yml:289-291 (publish globs tarball + .sha256)
  - id: CAT-05
    status: verified
    evidence:
      - scripts/build-release.sh §9 (cp catalog.json → dist/catalog-<tag>.json — byte-for-byte, NOT jq)
      - scripts/build-release.sh §10 (build-time self-verify sha256(source) == sha256(snapshot))
      - tests/bats/10-installer.bats (2 CAT-05 @tests — staging presence + byte-stability)
      - .github/workflows/release.yml:245-249 + :292 (build-step presence gate + publish catalog-*.json)
  - id: TST-03
    status: verified_structural
    evidence:
      - tests/qemu/boot.sh (390 lines — real orchestrator: cloud-init render + qemu-system-x86_64 -enable-kvm + cloud-init status --wait + ssh + installer + bats)
      - tests/qemu/cloud-init/user-data (25 lines, __AGENTLINUX_QEMU_PUBKEY__ template)
      - tests/qemu/cloud-init/meta-data (2 lines)
      - tests/qemu/cloud-images.txt (manifest for Ubuntu 22.04 + 24.04 cloud images)
      - .github/workflows/nightly-qemu.yml (118 lines — matrix 22.04 + 24.04 + KVM udev + actions/cache@v4 + upload-artifact on failure)
    deferred: runtime exit-0 on both Ubuntu versions — first CI run per 06-VALIDATION Manual-Only row 2
  - id: TST-05
    status: verified_structural
    evidence:
      - tests/bats/51-agt02-release-gate.bats (file present — runs inside both Docker and QEMU harnesses)
      - .github/workflows/release.yml gate-2-docker (runs tests/docker/run.sh × {22.04, 24.04} — includes 51-*.bats)
      - .github/workflows/release.yml gate-3-qemu (runs tests/qemu/boot.sh × {22.04, 24.04} — includes 51-*.bats)
      - explicit needs: chain so AGT-02 red in either runtime blocks downstream build + publish
    deferred: end-to-end blocking-gate exercise on real tag push per 06-VALIDATION Manual-Only row 3
  - id: TST-08
    status: verified_structural
    evidence:
      - .github/workflows/release.yml gate-4-pinned-combo (bash tests/docker/run.sh ubuntu-24.04 — full pinned catalog + 50-agents.bats + 51-*.bats)
      - tests/bats/50-agents.bats (covers all 3 agents — claude-code 2.1.98, gsd 1.37.1, playwright 1.59.1)
      - distinct observable green box in Actions UI; needs: gate-3-qemu; build: needs: gate-4-pinned-combo
    deferred: end-to-end release-gate exercise on first tag push per 06-VALIDATION Manual-Only row 3
  - id: DOC-01
    status: verified
    evidence:
      - README.md (138 lines — Install §14, Verify §39, Uninstall §52, Stability model §66; version stamp line 1)
      - docs/STABILITY-MODEL.md (124 lines — TL;DR → ADR-011 link §3, v0.3.0 pins 2.1.98/1.37.1/1.59.1, three divergence states, worked claude update example, agentlinux pin escape hatch)
      - ADR-011 cross-link verified: line 3 + line 119 of STABILITY-MODEL.md
invariants_rechecked:
  - invariant: "No 'sudo npm install -g' anywhere in runtime code"
    status: passed
    detail: "Grep in plugin/ only matches documentation comments (plugin/lib/as_user.sh:3, plugin/provisioner/10-agent-user.sh:77,100) — all describe what NOT to do. Zero actual invocations."
  - invariant: "No wrapper shims at /usr/local/bin/ pointing to agent-owned binaries"
    status: passed
    detail: "Grep for 'ln|cp|install .* /usr/local/bin/' in plugin/ returns zero matches. /usr/local/bin only appears in PATH strings (as a standard-location fall-through AFTER /home/agent/.npm-global/bin) — never as a destination for shim creation."
deferred_manual_only:
  - "Runtime exit-0 of tests/qemu/boot.sh on Ubuntu 22.04 + 24.04 (first CI run; GitHub Actions first-time KVM udev rule exercise)"
  - "End-to-end release-gate run on real v0.3.0-rc1 tag push (softprops/action-gh-release@v2.6.2 publish exercise)"
  - "Real curl | sudo bash against a live GH Release asset (post-publish smoke)"
  - "Cold-cache vs warm-cache QEMU runtime measurement (second nightly run)"
  - "Pinned-combo CI gate live exercise (first tag push)"
---

# Phase 6: Distribution + Release Pipeline — Verification Report

**Phase Goal** (per ROADMAP.md):
> Users can install AgentLinux v0.3.0 via a verified curl-pipe-bash installer;
> the release pipeline produces reproducible tarball + sha256 + catalog snapshot
> on `v*` tag push; QEMU release-gate ensures fresh-cloud-image correctness;
> README + STABILITY-MODEL make the stability model legible to users.

**Status:** passed (all 6 requirements have concrete in-codebase evidence; runtime-only manual items already logged in 06-VALIDATION.md §Manual-Only Verifications).

## Goal Achievement Summary

Phase 6 delivers a complete, reviewable distribution surface for AgentLinux v0.3.0. The curl-pipe-bash installer (`packaging/curl-installer/install.sh`) is hardened with `main() { }; main "$@"` partial-download safety, HTTPS-only GitHub Releases URLs, regex-gated env overrides, and a SHA256 sidecar gate that runs BEFORE `tar -xzf`. The `scripts/build-release.sh` script produces a reproducible tarball (SOURCE_DATE_EPOCH + `--sort=name` + `gzip -n` + pnpm-bookkeeping exclusions → byte-identical across re-runs on same HEAD) plus a GNU sha256sum sidecar plus a byte-for-byte catalog snapshot (`cp`, not `jq .`, with build-time self-verify). The `.github/workflows/release.yml` orchestrates a 7-job pipeline (resolve → gate-1-precommit → gate-2-docker × 2 → gate-3-qemu × 2 → gate-4-pinned-combo → build → publish) that blocks on any red gate via explicit `needs:` chaining, and `softprops/action-gh-release@v2.6.2` (Node-20 pin) publishes the tarball + .sha256 + catalog-<tag>.json as GitHub Release assets only on real `v*` tag push. The QEMU release-gate harness (`tests/qemu/boot.sh` + cloud-init templates + `nightly-qemu.yml`) boots fresh cloud images under KVM, runs cloud-init + installer + bats inside the guest, and uploads serial.log artifacts only on failure. The user-facing README and `docs/STABILITY-MODEL.md` document the one-command install, SHA256 trust story, curated-combo semantics, and the `agentlinux pin` / `agentlinux upgrade` escape hatches with the v0.3.0 pinned versions cited verbatim. All six Phase 6 requirements have concrete evidence at real file paths; every structural gate that can be checked without a live CI runner is green.

## Must-Haves Matrix

### 1. INST-03 — SHA256-verified curl-pipe-bash installer

| Expected                                              | Status     | Evidence (file:line) |
| ----------------------------------------------------- | ---------- | -------------------- |
| `packaging/curl-installer/install.sh` exists          | ✓ VERIFIED | `packaging/curl-installer/install.sh` (196 lines, mode 0755) |
| `main()` wrapper around full body                     | ✓ VERIFIED | `install.sh:115` (`main() {`) + `install.sh:196` (`main "$@"` as last non-empty line) |
| SHA256 gate BEFORE tar extraction                     | ✓ VERIFIED | `install.sh:171` (`sha256sum -c "${tarball}.sha256"`) precedes `install.sh:182` (`tar --extract --gzip ...`) |
| `tests/bats/60-curl-installer.bats` ≥3 @tests         | ✓ VERIFIED | Three `@test "INST-03: ..."` at lines 85, 106, 126 (wrapper shape, good-sha happy path, tampered-sha fail-fast) |
| `scripts/build-release.sh` produces `.tar.gz` + `.sha256` sidecar | ✓ VERIFIED | `scripts/build-release.sh:262-272` (tar → gzip -n pipe) + `scripts/build-release.sh:281-284` (`sha256sum "<basename>" > "<basename>.sha256"`) |

### 2. CAT-05 — Catalog snapshot in release

| Expected                                                | Status     | Evidence (file:line) |
| ------------------------------------------------------- | ---------- | -------------------- |
| `scripts/build-release.sh` emits `dist/catalog-v<X.Y.Z>.json` | ✓ VERIFIED | `scripts/build-release.sh:294-295` (`cp plugin/catalog/catalog.json "$CATALOG_SNAPSHOT"`) |
| `tests/bats/10-installer.bats` has CAT-05 @tests        | ✓ VERIFIED | `tests/bats/10-installer.bats:179` + `:195` (staging presence + byte-stability) |
| `.github/workflows/release.yml` publishes `catalog-v<X.Y.Z>.json` via softprops | ✓ VERIFIED | `release.yml:292` (`dist/catalog-*.json` in `files:` glob) + `release.yml:245` (`test -s dist/catalog-${TAG}.json` build-step presence gate) |

### 3. TST-03 — QEMU release-gate harness

| Expected                                                          | Status     | Evidence (file:line) |
| ----------------------------------------------------------------- | ---------- | -------------------- |
| `tests/qemu/boot.sh` real orchestrator (cloud-init + qemu + ssh + installer + bats) | ✓ VERIFIED | `tests/qemu/boot.sh` (390 lines; references: `cloud-localds:232`, `qemu-system-x86_64:247`, `cloud-init status --wait:287`, `plugin/bin/agentlinux-install:356`, `bats tests/bats/:370`) |
| `tests/qemu/cloud-init/user-data` + `meta-data` exist              | ✓ VERIFIED | `tests/qemu/cloud-init/user-data` (25 lines, `__AGENTLINUX_QEMU_PUBKEY__` template) + `tests/qemu/cloud-init/meta-data` (2 lines) |
| `.github/workflows/nightly-qemu.yml` populated (matrix + KVM + cache) | ✓ VERIFIED | `nightly-qemu.yml` (118 lines): matrix `['22.04', '24.04']`:33-34, KVM udev rule:67-76, `actions/cache@v4`:94-101, `bash tests/qemu/boot.sh ${{ matrix.ubuntu }}`:105, artifact-on-failure:111-118 |
| Runtime exit-0 gates explicitly deferred to first CI run          | ⏸ DEFERRED | Per `06-VALIDATION.md` §Manual-Only Verifications row 2 |

### 4. TST-05 — AGT-02 release-gate in CI

| Expected                                                    | Status     | Evidence (file:line) |
| ----------------------------------------------------------- | ---------- | -------------------- |
| `tests/bats/51-agt02-release-gate.bats` exists              | ✓ VERIFIED | `tests/bats/51-agt02-release-gate.bats` (present, 4.6 KB — authored by Plan 05-01) |
| `release.yml` includes a gate that runs this file           | ✓ VERIFIED | `release.yml:113` (gate-2-docker runs `tests/docker/run.sh ${{ matrix.ubuntu }}` which executes 51-*.bats) + `release.yml:171` (gate-3-qemu runs `tests/qemu/boot.sh` which executes 51-*.bats inside the guest); explicit `needs:` chain (gate-2 → gate-3 → gate-4 → build → publish) ensures AGT-02 red blocks publish |

### 5. TST-08 — Pinned-combo release-gate

| Expected                                                          | Status     | Evidence (file:line) |
| ----------------------------------------------------------------- | ---------- | -------------------- |
| `release.yml` gate runs `50-agents.bats` against pinned catalog   | ✓ VERIFIED | `release.yml:192-199` (gate-4-pinned-combo runs `bash tests/docker/run.sh ubuntu-24.04` which installs pinned catalog combo via Phase 4+5 provisioners and runs 50-agents.bats + 51-*.bats) |
| Verifies all 3 agents (claude-code, gsd, playwright) installable with pinned versions | ✓ VERIFIED | `tests/bats/50-agents.bats` covers claude-code 2.1.98, gsd 1.37.1, playwright 1.59.1 (pinned_version read via jq at runtime from catalog snapshot) |

### 6. DOC-01 — README + STABILITY model

| Expected                                                    | Status     | Evidence (file:line) |
| ----------------------------------------------------------- | ---------- | -------------------- |
| `README.md` has Install / Verify / Uninstall / Stability sections | ✓ VERIFIED | `README.md:14` `## Install` + `:39` `## Verify` + `:52` `## Uninstall` + `:66` `## Stability model` |
| `<!-- VERSION_START -->v0.3.0<!-- VERSION_END -->` stamp present | ✓ VERIFIED | `README.md:1` — exact match |
| `docs/STABILITY-MODEL.md` exists and cross-links ADR-011    | ✓ VERIFIED | `docs/STABILITY-MODEL.md` (124 lines); ADR-011 link at `:3` (TL;DR blockquote) and `:119` (Related §) |

## Invariants Re-Checked

| Invariant                                                            | Check                                                                                | Result |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------ | ------ |
| No `sudo npm install -g` anywhere in runtime code                    | `grep -r "sudo\\s\\+npm\\s\\+install\\s\\+-g" plugin/`                                 | ✓ PASS — 3 matches, all in comments/docstrings describing what NOT to do (`plugin/lib/as_user.sh:3`, `plugin/provisioner/10-agent-user.sh:77,100`). Zero invocations. |
| No wrapper shims at `/usr/local/bin/` pointing to agent-owned binaries | `grep -E "ln\\s+.*\\s+/usr/local/bin/\|cp\\s+.*\\s+/usr/local/bin/\|install.*\\s+/usr/local/bin/" plugin/` | ✓ PASS — zero matches. `/usr/local/bin` appears in PATH strings only (after `/home/agent/.npm-global/bin`, per Pitfall 4 ordering comment) — never as a destination. |

## Requirements Coverage

All 6 Phase 6 requirements declared in `06-VALIDATION.md` have concrete evidence:

- **INST-03**: 3 bats @tests + sha256 sibling in publish glob → COVERED
- **CAT-05**: 2 bats @tests + catalog snapshot in publish glob → COVERED
- **TST-03**: QEMU orchestrator + cloud-init templates + nightly-qemu.yml → COVERED (structural; runtime deferred)
- **TST-05**: 51-*.bats runs in both gate-2-docker and gate-3-qemu → COVERED (structural; tag-push deferred)
- **TST-08**: gate-4-pinned-combo invokes 50-agents.bats + 51-*.bats → COVERED (structural; tag-push deferred)
- **DOC-01**: README + STABILITY-MODEL.md with all required sections + version stamp + ADR-011 cross-links → COVERED

The deferred items are explicitly enumerated in `06-VALIDATION.md` §Manual-Only Verifications — they cannot be verified programmatically without a real CI runner or a real tag push. The 06-05-AUDIT.md and 06-01..04 SUMMARYs document this expectation; the deferred scope matches the VALIDATION contract.

## Anti-Patterns Found

None. All phase artifacts are substantive (8.6 KB install.sh, 16.1 KB build-release.sh, 15.6 KB boot.sh, 11.8 KB release.yml, 4.6 KB nightly-qemu.yml, 5.5 KB README.md, 5.4 KB STABILITY-MODEL.md). No TODO/FIXME placeholder content; no stub implementations; no hollow-prop patterns. Review loops for every plan (bash-engineer + security-engineer + qa-engineer + catalog-auditor + technical-writer + fact-checker per CLAUDE.md §Review Loop) returned zero actionable findings across all five plans.

## Human Verification Required

The following items require a human to trigger because the local test environment has no KVM/CI runner and no real GH Release assets:

1. **First CI run of `nightly-qemu.yml` on both Ubuntu matrix legs** — per `06-VALIDATION.md` Manual-Only row 2. Expected: both legs exit 0; AGT-02 bats output in the "QEMU boot + installer + bats" step log. Observable via `gh workflow run nightly-qemu.yml` + Actions UI.
2. **First real `v0.3.0-rc1` tag push** — per `06-VALIDATION.md` Manual-Only row 3. Expected: all 4 gates + build + publish green; GitHub Release page shows tarball + .sha256 + catalog-v0.3.0-rc1.json (+ optional .deb); `softprops/action-gh-release@v2.6.2` publishes successfully.
3. **Real `curl -fsSL https://agentlinux.org/install.sh | sudo bash` on a fresh Ubuntu VM** — per `06-VALIDATION.md` Manual-Only row 1. Expected: SHA256 verified, tarball extracted, installer runs, `agentlinux list` shows 3 agents. Becomes executable once v0.3.0-rc1 publishes.

All three are logged as manual-only in VALIDATION and do NOT block phase close — they are the shipping event itself.

## Gaps Summary

No gaps found. Every must-have has concrete evidence at real file paths; every structural gate is green; every deferred item is explicitly scoped to manual runtime-only verifications (first CI run + first tag push) already logged in `06-VALIDATION.md`. The invariants grep cleanly. Phase 6 is ready to ship.

## Final Verdict

**passed**

Phase 6 structurally delivers the v0.3.0 distribution surface: curl-pipe-bash installer + reproducible release tarball + SHA256 sidecar + catalog snapshot + 4-gate CI pipeline (precommit → Docker × 2 → QEMU × 2 → pinned-combo) + QEMU release-gate harness + user-facing README + stability-model documentation. All 6 Phase 6 requirements (INST-03, CAT-05, TST-03, TST-05, TST-08, DOC-01) have concrete evidence in-codebase. Runtime-only verifications are explicitly deferred to the first `v0.3.0-rc1` tag push and first CI run per `06-VALIDATION.md` §Manual-Only Verifications — this is the shipping event, not a gap.

VERIFICATION COMPLETE

---

_Verified: 2026-04-20_
_Verifier: Claude (gsd-verifier)_
