<!-- VERSION_START -->v0.3.0<!-- VERSION_END -->

# AgentLinux

**Agent-ready Ubuntu, one command.**

AgentLinux provisions a dedicated `agent` user with a correctly-owned Node.js
runtime so agent tools like Claude Code and GSD self-update without EACCES or
sudo fights. Curated stable versions; explicit override with `agentlinux pin`.

[![test](https://github.com/Roo4L/Agent-Linux/actions/workflows/test.yml/badge.svg)](https://github.com/Roo4L/Agent-Linux/actions/workflows/test.yml)
[![release](https://github.com/Roo4L/Agent-Linux/actions/workflows/release.yml/badge.svg)](https://github.com/Roo4L/Agent-Linux/actions/workflows/release.yml)
[![license: MIT](https://img.shields.io/github/license/Roo4L/Agent-Linux)](LICENSE)

## Install

One command on a clean Ubuntu 22.04, 24.04 or 26.04 host (root/sudo required):

```bash
curl -fsSL https://agentlinux.org/install.sh | sudo bash
```

Equivalent form (some hardening guides prefer the process-substitution shape):

```bash
sudo bash -c "$(curl -fsSL https://agentlinux.org/install.sh)"
```

Pin to an exact release (recommended for unattended provisioning):

```bash
AGENTLINUX_VERSION=v0.3.0 curl -fsSL https://agentlinux.org/install.sh | sudo bash
```

The installer downloads the release tarball and verifies its SHA256 against a
sibling asset on GitHub Releases before executing anything. A tampered or
partially-downloaded tarball aborts the install with a clear error and touches
nothing on disk.

## Verify

```bash
agentlinux list
agentlinux install claude-code
claude --version
```

`agentlinux list` also shows each agent's `pinned_version` — the curated
version AgentLinux tests end-to-end together before each release. Running
`claude update` later goes through Claude Code's own updater and writes into
the agent-owned install tree (no `sudo`, no EACCES). That's the whole point.

## Uninstall

```bash
sudo agentlinux-install --purge
sudo agentlinux-install --purge --remove-nodejs
```

`--purge` removes the `agent` user's home directory, the `/etc/profile.d/`
PATH wiring, the `/etc/sudoers.d/agentlinux` drop-in, the catalog staging
directory, and the entire install root at `/opt/agentlinux/`. Node.js is
preserved by default; add `--remove-nodejs` to drop the NodeSource apt list
and the `nodejs` package as well. A re-run of the curl installer after
`--purge` starts from a clean slate — there is no state hidden elsewhere.

## Why AgentLinux — concepts

Each AgentLinux surface — installer, agent user, sudo drop-in, Node.js runtime,
the agent catalog, the registry CLI, and the curated agent set (Claude Code,
GSD, Playwright) — solves a specific bug class that the naive `sudo npm
install -g` path leaves broken. The internals docs walk through one component
at a time: what the problem is, what AgentLinux does about it, and the value
vs. the naive approach.

See [docs/internals/README.md](docs/internals/README.md) for the index — nine
short component docs, each answering "what value does AgentLinux provide
here" in under a minute.

## Stability model

AgentLinux ships *curated combos*: every catalog agent is pinned to an exact
version that we test together end-to-end (Docker × {22.04, 24.04, 26.04} +
QEMU × {22.04, 24.04, 26.04}) before each release. When you install an agent, you get the
curated pin; when you want to run ahead of it, you can — `agentlinux upgrade`
shows the 3-way divergence between installed, curated, and upstream latest,
and `agentlinux pin` sets sticky overrides so power users are not re-nagged.

AGT-02 remains a permission invariant: whether you stay on the curated pin or
run `claude update` past it, AgentLinux's release-gate test verifies the
self-update path succeeds with zero `EACCES` and zero `sudo` prompts.

See [docs/STABILITY-MODEL.md](docs/STABILITY-MODEL.md) for the user-facing
one-page summary and [docs/decisions/011-stability-first-version-pinning.md](docs/decisions/011-stability-first-version-pinning.md)
for the full architectural decision record.

### Escape hatch

```bash
agentlinux pin claude-code=latest
agentlinux pin claude-code=curated
agentlinux pin gsd=1.38.0
```

`=latest` tells `agentlinux upgrade` to follow upstream for that agent. `=curated`
clears the sticky override. `=<semver>` pins to an exact version, even past the
catalog's curated choice. Precedent: Homebrew's `brew pin`.

## Requirements

- Ubuntu 22.04 LTS, 24.04 LTS, or 26.04 LTS (x86_64)
- root or sudo access for the one-time install
- `curl` preinstalled (stock on all three releases)

Not yet supported in v0.3.0: ARM64, Fedora/Alma/Rocky/Arch. Those are on the
v0.4+ roadmap. See [.planning/REQUIREMENTS.md](.planning/REQUIREMENTS.md) for
the full behavior contract.

## Security

The installer wraps its body in `main() { ... }; main "$@"` so a truncated
download (connection reset mid-transfer) yields a bash syntax error *before*
any commands run — partial-download execution is not possible. The release
tarball is fetched over HTTPS and verified against a sibling `.sha256` asset
published on the same GitHub Release before extraction. GPG signatures are
on the v0.4+ roadmap (ADR-006); v0.3.0's trust story is HTTPS + SHA256 +
maintainer 2FA + branch protection.

Report vulnerabilities via the repository's Security tab (coordinated
disclosure).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to file issues, open PRs, and
run the test harness locally. The `tests/bats/` suite is the behavior contract
— PRs that change behavior should add or update a `@test` per
[`docs/HARNESS.md`](docs/HARNESS.md) §4 (Review Loop).

## License

AgentLinux is released under the [MIT License](LICENSE) — see
[`docs/decisions/013-license-mit.md`](docs/decisions/013-license-mit.md) for
the rationale and the SPDX-header convention applied to source files.

The "AgentLinux" name and the crab mascot SVG are not covered by the MIT
license — forks should pick their own name to avoid implying maintainer
endorsement.

## Links

- **Source + issues:** https://github.com/Roo4L/Agent-Linux
- **Releases:** https://github.com/Roo4L/Agent-Linux/releases
- **Architecture decisions:** [docs/decisions/](docs/decisions/)
- **Internals (developer docs):** [docs/internals/](docs/internals/)
- **Test harness spec:** [docs/HARNESS.md](docs/HARNESS.md)
- **Stability model (user-facing):** [docs/STABILITY-MODEL.md](docs/STABILITY-MODEL.md)
- **Landing page:** https://agentlinux.org

## About

AgentLinux exists because "sudo npm install -g" breaks two real things:
it causes `EACCES` on any subsequent non-root operation under `~/.npm/`, and
for tools that write their own updater into a root-owned prefix (Claude Code
is the canonical case) it creates a recursive-shim loop at `/usr/local/bin/`
that the tool cannot self-update past. AgentLinux fixes both by giving agents
their own user with a per-user npm prefix and `PATH` wired across every
invocation mode (interactive shell, non-interactive SSH, cron, systemd user
units, `sudo -u agent`, `sudo -u agent -i`). Everything else — the catalog,
the curated combos, the reconciliation verbs — is downstream of that one
decision.
