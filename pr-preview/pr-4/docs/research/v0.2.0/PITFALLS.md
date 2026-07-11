# Domain Pitfalls

**Domain:** Linux distribution image building, .deb packaging, OpenNebula integration
**Researched:** 2026-03-10

## Critical Pitfalls

Mistakes that cause significant rework or broken images.

### Pitfall 1: cloud-init / one-context Conflict
**What goes wrong:** Installing both cloud-init (present in Debian cloud images) and one-context causes both to race on first boot. Network config applied twice, SSH keys injected inconsistently, hostname set then overwritten.
**Why it happens:** Debian genericcloud image ships with cloud-init pre-installed. Adding one-context on top creates a conflict.
**Consequences:** VM fails to get network on first boot, or gets it then loses it. SSH access unreliable. Debugging is maddening because it's a race condition.
**Prevention:** In Packer provisioning script, explicitly `apt-get purge -y cloud-init` BEFORE installing one-context. Verify with `systemctl list-units | grep -E 'cloud|context'` that only one-context services remain.
**Detection:** VM boots but SSH hangs. `virsh console` shows dual network configuration attempts in boot log.

### Pitfall 2: npm Native Module Architecture Mismatch
**What goes wrong:** Building .deb packages on a machine with different architecture or glibc version than the target image. Native modules (node-gyp compiled) built on build host won't work in the image.
**Why it happens:** npm packages with native bindings compile C/C++ for the host architecture and libc version during `npm install`.
**Consequences:** Packages install but crash at runtime with GLIBC version errors or segfaults.
**Prevention:** Build npm packages INSIDE the target environment or a matching Debian 12 container, not on an arbitrary host. Use `npm install --omit=dev` to reduce surface area.
**Detection:** Test each .deb package in a fresh Debian 12 VM before baking into the image.

### Pitfall 3: Packer QEMU Build Requires KVM Access
**What goes wrong:** Packer QEMU builder is agonizingly slow (10-50x) without KVM hardware acceleration. Build that should take 5 minutes takes hours.
**Why it happens:** Build machine lacks KVM support (nested virt disabled, running in a VM without KVM passthrough, or missing `/dev/kvm`).
**Consequences:** Builds time out or take so long that iteration is impossible.
**Prevention:** Verify KVM access on build machine: `ls -la /dev/kvm`. For CI, use bare metal runners or VMs with nested virtualization enabled. Packer config: `accelerator: "kvm"` (default, but be explicit).
**Detection:** Packer output shows "Could not access KVM kernel module" or build takes >15 minutes for a simple image.

### Pitfall 4: Oversized .deb Packages from node_modules
**What goes wrong:** Bundling all of node_modules creates packages that are 200-500MB. Claude Code's dependency tree is substantial.
**Why it happens:** npm install pulls entire dependency trees including dev dependencies, TypeScript source maps, README files, tests.
**Consequences:** Image size balloons. Three packages at 300MB each = ~1GB of agent tools alone.
**Prevention:** Use `npm install --omit=dev` (production only). After install, prune with `npm prune --omit=dev`. Consider `node-prune` tool to strip test files, markdown, TypeScript definitions. Target: each .deb under 100MB.
**Detection:** Check .deb size after build. If >150MB, investigate what's in node_modules.

## Moderate Pitfalls

### Pitfall 5: NodeSource GPG Key Expiry in Image
**What goes wrong:** NodeSource repo GPG key baked into image expires. After expiry, `apt update` fails on all VMs built from that image.
**Prevention:** Use the current keyring approach (`/usr/share/keyrings/`), not the deprecated `apt-key add`. Build images frequently enough that keys stay fresh.

### Pitfall 6: one-context Version / OpenNebula Version Mismatch
**What goes wrong:** one-context package version doesn't match the OpenNebula server version, causing contextualization to partially fail.
**Prevention:** Check which one-context version the target OpenNebula cluster expects. v6.6.1 is safe for OpenNebula 6.x. If the cluster runs OpenNebula 5.x, use matching one-context.

### Pitfall 7: Packer SSH Timeout During Build
**What goes wrong:** Packer can't SSH into the VM during provisioning. Build hangs then fails with "Timeout waiting for SSH."
**Why it happens:** Cloud image doesn't have a default password, SSH key not injected properly during build, firewall blocking, wrong SSH port.
**Prevention:** Use Packer's `ssh_username` + `ssh_password` with a cloud-init user-data that sets the password temporarily. Or use `ssh_keypair_name` with an injected key. Serve cloud-init config via Packer's `http_directory`.

### Pitfall 8: fpm Package Name Collision
**What goes wrong:** Using generic package names (e.g., `claude-code`) that could conflict with future official packages.
**Prevention:** Prefix all packages with `agentlinux-` namespace: `agentlinux-claude-code`, `agentlinux-gsd`, etc.

### Pitfall 9: Chrome Headless Dependencies
**What goes wrong:** Google Chrome installed but won't launch because shared library dependencies are missing (libgbm, libxkbcommon, libnss3, etc.).
**Why it happens:** Debian minimal/cloud images don't include X11 or graphics libraries.
**Prevention:** Install Chrome from Google's .deb repo (properly declares dependencies). Run `apt-get install -f` to pull in everything. Test with `google-chrome --headless --dump-dom https://example.com`.

## Minor Pitfalls

### Pitfall 10: Image Disk Space During Build
**What goes wrong:** Default QCOW2 virtual disk (2GB for Debian cloud image) runs out of space when installing Node.js + Chrome + agent packages.
**Prevention:** In Packer config, set `disk_size: "10G"` or use `qemu-img resize` on the base image before building. QCOW2 is sparse -- only actual data uses host disk space.

### Pitfall 11: Locale Warnings During Build
**What goes wrong:** Provisioner scripts produce locale warnings, and some tools behave differently without proper locale.
**Prevention:** First provisioner script should configure locale: `apt-get install -y locales && locale-gen en_US.UTF-8`.

### Pitfall 12: Wrapper Script Shebang
**What goes wrong:** Wrapper scripts use `#!/bin/sh` but contain bash-isms.
**Prevention:** Use `#!/bin/bash` explicitly, or keep scripts POSIX-compliant.

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Packer setup | KVM access (#3) | Verify /dev/kvm before starting |
| Packer setup | SSH timeout (#7) | Prepare cloud-init user-data with temp password |
| .deb packaging | Oversized packages (#4) | npm prune, measure sizes early |
| .deb packaging | Arch mismatch (#2) | Build in matching Debian 12 environment |
| Image composition | cloud-init conflict (#1) | Purge cloud-init before one-context |
| Image composition | Disk space (#10) | Resize disk to 10GB |
| Chrome integration | Missing libs (#9) | Use Google's repo, test headless mode |
| First boot | one-context version (#6) | Match to target OpenNebula version |

## Sources

- [OpenNebula Forum: one-context vs cloud-init](https://forum.opennebula.io/t/one-context-vs-cloud-init/1641)
- [Packer QEMU Builder Docs](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu)
- [fpm npm Package Docs](https://fpm.readthedocs.io/en/v1.14.2/packages/npm.html)
- [Debian Wiki: Node.js](https://wiki.debian.org/Javascript/Nodejs)
