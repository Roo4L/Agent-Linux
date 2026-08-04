# Phase 6 Requirement Coverage Audit (TST-07 phase-close)

**Date:** 2026-04-20
**Auditor:** behavior-coverage-auditor rubric applied inline per ADR-010 + 02-05/04-07/05-04 precedent (Task-tool subagent dispatch unavailable on executor host; mechanical grep over tests/bats/ + .github/workflows/ + docs-presence per the rubric in `.claude/agents/behavior-coverage-auditor.md`).
**Scope:** Phase 6 — Distribution + Release Pipeline — 6 requirement IDs.

## Phase 6 requirements (from `.planning/REQUIREMENTS.md` + `.planning/ROADMAP.md`)

| ID       | Owning Plan | Test Type      | Status       |
| -------- | ----------- | -------------- | ------------ |
| INST-03  | 06-02       | bats (3 @tests) + CI-gate (release.yml publish sha256 sibling) | COVERED (bats) |
| CAT-05   | 06-01       | bats (2 @tests) + CI-gate (release.yml publish catalog-*.json) | COVERED (bats) |
| TST-03   | 06-03       | CI-gate (nightly-qemu.yml comment citation) + tests/qemu/boot.sh | COVERED (CI-gate) |
| TST-05   | 06-04 + 05-01 | bats selector (51-*.bats) invoked by release.yml gate-2-docker + gate-3-qemu | COVERED (bats-via-gate) |
| TST-08   | 06-04       | CI-gate (release.yml gate-4-pinned-combo) | COVERED (CI-gate) |
| DOC-01   | 06-05       | docs-presence (README.md + docs/STABILITY-MODEL.md) | COVERED (docs-gate) |

## Coverage detail per ID

### INST-03 — SHA256-verified curl-pipe-bash installer

**Owner:** Plan 06-02.
**Bats coverage:** `tests/bats/60-curl-installer.bats` — 3 `@test "INST-03: ...` tests:

1. `INST-03: install.sh is wrapped in main(){}; main "$@" (partial-download safety — Pitfall 1)` — AST-style check that install.sh has exactly one `main() {` definition and the last non-empty line is `main "$@"`.
2. `INST-03: good SHA256 -> install.sh extracts + execs agentlinux-install (fake-fixture happy path)` — end-to-end happy path.
3. `INST-03: tampered SHA256 -> install.sh aborts with clear error, no extraction (T-06-02)` — tamper-fails-fast, no extraction side-effects.

**CI-gate citation:** `.github/workflows/release.yml:267` publishes `agentlinux-*.tar.gz.sha256` as a required release sibling (the curl-installer's verification input).

**Status:** COVERED. No action needed.

### CAT-05 — Release catalog snapshot + byte-stability

**Owner:** Plan 06-01.
**Bats coverage:** `tests/bats/10-installer.bats` — 2 `@test "CAT-05: ...` tests:

1. `CAT-05: catalog snapshot staged at /opt/agentlinux/catalog/<version>/catalog.json` — file-presence + jq-parseable shape check.
2. `CAT-05: staged catalog is byte-stable against tarball source (Pitfall 8 anti-drift)` — asserts the staged copy is byte-identical to the source in the tarball (no jq-reformat drift).

**CI-gate citation:** `.github/workflows/release.yml:268` publishes `catalog-*.json` as a required release sibling.

**Status:** COVERED. No action needed.

### TST-03 — QEMU release-gate harness

**Owner:** Plan 06-03.
**CI-gate citation:** `.github/workflows/nightly-qemu.yml:2` — `# Phase 6 Plan 06-03 Task 3. Nightly QEMU release-gate harness (TST-03).` The workflow invokes `tests/qemu/boot.sh` against Ubuntu 22.04 + 24.04 on schedule and on-demand (`workflow_dispatch`). No bats @test cites TST-03 directly because TST-03 is pipeline-level: the gate is "the QEMU harness exists, boots cleanly, SSH-ins, runs the installer, and runs bats inside the guest." Cross-verification of the in-guest bats result is how the gate fails — but the gate identity is the workflow run, not a bats @test.

**Acceptable per auditor rubric:** CI-gate citation is an accepted coverage form for pipeline-level requirements (`.claude/agents/behavior-coverage-auditor.md` §"what to look for" — "Exclude IDs that are not bats-verifiable. TST-01..07 are satisfied by the existence of the test harness itself").

**Status:** COVERED (CI-gate). Runtime verification (first real CI run exits 0 on both Ubuntu versions) deferred per `06-VALIDATION.md` §Manual-Only Verifications row 2.

### TST-05 — AGT-02 blocking release gate (Docker + QEMU)

**Owners:** Plan 05-01 (canonical bats authoring) + Plan 06-04 (blocking-gate wiring).
**Bats coverage:** `tests/bats/51-agt02-release-gate.bats` — 1 `@test "AGT-02 (release-gate): claude update exits 0 with zero EACCES/permission-denied lines"`. (File renamed with `51-` prefix specifically so `bats tests/bats/51-*.bats` selects it for the release-gate step.)

**CI-gate citation:** `.github/workflows/release.yml:11, 13, 100, 113` — `gate-2-docker` (Docker × {22.04, 24.04}) and `gate-3-qemu` (QEMU × {22.04, 24.04}) both invoke the `51-*.bats` glob. AGT-02 red in either runtime blocks downstream `build` + `publish` via explicit `needs:` chain.

**Status:** COVERED (bats-via-gate). First real tag push exercises the blocking-chain end-to-end; deferred per `06-VALIDATION.md` §Manual-Only row 3.

### TST-08 — Pinned-catalog-combo release gate

**Owner:** Plan 06-04.
**CI-gate citation:** `.github/workflows/release.yml:186, 191, 198` — `gate-4-pinned-combo` installs the full pinned catalog combo on Ubuntu 24.04 Docker and runs `tests/bats/50-agents.bats + tests/bats/51-*.bats`. Distinct observable green box in the Actions UI; blocks `build` via `needs: [..., gate-4-pinned-combo]`. No bats @test cites TST-08 directly because TST-08 is the gate-run signal itself, not an in-test assertion — the test bodies exercised by the gate are the AGT-XX suite (already covered).

**Status:** COVERED (CI-gate). First real tag push exercises the gate; deferred per `06-VALIDATION.md` §Manual-Only row 3.

### DOC-01 — User-facing README + stability model

**Owner:** Plan 06-05 (this plan).
**Docs-gate citation:**

- `README.md` (138 lines) — one-paragraph pitch + Install + Verify + Uninstall + Stability model + Escape hatch + Requirements + Security + Links + About. Canonical install command verbatim: `curl -fsSL https://agentlinux.org/install.sh | sudo bash`. Version stamp `<!-- VERSION_START -->v0.3.0<!-- VERSION_END -->` on line 1.
- `docs/STABILITY-MODEL.md` (124 lines) — user-facing one-pager companion to ADR-011 with the three v0.3.0 pinned versions (2.1.98, 1.37.1, 1.59.1), the three divergence states, a worked `claude update` → `agentlinux upgrade` example, and the `agentlinux pin` escape-hatch shapes.

Both files satisfy VALIDATION 06-05-01 + 06-05-02 grep chain (Install/Verify/Uninstall/Stability sections present, VERSION stamp present, ADR-011 link present, no emojis).

**Status:** COVERED (docs-gate). DOC-01 is verified by file-presence + content-grep per the auditor rubric's "DOC-01..02 are verified by file-presence checks" exclusion line.

## Summary

Covered: **6 / 6** Phase 6 req IDs.
Uncovered: **0**.
Partial: **0**.

Breakdown by coverage form:

- bats @test coverage (req-ID in @test name): INST-03 (3), CAT-05 (2), TST-05 (1 via 51-*.bats selector) — 3 IDs.
- CI-gate citation (workflow-job name or inline step-name comment): TST-03, TST-08, plus the publish-sibling side of INST-03 + CAT-05 — 2 IDs exclusively CI-gate.
- docs-gate (file-presence + content-grep): DOC-01 — 1 ID.

**TST-07 gate: GREEN**

Every v0.3.0 Phase 6 requirement has at least one coverage signal that a reviewer can cite from a single file + line reference. Phase 6 is closeable.

## Deferred verifications (not blockers)

These are explicitly logged in `06-VALIDATION.md` §Manual-Only Verifications and do not gate phase close:

1. **Runtime verification of QEMU harness (TST-03).** First real CI run on `workflow_dispatch` or `schedule:` trigger. The harness's static gates are green; the boot-exit-zero assertion fires only on a real CI runner with `/dev/kvm`.
2. **End-to-end release-gate (TST-05, TST-08, INST-03, CAT-05).** First real `v0.3.0-rc1` tag push exercises gates 1..4 + build + publish (softprops/action-gh-release@v2.6.2). The YAML is actionlint-green; the runtime signal is the Actions UI.
3. **Real `curl | sudo bash` against a live GH Release asset (INST-03 user-facing).** Exercised by the first user after v0.3.0 publishes. Local and Docker-fixture runs of `packaging/curl-installer/install.sh` are green against mock fixtures.

The Plan 06-05 checkpoint that gates on a "Part C ship-smoke" exercise of the curl-installer on a fresh Ubuntu VM + `claude update` monotonicity check is also deferred to post-tag per the same precedent — there is no `v0.3.0-rc1` asset in GH Releases yet for the curl-installer to fetch. Part C is documented here for executability but not enforced for phase close.
