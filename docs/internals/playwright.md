# Playwright

Playwright is the browser-automation surface coding agents use to read web
pages, fill forms, and inspect network traffic. AgentLinux ships
Microsoft's official agent-oriented Playwright CLI (`@playwright/cli`) as
an opt-in catalog entry. `agentlinux install playwright-cli` does the whole
job an agent actually needs: it installs the CLI binary into the agent's
per-user npm prefix, bootstraps the bundled Claude Code skill so the agent
has slash-commands for browser work, downloads the Chromium build the CLI
drives, and installs the OS-level libraries that Chromium needs to launch.

## The problem

Getting Playwright to the point where an agent can actually drive a browser
on a fresh host hits three failure modes a naive path runs into in sequence.

The first is the same ownership trap every npm-global install hits. A
naive `sudo npm install -g @playwright/cli` lands the install tree under
root ownership, breaks every subsequent operation under `~/.npm/`, and
poisons the agent's ability to self-update its own tooling — the bug
class AgentLinux exists to eliminate (see [Agent user](agent-user.md)).

The second is intent. Even with the CLI binary on PATH, Claude Code does
not see any `/playwright-cli` slash commands until the bundled skill is
copied into `~/.claude/skills/`. Operators who installed `@playwright/cli`
without running its `install --skills` bootstrapper reported "I installed
Playwright and the agent can't find it" — technically correct, intent-wise
wrong: installing the binary is not the same as the agent being able to
invoke it.

The third is that the downloaded browser cannot launch. `playwright-cli
install --skills` fetches a Chromium build (~175 MB) into
`~/.cache/ms-playwright/`, but not the roughly twenty shared libraries that
build needs to run — libnss3, libgbm1, libxkbcommon, the libX* set, and
more. Without them the binary sits on disk and `playwright-cli --version`
happily reports its version, but the first real browser command dies with
`error while loading shared libraries: libnspr4.so: cannot open shared
object file`. Two things make this sharper on AlmaLinux 9. Playwright
publishes no native AlmaLinux build, so it prints `BEWARE: your OS is not
officially supported by Playwright; downloading fallback build for
ubuntu24.04-x64` and uses the Ubuntu binary (which runs fine once its
libraries are present). And Playwright's own dependency installer,
`playwright install-deps`, only knows Debian/Ubuntu `apt` package names —
it has no `dnf` path and exits non-zero on AlmaLinux 9.

## What AgentLinux does

`agentlinux install playwright-cli` runs the catalog recipe as the agent
user. It runs `npm install -g @playwright/cli@<pinned>` into the agent's
per-user prefix at `~/.npm-global/`, so the `playwright-cli` binary lands
agent-owned at `/home/agent/.npm-global/bin/playwright-cli`. A pre-skills
version-lock asserts `playwright-cli --version` matches the pin, so a
mispin or channel drift fails before any heavier work runs.

The recipe then invokes `playwright-cli install --skills` from the agent's
home directory. That bootstrapper copies the bundled Claude Code skill into
`~/.claude/skills/playwright-cli/` — which is what surfaces the agent's
`/playwright-cli` slash commands inside Claude Code — and downloads the
Chromium build the CLI drives. A sanity check then asserts the skill
directory landed where Claude Code looks for it; a missing directory fails
the install rather than silently writing a sentinel for a half-bootstrapped
state.

Finally the recipe installs Chromium's launch dependencies, dispatched on
distro family because the two families need different package managers and
different package names:

- On **Debian/Ubuntu** it invokes Playwright's own `install-deps` (shipped
  bundled inside `@playwright/cli`'s dependency tree). Using Playwright's
  installer rather than a hardcoded `apt` list keeps the recipe correct
  across 22.04 / 24.04 / 26.04, including the 24.04 `t64` ABI package-name
  transition.
- On **AlmaLinux 9**, where Playwright's `install-deps` is a dead end, the
  recipe installs an explicit, on-box-verified `dnf` list — `nss`, `nspr`,
  `at-spi2-atk`, `mesa-libgbm`, `libxkbcommon`, the `libX*` set, and the
  rest of the closure (twenty packages).

Both arms install system packages under `sudo`. The agent user's NOPASSWD
sudo drop-in (`/etc/sudoers.d/agentlinux` — see
[the agent-user-full-sudo decision record](../decisions/012-agent-user-full-sudo.md))
is what lets that step run mid-install without stalling a long-running,
non-interactive agent loop on a `[sudo] password for agent:` prompt it can
never answer.

Playwright's own bootstrapper only knows about Claude Code, but the
skill it drops is portable, so AgentLinux mirrors it into the cross-tool
`~/.agents/skills/` directory that both Codex and opencode scan for
user-level skills (opencode also reads `~/.claude/skills/` directly).
That one extra copy is what surfaces Playwright inside Codex and
opencode too, not just Claude Code. Gemini CLI and Qwen Code have no
comparable skill host — only prompt-style commands — so Playwright is
not wired into them. The mirror is a derived copy, refreshed on every
(re)install and removed on uninstall.

## Worked example

```
$ agentlinux install playwright-cli
playwright-cli: installing @playwright/cli@0.1.11
playwright-cli: CLI at /home/agent/.npm-global/bin/playwright-cli, version 0.1.11
playwright-cli: wiring Claude Code skill via 'playwright-cli install --skills'
... apt-installing browser deps via the host's sudoers drop-in ...
playwright-cli: mirrored skill into /home/agent/.agents/skills/playwright-cli (codex/opencode ~/.agents/skills scan)
playwright-cli: install complete (binary at /home/agent/.npm-global/bin/playwright-cli;
     skill wired into /home/agent/.claude/skills/playwright-cli + /home/agent/.agents/skills)

$ sudo -u agent -H bash --login -c 'playwright-cli open about:blank'
### Page
- Page URL: about:blank
```

No password prompt, no permission-denied (EACCES) error, no half-installed
state. The agent ends up with a binary it owns, a skill set Claude Code can
find, the Chromium build the CLI drives, and the system libraries that let
that Chromium actually launch — on Ubuntu and AlmaLinux 9 alike.

## Value vs the naive approach

Without AgentLinux, the naive path is `sudo npm install -g @playwright/cli
&& playwright-cli install --skills` — and then a confusing `error while
loading shared libraries` the first time the agent opens a page. Three
problems map onto the three failure modes above:

1. **The npm install ends up root-owned.** Same self-update breakage the
   other catalog agents hit — see [Agent user](agent-user.md) for the bug
   class. Routing the install as the agent user keeps the per-user prefix
   invariant intact for Playwright too.
2. **The binary on PATH has no slash commands.** Without the `--skills`
   bootstrap, Claude Code sees the binary but none of the `/playwright-cli`
   commands, so the agent can't actually use it.
3. **The browser downloads but cannot launch.** `install --skills` fetches
   the Chromium binary but not its ~20 system libraries, so a `--version`
   check passes while the first real browser command crashes. AgentLinux
   installs the launch closure as part of the recipe, the right way per
   family — Playwright's own `install-deps` on Ubuntu, an explicit verified
   `dnf` list on AlmaLinux 9. Both run under the NOPASSWD sudo drop-in (see
   [Sudo drop-in](sudo-drop-in.md)) so the system-package step never stalls.

**AgentLinux ships the full Playwright install — npm package, agent skill
wiring, the Chromium build, and the OS-level libraries that build needs to
launch — as one opt-in catalog entry that works the first time, on both
Ubuntu and AlmaLinux 9, even under a non-interactive coding-agent loop.**

## Related

- [Agent user](agent-user.md) — the user that owns the per-user npm
  prefix this install lands in.
- [Sudo drop-in](sudo-drop-in.md) — the `/etc/sudoers.d/agentlinux`
  NOPASSWD grant that lets the browser-deps step run without a password
  prompt.
- [Catalog](catalog.md) — where the `playwright-cli` entry's
  `pinned_version` lives.
- [Registry CLI](registry-cli.md) — the `agentlinux` command that
  drives install / upgrade / pin against the catalog.
