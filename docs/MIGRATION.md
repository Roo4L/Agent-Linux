# Migrating to AgentLinux on a brownfield host

AgentLinux's `agentlinux install` detects every component it owns
(install user, Node.js, npm global prefix, sudoers drop-in, catalog
agents) before mutating anything and decides per component: **Reuse**,
**Create**, **Remediate**, or **Bail**. The four states are exhaustive
and exclusive; the design philosophy is documented in
[the README's Brownfield install section](../README.md#brownfield-install).

This document walks four representative pre-existing-host scenarios
end to end. Each scenario shows the host state you start from, the
pre-flight report `agentlinux install --dry-run` produces, the
decision tree, the exact non-interactive command, and the resulting
host state. Scenarios are ordered by difficulty (simplest to hardest);
the spec-locked letters (a-d per
[REQUIREMENTS.md DOC-02](../.planning/REQUIREMENTS.md)) are preserved
in section anchors.

> **Note** — every transcript below is illustrative. Pinned version
> strings (`claude-code@2.1.98`, `node v22.x`) may differ from your
> release; what is contractual is the **detection state**
> (`Reuse` / `Create` / `Remediate` / `Bail`), the **flag surface**
> (`--dry-run`, `--yes`, `--user=NAME`), and the **exit codes**
> (`0` / `64` / `65` / `1`).

## Table of contents

1. [Scenario B — NodeSource Node.js already correct](#scenario-b--nodesource-nodejs-already-correct-reuse-happy-path) — REUSE-02 happy path
2. [Scenario A — Manual useradd `agent`](#scenario-a--manual-useradd-agent-reuse-with-warning-if-sudoers-drifted) — REUSE-01 happy path (with REMEDIATE-03 if sudoers drifted)
3. [Scenario C — Claude Code installed under root](#scenario-c--claude-code-installed-under-root-remediate-04-reinstall-under-agent) — REMEDIATE-04 PATH-MISMATCH
4. [Scenario D — Playwright with a broken chromium cache](#scenario-d--playwright-with-a-broken-chromium-cache-remediate-04-reinstall--cache-rebuild) — REMEDIATE-04 broken-status

---

## Scenario B — NodeSource Node.js already correct (Reuse happy path)

**Setup.** Your host already has Node.js 22.x installed via NodeSource
(the same source AgentLinux would use), and the global npm prefix is
writable by whichever user will install agents:

```console
$ apt list --installed 2>/dev/null | grep -E '^nodejs/'
nodejs/jammy,now 22.11.0-1nodesource1 amd64 [installed]
$ id agent
uid=1001(agent) gid=1001(agent) groups=1001(agent)
$ stat -c '%U:%G %a' "$(sudo -u agent -H npm config get prefix)/lib"
agent:agent 0755
```

**Pre-flight report:**

```console
# agentlinux install --dry-run
[DET-01] user=agent shell=/bin/bash writable=true
[DET-02] nodejs=v22.11.0 source=nodesource user_writable=true
[DET-05] sudoers=present sha256=ok

pre-flight resolution:
  user      agent       Reuse  (existing user matches contract)
  nodejs    v22.11.0    Reuse  (REUSE-02 — NodeSource, correct major, writable prefix)
  sudoers   ok          Reuse
  catalog   absent      Create

exit code: 0 (dry-run — no state changed)
```

**Decision tree.** Every detected component is `Reuse`; only catalog
agents need to be installed (`Create`). No remediation flags needed.

**Non-interactive command:**

```bash
agentlinux install
```

**Resulting host state.**

- Pre-existing NodeSource Node.js: preserved, untouched.
- Pre-existing `agent` user: preserved, untouched.
- npm global prefix: preserved at its existing path (writable by agent).
- `/etc/sudoers.d/agentlinux` drop-in: preserved if present, installed
  if absent (additive — no `--yes` needed).
- Catalog agents: installed fresh under the existing agent ownership.

---

## Scenario A — Manual useradd `agent` (Reuse-with-warning if sudoers drifted)

**Setup.** You manually created an `agent` user months ago for an
unrelated tool; the user has the right shell (`/bin/bash`) and a
writable home, but no AgentLinux sudoers drop-in (or one with a
narrower NOPASSWD scope than ADR-012's `agent ALL=(ALL) NOPASSWD: ALL`):

```console
# useradd -m -s /bin/bash agent      # earlier manual setup
# echo 'agent ALL=(ALL) NOPASSWD: /usr/bin/apt-get' > /etc/sudoers.d/local-agent-apt
$ id agent && [ -f /etc/sudoers.d/agentlinux ] || echo "no agentlinux sudoers"
uid=1001(agent) ...
no agentlinux sudoers
```

**Pre-flight report:**

```console
# agentlinux install --dry-run
[DET-01] user=agent shell=/bin/bash writable=true
[DET-05] sudoers=absent (canonical /etc/sudoers.d/agentlinux not present)

pre-flight resolution:
  user      agent     Reuse      (REUSE-01 — existing user matches contract)
  nodejs    absent    Create
  sudoers   absent    Remediate  (REMEDIATE-03 — additive install, no --yes needed)
  catalog   absent    Create

exit code: 0 (dry-run — no state changed)
```

**Decision tree.** The agent user is `Reuse`. The canonical
AgentLinux sudoers drop-in is absent — REMEDIATE-03's additive branch
(missing-file install) does NOT require `--yes` because it never
overwrites pre-existing state. If your host had a DIFFERENT canonical
sudoers file with drifted content, REMEDIATE-03 would be a drift
overwrite and require `--yes`.

**Non-interactive command:**

```bash
agentlinux install                 # additive REMEDIATE-03 only
# — or, if your sudoers drifted (not missing-but-different):
agentlinux install --yes
```

**Resulting host state.**

- Pre-existing manual `agent` user: preserved, untouched.
- `/etc/sudoers.d/agentlinux` drop-in: installed canonically
  (mode `0440`, `agent ALL=(ALL) NOPASSWD: ALL` per ADR-012).
- Pre-existing `local-agent-apt` (or any other sudoers file):
  preserved alongside — AgentLinux owns only its own drop-in.
- Node.js + catalog agents: installed fresh.

---

## Scenario C — Claude Code installed under root (REMEDIATE-04 reinstall under agent)

**Setup.** Your host already has Claude Code installed at
`/usr/local/bin/claude` (root-owned) — installed via
`sudo npm install -g @anthropic-ai/claude-code` or the standalone
installer running as root. This is the canonical bug class AgentLinux
exists to fix: a root-owned `claude` shim shadows the agent-owned
canonical path, so `claude update` hits `EACCES`:

```console
$ which claude
/usr/local/bin/claude
$ stat -c '%U:%G' /usr/local/bin/claude
root:root
$ sudo -u agent -H claude update
npm error code EACCES
npm error syscall mkdir
npm error path /usr/local/lib/node_modules
```

**Pre-flight report:**

```console
# agentlinux install --dry-run
[DET-04] claude-code status=broken path=/usr/local/bin/claude owner=root
          (PATH-MISMATCH — canonical is ~agent/.local/bin/claude)

pre-flight resolution:
  user        agent       Reuse
  nodejs      v22.x       Reuse
  sudoers     ok          Reuse
  claude-code broken      Remediate  (REMEDIATE-04 — reinstall under agent, preserve ~/.claude/)

exit code: 0 (dry-run — no state changed)
```

**Decision tree.** REMEDIATE-04 is a state-overwriting remediation
(it runs the catalog `uninstall.sh` then `install.sh`). In TTY mode
you will be prompted `Proceed with this remediation? [Y/n]`. In
non-interactive mode (cron, CI, `curl | sudo bash`) you must pass
`--yes`; without it the installer bails with exit `65` and a hint
message naming `claude-code` as the component that needs remediation.

**Non-interactive command:**

```bash
agentlinux install --yes
```

**Resulting host state.**

- `/usr/local/bin/claude` (root-owned): removed by the catalog
  `uninstall.sh`.
- `~agent/.local/bin/claude` (agent-owned, canonical path): installed
  via the official Anthropic native installer at the catalog-pinned
  version.
- `~agent/.claude/` user data: **preserved** across uninstall →
  install (catalog `preserve_paths.json` per Phase 14 CAT-04).
- `claude update` from the agent user now succeeds with zero `EACCES`.

---

## Scenario D — Playwright with a broken chromium cache (REMEDIATE-04 reinstall + cache rebuild)

**Setup.** Playwright is installed globally for the agent user
(or a previous broken installer left a partial chromium cache),
but the chromium binary download is corrupted or missing — `playwright
--version` reports the package version but `playwright chromium ...`
fails:

```console
$ sudo -u agent -H playwright --version
Version 1.59.1
$ ls -la ~agent/.cache/ms-playwright/
chromium-1217  (incomplete: missing chrome-linux/chrome binary)
$ sudo -u agent -H playwright chromium --version
browserType.launch: Executable doesn't exist at /home/agent/.cache/ms-playwright/chromium-1217/chrome-linux/chrome
```

**Pre-flight report:**

```console
# agentlinux install --dry-run
[DET-04] playwright-cli status=broken path=/home/agent/.npm-global/bin/playwright-cli
          (health probe failed — chromium cache incomplete)

pre-flight resolution:
  user           agent       Reuse
  nodejs         v22.x       Reuse
  sudoers        ok          Reuse
  playwright-cli broken      Remediate  (REMEDIATE-04 — reinstall + rebuild chromium cache)

exit code: 0 (dry-run — no state changed)
```

**Decision tree.** REMEDIATE-04 again — same contract as Scenario C.
The catalog `uninstall.sh` removes the broken binary and (per the
Phase 14 CAT-04 amendment for playwright-cli) the broken chromium
cache; `install.sh` runs `npm install -g playwright@<pin>` followed
by `npx --yes playwright install --with-deps chromium` which
re-downloads the chromium binary from Playwright's CDN. Needs
`--yes` in non-interactive mode.

**Non-interactive command:**

```bash
agentlinux install --yes
```

**Resulting host state.**

- Broken `~agent/.cache/ms-playwright/chromium-*`: removed by
  catalog `uninstall.sh`.
- Fresh `~agent/.cache/ms-playwright/chromium-<id>`: re-downloaded
  and verified by `npx --yes playwright install --with-deps chromium`.
- `playwright-cli` binary at `~agent/.npm-global/bin/playwright-cli`:
  re-installed at the catalog-pinned version.
- Other catalog agents: unchanged.

---

*Last updated: 2026-05-26 — AgentLinux v0.3.4 close-out.*
