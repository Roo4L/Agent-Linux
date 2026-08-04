# Architecture Research — AgentLinux Plugin (v0.3.0)

**Domain:** Installable Ubuntu extension that provisions an agent-ready environment (dedicated agent user, correctly-owned Node.js, default agent, agent registry CLI)
**Researched:** 2026-04-18
**Confidence:** HIGH

---

## 1. Summary & Design Stance

The plugin is a **bash-orchestrated installer** that runs against an existing Ubuntu system, plus a **Node.js-backed CLI (`agentlinux`)** that ships with the installer for post-install agent management.

Three guiding decisions drive the structure:

1. **Installer is the source of truth.** A single entrypoint (`bin/agentlinux-install`) is what users actually run. Distribution mechanism (curl-pipe-bash vs `apt install agentlinux`) wraps the same script. Idempotency means re-running it converges, never destroys.
2. **Provisioner modules are bash, not a framework.** The v0.2.0 6-script chain proved layered numbered shell scripts are debuggable, ordered, and easy to test. The plugin reuses that exact model — minus the Packer/QEMU/OpenNebula plumbing.
3. **The registry CLI is a Node.js CLI installed for the agent user, not a system daemon.** It re-uses the same provisioner scripts the installer used (via a small dispatcher) so adding a new agent has one code path, not two.

**Carry-forward / new split (one-liner per v0.2.0 script):**

| v0.2.0 script | v0.3.0 disposition |
|---|---|
| `01-base.sh` | OBSOLETE — host already has a base OS; we don't own it |
| `02-one-context.sh` | OBSOLETE — no OpenNebula |
| `03-nodejs.sh` | CARRIES FORWARD as `provisioner/30-nodejs.sh` (Node 22 from NodeSource) |
| `04-packages.sh` (fpm + local apt repo) | OBSOLETE as a packaging mechanism; npm-global-as-agent-user replaces it. The MCP-config-merge logic carries forward into `provisioner/40-default-agent.sh` and into the registry catalog's per-agent post-install hooks. |
| `05-chrome.sh` | CARRIES FORWARD as `catalog/agents/chrome-devtools-mcp/install.sh` (only invoked when that agent is requested — not in the default install path) |
| `99-cleanup.sh` | OBSOLETE — no image to compact |
| /etc/skel-based default Claude Code config (with MCP pre-wired) | CARRIES FORWARD into `provisioner/40-default-agent.sh` (writes config under `agent` user's `~/.claude.json`) and into a `templates/skel/` directory the installer optionally seeds |
| Wrapper scripts at `/usr/local/bin/claude` | OBSOLETE — `npm install -g` as the agent user puts the bin on the agent user's own PATH (`~/.npm-global/bin/claude`); no system-wide wrapper needed |
| fpm packaging | DEFERRED — may be reused if we ship the plugin itself as a `.deb` (one of the open distribution-mechanism options); not on the critical path |

---

## 2. System Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                       USER (root or sudoer on Ubuntu)                     │
│   $ curl -fsSL https://agentlinux.org/install.sh | sudo bash             │
│   $ sudo apt install agentlinux               (alt distribution)         │
└────────────────────────┬─────────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────────────┐
│              INSTALLER ENTRYPOINT  (bin/agentlinux-install)              │
│   Parses flags → sources lib/ helpers → runs provisioner/ scripts in    │
│   order → drops registry CLI in agent user's PATH → prints next steps   │
└────┬──────────────────┬─────────────────┬─────────────────┬─────────────┘
     │ runs as root     │ runs as root    │ as agent user   │ root then agent
     ▼                  ▼                 ▼                 ▼
┌──────────┐      ┌────────────┐   ┌──────────────┐   ┌────────────────────┐
│ 10-agent │      │ 30-nodejs  │   │ 40-default-  │   │ 50-registry-cli    │
│ -user.sh │ ───▶ │ .sh        │ ─▶│ agent.sh     │ ─▶│ .sh                │
│          │      │            │   │              │   │                    │
│ create   │      │ NodeSource │   │ npm i -g     │   │ install agentlinux │
│ user,    │      │ apt repo,  │   │ <default>    │   │ CLI as agent user  │
│ sudoers, │      │ install    │   │ (as agent),  │   │ + bash completion  │
│ shell,   │      │ nodejs,    │   │ verify it    │   │                    │
│ home,    │      │ set npm    │   │ runs, write  │   │                    │
│ locale   │      │ prefix to  │   │ ~/.claude.   │   │                    │
│          │      │ ~/.npm-    │   │ json default │   │                    │
│          │      │ global     │   │              │   │                    │
└──────────┘      └────────────┘   └──────────────┘   └────────────────────┘
                                                                │
                                                                ▼
                                          ┌──────────────────────────────────┐
                                          │ POST-INSTALL — REGISTRY CLI       │
                                          │ agent$ agentlinux list            │
                                          │ agent$ agentlinux install gsd     │
                                          │ agent$ agentlinux uninstall <x>   │
                                          │                                   │
                                          │ Reads catalog/, dispatches to     │
                                          │ catalog/agents/<name>/install.sh  │
                                          │ Runs as the agent user — same    │
                                          │ npm-prefix, no sudo needed.       │
                                          └──────────────────────────────────┘
                                                                │
                                                                ▼
                                          ┌──────────────────────────────────┐
                                          │ TEST HARNESS  (tests/)            │
                                          │ • docker/   — clean Ubuntu image  │
                                          │   runs the installer end-to-end   │
                                          │ • qemu/     — ephemeral VM, same  │
                                          │   bats suite, slower, gated       │
                                          │ • bats/     — assertion suite     │
                                          │   (canonical: agent self-updates  │
                                          │   claude without sudo)            │
                                          └──────────────────────────────────┘
```

---

## 3. Recommended Project Structure

```
agent-linux/                                  # repo root (existing)
├── plugin/                                   # NEW — everything for v0.3.0 lives here
│   ├── bin/
│   │   ├── agentlinux-install                # installer entrypoint (bash)
│   │   └── agentlinux                        # registry CLI shim (calls Node)
│   │
│   ├── lib/                                  # shared bash helpers, sourced by scripts
│   │   ├── log.sh                            # log_info / log_warn / log_error / step
│   │   ├── idempotent.sh                     # ensure_user / ensure_line_in_file / etc.
│   │   ├── as_user.sh                        # run-as-agent-user helper (su/sudo wrapper)
│   │   └── distro.sh                         # detect Ubuntu version, abort on mismatch
│   │
│   ├── provisioner/                          # ordered, idempotent install steps
│   │   ├── 10-agent-user.sh                  # create user, sudoers, shell, locale, /etc/skel
│   │   ├── 30-nodejs.sh                      # NodeSource Node 22 + per-user npm prefix
│   │   ├── 40-default-agent.sh               # installs default agent as the agent user
│   │   └── 50-registry-cli.sh                # installs `agentlinux` CLI for agent user
│   │
│   ├── cli/                                  # the `agentlinux` registry CLI (Node.js)
│   │   ├── package.json                      # name: agentlinux, bin: agentlinux
│   │   ├── src/
│   │   │   ├── index.js                      # arg parser, command dispatch
│   │   │   ├── commands/
│   │   │   │   ├── list.js                   # `agentlinux list`
│   │   │   │   ├── install.js                # `agentlinux install <name>`
│   │   │   │   ├── uninstall.js              # `agentlinux uninstall <name>`
│   │   │   │   ├── info.js                   # `agentlinux info <name>`
│   │   │   │   └── doctor.js                 # `agentlinux doctor` (env diagnostic)
│   │   │   ├── catalog.js                    # load + validate catalog entries
│   │   │   ├── runner.js                     # spawns catalog/agents/<n>/install.sh
│   │   │   └── log.js                        # mirrors lib/log.sh format
│   │   └── README.md
│   │
│   ├── catalog/                              # the agent registry — schema + data
│   │   ├── schema.json                       # JSON Schema for an agent entry
│   │   ├── catalog.json                      # array of agent entries (embedded data)
│   │   └── agents/                           # per-agent install/uninstall scripts
│   │       ├── claude-code/
│   │       │   ├── install.sh
│   │       │   └── uninstall.sh
│   │       ├── gsd/
│   │       │   ├── install.sh
│   │       │   └── uninstall.sh
│   │       └── chrome-devtools-mcp/
│   │           ├── install.sh                # carries v0.2.0 chrome install logic
│   │           └── uninstall.sh
│   │
│   ├── templates/
│   │   └── skel/
│   │       └── .claude.json                  # default Claude Code config w/ MCP block
│   │                                          #   (substituted at install time)
│   │
│   └── tests/
│       ├── docker/
│       │   ├── Dockerfile.ubuntu-22.04
│       │   ├── Dockerfile.ubuntu-24.04
│       │   └── run.sh                        # builds image, runs installer, runs bats
│       ├── qemu/
│       │   ├── cloud-init/                   # NoCloud user-data for fresh Ubuntu VM
│       │   ├── boot.sh                       # boots ephemeral VM, ssh-injects bats
│       │   └── run.sh                        # full VM smoke
│       └── bats/
│           ├── 00-installer-runs.bats        # installer exits 0
│           ├── 10-agent-user.bats            # user exists, has shell, sudo works
│           ├── 20-node-ownership.bats        # npm prefix in $HOME, no root files
│           ├── 30-default-agent.bats         # claude --version succeeds as agent
│           ├── 40-self-update.bats           # CANONICAL: claude self-update no sudo
│           ├── 50-registry-cli.bats          # agentlinux list / install / uninstall
│           └── helpers.bash                  # shared assertions
│
├── packaging/                                # NEW — distribution wrapping
│   ├── deb/                                  # OPTIONAL .deb wrapper (uses fpm; v0.2.0 carry-forward)
│   │   └── build.sh
│   └── curl-installer/
│       └── install.sh                        # the script behind https://agentlinux.org/install.sh
│                                              #   → downloads tarball, extracts, runs bin/agentlinux-install
│
├── website/                                  # existing v0.1.0 landing page
└── .planning/                                # existing
```

**Structure Rationale:**

- **`plugin/` as a top-level container.** Keeps the plugin self-contained from the website and the v0.2.0 archives. When someone clones the repo and looks at `plugin/`, they see the whole plugin and nothing else.
- **`bin/` only for entrypoints.** Two binaries — the installer and the post-install CLI shim. Everything else is library code.
- **`lib/` for bash helpers, `cli/src/` for Node helpers.** Symmetrical: each language has one place for shared code. The `log.sh` ↔ `log.js` pairing keeps installer and CLI output consistent.
- **`provisioner/` numbered scripts mirror the v0.2.0 model exactly.** Numbering leaves room (10, 30, 40, 50) for future insertions without renumbering. We deliberately skip 20 to leave a gap for a "system prerequisites" step (apt update, build tools) if needed later.
- **`catalog/` separates schema, data, and per-agent code.** `schema.json` is the contract. `catalog.json` is the data the CLI reads. `agents/<name>/` holds the actual install logic — one directory per agent, so adding an agent is a one-PR change with no central code edits.
- **`templates/skel/` is real config templates.** Distinct from `catalog/` because these are *defaults applied during the base install*, not per-agent.
- **`tests/` has three peer dirs: `docker/`, `qemu/`, `bats/`.** The bats suite is the assertion library; docker and qemu are two different ways to *run* the same suite. This separation lets us add a third runner (e.g. `lxd/`) later without rewriting tests.
- **`packaging/` is separate from `plugin/`.** The plugin doesn't know how it's being shipped. The curl-installer is just a thin downloader; the .deb wrapper is also thin. Both invoke the same `bin/agentlinux-install` once they have the files on disk.

---

## 4. Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|----------------|----------------|
| **`bin/agentlinux-install`** | Single entrypoint; parses flags, sources lib, runs provisioner scripts in order, exits with clear status | Bash, ~150 LOC |
| **`lib/*.sh`** | Reusable helpers: logging, idempotency primitives (ensure-user, ensure-line, ensure-pkg), `as_user` wrapper, distro detection | Bash, sourced — never executed |
| **`provisioner/10-agent-user.sh`** | Create `agent` user (or whatever `--user` says), set shell `/bin/bash`, ensure home, configure locale, write sudoers drop-in, seed `~/.bashrc` with `PATH` for npm-global | Bash, idempotent |
| **`provisioner/30-nodejs.sh`** | Install Node.js 22 LTS from NodeSource (system-wide), then `as_user agent` set `npm config set prefix ~/.npm-global`, create the dir, ensure `~/.bashrc` exports `PATH=$HOME/.npm-global/bin:$PATH` | Bash, idempotent |
| **`provisioner/40-default-agent.sh`** | Read `--default-agent` flag (default: `claude`), invoke `catalog/agents/<name>/install.sh` as the agent user, then write `~/.claude.json` from `templates/skel/.claude.json`, verify the binary runs | Bash, dispatches into catalog |
| **`provisioner/50-registry-cli.sh`** | `as_user agent npm install -g <local-tarball-of-cli/>` (or from npm registry once published); writes bash completion to `/etc/bash_completion.d/agentlinux` | Bash, idempotent |
| **`bin/agentlinux`** | Tiny shim: `exec node /opt/agentlinux/cli/src/index.js "$@"` *or* installed by npm to `~/.npm-global/bin/agentlinux` directly. (Preferred: latter — keeps everything in agent's own prefix) | Bash one-liner OR direct npm bin entry |
| **`cli/src/index.js`** | Arg parser (use `commander` or hand-roll — small surface), dispatches to `commands/*.js` | Node.js, ESM |
| **`cli/src/catalog.js`** | Loads `catalog.json`, validates against `schema.json` (use `ajv`), supports remote catalog override via `AGENTLINUX_CATALOG_URL` env or `~/.config/agentlinux/config.json` (embedded ships always; remote is a *merge*, not a replace, so offline still works) | Node.js |
| **`cli/src/runner.js`** | For `install <name>`: looks up entry, locates `catalog/agents/<name>/install.sh` (bundled with the CLI), spawns it with proper env (`AGENT_USER`, `AGENT_HOME`, `NPM_PREFIX`), streams output | Node.js, child_process |
| **`catalog/schema.json`** | JSON Schema (draft 2020-12) for a catalog entry — see §6 | Static JSON |
| **`catalog/catalog.json`** | Embedded catalog — array of entries, validated by schema at CLI startup | Static JSON |
| **`catalog/agents/<n>/install.sh`** | Per-agent install logic, run as the agent user, expects standard env vars from runner | Bash, idempotent |
| **`templates/skel/.claude.json`** | Default Claude Code config including the chrome-devtools MCP block (templated — installer substitutes `{{AGENT_HOME}}` etc.) | JSON-with-mustache |
| **`tests/bats/*.bats`** | Black-box assertions against a freshly-installed system — language-independent, easy to read | Bats |
| **`tests/docker/run.sh`** | Builds clean Ubuntu image, COPIES the plugin in, runs `bin/agentlinux-install`, then runs the bats suite inside the container. Fast (< 2 min), runs in CI on every PR | Bash + Dockerfile |
| **`tests/qemu/run.sh`** | Boots a fresh Ubuntu cloud image with cloud-init, scp's plugin in, runs installer + bats over ssh. Slow (~5 min), runs nightly / on release | Bash + cloud-init |

---

## 5. Installer Entrypoint — Shape, Idempotency, Argument Surface

### Shape

**Recommendation:** ship two flavors that wrap the same thing.

1. **Curl-pipe-bash (primary, for try-it-now adoption):**
   ```bash
   curl -fsSL https://agentlinux.org/install.sh | sudo bash
   curl -fsSL https://agentlinux.org/install.sh | sudo bash -s -- --user agent --default-agent claude
   ```
   The fetched script is `packaging/curl-installer/install.sh`. It:
   1. Downloads a tagged release tarball of the plugin
   2. Verifies SHA256 (checksum embedded in the curl script)
   3. Extracts to `/opt/agentlinux/`
   4. Execs `/opt/agentlinux/bin/agentlinux-install "$@"`

2. **`apt install agentlinux` (secondary, for users who prefer package management):**
   A `.deb` built with fpm (carry-forward from v0.2.0) that:
   - Installs the same files to `/opt/agentlinux/`
   - Drops `/usr/local/bin/agentlinux-install` symlink → `/opt/agentlinux/bin/agentlinux-install`
   - Postinst does **not** auto-run the installer (user runs it explicitly with their flags)
   - Hosted on a public PPA later (out of scope for v0.3.0 per PROJECT.md — keep this build path *ready* but not the default)

Both paths converge on `bin/agentlinux-install` so there is exactly one installer to test.

### Idempotency Model

Every operation is **converging, not commanding.** Use these primitives from `lib/idempotent.sh`:

| Primitive | Behavior |
|-----------|----------|
| `ensure_user <name>` | Skip if `getent passwd` succeeds; else `useradd -m -s /bin/bash` |
| `ensure_line_in_file <line> <file>` | grep -F first; append only if missing |
| `ensure_apt_repo <name> <url> <key>` | Check `/etc/apt/sources.list.d/<name>.list`; install only if missing |
| `ensure_apt_pkg <pkg>` | Check `dpkg -s` first; install only if missing |
| `ensure_npm_global <pkg>` | `as_user agent npm list -g --depth=0` parse; install only if missing |
| `ensure_npm_prefix <user> <prefix>` | Check `npm config get prefix --userconfig=$HOME/.npmrc`; set only if mismatched |

**Re-running the installer must be safe and converge to the same end state.** This is the single biggest UX feature — users will re-run after partial failures.

### Argument Surface

```
agentlinux-install [OPTIONS]

Options:
  --user <name>             Agent username to create or use (default: agent)
  --default-agent <id>      Catalog id to install as default (default: claude-code, special: 'none')
  --no-default              Skip default-agent install (alias for --default-agent none)
  --skip-node               Don't install Node.js (assume present and properly owned)
  --skip-registry           Don't install the agentlinux CLI (rare; mostly for testing)
  --node-version <ver>      Override Node.js LTS version (default: 22)
  --npm-prefix <path>       Custom npm global prefix (default: $AGENT_HOME/.npm-global)
  --catalog-url <url>       Override remote catalog URL for the registry CLI
  --dry-run                 Print actions without executing
  --verbose                 Stream all subcommand output
  --quiet                   Errors only
  --version                 Print plugin version and exit
  --help                    Show this and exit

Exit codes:
  0  success
  1  generic failure
  2  invalid arguments
  3  unsupported distro / version
  4  precondition failed (no sudo / not Ubuntu / etc.)
  5  one or more provisioner steps failed (re-run is safe)
```

---

## 6. Catalog Format

### Schema (JSON Schema 2020-12, abridged)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://agentlinux.org/schema/catalog-entry.json",
  "type": "object",
  "required": ["id", "name", "description", "version_method", "install"],
  "properties": {
    "id":          { "type": "string", "pattern": "^[a-z0-9-]+$" },
    "name":        { "type": "string" },
    "description": { "type": "string" },
    "homepage":    { "type": "string", "format": "uri" },
    "tags":        { "type": "array", "items": { "type": "string" } },

    "version_method": {
      "enum": ["npm", "binary", "apt", "script"]
    },
    "package":     { "type": "string", "description": "npm package id, .deb name, or binary URL template" },

    "install": {
      "type": "object",
      "required": ["script"],
      "properties": {
        "script":       { "type": "string", "description": "path inside catalog/agents/<id>/, relative" },
        "needs_chrome": { "type": "boolean", "default": false },
        "needs_sudo":   { "type": "boolean", "default": false }
      }
    },

    "uninstall": {
      "type": "object",
      "properties": {
        "script": { "type": "string" }
      }
    },

    "post_install_config": {
      "description": "Optional config snippets to merge into the agent user's environment",
      "type": "object",
      "properties": {
        "claude_mcp_server":   { "type": "object" },
        "claude_settings":     { "type": "object" },
        "env_lines":           { "type": "array", "items": { "type": "string" } }
      }
    },

    "verify_command": {
      "type": "string",
      "description": "Single-line command run as the agent user; non-zero exit = failed verification"
    }
  }
}
```

### Filled-in Example: Claude Code

```json
{
  "id": "claude-code",
  "name": "Claude Code",
  "description": "Anthropic's official CLI coding agent",
  "homepage": "https://claude.com/claude-code",
  "tags": ["agent", "default", "anthropic"],
  "version_method": "npm",
  "package": "@anthropic-ai/claude-code",
  "install": {
    "script": "install.sh",
    "needs_chrome": false,
    "needs_sudo": false
  },
  "uninstall": {
    "script": "uninstall.sh"
  },
  "post_install_config": {
    "env_lines": [
      "# Claude Code config dir",
      "export CLAUDE_CONFIG_DIR=\"$HOME/.claude\""
    ]
  },
  "verify_command": "claude --version"
}
```

### Filled-in Example: Chrome DevTools MCP (carries v0.2.0 logic)

```json
{
  "id": "chrome-devtools-mcp",
  "name": "Chrome DevTools MCP Server",
  "description": "Lets Claude Code drive a headless Chrome via DevTools protocol",
  "homepage": "https://github.com/ChromeDevTools/chrome-devtools-mcp",
  "tags": ["mcp", "chrome", "browser"],
  "version_method": "npm",
  "package": "chrome-devtools-mcp",
  "install": {
    "script": "install.sh",
    "needs_chrome": true,
    "needs_sudo": true
  },
  "uninstall": {
    "script": "uninstall.sh"
  },
  "post_install_config": {
    "claude_mcp_server": {
      "name": "chrome-devtools",
      "command": "npx",
      "args": ["-y", "chrome-devtools-mcp@latest", "--headless", "--no-sandbox"]
    }
  },
  "verify_command": "npx -y chrome-devtools-mcp --version"
}
```

### Catalog Resolution Order

1. **Embedded** (`catalog/catalog.json` shipped with the CLI) — always loaded first, always works offline.
2. **Remote merge** (env `AGENTLINUX_CATALOG_URL` or config file) — fetched if reachable, merged on top by `id`. Failure to fetch is a warning, not an error. Allows updating the catalog without shipping a new plugin release.
3. **Validation:** every loaded entry must pass `schema.json` (via `ajv`); invalid entries are dropped with a warning.

---

## 7. Data Flow — Install Path

```
                          User runs:
              $ curl ... | sudo bash -s -- --user agent

                                  │
                                  ▼
   ┌─────────────────────────────────────────────────────┐
   │ packaging/curl-installer/install.sh                 │
   │  • Verify checksum                                  │
   │  • Extract /opt/agentlinux/                         │
   │  • exec bin/agentlinux-install --user agent         │
   └───────────────────────┬─────────────────────────────┘
                           │
                           ▼
   ┌─────────────────────────────────────────────────────┐
   │ bin/agentlinux-install                              │
   │  • parse flags  → AGENT_USER=agent                  │
   │  • source lib/log.sh, lib/distro.sh, lib/idempotent │
   │  • lib/distro.sh:assert_supported_ubuntu            │
   │  • for s in provisioner/[0-9]*.sh ; do bash $s; done│
   └─────┬───────────┬───────────┬──────────────┬────────┘
         │           │           │              │
         ▼           ▼           ▼              ▼
  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────┐
  │10-agent- │ │30-nodejs │ │40-default│ │50-registry │
  │ user.sh  │ │   .sh    │ │ -agent.sh│ │  -cli.sh   │
  ├──────────┤ ├──────────┤ ├──────────┤ ├────────────┤
  │ensure_   │ │ensure_   │ │as_user   │ │as_user     │
  │ user     │ │ apt_repo │ │ agent    │ │ agent npm  │
  │ agent    │ │ NodeSrc  │ │ catalog/ │ │ install -g │
  │          │ │ensure_   │ │ agents/  │ │ /opt/agent │
  │ensure_   │ │ apt_pkg  │ │ claude-  │ │ linux/cli  │
  │ sudoers  │ │ nodejs   │ │ code/    │ │            │
  │ drop-in  │ │as_user   │ │ install  │ │ writes     │
  │          │ │ agent    │ │ .sh      │ │ /etc/bash_ │
  │ensure_   │ │ npm cfg  │ │          │ │ completion │
  │ locale   │ │ prefix   │ │as_user   │ │ .d/agent   │
  │          │ │ ~/.npm-  │ │ agent    │ │ linux      │
  │ensure_   │ │ global   │ │ render   │ │            │
  │ ~/.bash- │ │ensure_   │ │ skel/.   │ │            │
  │ rc PATH  │ │ line in  │ │ claude.  │ │            │
  │          │ │ ~/.bashrc│ │ json     │ │            │
  │          │ │          │ │ to       │ │            │
  │          │ │          │ │ ~/.claude│ │            │
  │          │ │          │ │ .json    │ │            │
  │          │ │          │ │          │ │            │
  │          │ │          │ │ verify:  │ │            │
  │          │ │          │ │ claude   │ │            │
  │          │ │          │ │ --version│ │            │
  └──────────┘ └──────────┘ └──────────┘ └────────────┘
                                  │
                                  ▼
                ┌────────────────────────────────────┐
                │ Final state on the host:           │
                │  • user `agent` exists, sudo OK    │
                │  • node, npm in /usr/bin           │
                │  • ~agent/.npm-global/bin in PATH  │
                │  • claude binary at               │
                │    ~agent/.npm-global/bin/claude   │
                │  • ~agent/.claude.json with MCP    │
                │  • agentlinux CLI at              │
                │    ~agent/.npm-global/bin/agentlx  │
                │  • agent$ claude --self-update     │
                │    works without sudo  ← PROVES IT │
                └────────────────────────────────────┘
```

---

## 8. Data Flow — Registry Path (`agentlinux install gsd`)

```
                  Agent user runs (no sudo):
              agent$ agentlinux install gsd

                                  │
                                  ▼
   ┌──────────────────────────────────────────────────────┐
   │ ~agent/.npm-global/bin/agentlinux                    │
   │  → exec node /opt/agentlinux/cli/src/index.js        │
   │     install gsd                                      │
   └──────────────────────────┬───────────────────────────┘
                              │
                              ▼
   ┌──────────────────────────────────────────────────────┐
   │ cli/src/index.js                                     │
   │  • parse argv                                        │
   │  • route → commands/install.js                       │
   └──────────────────────────┬───────────────────────────┘
                              │
                              ▼
   ┌──────────────────────────────────────────────────────┐
   │ cli/src/commands/install.js                          │
   │  1. catalog = await loadCatalog()                    │
   │     ├─ load /opt/agentlinux/catalog/catalog.json    │
   │     ├─ try fetch AGENTLINUX_CATALOG_URL (if set)    │
   │     └─ ajv.validate(schema, entry)                   │
   │  2. entry = catalog.findById('gsd')                  │
   │  3. if entry.install.needs_sudo: warn + abort if    │
   │     not ran with `sudo -E agentlinux install ...`   │
   │  4. runner.run(entry)                                │
   └──────────────────────────┬───────────────────────────┘
                              │
                              ▼
   ┌──────────────────────────────────────────────────────┐
   │ cli/src/runner.js                                    │
   │  • script = /opt/agentlinux/catalog/agents/gsd/      │
   │             install.sh                               │
   │  • env = { AGENT_USER, AGENT_HOME, NPM_PREFIX,       │
   │           CATALOG_ENTRY_JSON }                       │
   │  • spawn(bash, [script], { env, stdio: 'inherit' })  │
   └──────────────────────────┬───────────────────────────┘
                              │
                              ▼
   ┌──────────────────────────────────────────────────────┐
   │ catalog/agents/gsd/install.sh                        │
   │   #!/bin/bash                                        │
   │   set -euo pipefail                                  │
   │   npm install -g get-shit-done       # under agent's │
   │                                       # own prefix — │
   │                                       # NO SUDO      │
   │   # plus per-agent post-install:                     │
   │   #   merges settings.json hooks                     │
   │   #   (carries forward v0.2.0 GSD postinst logic)   │
   └──────────────────────────┬───────────────────────────┘
                              │
                              ▼
   ┌──────────────────────────────────────────────────────┐
   │ Verify: run entry.verify_command                     │
   │   `gsd --version` exits 0                            │
   │ Print: "Installed gsd 1.25.1"                        │
   │ Exit 0                                               │
   └──────────────────────────────────────────────────────┘
```

**Symmetry note:** the same `runner.js` + `catalog/agents/<n>/install.sh` pair is used by `provisioner/40-default-agent.sh` during the initial install. Adding a new agent = one PR, one directory, one catalog entry. No code edits to the CLI.

---

## 9. Test Harness Architecture

### Three components, one assertion suite

```
        bats suite (tests/bats/)
       ┌────────────────────────┐
       │ canonical assertions   │
       │ language-independent   │
       │ runs IN the target env │
       └─────────┬──────────────┘
                 │
       ┌─────────┴──────────────┐
       │                        │
       ▼                        ▼
  Docker runner            QEMU runner
  (tests/docker/)         (tests/qemu/)

  fast (~90s)             slow (~5min)
  runs every PR           runs nightly
  PID-1 caveats           true VM, systemd works
                          init system tested
```

### Bats assertion suite — canonical tests

```
tests/bats/40-self-update.bats
─────────────────────────────────────────────────
@test "agent user can self-update Claude Code without sudo" {
  run sudo -u agent bash -lc 'claude --version'
  [ "$status" -eq 0 ]
  pre_version="$output"

  run sudo -u agent bash -lc 'npm update -g @anthropic-ai/claude-code'
  [ "$status" -eq 0 ]
  refute_output --partial 'EACCES'
  refute_output --partial 'permission denied'

  run sudo -u agent bash -lc 'claude --version'
  [ "$status" -eq 0 ]
}
```

This is the **canonical acceptance test** named in `PROJECT.md` — proving the motivating bug class is gone.

### Docker runner

```dockerfile
# tests/docker/Dockerfile.ubuntu-24.04
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y curl sudo bats jq ca-certificates
COPY plugin/ /opt/agentlinux/
RUN /opt/agentlinux/bin/agentlinux-install --user agent --default-agent claude-code
COPY plugin/tests/bats/ /opt/tests/bats/
CMD ["bats", "-r", "/opt/tests/bats/"]
```

- Runs in CI on every PR (GitHub Actions)
- Two image variants: `ubuntu:22.04` and `ubuntu:24.04`
- Limitation: no real systemd; tests that touch services skip with `if ! systemctl --quiet ; then skip ; fi`

### QEMU runner

- Boot a fresh `ubuntu-24.04-cloud-amd64.img` with cloud-init seeding an ssh key
- `scp -r plugin/ ubuntu@vm:/tmp/`
- `ssh ubuntu@vm 'sudo /tmp/plugin/bin/agentlinux-install --user agent'`
- `scp tests/bats/ ubuntu@vm:/tmp/tests/`
- `ssh ubuntu@vm 'sudo bats -r /tmp/tests/'`
- Tear down VM
- Runs nightly + on release tag

### Why bats specifically

| Option | Verdict |
|---|---|
| Plain shell + `assert_*` helpers | Works but no test-isolation, no setup/teardown, no readable output |
| **Bats** | Bash-native, runs *inside* the target system without extra runtime, TAP output for CI, well-known. Best fit. |
| pytest | Forces Python on the test target — extra dep, extra surface |
| Bash-only with `set -e` | Single failure halts everything; no visibility into which assertion failed |

Bats wins because the *test target is bash*, the *thing being tested is bash + node*, and the *assertions are mostly "this command exits 0 / produces this output"* — no need for a richer test runtime.

### Test runtime sizing

- Bats suite: ~10 .bats files, ~30 test cases total at v0.3.0 ship
- Per Docker run: ~90 seconds (include image build + installer run + assertions)
- Per QEMU run: ~5 minutes (boot is dominant)
- CI plan: Docker runs on every push; QEMU runs nightly on `master` and on tagged releases

---

## 10. Logging / Observability

### During Installation (user-facing)

`lib/log.sh` exposes:
- `log_step "Creating agent user"` — bold cyan, indented progress marker
- `log_info` / `log_warn` / `log_error` — colored, timestamped to stderr
- All commands are streamed *unless* `--quiet`; on `--verbose`, sub-shells inherit stdout/stderr; otherwise sub-shells go to a logfile and a one-line summary is shown

Example output (default verbosity):

```
==> AgentLinux installer 0.3.0
==> Detected: Ubuntu 24.04 LTS (noble)
==> [1/4] Creating agent user 'agent'
    ✓ user created
    ✓ sudoers drop-in /etc/sudoers.d/agentlinux written
    ✓ locale en_US.UTF-8 ensured
==> [2/4] Installing Node.js 22 LTS
    ✓ NodeSource apt repo added
    ✓ nodejs 22.18.0 installed
    ✓ npm prefix set to /home/agent/.npm-global
==> [3/4] Installing default agent: claude-code
    ✓ @anthropic-ai/claude-code 2.1.77 installed
    ✓ ~/.claude.json seeded
    ✓ verified: claude 2.1.77 (Claude Code)
==> [4/4] Installing agentlinux registry CLI
    ✓ agentlinux 0.3.0 installed
    ✓ bash completion installed

✓ Done in 47s. Try:
    sudo su - agent
    claude
    agentlinux list
```

### Persistent Log File

Everything (verbose or not) is also written to `/var/log/agentlinux/install-<timestamp>.log`. On failure, the installer prints:

```
✗ Step 3 failed. See full log:
    /var/log/agentlinux/install-2026-04-18T10-23-44.log
  Re-run is safe — installer is idempotent:
    sudo agentlinux-install --user agent --verbose
```

### CLI (`agentlinux`) Output

`cli/src/log.js` mirrors the bash style:
- `agentlinux install gsd` — same `==>` `✓` style as the installer
- Logs to stderr; data (e.g. `agentlinux list --json`) goes to stdout
- Non-zero exit on any failure
- `agentlinux doctor` runs a diagnostic checklist (node version, npm prefix correctness, PATH sanity, claude binary present, MCP config valid JSON)

---

## 11. Suggested Build Order

Dependencies between components dictate ordering. Phases are sized for one focused unit of work each.

| # | Phase / Component | Depends On | Notes |
|---|---|---|---|
| **1** | `lib/` helpers (log, idempotent, as_user, distro) | nothing | Foundation; ~200 LOC, fully unit-testable with bats |
| **2** | `provisioner/10-agent-user.sh` + `bin/agentlinux-install` skeleton | lib | First end-to-end integration; running this alone produces a usable agent user |
| **3** | `provisioner/30-nodejs.sh` (Node + per-user npm prefix) | lib, 10-agent-user | This is the **trickiest** step — proves the no-sudo-needed claim. Validate with `sudo -u agent npm install -g cowsay` (smoke test) |
| **4** | `provisioner/40-default-agent.sh` + `templates/skel/.claude.json` + `catalog/agents/claude-code/install.sh` | 30-nodejs | First catalog agent. Don't build the full catalog yet — just the one path. |
| **5** | `tests/docker/` + `tests/bats/` (00, 10, 20, 30, **40 self-update — the canonical test**) | 1-4 | Lock in the no-sudo-self-update gate before touching the registry CLI |
| **6** | `cli/` (Node CLI) — `list`, `info`, embedded catalog only | nothing (lives in its own Node project), but its install path needs 30-nodejs | Can be built in parallel with steps 1-4 if a second person works on it. Unit-tested in isolation. |
| **7** | `cli/` — `install` and `uninstall` commands + `runner.js` + `catalog/agents/gsd/install.sh` | 6, 4 | Now `agentlinux install gsd` works end-to-end |
| **8** | `provisioner/50-registry-cli.sh` (wires the CLI into the installer) | 6, 7 | Connects CLI to the installer pipeline |
| **9** | `catalog/agents/chrome-devtools-mcp/install.sh` (carries v0.2.0 chrome install) | 7 | Tests the `needs_chrome: true` path; second non-trivial agent |
| **10** | `tests/bats/50-registry-cli.bats` + extended docker tests | 8, 9 | Locks in registry CLI behavior |
| **11** | `packaging/curl-installer/install.sh` + release tarball workflow | 1-10 (full plugin works) | The shippable artifact. GitHub Action: tag → build tarball → upload to releases → curl-installer points at it |
| **12** | `tests/qemu/` runner | 1-10 (works in docker), QEMU available on CI | Nightly + release-tag verification on a true VM |
| **13** | `packaging/deb/build.sh` (fpm wrapper) | 11 | OPTIONAL for v0.3.0; can defer to v0.3.1. Carries forward fpm knowledge from v0.2.0 |

**Critical-path dependency chain:** 1 → 2 → 3 → 4 → 5 → 7 → 8 → 11

**Parallelizable:** step 6 (CLI dev) can run alongside 1-4. Steps 9, 12, 13 can ship after the v0.3.0 tag.

---

## 12. Carry-Forward Integration Points (Explicit Map)

| v0.2.0 artifact | v0.3.0 destination | What carries / what changes |
|---|---|---|
| `packer/scripts/01-base.sh` | OBSOLETE | Host already has base OS |
| `packer/scripts/02-one-context.sh` | OBSOLETE | No OpenNebula |
| `packer/scripts/03-nodejs.sh` (NodeSource Node 22 install) | `plugin/provisioner/30-nodejs.sh` | KEEP NodeSource setup verbatim. ADD: per-user npm prefix step (`as_user agent npm config set prefix ~/.npm-global` + PATH export). REMOVE: fpm install (no packaging needed) |
| `packer/scripts/04-packages.sh` (fpm + local apt repo + 3 .debs) | OBSOLETE as a unit | The *pattern* of "install npm package then merge MCP config" splits into `provisioner/40-default-agent.sh` (default agent) and `catalog/agents/<n>/install.sh` (everything else). `fpm`/local-apt-repo/.deb-postinst plumbing all gone. |
| `packer/scripts/05-chrome.sh` (Google Chrome install + cleanup) | `plugin/catalog/agents/chrome-devtools-mcp/install.sh` | KEEP the apt-add → install → apt-mark hold → repo-cleanup sequence verbatim. Move from "always-installed in image" to "installed only when this agent is requested" |
| `packer/scripts/99-cleanup.sh` (truncate logs, zero free space, etc.) | OBSOLETE | No image to compact; host owns its own log rotation |
| **MCP-config-merge logic** (jq merge into `~/.claude.json`, iterate /home/*/, also write /etc/skel) | `plugin/catalog/agents/chrome-devtools-mcp/install.sh` + `templates/skel/.claude.json` | CARRIES FORWARD. New simplification: only one user (the agent), so no /home/*/ iteration. /etc/skel still seeded for future safety. |
| **GSD postinst logic** (`npx get-shit-done-cc --claude --global` + settings.json merge) | `plugin/catalog/agents/gsd/install.sh` | CARRIES FORWARD verbatim, runs as agent user instead of via .deb postinst |
| **Wrapper scripts** (`/usr/local/bin/claude`, `/usr/local/bin/gsd`) | OBSOLETE | Per-user npm prefix puts the bin on the agent user's own PATH at `~/.npm-global/bin/`. No wrapper indirection needed. |
| **fpm packaging knowledge** | `plugin/packaging/deb/build.sh` (optional v0.3.1+) | DEFERRED. The plugin *itself* may eventually ship as a `.deb`; fpm is the right tool for that. Not on v0.3.0 critical path. |
| **/etc/skel default-config approach** | `plugin/templates/skel/.claude.json` + `provisioner/10-agent-user.sh` | KEEP. Even though we have one agent user, seeding /etc/skel makes the design future-proof and aligns with Linux conventions. |

---

## 13. NEW vs MODIFIED-FROM-v0.2.0 (Quick Reference)

### NEW (no v0.2.0 analog)

- `bin/agentlinux-install` — installer entrypoint (v0.2.0 had Packer; this is fundamentally different)
- `lib/idempotent.sh` — converging install primitives (v0.2.0 always built clean; never had to be idempotent)
- `lib/distro.sh` — Ubuntu version detection (v0.2.0 owned the distro)
- `lib/as_user.sh` — run-as-agent-user helper (v0.2.0 had `agent` user only at deploy time)
- `provisioner/10-agent-user.sh` — host-side user provisioning (v0.2.0 delegated to one-context)
- `provisioner/50-registry-cli.sh` — installs the registry CLI (no equivalent in v0.2.0)
- **All of `cli/`** — registry CLI is entirely new; no v0.2.0 analog
- **All of `catalog/`** — registry catalog format is new; v0.2.0 had a fixed three-package set
- `templates/skel/` (as a structured template directory with substitution) — new
- **All of `tests/docker/` and `tests/qemu/`** — v0.2.0 only validated via Packer build + manual deploy
- **All of `tests/bats/`** — bats was not used in v0.2.0
- `packaging/curl-installer/` — new distribution mechanism
- Catalog schema (JSON Schema, version_method, post_install_config) — new

### MODIFIED FROM v0.2.0

- `provisioner/30-nodejs.sh` — keep NodeSource Node 22 install; add per-user npm prefix setup
- `catalog/agents/chrome-devtools-mcp/install.sh` — port v0.2.0 `05-chrome.sh` + the chrome-devtools-mcp .deb postinst into a single script
- `catalog/agents/gsd/install.sh` — port v0.2.0 GSD .deb postinst into a single script (drop the .deb wrapping)
- `catalog/agents/claude-code/install.sh` — port v0.2.0 claude .deb postinst, dropping wrapper-script generation (npm prefix handles PATH)
- `templates/skel/.claude.json` — port v0.2.0 /etc/skel/.claude.json, parameterizing $HOME paths

### CARRY-FORWARD KNOWLEDGE (not code)

- **NodeSource setup script URL + apt-key handling** (from v0.2.0 `03-nodejs.sh`)
- **Google Chrome apt repo cleanup** (from v0.2.0 `05-chrome.sh` — the apt-mark hold + key removal sequence)
- **`jq -s '.[0] * .[1]'` for JSON config merging** (from v0.2.0 MCP config merge)
- **GSD installer non-interactive invocation** (`npx get-shit-done-cc --claude --global`)
- **Chrome --no-sandbox / --headless flags for server use** (v0.2.0 Pitfall 8)
- **fpm staging-dir pattern** — kept in back pocket for `packaging/deb/build.sh` later

---

## 14. Anti-Patterns to Avoid

### Anti-Pattern 1: A "framework" instead of a script

**What people do:** Reach for Ansible, Salt, Chef, or write a custom Python orchestrator.
**Why it's wrong:** Adds a runtime dependency on the host. The whole point is "runs on a clean Ubuntu box." Bash + npm is the bare minimum.
**Do this instead:** Bash provisioner scripts, sourced helpers, no orchestration framework.

### Anti-Pattern 2: Running Node.js as root (or `sudo npm install -g`) anywhere

**What people do:** Install everything as root because "the installer runs as root anyway."
**Why it's wrong:** Reproduces the original bug. Files end up root-owned in places the agent user must write to. Self-updates fail with EACCES.
**Do this instead:** Always switch to the agent user (`as_user agent ...`) before any npm operation. The agent user's npm prefix is `$HOME/.npm-global` — nothing under root's control.

### Anti-Pattern 3: System-wide MCP config (`/etc/claude-code/managed-mcp.json`)

**What people do:** Use the system-wide managed-mcp.json because "it's cleaner."
**Why it's wrong:** Per Phase 4 research (HIGH confidence): managed-mcp.json takes **exclusive control** — users cannot add their own MCP servers afterward. Hostile to the user.
**Do this instead:** Per-user `~/.claude.json` (the current correct location for MCP config in Claude Code 2.x).

### Anti-Pattern 4: Hand-rolling user/SSH/network setup

**What people do:** Write custom scripts to add the user to /etc/passwd, configure SSH, etc.
**Why it's wrong:** `useradd`, `usermod`, `/etc/sudoers.d/`, `chown` — these are well-tested. Don't re-invent.
**Do this instead:** Use `useradd -m -s /bin/bash`, drop a sudoers file in `/etc/sudoers.d/`, that's it.

### Anti-Pattern 5: Wrapper scripts under /usr/local/bin

**What people do:** Carry forward the v0.2.0 wrapper-script pattern (`/usr/local/bin/claude` → `exec /usr/bin/node /opt/agentlinux/.../claude`).
**Why it's wrong:** With per-user npm prefix, `npm install -g` puts the binary directly on the agent's PATH. Wrappers add an indirection that breaks self-update (the wrapper points at a path that npm just replaced).
**Do this instead:** Trust the per-user npm prefix. No wrappers. PATH does the work.

### Anti-Pattern 6: Fetching the catalog only from remote

**What people do:** Always fetch `catalog.json` from a remote URL.
**Why it's wrong:** Breaks offline use; breaks if agentlinux.org is down; adds a network dependency to a CLI that should be reliable.
**Do this instead:** Embedded catalog ships with the CLI; remote is a *merge*, not a *replace*; remote-fetch failure is a warning, not an error.

### Anti-Pattern 7: Running the installer non-idempotently

**What people do:** Use `useradd agent` (errors if exists), `apt-get install` (no check), `echo X >> ~/.bashrc` (duplicates lines).
**Why it's wrong:** Re-running the installer to recover from partial failure breaks instead of converging. Worst-of-both-worlds.
**Do this instead:** Every operation goes through `lib/idempotent.sh` primitives.

---

## 15. Integration Points

### External Services (network deps)

| Service | When | Pattern | Failure Mode |
|---|---|---|---|
| NodeSource apt repo | provisioner/30-nodejs.sh | Add repo, apt update, apt install nodejs, leave repo for future updates | Network failure → installer aborts at step 2; re-run is safe |
| npm registry | every npm install | Default `npm install` against registry.npmjs.org | Mirror via `--registry` flag if needed (hostile-network env) |
| Google apt repo | catalog/agents/chrome-devtools-mcp/install.sh | Add → install Chrome → apt-mark hold → remove repo (per v0.2.0 Pitfall 4) | Only triggered when chrome-mcp agent installed |
| Remote catalog URL (optional) | cli/src/catalog.js | Fetch + merge with embedded; warning on failure | Falls back to embedded; never blocks CLI usage |
| Release tarball download | packaging/curl-installer/install.sh | curl + sha256 verify + tar -xz | Network failure aborts before any system change |

### Internal Boundaries

| Boundary | Communication | Notes |
|---|---|---|
| installer (bash) ↔ provisioner scripts | shell `bash provisioner/NN.sh`, env vars (`AGENT_USER`, `AGENT_HOME`) | Each script is independently runnable for debugging |
| provisioner ↔ catalog (during 40-default-agent) | runner shells out to `catalog/agents/<n>/install.sh` with env vars | Same dispatch path the CLI uses — single code path for "install an agent" |
| CLI (Node) ↔ catalog scripts (bash) | `child_process.spawn('bash', [scriptPath], { env, stdio: 'inherit' })` | Streaming output, exit code propagates |
| CLI (Node) ↔ catalog data | reads `catalog.json` from filesystem; validates with ajv | Embedded with the CLI's npm package |
| installer ↔ CLI | installer invokes `npm install -g` of the CLI; never imports it | Loose coupling — CLI ships independently if desired |
| tests/bats ↔ everything | Black-box: runs commands, asserts outputs/exit codes | Tests do not import any internal code; they test the assembled system |

---

## 16. Scaling Considerations

| Scale | Architecture Adjustments |
|---|---|
| **Single host, single user** (v0.3.0 default) | Current design — no changes |
| **Multiple agent users on one host** (out of scope per PROJECT.md, but design-affects) | Re-run installer with different `--user`; provisioner is idempotent so 30-nodejs.sh skips Node reinstall, only the per-user npm-prefix step runs again. Already supported by the design. |
| **Fleet of hosts** | Wrap the curl-pipe-bash in user's existing config-management (Ansible, Salt). The plugin doesn't try to be a fleet manager. |
| **Distros beyond Ubuntu** (v0.4+) | `lib/distro.sh` already exists as the abstraction point. Add `lib/distro-fedora.sh`, route `provisioner/30-nodejs.sh` through a distro-aware package-source helper. The catalog-and-CLI half of the architecture is distro-independent. |
| **Catalog growth (many agents)** | Embedded catalog stays small; remote-merge handles growth without re-shipping the plugin. If catalog becomes huge (>100 entries), add `agentlinux search <query>`. |

---

## 17. Sources

### v0.2.0 carry-forward (HIGH confidence — already validated in this project)

- `.planning/milestones/v0.2.0-research/ARCHITECTURE.md` — Packer/QEMU/fpm architecture, anti-patterns
- `.planning/milestones/v0.2.0-phases/03-bootable-image-with-agent-user/03-RESEARCH.md` — agent user / sudoers / one-context internals
- `.planning/milestones/v0.2.0-phases/04-agent-tool-packages/04-RESEARCH.md` — fpm pattern, MCP config locations, GSD installer behavior, Chrome install pitfalls

### Per-user npm prefix (HIGH confidence)

- [npm Docs — Resolving EACCES permissions errors when installing packages globally](https://docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally/)
- [sindresorhus/guides — npm-global-without-sudo](https://github.com/sindresorhus/guides/blob/main/npm-global-without-sudo.md)
- [npm Docs — npm-config (prefix)](https://docs.npmjs.com/cli/v9/commands/npm-config/)

### Bats test framework (MEDIUM confidence — well-known but not lib-of-record verified)

- bats-core GitHub — bash-native testing framework, TAP output

### JSON Schema for catalog (HIGH confidence)

- [JSON Schema 2020-12](https://json-schema.org/draft/2020-12)
- ajv (Node.js validator) — de facto standard for JSON Schema in Node

### Cloud-init for QEMU test harness (HIGH confidence)

- Ubuntu cloud images + NoCloud datasource (used the same way in v0.2.0 Packer build)

---

*Architecture research for: AgentLinux Plugin v0.3.0 (Ubuntu)*
*Researched: 2026-04-18*
*Author: project research subagent*
