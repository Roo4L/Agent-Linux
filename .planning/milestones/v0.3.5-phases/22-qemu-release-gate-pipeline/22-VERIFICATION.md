# Phase 22 Verification — QEMU Release-Gate + Pipeline

**Verified (host-runnable parts):** 2026-06-29
**Verdict:** HARNESS AUTHORED + REVIEWED; CI validation PENDING (QEMU not local).

This phase is **not yet closeable**: its goal includes proving the EL9 port on a
real QEMU guest + the AGT-02 milestone-close gate, which can only run in CI.
This document records what IS verified now and what remains.

## Verified now (host-runnable)

| Check | Result |
|---|---|
| `verify_one_checksum` against BOTH real formats | PASS — Ubuntu binary-mode (`<hash> *name`) + AlmaLinux text-mode (`<hash>  name`) both verify; corruption rejected; missing-line rejected (HARN-02 ≥1-match gate); xfs≠ext4 field-exact anchor |
| `selftest_checksum_guard` (flipped-byte) | PASS — intact OK, corruption detected on every run |
| shellcheck `tests/qemu/boot.sh` | clean |
| Ubuntu boot.sh path unchanged | only the `case` selector + generalized IMG_NAME/checksum are new; SSH/install/bats flow identical |
| YAML parse (nightly-qemu, release) | OK |
| pre-commit (changed files) | all hooks pass |

## Review loop (4 reviewers)

- **bash-engineer — CRITICAL (FIXED):** the original two-space grep anchor would
  have regressed ALL THREE Ubuntu targets (Ubuntu SHA256SUMS is binary-mode
  `*name`, not two-space). Replaced with an awk field-exact match handling both
  modes — re-tested against both real formats.
- **qa-engineer — MEDIUM (FIXED):** "enforcing SELinux" was only implicit.
  Added a rhel-only `getenforce == Enforcing` assertion in boot.sh (the
  Docker EL9 row can't run enforcing, so this lives in the QEMU harness, not the
  shared bats suite). Plus LOW fixes: cloud-init `status: error` fast-fail
  (was spinning to the 300s deadline), python3-reliance note in the seed.
- **security-engineer — MEDIUM (DEFERRED, harness-wide):** image + CHECKSUM are
  fetched same-origin over TLS with no PGP verification of CHECKSUM(.asc). This
  gap is identical on the Ubuntu arm (no SHA256SUMS.gpg) — NOT EL9-specific, so
  it is a harness-wide hardening follow-up, not a Phase 22 blocker. LOW: hostfwd
  loopback-pinned (FIXED). Gate confirmed fails-closed in every ambiguous case.
- **ai-deslop — LOW (FIXED):** trimmed changelog prose, reconciled the gate-2 /
  gate-3 comments, dropped a redundant redirect.

## Remaining (CI-only — the actual milestone proof)

1. nightly-qemu `almalinux-9` arm GREEN = EL9 boots (systemd + enforcing SELinux
   + cloud-init), installer runs, full bats suite green in-guest incl. AGT-02
   (51-*.bats) and the restorecon-under-enforcement path. **HARN-02 + PAR-02.**
2. The REL-01 hard-flip: drop `experimental` from gate-2-docker + gate-3-qemu
   `almalinux-9` once (1) is green — done as ONE coordinated step.
3. Both require pushing the branch / opening the single milestone PR so CI runs —
   an outward-facing step gated on the user (per the 2026-06-29 decision).

## Deferred follow-ups (tracked, not blocking)

- **CHECKSUM.asc PGP verification** (harness-wide, Ubuntu + AlmaLinux) — add a
  pinned-key `gpg --verify` before `verify_one_checksum`. Security MEDIUM.
