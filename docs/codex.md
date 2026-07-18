# Codex CLI support

AgentLinux development supports [OpenAI Codex CLI](https://developers.openai.com/codex/cli)
**alongside** Claude Code, not instead of it. Both agents read the same project
context and the same skills; each keeps its own tool-specific wiring. (See
"What changed vs. what didn't" at the end for exactly what was added vs. left
untouched.)

This doc is for contributors who want to drive this repo with Codex. It does not
add Codex to the AgentLinux *catalog* (`agentlinux install codex`) — that is a
separate, future product feature.

## Install

Use the **standalone installer** — it drops an agent-owned, self-updating build
under `~/.codex/` with a launcher in `~/.local/bin` (no sudo):

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
codex --version                  # -> codex-cli <version> (0.144.x as of 2026-07)
```

Prefer this over `npm install -g @openai/codex`. The npm package works for basic
interactive/`exec` use, but the **remote-control daemon** (driving a session from
your phone — see below) requires the standalone build: it self-updates the
app-server from the fixed managed path `~/.codex/packages/standalone/current/`,
which the npm install does not provide. Running both at once also puts two
`codex` binaries on `PATH` — pick one. If you started with npm,
`npm uninstall -g @openai/codex` first, then run the standalone installer.

## Authenticate

```bash
codex login          # ChatGPT sign-in (interactive, opens a browser/device flow)
```

Or set an API key (`OPENAI_API_KEY` / `~/.codex/auth.json`). Run `codex doctor` to
see the current auth mode. Auth is a per-user concern — it is never committed.

**First run in this repo:** Codex prompts you to **trust** the project. Accept it —
otherwise the project-level `.codex/config.toml` (the Stop hooks) and the project
skills under `.codex/skills/` will not load.

## How context is shared (`AGENTS.md` + `CLAUDE.md`)

Codex reads project instructions from **`AGENTS.md`** (git-root → cwd, merged; 32
KiB cap). It does **not** support Claude's `@`-imports. So the shared,
agent-neutral project context lives in the root **`AGENTS.md`**:

- **Codex** reads `AGENTS.md` natively.
- **Claude Code** reads it via `@AGENTS.md` at the top of `CLAUDE.md`, then adds
  its own Claude-specific mechanics below the import.

Keep `AGENTS.md` agent-neutral. Put tool-specific mechanics in each tool's own
file (`CLAUDE.md` for Claude Code; this doc + `.codex/` for Codex).

> Note: a nested `agents/software-engineer/AGENTS.md` also exists — see the note
> in `AGENTS.md` > "Where Things Live" for how Codex scopes it to that subtree.

## Skills

`SKILL.md` is a cross-agent standard, so the project's skills work in Codex
unmodified. Codex discovers project skills from `.codex/skills/`, which contains
symlinks back to the canonical `.claude/skills/*`:

```
.codex/skills/review -> ../../.claude/skills/review
.codex/skills/session-tracker -> ../../.claude/skills/session-tracker
... (one per skill)
```

One source of truth, zero drift. Confirm Codex sees them with
`codex debug prompt-input "hi"` (the skill list appears in the rendered prompt).

## End-of-session reminders (Stop hooks)

Codex has a hooks system matching Claude Code's, including a `Stop` event with the
same `stop_hook_active` one-shot guard and `{"decision":"block","reason":...}`
contract (the `reason` becomes the next message). The two reminders — **run the
review loop** and **keep the Jira ticket in sync** — are wired for Codex in
`.codex/config.toml`, backed by scripts in `.codex/hooks/`:

```toml
[[hooks.Stop]]
[[hooks.Stop.hooks]]
type = "command"
command = 'bash "$(git rev-parse --show-toplevel)/.codex/hooks/review-reminder.sh"'
```

These are **separate** from the Claude Code reminders in `.claude/` on purpose:
the stdin envelope, the reason wording, and the review path each agent can run
differ. We accept the small duplication instead of forcing a shared script.

Project-level config (and its hooks) load once you **trust** the project — Codex
prompts on first run in a new repo. Smoke-test a hook directly:

```bash
echo '{"stop_hook_active":false}' | bash .codex/hooks/review-reminder.sh   # emits the reminder JSON
echo '{"stop_hook_active":true}'  | bash .codex/hooks/review-reminder.sh   # silent (guard)
```

## Review loop under Codex

Codex has no equivalent to the project reviewer subagents in `.claude/agents/`, so
the deep multi-agent review loop stays Claude Code's strength. Under Codex, run
the built-in pass:

```bash
codex review
```

and use the file-type → concern mapping in `AGENTS.md` > "Review Loop" as a
checklist. The review Stop-hook reminder points Codex at exactly this.

## Remote control (drive Codex from your phone)

Codex can be steered from the ChatGPT mobile app while the work runs on this host
(your phone is a control surface, not a second Codex). This is experimental and
**requires the standalone install** (see Install) — the daemon self-updates the
app-server from the managed `~/.codex/packages/standalone/current/` path, which
the npm package does not provide.

```bash
codex remote-control start     # start the app-server daemon (remote control enabled)
codex remote-control pair      # print a short-lived pairing code for your phone
codex remote-control stop      # tear it down
```

Pair the phone from the ChatGPT app; pairing is tied to your ChatGPT account, so
run `codex login` first if you authenticate with an API key. There is no
per-session "always on" flag — keep the daemon running (e.g. a `systemctl --user`
service that runs `codex remote-control start`) to make every session reachable.

## Optional: MCP for session-tracking

The `session-tracker` skill writes to Jira (project AL) through the Atlassian MCP
server. To use it from Codex, register the server in your **user** config
`~/.codex/config.toml`:

```toml
[mcp_servers.atlassian]
url = "https://mcp.atlassian.com/v1/sse"   # or the command form for a local server
```

Then authenticate in-client. Without it, session-tracking degrades gracefully —
Codex just can't reach Jira. (MCP config is per-user; not committed.)

## What changed vs. what didn't

Added: `AGENTS.md`, `.codex/config.toml`, `.codex/hooks/*`, `.codex/skills/*`
(symlinks), this doc. `CLAUDE.md` was slimmed to `@AGENTS.md` + Claude-only
sections. Left untouched: `.claude/agents/`, `.claude/hooks/`,
`.claude/settings.json`, the catalog, and `agents/software-engineer/AGENTS.md`.

## Troubleshooting

- `codex doctor` — diagnoses install, auth, config parse, sandbox.
- `codex debug prompt-input "hi"` — prints the model-visible prompt; confirm
  `AGENTS.md` content and the skill list appear.
- Prefer the standalone install (`codex doctor` shows `install method: standalone`);
  it self-manages updates and is required for remote control. If you instead use
  the npm package and `codex doctor` reports the running package root differs from
  the npm global root, your shell's `npm` prefix disagrees with where `codex` is
  installed — fix `PATH` / `npm config get prefix` so both point at `~/.npm-global`,
  or switch to the standalone installer.
