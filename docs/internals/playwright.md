# Playwright

Playwright is the browser-automation surface coding agents use to read web
pages, fill forms, and inspect network traffic. AgentLinux ships
Microsoft's official agent-oriented Playwright CLI (`@playwright/cli`) as
an opt-in catalog entry — `agentlinux install playwright-cli` installs the
CLI binary into the agent's per-user npm prefix and then bootstraps the
bundled Claude Code skill so the agent actually has slash-commands for
browser work, not just a binary on PATH. The agent user's NOPASSWD sudo
drop-in is what lets the bootstrapper's apt-layer browser-deps install
run mid-task without stalling on a password prompt.

## The problem

Installing Playwright on a fresh Ubuntu host has three failure modes a
naive path hits in sequence.

The first is the same ownership trap every npm-global install hits. A
naive `sudo npm install -g @playwright/cli` lands the install tree under
root ownership, breaks every subsequent operation under `~/.npm/`, and
poisons the agent's ability to self-update its own tooling — the bug
class AgentLinux exists to eliminate (see [Agent user](agent-user.md)).

The second is the apt-deps step. Playwright's browser binaries (chromium,
firefox, webkit) need a substantial set of OS-level libraries — libnss3,
libatk-bridge2.0-0, libxkbcommon0, and ~200 MB more — that only apt can
install. Playwright's installer auto-prepends `sudo` to that apt step, so
without a sudoers drop-in the install stalls indefinitely on a
`[sudo] password for agent:` prompt that a non-interactive session never
satisfies. Long-running coding-agent loops that hit this prompt do not
recover; they wait for stdin that never arrives.

The third is intent. Even with the CLI binary on PATH, Claude Code does
not see any `/playwright-cli` slash commands until the bundled skill is
copied into `~/.claude/skills/`. Operators who installed `@playwright/cli`
without running its `--skills` bootstrapper reported "I installed
Playwright and the agent can't find it" — technically correct,
intent-wise wrong, and identical in shape to the GSD skill-set issue.

## What AgentLinux does

`agentlinux install playwright-cli` runs the catalog recipe via the
agent user. The recipe runs `npm install -g @playwright/cli@<pinned>`
into the agent's per-user prefix at `~/.npm-global/`, so the
`playwright-cli` binary lands agent-owned at
`/home/agent/.npm-global/bin/playwright-cli`. A pre-skills version-lock
asserts `playwright-cli --version` matches the pin, so a mispin or
channel drift fails before any heavier work runs.

The recipe then invokes `playwright-cli install --skills` from the
agent's home directory. That bootstrapper copies the bundled Claude Code
skill into `~/.claude/skills/playwright-cli/` — which is what makes the
agent's `/playwright-cli` slash commands surface inside Claude Code.
Apt-layer browser deps that the bootstrapper's underlying Playwright
runtime needs install via the upstream sudo-prepended path; the agent
user's NOPASSWD sudo drop-in (`/etc/sudoers.d/agentlinux`,
[ADR-012](../decisions/012-agent-user-full-sudo.md)) is what makes that
step run cleanly without prompting. After install, a sanity check asserts
the skill directory landed where Claude Code looks for it; a missing
directory fails the install rather than silently writing a sentinel for
a half-bootstrapped state.

## Worked example

```
$ agentlinux install playwright-cli
playwright-cli: installing @playwright/cli@0.1.11
playwright-cli: CLI at /home/agent/.npm-global/bin/playwright-cli, version 0.1.11
playwright-cli: wiring Claude Code skill via 'playwright-cli install --skills'
... apt-installing browser deps via the host's sudoers drop-in ...
playwright-cli: install complete (binary at /home/agent/.npm-global/bin/playwright-cli;
     skill wired into /home/agent/.claude/skills/playwright-cli)

$ sudo -u agent playwright-cli --version
0.1.11
```

No `[sudo] password for agent:` prompt. No EACCES. No half-installed
state. The agent ends up with a binary it owns, a skill set Claude Code
can find, and browser deps the apt layer installed cleanly under the
NOPASSWD drop-in.

## Value vs the naive approach

Without AgentLinux, the naive path is `sudo npm install -g
@playwright/cli && sudo playwright-cli install --skills`. Two problems:

1. **The npm install ends up root-owned.** Same self-update breakage
   the other catalog agents hit — see [Agent user](agent-user.md) for
   the bug class. Routing the install through `as_user agent` is what
   keeps the per-user prefix invariant intact for Playwright too.
2. **The browser-deps step needs sudo, which stalls non-interactive
   sessions.** Playwright's installer auto-prepends `sudo` to the
   apt-deps install. A long-running agent that hits a `[sudo]
   password for agent:` prompt mid-install is a stalled agent — the
   prompt never resolves, the loop never recovers. The NOPASSWD sudo
   drop-in (see [Sudo drop-in](sudo-drop-in.md)) is what makes the
   apt step run cleanly under automation, and the install includes the
   `--skills` bootstrap so the agent actually has slash commands for
   browser work, not just a binary on PATH.

**AgentLinux ships the full Playwright install — npm package, agent
skill wiring, and the OS-level browser deps the apt layer needs — as
one opt-in catalog entry that works the first time, every time, even
under a non-interactive coding-agent loop.**

## Related

- [Agent user](agent-user.md) — the user that owns the per-user npm
  prefix this install lands in.
- [Sudo drop-in](sudo-drop-in.md) — the `/etc/sudoers.d/agentlinux`
  NOPASSWD grant that lets the apt-deps step run without a password
  prompt.
- [Catalog](catalog.md) — where the `playwright-cli` entry's
  `pinned_version` lives.
- [Registry CLI](registry-cli.md) — the `agentlinux` command that
  drives install / upgrade / pin against the catalog.
