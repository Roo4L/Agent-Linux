# Stack Research

**Domain:** Installable Ubuntu plugin / agent provisioning extension (Node.js + bash + apt)
**Researched:** 2026-04-18
**Milestone:** v0.3.0 AgentLinux Plugin (pivot from custom distro to extension-on-top)
**Confidence:** HIGH (Context7-verified for npm packages; official docs verified for Ubuntu/Claude Code/Node.js)

## Scope Note

This research covers ONLY new capabilities required by the v0.3.0 pivot. The following v0.2.0 deliverables carry forward unchanged and are **not re-researched**:

- Node.js 22 LTS install via NodeSource (`setup_22.x` script)
- Google Chrome install pattern (apt repo, then `apt-mark hold`, then strip repo)
- Claude Code / GSD / Chrome DevTools MCP install patterns (npm or native installer)
- fpm-based `.deb` packaging mechanics (`fpm -s dir -t deb` with maintainer scripts)
- `~/.claude.json` MCP merge pattern with `jq`
- `/etc/skel`-based default config seeding

This document focuses on what's **net-new for the plugin**: distribution mechanism for the plugin itself, agent-user provisioning, Node.js ownership model, registry CLI framework, and test harness.

---

## Recommended Stack

### Core Technologies (NEW for v0.3.0)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **fpm** (carry-forward) | 1.17.0 | Build the `agentlinux` plugin itself as a `.deb` | Already validated in v0.2.0; one tool for both directions (built the prior packages, now builds this one); avoids the Debian-policy learning curve |
| **bash 5.x** (Ubuntu default) | system | Plugin installer body (postinst, registry shim, idempotent provisioner steps) | Already required for `apt` postinst; team has v0.2.0 bash provisioner experience; zero added runtime dependency; simpler than rewriting in Node before Node is even installed |
| **Node.js 22 LTS** (carry-forward) | 22.20.x (current LTS) | Runtime for Claude Code, registry CLI, GSD, MCP | Already validated in v0.2.0; LTS until Apr 2027; stays as system-wide install from NodeSource — see "Node.js Ownership" below for the prefix change |
| **Commander.js** | 14.0.3 | Registry CLI framework (`agentlinux list`, `agentlinux install <agent>`) | Zero dependencies, ~35M weekly downloads, smallest API surface for a thin "list/install" CLI; ~18ms `--version`, ~22ms `--help` (Commander 13 benchmark on Node 20); supports stand-alone executable subcommands which maps cleanly to per-agent install scripts |
| **jq** (carry-forward) | 1.7.x (Ubuntu apt) | JSON merging for `~/.claude.json` MCP entries and registry manifest reads | Already chosen in v0.2.0 phase 4 research; no churn |
| **Docker Engine + Ubuntu official image** | Engine 27.x; `ubuntu:24.04` image | Primary CI test harness — clean Ubuntu installer-under-test in seconds | Standard, free CI runner support (GitHub Actions has it built in), tens-of-seconds boot vs. minutes for VMs, exactly the right scope for "did the installer leave the system correct" assertions |
| **bats-core** | 1.11.x | Bash assertion framework for installer smoke tests | TAP-compliant, Ubuntu-packaged (`apt install bats`), idiomatic for testing shell-driven installers; assertion library `bats-assert` covers `assert_success`, `assert_output`, `assert_file_exists` |

### Distribution Mechanism Recommendation

**Primary: `.deb` package downloaded from GitHub Releases, installed with `apt install ./agentlinux_<ver>_amd64.deb`**

| Property | Value |
|----------|-------|
| Build tool | fpm 1.17.0 (carries forward from v0.2.0) |
| Hosting | GitHub Releases (free, signed via GitHub Actions OIDC, integrates with the existing GitHub Pages site) |
| Install command (user UX) | `wget https://github.com/<org>/agentlinux/releases/latest/download/agentlinux_amd64.deb && sudo apt install ./agentlinux_amd64.deb` |
| Update command (user UX) | Re-run install with newer .deb (or run `agentlinux self-update` if we wrap it) |
| Infra required | None beyond GitHub repo + Releases (no PPA server, no GPG key management infrastructure, no apt repo metadata to maintain) |
| Dependency resolution | `apt install` (vs. `dpkg -i`) auto-pulls declared deps (`nodejs`, `jq`, `curl`, `ca-certificates`) — this is the key reason to use `apt install ./pkg.deb` instead of `dpkg -i pkg.deb` |

**Fallback: curl-pipe-bash bootstrap script that fetches and installs the .deb**

The fallback is not an alternative distribution mechanism — it's a **convenience shim around the primary one**:

```bash
curl -fsSL https://agentlinux.org/install.sh | sudo bash
```

The script does exactly: detect arch, fetch the latest .deb URL from the GitHub Releases API, download, verify SHA256 against the release asset, run `apt install -y ./pkg.deb`, exit. Hosted on the existing `agentlinux.org` GitHub Pages site (no new infra). This gives the marketing-friendly one-liner without committing to curl-pipe-bash's known security issues (full script wrapped in a `main()` function so partial-download failures abort safely; SHA256 verification against the GitHub-signed release; user can `curl ... -o install.sh && less install.sh` to audit before running).

**Rejected alternatives:**

| Mechanism | Why Not (for v0.3.0) |
|-----------|---------------------|
| Self-hosted PPA / apt repo | Requires GPG key infrastructure, key rotation policy, repo metadata generation, ongoing apt server uptime — disproportionate for a single-package self-distribution. PROJECT.md "Out of Scope" explicitly defers PPA. Reconsider when v0.4+ adds a second package or third-party packagers want to mirror. |
| Snap | Strict confinement breaks system user provisioning (snaps can't `useradd`); snapd is a Canonical-specific runtime that conflicts with the v0.2.0-research stance against Snap bloat; AgentLinux is fundamentally a system-level extension, not a sandboxed app. |
| Pure curl-pipe-bash (no .deb) | No uninstall path (or, you have to ship a separate uninstall script users have to find later); no integration with `apt list --installed`; no dependency declaration. The .deb is cheap to build, so do it. |
| Flatpak / AppImage | Same sandboxing problem as Snap; wrong shape for a system extension. |
| One .deb per distro version (Focal / Jammy / Noble) | Premature for v0.3.0 — a single noarch-ish .deb declaring `Depends: nodejs, jq, curl, ca-certificates` works on all current Ubuntu LTS. Split if a real binary-compat issue emerges. |

### Agent-User Provisioning

Use **`useradd`** (not `adduser`) directly from the .deb's postinst, with these flags. `adduser` is interactive-friendly but its semantics shift between Debian and Ubuntu; `useradd` is the POSIX-stable building block recommended for scripted/packaged installs:

```bash
# Idempotent: only create if missing.
if ! id agent &>/dev/null; then
  useradd \
    --create-home \
    --shell /bin/bash \
    --user-group \
    --comment "AgentLinux runtime user" \
    agent
fi
```

**Flag rationale:**

| Flag | Why |
|------|-----|
| `--create-home` (`-m`) | Provisions `/home/agent` and copies `/etc/skel` contents — that's where v0.2.0's seeded `~/.claude.json`, `~/.bashrc` PATH lines, etc. land for free |
| `--shell /bin/bash` | Agents run interactive-shell-style commands (heredocs, glob expansion); `/usr/sbin/nologin` would break Claude Code immediately. NOT a daemon — do not use `--system`. |
| `--user-group` (`-U`) | Creates an `agent` group with the user as sole member — clean ownership model for `chown -R agent:agent ~agent` |
| `--comment "AgentLinux runtime user"` | Shows up in `getent passwd`, helps sysadmins understand the user's purpose |
| (No `--system`) | System users (`useradd -r`) get a UID < 1000, no aging, sometimes no shell. The agent user is a real interactive user — a human (or external automation) will SSH or `su - agent` into it. Use a regular UID. |
| (No `--password`) | No password set → cannot log in via password. Login is via `sudo -u agent -i` from the host owner, or via SSH key the user adds later. The plugin does not manage SSH keys (PROJECT.md Out of Scope: multi-user provisioning, key management). |

**Sudoers placement:** Do **not** put the agent user in `sudo` group by default. The whole point of the agent user is that it owns its own Node runtime and never needs sudo for `claude update`, `npm install -g`, or registry actions. A `/etc/sudoers.d/agentlinux` entry should be empty (file present for ownership/upgrade tracking, but no rules). If a future feature needs sudo, add a narrow `NOPASSWD` rule for one specific command path — never blanket `ALL=(ALL) ALL`.

**Locale / UTF-8:** Rely on Ubuntu's default `en_US.UTF-8` (configured by `locale-gen` during Ubuntu install). The plugin should `Depends: locales` and verify `locale -a | grep -q en_US.utf8` in postinst, regenerating only if missing. Don't override the system locale.

**`/etc/skel` usage:** Carries forward from v0.2.0 unchanged. The .deb's postinst seeds:
- `/etc/skel/.claude.json` (with default MCP entries — empty for agent registry not yet installed)
- `/etc/skel/.bashrc.d/agentlinux.sh` (PATH export for agent's npm prefix — see next section)

Then `useradd -m` copies these into `/home/agent/` automatically. For the case where `agent` already exists when the .deb installs, the postinst also iterates `/home/agent/` and merges (using `jq` for JSON, append-if-missing for the bashrc snippet).

**Sources:**
- [Ubuntu Manpage: useradd(8)](https://manpages.ubuntu.com/manpages/noble/en/man8/useradd.8.html) — flag semantics
- [Debian Wiki: SystemUsers](https://wiki.debian.org/SystemUsers) — `--system` vs regular user distinction
- [OneUptime: How to Create and Manage Users on Ubuntu](https://oneuptime.com/blog/post/2026-01-15-create-manage-users-groups-ubuntu/view) — current 2026 best practices

### Node.js Ownership Model (THE KEY DECISION)

**Recommendation: Keep system-wide NodeSource Node.js 22 LTS, but configure the agent user's npm to use `~/.npm-global` as its prefix.**

This is a deliberate **change** from v0.2.0's "system-wide everything" model — but it's a **small surgical change**, not a stack pivot. Node.js itself (the binary at `/usr/bin/node`) stays system-owned and shared. Only the npm-global prefix moves into the agent user's home.

**The mechanics (in postinst, run for the `agent` user):**

```bash
# Run as the agent user (not root)
sudo -u agent bash <<'EOF'
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'
# .bashrc.d/agentlinux.sh (seeded by /etc/skel) already exports:
#   export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
EOF
```

After this, `sudo -u agent -i` followed by `npm install -g <anything>` writes to `/home/agent/.npm-global/{bin,lib}` with `agent:agent` ownership. No sudo. No EACCES. `claude update` (which is npm-driven for npm-installed Claude Code, or self-binary-update for native-installer Claude Code) succeeds because the binary lives under the agent's home.

**Why this over the alternatives:**

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **(a) System NodeSource + per-user `~/.npm-global` prefix** ← chosen | Reuses validated v0.2.0 install path; one Node.js install for all (future) users; PATH change is a one-liner; npm prefix change is a one-liner; trivial uninstall (remove `~/.npm-global`); no shell hooks; no recursive shim risk | Slight inconsistency: `node` is at `/usr/bin/node` (system) but `npm`-installed binaries are in `~/.npm-global/bin` (user) — but this is the documented standard npm pattern, not a hack | **Use this** |
| (b) per-user nvm | Most documented "no sudo" pattern; well-known; multi-version support | Bash function injection into every shell startup (~4,700 LOC of shell sourced per terminal); slow shell startup (notable, ~200ms); fragile in non-interactive contexts (cron, CI, sshd ForceCommand) — exactly the contexts where Claude Code may be invoked; recursive shim risk if user installs another node manager later; harder uninstall (must scrub `.bashrc` modifications) | Reject — too heavyweight, too brittle in non-login shells |
| (c) per-user fnm | Rust binary, ~10ms shell hook, cross-shell, modern; can install Node per-user | Adds a second runtime concern (the fnm binary itself needs updating); harder for sysadmin to reason about ("which node am I running?") since `node` resolves through fnm shims; still has shell-hook recursion risk if user already has volta/nvm; the v0.2.0 motivation pitfall (recursive pnpm shim) is precisely this class of bug | Reject for v0.3.0; **revisit for multi-Node-version requirements in v0.4+** |
| (d) per-user volta | Per-project pinning is great; tool-version stickiness | Overkill — agentlinux is one Node version (LTS), not a polyglot tool manager; adds a binary to maintain; same shim-recursion class of risk | Reject |
| (e) Bundle Node.js binary in the .deb | Self-contained; no NodeSource dep | Massive .deb size (~50MB extra); we own the Node.js update cycle; loses NodeSource's security updates | Reject (also rejected in v0.2.0) |

**Critical gotcha to encode in postinst:** If the user previously ran `sudo npm install -g` as root before AgentLinux was installed, root-owned files in `/usr/lib/node_modules` and `/usr/local/bin` may shadow the user-owned ones via PATH. The postinst should print a warning if it detects root-owned global packages and link to a "fix it" doc. Do not silently `chown` user-system files.

**Why NOT switch Claude Code to native installer in this milestone:** The native installer (`curl -fsSL https://claude.ai/install.sh | bash`) puts Claude Code at `~/.local/bin/claude` and self-updates without npm — which is great. Phase 4 of v0.2.0 already discovered this. But: (1) it installs per-user, requiring the postinst to `sudo -u agent` invoke it (network at install time); (2) it bypasses the `agent install <name>` registry flow we're building; (3) we want the canonical acceptance test (`claude self-update`) to test our prefix-ownership solution, not Anthropic's native installer's. **For v0.3.0, install Claude Code via `npm install -g @anthropic-ai/claude-code` into the agent's `~/.npm-global` prefix.** The native installer is a future option (v0.4+) once the registry is mature enough to invoke arbitrary install scripts safely.

**Sources:**
- [npm Docs: Resolving EACCES errors](https://docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally/) — official prefix-change procedure
- [sindresorhus/guides: npm-global-without-sudo.md](https://github.com/sindresorhus/guides/blob/main/npm-global-without-sudo.md) — canonical user-writable prefix recipe
- [Claude Code: Setup docs](https://code.claude.com/docs/en/setup) — confirms `chown -R $(whoami) ~/.claude` is the published fix for sudo-poisoned installs (validates the "warn don't auto-fix" stance)

### Registry CLI Framework

**Recommendation: Commander.js 14.0.3** (Context7-verified, npm `latest` tag = `14.0.3`, `2_x` tag = `2.20.3`).

| Tool | Version | Weekly DLs | Deps | Bundle size | Best for |
|------|---------|-----------|------|-------------|----------|
| **commander** ← chosen | 14.0.3 | ~35M | 0 | small | Minimal CLIs, programmatic API, stand-alone executable subcommands |
| cac | 7.0.0 | ~5M | 0 | very small | Even more minimal than commander; chainable API; Vue/Vite ecosystem origin |
| yargs | 18.0.0 | ~30M | 7 | larger | Argument-validation-heavy CLIs, middleware chains, complex parsing |
| @oclif/core | 4.10.5 | small | many | very large | Plugin-heavy CLIs (Heroku CLI, Salesforce CLI scale); over-engineered for our 3-verb registry |

**Why Commander over the alternatives for this specific case:**

The agentlinux registry CLI has a tiny surface: `agentlinux list`, `agentlinux install <name>`, `agentlinux uninstall <name>`, `agentlinux info <name>`, `--version`, `--help`. Maybe `agentlinux update` later. There is **no** complex argument validation, **no** middleware chain, **no** plugin system needed. Commander gives us:

1. **Zero dependencies** — the .deb's npm install is one network round-trip per the framework; trivial supply chain to vet.
2. **Smallest install footprint** of the major options.
3. **Stand-alone executable subcommands** (Commander pattern: `program.command('install <name>', '...')` resolves to an external script `agentlinux-install`) which lets us ship one bash script per registry verb if we want. This dovetails with the bash-driven plugin design.
4. **Most popular** (~35M weekly DLs) → easiest hiring signal, most Stack Overflow coverage, lowest learning curve for future contributors.
5. **Battle-tested at TJ Holowaychuk / Express scale** — Commander is the npm-CLI default reference implementation.

**Why not cac:** Smaller and equally dependency-free, but smaller community (~5M DLs), less documented, and we'd be choosing it on aesthetic grounds (chainable API). Commander's slightly more imperative API is fine for 3-5 commands.

**Why not yargs:** Adds 7 transitive dependencies (supply-chain surface) and ~2x the bundle size, in exchange for argument-parsing features we won't use.

**Why not oclif:** Designed for Heroku/Salesforce-scale CLIs with plugin systems, hundreds of commands, generators, autocomplete generation, JSON schema validation. We want a `for agent in registry: print(agent)` script, not a framework.

**Registry data format:** Static JSON file at `/usr/share/agentlinux/registry.json` (shipped inside the .deb), structure like:

```json
{
  "agents": {
    "claude-code": {
      "name": "Claude Code",
      "description": "Anthropic's coding agent",
      "install": ["npm", "install", "-g", "@anthropic-ai/claude-code"],
      "default": true
    },
    "gsd": {
      "name": "Get Shit Done",
      "description": "Workflow framework for Claude Code",
      "install": ["npm", "install", "-g", "get-shit-done-cc"],
      "depends": ["claude-code"]
    },
    "chrome-devtools-mcp": {
      "name": "Chrome DevTools MCP",
      "description": "Chrome DevTools MCP server",
      "install": ["npm", "install", "-g", "chrome-devtools-mcp"],
      "post_install": ["jq", "merge", "/etc/agentlinux/mcp-templates/chrome-devtools.json", "$HOME/.claude.json"]
    }
  }
}
```

CLI reads the JSON via `fs.readFileSync` + `JSON.parse` (no DB, no fetch). Updates to the registry ship via .deb updates. **Do not** make the registry a remote-fetched dynamic catalog in v0.3.0 — that's a v0.4+ feature once we have a publishing story.

**Sources:**
- Context7 verified: `/tj/commander.js` — 265 code snippets, benchmark score 90.22, supports stand-alone executable subcommands pattern
- Context7 verified: `/cacjs/cac` — 92 snippets, benchmark score 92.5
- Context7 verified: `/yargs/yargs` — 211 snippets, benchmark score 87.3
- Context7 verified: `/oclif/oclif` — 25 snippets only (sparse documentation in Context7 is itself a signal)
- npm registry: `commander@14.0.3`, `cac@7.0.0`, `yargs@18.0.0`, `@oclif/core@4.10.5`
- [PkgPulse: How to Build a CLI with Node.js](https://www.pkgpulse.com/blog/how-to-build-cli-nodejs-commander-yargs-oclif) — comparison & benchmarks

### Test Harness (NEW)

**Primary: Docker container with `ubuntu:24.04`, driven by bats-core, run in GitHub Actions.**

The acceptance test from PROJECT.md is: *"agent user can `claude` self-update without sudo."* That is a single-host integration assertion. It does not need a full VM, a kernel, systemd, networking emulation, or persistent disk — all of which VMs add cost for.

**The test pattern (one-shot Docker container per CI run):**

```bash
# .github/workflows/installer-test.yml fragment
docker run --rm -v "$PWD":/work ubuntu:24.04 bash -lc '
  set -e
  apt-get update
  apt-get install -y ./work/dist/agentlinux_*.deb
  # Smoke: agent user exists, has writable npm prefix
  bats /work/test/installer.bats
  # Acceptance: claude self-update from agent user, no sudo
  sudo -u agent -i bash -c "claude update --quiet" || sudo -u agent -i claude --version
'
```

**Why Docker over VM-based options:**

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **Docker `ubuntu:24.04`** ← chosen | Free in GitHub Actions; ~5s container start; tens of seconds for full install+test loop; trivial to parallelize across Ubuntu versions (matrix strategy on `22.04`, `24.04`); zero infra | No systemd by default (requires `systemd` + `systemd-sysv` install if we ever need it — we don't, since the plugin doesn't ship a systemd service); root-by-default container needs `sudo -u agent` discipline | **Use this for primary CI** |
| Multipass + KVM | Real VM, full systemd, snapshot support, cloud-init parity, official Canonical tool | Requires KVM (i.e., a self-hosted CI runner — GitHub Actions hosted runners do not have KVM); overhead per test ~30-60s vs. Docker's ~5s; another tool to maintain | Skip for v0.3.0; consider for v0.4+ if we need to test cloud-init / first-boot flow |
| Vagrant + libvirt/VirtualBox | Most expressive (Vagrantfile is full Ruby); huge ecosystem of base boxes | Slow boots (~60s+); overkill for "did the .deb leave the system in the right shape"; HashiCorp BSL license drama in 2023+ | Skip — too heavy for the assertion |
| QEMU (raw) | Maximum control; no abstraction overhead | We'd be writing Vagrant or Multipass ourselves — no value-add | Skip |

**The bats-core assertions** (sketch — the executor will flesh out):

```bash
#!/usr/bin/env bats

@test "agent user exists" {
  id agent
}

@test "agent user owns ~/.npm-global" {
  test "$(stat -c '%U' /home/agent/.npm-global)" = "agent"
}

@test "agentlinux CLI is on root's PATH" {
  command -v agentlinux
}

@test "agent can list registry without sudo" {
  sudo -u agent agentlinux list | grep -q claude-code
}

@test "claude is installed for agent user" {
  sudo -u agent -i which claude
}

@test "claude self-updates without sudo (acceptance)" {
  sudo -u agent -i claude --version
  # Once Claude Code's --update flag is stable, replace with:
  # sudo -u agent -i claude update --quiet
}

@test "no root-owned files in agent home" {
  ! find /home/agent -uid 0 -print -quit | grep -q .
}
```

**Fallback / second track: Multipass on a self-hosted runner**

Only build this if the v0.3.0 user reports an environment-specific bug Docker can't reproduce (e.g., a cloud-init interaction). Don't build it speculatively. PROJECT.md already lists Multipass/QEMU as "optional second track."

**Sources:**
- [bats-core](https://github.com/bats-core/bats-core) — TAP-compliant Bash testing, `apt install bats` available
- [Docker Engine on Ubuntu install docs](https://docs.docker.com/engine/install/ubuntu/) — official source for runner setup
- [Multipass GitHub](https://github.com/canonical/multipass) — confirmed snapshot support since 1.13, fully open source as of 1.16
- [Ubuntu 24.04 on Docker](https://linuxconfig.org/running-ubuntu-24-04-lts-on-docker) — base image confirmation

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| jq (carry-forward) | 1.7.x (Ubuntu apt) | JSON merge for `~/.claude.json`, registry parse in bash fallback paths | Postinst MCP merge; non-Node CLI subscripts |
| ca-certificates | system | TLS for `curl` install bootstrap | Declared as `Depends:` in the .deb |
| curl | system | Bootstrap downloads (registry post_install hooks if any pull from network) | Declared as `Depends:` |
| locales | system | UTF-8 verification | Declared as `Depends:` |

### Development Tools (build-time only, NOT installed by users)

| Tool | Purpose | Notes |
|------|---------|-------|
| fpm 1.17.0 | Build the `agentlinux_*.deb` | Already on the build host from v0.2.0 |
| ruby + ruby-dev | fpm runtime | Build-host only; never enters the .deb |
| dpkg-deb (system) | Inspect built .deb in CI | `dpkg-deb --info`, `dpkg-deb --contents` for build-time assertions |
| shellcheck | Lint installer + registry scripts | Catches the bash gotchas that sneak past `bash -n` |
| bats-core 1.11.x | Run installer assertions in CI | Installed in the test container, not in the .deb |

## Installation

### What ships in the `agentlinux_<ver>_amd64.deb`

```
# Files installed by the .deb
/usr/bin/agentlinux                          # Commander.js CLI entrypoint (Node script with shebang)
/usr/share/agentlinux/cli/                   # CLI source + node_modules (vendored, ~200KB w/ commander only)
/usr/share/agentlinux/registry.json          # Agent registry data
/usr/share/agentlinux/install-scripts/*.sh   # One bash script per registry verb (optional pattern)
/etc/agentlinux/mcp-templates/*.json         # MCP entry templates for known agents
/etc/skel/.bashrc.d/agentlinux.sh            # PATH export snippet
/etc/skel/.claude.json                       # Default Claude Code config (empty MCP)
/etc/sudoers.d/agentlinux                    # (empty, present for upgrade tracking)

# Maintainer scripts inside the .deb
DEBIAN/postinst    # creates agent user, sets npm prefix, installs default agent (Claude Code)
DEBIAN/prerm       # warns if agent has unsaved work (or skip — not our concern)
DEBIAN/postrm      # removes agent user IFF home is empty AND --purge passed; otherwise leaves it
```

### Build commands (on the developer's machine or CI)

```bash
# 1. Build the CLI bundle (vendored node_modules, no devDeps)
cd cli/
npm ci --omit=dev
cd ..

# 2. Stage the .deb tree
mkdir -p staging/usr/bin staging/usr/share/agentlinux/cli
cp -r cli/{package.json,bin,src,node_modules} staging/usr/share/agentlinux/cli/
cp registry.json staging/usr/share/agentlinux/
cp -r mcp-templates/ staging/etc/agentlinux/mcp-templates/
cp -r skel/ staging/etc/skel/
ln -sf /usr/share/agentlinux/cli/bin/agentlinux staging/usr/bin/agentlinux

# 3. fpm build (carries forward from v0.2.0 phase 4 patterns)
fpm -s dir -t deb \
  --name agentlinux \
  --version 0.3.0 \
  --architecture amd64 \
  --depends "nodejs (>= 22)" \
  --depends "jq" \
  --depends "curl" \
  --depends "ca-certificates" \
  --depends "locales" \
  --description "Installable Ubuntu extension provisioning an agent-ready environment" \
  --maintainer "AgentLinux <hello@agentlinux.org>" \
  --url "https://agentlinux.org" \
  --license "MIT" \
  --after-install scripts/postinst.sh \
  --before-remove scripts/prerm.sh \
  --after-remove scripts/postrm.sh \
  --deb-no-default-config-files \
  -C staging \
  .
```

### User install (one command)

```bash
# Direct .deb (primary)
wget https://github.com/<org>/agentlinux/releases/latest/download/agentlinux_amd64.deb
sudo apt install ./agentlinux_amd64.deb

# Or, bootstrap (fallback / marketing one-liner)
curl -fsSL https://agentlinux.org/install.sh | sudo bash
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Direct .deb from GitHub Releases | Self-hosted PPA | When v0.4+ adds multiple packages or third parties want to mirror the repo (justifies GPG infrastructure cost) |
| System NodeSource + per-user `~/.npm-global` | per-user fnm | When v0.4+ needs to support multiple Node.js versions per agent OR when supporting Linux distros without a current Node.js LTS package |
| Commander.js | cac | Pure aesthetic preference for chainable API; no functional reason in v0.3.0 |
| Commander.js | oclif | When the registry grows past ~10 verbs and needs a real plugin system (not in v0.3.0 scope) |
| Docker for tests | Multipass | When a bug requires real systemd or cloud-init reproduction (build only when needed) |
| `useradd` directly | `adduser --disabled-password` | Never — `useradd` is the scriptable, Debian/Ubuntu-stable choice for packages |
| bash for installer body | Python or Node | When the installer logic exceeds ~500 lines OR needs structured error handling beyond `set -e` + traps. v0.3.0 will not approach this. |
| bats-core for tests | shunit2 / pytest+pexpect | When you need cross-language assertions or already have a pytest harness; not the case here |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **Snap as distribution mechanism** | Strict confinement breaks `useradd`; AgentLinux is a system extension, not a sandboxed app | `.deb` from GitHub Releases (primary) |
| **Self-hosted PPA in v0.3.0** | Disproportionate infrastructure cost for one package; GPG key rotation is real work; PROJECT.md explicitly defers | Direct .deb download; revisit in v0.4+ |
| **nvm as the agent's Node.js manager** | 4,700-line bash script sourced into every shell; slow startup; fragile in non-interactive shells (cron, sshd, CI) — exactly where Claude Code may run | System NodeSource + `~/.npm-global` prefix |
| **fnm/volta in v0.3.0** | One Node version (LTS) is enough for v0.3.0; adds another runtime concern; shim-recursion is the bug class AgentLinux exists to eliminate | System NodeSource + `~/.npm-global` prefix; revisit fnm if multi-version becomes a hard requirement |
| **oclif** | Designed for Heroku/Salesforce-scale CLIs; massive dependency tree; needless complexity for 3-5 verbs | Commander.js |
| **yargs** | 7 transitive dependencies; unused features (middleware, validation chains); 2x bundle size | Commander.js |
| **Ansible / Puppet / Chef / SaltStack** | Designed for fleet management; multi-host orchestration; pulls in Python or Ruby runtimes; massive overkill for a single-host one-shot installer | bash + apt + Node — that's it |
| **Docker as a runtime dependency for end users** | PROJECT.md "Permanently out of scope: Docker-in-Docker"; agent runs on host directly | Docker is a TEST-ONLY dependency, never declared in `Depends:` |
| **systemd unit for agentlinux** | The plugin is a one-shot installer + a CLI; nothing daemonizes; no systemd unit needed | postinst runs once, registry CLI is invoked on demand |
| **adduser instead of useradd in postinst** | `adduser` is interactive-friendly with semantics that drift between Debian and Ubuntu | `useradd` with explicit flags — POSIX-stable scripted invocation |
| **Public npm publish for the registry CLI** | The CLI is meaningless outside the .deb (depends on `/usr/share/agentlinux/registry.json`); publishing to npm just creates a confusing duplicate install path | Vendor `node_modules/` inside the .deb; never publish to npm |
| **`curl ... \| bash` as PRIMARY mechanism** | No uninstall path; no `apt list --installed` integration; no dependency declaration | Use `curl ... \| bash` only as a fallback that internally `apt install`s the .deb |
| **dpkg -i (instead of apt install ./pkg.deb)** | dpkg doesn't resolve dependencies — installs would fail on missing nodejs/jq | Always document `apt install ./agentlinux_amd64.deb` |
| **Ubuntu pre-packaged Node.js (`apt install nodejs`)** | Ubuntu Noble ships Node.js 18.19 (out of LTS in 2026); will break Claude Code | NodeSource setup_22.x (carries forward from v0.2.0) |
| **chown -R during postinst to fix prior sudo-poisoned npm installs** | Hides bugs; users learn nothing; potentially destroys files in unexpected ways | Detect, warn loudly, link to documented fix; let the user run the chown |

## Stack Patterns by Variant

**If the user is installing on a fresh Ubuntu host:**
- `apt install ./agentlinux_amd64.deb`
- postinst creates `agent` user, sets npm prefix, installs Claude Code, prints success message with `sudo -u agent -i` invocation
- No surprises; standard apt install UX

**If the user already has a user named `agent`:**
- postinst detects existing user via `id agent`
- If home directory already has `~/.npm-global` with non-root ownership, leave it alone (idempotent)
- If home has root-owned npm artifacts, print warning + link to fix; do not auto-chown

**If the user previously ran `sudo npm install -g`:**
- postinst inspects `/usr/lib/node_modules` and `/usr/local/bin` for stale Claude Code / GSD / MCP installs
- Warn that these may shadow the agent's installs via PATH precedence
- Document a one-line fix (`sudo npm uninstall -g <pkg>`) but do not run it

**If the user installs on Ubuntu 22.04 (vs. 24.04):**
- 22.04 ships apt without DEB822 support — use legacy `.list` files in keyring fragment
- Otherwise identical (Node.js 22 LTS available on both via NodeSource)
- Test matrix in CI covers both

**If the user installs on a non-Ubuntu Debian-family distro (Debian, Pop!_OS, Mint):**
- Out of scope for v0.3.0 explicit support, but the .deb will likely just work if Node.js 22 is available
- Do not advertise compatibility; do not block install

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| Node.js 22.x LTS | npm 10.x (bundled) | NodeSource ships matched pair |
| Node.js 22.x LTS | @anthropic-ai/claude-code 2.x | Claude Code 2.x requires Node 18+; 22 LTS is comfortably in range |
| commander 14.x | Node.js >= 20 | commander 14 dropped Node 18; use commander 12.x if Ubuntu 22.04 ships Node < 20 (it doesn't via NodeSource setup_22.x) |
| Ubuntu 24.04 | DEB822 sources format | Default since 24.04; legacy .list still works |
| Ubuntu 22.04 LTS | NodeSource Node.js 22 | Confirmed compatible |
| fpm 1.17.0 | Ruby 2.7+ | Available via Ubuntu apt; build-host only |
| bats-core 1.11.x | bash 3.2+ | Trivially satisfied on Ubuntu |

**Node.js 22 vs. 24:** Node 22 is in **Maintenance LTS through April 2027**. Node 24 entered Active LTS in late 2025 and is in Active LTS through October 2026 (then Maintenance through April 2028). Either is defensible; staying on 22 carries forward v0.2.0 validation with zero risk. **Recommendation: stay on Node.js 22 for v0.3.0**, plan a Node 24 bump for v0.4 (after the Active→Maintenance transition for 22 in late 2026 or early 2027). Tracked as a v0.4+ research flag, not a v0.3.0 concern.

## Carry-Forward Integration with v0.2.0 Stack

This is what stays exactly the same so the executor doesn't churn it:

| v0.2.0 Decision | v0.3.0 Status | Notes |
|-----------------|---------------|-------|
| NodeSource setup_22.x | **Unchanged** | Same script, same source, same install command |
| fpm 1.17.0 | **Unchanged** | Now builds the plugin .deb instead of three agent-tool .debs |
| jq for JSON merging | **Unchanged** | Same patterns from v0.2.0 phase 4 research |
| `~/.claude.json` MCP location | **Unchanged** | v0.2.0 phase 4 corrected this — stays correct |
| `/etc/skel/.claude.json` seeding | **Unchanged** | Used identically by `useradd -m` |
| `--no-sandbox` for Chrome MCP | **Unchanged** | When the registry installs chrome-devtools-mcp, it uses the same MCP entry shape |
| Google Chrome via Google apt repo + apt-mark hold + repo cleanup | **Unchanged** | Used by the registry's chrome-devtools-mcp install verb |
| `npm install -g` for Claude Code | **Unchanged for v0.3.0** | But install target changes from system `/usr/lib` to `/home/agent/.npm-global/lib` |
| Chrome DevTools MCP via npm + `npx -y chrome-devtools-mcp@latest` MCP config | **Unchanged** | Carries forward verbatim |

What's NEW (everything else in this document): plugin distribution mechanism, agent-user provisioning, npm prefix configuration, registry CLI, Docker/bats test harness.

What's RETIRED (do not include in v0.3.0):
- Packer + QEMU image build (v0.2.0)
- Three separate `.deb` packages for Claude Code / GSD / MCP (v0.2.0)
- Local apt repo embedded in image (v0.2.0)
- OpenNebula contextualization (v0.2.0)
- one-context (v0.2.0)
- Debian 12 Bookworm as base (v0.2.0 — now Ubuntu LTS)

## Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Distribution mechanism (.deb + GitHub Releases primary, curl-pipe-bash fallback) | HIGH | Multiple verified sources; aligns with PROJECT.md's "no public PPA" Out of Scope; reuses validated v0.2.0 fpm tooling |
| Agent-user provisioning with `useradd` | HIGH | Ubuntu manpage authoritative; flags well-documented; pattern is decades-old standard |
| Node.js ownership (system NodeSource + `~/.npm-global` prefix) | HIGH | Officially documented npm pattern; verified by sindresorhus/guides + npm Docs; explicitly avoids the v0.2.0 motivating bug class |
| Registry CLI = Commander.js | HIGH | Context7-verified; npm latest tag confirmed; sized appropriately for the verb count; zero deps |
| Test harness = Docker + bats-core | HIGH | Both are standard tools; GitHub Actions support is built-in; pattern is widely used |
| Node.js 22 LTS retained | HIGH | EOL April 2027 confirmed via nodejs.org/about/eol; carries forward v0.2.0 validation |
| Don't-add list (Snap, Ansible, oclif, fnm in v0.3.0) | HIGH | Each has a specific named reason rooted in PROJECT.md scope or known-bug class |

## Sources

### Primary (HIGH confidence)
- [Ubuntu Manpage: useradd(8)](https://manpages.ubuntu.com/manpages/noble/en/man8/useradd.8.html) — flag semantics for system user creation
- [Debian Wiki: SystemUsers](https://wiki.debian.org/SystemUsers) — `--system` vs regular user distinction
- [npm Docs: Resolving EACCES errors](https://docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally/) — official user-writable prefix recipe
- [sindresorhus/guides: npm-global-without-sudo.md](https://github.com/sindresorhus/guides/blob/main/npm-global-without-sudo.md) — canonical recipe
- [Claude Code Setup Docs](https://code.claude.com/docs/en/setup) — auto-update mechanism, sudo-ownership warnings
- [Node.js EOL Schedule](https://nodejs.org/en/about/eol) — Node 22 LTS dates
- Context7: `/tj/commander.js` — Commander documentation, subcommand patterns
- Context7: `/cacjs/cac` — CAC documentation
- Context7: `/yargs/yargs` — Yargs documentation
- Context7: `/oclif/oclif` — oclif documentation
- npm registry (verified live): `commander@14.0.3`, `cac@7.0.0`, `yargs@18.0.0`, `@oclif/core@4.10.5`, `@anthropic-ai/claude-code@2.1.114`, `get-shit-done-cc@1.37.1`, `chrome-devtools-mcp@0.21.0`, `n@10.2.0`
- [bats-core](https://github.com/bats-core/bats-core) — TAP-compliant Bash testing
- [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/) — official install docs

### Secondary (MEDIUM confidence)
- [Multipass GitHub](https://github.com/canonical/multipass) — confirmed 1.16+ open source, snapshots since 1.13
- [Ubuntu Discourse: Spec — APT deb822 sources by default](https://discourse.ubuntu.com/t/spec-apt-deb822-sources-by-default/29333) — DEB822 transition status
- [Debian Wiki: DebianRepository/UseThirdParty](https://wiki.debian.org/DebianRepository/UseThirdParty) — keyring placement standards
- [PkgPulse: How to Build a CLI with Node.js](https://www.pkgpulse.com/blog/how-to-build-cli-nodejs-commander-yargs-oclif) — CLI framework comparison
- [Leapcell: nvm vs Volta vs fnm Deep Dive](https://leapcell.io/blog/navigating-node-js-versions-a-deep-dive-into-nvm-volta-and-fnm) — Node version manager tradeoffs
- [Sysdig: Friends don't let friends curl | bash](https://www.sysdig.com/blog/friends-dont-let-friends-curl-bash) — curl-pipe-bash security analysis
- [Chef: 5 Ways to Deal With the install.sh Curl Pipe Bash problem](https://www.chef.io/blog/5-ways-to-deal-with-the-install-sh-curl-pipe-bash-problem) — mitigation patterns
- [DigitalOcean: apt-key Deprecation, Add Repositories with GPG](https://www.digitalocean.com/community/tutorials/how-to-handle-apt-key-and-add-apt-repository-deprecation-using-gpg-to-add-external-repositories-on-ubuntu-22-04) — modern keyring practices
- [Claude Code Native Installer: Skip Node.js Entirely](https://claudefa.st/blog/guide/native-installer) — context for the deferred native-installer path

### Tertiary (LOW confidence — directional only)
- [Heissen Lopez: Volta vs fnm](https://heilop.com/posts/volta-vs-fnm-nodejs-version-managers/) — opinion piece, not authoritative
- [The New Stack: Multipass](https://thenewstack.io/multipass-fast-scriptable-ubuntu-vms-for-modern-devops/) — vendor-friendly summary

---

*Stack research for: AgentLinux v0.3.0 — Installable Ubuntu plugin*
*Researched: 2026-04-18*
*Confidence: HIGH overall*
