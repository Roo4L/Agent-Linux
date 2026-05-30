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

If you already have an `agent` user, Node.js, or any of these agents installed, see [Brownfield install](#brownfield-install).

The installer downloads the release tarball and verifies its SHA256 against a
sibling asset on GitHub Releases before executing anything. A tampered or
partially-downloaded tarball aborts the install with a clear error and touches
nothing on disk.

## Brownfield install (existing user / Node.js / agents)

If your host already has an `agent` user, a Node.js install, or any of the
catalog agents (claude-code, gsd, playwright), AgentLinux detects them up
front and decides on a per-component basis. There are four possible
states:

- **Reuse** — the existing component matches AgentLinux's contract; the
  provisioner or recipe short-circuits without writing.
- **Create** — the component is absent; the greenfield path runs as in
  a fresh-host install.
- **Remediate** — the component is present but has a fixable defect
  (wrong ownership on the npm prefix, drifted sudoers, broken catalog
  agent). The installer either prompts you per action in TTY mode or
  requires `--yes` in non-interactive mode (`apt install -y`-style).
- **Bail** — the component has an irreconcilable defect (e.g. the
  existing `agent` user has the wrong login shell). The installer
  exits with code `65` and a remediation hint.

**Preview first — zero changes:**

```console
$ agentlinux install --dry-run
[DET-01] user=agent uid=1001 shell=/bin/bash home=/home/agent writable=true
[DET-02] nodejs=v22.x source=nodesource user_writable=false
[DET-04] claude-code status=broken path=/usr/local/bin/claude owner=root
[DET-04] gsd status=absent
[DET-04] playwright-cli status=absent
[DET-05] sudoers=present sha256=ok

pre-flight resolution:
  user        agent       Reuse      (existing user matches contract)
  nodejs      v22.x       Reuse      (NodeSource, correct major)
  npm-prefix  /usr/lib/   Remediate  (REMEDIATE-01 — root-owned; rebases to ~agent/.npm-global)
  sudoers     ok          Reuse
  claude-code broken      Remediate  (REMEDIATE-04 — reinstall under agent)

exit code: 0 (dry-run — no state changed)
```
*(illustrative — version strings and component layout may differ on your host)*

**Apply in non-interactive mode** (`--yes` opts in to every required
remediation in one shot — there are no per-action flags):

```console
$ agentlinux install --yes
[REMEDIATE-01] rebasing npm-global to /home/agent/.npm-global
[REMEDIATE-04] reinstalling claude-code under agent (preserving ~/.claude/)
[INSTALL] complete
```

**In a terminal** (`stdin` is a TTY), the installer asks `Proceed with
this remediation? [Y/n]` per state-overwriting action; declining one
skips it (the component stays as-is, flagged
`reused — declined remediation` in `agentlinux list`) and continues
with the others.

**Exit codes:**

- `0` — success
- `64` (`EX_USAGE`) — bad command-line flags or contradictory options
  (e.g. `--dry-run --yes`)
- `65` (`EX_DATAERR`) — incompatible host state surfaced by detection
  that `--yes` cannot resolve (e.g. existing `agent` user has shell
  `/bin/sh`); the bail message names the conflicting attribute and
  suggests `--user=NAME` or manual remediation
- `1` — runtime failure during the Create / Remediate path

For per-scenario walkthroughs (manual useradd, NodeSource already
correct, root-installed Claude Code, broken Playwright), see
[per-scenario walkthroughs](docs/MIGRATION.md).

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

The self-update-without-sudo invariant is permanent: whether you stay on the
curated pin or run `claude update` past it, AgentLinux's release-gate test
verifies the self-update path succeeds with zero `EACCES` and zero `sudo`
prompts.

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
v0.4+ roadmap.

## Security

The installer wraps its body in `main() { ... }; main "$@"` so a truncated
download (connection reset mid-transfer) yields a bash syntax error *before*
any commands run — partial-download execution is not possible. The release
tarball is fetched over HTTPS and verified against a sibling `.sha256` asset
published on the same GitHub Release before extraction. GPG signatures are
on the v0.4+ roadmap — see [`docs/decisions/006-curl-pipe-bash-plus-deb.md`](docs/decisions/006-curl-pipe-bash-plus-deb.md)
for the distribution decision; v0.3.0's trust story is HTTPS + SHA256 +
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
- **Vision:** [docs/VISION.md](docs/VISION.md)
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

AgentLinux is framed around two pillars: **Time-to-productive** (the
assembly the user gets on install — agent user, runtime, permissions,
catalog — without learning to assemble it themselves) and **Stability**
(the curated toolchain holds compatible across upstream churn). See
[docs/VISION.md](docs/VISION.md) for the full framing.
