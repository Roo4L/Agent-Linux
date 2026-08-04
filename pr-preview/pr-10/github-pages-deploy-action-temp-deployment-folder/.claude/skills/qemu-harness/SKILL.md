---
name: qemu-harness
description: Use when running the QEMU-based behavior-test suite locally or debugging the nightly-qemu workflow. Documents the download + cache of Ubuntu cloud images (22.04, 24.04), cloud-init seed generation, QEMU boot flow, SSH-into-guest pattern, bats-over-SSH execution, teardown, artifact collection, and how to add a new Ubuntu version. Docker-only testing is disqualified per ADR-007 — systemd, locale generation, and cloud-init paths require a real VM. Grows with Phase 6's full harness implementation.
---

# qemu-harness — QEMU test harness operation

**Status:** Skeleton. The real `tests/qemu/boot.sh` lands in Phase 6. This skill documents the target shape so Phase 6 has a starting point and so Phase 1's `nightly-qemu.yml` workflow knows what entrypoint to invoke. The `nightly-qemu.yml` workflow ships a guard that skips cleanly when `tests/qemu/boot.sh` is missing, so the skeleton-phase repo green-bars without this harness existing yet.

Authoritative spec: `docs/HARNESS.md` §1.3 (testing layers), §3 (Systems Access Inventory — row for Ubuntu cloud images names this skill as the P1 deliverable), §5.2 (skill table). Decision: **ADR-007 (Docker + QEMU harness; Docker-only is disqualified).** Requirements this skill helps satisfy: TST-03 (QEMU release gate), TST-05 (AGT-02 blocking release gate), and indirectly every BHV/AGT test because the release gate runs them.

## When to use this skill

Use when the task touches any file under:

- `tests/qemu/boot.sh` — the boot orchestrator (arrives Phase 6).
- `tests/qemu/cloud-init/user-data` / `meta-data` — cloud-init seed templates.
- `.github/workflows/nightly-qemu.yml` — the CI wrapper.
- Release-pipeline scripts that invoke the QEMU gate (Phase 6).
- Developer docs explaining how to run the QEMU suite locally.

Skip for Docker-harness work (`tests/docker/run.sh`) — that is the faster companion layer and does not need cloud images or SSH.

## Why QEMU, not Docker-only (ADR-007)

Docker false-positives mask real bugs. The classes Docker-only testing cannot catch:

- **systemd**: Docker containers have no systemd by default; `BHV-04` (agent user runs under `systemd User=agent`) is invisible.
- **Locale generation**: `locale-gen en_US.UTF-8` is a no-op inside Debian-style slim images; `BHV-01` UTF-8 assertions pass under conditions the real target won't have.
- **Cloud-init paths**: Real Ubuntu cloud images provision `/etc/cloud/cloud.cfg` and `/etc/ssh/sshd_config.d/`. Docker never runs cloud-init, so any installer code that assumes those paths behaves differently in prod.
- **Non-trivial UID allocation**: `useradd` in Docker usually lands at UID 1000 on an empty passwd; on a cloud image, `ubuntu` is already UID 1000 and the agent user picks up 1001 — a real-world drift that Docker hides.
- **SELinux / AppArmor**: Docker default profiles mask the real distro's MAC behavior.

ADR-007 locks this. **Docker tests run every PR (~90s per Ubuntu version); QEMU tests gate every release (~5min per run).** Both must be green before any tag.

## Target boot flow (`tests/qemu/boot.sh`)

1. **Download the Ubuntu cloud image** into a local cache dir (default `~/.cache/agentlinux/qemu/`):
   - `ubuntu-22.04-server-cloudimg-amd64.img`
   - `ubuntu-24.04-server-cloudimg-amd64.img`
   - Source: `https://cloud-images.ubuntu.com/releases/<version>/release/`
   - Skip download if cached file's SHA256 matches the upstream `SHA256SUMS` manifest. Never trust a cached image without SHA verification.
2. **Generate cloud-init seed ISO** from `tests/qemu/cloud-init/user-data` + `meta-data`:
   - `user-data` creates a root SSH keypair, installs openssh-server, opens port 22, and disables password auth.
   - The keypair is generated per-run into the cache dir; no private key is ever committed to the repo.
   - Built with `cloud-localds seed.iso user-data meta-data` (package: `cloud-image-utils`).
3. **Boot QEMU** (backgrounded):
   ```bash
   qemu-system-x86_64 \
     -cpu host -enable-kvm \
     -m 2048 -smp 2 \
     -drive file=<cached-image>,if=virtio,snapshot=on \
     -drive file=<seed.iso>,format=raw \
     -netdev user,id=n0,hostfwd=tcp::2222-:22 \
     -device virtio-net,netdev=n0 \
     -nographic -serial mon:stdio \
     &
   ```
   `snapshot=on` means writes never touch the cached image — no cache corruption between runs.
4. **Wait for SSH.** Poll `nc -z localhost 2222` with a timeout (default 300s). Fail loudly if the guest never comes up.
5. **scp the plugin tarball** into the guest (`/tmp/agentlinux.tar.gz`).
6. **Run the installer over SSH** (`ssh root@localhost -p 2222 'tar -xzf /tmp/agentlinux.tar.gz && ./plugin/bin/agentlinux-install'`).
7. **Run the bats suite over SSH** against the *installed* plugin.
8. **Collect artifacts** — installer log, bats output, any core dumps — into a local `tests/qemu/artifacts/<run-id>/` directory.
9. **Shutdown gracefully** (`ssh root@localhost -p 2222 poweroff`) and `wait` on the QEMU PID. Cleanup the seed ISO and the ephemeral SSH keypair.

## Adding a new Ubuntu version

Four touchpoints (kept in sync so new versions land atomically):

1. Add the image URL + SHA256 to `tests/qemu/cloud-images.txt` (Phase 6 will seed this file).
2. Extend `tests/qemu/boot.sh` with a new `--ubuntu <version>` branch.
3. Add a matrix entry in `.github/workflows/test.yml` (Docker) and `.github/workflows/nightly-qemu.yml` (QEMU).
4. Add a `tests/docker/Dockerfile.ubuntu-<version>` for the fast-path Docker mirror.

A version that works in Docker but not in QEMU (or vice versa) is a release-blocker bug, not a skip — that's the whole point of running both harnesses.

## Local prerequisites

Ubuntu host one-liner:

```bash
sudo apt install qemu-system-x86 cloud-image-utils openssh-client curl coreutils
```

Check KVM availability (`kvm-ok` from `cpu-checker`, or `test -e /dev/kvm`). Without KVM, QEMU falls back to TCG and boots take ~20-30× longer — fine for a one-off, impractical for CI.

GitHub Actions runners (ubuntu-22.04, ubuntu-24.04 images) ship with QEMU and KVM preinstalled; `nightly-qemu.yml` needs no extra `apt install` step for the standard hosts.

## Artifacts on failure

When any bats test fails inside the guest, `boot.sh` MUST:

- scp the installer log and bats output back to the host before poweroff.
- Keep the guest's `/var/log/syslog` + `/var/log/cloud-init.log` in the artifacts dir.
- Fail the harness with a non-zero exit so CI surfaces the red.

## Security hygiene (threat model)

- The per-run SSH keypair lives in the cache dir, mode 0600, never committed. Phase 6 must implement this; this skill names the requirement so Phase 6 cannot skip it.
- The cached cloud images are SHA256-verified against upstream `SHA256SUMS` before first boot and on every cache hit. A mismatch is a hard failure, not a warning.
- The QEMU guest is ephemeral (`snapshot=on`) and destroyed after the run. No state leaks between runs.

## Growth plan

- **Phase 6:** Writes the real `tests/qemu/boot.sh` and `tests/qemu/cloud-init/*`. This skill absorbs the concrete flags, the cloud-init template snippets, and the artifact-collection protocol.
- **Phase 6:** The release workflow (`.github/workflows/release.yml`) gates every tag on a green QEMU run (TST-03). This skill documents how the release workflow invokes `boot.sh` and what a red run looks like.
- **v0.4+:** When Fedora / Alma / Arch land as targets, this skill extends with their cloud-image URLs and any distro-specific cloud-init differences.

## Related

- `docs/HARNESS.md` §1.3 (testing layers — QEMU row), §3 (Systems Access — Ubuntu cloud images P1 action is this skill), §5.2 (skill table).
- ADRs: 007 (Docker + QEMU two-layer harness; Docker-only disqualified).
- Workflows: `.github/workflows/nightly-qemu.yml` (cron + dispatch), Phase 6 release workflow (gate).
- Subagents: `qa-engineer` (review of boot.sh + cloud-init), `security-engineer` (SHA verification, keypair hygiene).
- Sibling skills: `agentlinux-installer` (the installer run inside the guest), `behavior-test-contract` (the bats suite run over SSH).
