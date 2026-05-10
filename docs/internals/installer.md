# Installer

AgentLinux ships as a curl-pipe-bash installer that downloads a versioned
release tarball, verifies it against a sibling SHA256 sidecar, and executes
the staged plugin. One command on a clean Ubuntu host turns it into an
agent-ready environment — no Ansible, no manual `apt` dance, no per-machine
shell-script drift.

## The problem

Bootstrapping an agent environment on a fresh Ubuntu host is a graveyard of
bespoke shell scripts. Every team has one — copy-pasted between machines,
edited in place, slightly different on every host. They `apt install` a few
packages, then `npm install -g` the agent tooling, and call it done. The
result is a machine where nobody knows what is installed, what version, or
whether the next `claude update` will silently break.

The shell-script-from-the-internet pattern itself has a real security
problem. A naive `curl https://example/script | sudo bash` executes whatever
bytes the server returned today — no verification, no version pinning, no
defence against a tampered mirror. Worse, if the connection drops mid-stream,
bash will execute the partial script it received, which can leave the host
in a half-configured state that is harder to recover from than a clean
failure.

And the typical bootstrap script ends with `sudo npm install -g <tool>`,
which is the exact corruption AgentLinux exists to eliminate: root-owned
files under `/usr/lib/node_modules`, a wrapper at `/usr/local/bin/`, and
a tool that can never self-update again because the agent user can no
longer write to its own install tree.

## What AgentLinux does

The installer is one shell script, fetched once, that does five things in
order: HTTPS-fetch the release tarball from a versioned GitHub Release URL,
fetch the sibling `.sha256` sidecar, verify the tarball against the sidecar
*before* extracting anything, extract into a versioned path under
`/opt/agentlinux/`, and `exec` the staged `agentlinux-install` entrypoint
which runs the ordered provisioner steps (agent user, sudo drop-in, Node.js
runtime, PATH wiring, registry CLI).

The whole script body is wrapped in `main() { ... }; main "$@"` with no
content after the final invocation. This is the canonical mitigation for
partial-download execution: bash parses the entire file before running any
logic, so a truncated download yields a syntax error before any commands
fire. A short read cannot destroy the host.

The version is either pinned explicitly via the `AGENTLINUX_VERSION`
environment variable (regex-validated before any URL interpolation) or
resolved by reading the `Location` header of the GitHub Releases "latest"
permalink. No JSON API call, no rate-limit exposure. The release URL is
HTTPS-only, the tarball's gzip magic bytes are checked before the SHA256
verification, and extraction happens with `--no-same-owner` as a defence
against forged owner metadata. The trust story is explicit: HTTPS plus
SHA256 sidecar plus maintainer 2FA plus branch protection.

## Worked example

```
$ curl -fsSL https://agentlinux.org/install.sh | sudo bash
agentlinux-install: downloading https://github.com/Roo4L/agent-linux/releases/download/v0.3.0/agentlinux-v0.3.0.tar.gz
agentlinux-install: downloading agentlinux-v0.3.0.tar.gz.sha256
agentlinux-install: SHA256 verified for agentlinux-v0.3.0.tar.gz
agentlinux-install: verified and extracted agentlinux-v0.3.0.tar.gz — handing off to agentlinux-install
agentlinux-install: agentlinux-install v0.3.0 starting
agentlinux-install: 10-agent-user: done
agentlinux-install: 20-sudoers: done
agentlinux-install: 30-nodejs: done
agentlinux-install: 40-path-wiring: done
agentlinux-install: agentlinux-install complete

$ agentlinux list
ID            STATUS         PINNED      LATEST
claude-code   not installed  2.1.98      —
gsd           not installed  1.37.1      —
playwright    not installed  1.59.1      —
```

No agents are installed by default — that is a deliberate choice (ADR-003),
not an oversight. Users opt in with `agentlinux install <name>`.

## Value vs the naive approach

Without a versioned, SHA-verified installer, the naive path is
`curl https://example/script | bash`. Two problems:

1. **Tampered or partial downloads execute by default.** A connection reset
   mid-stream feeds a truncated script to bash, which runs whatever
   commands it has parsed so far — half a config edit, the start of a
   `rm -rf` loop, anything. A malicious mirror or a compromised CDN can
   substitute an arbitrary payload silently; without a sibling SHA256
   sidecar verified against a published hash, the user has no signal.
2. **The install is not reproducible.** Re-running the same command a week
   later may pull a newer remote script with different behavior, different
   version pins, or different security posture. There is no way to say
   "install exactly what we ran in CI yesterday" because there is no
   artifact to point at — only a moving URL.

**AgentLinux's installer makes the trust story explicit: HTTPS plus a
SHA256 sidecar verified before extraction plus a `main(){}; main "$@"`
wrapper that defeats partial-download execution plus an env-pinnable
`AGENTLINUX_VERSION` that resolves to a permanent versioned URL.** The
full release pipeline (curl-pipe-bash primary plus optional .deb wrapper)
is recorded as ADR-006.

## Related

- [Agent user](agent-user.md) — the user the installer provisions and the
  ownership invariant every later step preserves.
- [Sudo drop-in](sudo-drop-in.md) — the `/etc/sudoers.d/agentlinux` grant
  one of the provisioner steps installs.
- [Node.js runtime](nodejs-runtime.md) — what the installer's third
  provisioner step puts in place.
- [../README.md](../README.md) — the top-level install + verify story.
