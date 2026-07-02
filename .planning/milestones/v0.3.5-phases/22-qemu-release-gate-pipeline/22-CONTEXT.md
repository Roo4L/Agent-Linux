# Phase 22: QEMU Release-Gate + Pipeline — Context

**Gathered:** 2026-06-29
**Status:** In progress (author-now-validate-via-CI; QEMU unavailable locally)
**Mode:** Locked decisions from REQUIREMENTS/ROADMAP; the EL9 specifics come from
22-RESEARCH.md (QEMU cannot run on this box — no qemu binary, no /dev/kvm).

<domain>
## Phase Boundary

Prove the EL9 port once on a real AlmaLinux 9 QEMU cloud-image VM (systemd +
enforcing SELinux + cloud-init), wire the AlmaLinux QEMU + Docker arms into the
release pipeline, and gate the v0.3.5 tag on both being green — with AGT-02
zero-EACCES `claude update` on the real guest as the milestone-close gate.
Requirements: HARN-02, PAR-02, REL-01.

In scope:
- **HARN-02:** `tests/qemu/boot.sh almalinux-9` boots a pinned dated AlmaLinux 9
  GenericCloud qcow2 with a checksum guard that asserts **≥1 row actually matched**
  (a flipped-byte corruption test must make the run exit non-zero), the EL9 cloud-init
  seed, family-correct SSH (almalinux@ + sudo / sshd unit), and runs the full bats
  suite in the guest. Add the `almalinux-9` arm to nightly-qemu.yml + release.yml gate-3.
- **PAR-02:** AGT-02 passes on the real EL9 guest — `claude update` zero-EACCES /
  no-sudo, monotonic bump, live CDN. Milestone-close gate. Ubuntu AGT-02 unchanged.
- **REL-01:** `release.yml` blocks the v0.3.5 tag until `almalinux-9` passes BOTH the
  Docker matrix gate (flip gate-2 from experimental to hard) AND the QEMU release gate
  (new gate-3 almalinux-9 arm). Ubuntu gates + pinned-combo gate unchanged.

Out of scope: nothing deferred — this is the milestone exit.

## Constraint: QEMU not local
QEMU/KVM is absent on the dev box (no qemu-system-x86_64, no /dev/kvm). CI runs
QEMU on `ubuntu-24.04` GitHub runners (nightly-qemu + release gate-3 install
`qemu-system-x86` + a KVM udev rule). So: author here, validate in CI.
**The gate-2/gate-3 hard-flip happens only AFTER CI proves the EL9 QEMU row green**
(user decision 2026-06-29); checking with the user before opening the milestone PR.
</domain>

<decisions>
## Locked
- SELinux stays enforcing on the guest; green-with-permissive is a false pass.
- Pinned DATED image (not `-latest`); checksum verified with ≥1-row-matched + a
  flipped-byte corruption self-test.
- Preserve Ubuntu QEMU rows byte-for-equivalent (family dispatch in boot.sh).
- AGT-02 on the real EL9 guest is the milestone-close gate (ADR-007: Docker alone
  disqualified).

## Claude's discretion
boot.sh generalization tactic (family dispatch on the target arg), the EL9
cloud-init seed (root-vs-almalinux user model per 22-RESEARCH), and whether bats
comes from EPEL or the bundled node_modules/bats.
</decisions>

<code_context>
## Existing harness (the Ubuntu analog to generalize)
- `tests/qemu/boot.sh` — Ubuntu-only: arg→version, jammy/noble/resolute codename
  map, `ubuntu-...-cloudimg-amd64.img`, `sha256sum --ignore-missing --check`
  (does NOT assert ≥1 matched — the gap HARN-02 closes), root@localhost SSH,
  in-guest installer + bats over SSH.
- `tests/qemu/cloud-images.txt` — `<version> <img-url> <sha256sums-url>` rows.
- `tests/qemu/cloud-init/{user-data,meta-data}` — root pubkey seed + bats/jq + `ssh`.
- `.github/workflows/nightly-qemu.yml` + `release.yml` gate-3-qemu — matrix
  `ubuntu: [22.04,24.04,26.04]` → `boot.sh ${{ matrix.ubuntu }}`. release.yml
  gate-2-docker already has almalinux-9 but EXPERIMENTAL (the comment says Phase 22
  makes it a hard gate).

## Precedent
Phase 19/20 Docker EL9 work: family dispatch, `almalinux` user model, sshd unit,
dnf, enforcing-SELinux + guarded restorecon. boot.sh's EL9 arm mirrors that.
</code_context>
