# Phase 22: QEMU Release-Gate + Pipeline — Research (AlmaLinux 9 row)

**Researched:** 2026-06-29
**Domain:** AlmaLinux 9 GenericCloud qcow2 in a QEMU/cloud-init CI harness (EL9 parity for the Ubuntu `tests/qemu/boot.sh` arm)
**Confidence:** HIGH — every answer below is sourced from the live AlmaLinux repo and the official `AlmaLinux/cloud-images` Packer/kickstart that *builds the actual image*, not from training data.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- SELinux stays **enforcing** on the guest; green-with-permissive is a false pass.
- Pinned **DATED** image (not `-latest`); checksum verified with **≥1-row-matched** + a flipped-byte corruption self-test.
- Preserve Ubuntu QEMU rows byte-for-equivalent (family dispatch in `boot.sh`).
- AGT-02 (`claude update` zero-EACCES) on the real EL9 guest is the milestone-close gate.

### Claude's Discretion
- `boot.sh` generalization tactic (family dispatch on the target arg).
- The EL9 cloud-init seed (root-vs-`almalinux` user model — this research recommends below).
- Whether `bats` comes from EPEL or the bundled `node_modules/bats`.

### Deferred Ideas (OUT OF SCOPE)
- Nothing deferred — this is the milestone exit.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HARN-02 | `boot.sh almalinux-9` boots a pinned dated qcow2, checksum-guards (≥1 row matched + flip test), EL9 cloud-init seed, family-correct SSH, runs bats in guest | Q1 (URL/pin), Q2 (checksum format), Q3 (SSH/user), Q4 (sshd unit), Q5 (bats), Q8 (cloud-init) |
| PAR-02 | AGT-02 passes on real EL9 guest | Q3 (root-level installer access), Q6 (SELinux enforcing intact) |
| REL-01 | release.yml blocks tag on EL9 Docker + QEMU green | All — the QEMU arm must be reproducible/pinned |
</phase_requirements>

## Summary

The AlmaLinux 9 GenericCloud qcow2 is a near drop-in analog to the Ubuntu cloud image for this harness. Three deltas matter, all confirmed authoritatively:

1. **Checksum format is GNU `sha256sum`, NOT BSD.** The `CHECKSUM` file next to the image is plain `<hash>  <filename>` lines — `sha256sum -c` consumes it directly, exactly like Ubuntu's `SHA256SUMS`. No reformat needed. (The widely-repeated "AlmaLinux uses BSD `SHA256 (file) = hash`" claim is **false for the current EL9 cloud CHECKSUM** — verified against the live file.)
2. **systemd unit is `sshd` (not `ssh`)**, enabled by default, and **root key-based SSH works out of the box** — the image's kickstart explicitly drops `PermitRootLogin yes`. The existing root-pubkey cloud-init seed ports over unchanged except `enable --now ssh` → `enable --now sshd`.
3. **`bats` is EPEL-only** (not in BaseOS/AppStream). Either enable `epel-release` *before* `bats` (cloud-init `packages:` installs in one transaction, so a single mixed list fails), or sidestep EPEL with the bundled `node_modules/bats`. `jq` is preinstalled in the GenericCloud image.

SELinux is **enforcing** by default (kickstart `selinux --enforcing`), root is on a plain XFS partition with no LVM so cloud-init `growpart`+`resizefs` resize the overlay normally, and cloud-init is preinstalled with `cloud-init status --wait` support.

**Primary recommendation:** Keep the existing root-pubkey cloud-init seed; change only `ssh`→`sshd`, the image/checksum URLs, and the bats sourcing. Verify the dated image with `sha256sum --ignore-missing --check CHECKSUM` (works as-is — same call shape as Ubuntu, just point at `CHECKSUM` instead of `SHA256SUMS`).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Image download + pin | Harness host (`boot.sh`) | AlmaLinux repo CDN | Host fetches the dated qcow2 + CHECKSUM |
| Integrity gate | Harness host | — | `sha256sum -c` runs host-side before boot |
| Guest provisioning | cloud-init (in guest) | seed ISO from host | user-data/meta-data injected via `cloud-localds` |
| Root-level install + bats | Guest (over SSH) | — | installer + bats run inside the booted VM |

## Findings (the 8 questions)

### Q1 — GenericCloud image URL (pinned, dated)

**Directory:** `https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/` [VERIFIED: live curl 2026-06-29]

**Current dated x86_64 GenericCloud qcow2 (XFS root — the standard variant):**
```
https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-9.8-20260526.x86_64.qcow2
```
Filename pattern: `AlmaLinux-9-GenericCloud-<minor>-<YYYYMMDD>.x86_64.qcow2`. The current point release is **9.8**, image build dated **20260526**. [VERIFIED: directory listing]

Variants present in the dir:
- `AlmaLinux-9-GenericCloud-9.8-20260526.x86_64.qcow2` ← **use this** (XFS root, default)
- `AlmaLinux-9-GenericCloud-ext4-9.8-20260526.x86_64.qcow2` (ext4 root variant)
- `AlmaLinux-9-GenericCloud-latest.x86_64.qcow2` ← do NOT use (moving target; CONTEXT locks dated)

**Pin caveat for `cloud-images.txt`:** unlike Ubuntu's stable per-codename path, AlmaLinux rotates the dated file *and* bumps the minor version in place — when `9.8-20260526` is superseded the old file is removed from the dir (only `-latest` and the newest dated build are guaranteed). Pin the full dated URL in `cloud-images.txt`; when CI 404s on download, that is the rotation signal to bump the row (and the `actions/cache` key auto-invalidates on the file edit, same mechanism as the Ubuntu rows). [VERIFIED: dir listing shows only newest dated build retained]

### Q2 — Checksum file (format + verification)

**File:** `CHECKSUM` (and a detached `CHECKSUM.asc` PGP signature) at the same dir. [VERIFIED: live curl]

**Actual format — GNU coreutils, two-space separator, NOT BSD:** [VERIFIED: `curl … | cat -A`]
```
c397eed7023e92c841155831b1f47e26300e5bef0f0256c129322307c897a251  AlmaLinux-9-GenericCloud-9.8-20260526.x86_64.qcow2
53a20d1d73d739f437b45e34fcbda48b7b9856c648fcc9730ce9653e27712092  AlmaLinux-9-GenericCloud-ext4-9.8-20260526.x86_64.qcow2
...
```
- It is `<sha256hex><SP><SP><filename>` — exactly the format `sha256sum --check` expects. **`grep -c 'SHA256 ('` on the live file returns 0** — there are no BSD-style lines.
- **Verification (works as-is, no reformat):**
  ```bash
  # in the cache dir, with CHECKSUM downloaded next to the qcow2:
  sha256sum --ignore-missing --check CHECKSUM
  # → "AlmaLinux-9-GenericCloud-9.8-20260526.x86_64.qcow2: OK"
  ```
  This is the identical call shape the Ubuntu arm uses against `SHA256SUMS`; only the filename differs (`CHECKSUM` vs `SHA256SUMS`). `--ignore-missing` is required because `CHECKSUM` lists 6 files (GenericCloud xfs/ext4 + OpenNebula, each dated + latest) and the cache holds only one.

**HARN-02 "≥1 row matched" gap:** `sha256sum --check --ignore-missing` exits **0 even when ZERO listed files are present** (nothing checked = no failures). This is the exact false-pass HARN-02 must close — assert that the matched-file count ≥ 1, e.g. capture `--check` output and grep for `: OK`, or pre-assert the pinned basename appears in `CHECKSUM`. A flipped-byte corruption test must then drive exit non-zero. [VERIFIED: `sha256sum --check` semantics]

> Historical note: AlmaLinux **8** and older `CHECKSUM` files *did* carry BSD `SHA256 (file) = hash` lines (sometimes alongside a size comment). The EL9 cloud CHECKSUM is plain GNU format today. If you ever need BSD→GNU conversion as defensive code: `sed -E 's/^SHA256 \((.*)\) = (.*)$/\2  \1/'`. Not needed for EL9 now. [ASSUMED: EL8 historical format — not load-bearing for this phase]

### Q3 — Default cloud-init user + root SSH

- **Default cloud-init user:** `almalinux` (locked password; key/password must be injected). [VERIFIED: AlmaLinux wiki + cloud-images]
- **Root SSH IS permitted by default.** The official gencloud kickstart `%post` runs:
  ```
  echo "PermitRootLogin yes" > /etc/ssh/sshd_config.d/01-permitrootlogin.conf
  ```
  and the ansible `gencloud_guest` role's "Disable root login" task only **locks the root password** (`password: "*"`) — it does NOT touch `PermitRootLogin`. So **key-based root SSH works out of the box**; only password root login is effectively blocked (no password set). [VERIFIED: `AlmaLinux/cloud-images` `http/almalinux-9.gencloud-x86_64.ks` + `ansible/roles/gencloud_guest/tasks/main.yml`, main branch]
- **cloud-init `disable_root: false` + `users: - name: root, ssh_authorized_keys: [...]`** therefore injects the per-run pubkey into root's `authorized_keys` with no forced-command banner, and sshd already permits root key login. **The existing Ubuntu `user-data` seed works on EL9 unchanged** for the root model.

**Most robust approach for the CI harness (recommendation):** keep the **root** model for byte-equivalence with the Ubuntu arm — it is confirmed working and avoids a `sudo` indirection for the root-level installer + bats run. SSH as `root@localhost`. (The `almalinux` + NOPASSWD-sudo model also works and is the cloud-native default, but it adds a `sudo` wrapper on every in-guest command for no benefit here, and CONTEXT wants Ubuntu-parity dispatch.) If a future image ever drops `PermitRootLogin yes`, the fallback is `almalinux@` + `sudo` — note this in `boot.sh` as the family-dispatch escape hatch.

### Q4 — sshd unit + readiness

- **Unit name: `sshd.service`** on EL9 (NOT `ssh`). [VERIFIED: kickstart `services --enabled=sshd`]
- **Enabled by default** in the GenericCloud image (`services --enabled=sshd`), so it starts on boot with no runcmd needed. The Ubuntu seed's `runcmd: systemctl enable --now ssh` becomes `systemctl enable --now sshd` on EL9 (harmless belt-and-suspenders; the unit is already enabled). [VERIFIED: kickstart]
- Readiness: gate on `cloud-init status --wait` over SSH exactly as Ubuntu (Q8), not on a raw port probe.

### Q5 — bats availability

- **`bats` is NOT in BaseOS or AppStream.** It ships only via **EPEL 9**: `bats-1.8.0-1.el9.noarch` is present in EPEL 9 `Everything/x86_64`. [VERIFIED: `dl.fedoraproject.org/pub/epel/9/Everything/x86_64/Packages/b/`]
- **`epel-release` is reachable from base** (AlmaLinux ships it in `extras`), so `dnf install -y epel-release` then `dnf install -y bats` works. [VERIFIED: AlmaLinux wiki repos]
- **cloud-init `packages:` ordering caveat (important):** cloud-init's `packages` module installs the whole list in a **single `dnf install pkg1 pkg2 …` transaction**. Putting `epel-release` and `bats` in the same `packages:` list **fails** — `bats` can't resolve because EPEL isn't enabled until that transaction's `epel-release` is *already installed*. Options:
  - **(a)** Enable EPEL earlier via the cloud-init **`yum_repos:`** module (defines the repo declaratively before `packages:` runs), then list `bats` in `packages:`.
  - **(b)** Use `runcmd:` (runs after `packages:`): `dnf install -y epel-release && dnf install -y bats`.
  - **(c) Recommended / simplest — sidestep EPEL entirely:** ship the **bundled `node_modules/bats`** (or vendored `bats-core`) and don't install distro bats at all. This removes the EPEL dependency, the ordering caveat, and a network fetch from the gate — and makes the EL9 and Ubuntu arms run the *same* bats binary. CONTEXT explicitly leaves this to discretion; (c) is the lowest-risk pick for a hermetic release gate.
- `jq` (used by the harness) is **preinstalled** in the GenericCloud image (ansible role installs it), and is also in AppStream — no EPEL needed for jq. [VERIFIED: `gencloud_guest` role "Install additional packages": `jq`]

### Q6 — SELinux

- **SELinux is enforcing by default.** Kickstart: `selinux --enforcing`. [VERIFIED: `almalinux-9.gencloud-x86_64.ks`]
- **The harness must NOT disable it** (CONTEXT locks this; green-on-permissive is a false pass). No `enforcing=0` kernel arg, no `setenforce 0`.
- **First-boot autorelabel gotcha:** the prebuilt GenericCloud image is already correctly labelled, so a normal boot does **not** trigger a relabel. The relabel-on-reboot trap only appears if something drops `/.autorelabel` or you edit `/etc/selinux/config` mode — don't. The relevant EL9 SELinux behavior the harness must respect (mirroring Phase 19/20 Docker work): file contexts for newly written files. If the installer writes into non-default paths, use a **guarded `restorecon`** (only if `selinuxenabled` returns true and `restorecon` exists) rather than disabling SELinux. No `chcon` on the host image file is needed for QEMU (that wiki note is about libvirt storage labelling on enforcing *hosts*, not relevant to a `-snapshot` QEMU run on a GitHub runner).
- AGT-02 (`claude update`) must pass with SELinux enforcing — confirm no AVC denials block the npm-prefix self-update path.

### Q7 — growpart / resize + qcow2

- **Root is a plain XFS partition (sda4), no LVM.** Kickstart partitions: `part / --fstype=xfs --onpart=sda4` (last partition, 1226MiB→100%). [VERIFIED: kickstart `%pre`]
- Because root is a bare partition (not LVM), **cloud-init `growpart` + `resizefs` resize it on first boot exactly like Ubuntu** — `growpart` does not support LVM, but that caveat does not apply here. Resizing the overlay/qcow2 to 12G host-side (`qemu-img resize`) then booting lets cloud-init expand sda4 + the XFS fs automatically. [VERIFIED: partition layout + cloud-init default modules]
- XFS grows online via `xfs_growfs` (cloud-init's `resizefs` handles it); XFS **cannot shrink**, irrelevant here since the harness only grows.
- The `-ext4-` variant exists if an ext4 root is ever preferred, but the default XFS variant resizes fine — no need to switch.

### Q8 — cloud-init present

- **cloud-init is preinstalled** — the image is literally "Cloud-init included" (kickstart header) and the GenericCloud image's entire purpose is cloud-init provisioning. [VERIFIED: kickstart header line 1 + AlmaLinux wiki]
- **`cloud-init status --wait` is supported** (EL9 ships cloud-init 23.x+, which has `status --wait`). Gate guest-readiness on it over SSH exactly as the Ubuntu arm does. [CITED: RHEL 9 cloud-init docs — same cloud-init build]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| BSD→GNU checksum reformat | A `sed` pre-processor | Nothing — EL9 `CHECKSUM` is already GNU; `sha256sum -c` direct | The reformat is a fix for a problem that doesn't exist on EL9 |
| "≥1 row matched" assertion | Trusting `sha256sum -c` exit 0 | Explicit matched-count check / pinned-basename grep | `--check --ignore-missing` exits 0 on zero matches (the HARN-02 false-pass) |
| EPEL ordering dance in cloud-init | `epel-release`+`bats` in one `packages:` list | Bundled `node_modules/bats` (or `yum_repos:` then `bats`) | Single-transaction dnf can't see EPEL mid-list |
| Root SSH enablement | Editing sshd_config in runcmd | `disable_root: false` + `users: - name: root` (image already `PermitRootLogin yes`) | Image ships root key-login enabled |

## Common Pitfalls

### Pitfall 1: `ssh` vs `sshd` unit name
`systemctl enable --now ssh` (Ubuntu) fails on EL9 — the unit is `sshd`. Family-dispatch the unit name in the seed/runcmd.

### Pitfall 2: checksum file name + silent zero-match pass
EL9 uses `CHECKSUM` not `SHA256SUMS`, and `sha256sum --check --ignore-missing` returns 0 when nothing matched. Assert a positive match (HARN-02 core requirement) and self-test with a flipped byte.

### Pitfall 3: bats from a mixed cloud-init package list
`packages: [epel-release, bats]` fails — EPEL isn't active within the same dnf transaction. Bundle bats or define EPEL via `yum_repos:` first.

### Pitfall 4: dated image rotation → 404
AlmaLinux removes superseded dated builds from the dir (keeps only `-latest` + newest dated). A pinned older URL will eventually 404 — treat download 404 as the row-bump signal, not a flaky-network retry.

### Pitfall 5: assuming SELinux needs disabling to pass
It does not, and disabling it is a locked-out false pass. Use guarded `restorecon` for any installer-written paths instead.

## Environment Availability

> Host-side (GitHub `ubuntu-24.04` runner per CONTEXT) — guest tooling is provisioned by cloud-init.

| Dependency | Required By | Available | Notes / Fallback |
|------------|------------|-----------|------------------|
| `qemu-system-x86` + `/dev/kvm` | booting the guest | ✗ locally (no qemu, no /dev/kvm) | CI installs it on the runner + KVM udev rule; author here, validate in CI |
| `cloud-localds` (cloud-image-utils) | seed ISO | host-side, CI-provided | same as Ubuntu arm |
| `sha256sum` (coreutils) | checksum gate | ✓ | already used by Ubuntu arm |
| `bats` (in guest) | in-guest suite | provisioned | EPEL or bundled `node_modules/bats` (Q5) |
| `jq` (in guest) | harness JSON | preinstalled in image | no action |

**Blocking locally:** QEMU/KVM — expected and accounted for (CONTEXT "QEMU not local"). No local fallback; CI is the validation path.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bats-core (in-guest suite under `tests/bats/`); harness is a bash script `tests/qemu/boot.sh` |
| Config file | `tests/qemu/cloud-images.txt` (image manifest) + `tests/qemu/cloud-init/{user-data,meta-data}` |
| Quick run command | `tests/qemu/boot.sh almalinux-9` (full boot+install+bats; CI-only — needs KVM) |
| Full suite command | nightly-qemu.yml matrix incl. `almalinux-9`; release.yml gate-3 |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Command | Exists? |
|--------|----------|-----------|---------|---------|
| HARN-02 | EL9 boots + checksum-guard + bats green | e2e (QEMU) | `tests/qemu/boot.sh almalinux-9` | ❌ Wave 0 (EL9 arm new) |
| HARN-02 | checksum guard asserts ≥1 match; flip-byte → non-zero | unit (host) | bats test over `boot.sh` checksum fn / corruption fixture | ❌ Wave 0 |
| PAR-02 | AGT-02 `claude update` zero-EACCES on EL9 guest | e2e (QEMU) | in-guest bats AGT-02 | exists for Ubuntu; runs on EL9 once arm lands |
| REL-01 | tag blocked until EL9 Docker+QEMU green | CI gate | release.yml gate-2 hard-flip + gate-3 almalinux-9 | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** shellcheck/bats-lint on `boot.sh` (host-runnable); EL9 boot itself is CI-only.
- **Per wave merge:** nightly-qemu `almalinux-9` arm green.
- **Phase gate:** release.yml gate-2 (Docker, hard) + gate-3 (QEMU almalinux-9) both green before v0.3.5 tag.

### Wave 0 Gaps
- [ ] `tests/qemu/cloud-images.txt` — add `almalinux-9` row (dated qcow2 URL + `CHECKSUM` URL).
- [ ] `tests/qemu/boot.sh` — family dispatch: `CHECKSUM` filename, `sshd` unit, `root@`/`almalinux@` model, ≥1-row-matched assertion + flip-byte self-test.
- [ ] `tests/qemu/cloud-init/` — EL9 seed variant (or templating): `sshd` not `ssh`, bats sourcing per Q5.
- [ ] `.github/workflows/nightly-qemu.yml` + `release.yml` — add `almalinux-9` matrix arm; flip gate-2 Docker EL9 experimental→hard.

## Security Domain

> `security_enforcement` not disabled in config — included.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Per-run ephemeral ed25519 keypair (mktemp 0700), injected via cloud-init; no static creds |
| V6 Cryptography | yes | SHA-256 image integrity via published `CHECKSUM`; optionally verify `CHECKSUM.asc` PGP against AlmaLinux release key |
| V12/Config | yes | SELinux stays enforcing; no sshd password auth; root password locked (key-only) |

### Known Threat Patterns
| Pattern | STRIDE | Mitigation |
|---------|--------|-----------|
| Tampered/substituted cloud image | Tampering | `sha256sum -c CHECKSUM` with ≥1-match assertion + flip-byte self-test; optional `CHECKSUM.asc` PGP verify |
| Stale/poisoned cache hit | Tampering | Re-verify checksum on EVERY cache hit (existing Ubuntu Pitfall-10 pattern), not just first fetch |
| Leaked SSH key reuse | Spoofing | Per-run ephemeral keypair destroyed by EXIT trap |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | AlmaLinux 8 cloud CHECKSUM historically used BSD format | Q2 note | None — EL9 (this phase) is verified GNU; the BSD `sed` is dead code if unused |
| A2 | EL9 cloud-init is 23.x+ with `status --wait` | Q8 | Low — `status --wait` has been present since cloud-init 20.x; EL9 ships newer |

## Sources

### Primary (HIGH)
- `https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/` — live dir listing (dated filenames, `CHECKSUM`, `CHECKSUM.asc`) [curl 2026-06-29]
- `https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/CHECKSUM` — exact GNU format, verified with `cat -A` + `grep -c 'SHA256 ('`=0
- `AlmaLinux/cloud-images` @ `main`, `http/almalinux-9.gencloud-x86_64.ks` — `selinux --enforcing`, `services --enabled=sshd`, `PermitRootLogin yes`, XFS sda4 partitioning, `rootpw --plaintext almalinux`
- `AlmaLinux/cloud-images` @ `main`, `ansible/roles/gencloud_guest/tasks/main.yml` — preinstalled `jq`; "Disable root login" locks password only
- `https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/Packages/b/` — `bats-1.8.0-1.el9.noarch.rpm` present (EPEL-only)

### Secondary (MEDIUM)
- AlmaLinux Wiki — Generic Cloud (`wiki.almalinux.org/cloud/Generic-cloud.html`), default user `almalinux`
- AlmaLinux Wiki — Repos (`wiki.almalinux.org/repos/AlmaLinux.html`), `epel-release` availability
- RHEL 9 cloud-init docs (`docs.redhat.com`) — growpart/resizefs default modules, LVM caveat (N/A here), `status --wait`

## Metadata
**Confidence breakdown:**
- Image URL / checksum format: HIGH — live repo verified byte-for-byte.
- SSH/root/sshd/SELinux/partition: HIGH — read from the official kickstart that builds the image.
- bats/EPEL: HIGH — RPM presence verified in EPEL 9 index.
**Research date:** 2026-06-29
**Valid until:** ~2026-07-29 for the dated image URL (rotates on next point release / build); facts (format, unit name, SELinux, root policy) are stable across EL9.
