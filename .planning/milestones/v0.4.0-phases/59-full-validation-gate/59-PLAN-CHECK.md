# Phase 59 — Full Validation Gate: Plan Check

**Checked:** 2026-07-29
**Checker:** gsd-plan-checker (goal-backward, adversarial — FINAL milestone gate)
**Plans:** 59-01 (Wave 1), 59-02 (Wave 2), 59-03 (Wave 3) — 7 tasks
**Verdict:** ✅ **GO**

---

## Verdict Summary

The three plans deliver the phase goal. Every anchor claim was verified against
the live tree this session: `boot.sh:531` really runs the Bash entrypoint (the
GATE-02 gap); `13-reuse.bats:552` really carries the stale `type == "string"`
assertion while the on-disk schema emits `["string","null"]` (schemars
`Option<String>` at `schema_gen.rs:79`, drift-locked at :143); `51-*.bats:37-39`
is the isolated-invocation Bash false-green trap; `security-engineer.md` has no
`0440|sudoers` line; `.planning/research/` is absent yet `research` is an ALLOWED
durable dir (`check-planning-clean.sh:44`) with the byte-source at
`docs/research/v0.3.0/SUMMARY.md` present. The #1 risk (false GATE-02) and the #5
risk (cutover deletion) are both correctly handled. No blockers.

---

## Dimension Findings

### 1. Requirement coverage — PASS
GATE-01/02/03/04/05 each map to a concrete task with a real deliverable:
- GATE-01 → 59-01 T1 (13-reuse 32/32) + T2 (HRN-05 restore, HRN-06 rubric → harness green).
- GATE-02 → 59-02 T1 (boot.sh re-point + identity assert) + T2 (Docker-gate confirmation).
- GATE-03 → 59-03 T1 (coverage auditor → 59-COVERAGE.md, TST-07 GREEN).
- GATE-04 → 59-03 T2 (AGT-02 via run.sh default → zero-EACCES).
- GATE-05 → 59-03 T3 (59-GATE-DECLARATION.md, no-deletion, LEGACY_TS demo).
Matches ROADMAP `Requirements: GATE-02, GATE-03, GATE-04, GATE-01, GATE-05`.

### 2. THE #1 RISK — no false GATE-02 green — PASS (assertion has teeth)
59-02 T1 re-points the in-guest install from `bash plugin/bin/agentlinux-install`
(boot.sh:531) to the STAGED musl bin `plugin/bin/agentlinux provision --user
agent --yes`. The transport is sound: `build-release.sh` payload places the
static musl bin at `plugin/bin/agentlinux`, boot.sh already extracts the tarball
into `/opt/agentlinux-src` (:527-529), so the bin exists in-guest with no extra
scp. The provisioner-IDENTITY assertion (`readelf` no-PT_INTERP / `file`
statically-linked / `ldd` not-dynamic) fails the run non-zero on mismatch — a
silent revert to the Bash shell-script entrypoint (which is `#!`-prefixed ASCII,
not a static ELF) trips the guard. The assertion has real teeth: it discriminates
exactly the regression it must catch.

### 3. The 13-reuse #29 edit is spec-tracks-schema, NOT a weakening — PASS
Confirmed on disk: `schema.json` `compatibility_window.type == ["string","null"]`
(minLength 1), generated from `Option<String>` and byte-locked by
`schema_is_not_drifted`. Changing the schema to satisfy `type=="string"` would
(a) fail the drift-check and (b) make the field required — breaking the
`test_only entries MUST NOT carry it` invariant (13-reuse.bats:521-543, verified
present). The fix belongs in the test. The corrected predicate still asserts the
field IS the nullable-string union (not deleted / not `any type`) — it accepts
`["string","null"]` OR scalar `"string"` OR an array containing `"string"`, so it
remains a meaningful type assertion. Meaningful, not gutted.

### 4. GATE-04 false-green trap avoided — PASS
59-03 T2 runs `run.sh <distro> 51-agt02-release-gate` (NOT bare `bats 51-*.bats`).
run.sh's default provisions with the Rust musl `provision` at the top
(banner confirmed at run.sh:310, provision invocation at :337), creating the
`~agent/.npm-global/bin/agentlinux` symlink so the 51:37-39 Bash fallback does NOT
fire. The verify asserts the `run Rust provisioner (agentlinux provision)
[default]` banner appeared (`RUST-PROVISION-RAN`) — the "Rust path was actually
exercised" check has a concrete grep. Zero-EACCES asserted on the transcript.

### 5. GATE-05 — NO cutover deletion — PASS
Zero deletion tasks. Every mention of deletion in the plans is a RETAIN/no-delete
assertion. The 59-03 T3 verify positively guards the substrate:
`test -d plugin/cli && test -f plugin/bin/agentlinux-install` (both confirmed
present) and demonstrates the `AGENTLINUX_LEGACY_TS=1` rollback lever green. The
PROV-02 "retired at the Phase-59 entrypoint cutover" phrasing is correctly
reconciled (CONTEXT/ROADMAP win) as the POST-milestone step. Rollback intact.

### 6. Honest dev vs CI/QEMU/live-CDN split — PASS
No task claims a local full-Docker-matrix, full-QEMU, or live-CDN pass. Dev floor
= per-file bats (ubuntu-24.04 + almalinux-9) + coverage audit + AGT-02 smoke +
LEGACY_TS smoke; the full matrix/QEMU/live-CDN are explicitly documented as
CI/pipeline-gated (VALIDATION.md ⚠️ split honored; boot.sh dev verify is
`bash -n` + grep-asserts, not an in-guest QEMU run — no KVM in dev VM).

### 7. HRN-05 / HRN-06 fixes sound — PASS
HRN-05: RESTORE `.planning/research/SUMMARY.md` byte-identical to the present
`docs/research/v0.3.0/SUMMARY.md`; `research` is an ALLOWED durable dir
(check-planning-clean.sh:44 verified), so the restore survives merge — not a
merge-transient patch, not a test re-scope. (Research floated re-scope as
Option A2/Open-Q1; the planner resolved to RESTORE, which is the stronger,
invariant-preserving fix and is the master-shippable choice.) HRN-06: a genuine
`0440 root:root NOPASSWD` sudoers review line (ADR-012 surface) satisfying
`grep -qEi "0440|sudoers"` — a real review-surface addition, not a token string.
Neither edits a `tests/harness/*.bats` file.

### 8. Nyquist / deps / waves — PASS
Wave chain 0→1→2 sound: red-free suite (W1) precedes the matrix wiring (W2)
precedes the gate declaration (W3); depends_on is acyclic (01:[] → 02:[01] →
03:[01,02]). No 3-consecutive automated-verify gap — every task carries an
`<automated>` verify. No same-wave file collision (01 edits 13-reuse.bats +
SUMMARY.md + security-engineer.md; 02 edits boot.sh; 03 writes two new planning
docs). VALIDATION.md exists (Dimension 8e gate passes).

---

## Non-blocking notes (WARNING — optional)

- **W-1 (scope, minor):** 59-01 T1 runs `13-reuse` on 2 distros (ubuntu-24.04 +
  almalinux-9), not all 4. Acceptable — the schema/jq assertion is
  distro-invariant; the full 4-distro matrix is the CI floor. No action required.
- **W-2 (transport fallback):** 59-02 T1's `AGENTLINUX_LEGACY_TS` env forwarding
  through the ssh hop is flagged "if awkward, at minimum keep the Bash-entrypoint
  invocation present under the legacy branch." The rollback substrate survives
  either way; the softness is only about lever *parity*, not GATE-05 retention.
  Prefer full flag-forwarding but not a blocker.

---

## Recommendation

**GO.** All five gates are covered by concrete tasks with real, teeth-bearing
verifies; the two final-gate failure modes (false GATE-02 green, cutover
deletion) are both closed; the dev/CI split is honest. Proceed to
`/gsd-execute-phase 59`.
