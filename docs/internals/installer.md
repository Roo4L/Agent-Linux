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
which corrupts the install tree in a way the agent can never recover from
on its own. That bug class is the subject of [Agent user](agent-user.md);
the installer's job here is the trust story for getting onto disk safely.

## What AgentLinux does

The installer is one shell script that turns a clean Ubuntu host into an
agent-ready environment in a single command. It downloads a versioned
release tarball from GitHub Releases over HTTPS, verifies it against a
sibling `.sha256` sidecar *before* extracting anything, and hands off to
the staged `agentlinux-install` entrypoint which runs the ordered
provisioner steps: agent user, sudo drop-in, Node.js runtime, PATH wiring,
registry CLI.

After provisioning, on an apply (not a `--dry-run`), the installer runs an
adopt-on-install pass: any agent tool the host already had — a healthy
Claude Code or GSD at its canonical location, within the catalog's
compatibility window — is recorded into a managed sentinel so `agentlinux
list` reflects it as `reused` rather than `not-installed`. This installs
nothing; it only records what the read-only detection pass already found
(see [Registry CLI](registry-cli.md) for the `adopt` verb).

The version is either pinned explicitly via the `AGENTLINUX_VERSION`
environment variable or resolved automatically to the latest GitHub
Release. Either way the resulting URL is a permanent, versioned artifact
— so the same command run a week later installs the same tarball you
ran today, byte for byte. That is the key win over a hand-rolled `curl
| bash`: a reproducible install that pins to a CI-tested combo of
installer, runtime, and catalog, with the SHA256 verified before any
code runs.

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
agentlinux-install: 50-registry-cli: done
agentlinux-install: adopting pre-existing reuse-eligible agents (agentlinux adopt --all)
agentlinux-install: agentlinux-install complete

$ agentlinux list
NAME            STATUS         CURATED   INSTALLED   DESCRIPTION
claude-code     not installed  2.1.98    —           Anthropic's coding agent
gsd             not installed  1.37.1    —           get-shit-done-cc planning workflow CLI
playwright-cli  not installed  0.1.11    —           Browser automation with chromium
```

No agents are installed by default — that is a deliberate choice (see
[the no-default-installs decision record](../decisions/003-no-default-agents-installed.md)),
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
SHA256 sidecar verified before extraction, plus an env-pinnable
`AGENTLINUX_VERSION` that resolves to a permanent versioned URL — so
the install is reproducible a week from now and the bytes are checked
before any code runs.** The full release pipeline — curl-pipe-bash
primary plus optional `.deb` wrapper — is recorded in
[the distribution decision record](../decisions/006-curl-pipe-bash-plus-deb.md).

## Related

- [Agent user](agent-user.md) — the user the installer provisions and the
  ownership invariant every later step preserves.
- [Sudo drop-in](sudo-drop-in.md) — the `/etc/sudoers.d/agentlinux` grant
  one of the provisioner steps installs.
- [Node.js runtime](nodejs-runtime.md) — what the installer's third
  provisioner step puts in place.
- [../README.md](../README.md) — the top-level install + verify story.
