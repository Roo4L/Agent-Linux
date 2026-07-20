# Playwright

Playwright is the browser-automation tool coding agents use to read web
pages, fill forms, and inspect network traffic. AgentLinux ships Microsoft's
official agent-oriented `@playwright/cli` as an opt-in catalog entry.

## The problem

Installing the npm package is only the first third of the job. A root-global
install creates the ownership problem AgentLinux exists to remove. A bare CLI
install also does not copy the bundled Claude Code instructions, so the agent cannot
discover its commands. Finally, a downloaded browser can still fail at launch
when shared libraries such as `libnss`, `libglib`, or `libgbm` are missing.

## What AgentLinux does

`agentlinux install playwright-cli` installs `@playwright/cli@<pinned>` as the
agent user into `/home/agent/.npm-global/`, runs `playwright-cli install
--skills` from the agent's writable home, and ensures the branded Chrome
executable required by the CLI at `/opt/google/chrome/chrome`. It then uses the
shared browser-prerequisite helper to install the launch libraries:

- Debian/Ubuntu uses `apt-get`, including the adaptive `libasound2t64` versus
  `libasound2` package name.
- RHEL-family systems use an explicit `dnf` package list because Playwright's
  own dependency installer does not provide a reliable RHEL path.

Only the OS package operations use root, and they use `sudo -n`. If the agent
user lacks non-interactive package permission, the recipe reports the exact
administrator action needed and stops. npm and browser-cache writes remain
agent-owned.

The pinned CLI currently reports action-resolution failures in a structured
`### Error` block but exits zero; JSON mode reports `{ "isError": true }` with
the same defect. AgentLinux installs a prefix-local status adapter beside the
npm bin entry; it delegates all commands and changes status only for those exact
error forms. It does not use a system-wide shim or scan arbitrary page text, and
it does not impose a fixed output-size cap.

The recipe finishes with a real `playwright-cli open about:blank` launch probe,
then closes that session. This catches missing shared libraries that a version
check cannot detect. The bundled instructions are mirrored into
`~/.agents/skills/` for Codex/OpenCode discovery. Antigravity supports
workspace-local `.agents/skills/`, but AgentLinux does not choose a workspace
to populate; users who want a workspace-specific copy should place it there.
Qwen has no equivalent multi-file discovery path for these browser
instructions.

## Worked example

```text
$ agentlinux install playwright-cli
playwright-cli: installing @playwright/cli@0.1.17
playwright-cli: CLI at /home/agent/.npm-global/bin/playwright-cli, version 0.1.17
... installing browser libraries via sudo -n ...
playwright-cli: install complete (browser launch probe passed)

$ sudo -u agent -H bash --login -c 'playwright-cli open about:blank'
### Page
- Page URL: about:blank
```

## Value vs the naive approach

The catalog entry makes “install Playwright” mean:

1. **An agent-owned CLI.** The package and browser cache belong to the agent.
2. **Discoverable instructions.** Compatible agents can find the bundled
   browser commands.
3. **A usable browser runtime.** The recipe installs or verifies the required
   browser and shared libraries.
4. **Actionable failures.** The status wrapper reports known browser-action
   errors without hiding unrelated output.

The launch probe and distro dispatch close the gap between “the package is on
PATH” and “the agent can actually open a page.”

## Related

- [Agent user](agent-user.md) — owns npm and browser-cache files.
- [Sudo drop-in](sudo-drop-in.md) — permits non-interactive OS package setup.
- [Catalog](catalog.md) — stores the `playwright-cli` pin.
- [Registry CLI](registry-cli.md) — drives install and removal.
