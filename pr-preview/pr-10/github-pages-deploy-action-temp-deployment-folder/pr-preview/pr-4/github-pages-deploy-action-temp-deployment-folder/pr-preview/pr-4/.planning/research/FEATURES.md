# Feature Research

**Domain:** Installable Linux extension / agent-environment plugin (Ubuntu first)
**Researched:** 2026-04-18
**Confidence:** MEDIUM-HIGH (comparison set verified from official docs/scripts; recommendations are opinionated)
**Milestone:** v0.3.0 — AgentLinux Plugin (subsequent milestone, post-pivot from custom distro)

---

## Carry-Forward From v0.1.0 / v0.2.0 (Not Re-Researched)

The following capabilities are already proven and explicitly out of scope for re-research. They become *implementation primitives* for v0.3.0 features:

| Carry-forward asset | Origin | How v0.3.0 uses it |
|---|---|---|
| Node.js 22 LTS install via NodeSource | v0.2.0 phase 03-01 | Plugin installer's "install Node.js comfortably" step |
| Claude Code install pattern (npm + skel config) | v0.2.0 phase 04-02 | Default-agent install + `agentlinux install claude-code` |
| GSD framework install pattern | v0.2.0 phase 04-02 | `agentlinux install gsd` registry entry |
| Chrome DevTools MCP server install pattern | v0.2.0 phase 04-02 | `agentlinux install chrome-devtools-mcp` registry entry |
| Chrome browser install pattern | v0.2.0 phase 03-02 | Dependency for Chrome DevTools MCP entry |
| `/etc/skel`-based default config | v0.2.0 phase 04-02 | Default agent config seeding for the agent user |
| fpm-built `.deb` knowledge | v0.2.0 phase 04-02 | *Reference* for plugin packaging — see "Self-update" below |
| Landing page + email capture (agentlinux.org) | v0.1.0 | Distribution channel for the install one-liner |

**Implication:** v0.3.0 is *integration + UX work*, not new install-mechanism research. The installer's job is to (a) create the agent user correctly, (b) wire the carry-forward provisioner logic to that user, and (c) add the registry CLI on top.

---

## Comparison Set (the 7 projects this research is anchored on)

| # | Project | Install command | Distribution mechanism | Creates dedicated user? | Default install behavior | Update mechanism | Uninstall |
|---|---------|-----------------|------------------------|-------------------------|--------------------------|------------------|-----------|
| 1 | **Docker Engine** (Linux) | `curl -fsSL https://get.docker.com \| sh` | Convenience script that adds `docker` apt repo and `apt install`s | Yes — `docker` group + `docker` daemon user (system account, no shell) | Installs Docker daemon + CLI. Daemon starts. | `apt upgrade docker-ce` (script wires the apt repo) | `apt purge docker-ce && rm -rf /var/lib/docker /var/lib/containerd` (manual) |
| 2 | **Tailscale** | `curl -fsSL https://tailscale.com/install.sh \| sh` | Detects distro, adds Tailscale apt/yum/zypper repo, then `apt install tailscale` | Yes — `tailscaled` runs as root system service; no human `tailscale` user | Installs daemon + CLI; daemon starts; user must run `tailscale up` to authenticate | `apt upgrade tailscale` (repo wired) | `apt purge tailscale` |
| 3 | **k3s** | `curl -sfL https://get.k3s.io \| sh -` | Direct binary install + systemd unit (no apt repo) | No dedicated user — runs as root (or `k3s:k3s` group when configured) | Installs and **starts** k3s server; cluster comes up immediately | Re-run install script with new env vars; or `k3s` channel-update (auto-restart only on hash change) | Generated `/usr/local/bin/k3s-uninstall.sh` (clean removal) |
| 4 | **Homebrew on Linux** | `/bin/bash -c "$(curl -fsSL .../install.sh)"` | git clone + linked binary in `/home/linuxbrew/.linuxbrew` | **Yes** — recommends a `linuxbrew` user owning `/home/linuxbrew/.linuxbrew`; otherwise installs under invoking user | Installs **no formulae** by default; user runs `brew install <pkg>` | `brew update && brew upgrade` | `brew uninstall <pkg>` per-formula; full uninstall via separate script |
| 5 | **nvm** | `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/.../install.sh \| bash` | git clone into `$HOME/.nvm` + shell-rc edit | No — single-user, lives in `$HOME` | Installs **no Node version** by default; user runs `nvm install <ver>`. First version installed becomes default. | `nvm install` a newer version; nvm itself updated by re-running install script | `rm -rf ~/.nvm` + manual rc cleanup |
| 6 | **mise** | `curl https://mise.run \| sh` | Static binary into `~/.local/bin` | No — single-user | Installs no tools by default; user runs `mise use -g node@lts` | `mise self-update` | `mise implode` (built-in, removes everything) |
| 7 | **GitHub CLI (`gh`)** | Add apt key + repo + `apt install gh` (4-line snippet) | Native apt repo (`cli.github.com/packages`) | No — pure CLI binary, runs as invoking user | Installs `gh` only; user runs `gh auth login` | `apt upgrade gh` | `apt purge gh` |

**Plus, two service-user reference points (not installer comparison, just user-provisioning shape):**

| Reference | User created | Home dir | Shell | Notes |
|---|---|---|---|---|
| **PostgreSQL** (Ubuntu pkg) | `postgres` (system) | `/var/lib/postgresql` | `/bin/bash` | Daemon user but also has shell — `sudo -u postgres psql` is a documented workflow |
| **Jenkins** (Ubuntu pkg) | `jenkins` (system) | `/var/lib/jenkins` | `/bin/bash` | Service-style user; admins `sudo su - jenkins` for debugging |

**Pattern observed:** Service-user installers (postgres, jenkins) put the user in `/var/lib/<name>` with a real shell so admins can `sudo -u <name>`. AgentLinux's `agent` user *is more like* postgres/jenkins than like Homebrew's `linuxbrew` — it's a distinct identity an admin will routinely shell into, not just a permissions trick.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Missing any of these = product feels incomplete or like a toy.

| # | Feature | Why Expected | Complexity | Notes / Carry-forward dep |
|---|---------|--------------|------------|---------------------------|
| TS-1 | **One-command install** (`curl ... \| sh` style) | Universal pattern across all 7 comparison tools | S | Bash script that detects Ubuntu version, sets up apt repo OR direct install. New work, no carry-forward. |
| TS-2 | **Sudo / privilege escalation handled gracefully** | Tailscale/Docker scripts both detect root vs sudo and exit cleanly if neither works | S | Standard `if [ "$EUID" -ne 0 ]; then ... sudo ... fi` boilerplate. |
| TS-3 | **Dedicated `agent` system user** | postgres / jenkins / docker daemon all do this; users expect a service-style account | S | `useradd --system --create-home --home-dir /home/agent --shell /bin/bash agent`. Note: `--system` defaults to *no* home dir, so explicitly add `--create-home`. |
| TS-4 | **Node.js 22 LTS installed for the agent user** | Headline value prop — Node must be there before any agent works | S | **Direct carry-forward from v0.2.0 phase 03-01 (NodeSource).** New work: ensure ownership lands on `agent`. |
| TS-5 | **Writable npm global prefix in agent user's home** | The motivating bug: `sudo npm install -g` and recursive shim pain. This is the *acceptance test*. | S | `npm config set prefix=/home/agent/.npm-global` + add `$prefix/bin` to agent's `PATH`. Carry-forward learning from v0.2.0. |
| TS-6 | **Default agent installed on first install** (Claude Code) | Docker installs Docker; gh installs gh; users expect *something works* after install | M | **Direct carry-forward from v0.2.0 phase 04-02.** Reuse npm install + `/etc/skel`-equivalent config seeding. |
| TS-7 | **Registry CLI: `agentlinux list`** | Every package manager has list (apt list, brew list, mise list, asdf current) | S | List installed agents from a local manifest file (e.g. `/var/lib/agentlinux/installed.json`) |
| TS-8 | **Registry CLI: `agentlinux install <agent>`** | Universal verb across apt/brew/npm/mise/asdf | M | Reuses v0.2.0 install patterns per agent. Each registry entry is an install recipe. |
| TS-9 | **Registry CLI: `agentlinux remove <agent>`** | Counterpart to install; without it, registry feels broken | S | npm uninstall + config cleanup per recipe |
| TS-10 | **Idempotent installer** (re-running is safe) | Docker / Tailscale / k3s scripts are all re-runnable; users will re-run on failure | S | Check user exists, check Node installed, check default agent installed before each step |
| TS-11 | **Acceptance test: agent self-updates Claude Code without sudo** | This *is* the canonical bug AgentLinux exists to fix | S | Test step in CI: `sudo -u agent claude update` (or equivalent) returns 0 |
| TS-12 | **Uninstall path** | All 7 comparison tools have one (script, `apt purge`, `mise implode`) | M | `agentlinux uninstall` removes user (with `--purge` removing home), removes registry state, leaves Node optional |

**Table stakes total: 12 features. Sized: 9×S + 3×M.**

### Differentiators (Competitive Advantage)

Features no comparison tool combines, which together define AgentLinux's edge.

| # | Feature | Value Proposition | Complexity | Notes |
|---|---------|-------------------|------------|-------|
| D-1 | **Service-user model for an agent runtime** (not version-manager, not daemon) | Hybrid of Jenkins/Postgres pattern + user-tooling — `sudo -u agent claude` becomes the ergonomic invocation. No tool in the comparison set targets this exact niche. | S | The whole installer is structured around this. |
| D-2 | **Pre-wired MCP server in default config** (Chrome DevTools MCP) | Out of the box, the default agent has a real tool installed and configured — not just an empty CLI | M | **Direct carry-forward from v0.2.0 phase 04-02.** Reuse `/etc/skel`-style config that pre-registers the MCP. |
| D-3 | **Curated agent registry with vetted recipes** | Homebrew has formulae; mise has plugins; AgentLinux has *agents*. Niche curation is the moat. | M | JSON/TOML manifest in the repo; `install <agent>` looks it up. Initial catalog detailed below. |
| D-4 | **Registry CLI: `agentlinux info <agent>`** | Useful "what is this thing" before installing — `brew info`, `apt show` parallel | S | Read recipe metadata, print description + URL + size estimate |
| D-5 | **Registry CLI: `agentlinux update <agent>`** | Per-agent update without forcing whole-system upgrade | S | npm update + version pin recipe. Composes with TS-8. |
| D-6 | **Container + QEMU test harness for the installer itself** | Few install scripts ship with a reproducible install-test rig; we will. Build credibility. | M | Already in PROJECT.md "Active" requirements. |
| D-7 | **`agentlinux doctor`** | mise has `mise doctor`, Homebrew has `brew doctor`. For an agent environment, a "is your Node owned right, is the agent user healthy, is sudoers correct" command is high-value. | S | Diagnostic script: check each invariant the installer establishes. |

**Differentiators total: 7 features. Sized: 4×S + 3×M.**

### Anti-Features (Commonly Requested, Out of Scope for v0.3.0)

| # | Anti-Feature | Why It Seems Good | Why Out of Scope (v0.3.0) | Alternative |
|---|------|---|---|---|
| A-1 | **GUI / TUI installer** | Friendlier than CLI | None of the 7 comparison tools have one for the install step. CLI-first is the norm; TUI adds 2× scope for marginal value. | Plain script + good defaults. PROJECT.md already excludes. |
| A-2 | **Sandbox-per-agent** (containers, namespaces, jails) | "Each agent is isolated, safer" | Sandboxing the agent is *Claude Code's* job, not the installer's. Adds container runtime as a hard dep. | Document the agent user's permissions clearly; defer to upstream agent sandbox features. |
| A-3 | **Multi-tenancy / multiple agent users** | Power users want it | One agent user covers 95% of the motivating use case. Multi-user means UID conflicts, registry partitioning, sudoers complexity. | Defer to v0.4+ if demand emerges. PROJECT.md already excludes. |
| A-4 | **Configuration management (Ansible-like)** | "Declarative is better" | YAML + state-reconciliation is a large codebase and a different product. Imperative install + idempotency is enough for v0.3.0. | Re-runnable install script (TS-10) gets 80% of the value at 5% of the cost. |
| A-5 | **Secrets management** (storing API keys for agents) | Agents need API keys to talk to LLMs | Solved problem (gh auth, doppler, 1password CLI, env vars). Building our own = bad-at-it. | Document patterns; let `claude auth` etc. own this. |
| A-6 | **Public PPA / signed apt repo** | "Real" Linux software ships via signed apt | Hosting + signing + key rotation is a project on its own. PROJECT.md already excludes for v0.3.0 (local install only). | Self-hosted install script via agentlinux.org for now. |
| A-7 | **Auto-update daemon** for the plugin | "It should keep itself current" | Background daemons are a maintenance liability. Docker/Tailscale rely on `apt upgrade`; nvm/mise require explicit user action. | `agentlinux self-update` command (manual, opt-in) — see Self-Update section. |
| A-8 | **Cross-distro support in v0.3.0** (Fedora/Arch/etc.) | Broader reach | Each distro-specific install path is incremental work. Land Ubuntu cleanly first. | Defer to v0.4+. PROJECT.md already excludes. |
| A-9 | **Default-install many agents** | "Out of the box loaded" | Slows install, bloats home dir, opinionated about which agent the user wants. nvm/mise/brew all install nothing by default. | Install Claude Code only by default; everything else opt-in via registry. |
| A-10 | **Telemetry / phone-home** | "Need to know who's using it" | Adds opt-out UX, privacy policy, hosting cost. Landing page already does the user-volume measurement. | Use agentlinux.org page-views / downloads as the proxy. |

**Anti-features total: 10. Holds the line on v0.3.0 scope.**

---

## Feature Dependencies

```
TS-1 (one-command installer)
    ├── TS-2 (privilege escalation)
    ├── TS-3 (agent user creation)
    │       └── TS-4 (Node.js for agent) ── carry-forward v0.2.0/03-01
    │               └── TS-5 (writable npm prefix) ── carry-forward v0.2.0/04-02 lessons
    │                       └── TS-6 (default agent install) ── carry-forward v0.2.0/04-02
    │                               └── D-2 (MCP pre-wired in skel) ── carry-forward v0.2.0/04-02
    │                                       └── TS-11 (acceptance test: self-update without sudo)
    └── TS-10 (idempotency) — wraps everything

TS-7 (list) ─┐
TS-8 (install) ── reuses TS-4..TS-6 install primitives
TS-9 (remove) ─┘
    └── D-3 (curated registry) — feeds TS-7/8/9
            ├── D-4 (info) — reads same recipes
            └── D-5 (update) — composes TS-9+TS-8

TS-12 (uninstall) — reverses TS-3..TS-6
D-6 (test harness) — validates everything end-to-end
D-7 (doctor) — read-only diagnostic over invariants from TS-3..TS-6
```

### Dependency Notes

- **TS-4 → TS-5 → TS-6 is the critical chain** — if Node ownership is wrong, the writable prefix won't help; if the prefix is wrong, the default agent self-update will EACCES. The acceptance test (TS-11) gates the entire milestone.
- **D-3 (registry) is the spine of the CLI features** — TS-7/8/9 and D-4/5 all read the same recipe format. Designing the recipe schema is on the critical path.
- **TS-12 (uninstall) is harder than it looks** — must handle "user has data in /home/agent we should preserve" vs "user wants a clean slate". Default to preserve, `--purge` to wipe.
- **D-6 (test harness) is independent** but blocks confident shipping; recommend running it in CI from day 1.

---

## MVP Definition

### Launch With (v0.3.0)

The opinionated minimum for a credible Ubuntu plugin.

- [x] TS-1 One-command installer (Ubuntu 22.04 + 24.04)
- [x] TS-2 Privilege escalation
- [x] TS-3 Agent user (`agent`, system, `/home/agent`, bash shell)
- [x] TS-4 Node.js 22 LTS (carry-forward)
- [x] TS-5 Writable npm prefix in `/home/agent/.npm-global`
- [x] TS-6 Default agent: Claude Code (carry-forward)
- [x] TS-7 `agentlinux list`
- [x] TS-8 `agentlinux install <agent>`
- [x] TS-9 `agentlinux remove <agent>`
- [x] TS-10 Idempotent installer
- [x] TS-11 Acceptance test: agent self-updates Claude Code without sudo
- [x] TS-12 `agentlinux uninstall`
- [x] D-1 Service-user model (free with TS-3)
- [x] D-2 Chrome DevTools MCP pre-wired (carry-forward)
- [x] D-3 Curated registry (3 entries — see catalog below)
- [x] D-6 Container test harness

### Add After Validation (v0.3.x patches)

- [ ] D-4 `agentlinux info <agent>` — natural follow-on to D-3
- [ ] D-5 `agentlinux update <agent>` — same
- [ ] D-7 `agentlinux doctor` — once we see install failures in the wild
- [ ] QEMU-based test harness (PROJECT.md lists as optional second track)
- [ ] Self-update for the plugin itself — see recommendation below

### Future Consideration (v0.4+)

- [ ] Cross-distro (Fedora, CentOS, Alma, Arch, openSUSE)
- [ ] Public PPA with package signing
- [ ] Multi-tenant agent users
- [ ] Agent-skills system (per PROJECT.md long-term roadmap)

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---|---|---|---|
| TS-1 One-command install | HIGH | LOW | P1 |
| TS-3 Agent user | HIGH | LOW | P1 |
| TS-4 Node.js for agent | HIGH | LOW (carry-forward) | P1 |
| TS-5 Writable npm prefix | HIGH | LOW | P1 |
| TS-6 Default Claude Code | HIGH | MEDIUM (carry-forward) | P1 |
| TS-7/8/9 Registry CLI list/install/remove | HIGH | MEDIUM | P1 |
| TS-10 Idempotency | MEDIUM | LOW | P1 |
| TS-11 Self-update acceptance test | HIGH (defines done) | LOW | P1 |
| TS-12 Uninstall | MEDIUM | MEDIUM | P1 |
| D-2 MCP pre-wired | HIGH | MEDIUM (carry-forward) | P1 |
| D-3 Curated registry recipes | HIGH | MEDIUM | P1 |
| D-6 Container test harness | HIGH (CI confidence) | MEDIUM | P1 |
| D-4 `info` | MEDIUM | LOW | P2 |
| D-5 `update` | MEDIUM | LOW | P2 |
| D-7 `doctor` | MEDIUM | LOW | P2 |
| Plugin self-update | MEDIUM | MEDIUM | P2 |
| QEMU test harness | LOW (container covers 90%) | MEDIUM | P3 |
| Cross-distro | HIGH long-term | HIGH | P3 (v0.4+) |

**P1 cluster:** 12 features — the v0.3.0 scope.
**P2 cluster:** 4 features — fast-follow.
**P3 cluster:** explicit v0.4+ deferrals.

---

## Initial Agent Registry Catalog (D-3)

The seed catalog for v0.3.0. Each entry is a recipe:
```
{ name, description, install_cmd, uninstall_cmd, default_config?, deps[] }
```

### Definite-Include (ships in v0.3.0)

| Agent | Why definite | Recipe complexity | Carry-forward |
|---|---|---|---|
| **claude-code** (default) | The whole installer's reason for being. Default install. | LOW | v0.2.0/04-02 |
| **gsd** (Get Shit Done framework) | Already packaged in v0.2.0; first-party piece of the agent workflow story. | LOW | v0.2.0/04-02 |
| **chrome-devtools-mcp** | MCP-server-as-package proves the registry can handle non-trivial recipes (browser dep). Also pre-wired into Claude Code default config (D-2). | MEDIUM (Chrome dep) | v0.2.0/03-02 + v0.2.0/04-02 |

**3 agents = enough to prove "this is a registry, not a hardcoded list."**

### Nice-to-Include (if time permits in v0.3.0)

| Agent | Why nice | Risk if skipped | Notes |
|---|---|---|---|
| **codex** (`@openai/codex`) | Validates registry isn't Anthropic-only; another npm-installed agent so install pattern is identical to Claude Code | None — easy add post-v0.3.0 | npm package: `@openai/codex` (verified npm.com 2026) |
| **aider** | Validates registry handles **Python/pip** agents, not just npm | MEDIUM — first non-npm install path. Could surface design gaps in recipe schema. | Recommend including *if* the recipe schema design budget allows; otherwise defer to force a clean Python-recipe story in v0.3.1. |

### Defer (v0.3.x or v0.4)

| Agent | Why defer | When to revisit |
|---|---|---|
| **cline** (`npm install -g cline`) | npm install pattern identical to Claude Code/Codex; adds catalog noise without adding signal. | Add when registry schema is settled and adding entries is trivial |
| **Cursor CLI** | Cursor's CLI story is unstable as of 2026-04; risk of breakage | When Cursor ships a stable Linux CLI |
| **Generic MCP servers as a category** | "Install any MCP server" is a richer feature than v0.3.0 should take on — it's a sub-registry | Real v0.4+ work; consider `agentlinux mcp install <name>` namespacing |
| **goose** (Block's agent), **OpenHands**, etc. | Open ecosystem; pick winners after v0.3.0 lands | Watch usage signals from agentlinux.org |

**Catalog rationale:** Ship 3 in v0.3.0 (definites). The schema must accommodate Python (Aider) cleanly even if the entry isn't shipped — design it in, ship it later. This avoids registry v2 in 6 months.

---

## Self-Update Capability for the Plugin Itself

### Survey of the comparison set

| Tool | Self-update mechanism |
|---|---|
| Docker | `apt upgrade docker-ce` (apt repo wired by install script) |
| Tailscale | `apt upgrade tailscale` (apt repo wired) |
| k3s | Re-run install script with same env vars; checks hash |
| Homebrew | `brew update` (built-in) |
| nvm | Re-run install script (manual) |
| mise | `mise self-update` (built-in command) |
| gh | `apt upgrade gh` (apt repo wired) |

**Pattern:** 4/7 use apt repo upgrade, 1/7 has a built-in `self-update`, 2/7 require re-running the install script.

### Recommendation for v0.3.0

**Tier the answer:**

- **v0.3.0 (P2 / fast-follow):** ship `agentlinux self-update` as a built-in command. Implementation: re-fetch the install script and re-run it. This is the **mise pattern** and the **k3s pattern** combined — minimal infra (no apt repo to host), opt-in (no daemon), single command.
- **v0.4+ (P3):** when public PPA / package signing arrives (anti-feature A-6 lifts), shift to `apt upgrade agentlinux` (the **Docker/Tailscale/gh pattern**). At that point, `self-update` becomes a thin wrapper around apt.

**Rationale:**

1. PROJECT.md explicitly excludes public PPA infra for v0.3.0, so `apt upgrade agentlinux` isn't on the table yet.
2. A built-in `self-update` is a 50-line shell function. Cost is tiny.
3. Avoids users having to remember the install URL. Avoids the "I installed this 6 months ago, how do I update" failure mode that nvm has.
4. Composes with `agentlinux update <agent>` mental model — same verb, different scope (`self` is just a special agent name).

**Alternative considered: do nothing, rely on user re-running the install script.** Rejected because (a) discoverability is poor, (b) we already have a CLI, the increment is trivial, (c) it sets the expectation that the plugin maintains itself.

---

## Default-Agent Install Behavior — Recommendation

### Survey

| Tool | Default install |
|---|---|
| Docker | Installs Docker (the thing) |
| Tailscale | Installs daemon, requires `tailscale up` for auth |
| k3s | Installs and **starts** k3s |
| Homebrew | Installs **no** formulae |
| nvm | Installs **no** Node version |
| mise | Installs **no** tools |
| gh | Installs gh (the thing) |

**Pattern:** Tools that *are* the package install themselves (Docker, Tailscale, k3s, gh). Tools that are *managers* of other things install nothing (Homebrew, nvm, mise).

### Recommendation: install Claude Code by default

**Rationale:**

1. **AgentLinux is not (just) a manager** — its core value prop is "an agent environment ready to go." Empty installation contradicts the pitch.
2. **Most-installed package = Claude Code** — verified by both v0.2.0 baking it as the headline agent and the project being explicitly built around the EACCES self-update bug *for Claude Code*.
3. **The acceptance test (TS-11) requires Claude Code to be installed** — installing it by default is no extra cost.
4. **Discoverability** — first-time user runs the installer, gets a working agent, runs `claude` and it works. That's the moment of value. Asking them to also run `agentlinux install claude-code` is friction.
5. **Docker/gh precedent** is stronger than the nvm/mise precedent here because AgentLinux isn't a tool-version-manager — it's an opinionated environment.

**Override:** support `--no-default-agent` for the curl-pipe case (CI installs that don't want Claude Code).

**Composability:** `agentlinux install claude-code` should be idempotent (TS-10), so post-install reinstall is safe.

---

## Competitor Feature Analysis

| Feature | Docker | Tailscale | k3s | Homebrew/Linux | nvm | mise | gh | **AgentLinux** |
|---|---|---|---|---|---|---|---|---|
| One-command install | curl\|sh | curl\|sh | curl\|sh | bash -c curl | curl\|bash | curl\|sh | apt 4-liner | curl\|sh (P1) |
| Dedicated user | docker daemon | none | none | linuxbrew (rec.) | none | none | none | **agent** (P1) |
| Default install thing | self | self | self | nothing | nothing | nothing | self | **Claude Code** |
| Registry/list verb | n/a | n/a | n/a | brew list | nvm list | mise list | n/a | `agentlinux list` (P1) |
| Install verb | n/a | n/a | n/a | brew install | nvm install | mise install | n/a | `agentlinux install` (P1) |
| Update path | apt | apt | re-run | brew update | re-run | mise self-update | apt | `agentlinux self-update` (P2) |
| Uninstall | apt purge | apt purge | k3s-uninstall.sh | brew uninstall | rm -rf | mise implode | apt purge | `agentlinux uninstall` (P1) |
| Doctor | n/a | n/a | n/a | brew doctor | n/a | mise doctor | n/a | `agentlinux doctor` (P2) |
| Test harness ships | yes (CI) | yes | yes | yes | yes | yes | yes | yes (D-6, P1) |

**Where AgentLinux is unique:** the **dedicated agent user + default agent + curated registry** combination. No comparison tool does all three. Docker/Tailscale/gh have dedicated installs but no registry. Homebrew/mise have registries but no dedicated user (single-user tools). Jenkins/postgres have dedicated users but no curated user-tooling.

This intersection *is* the moat for v0.3.0.

---

## Open Questions / Risks

1. **Recipe schema:** JSON vs TOML vs shell-script-per-agent. TOML wins on readability; shell-script-per-agent wins on flexibility. Recommendation: TOML manifest with `install_script` field that points to a sibling `.sh` for non-trivial recipes (Chrome DevTools MCP needs Chrome).

2. **Where does the registry live?** Embedded in the plugin (frozen per release) vs fetched from agentlinux.org (live)? Recommendation: embedded for v0.3.0 (no infra dep), fetched for v0.4+ (allows non-release recipe updates).

3. **What happens if `claude` already exists for the invoking user?** Should the installer migrate the user's existing `~/.claude` config to `/home/agent/.claude`? Recommendation: don't migrate, document the difference, surface via `agentlinux doctor`.

4. **Sudoers entry for the agent user?** PROJECT.md says agent user "has sudo access" in v0.2.0 docs. Re-confirm for v0.3.0: does the plugin's agent user need sudo? Default to **no sudo** (least privilege); add `--with-sudo` flag if requested. The motivating bug doesn't require sudo — it requires *avoiding* sudo for npm.

5. **Confirm Codex CLI npm package shape** before committing it as nice-to-include. Verified `@openai/codex` exists on npm; recipe is essentially `npm install -g @openai/codex` with same ownership story as Claude Code.

---

## Sources

### Comparison tools
- [Docker convenience install script (get.docker.com)](https://get.docker.com/)
- [Docker Engine install on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [docker/docker-install repo](https://github.com/docker/docker-install)
- [Tailscale Linux install docs](https://tailscale.com/docs/install/linux)
- [tailscale/scripts/installer.sh](https://github.com/tailscale/tailscale/blob/main/scripts/installer.sh)
- [k3s install script (get.k3s.io)](https://get.k3s.io/)
- [k3s uninstall docs](https://docs.k3s.io/installation/uninstall)
- [Homebrew Common Issues / multi-user](https://docs.brew.sh/Common-Issues)
- [Homebrew multi-user discussion](https://www.codejam.info/2021/11/homebrew-multi-user.html)
- [nvm-sh/nvm README](https://github.com/nvm-sh/nvm)
- [mise Getting Started](https://mise.jdx.dev/getting-started.html)
- [mise CLI: install](https://mise.jdx.dev/cli/install.html)
- [asdf All Commands](https://asdf-vm.com/manage/commands.html)
- [GitHub CLI install on Linux (cli/cli docs)](https://github.com/cli/cli/blob/trunk/docs/install_linux.md)

### Service-user references
- [Jenkins Linux install](https://www.jenkins.io/doc/book/installing/linux/)
- [PostgreSQL install on Ubuntu](https://ubuntu.com/server/docs/how-to/databases/install-postgresql/)
- [useradd man page (man7.org)](https://man7.org/linux/man-pages/man8/useradd.8.html)

### Agents for catalog
- [@openai/codex on npm](https://www.npmjs.com/package/@openai/codex)
- [Aider install docs](https://aider.chat/docs/install.html)
- [Cline install docs](https://docs.cline.bot/getting-started/installing-cline)

### Self-update patterns
- [go-selfupdate](https://github.com/sanbornm/go-selfupdate)
- [inconshreveable/go-update](https://github.com/inconshreveable/go-update)

### Security / curl-pipe-sh discourse
- [Chef: 5 Ways to Deal With install.sh Curl Pipe Bash](https://www.chef.io/blog/5-ways-to-deal-with-the-install-sh-curl-pipe-bash-problem)
- [Sysdig: Friends Don't Let Friends Curl Bash](https://www.sysdig.com/blog/friends-dont-let-friends-curl-bash)

### Internal carry-forward
- `.planning/PROJECT.md` (v0.3.0 active scope, out-of-scope list)
- `.planning/MILESTONES.md` (v0.2.0 retirement context)
- `.planning/milestones/v0.2.0-research/FEATURES.md` (carry-forward artifacts: Node.js install, Claude Code .deb, GSD .deb, Chrome DevTools MCP .deb, Chrome install pattern, /etc/skel config)

---

*Feature research for: Installable Linux extension / agent-environment plugin (Ubuntu first)*
*Researched: 2026-04-18*
