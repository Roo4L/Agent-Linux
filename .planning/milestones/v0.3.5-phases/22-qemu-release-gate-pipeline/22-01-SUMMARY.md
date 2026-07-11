# Phase 22 Plan 01 — Summary

**Authored:** 2026-06-29
**Status:** Harness authored + reviewed + committed; CI validation + REL-01
hard-flip pending (QEMU not local — author-now-validate-via-CI).

## What shipped (committed on worktree-almalinux-support)

- `tests/qemu/boot.sh` — generalized Ubuntu-only → `{22.04,24.04,26.04,almalinux-9}`:
  TARGET/FAMILY/RELEASE dispatch, IMG_NAME from URL basename, family-selected
  cloud-init seed, root@ SSH for both families. **HARN-02 checksum guard:**
  `verify_one_checksum` (awk field-exact match, handles Ubuntu binary-mode +
  AlmaLinux text-mode, requires the pinned line → ≥1-match) + `selftest_checksum_guard`
  (flipped-byte self-test). Plus a rhel-only `getenforce == Enforcing` assertion
  and a cloud-init `status: error` fast-fail.
- `tests/qemu/cloud-images.txt` — pinned dated AlmaLinux 9 GenericCloud qcow2 + CHECKSUM.
- `tests/qemu/cloud-init/user-data.almalinux9` — EL9 seed (root pubkey, sshd, EPEL bats).
- `.github/workflows/nightly-qemu.yml` — matrix `ubuntu`→`target` incl almalinux-9 (hard arm).
- `.github/workflows/release.yml` gate-3-qemu — almalinux-9 as EXPERIMENTAL until CI green.

## Key facts (from 22-RESEARCH.md, live-verified)
- AlmaLinux CHECKSUM is GNU **text-mode**; Ubuntu SHA256SUMS is GNU **binary-mode**
  (`*name`) — the awk verifier handles both (the bash-engineer CRITICAL fix).
- AlmaLinux GenericCloud ships `PermitRootLogin yes` → root@ SSH works → no sudo
  divergence; SELinux **enforcing** by default → the in-guest suite re-confirms
  the Phase 20 restorecon path under real enforcement.
- bats is EPEL-only → installed via runcmd (not a mixed `packages:` transaction).

## Verification
Host-runnable parts all green (checksum guard 6/6 incl. both real formats,
shellcheck, YAML, pre-commit). The real EL9 QEMU proof + AGT-02 milestone-close
gate are CI-only — see 22-VERIFICATION.md.

## NOT done in this plan (the milestone close)
- nightly-qemu almalinux-9 GREEN in CI (the real EL9 boot + AGT-02 proof).
- REL-01 hard-flip (drop `experimental` from gate-2 + gate-3 almalinux-9) — one
  coordinated step after CI green.
- Opening the single milestone PR / cutting the v0.3.5 tag — outward-facing,
  user-gated.

## Deferred follow-up
- CHECKSUM.asc PGP verification (harness-wide hardening; Ubuntu + AlmaLinux).
