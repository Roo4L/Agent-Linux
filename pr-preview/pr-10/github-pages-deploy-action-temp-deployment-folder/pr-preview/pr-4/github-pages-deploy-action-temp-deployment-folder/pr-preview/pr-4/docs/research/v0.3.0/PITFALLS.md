# Pitfalls Research

**Domain:** Ubuntu plugin/extension installer — provisioning an `agent` user with correctly-owned Node.js, default agent (Claude Code), and CLI registry; tested in Docker / QEMU.
**Researched:** 2026-04-18
**Confidence:** HIGH for ownership / Claude-Code-self-update / sudoers / locale (verified against Anthropic and npm official docs); MEDIUM for distribution-mechanism tradeoffs and Docker-test false-positives (synthesized from multiple sources, not single-vendor)

## Orientation: The Canonical Bug Class

Every pitfall in this document is organized around one acceptance test:

> The `agent` user runs `claude update` (or triggers a background auto-update) on a freshly-installed system, and it succeeds without `sudo`, without manual `chown`, without "command not found", and without producing recursive `npx`-shim workarounds.

If that single test passes on a clean Ubuntu, the installer has defeated the bug class that motivated this entire project. Pitfalls below are scored by *how directly they break that test*.

A second-order goal that's easy to miss: **make the install so unambiguously correct that an AI agent doesn't *want* to create shims.** Agents reach for shims when they see EACCES, "command not found", or sudo prompts. Eliminate those signals and the workaround impulse goes away.

---

## What Changed Since v0.2.0 Research (Read This First)

The v0.2.0 phase-04 research recommended `npm install -g @anthropic-ai/claude-code` with system-wide install. **For v0.3.0 this is wrong.** Anthropic's current (2026-Q1) recommendation is the **native binary installer**:

```bash
curl -fsSL https://claude.ai/install.sh | bash
# → ~/.local/bin/claude          (binary, no Node dependency)
# → ~/.local/share/claude/       (versioned binaries + auto-update state)
# → ~/.claude/                   (settings, hooks, MCP, history)
# → ~/.claude.json               (global state, OAuth, MCP servers)
```

Key facts from [code.claude.com/docs/en/setup](https://code.claude.com/docs/en/setup) and [troubleshooting](https://code.claude.com/docs/en/troubleshooting):

1. The native binary **does not invoke Node.js at runtime**. Even the npm install path now ships a per-platform binary via optional dependency (`@anthropic-ai/claude-code-linux-x64`) and links it. The `claude` binary is a real ELF, not a JS shim.
2. Auto-update **requires** `~/.local/bin/` and `~/.claude/` to be writable by the running user. The doctor check is literally `test -w ~/.local/bin && test -w ~/.claude`.
3. `claude update` invokes the same atomic-replace mechanism the background updater uses; both fail identically if either directory is non-writable or owned by another user.
4. There is a documented [self-update bug class](https://github.com/anthropics/claude-code/issues/9327) where Claude Code installed via `npm install -g --prefix=~/.local` (creating a *symlink* at `~/.local/bin/claude`) gets clobbered by self-update because the updater writes a real file over the symlink target. **Conclusion: prefer the native installer over npm-with-prefix.**
5. **Do NOT use `sudo` to install.** Anthropic's docs are explicit: `Do NOT use 'sudo npm install -g'`.

This single shift (npm-global → native installer in `~/.local/bin/`) eliminates the largest pitfall class from v0.2.0 (system-wide npm prefix ownership) but introduces a new one (the agent user's *home* must be writable by the agent user — sounds trivial, but `chown -R root:root /home/agent` happens in installer scripts more often than you'd think).

---

## Critical Pitfalls

### Pitfall 1: System-wide npm prefix ownership breaks `claude update`

**What goes wrong:**
The installer runs `npm install -g @anthropic-ai/claude-code` as root during `apt install` postinst. The binary lands in `/usr/lib/node_modules/@anthropic-ai/claude-code/` (NodeSource default prefix) with a symlink at `/usr/bin/claude` (or `/usr/local/bin/claude`), all owned by `root:root`. When the agent user later runs `claude update`, Claude Code attempts to atomic-rename a new binary into place. It fails:

```
Error: EACCES: permission denied, rename '/tmp/claude-2.1.99-tmp' → '/usr/bin/claude'
```

The agent then either (a) prompts the user for sudo (breaks "no sudo" goal), (b) fails silently and runs an old version, or (c) — the bug we're explicitly defending against — the user/agent invents a workaround like `alias claude='npx @anthropic-ai/claude-code@latest'` which spawns a new download every invocation.

**Why it happens:**
Decades of Linux installer muscle memory: "system tools go in /usr/bin, owned by root." This is correct for system daemons. It is **wrong** for tools whose own update mechanism is a self-rewrite. Claude Code, brew formulae, rustup, fnm/nvm, mise, uv, and every modern self-updating CLI assume the install location is in *user* space.

**How to avoid:**
1. **Do not install Claude Code system-wide.** Install it into the agent user's home: `~/.local/bin/claude` via the official native installer, run *as the agent user* (not as root).
2. The plugin installer's job is to (a) create the user, (b) drop into the user, (c) run the official installer. Pseudocode:
   ```bash
   useradd -m -s /bin/bash agent
   sudo -u agent -H bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
   ```
   `sudo -u … -H` sets `HOME=/home/agent` so the installer targets the right paths.
3. Verify in the same install run: `sudo -u agent -H test -w /home/agent/.local/bin && sudo -u agent -H test -w /home/agent/.claude`.
4. Run the canonical test as the final installer step: `sudo -u agent -H claude doctor` (which checks all this) and a dry-run of the update mechanism.

**Warning signs:**
- `ls -la $(sudo -u agent which claude)` shows owner `root`.
- `sudo -u agent claude update` prints anything containing `EACCES`, `permission denied`, or `rename`.
- `sudo -u agent claude doctor` reports any directory as "not writable".
- A grep of the installer for `npm install -g`, `sudo npm`, or any path under `/usr/lib/node_modules` involving Claude Code or agent tools.

**Phase to address:** **Earliest installer-foundation phase.** This is the canonical bug class. The phase that creates the agent user and installs Claude Code MUST get this right; everything else is downstream.

---

### Pitfall 2: Node.js global prefix ownership for *other* npm packages (GSD, MCP servers)

**What goes wrong:**
Claude Code itself no longer needs npm at runtime, but the registry still installs other agents/tools that *do* — `get-shit-done-cc` (GSD), `chrome-devtools-mcp`, future MCP servers. If those are installed via `sudo npm install -g`:

- Files land in `/usr/lib/node_modules/`, owned by root.
- `~/.npm` cache may be created with root ownership the first time root runs npm in the agent's home (e.g., via a misuse of `sudo -E npm install -g`), which then breaks every subsequent `npm` invocation by the agent user with `EACCES: permission denied, mkdir '/home/agent/.npm/_cacache/...'`.
- Updating GSD or MCP servers via `npm update -g` will require sudo, breaking the no-sudo guarantee.

**Why it happens:**
Same reflex as Pitfall 1, plus the v0.2.0 .deb postinst pattern explicitly used `npm install -g` as root. Carrying that pattern into v0.3.0 reintroduces the bug.

**How to avoid:**
1. Configure the agent user with a per-user npm prefix at user-creation time:
   ```bash
   sudo -u agent -H npm config set prefix '/home/agent/.local'
   ```
   This makes `npm install -g X` install to `/home/agent/.local/lib/node_modules/X` with bins in `/home/agent/.local/bin/X` — same `~/.local/bin` directory Claude Code uses, no collision.
2. Make sure `/home/agent/.local/bin` is on PATH for *all* invocation paths (see Pitfall 4).
3. Always invoke npm as the agent user: `sudo -u agent -H npm install -g <pkg>`. **Never** run npm as root in the install scripts.
4. If Node.js itself is system-installed (NodeSource), that's fine — Node binary in `/usr/bin/node` is read-only for the agent and that's correct. Only the *prefix* matters.
5. Pre-create `/home/agent/.npm/` with correct ownership at user-creation time so the first run doesn't race.

**Warning signs:**
- `sudo -u agent npm config get prefix` returns `/usr` or `/usr/local` (default) instead of `/home/agent/.local`.
- `ls -ld /home/agent/.npm` is owned by root.
- Running `sudo -u agent npm install -g cowsay` produces EACCES.
- A separate test as the agent user (not root): `npm install -g cowsay && cowsay hi` should just work.

**Phase to address:** Same phase as Pitfall 1. The npm prefix is configured at the same moment Claude Code is installed, as part of "create agent user with correct Node.js setup."

**Why not nvm/fnm/volta:** Tempting because they're popular, but each introduces its own shell-rc-sourcing pitfall (Pitfall 3): the version manager only activates when an interactive shell sources `~/.bashrc`. Cron, systemd, `sudo -u agent <cmd>` (without `-i`), and non-interactive SSH all skip rc files, so `node` and `npm` aren't on PATH. **Recommend system Node.js (NodeSource) + per-user npm prefix.** This puts `node` at `/usr/bin/node` (always on PATH) and the prefix in `~/.local/bin/` (just needs PATH wired once — see Pitfall 4).

---

### Pitfall 3: Version manager (nvm/fnm/volta) only activates in interactive shells

**What goes wrong:**
Tutorials universally recommend nvm. The agent installer follows that advice. Now:
- Interactive SSH: `claude --version` → works. `npm --version` → works.
- `sudo -u agent claude --version` → `command not found`.
- A systemd `User=agent` service: `node: command not found`.
- A cron job under the agent user: same.
- Even `ssh agent@host 'node --version'` (non-interactive SSH) often fails because `~/.bashrc` typically guards itself with `[[ $- != *i* ]] && return` at the top.

The reason: nvm/fnm/volta install themselves by appending sourcing logic to `~/.bashrc`. That file is only read by interactive non-login shells. Login shells read `~/.profile`. Non-interactive shells read neither (unless `BASH_ENV` is set).

**Why it happens:**
The agent's shell (when the human SSHes in) "just works", so the developer thinks the install is correct. The breakage is invisible until automation runs — and the canonical Claude Code self-update *is* automation (background timer in the running `claude` process).

**How to avoid:**
**Don't use a version manager.** Use system Node.js from NodeSource (binary at `/usr/bin/node`, on PATH for every shell type), and per-user npm prefix in `~/.local/`. This is the same conclusion the v0.2.0 phase-04 research arrived at: NodeSource at `/usr/bin/node`, plus a writable user prefix.

If you must use a version manager (some user requested fnm), then:
- Source the activation snippet from `~/.profile`, NOT `~/.bashrc` (login-shell coverage).
- Drop a small `/etc/profile.d/agent-node.sh` that activates fnm globally for the agent user.
- Provide a wrapper at `/usr/local/bin/claude` that explicitly sets up env then `exec`s the real binary — so cron/systemd see a usable `claude` regardless of shell-rc loading.

**Warning signs:**
- `bash -c 'node --version'` (non-interactive) fails for the agent user but `bash -i -c 'node --version'` succeeds.
- `sudo -u agent which node` returns nothing.
- The hooks in `~/.claude/settings.json` reference an absolute path like `/home/agent/.local/share/fnm/aliases/default/bin/node` (this is exactly the v0.2.0 phase-04 Pitfall 5).

**Phase to address:** Same installer-foundation phase. Decision is "system Node + per-user prefix" and lock it in via the design.

---

### Pitfall 4: PATH gets dropped by every non-interactive invocation path

**What goes wrong:**
`~/.local/bin/` is correctly populated with `claude`, `gsd`, etc., owned by the agent user. `claude --version` works in an SSH session. Then:
- Cron: `* * * * * claude doctor` → `/bin/sh: 1: claude: not found`. Cron's PATH is `/usr/bin:/bin`.
- systemd `User=agent ExecStart=/usr/bin/env claude doctor` → same `not found`. systemd's default PATH is `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`.
- `sudo -u agent claude doctor` from a root cron → fails with `command not found` because sudo's `secure_path` (in `/etc/sudoers`) overrides PATH and points only at system bin dirs.
- `ssh agent@host 'claude doctor'` (non-interactive) → fails because `~/.bashrc` returns early for non-interactive shells.
- A script invoked as `bash -c '...'` from inside the agent's session but which `exec`s without inheriting env → fails.

**Why it happens:**
Each invocation path has its own PATH-construction policy. There's no single file that controls PATH for *all* of them.

**How to avoid:**
Belt-and-braces — use multiple mechanisms because no single one covers everything:

1. **System-wide PATH modification via `/etc/profile.d/`.** Drop a file `/etc/profile.d/agentlinux-path.sh`:
   ```sh
   if [ -d "$HOME/.local/bin" ]; then
       case ":$PATH:" in
           *:"$HOME/.local/bin":*) ;;
           *) PATH="$HOME/.local/bin:$PATH" ;;
       esac
   fi
   ```
   This covers all login shells (`/bin/bash -l`, `su -`, `sudo -i`, SSH login).

2. **Stub binaries in `/usr/local/bin/`.** Drop a tiny wrapper at `/usr/local/bin/claude`:
   ```bash
   #!/bin/bash
   exec /home/agent/.local/bin/claude "$@"
   ```
   `/usr/local/bin` is on `secure_path` in default Ubuntu sudoers and is in cron's default PATH. **Caveat:** these wrappers are owned by root, so when Claude Code self-updates `~/.local/bin/claude`, the `/usr/local/bin/claude` wrapper is unaffected and keeps pointing at the (now updated) real binary. This is the right shape.

3. **systemd-aware `User=` with explicit `Environment=PATH=...`** in any unit files the installer creates.

4. **For cron**, the agent's crontab should set `PATH=/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin` explicitly at the top.

5. **Sudoers `secure_path` adjustment.** In `/etc/sudoers.d/agentlinux` (mode 0440):
   ```
   Defaults:agent secure_path="/home/agent/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
   ```
   This makes `sudo -u agent claude` work from anywhere.

**Warning signs:**
- The Wave-0 test plan must include all of: `cron`, `systemd User=`, `sudo -u agent`, `ssh agent@host 'claude --version'`, `bash -c 'claude --version'` (non-interactive), and `su - agent -c 'claude --version'`. If any one fails, the install is incomplete.

**Phase to address:** Installer-foundation phase (same one that creates the user and installs Claude Code). The PATH plumbing must ship in v1 of the installer; retrofitting PATH later is painful.

---

### Pitfall 5: Installer is not idempotent (re-run / pre-existing user / pre-existing Node)

**What goes wrong:**
Common failure modes when the installer is re-run or run on a "dirty" system:
1. **Pre-existing `agent` user (created by sysadmin or another tool).** Installer runs `useradd agent` → fails with `useradd: user 'agent' already exists`, exits non-zero. Or worse, the installer "just continues" and overwrites that user's `~/.bashrc`, `~/.npm`, etc., destroying their work.
2. **Pre-existing Node.js (different version, different source).** Installer adds NodeSource repo and runs `apt install nodejs` → conflicts with `apt install node` from Ubuntu's own repo (which provides `nodejs` as a virtual package). Result: held packages, broken `node`, or silent downgrade.
3. **Re-running on a system with Claude Code already installed.** The installer naively re-runs `curl … install.sh | bash` → installer exits cleanly, but the agent's `~/.claude.json` may get reset or OAuth tokens invalidated. Or the installer tries to `npm install -g chrome-devtools-mcp` again → succeeds but resets the version, breaking pinned configurations.
4. **Pre-existing global Claude Code as root** (from someone running `sudo npm install -g @anthropic-ai/claude-code` in a previous attempt). Now there are TWO `claude` binaries on PATH — the root-owned one in `/usr/bin/` shadows the agent's one in `~/.local/bin/`. `which -a claude` shows both. Auto-update fails on the root-owned one, the agent-owned one updates fine, and which one runs depends on PATH order. This is exactly the [conflicting-installations issue](https://code.claude.com/docs/en/troubleshooting) Anthropic calls out.
5. **dpkg lock contention.** unattended-upgrades is running in the background; the installer's `apt install` fails with `Could not get lock /var/lib/dpkg/lock-frontend`.

**Why it happens:**
Installers are written linearly: "do A, then do B, then do C." Each step assumes a clean prior state. Real systems are dirty.

**How to avoid:**
Defensive checks at every stateful step:

1. **User creation.** Use `id -u agent >/dev/null 2>&1 || useradd -m -s /bin/bash agent`. If the user exists, decide policy: error out with a clear message ("--force to proceed and overwrite agent user's environment"), or skip user creation but verify the existing user has a writable home.
2. **Node.js install.** Check `command -v node && node --version` before installing. If Node ≥ 18 is present, skip the NodeSource setup; just verify and continue. If Node < 18, error out with a remediation hint.
3. **Claude Code install.** Use the `claude doctor` check: if it reports a healthy install in the agent's home, skip reinstall and verify the version. If multiple installs found (root-owned + user-owned), error and prompt for cleanup.
4. **dpkg lock.** Use `apt-get -o DPkg::Lock::Timeout=300 install …` which waits up to 5 minutes for the lock instead of failing immediately.
5. **The installer should be safe to run as `installer.sh` AND as `installer.sh --uninstall` AND as `installer.sh` again.** Test all three orderings in CI.

**Warning signs:**
- The installer's first line is `useradd -m agent` with no preceding check.
- `apt install` is called without `-o DPkg::Lock::Timeout=…`.
- The CI test matrix doesn't include "run installer twice in a row" and "run installer on Ubuntu image with Node already preinstalled."

**Phase to address:** Installer-foundation phase, with idempotency as an explicit acceptance criterion. Don't postpone "make it idempotent" to a polish phase — re-runs happen during developer iteration on the installer itself.

---

### Pitfall 6: Distribution mechanism — picking the wrong shape costs months

Each candidate has a distinct failure mode profile. Summary table, then per-mechanism detail.

| Mechanism | Strength | Killer Weakness | Recommend? |
|-----------|----------|-----------------|------------|
| `curl pipe bash` | Simplest UX, no infra | No mid-stream interrupt protection unless wrapped; security-conscious users won't run it | Yes for v0.3.0, with mitigations |
| Local `.deb` (`apt install ./agentlinux.deb`) | Familiar to Debian users, dependency resolution via apt | No auto-update, dependency resolution can fail without configured repo, dpkg lock contention | Optional secondary path |
| Hosted `.deb` PPA | Auto-update, signed, trusted | Requires repo + signing-key infrastructure (out of scope per PROJECT.md) | Defer to post-v0.3.0 |
| Snap | Auto-update, Ubuntu-blessed | Confinement breaks agent file access; classic-confinement requires Snap Store review | **No** — confinement is a non-starter for an agent that needs whole-filesystem access |

**6a. curl-pipe-bash specifics:**

*What goes wrong (the security objection):* The user runs `curl -fsSL https://agentlinux.org/install.sh | bash`. They have no opportunity to read the script first. A compromised CDN, MITM (despite TLS, e.g. corporate proxies that re-sign), or a stolen GitHub Pages credential lets an attacker execute arbitrary code as root.

*What goes wrong (mid-stream interruption):* Documented in [curl issue #1399](https://github.com/curl/curl/issues/1399) and elsewhere. If the connection drops at byte N of the script, bash executes lines 1..N as the *complete* script. If line N is a partial `rm -rf /opt/foo` truncated to `rm -rf /`, you eat the system. This is why responsible curl-pipe-bash installers wrap **everything** in a single `main()` function and call it on the last line — so a truncated download never executes any "real" code.

*Mitigations to bake in:*
1. Wrap the whole script in `main() { ... }; main "$@"` so partial download executes nothing.
2. Publish a SHA256 manifest at `https://agentlinux.org/install.sh.sha256` so the security-conscious can `curl … | sha256sum -c <(curl install.sh.sha256) && bash install.sh`. (Documented but not the default flow — defaults must work for the lowest-friction install.)
3. Don't require `sudo bash`. Have the script `sudo` only the parts that need root, so the user can audit the script first by running it with `--dry-run`.
4. The script must be small and human-readable. The bulk of the work belongs in a downloaded payload (e.g., a tarball of installer scripts) which itself is integrity-checked.

**6b. Local `.deb` specifics:**

*What goes wrong:* `apt install ./agentlinux_0.3.0_amd64.deb` fails with `unmet dependencies: nodejs (>= 18) but it is not going to be installed`, because the user hasn't added the NodeSource repo. The .deb declares `Depends: nodejs (>= 18)` and apt has no candidate. User Googles, finds bad advice, ends up `dpkg -i --force-depends`-ing the package, ends up with a half-installed .deb that can't be cleanly uninstalled.

*What goes wrong (no auto-update):* Once installed, the .deb has no update path unless a repo is configured. The agent gets stuck on whatever version shipped at install time. (Claude Code itself still self-updates because that's owned by the binary, not the .deb — but the AgentLinux *plugin* that wraps it doesn't.)

*Mitigations:* The .deb's preinst should add the NodeSource repo (with apt-key, modern keyring approach) before declaring its dependency, OR bundle the Node setup script invocation in postinst. **This is the v0.2.0 phase-04 pattern; carry it forward if .deb is chosen.**

**6c. Snap specifics — DISQUALIFIES SNAP:**

Snap's strict confinement uses AppArmor + seccomp + namespaces to restrict an app to its own data directory + the `home` interface (which only sees non-hidden files in `$HOME`). An agent that needs to read/write arbitrary files in the user's home (which is the entire point of Claude Code) **cannot run under strict confinement**. Classic confinement disables this, but [requires Snap Store review](https://snapcraft.io/docs/classic-confinement) and is gated. Even with classic, the agent runs in a separate mount namespace that doesn't see the user's normal `~/.bashrc`, `~/.ssh`, etc., reliably.

**Conclusion:** Snap is structurally wrong for an agent. Don't ship a snap.

**Phase to address:** Distribution-mechanism decision happens in the *first* execution phase (installer foundation). Build curl-pipe-bash first; .deb optionally as a phase-2 packaging task once the installer is proven.

---

### Pitfall 7: Test-harness false positives (Docker passes, real Ubuntu fails)

**What goes wrong:**
The Docker test passes. The installer ships. A real user runs it on real Ubuntu. It breaks. Common causes:

1. **Running as root in Docker.** Default `ubuntu:22.04` images run commands as root with no `sudo` configured. The installer "just works" because every command effectively has root. On a real system the agent user has limited rights and needs sudo for some steps. The Docker test never exercises the sudo paths.
2. **No systemd in Docker.** Containers don't run systemd unless explicitly built with it. If the installer creates a systemd unit for an "agent supervisor", the Docker test doesn't run it. On real Ubuntu the unit file is loaded and may have errors that only surface at boot.
3. **No `/dev/kvm`, no nested virt.** Docker tests can't exercise QEMU-launched-from-installer scenarios. Some agent tools (Chrome DevTools MCP via Chrome) need device access that Docker may pass through differently than a real host.
4. **C/POSIX locale.** Default Ubuntu Docker images don't have `en_US.UTF-8` generated. UTF-8 output from agents (em-dashes, smart quotes, emoji) crashes Python tools and silently corrupts in some Node tools. See Pitfall 8.
5. **Different filesystem semantics.** Docker overlayfs handles inode-renames slightly differently from ext4. Atomic-rename (used by Claude Code self-update) works on both, but edge cases (cross-device rename when `~/.local/bin` is a separate mount) only manifest on real systems.
6. **systemd-resolved present on Ubuntu host but not in Docker.** Affects DNS for `npm install` and `claude` API calls in some weird configurations.
7. **No swap in Docker by default.** The Claude Code installer needs ≥4 GB RAM (per the docs); on low-mem CI runners the install gets OOM-killed and the test reports "install script failed" without the user-friendly "add swap" message.
8. **The `agent` user inside Docker has UID 1000 by default,** matching the Docker host. On a real system created by `useradd`, the agent's UID may be 1001+. Hard-coded UID assumptions in scripts (e.g., `chown 1000:1000`) work in Docker, fail in the wild.

**Why it happens:**
Docker is "Linux-shaped" but isn't Linux. Tests written against Docker test the installer-against-Docker, not the installer-against-Linux.

**How to avoid:**
1. **Run Docker tests as a non-root user inside the container.** `USER agent` in the test Dockerfile; the installer must use `sudo` (preinstalled and configured for the test user). This catches every "I forgot to sudo this command" bug.
2. **Use a systemd-enabled image** (e.g., `jrei/systemd-ubuntu` or `geerlingguy/docker-ubuntu2204-ansible`) for installer tests, OR have the installer skip systemd setup gracefully when systemd isn't running, and log it as a warning rather than a silent skip.
3. **Run the installer test on QEMU** (which the project plans to do) for the canonical acceptance test. Docker tests are smoke tests; QEMU is integration. Don't rely on Docker for acceptance.
4. **Generate the locale in the test image.** Or — better — make the installer generate the locale itself (Pitfall 8) so the install works on locale-broken systems.
5. **Test "after install, run `claude update`"** in both Docker and QEMU. This is the canonical test from PROJECT.md. Run it as the agent user, not root, with no PATH inheritance from the test runner: `sudo -u agent -i bash -c 'claude update'`.
6. **Test the worst-case invocation** at the end: `env -i HOME=/home/agent USER=agent /bin/bash -c 'claude --version'` — strips all environment and runs from a clean shell, simulating the worst-case automation context.

**Warning signs:**
- The Dockerfile has `USER root` (or no USER directive, defaulting to root).
- Tests don't include any `sudo -u agent` invocation.
- No QEMU test exists, only Docker.
- The test asserts "install script exit code is 0" but doesn't assert "the agent user can self-update."

**Phase to address:** **Test-harness phase**, in parallel with installer-foundation. The harness must exist before the installer is "done", because every iteration on the installer needs the test to validate it.

---

### Pitfall 8: Locale (C/POSIX) breaks UTF-8 output from agents

**What goes wrong:**
Default `ubuntu:22.04` Docker images and minimal-Ubuntu installs ship with `LANG=C.UTF-8` in some versions and `LANG=POSIX` in others. Some have *no locale generated at all* (`locale -a` returns just `C` and `POSIX`). When Claude Code prints an em-dash (`—`) or curly quote (`'`), or any agent tool emits emoji:

- Python-based tools: `UnicodeEncodeError: 'ascii' codec can't encode character`.
- Node tools (less likely now, but historic): output shows `?` or `\ufeff` garbage instead of the character.
- `printf` from shell scripts producing non-ASCII: silent truncation.
- `claude doctor` output may include checkmarks (`✓`/`✗`) and break.
- Logs become unreadable. Hooks that pipe output through other tools corrupt downstream.

**Why it happens:**
Docker base images strip locales to save space. Ubuntu cloud images sometimes do too. The `locales` package is not installed by default. `LANG` defaults to C.

**How to avoid:**
The installer must:
1. `apt-get install -y locales` (idempotent — already installed on most systems).
2. `locale-gen en_US.UTF-8` (or the user's preferred locale).
3. `update-locale LANG=en_US.UTF-8` to make it system-wide default.
4. Drop `/etc/profile.d/agentlinux-locale.sh` setting `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` for any shell that doesn't pick up `/etc/default/locale`.
5. For the agent user specifically, set `LANG`/`LC_ALL` in `~/.profile` (so login shells get it) and document it as a requirement for systemd units.

**Warning signs:**
- Test the installer in a `FROM ubuntu:22.04` Dockerfile with no extra setup. If `locale -a | grep -i utf` is empty after install, it's broken.
- Test agent output that includes a Unicode character: `claude doctor 2>&1 | grep '✓' || echo BROKEN`.
- The v0.2.0 phase research already flagged this (Pitfall 11 in v0.2.0 PITFALLS.md). It's still a thing.

**Phase to address:** Installer-foundation phase. Locale setup is one of the very first things the installer does, before any agent-tool install runs.

---

### Pitfall 9: Sudoers configuration mistakes can brick sudo for everyone

**What goes wrong:**
The installer adds passwordless sudo for the agent user via `/etc/sudoers.d/agent`. Common mistakes:

1. **Bad syntax** (typo, missing colon, unknown alias) → `sudo` refuses to run *for any user*, including root. The next person to run `sudo` is locked out. Recovery requires a recovery shell or single-user boot.
2. **Wrong file mode.** sudoers.d files MUST be mode 0440 (`-r--r-----`). Mode 0444, 0644, 0755 → sudo logs the file as "bad permissions" and ignores it (or refuses to start, depending on version).
3. **Wrong owner.** Must be `root:root`. If the installer runs `chown agent:agent /etc/sudoers.d/agent` by mistake, sudo ignores it.
4. **Filename contains a dot or tilde.** sudoers.d explicitly skips files with `.` or `~` in the name (per `sudoers(5)`). A file named `agentlinux.conf` is *silently ignored*. Files should be named like `agentlinux` (no extension) or `99-agentlinux`.
5. **Conflicting `secure_path` from another sudoers file.** If `/etc/sudoers` has `Defaults secure_path="…"` and `/etc/sudoers.d/agentlinux` has `Defaults:agent secure_path="…"`, ordering may differ from what's expected.
6. **Overly broad `NOPASSWD: ALL`** — security disaster. Anyone who pwns the agent owns the box.

**How to avoid:**
1. **Always validate before installing** with `visudo -c -f /tmp/agentlinux-sudoers-staged` (checks syntax of an arbitrary file). Only after a clean check, atomically `install -m 0440 -o root -g root /tmp/agentlinux-sudoers-staged /etc/sudoers.d/agentlinux`.
2. Use `install -m 0440 -o root -g root` (a single atomic command that sets mode + owner) instead of `cp` + `chmod` + `chown` (three steps, race-prone).
3. Avoid `NOPASSWD: ALL`. Specify exact commands: `agent ALL=(root) NOPASSWD: /usr/bin/apt-get install *, /usr/bin/systemctl restart agentlinux*` etc. Tighter is safer.
4. After installation, do a final `sudo -n true` test as the agent user to verify NOPASSWD works.
5. Ship an uninstaller that removes `/etc/sudoers.d/agentlinux` and a recovery doc ("If sudo is broken, boot to recovery and `rm /etc/sudoers.d/agentlinux`").

**Warning signs:**
- The installer uses `cp` + `chmod` + `chown` separately to deploy the sudoers file (race window).
- No `visudo -c -f` check before deployment.
- The sudoers file is named `agentlinux.sudoers` or `agentlinux.conf` (silently ignored due to dot in name).
- `NOPASSWD: ALL` appears anywhere.

**Phase to address:** Whichever phase introduces the agent user / installer scripts. Could be installer-foundation if sudo is needed from day one, or a later "agent user permissions" phase. Either way, gate it behind `visudo -c -f` validation.

---

### Pitfall 10: `/etc/skel` only applies at user-creation time

**What goes wrong:**
The v0.2.0 phase-04 research relied on `/etc/skel/.claude.json` and `/etc/skel/.bashrc` for new agent users. This is correct *the first time the user is created*. But:

1. **The user already exists** when the installer runs (sysadmin pre-created an `agent` user, or this is a re-run). `/etc/skel` is *not* applied; the existing user's config is untouched. The agent ends up with no MCP config, no PATH setup, etc.
2. **The plugin is updated** (e.g., a future `agentlinux update` command). Updating `/etc/skel/.claude.json` doesn't propagate to existing users.
3. **The user is created by another tool** (cloud-init, Ansible, manual `useradd -m`) before the AgentLinux installer runs. Same as case 1.

`/etc/skel` is a one-time template, not a config-management mechanism.

**How to avoid:**
1. The installer must populate the agent user's home **directly**, not via `/etc/skel`, for the existing-user case. Use `install -o agent -g agent -m 0644 …` to drop files with correct ownership.
2. **Also** populate `/etc/skel/` so any future user creations get the defaults. But never rely on it as the sole mechanism.
3. For config files that the user might modify (`.bashrc`, `.claude.json`), use idempotent merge (`jq` for JSON, marker-comment-based block insertion for shell rc) rather than overwriting. This way a re-run of the installer doesn't blow away the user's customizations.
4. Track which files the installer has installed via a manifest (e.g., `/var/lib/agentlinux/manifest.json`) so the uninstaller knows what to remove without touching files the user added.

**Warning signs:**
- The installer's only path for setting up agent config is `cp /etc/skel/X /home/agent/X`.
- Re-running the installer doesn't update the agent's `~/.bashrc` PATH wiring.
- An existing-user test isn't in the CI matrix.

**Phase to address:** Installer-foundation phase, simultaneously with agent-user creation. The "merge into existing" pattern needs to be the default path; `/etc/skel` is a fallback for genuinely-fresh systems.

---

### Pitfall 11: Agent creates recursive shims even after install is correct

**What goes wrong:**
Even with a perfect install, an AI agent may *still* create a recursive `npx` shim out of habit. The agent's training data is full of EACCES → npx-shim workarounds, so when the agent merely *anticipates* a permission issue (or sees an unrelated error and pattern-matches to "permission problem"), it may proactively write a shim like:
```bash
alias claude='npx @anthropic-ai/claude-code@latest'
```
This is the original bug class re-emerging not from a real permission failure but from agent-prior-belief.

**Why it happens:**
LLMs are pattern-matchers on prior context. They've seen "agent fails → npx workaround" thousands of times. If anything looks vaguely like a permission issue, they'll reach for the shim before checking.

**How to avoid:**
Make the install so unambiguously, *visibly* correct that the agent has no excuse to suspect a problem:

1. **Run `claude doctor` as the agent user as the *final* step of install** and include its (passing) output in the install summary. `claude doctor` checks all the things ("Native install: writable; PATH: configured; updates: enabled; …"). The agent sees this and updates its prior.

2. **Drop a marker file** that the agent's startup hook reads and surfaces:
   ```
   /etc/agentlinux/install-verified.json
   {
     "claude_path": "/home/agent/.local/bin/claude",
     "claude_owned_by": "agent",
     "claude_writable": true,
     "claude_self_update_tested": true,
     "verified_at": "2026-04-18T12:34:56Z"
   }
   ```
   When the agent considers permission concerns, the hook can present this evidence ("install-verified.json says ownership is correct").

3. **Never produce a `permission denied` error in the happy path.** If the agent ever sees that string during normal operation, all bets are off. Wrap any operation that *could* prompt for sudo with explicit error handling that surfaces "this should not have happened, please file a bug" rather than letting the EACCES bubble up.

4. **Ship a CLAUDE.md / agent-readable doc** in the agent user's home that says, at the top: "AgentLinux has set up Claude Code so it self-updates without sudo. If you see EACCES related to ~/.local/bin or ~/.claude, do NOT create an npx shim — instead run `claude doctor` and report the output. The shim pattern was the original bug this distro was built to eliminate." Agents read CLAUDE.md as authoritative project context.

5. **Run the canonical test on every install,** record the result in the manifest, and have the install fail loudly if it fails. Don't let a broken install ship "for the user to figure out" — the user *is* an agent, and an agent will paper over breakage.

6. **Use an exit message that explicitly tells the agent this is solved:** "Installation complete. Claude Code self-update verified. The agent user can run `claude update` without sudo. PATH is configured. Locale is UTF-8. **Do not create npx wrappers — the install is correct.**"

**Warning signs:**
- Agent in CI logs creates an alias or shim.
- Agent output mentions "permission" in any context other than "verified writable".
- The install succeeds but `claude doctor` shows ANY warning. (Warnings are agent-bait.)

**Phase to address:** All phases that touch the install path AND the registry/post-install agent-bootstrap phase. The marker file + CLAUDE.md ship in installer-foundation; the registry-CLI phase reinforces the "this is correct" signal in its own user-facing output.

---

### Pitfall 12: Conflicting Claude Code installs (npm + native, root + user)

**What goes wrong:**
Pre-existing installs from earlier attempts collide. Anthropic's [troubleshooting guide](https://code.claude.com/docs/en/troubleshooting) explicitly calls out: "Multiple Claude Code installations can cause version mismatches or unexpected behavior." Common shapes:

1. User previously ran `sudo npm install -g @anthropic-ai/claude-code` → `/usr/lib/node_modules/@anthropic-ai/claude-code` exists, root-owned.
2. AgentLinux installer runs the native installer → `~/.local/bin/claude` exists, agent-owned.
3. PATH order determines which one runs. `~/.local/bin` is usually before `/usr/bin`, but not always (depends on shell type and rc-file ordering).
4. `which -a claude` shows two binaries.
5. Auto-update updates the user-owned one cleanly. The root-owned one rots. If a tool ever invokes `claude` via absolute path `/usr/bin/claude` it gets the rotted version.

**How to avoid:**
Installer's preflight check runs `which -a claude` and `npm -g ls @anthropic-ai/claude-code` and lists every install location. If more than one is found, the installer either (a) refuses with a remediation message ("uninstall the npm-global version first: `sudo npm uninstall -g @anthropic-ai/claude-code`"), or (b) offers a `--cleanup-conflicting` flag that does the npm uninstall before proceeding.

**Warning signs:**
- `which -a claude | wc -l` returns > 1 after install.
- `claude doctor` reports conflicting installations.

**Phase to address:** Installer-foundation phase preflight checks, plus the testing phase needs a "dirty system with prior npm-global Claude Code" test case.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `sudo npm install -g` instead of per-user prefix | Two lines of installer code instead of ten | Reintroduces the original bug class. Agent self-update breaks, EACCES storm, recursive shims | **Never** — this is the explicit anti-pattern of the project |
| Use `nvm` because "everyone uses nvm" | Familiar to users | Breaks every non-interactive invocation (cron, systemd, sudo -u, ssh non-interactive) | Never for the default install. Acceptable only as a documented opt-in for users who insist |
| Skip `visudo -c -f` validation on sudoers file | Saves 3 lines of installer code | A typo bricks sudo system-wide; user must boot recovery to fix | Never |
| Skip the "install on dirty system" test case | Faster CI | First user with a pre-existing `agent` user files an angry bug | Acceptable only if v0.3.0 is explicitly scoped to "fresh Ubuntu only" and that's documented. Recommended: don't skip |
| Test only in Docker, not QEMU | Faster CI, no nested virt | Docker false positives ship broken installs to users | Acceptable for inner loop. Never for release gate |
| Use `/etc/skel` as the sole config-distribution mechanism | Simpler scripts | Existing-user case breaks; future plugin updates don't propagate | Never for v0.3.0; user-already-exists is a primary scenario |
| Leave `LANG=C` and assume the user fixed it | One less install step | Agent UTF-8 output silently corrupts; debugging is awful | Never |
| Bundle Claude Code binary in the installer (avoid network) | Offline install | Stale version on day 1; loses Anthropic's signed-release verification | Acceptable only if explicitly building an air-gapped variant; not for v0.3.0 default |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Claude Code install | `sudo npm install -g @anthropic-ai/claude-code` | `sudo -u agent -H curl -fsSL https://claude.ai/install.sh \| bash` (native installer, in agent's home) |
| Node.js install | `nvm install 22` for the agent user | NodeSource apt install (`/usr/bin/node` system-wide) + per-user `npm config set prefix ~/.local` |
| MCP server install | `sudo npm install -g chrome-devtools-mcp` | `sudo -u agent -H npm install -g chrome-devtools-mcp` (lands in `~/.local/lib/node_modules/`) |
| Sudoers file | `cp agentlinux.sudoers /etc/sudoers.d/`; `chmod 0440 …` (race) | Validate with `visudo -c -f staged` then `install -m 0440 -o root -g root staged /etc/sudoers.d/agentlinux` (atomic) |
| User creation | `useradd agent` (fails on re-run) | `id agent &>/dev/null \|\| useradd -m -s /bin/bash agent` |
| apt install | `apt install nodejs` (fails under unattended-upgrades) | `apt-get -o DPkg::Lock::Timeout=300 install nodejs` |
| Locale | Assume the user has `en_US.UTF-8` | `apt install locales && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8` |
| PATH for cron/systemd | Rely on `~/.bashrc` PATH | Drop `/etc/profile.d/agentlinux-path.sh` AND wrappers in `/usr/local/bin/` AND set `Defaults:agent secure_path` in sudoers |
| Self-update verification | `[ -x ~/.local/bin/claude ]` | `sudo -u agent -H claude doctor` (Anthropic's official check) |
| Distribution | Snap with strict confinement | curl-pipe-bash with mid-stream-protection wrapping; .deb optionally, no snap |

## Performance Traps

Performance isn't the primary axis here (this is an installer, not a server). The traps that matter are install-time:

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Install OOM-killed on small VPS | Install script exits with `Killed` at the binary-extract step | Document 4 GB RAM requirement; suggest `fallocate -l 2G /swapfile && swapon` if under 4 GB; surface a friendly message rather than letting the OOM message be the user's only signal | Ubuntu VPS instances < 4 GB (very common — 1 GB and 2 GB tiers) |
| Multiple npm installs serially in postinst | 90-second installer becomes 5 minutes | Parallelize independent installs; or skip optional ones until the registry CLI requests them | When the registry has > 5 default agents |
| `apt update` runs on every plugin invocation | Every command takes 10-30 seconds | Run `apt update` only when explicitly required (install/upgrade), cache the timestamp, skip if recent | Always for second invocation onward |
| `claude doctor` invoked synchronously in a hook | Every shell prompt takes 2+ seconds | Cache doctor output; run async; show stale-but-recent state | Any setup that hooks doctor into an interactive prompt |

## Security Mistakes

Beyond OWASP basics, domain-specific:

| Mistake | Risk | Prevention |
|---------|------|------------|
| `NOPASSWD: ALL` for the agent user | Compromise of the agent user (e.g., via prompt injection) becomes full root | Specify exact NOPASSWD commands; default to no-NOPASSWD |
| curl-pipe-bash without mid-stream protection | Network interruption executes a partial script that may have catastrophic effects | Wrap entire script in `main()` invoked on the last line; publish SHA256 manifest |
| Trusting unsigned `.deb` (`[trusted=yes]`) for the install | Malicious local repo or MITM serves a tampered package | Sign the .deb (post-v0.3.0); for v0.3.0 use HTTPS-only download + manifest check |
| Pre-shipping API keys in the install image | Credential leak | No API keys in the install — agent user authenticates first-run, OAuth flow |
| `/etc/sudoers.d/agentlinux` mode 0644 | Local users can read the policy (information disclosure) and possibly tamper depending on directory perms | Mode 0440, owner root:root |
| Storing agent's OAuth token in world-readable `~/.claude.json` | Local privilege escalation reads the token | `~/.claude.json` mode 0600, owned by agent (Claude Code does this; verify the installer doesn't reset it) |
| Background auto-update silently disabled to "avoid breakage" | Agent runs vulnerable old version indefinitely | Auto-update enabled by default; document how to opt out; test it works |
| Installer adds the NodeSource apt repo and *leaves it* with `[trusted=yes]` | Future apt updates from a compromised NodeSource serve any payload as root | Use proper keyring approach (NodeSource provides this); periodically refresh keys |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Installer silently does the wrong thing on a dirty system | User has weird breakage hours later, blames the installer | Loud preflight checks; error out with a clear remediation rather than continuing |
| The single-line install command requires the user to read `agentlinux.org/install.sh` to know what it does | Distrust; some users won't run it | Publish the script source in the GitHub repo; the install URL redirects to the GitHub raw URL (transparent) |
| The install runs without progress output | User thinks it hung; Ctrl+C interrupts mid-install | Step-by-step progress; ETA per phase; `--quiet` for CI |
| Re-running the installer asks for sudo password again from scratch | Annoying | Cache the user's sudo authentication for the install duration with `sudo -v` upfront |
| `claude doctor` warnings shown only on first run | User never sees subsequent regressions | The plugin's own status command should re-run doctor on demand |
| Uninstall leaves agent user's home untouched | Disk usage; unexpected for users who just wanted it gone | Documented two-step uninstall: `agentlinux uninstall` (removes plugin files only) and `agentlinux purge` (also removes agent user + home) |

## "Looks Done But Isn't" Checklist

- [ ] **`claude` on PATH:** Often missing for `cron`/`systemd`/`sudo -u` — verify with `sudo -u agent -i bash -c 'claude --version'` AND `sudo -u agent crontab -l` AND a one-shot systemd `User=agent` test.
- [ ] **Self-update writable:** Often missing because install ran as root — verify with `sudo -u agent -H test -w ~/.local/bin && sudo -u agent -H test -w ~/.claude && sudo -u agent -H claude doctor`.
- [ ] **Self-update actually works:** Often only the *path* is checked, not the *update* — verify with `sudo -u agent -H claude update` and assert exit 0 + version reported.
- [ ] **npm prefix per-user:** Often missing if the only test is "Claude Code works" — verify with `sudo -u agent -H bash -c 'npm config get prefix'` returns `/home/agent/.local`, AND `sudo -u agent -H npm install -g cowsay && cowsay test`.
- [ ] **Locale UTF-8:** Often missing on Docker tests — verify with `sudo -u agent -H bash -c 'locale | grep UTF-8'` returns matches AND `sudo -u agent -H printf '\xe2\x9c\x93 ok\n'` prints `✓ ok` not `?`.
- [ ] **Sudoers file valid:** Often missing because installer doesn't validate — verify with `visudo -c` (no errors) AND `sudo -n -u agent true` (no password prompt for the agent's specifically-allowed commands).
- [ ] **Idempotency:** Often missing because only fresh-install is tested — verify by running installer twice on the same image; second run should report "already installed, no changes" and exit 0.
- [ ] **Existing-user handling:** Often missing — verify by pre-creating an `agent` user with custom `~/.bashrc`, then running installer; the user's customizations must survive.
- [ ] **No conflicting installs:** Often missing because no preflight check — verify with `which -a claude | wc -l` returns 1.
- [ ] **No `permission denied` in install transcript:** Often missing because warnings are silently ignored — grep the install log for `EACCES`, `permission denied`, `not writable`. Any hit is a defect.
- [ ] **CLAUDE.md / install-verified.json present:** Often missing because not part of "core install" — verify both files exist and are readable by the agent.
- [ ] **Uninstaller actually uninstalls:** Often shipped as an afterthought — verify by install + uninstall + grep for residue (`/etc/sudoers.d/agentlinux`, agent home, NodeSource repo files).

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Pitfall 1: System-wide npm prefix used | MEDIUM | `sudo npm uninstall -g @anthropic-ai/claude-code`; remove `/usr/bin/claude` if a symlink; re-run installer with native-installer path |
| Pitfall 2: `~/.npm` cache owned by root | LOW | `sudo chown -R agent:agent ~agent/.npm` (Anthropic explicitly documents this) |
| Pitfall 3: nvm shim doesn't activate in cron | LOW | Add explicit PATH or `BASH_ENV` to cron, OR rip out nvm and switch to system Node + per-user prefix |
| Pitfall 4: PATH dropped for systemd | LOW | Add `Environment=PATH=/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin` to the unit file |
| Pitfall 5: Installer not idempotent | MEDIUM | Refactor to add preflight checks; bump version; ship as a patch |
| Pitfall 6: Shipped a snap | HIGH | Shipped product is wrong shape; rewrite as .deb or curl-pipe-bash; deprecate the snap |
| Pitfall 7: Test passed but real systems break | HIGH | Add QEMU + real-Ubuntu-CI; root-cause the false positive; expand the test matrix |
| Pitfall 8: Locale broken in production | LOW | `apt install locales && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8` (the same install steps the installer should have run) |
| Pitfall 9: Sudoers file bricked sudo | HIGH | Boot recovery shell; `rm /etc/sudoers.d/agentlinux`; reboot. If installer used `install -m 0440` atomically and `visudo -c -f` first, this never happens |
| Pitfall 10: `/etc/skel` changes didn't propagate | LOW | Run installer's "sync existing users" subcommand (which the installer should expose); or do it manually with the same `install -o agent …` calls |
| Pitfall 11: Agent created an npx shim post-install | MEDIUM | Find and remove the shim (`grep -r 'npx.*claude' ~/.bashrc ~/.profile ~/.zshrc /etc/profile.d/`); re-run install verification; surface install-verified.json to the agent prominently |
| Pitfall 12: Two `claude` installs collide | LOW | `sudo npm uninstall -g @anthropic-ai/claude-code`; reinstall with native installer; `claude doctor` to confirm |

## Pitfall-to-Phase Mapping

Phase placement assumes a roughly four-phase v0.3.0 plan: **(P1) Installer foundation**, **(P2) Default agent + npm-prefix correctness**, **(P3) Registry CLI**, **(P4) Test harness**. Test harness should be developed in parallel with P1 (not last) so each phase can validate against it.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1: System-wide npm prefix breaks self-update | P1 + P2 (decision in P1, implementation in P2) | `sudo -u agent -H claude update` succeeds in P4 test harness; `claude doctor` reports all writable |
| 2: npm prefix ownership for other npm packages | P2 | `sudo -u agent -H npm install -g cowsay && cowsay ok` succeeds in P4 |
| 3: Version manager + non-interactive shells | P1 (architectural decision: don't use nvm) | P4 tests: cron, systemd, `sudo -u`, non-interactive ssh all run `claude --version` successfully |
| 4: PATH dropped by non-interactive paths | P1 (foundational) | P4 includes the full invocation matrix; one row per: cron, systemd, sudo, ssh, su, env-stripped bash |
| 5: Installer not idempotent | P1 (every step) | P4 tests: re-run install; install on dirty system with pre-existing `agent` user; install with Node already present |
| 6: Distribution mechanism | P1 (decision and primary mechanism) + P3 (.deb optional packaging if chosen) | P4 tests the chosen mechanism end-to-end on a clean Ubuntu image |
| 7: Test-harness false positives | P4 (the harness itself), feedback to all earlier phases | Run installer in BOTH Docker and QEMU; require BOTH to pass before merging |
| 8: Locale | P1 (one of the first installer steps) | P4 verifies `locale -a \| grep UTF-8` and a Unicode-print smoke test |
| 9: Sudoers | P2 or wherever sudo-as-agent is first needed | P4 includes a "boot, install, run, verify sudo still works for root" test |
| 10: `/etc/skel` after-the-fact | P1 (architectural: never rely on /etc/skel alone) | P4 includes a "user pre-existed" test case |
| 11: Agent creates recursive shims | All phases (cumulative): P1 install verified message; P2 marker file; P3 registry-CLI output reinforces; P4 test that no shim is created in agent's home after install | Grep `~/.bashrc`, `~/.profile`, `~/.zshrc` for `npx.*claude` / `alias claude=` after a no-op agent run; must be empty |
| 12: Conflicting installs | P1 (preflight check) | P4 includes a "system already had `sudo npm install -g @anthropic-ai/claude-code`" test case |

## Sources

### Primary (HIGH confidence)
- [Claude Code: Advanced setup](https://code.claude.com/docs/en/setup) — Native installer is the recommended path; binary at `~/.local/bin/claude`; auto-update mechanism; npm package now installs binary via optional dep, not Node script.
- [Claude Code: Troubleshooting](https://code.claude.com/docs/en/troubleshooting) — `claude doctor`; permission checks (`test -w ~/.local/bin && test -w ~/.claude`); conflicting-install detection; "Do NOT use sudo npm install -g" warning.
- [npm: Resolving EACCES permissions errors](https://docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally/) — Official npm guidance: per-user prefix `~/.local`, never sudo for global installs.
- [sudoers(5) man page (Debian)](https://manpages.debian.org/buster/sudo/sudoers.5.en.html) — File mode 0440, ownership root:root, `secure_path`, NOPASSWD syntax, files-in-sudoers.d filename rules (no dots, no tildes).
- [Sudo project: secure_path advisory](https://www.sudo.ws/security/advisories/secure_path/) — Why secure_path matters; sudo 1.9.16 enables it by default.

### Secondary (MEDIUM confidence)
- [GitHub anthropics/claude-code #9327](https://github.com/anthropics/claude-code/issues/9327) — Real-world bug: self-update misbehaves with npm-with-prefix install (symlink case). Supports recommendation to prefer native installer over npm.
- [Snap classic confinement docs](https://snapcraft.io/docs/classic-confinement) — Confirms classic confinement requires Snap Store review and is the only viable mode for filesystem-touching agents.
- [Snap home interface](https://snapcraft.io/docs/reference/interfaces/home-interface/) — Strict confinement only sees non-hidden files in `$HOME`; disqualifies snap for agent use.
- [Setting Locale In Docker (Lei Mao)](https://leimao.github.io/blog/Docker-Locale/) — `locales` package not installed by default in Ubuntu Docker images; standard fix `locale-gen en_US.UTF-8 && update-locale`.
- [Debian wiki: AccountHandlingInMaintainerScripts](https://wiki.debian.org/AccountHandlingInMaintainerScripts) — `adduser --system` is idempotent; useradd is not (must guard with `id` check).
- [Debian apt-get DPkg::Lock::Timeout](https://blog.sinjakli.co.uk/2021/10/25/waiting-for-apt-locks-without-the-hacky-bash-scripts/) — Wait-for-lock pattern using `-o DPkg::Lock::Timeout=N` (clean alternative to retry loops).

### Tertiary (LOW confidence — corroborates with above sources)
- Multiple blog posts on curl-pipe-bash mid-stream interruption (the `main(){...};main` wrapping pattern is widely-recommended; the exact security tradeoff is a live debate).
- v0.2.0 phase-04 research (`.planning/milestones/v0.2.0-phases/04-agent-tool-packages/04-RESEARCH.md`) — Project-internal source for what was learned in the previous milestone, particularly on the v0.2.0 npm-as-root patterns we are now explicitly rejecting.

---
*Pitfalls research for: AgentLinux v0.3.0 Ubuntu plugin installer*
*Researched: 2026-04-18*
