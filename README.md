<!-- VERSION_START -->v0.3.6<!-- VERSION_END -->

# AgentLinux

**Agent-ready Linux in one command.**

Setting up a server to run coding agents is fiddlier than it looks. Install
the tools the usual way and they end up owned by the wrong user, so they can't
update themselves, and small permission problems keep interrupting the work you
actually wanted the agent to do.

AgentLinux gives you a host that's already set up correctly. One command
provisions a dedicated `agent` user with a runtime it fully owns, plus a small
CLI for installing agent tools. The tools install cleanly and keep themselves
up to date on their own — no permission errors, no manual repair.

[![test](https://github.com/Roo4L/Agent-Linux/actions/workflows/test.yml/badge.svg)](https://github.com/Roo4L/Agent-Linux/actions/workflows/test.yml)
[![release](https://github.com/Roo4L/Agent-Linux/actions/workflows/release.yml/badge.svg)](https://github.com/Roo4L/Agent-Linux/actions/workflows/release.yml)
[![license: MIT](https://img.shields.io/github/license/Roo4L/Agent-Linux)](LICENSE)

## Install

Run this on a clean host, as root or with sudo:

```bash
curl -fsSL https://agentlinux.org/install.sh | sudo bash
```

To pin an exact release (recommended for unattended provisioning):

```bash
AGENTLINUX_VERSION=v0.3.6 curl -fsSL https://agentlinux.org/install.sh | sudo bash
```

The installer downloads the release tarball and checks its SHA256 against a
sibling asset on GitHub Releases before running anything. A tampered or
half-downloaded tarball aborts with a clear error and touches nothing.

Already have an `agent` user, Node.js, or some of these tools? The installer
detects them and reconciles instead of clobbering — see
[Installing onto an existing host](docs/MIGRATION.md).

## Use it

```bash
agentlinux list                 # browse the catalog (25 tools)
agentlinux install claude-code  # install one
claude --version                # it's on PATH, owned by the agent user
```

From here the tool manages itself: `claude update` and the like just work,
because everything is owned by the `agent` user rather than root.

## Uninstall

```bash
sudo agentlinux-install --purge                  # remove everything AgentLinux added
sudo agentlinux-install --purge --remove-nodejs  # also drop the Node.js package
```

`--purge` removes the `agent` user's home, the PATH wiring, the sudoers
drop-in, and the install root. Node.js is kept unless you add `--remove-nodejs`.
Re-running the installer afterward starts from a clean slate.

## Requirements

- Ubuntu 22.04 / 24.04 / 26.04 LTS, or AlmaLinux 9 (x86_64)
- root or sudo for the one-time install
- `curl` (preinstalled on all supported releases)

ARM64 and more distros are on the roadmap.

## How versions stay stable

Every tool in the catalog is pinned to a version AgentLinux tests together
before each release, so a fresh install gives you a combination that's known to
work. You're not locked in: `agentlinux upgrade` shows where your installed
version, the curated pin, and upstream latest diverge, and `agentlinux pin`
sets a sticky override when you want to run ahead.

```bash
agentlinux pin claude-code=latest    # follow upstream for this tool
agentlinux pin claude-code=curated   # go back to the tested pin
agentlinux pin gsd=1.7.0             # pin an exact version
```

Details in [docs/STABILITY-MODEL.md](docs/STABILITY-MODEL.md).

## Built with Codex

Part of AgentLinux's quality work was driven with OpenAI's **Codex CLI**
alongside Claude Code. Codex ran the project's black-box QA campaign against
the full agent catalog — planning tests, reproducing failures in disposable
sandboxes, and routing findings to a fix — largely on its own, and several
shipped fixes came out of it.

The full write-up is in
[CODEX-QA-HACKATHON-REPORT.md](CODEX-QA-HACKATHON-REPORT.md); using Codex in
this repo is covered in [docs/codex.md](docs/codex.md).

## Learn more

- [How it works, component by component](docs/internals/) — the agent user,
  sudo drop-in, runtime, catalog, and CLI, each in about a minute
- [Vision](docs/VISION.md) — what AgentLinux is for and where it's going
- [Contributing](CONTRIBUTING.md) — filing issues, opening PRs, running the
  tests. The `tests/bats/` suite is the behavior contract.
- Source and releases: [github.com/Roo4L/Agent-Linux](https://github.com/Roo4L/Agent-Linux)

## License

[MIT](LICENSE). The "AgentLinux" name and crab mascot are not covered by the
license — forks should pick their own name so they don't imply endorsement.
