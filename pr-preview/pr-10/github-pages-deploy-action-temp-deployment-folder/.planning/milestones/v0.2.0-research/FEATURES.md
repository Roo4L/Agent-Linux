# Feature Landscape

**Domain:** Agent-focused Linux distribution (v0.2.0 -- first image)
**Researched:** 2026-03-10

## Table Stakes

Features that must exist for the image to demonstrate the AgentLinux concept.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Bootable QCOW2 image on KVM | Without this, nothing works | High | Packer + QEMU builder, Debian 12 base |
| OpenNebula contextualization | Target infra is OpenNebula; image must configure itself on boot | Medium | one-context package handles SSH, networking, hostname |
| Agent user with SSH access | Agents connect via SSH; no user = no access | Low | Create `agent` user in image build, one-context injects SSH keys |
| Claude Code .deb package | Core agent tool, headline feature | Medium | Bundle npm package + node_modules, wrapper script |
| GSD framework .deb package | Supporting agent tool for task management | Medium | Same approach as Claude Code |
| Chrome DevTools MCP server .deb | Demonstrates MCP server packaging with system deps | High | Requires Chrome browser as dependency |
| Node.js 22 LTS pre-installed | Runtime dependency for all agent .deb packages | Low | NodeSource repo baked into image |
| Automated/reproducible build | Must be rebuildable from source, not a hand-crafted snowflake | Medium | Packer HCL template + shell provisioners |

## Differentiators

Features that set this apart from "just another Debian cloud image."

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Agent user as default persona | Image boots ready for agent use, not human admin | Low | Convention: `agent` user, home at `/home/agent`, sudo access |
| Native package manager for agent tools | `apt install agentlinux-claude-code` -- no npm/pip fragility | Medium | Custom .deb packages in local repo or pre-installed |
| Pre-configured tool paths | Agent tools on PATH, no activation/sourcing needed | Low | Wrapper scripts in `/usr/local/bin/` |
| Minimal attack surface | No desktop, no unnecessary services, small image | Low | Debian genericcloud base is already minimal |

## Anti-Features

Features to explicitly NOT build in v0.2.0.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Local apt repository / PPA | Premature -- no update mechanism needed yet, adds hosting complexity | Pre-install .deb packages in image, defer repo hosting |
| Package groups / workload bundles | Out of scope per PROJECT.md | Install individual packages |
| GUI / desktop environment | Agents don't need displays; adds 500MB+ to image | Headless only, Chrome runs headless for DevTools MCP |
| Docker-in-Docker | Complex, security implications, not needed for v0.2.0 | Run agent tools natively |
| Multi-arch support (ARM) | OpenNebula target is amd64 KVM | amd64 only |
| ISO / live image format | Target is QCOW2 for OpenNebula | QCOW2 only |
| Auto-update mechanism | Premature for first image | Manual rebuilds |
| Agent skills system | Future milestone per PROJECT.md | Defer |

## Feature Dependencies

```
NodeSource repo in image --> Node.js 22 installed --> .deb packages can run
one-context in image --> SSH key injection --> agent user accessible
Packer build works --> QCOW2 produced --> can test on OpenNebula
Chrome .deb installed --> Chrome DevTools MCP server can launch browser
```

## MVP Recommendation

Prioritize in this order:

1. **Packer build producing bootable QCOW2** -- gate for everything else
2. **one-context + agent user** -- gate for SSH access and testing
3. **Claude Code .deb** -- headline feature, proves the packaging approach
4. **GSD .deb** -- same pattern as Claude Code, fast follow
5. **Chrome DevTools MCP .deb** -- most complex (Chrome dependency), do last

Defer: Local apt repo, auto-updates, multi-arch -- all future milestones.
