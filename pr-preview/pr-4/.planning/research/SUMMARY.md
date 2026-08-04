# Project Research Summary

**Project:** AgentLinux v0.3.0 — Installable Ubuntu Plugin
**Domain:** Linux system extension / agent-environment provisioner (bash installer + Node.js CLI)
**Researched:** 2026-04-18
**Confidence:** HIGH overall

## Executive Summary

AgentLinux v0.3.0 is a one-command Ubuntu installer that provisions a dedicated `agent` user with a correctly-owned Node.js runtime, a pre-installed default agent (Claude Code), and a curated registry CLI for adding more agents. The product is best understood as a hybrid of two well-understood patterns: a service-user installer (like Jenkins or PostgreSQL packages, which create a functional system account with a real shell) and a tooling manager (like Homebrew or mise, which list and install things). No existing tool combines both. The canonical acceptance test — "the agent user can `claude update` without sudo on a fresh Ubuntu install" — directly exercises the motivating bug class (EACCES from root-owned npm globals) and must be green before shipping.

The recommended implementation is a bash installer entrypoint (`bin/agentlinux-install`) that runs four ordered, idempotent provisioner scripts, plus a Node.js/Commander.js registry CLI (`agentlinux list/install/remove`) that ships as a vendored package inside `/opt/agentlinux/`. Distribution is curl-pipe-bash as primary (wrapping a SHA256-verified tarball download) with an optional `.deb` built by fpm as a secondary path — the reverse of what STACK.md proposed. Tests run in Docker (every PR, fast) and QEMU (nightly and release gate, definitive). The most critical implementation decision for v0.3.0 is how Claude Code itself is installed: the four research files contain a genuine tension (npm install vs. native binary installer) that requires user input before Phase 2 requirements can be locked.

The single biggest risk is subtle ownership mistakes that make the install look correct until an agent tries to self-update or run in a non-interactive context (cron, systemd, `sudo -u agent`). Belt-and-braces PATH setup — `/etc/profile.d/`, stubs in `/usr/local/bin/`, and `Defaults:agent secure_path` in sudoers — is mandatory, not optional. Docker tests have known false-positive categories (root-by-default, no systemd, C/POSIX locale) that must be compensated for; QEMU is required as the release gate.

---

## Key Findings

### Recommended Stack

The v0.3.0 stack is almost entirely carry-forward from v0.2.0 with three surgical additions: a distribution mechanism for the plugin itself, an agent-user provisioning model, and a registry CLI framework.

**Core technologies:**

| Technology | Purpose | Why Recommended |
|------------|---------|-----------------|
| bash 5.x (system) | Installer body, provisioner scripts | Zero added runtime dep; postinst-compatible; team has v0.2.0 experience |
| Node.js 22 LTS via NodeSource | Agent runtime, registry CLI runtime | Carry-forward; EOL April 2027; system-wide binary avoids shell-hook activation problems |
| per-user `~/.npm-global` prefix | npm install destination for the agent user | The keystone decision: moves npm globals into agent home so self-update never needs sudo |
| Commander.js 14.0.3 | Registry CLI framework | Zero dependencies; 35M weekly downloads; right-sized for 3-5 verbs |
| fpm 1.17.0 | Build optional `.deb` | Carry-forward from v0.2.0; already validated |
| jq 1.7.x | JSON merge for `~/.claude.json` MCP config | Carry-forward from v0.2.0 |
| bats-core 1.11.x | Bash assertion framework for installer tests | TAP-compliant; apt-installable; idiomatic for shell installer testing |
| Docker + ubuntu:22.04/24.04 | Primary CI test harness | Free in GitHub Actions; ~90s per run; matrix across Ubuntu versions |

**Structurally disqualified (do not revisit for v0.3.0):**
- Snap: AppArmor confinement incompatible with whole-filesystem agent access
- nvm/fnm/volta: shell-hook activation breaks non-interactive shells (cron, systemd, `sudo -u agent`)
- Ansible/Chef/Puppet: single-host installer does not need fleet management tooling
- oclif: designed for Heroku-scale CLIs; overkill for 3-5 verbs
- Ubuntu's packaged nodejs: ships Node.js 18.19 (out of LTS in 2026)
- `dpkg -i` (use `apt install ./pkg.deb` instead for dependency resolution)

### Expected Features

**Must have — table stakes (all P1, ships in v0.3.0):**
- One-command installer for Ubuntu 22.04 + 24.04 (curl-pipe-bash primary)
- Dedicated `agent` user: real interactive user via `useradd -m -s /bin/bash --user-group`, regular UID (not `--system`), no password
- Node.js 22 LTS from NodeSource (system-wide binary, per-user npm prefix)
- Writable npm global prefix at `~/.npm-global` owned by the agent user
- Default agent installed on first install: Claude Code (with `--no-default-agent` flag for CI use)
- `agentlinux list / install / remove` registry CLI
- Idempotent installer (safe to re-run; converges, never destroys)
- Canonical acceptance test: `sudo -u agent -i claude update` exits 0, no EACCES
- Uninstall path (`agentlinux uninstall` + `--purge` option)
- Initial catalog: 3 definite agents (claude-code, gsd, chrome-devtools-mcp)
- Docker + bats test harness in CI

**Should have — differentiators (P2, fast-follow patches):**
- `agentlinux info <agent>`, `agentlinux update <agent>`, `agentlinux doctor`
- `agentlinux self-update` (re-fetches and re-runs install script; mise pattern)
- QEMU-based test runner (nightly + release gate)
- `install-verified.json` marker file + `CLAUDE.md` in agent home (prevents agent from inventing npx shims post-install)

**Defer to v0.4+:**
- Cross-distro support (Fedora, Arch, CentOS)
- Public PPA with package signing
- Multi-tenant agent users
- Remote-fetch catalog (embedded-only for v0.3.0; remote merge as optional env-var override)
- Claude Code native binary installer path (pending OQ-1 decision — see Open Questions)
- fnm/volta for multi-version Node.js support

**Permanent anti-features (excluded for all versions):**
- GUI/TUI installer
- Docker-in-Docker inside the agent environment
- Agent sandboxing (Claude Code's job, not ours)
- Auto-update daemon (opt-in manual `self-update` only)
- Telemetry / phone-home

### Architecture Approach

The plugin is a bash-orchestrated installer plus a Node.js registry CLI. The installer entrypoint (`bin/agentlinux-install`) sources shared bash helpers from `lib/` and executes four ordered, idempotent provisioner scripts in sequence. The registry CLI (`cli/`) is a Node.js/Commander.js project that reads `catalog/catalog.json` and dispatches to per-agent `catalog/agents/<name>/install.sh` bash scripts — the same scripts the provisioner called during initial install. This single-code-path design means "install an agent via provisioner" and "install an agent via registry CLI" are identical operations.

**Major components:**

| Component | Responsibility |
|-----------|----------------|
| `bin/agentlinux-install` | Entrypoint; parses flags, sources lib, runs provisioner scripts in order |
| `lib/*.sh` | Shared bash helpers: logging, idempotency primitives (`ensure_user`, `ensure_line_in_file`, `ensure_npm_prefix`), `as_user` wrapper, distro detection |
| `provisioner/10-agent-user.sh` | Creates `agent` user, configures sudoers drop-in (validated with `visudo -c -f`), sets locale, seeds `~/.bashrc` PATH |
| `provisioner/30-nodejs.sh` | Installs NodeSource Node.js 22; runs `as_user agent npm config set prefix ~/.npm-global` |
| `provisioner/40-default-agent.sh` | Installs default agent as the agent user; seeds `~/.claude.json` from template |
| `provisioner/50-registry-cli.sh` | Installs the `agentlinux` CLI for the agent user; writes bash completion |
| `cli/` (Node.js) | Registry CLI: `list`, `install`, `remove`, `info`, `doctor`; reads `catalog.json`, dispatches to per-agent scripts via `runner.js` |
| `catalog/` | `schema.json` (JSON Schema contract), `catalog.json` (embedded data), `agents/<name>/install.sh` (per-agent logic) |
| `packaging/curl-installer/install.sh` | Primary distribution: verifies SHA256, extracts to `/opt/agentlinux/`, execs `bin/agentlinux-install` |
| `packaging/deb/` | Optional fpm wrapper; secondary distribution path |
| `tests/bats/` | Black-box assertion suite; runs inside the target environment |
| `tests/docker/` | Fast CI runner: clean Ubuntu image, installer, bats (~90s, every PR) |
| `tests/qemu/` | Definitive runner: fresh Ubuntu cloud image over SSH (~5min, nightly + release gate) |

All v0.3.0 code lives under `plugin/` in the repo; `packaging/` holds distribution wrappers; `website/` and `.planning/` are unchanged.

### Critical Pitfalls

1. **System-wide Claude Code install breaks self-update (the original bug class)** — Any install that runs as root produces root-owned files in paths the agent user must write to. `claude update` fails with EACCES. Prevention: always `sudo -u agent -H` before any Claude Code install; verify with `claude doctor` as the final installer step; run `sudo -u agent -i claude update` in every CI run.

2. **PATH not set for non-interactive invocations (cron, systemd, `sudo -u agent`, non-interactive SSH)** — `~/.bashrc` is only sourced in interactive shells. PATH must be wired via all four mechanisms: `/etc/profile.d/agentlinux-path.sh`, stub wrappers in `/usr/local/bin/`, `Defaults:agent secure_path` in sudoers, and explicit `Environment=PATH=...` in any systemd units. If any path is missing, agents create wrapper shims — the exact bug this project exists to eliminate.

3. **nvm/fnm/volta shell-hook activation breaks non-interactive shells** — Version managers inject via `~/.bashrc`. Non-interactive shells skip this file. `node` and `npm` vanish from PATH in cron, systemd, and `sudo -u agent <cmd>`. Prevention: NodeSource system Node.js (`/usr/bin/node`, always on PATH), per-user prefix for globals only.

4. **Installer not idempotent (pre-existing user, pre-existing Node, re-runs)** — `useradd agent` fails if user exists. `echo >> ~/.bashrc` duplicates lines. Every operation must go through idempotency primitives. CI must test: fresh install, re-run on same system, install with pre-existing `agent` user, install with Node already present.

5. **Sudoers misconfiguration bricks sudo for all users** — Bad syntax, wrong file mode (must be 0440), wrong filename (dot in name is silently ignored by sudo), or `NOPASSWD: ALL`. Prevention: always validate with `visudo -c -f /tmp/staged` before deploying; use `install -m 0440 -o root -g root` (atomic).

6. **Docker tests pass, real Ubuntu fails** — Docker runs as root by default (masks missing sudo paths), has no systemd, uses C/POSIX locale, assigns UID 1000 by default. Prevention: run test container as non-root; generate locale in test image; require QEMU as release gate.

---

## Tensions Resolved

### Distribution Mechanism: curl-pipe-bash primary, .deb secondary

STACK.md recommends `.deb` as primary. ARCHITECTURE.md recommends curl-pipe-bash as primary. **Resolution: curl-pipe-bash is primary for v0.3.0.**

The curl-pipe-bash installer is a thin wrapper that downloads a SHA256-verified release tarball and execs `bin/agentlinux-install`. This avoids the NodeSource-dependency-declaration problem inherent in `.deb` (the .deb can't auto-install NodeSource Node.js without bundling the repo setup script — which is exactly what the bash installer already does). The `.deb` path is built as an optional secondary for users who prefer package management. Both paths converge on the same `bin/agentlinux-install` entrypoint, so there is exactly one installer to test and maintain.

### Agent User sudo: no NOPASSWD by default

PROJECT.md v0.2.0 gave the agent user passwordless sudo. The v0.3.0 core value message is "agent user never needs sudo." **Resolution: no NOPASSWD sudo in the default install.** The agent user's entire toolchain (claude, npm, gsd, agentlinux) must work without escalation. The `/etc/sudoers.d/agentlinux` file is present for upgrade tracking and `Defaults:agent secure_path` wiring, but contains no NOPASSWD grant. A `--with-sudo` flag can be added if a specific use case demands it.

### PATH setup: belt-and-braces is mandatory

Other docs treat PATH wiring as "configure `~/.bashrc`." PITFALLS.md is emphatic that this is insufficient. **Resolution: all four layers are mandatory:**
1. `/etc/profile.d/agentlinux-path.sh` — login shells
2. Stub wrappers in `/usr/local/bin/` (root-owned, pointing at agent's `~/.npm-global/bin/`) — cron and sudo
3. `Defaults:agent secure_path` in sudoers — `sudo -u agent <cmd>`
4. Explicit `Environment=PATH=...` in any systemd unit files

The stub-wrapper pattern is safe: the wrapper is root-owned (survives sudo's secure_path) but points at the agent's home path where self-update writes. Self-update updates `~/.npm-global/bin/claude`; the wrapper continues pointing at it.

---

## Open Questions

These require user input before requirements can be locked. The requirements step must resolve them.

### OQ-1: Claude Code install mechanism — npm vs native binary installer (HIGH PRIORITY)

This is the most consequential open decision for v0.3.0.

**Option A — npm install (STACK.md / FEATURES.md / ARCHITECTURE.md position):**
`sudo -u agent npm install -g @anthropic-ai/claude-code` into agent's `~/.npm-global`. The per-user npm prefix is the keystone decision; this exercises it directly. The acceptance test validates the prefix ownership story. Consistent with carrying forward v0.2.0 install patterns.

**Option B — native binary installer (PITFALLS.md position):**
`sudo -u agent -H curl -fsSL https://claude.ai/install.sh | bash`. Installs to `~/.local/bin/claude`; self-updates via atomic binary replacement; does not involve npm at runtime. Anthropic's current documented recommended install path. Avoids GitHub issue #9327 where `npm install -g --prefix=~/.local` creates a symlink that the self-updater clobbers.

The tension: three of four research docs assume Option A; PITFALLS.md recommends Option B citing current Anthropic documentation. STACK.md explicitly defers Option B to v0.4+ arguing that v0.3.0 should validate the per-user prefix solution end-to-end.

**Ask the user:** if the goal is to validate the npm-prefix ownership model, choose Option A. If the goal is to use Anthropic's recommended path and maximize long-term reliability, choose Option B. The `~/.local/bin` PATH plumbing is effectively identical either way.

### OQ-2: Distribution mechanism confirmation

Research converges on curl-pipe-bash primary, .deb optional secondary. Confirm with user that they do not want to invest in `.deb` as primary for v0.3.0.

### OQ-3: Catalog schema format — JSON vs TOML

FEATURES.md suggests TOML. ARCHITECTURE.md and STACK.md use JSON. **Recommendation: JSON** — Node.js reads it natively, no extra dep. Confirm with user.

### OQ-4: Initial catalog scope — include @openai/codex?

The 3 definite agents are agreed. `@openai/codex` is "nice-to-include" — identical npm install recipe, validates the registry is not Anthropic-only. Low risk either way. Confirm with user.

---

## Implications for Roadmap

All three structural researchers converged on a 4-6 phase plan. The synthesis below collapses overlapping suggestions into a single recommended phase list.

### Phase 1: Installer Foundation

**Rationale:** Everything depends on a correct agent user with correct PATH wiring. The most critical pitfalls live here. Idempotency patterns established here prevent retrofitting later.
**Delivers:** Running `bin/agentlinux-install` on a fresh Ubuntu 22.04 or 24.04 produces a correct `agent` user with bash shell, locale, sudoers drop-in (validated with `visudo -c -f`), and belt-and-braces PATH setup. No agents installed yet.
**Addresses:** TS-1, TS-2, TS-3, TS-10 (idempotency)
**Must avoid:** Pitfall 4 (PATH dropped), Pitfall 5 (non-idempotent), Pitfall 8 (locale), Pitfall 9 (sudoers)
**Research flag:** Standard patterns — `useradd`, `/etc/sudoers.d/`, `/etc/profile.d/`, locale-gen are all well-documented; no research phase needed.

### Phase 2: Node.js Ownership + Default Agent Install

**Rationale:** The keystone and highest-risk phase. The canonical acceptance test lives here. npm prefix ownership, PATH wiring for npm-global bin dir, and Claude Code install must all be correct before anything is built on top. OQ-1 (npm vs native installer) must be resolved before this phase begins.
**Delivers:** NodeSource Node.js 22 installed; agent user's npm prefix configured; Claude Code installed as the agent user; `~/.claude.json` seeded. Canonical acceptance test (`sudo -u agent -i claude update`) passes.
**Addresses:** TS-4, TS-5, TS-6, TS-11
**Must avoid:** Pitfall 1 (system-wide Claude Code install), Pitfall 2 (npm prefix for other packages), Pitfall 3 (nvm), Pitfall 10 (/etc/skel inadequacy), Pitfall 12 (conflicting installs)
**Research flag:** OQ-1 must be decided by the user. Once resolved, PITFALLS.md has detailed implementation guidance for both paths. No additional research phase needed.

### Phase 3: Test Harness

**Rationale:** Build the test harness immediately after Phase 2 passes the acceptance test manually, before the registry CLI is added. Locking the canonical test in CI prevents regressions during Phase 4 development. PITFALLS.md is explicit that Docker-only testing ships broken installs to users.
**Delivers:** Docker test runner (ubuntu:22.04 + ubuntu:24.04 matrix), bats assertion suite covering agent user, Node.js ownership, Claude Code install, PATH for all invocation modes (cron, systemd, sudo-u, non-interactive ssh), and the canonical self-update acceptance test. QEMU runner scaffolded.
**Addresses:** D-6 (container test harness)
**Must avoid:** Pitfall 7 (Docker false positives) — run container as non-root, generate locale, test non-interactive PATH in all forms
**Research flag:** Standard patterns — Docker + bats is fully documented in STACK.md down to Dockerfile level.

### Phase 4: Registry CLI

**Rationale:** The CLI is independent of the installer core and can be developed in parallel with Phase 3. It depends on Phase 2 (Node.js installed) and Phase 1 (agent user exists). The catalog schema must accommodate Python agents even if only npm agents ship in v0.3.0.
**Delivers:** `agentlinux list / install / remove` commands backed by embedded `catalog.json`; `provisioner/50-registry-cli.sh` wires the CLI into the installer; initial catalog: claude-code, gsd, chrome-devtools-mcp.
**Addresses:** TS-7, TS-8, TS-9, TS-12, D-1, D-2, D-3
**Must avoid:** Anti-pattern 2 (npm as root), Anti-pattern 3 (system-wide MCP config), Anti-pattern 6 (remote-only catalog — embedded must always work offline)
**Research flag:** Standard patterns — Commander.js + catalog dispatch pattern fully documented in ARCHITECTURE.md.

### Phase 5: Packaging + Distribution + Release

**Rationale:** Once the installer is tested and the registry works, wrap it for distribution. This produces the shippable artifact.
**Delivers:** `packaging/curl-installer/install.sh` (primary — thin downloader with SHA256 verification, execs `bin/agentlinux-install`); GitHub Actions release workflow (tag → build tarball → upload to Releases); optional `.deb` via fpm; QEMU runner fully wired (nightly + release gate); `install-verified.json` marker file and `CLAUDE.md` in agent home.
**Addresses:** TS-1 (one-command install), Pitfall 6 (distribution mechanism), Pitfall 11 (agent shim prevention)
**Must avoid:** curl-pipe-bash mid-stream interruption (wrap in `main()` called on last line; SHA256 verify); `dpkg -i` vs `apt install ./pkg.deb`
**Research flag:** Standard patterns — GitHub Releases + fpm carry-forward from v0.2.0.

### Phase Ordering Rationale

- Phase 1 before everything: `agent` user is a dependency of all provisioner steps; PATH is a dependency of the acceptance test.
- Phase 2 before Phase 4: the registry CLI installs agents via the same npm path established in Phase 2; that path must be proven before the CLI drives it.
- Phase 3 immediately after Phase 2: the canonical acceptance test should be in CI before more code is added on top.
- Phase 4 parallelizable with Phase 3: CLI Node.js code and catalog are independent of Docker/bats scaffolding.
- Phase 5 last: packaging wraps a working, tested installer.

ARCHITECTURE.md critical-path dependency chain: Phase 1 → Phase 2 → Phase 3 → (Phase 4 / Phase 3 in parallel) → Phase 5.

### Research Flags

Phases needing deeper research during planning:
- **Phase 2:** OQ-1 (npm vs native Claude Code installer) is the only remaining open question. It is a user/product decision, not a technical research gap. No research phase needed — just user input.

Phases with standard, fully-documented patterns (skip research-phase):
- **Phase 1:** useradd, sudoers, locale-gen — decades-old patterns; ARCHITECTURE.md + PITFALLS.md have exact implementation sketches.
- **Phase 3:** Docker + bats + QEMU runner patterns documented in STACK.md + ARCHITECTURE.md down to Dockerfile level.
- **Phase 4:** Commander.js CLI + catalog dispatch pattern fully documented in STACK.md + ARCHITECTURE.md.
- **Phase 5:** GitHub Releases + fpm is a carry-forward pattern from v0.2.0.

---

## Anti-Patterns Summary (do not add these)

From across all four research docs:

| Anti-pattern | Why not | Instead |
|---|---|---|
| `sudo npm install -g` anywhere in installer | Reintroduces the exact bug AgentLinux exists to fix | Always `sudo -u agent -H npm install -g` |
| Snap as distribution mechanism | AppArmor confinement incompatible with agent filesystem access | curl-pipe-bash + optional .deb |
| nvm/fnm/volta for the agent's Node.js | Shell-hook activation breaks cron, systemd, non-interactive SSH | NodeSource system Node + per-user npm prefix |
| Ansible/Chef/Puppet as the installer | Requires Python/Ruby runtime; designed for fleet management | bash + apt + npm |
| Docker-only testing (no QEMU) | Docker false-positive categories ship broken installs | Docker for inner loop; QEMU for release gate |
| `/etc/skel` as sole config distribution mechanism | Not applied to pre-existing users; not applied on plugin updates | Direct `install -o agent` to agent home + `/etc/skel` for freshness |
| System-wide MCP config (`/etc/claude-code/managed-mcp.json`) | Takes exclusive control; users cannot add their own MCP servers | Per-user `~/.claude.json` |
| Wrapper shims at `/usr/local/bin/` that exec via Node path | Self-update writes over the wrapper's Node target | Trust per-user npm prefix; if stubs are needed, hard-exec the agent's binary path |
| Remote-only catalog (always-fetch) | Breaks offline; breaks if agentlinux.org is down | Embedded catalog primary; remote merge optional via `AGENTLINUX_CATALOG_URL` env |
| Publishing the registry CLI to npm as a standalone package | CLI depends on `/opt/agentlinux/catalog.json`; meaningless outside the install | Vendor `node_modules/` inside the install directory |

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Context7-verified package versions; official docs for NodeSource, Claude Code, useradd, npm prefix; all key decisions carry forward v0.2.0 validation |
| Features | HIGH | 7-tool comparison set grounds all feature claims; anti-feature rationale is explicit and PROJECT.md-anchored |
| Architecture | HIGH | Component boundaries specific and validated against analogous systems (Jenkins, postgres, Homebrew); v0.2.0 provisioner-script model proven |
| Pitfalls | HIGH (ownership/PATH/sudoers/locale) MEDIUM (Docker false-positive taxonomy) | The npm-vs-native-installer tension is the one unresolved high-confidence disagreement between docs |

**Overall confidence:** HIGH for all implementation decisions. One open question (OQ-1: Claude Code install mechanism) is the only item requiring user input before Phase 2 begins.

### Gaps to Address

- **OQ-1 (Claude Code install: npm vs native binary):** Ask user during requirements. Both paths are fully researched; this is a product/philosophy decision.
- **OQ-2 (curl-pipe-bash vs .deb as primary):** Confirm with user; research recommends curl-pipe-bash primary.
- **OQ-3 (JSON vs TOML for catalog schema):** Confirm with user; default to JSON.
- **OQ-4 (include @openai/codex in initial catalog):** Low-stakes; confirm with user.
- **Sudoers scope for agent user:** Research recommends no NOPASSWD by default; confirm user agrees before locking in the design.

---

## Sources

### Primary (HIGH confidence)
- [Claude Code: Advanced setup](https://code.claude.com/docs/en/setup) — native installer, binary location, auto-update mechanism, `claude doctor`
- [Claude Code: Troubleshooting](https://code.claude.com/docs/en/troubleshooting) — conflicting installs, "Do NOT use sudo npm install -g", permission verification
- [npm Docs: Resolving EACCES errors](https://docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally/) — official per-user prefix recipe
- [sindresorhus/guides: npm-global-without-sudo.md](https://github.com/sindresorhus/guides/blob/main/npm-global-without-sudo.md) — canonical user-writable prefix recipe
- [Ubuntu Manpage: useradd(8)](https://manpages.ubuntu.com/manpages/noble/en/man8/useradd.8.html) — flag semantics for agent user creation
- [sudoers(5) man page](https://manpages.debian.org/buster/sudo/sudoers.5.en.html) — file mode 0440, secure_path, NOPASSWD syntax, filename rules (no dots)
- [Node.js EOL Schedule](https://nodejs.org/en/about/eol) — Node 22 LTS maintenance through April 2027
- Context7: `/tj/commander.js` — Commander 14.x, zero deps, stand-alone executable subcommands pattern
- npm registry (live, 2026-04-18): `commander@14.0.3`, `@anthropic-ai/claude-code@2.1.114`, `get-shit-done-cc@1.37.1`, `chrome-devtools-mcp@0.21.0`
- [bats-core](https://github.com/bats-core/bats-core) — TAP-compliant bash testing
- [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/) — test harness base image

### Secondary (MEDIUM confidence)
- [GitHub anthropics/claude-code #9327](https://github.com/anthropics/claude-code/issues/9327) — self-update misbehaves with npm symlink install; supports native installer preference in PITFALLS.md
- [Snap classic confinement docs](https://snapcraft.io/docs/classic-confinement) — confirms Snap Store review required; disqualifies snap
- Docker, Tailscale, k3s, Homebrew, nvm, mise, gh install scripts — feature baseline and install-behavior comparison set from FEATURES.md
- Jenkins/PostgreSQL service-user model — agent user shape precedent
- [Leapcell: nvm vs Volta vs fnm Deep Dive](https://leapcell.io/blog/navigating-node-js-versions-a-deep-dive-into-nvm-volta-and-fnm) — non-interactive shell failure modes for version managers
- [Sysdig: Friends don't let friends curl bash](https://www.sysdig.com/blog/friends-dont-let-friends-curl-bash) — curl-pipe-bash mid-stream interruption mitigations
- [Debian apt-get DPkg::Lock::Timeout](https://blog.sinjakli.co.uk/2021/10/25/waiting-for-apt-locks-without-the-hacky-bash-scripts/) — dpkg lock contention fix pattern

### Tertiary (LOW confidence — directional only)
- v0.2.0 phase-04 research (`.planning/milestones/v0.2.0-phases/04-agent-tool-packages/04-RESEARCH.md`) — project-internal; treated as MEDIUM for carry-forward decisions
- Various blog posts on curl-pipe-bash mid-stream interruption (the `main(){};main` wrapping pattern is widely recommended)
- [Claude Code Native Installer blog](https://claudefa.st/blog/guide/native-installer) — context for OQ-1 native installer path

---

*Research completed: 2026-04-18*
*Ready for roadmap: yes — pending user resolution of OQ-1 (Claude Code install mechanism) before Phase 2 requirements are locked*
