# Phase 3: Bootable Image with Agent User - Research

**Researched:** 2026-03-15
**Domain:** Packer image build, QEMU/KVM, Debian cloud images, OpenNebula contextualization
**Confidence:** HIGH

## Summary

Phase 3 produces a bootable Debian 12 QCOW2 image using Packer with the QEMU builder. The image starts from the official Debian 12 genericcloud QCOW2 (329 MB, updated 2026-03-13), uses cloud-init during the Packer build for SSH bootstrapping, then replaces cloud-init with OpenNebula's one-context package for production use. On first boot in OpenNebula, one-context creates a non-root `agent` user (via the `USERNAME` context variable), injects SSH keys (via `SSH_PUBLIC_KEY`), and grants passwordless sudo -- all without custom scripting.

The build machine (AlmaLinux 9.7) has `/dev/kvm` access but needs Packer and QEMU system packages installed. Packer 1.15.0 (latest, Feb 2026) with the QEMU plugin v1.1.4 is the verified current stack. The `cd_content` + `cd_label = "cidata"` approach injects cloud-init config directly as a virtual CD during build -- no HTTP server or external ISO generation needed.

**Primary recommendation:** Use Packer `disk_image = true` with Debian 12 genericcloud QCOW2, cloud-init via `cd_content` for build-time SSH access, layered shell provisioners for system configuration, and one-context for runtime OpenNebula integration. The agent user is created by one-context at deploy time, NOT baked into the image.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| IMG-01 | Packer builds a bootable Debian 12 QCOW2 image from the official cloud base image | Packer 1.15.0 + QEMU plugin v1.1.4 with `disk_image=true` from `debian-12-genericcloud-amd64.qcow2`. Verified approach with `cd_content` for cloud-init bootstrapping. |
| IMG-02 | Built image boots successfully on KVM/QEMU | `format = "qcow2"`, `accelerator = "kvm"`, virtio disk/net interfaces. Verify with `qemu-system-x86_64` test boot. |
| ONE-01 | Image includes one-context package (cloud-init purged) for SSH key injection and network configuration | one-context .deb from GitHub releases (v6.10.0-3 or v7.0.0 depending on OpenNebula server version). Cloud-init must be purged during build. |
| ONE-02 | Image deploys and contextualizes correctly on OpenNebula | one-context reads context CD-ROM, configures networking (`NETWORK=YES`), injects SSH keys (`SSH_PUBLIC_KEY`). Requires matching one-context version to OpenNebula server. |
| USR-01 | Non-root agent user is created on first boot via one-context | `USERNAME=agent` in OpenNebula VM template context. one-context's `loc-20-set-username-password` script runs `useradd -m agent -p '*' -s /bin/bash`. |
| USR-02 | Agent user is SSH-accessible with OpenNebula-injected public key | `SSH_PUBLIC_KEY=$USER[SSH_PUBLIC_KEY]` in VM template. one-context's `loc-22-ssh_public_key` script writes key to `~agent/.ssh/authorized_keys`. |
| USR-03 | Agent user has passwordless sudo access | `USERNAME_SUDO` defaults to `YES` in one-context. Script writes `agent ALL=(ALL) NOPASSWD:ALL` to `/etc/sudoers.d/one-context`. |
</phase_requirements>

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| HashiCorp Packer | 1.15.0 | Automated QCOW2 image building | Industry standard, HCL declarative config, QEMU/KVM native support. Latest release 2026-02-04. |
| Packer QEMU Plugin | 1.1.4 | QEMU/KVM builder for Packer | Official HashiCorp plugin, outputs QCOW2 directly, supports `disk_image` mode. Latest release 2025-07-31. |
| Debian 12 genericcloud | bookworm latest | Base OS image | 329 MB QCOW2, updated 2026-03-13, minimal cloud-ready image with virtio drivers, official Debian. |
| one-context | 6.10.0-3 or 7.0.0 | OpenNebula VM contextualization | Handles SSH key injection, user creation, networking on first boot. Version depends on OpenNebula server. |
| QEMU/KVM | system package | VM runtime for Packer builds | Required by Packer QEMU builder. Build machine has `/dev/kvm`. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| qemu-img | system package | Image inspection and conversion | Build verification, checking output image |
| cloud-init | (in base image) | Build-time SSH bootstrapping | Only during Packer build; purged before final image |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| cd_content for cloud-init | http_content + qemuargs SMBIOS | Works but more complex; cd_content is simpler and self-contained |
| cd_content for cloud-init | Pre-built cidata.iso via genisoimage | Requires external tool, extra build step |
| genericcloud QCOW2 | Debian netinst ISO | Much slower (full install), complex preseed, unnecessary |
| Shell provisioners | Ansible provisioner | Adds dependency, overkill for 3-4 scripts in v0.2.0 |

**Installation (build machine -- AlmaLinux 9.7):**
```bash
# Packer (HashiCorp repo)
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum -y install packer

# QEMU for Packer builds
sudo yum install -y qemu-kvm qemu-img

# NOTE: /usr/sbin/packer on this system is cracklib-packer (not HashiCorp)
# HashiCorp Packer installs to /usr/bin/packer -- verify with: /usr/bin/packer version
```

## Architecture Patterns

### Recommended Project Structure
```
packer/
  agentlinux.pkr.hcl           # Main Packer template (source + build blocks)
  variables.pkr.hcl            # Variable definitions (base image URL, checksums, versions)
  scripts/
    01-base.sh                  # Locale, timezone, apt config, resize disk
    02-one-context.sh           # Purge cloud-init, install one-context .deb
    03-cleanup.sh               # Remove build artifacts, zero free space, truncate logs
```

### Pattern 1: Packer with disk_image + cd_content for Cloud-Init

**What:** Use Packer's QEMU builder in `disk_image = true` mode starting from the Debian 12 genericcloud QCOW2. Inject cloud-init configuration via `cd_content` with `cd_label = "cidata"` to bootstrap SSH access during the build.

**When to use:** Always -- this is the build pattern for Phase 3.

**Why:** The Debian genericcloud image ships with cloud-init pre-installed and expects a NoCloud datasource. Packer's `cd_content` creates a virtual CD-ROM with cloud-init user-data and meta-data. No HTTP server needed, no external ISO generation.

**Example:**
```hcl
# Source: Packer QEMU plugin docs + liorokman/packer-Debian pattern
packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.4"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "debian_image_url" {
  type    = string
  default = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
}

variable "debian_image_checksum" {
  type    = string
  default = "file:https://cloud.debian.org/images/cloud/bookworm/latest/SHA512SUMS"
}

source "qemu" "agentlinux" {
  # Start from existing cloud image (not ISO)
  disk_image   = true
  iso_url      = var.debian_image_url
  iso_checksum = var.debian_image_checksum

  # VM specs
  cpus         = 2
  memory       = 2048
  disk_size    = "10G"
  accelerator  = "kvm"
  headless     = true

  # Disk settings
  disk_interface = "virtio"
  net_device     = "virtio-net"
  format         = "qcow2"

  # Cloud-init via virtual CD (NoCloud datasource)
  cd_content = {
    "meta-data" = ""
    "user-data" = <<-EOF
      #cloud-config
      users:
        - name: packer
          plain_text_passwd: packer
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          lock_passwd: false
      ssh_pwauth: true
    EOF
  }
  cd_label = "cidata"

  # SSH for Packer provisioning
  ssh_username     = "packer"
  ssh_password     = "packer"
  ssh_timeout      = "5m"
  ssh_port         = 22

  # Output
  output_directory = "output"
  vm_name          = "agentlinux-0.2.0-amd64.qcow2"

  # Compact output
  disk_compression   = true
  disk_discard       = "unmap"
  disk_detect_zeroes = "unmap"
  skip_compaction    = false

  shutdown_command = "echo 'packer' | sudo -S shutdown -P now"
}

build {
  sources = ["source.qemu.agentlinux"]

  provisioner "shell" {
    execute_command = "echo 'packer' | sudo -S bash -c '{{ .Vars }} {{ .Path }}'"
    scripts = [
      "scripts/01-base.sh",
      "scripts/02-one-context.sh",
      "scripts/03-cleanup.sh",
    ]
  }
}
```

### Pattern 2: Layered Provisioning Scripts

**What:** Numbered shell scripts, each handling one concern, executed in order via Packer's shell provisioner.

**When to use:** Always -- this is the provisioning model.

**Example:**
```bash
#!/bin/bash
# scripts/01-base.sh -- Base system configuration
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

# Configure locale
apt-get update
apt-get install -y locales
sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen en_US.UTF-8

# Set timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Install essential packages
apt-get install -y \
  sudo \
  openssh-server \
  curl \
  ca-certificates \
  gnupg
```

```bash
#!/bin/bash
# scripts/02-one-context.sh -- Install OpenNebula contextualization
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

# Purge cloud-init FIRST (conflicts with one-context)
apt-get purge -y cloud-init
rm -rf /etc/cloud /var/lib/cloud

# Download and install one-context
# NOTE: Version must match target OpenNebula server version
ONE_CONTEXT_VERSION="6.10.0-3"
wget -q "https://github.com/OpenNebula/one-apps/releases/download/v${ONE_CONTEXT_VERSION}/one-context_${ONE_CONTEXT_VERSION}.deb" \
  -O /tmp/one-context.deb
dpkg -i /tmp/one-context.deb || apt-get install -fy
rm -f /tmp/one-context.deb

# Verify one-context is installed and enabled
systemctl is-enabled one-context || systemctl enable one-context
systemctl is-enabled one-context-local || systemctl enable one-context-local
```

```bash
#!/bin/bash
# scripts/03-cleanup.sh -- Minimize image size
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

# Remove the temporary packer user created by cloud-init
userdel -r packer 2>/dev/null || true
rm -f /etc/sudoers.d/90-cloud-init-users

# Clean apt cache
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*

# Remove cloud-init artifacts
rm -rf /etc/cloud /var/lib/cloud

# Remove machine-id (regenerated on first boot)
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

# Clear logs
journalctl --flush
journalctl --rotate
journalctl --vacuum-time=0
truncate -s 0 /var/log/wtmp
truncate -s 0 /var/log/lastlog

# Zero free space for better compression
dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true
rm -f /EMPTY
sync
```

### Pattern 3: one-context User Creation at Deploy Time

**What:** The `agent` user is NOT baked into the image. Instead, OpenNebula's VM template context section sets `USERNAME=agent`, and one-context creates the user on first boot.

**When to use:** Always for the agent user. This is how OpenNebula contextualization is designed to work.

**Why:** The same image can work for any username. The SSH key injection is tied to the user creation flow. Baking the user into the image would bypass one-context's SSH key management.

**OpenNebula VM Template context section:**
```
CONTEXT = [
  NETWORK = "YES",
  SSH_PUBLIC_KEY = "$USER[SSH_PUBLIC_KEY]",
  USERNAME = "agent",
  USERNAME_SUDO = "YES"
]
```

**What happens on first boot:**
1. `loc-10-network` -- configures networking from OpenNebula context
2. `loc-20-set-username-password` -- creates `agent` user: `useradd -m agent -p '*' -s /bin/bash`
3. `loc-20-set-username-password` -- writes sudo rule: `agent ALL=(ALL) NOPASSWD:ALL` to `/etc/sudoers.d/one-context`
4. `loc-22-ssh_public_key` -- writes SSH key to `~agent/.ssh/authorized_keys`
5. `net-15-hostname` -- sets hostname

### Anti-Patterns to Avoid

- **cloud-init + one-context together:** They race on boot. Cloud-init must be purged BEFORE one-context install.
- **Baking the agent user into the image:** Bypasses one-context's SSH key management. Let one-context create it.
- **Building from ISO:** Unnecessary when official cloud QCOW2 exists. Adds preseed complexity and 10x longer build times.
- **Using /usr/sbin/packer:** This is cracklib-packer on the build machine, NOT HashiCorp Packer. HashiCorp Packer installs to `/usr/bin/packer`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SSH key injection | Custom first-boot script to read keys | one-context `loc-22-ssh_public_key` | Handles authorized_keys permissions, SELinux contexts, multiple key formats |
| User creation on first boot | Custom systemd service | one-context `loc-20-set-username-password` | Handles sudo config, password management, shell setup, idempotency |
| Network configuration | Custom network setup scripts | one-context `loc-10-network` | Handles DHCP, static IP, IPv6, DNS, gateway, multiple NICs |
| Cloud-init CD-ROM generation | Manual genisoimage calls | Packer `cd_content` + `cd_label` | Built into Packer, no external tools needed |
| Image compression | Manual qemu-img convert | Packer `disk_compression` + `disk_discard` | Integrated into build pipeline |

**Key insight:** one-context handles the entire first-boot lifecycle. The Packer build should only install one-context and set up the base system. All user/SSH/network config happens at deploy time through OpenNebula context variables.

## Common Pitfalls

### Pitfall 1: cloud-init / one-context Conflict
**What goes wrong:** Debian genericcloud image ships with cloud-init. Installing one-context on top creates a race condition on first boot -- both try to manage networking, SSH keys, hostname.
**Why it happens:** Both are "first boot" configuration systems that operate on the same resources.
**How to avoid:** In provisioner script, `apt-get purge -y cloud-init` BEFORE installing one-context. Also `rm -rf /etc/cloud /var/lib/cloud`.
**Warning signs:** VM boots but SSH times out. Console shows dual network configuration attempts.

### Pitfall 2: /usr/sbin/packer vs /usr/bin/packer
**What goes wrong:** Running `packer build` invokes cracklib-packer instead of HashiCorp Packer.
**Why it happens:** AlmaLinux ships cracklib-packer at `/usr/sbin/packer`. HashiCorp Packer installs to `/usr/bin/packer`.
**How to avoid:** After installing HashiCorp Packer, verify with `/usr/bin/packer version` or use full path. Alternatively, `hash -r` to refresh PATH cache.
**Warning signs:** `packer build` produces cryptic errors unrelated to Packer.

### Pitfall 3: KVM Acceleration Missing
**What goes wrong:** Packer builds without KVM are 10-50x slower (full CPU emulation).
**Why it happens:** Build machine lacks KVM access or Packer defaults to TCG.
**How to avoid:** Build machine has `/dev/kvm` (VERIFIED: present, world-writable). Set `accelerator = "kvm"` explicitly in Packer config.
**Warning signs:** Build takes >10 minutes for a simple provisioning run.

### Pitfall 4: Disk Space Exhaustion During Build
**What goes wrong:** Default Debian genericcloud disk is ~2GB. Installing packages fills it up.
**Why it happens:** The base image's virtual disk is small. Packer's `disk_size` parameter resizes it.
**How to avoid:** Set `disk_size = "10G"` in Packer config. QCOW2 is sparse -- only actual data uses host space.
**Warning signs:** `apt-get install` fails with "No space left on device".

### Pitfall 5: one-context Version Mismatch
**What goes wrong:** one-context version incompatible with OpenNebula server, causing contextualization to partially fail.
**Why it happens:** one-context v7.0.0+ required for OpenNebula 7.x (OneGate incompatibility). one-context v6.x works for OpenNebula 6.x.
**How to avoid:** Check target OpenNebula server version FIRST. Use matching one-context version. STATE.md lists API at api.nebula.k8s.svcs.io -- verify OpenNebula version before choosing one-context.
**Warning signs:** VM boots, network works, but SSH keys not injected or user not created.

### Pitfall 6: SSH Timeout During Packer Build
**What goes wrong:** Packer can't SSH into the VM during build. Build hangs then fails.
**Why it happens:** Cloud-init hasn't finished configuring the user, or cloud-init fails to pick up the cidata CD.
**How to avoid:** Use `cd_content` with `cd_label = "cidata"` (verified approach). Set `ssh_timeout = "5m"`. Ensure `ssh_pwauth: true` in cloud-init user-data.
**Warning signs:** "Timeout waiting for SSH" in Packer output.

### Pitfall 7: Packer User Left in Final Image
**What goes wrong:** The temporary `packer` user created by cloud-init during build remains in the final image.
**Why it happens:** Cloud-init creates the SSH user. If not cleaned up, the user persists.
**How to avoid:** In cleanup script, `userdel -r packer` and remove `/etc/sudoers.d/90-cloud-init-users`.
**Warning signs:** `getent passwd packer` returns a result in the deployed image.

## Code Examples

### cloud-init user-data for Packer Build
```yaml
# Source: Cloud-init NoCloud docs + verified community patterns
#cloud-config
users:
  - name: packer
    plain_text_passwd: packer
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
ssh_pwauth: true
```

### one-context User Creation (source code verified)
```bash
# Source: github.com/OpenNebula/addon-context-linux/src/etc/one-context.d/loc-20-set-username-password
# Executed on first boot when USERNAME is set in OpenNebula context

# Defaults (from source code):
USERNAME=${USERNAME:-root}
USERNAME_SUDO=${USERNAME_SUDO:-YES}
USERNAME_SHELL=${USERNAME_SHELL:-/bin/bash}

# Create user if missing
if ! getent passwd "${USERNAME}" > /dev/null 2>&1; then
    useradd -m "${USERNAME}" -p '*' -s "${USERNAME_SHELL}"
fi

# Enable sudo (when USERNAME_SUDO=YES and user is not root)
if [ "${USERNAME_SUDO}" == "YES" ] && [ "${USERNAME}" != "root" ]; then
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >"/etc/sudoers.d/one-context"
    chmod 0440 "/etc/sudoers.d/one-context"
fi
```

### one-context SSH Key Injection (source code verified)
```bash
# Source: github.com/OpenNebula/addon-context-linux/src/etc/one-context.d/loc-22-ssh_public_key
# Executed after user creation

USER_HOME=$(getent passwd "${USERNAME}" | awk -F':' '{print $6}')
AUTH_DIR="${USER_HOME}/.ssh"
AUTH_FILE="$AUTH_DIR/authorized_keys"

mkdir -m0700 -p $AUTH_DIR
[ ! -f $AUTH_FILE ] && touch $AUTH_FILE

echo "$SSH_PUBLIC_KEY" | while read key; do
    if ! grep -q -F "$key" $AUTH_FILE; then
        echo "$key" >> $AUTH_FILE
    fi
done

chown "${USERNAME}": ${AUTH_DIR} ${AUTH_FILE}
chmod 600 $AUTH_FILE
```

### Testing the Built Image Locally
```bash
# Quick boot test with QEMU (no OpenNebula needed)
qemu-system-x86_64 \
  -enable-kvm \
  -m 2048 \
  -cpu host \
  -drive file=output/agentlinux-0.2.0-amd64.qcow2,format=qcow2 \
  -nographic \
  -serial mon:stdio

# Should reach login prompt within 30 seconds
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| addon-context-linux (archived) | one-apps repo context packages | Jan 2024 | Download from one-apps releases, not addon-context-linux |
| one-context 6.6.1 | one-context 6.10.0-3 (for ONE 6.x) or 7.0.0 (for ONE 7.x) | 2025 | v7.0.0 required for OpenNebula 7.x OneGate compatibility |
| `http_directory` for cloud-init | `cd_content` + `cd_label` | Packer QEMU plugin 1.0.1+ (Sept 2021) | Simpler, no HTTP server, self-contained |
| Packer JSON templates | Packer HCL2 | Packer 1.5+ | HCL is standard, JSON deprecated |
| `iso_checksum_type` + `iso_checksum` | `iso_checksum = "file:URL"` | Packer 1.6+ | Single parameter with auto-detection |

**Deprecated/outdated:**
- `addon-context-linux` repo: Archived Jan 2024. Use `one-apps` releases instead.
- one-context v6.6.1: Outdated. Use v6.10.0-3 (for ONE 6.x) or v7.0.0 (for ONE 7.x).
- Packer JSON templates: HCL2 is the standard format.
- `http_directory` for cloud-init: Works but `cd_content` is simpler.

## Open Questions

1. **OpenNebula Server Version**
   - What we know: API is at `api.nebula.k8s.svcs.io`, user is `nivanov`, network is `ire_developers` (ID 500)
   - What's unclear: Is this OpenNebula 6.x or 7.x?
   - Recommendation: Check server version FIRST (e.g., `oneserver version` or API call). Use one-context 6.10.0-3 for ONE 6.x, or 7.0.0 for ONE 7.x. **Default to 6.10.0-3** since STATE.md references v6.6.1 in prior research, suggesting a 6.x cluster.

2. **Build Machine QEMU Installation**
   - What we know: AlmaLinux 9.7, `/dev/kvm` present (world-writable), no QEMU system packages installed
   - What's unclear: Whether `qemu-kvm` package is available or if `qemu-system-x86-core` is needed
   - Recommendation: `sudo yum install -y qemu-kvm qemu-img` should suffice. Verify with `qemu-system-x86_64 --version`.

3. **Debian genericcloud vs generic Image**
   - What we know: `genericcloud` (329 MB) has reduced hardware drivers; `generic` (slightly larger) has full drivers
   - What's unclear: Whether OpenNebula/KVM needs any drivers not in genericcloud
   - Recommendation: Use `genericcloud` -- it includes virtio drivers which is all KVM needs. The "reduced" drivers omit bare-metal hardware (RAID controllers, specific NICs) that don't apply to VMs.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Shell scripts (bash) + Packer build verification |
| Config file | None -- tests are shell commands |
| Quick run command | `packer validate packer/agentlinux.pkr.hcl` |
| Full suite command | `packer build packer/agentlinux.pkr.hcl && qemu-system-x86_64 -enable-kvm -m 1024 -drive file=output/agentlinux-0.2.0-amd64.qcow2,format=qcow2 -nographic -serial mon:stdio` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| IMG-01 | Packer produces QCOW2 from Debian cloud image | integration | `packer build packer/agentlinux.pkr.hcl && test -f output/agentlinux-0.2.0-amd64.qcow2` | -- Wave 0 |
| IMG-02 | QCOW2 boots on KVM/QEMU | smoke | `timeout 60 qemu-system-x86_64 -enable-kvm -m 1024 -drive file=output/*.qcow2,format=qcow2 -nographic -serial mon:stdio` | -- Wave 0 |
| ONE-01 | one-context installed, cloud-init absent | unit | `virt-customize -a output/*.qcow2 --run-command 'dpkg -l one-context && ! dpkg -l cloud-init'` | -- Wave 0 |
| ONE-02 | VM contextualizes on OpenNebula | manual-only | Deploy to OpenNebula, verify IP + SSH (Phase 5 automates this) | N/A |
| USR-01 | agent user created on first boot | manual-only | Deploy with USERNAME=agent, verify `id agent` | N/A |
| USR-02 | agent user SSH-accessible | manual-only | Deploy with SSH_PUBLIC_KEY, ssh agent@VM_IP | N/A |
| USR-03 | agent user has passwordless sudo | manual-only | SSH in, run `sudo whoami` without password prompt | N/A |

### Sampling Rate
- **Per task commit:** `packer validate packer/agentlinux.pkr.hcl`
- **Per wave merge:** Full `packer build` + boot test
- **Phase gate:** Full build succeeds, image file exists, Packer exits 0

### Wave 0 Gaps
- [ ] Packer installation on build machine (`sudo yum install -y packer`)
- [ ] QEMU installation on build machine (`sudo yum install -y qemu-kvm qemu-img`)
- [ ] `packer/agentlinux.pkr.hcl` -- main template (does not exist yet)
- [ ] `packer/scripts/*.sh` -- provisioner scripts (do not exist yet)

NOTE: ONE-02, USR-01, USR-02, USR-03 require actual OpenNebula deployment and are tested in Phase 5 (End-to-End Validation). Phase 3 builds the image; Phase 5 proves it works on real infrastructure.

## Sources

### Primary (HIGH confidence)
- [Packer QEMU Builder Docs](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu) - disk_image, cd_content, cd_label, accelerator, all builder params
- [Debian Official Cloud Images](https://cloud.debian.org/images/cloud/bookworm/latest/) - genericcloud QCOW2 329MB, SHA512SUMS, updated 2026-03-13
- [OpenNebula one-apps Releases (GitHub API)](https://github.com/OpenNebula/one-apps/releases) - v7.0.0 (2025-05-29), v6.10.0-3 (2025-01-28), .deb download URLs verified
- [one-context loc-20-set-username-password source](https://github.com/OpenNebula/addon-context-linux/blob/master/src/etc/one-context.d/loc-20-set-username-password) - exact user creation logic verified
- [one-context loc-22-ssh_public_key source](https://github.com/OpenNebula/addon-context-linux/blob/master/src/etc/one-context.d/loc-22-ssh_public_key) - exact SSH key injection logic verified
- [Packer 1.15.0 Release](https://github.com/hashicorp/packer/releases) - latest as of 2026-02-04
- [Packer QEMU Plugin v1.1.4](https://github.com/hashicorp/packer-plugin-qemu/releases) - latest as of 2025-07-31
- [packer-plugin-qemu issue #45](https://github.com/hashicorp/packer-plugin-qemu/issues/45) - cd_content available since plugin v1.0.1

### Secondary (MEDIUM confidence)
- [liorokman/packer-Debian](https://github.com/liorokman/packer-Debian) - Working HCL template for Debian cloud image + cloud-init via http_content + qemuargs SMBIOS
- [OpenNebula KVM Contextualization Docs (6.4)](https://docs.opennebula.io/6.4/management_and_operations/references/kvm_contextualization.html) - SSH_PUBLIC_KEY, NETWORK, USERNAME variables
- [OpenNebula one-apps Wiki: linux_feature](https://github.com/OpenNebula/one-apps/wiki/linux_feature) - USERNAME, USERNAME_SUDO, NETCFG_TYPE variables
- [OpenNebula Forum: one-context version compatibility](https://forum.opennebula.io/t/compatibility-of-one-context-and-opennebula-versions/9870) - v7.0 required for ONE 7.x

### Tertiary (LOW confidence)
- Build machine QEMU package name: `qemu-kvm` assumed for AlmaLinux 9.7 -- needs verification at install time

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Packer 1.15.0, QEMU plugin 1.1.4, Debian 12 genericcloud all verified via official sources and GitHub API
- Architecture: HIGH - Packer disk_image=true + cd_content pattern verified from docs and working community examples; one-context user/SSH scripts read from source
- Pitfalls: HIGH - cloud-init/one-context conflict, /usr/sbin/packer naming collision, one-context version compatibility all documented with specific prevention steps

**Research date:** 2026-03-15
**Valid until:** 2026-04-15 (stable domain -- Packer, Debian 12, one-context all on slow release cycles)
