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

Codex uses the same agent-neutral `$review` skill as Claude Code. The skill's
file-type → reviewer-role mapping and triage rules are the source of truth.

Codex runs the reviewers through its native **multi-agent** feature
(`multi_agent`, enabled by default — confirm with
`codex features list | grep multi_agent`). The model calls the `spawn_agent`
tool once per matched role, with `agent_type` set to the role name, and runs
independent roles as parallel spawns. Do **not** invoke the Claude CLI, and do
**not** substitute the built-in `codex review` command for the project skill —
`codex review` is a single-pass diff review, not the multi-role read-only loop
the skill defines.

### Reviewer roles as Codex subagents (`.codex/agents/`)

Codex discovers the `agent_type` values `spawn_agent` can target from
**`.codex/agents/*.toml`** (merged with your user-level `~/.codex/agents/`), so
the reviewer roles are projected there:

```bash
scripts/sync-codex-agents.sh          # regenerate .codex/agents/*.toml
scripts/sync-codex-agents.sh --check  # CI gate: fail if out of sync
```

The generator reads each canonical `.claude/agents/<role>.md` (YAML frontmatter
+ prompt body) and writes `.codex/agents/<role>.toml` with `name`,
`description`, `developer_instructions` (the prompt body), and
`sandbox_mode = "read-only"` — which is what enforces the skill's read-only
reviewer contract on the spawned agent. `.claude/agents/` stays the single
source of truth; the `.codex/agents/` TOMLs are a committed build product, kept
honest by the `--check` gate (wired into `.pre-commit-config.yaml` and the
`tests/harness/50-agents-and-skills.bats` HRN-07 tests). After editing a role
prompt, rerun the generator and commit both.

> Schema note: this repo targets the `spawn_agent` schema that carries an
> `agent_type` field. If a future/older Codex build exposes only the generic
> form (`message`/`items`/`fork_context`, no `agent_type`), fall back to reading
> `.claude/agents/R.md` and injecting it as a role preamble into
> `spawn_agent(message=…)`. Inspect the live tool schema (via `tool_search` or
> the tool list) before dispatching.

The review Stop-hook reminder (`.codex/hooks/review-reminder.sh`) points Codex
at the shared skill.

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

Codex-specific wiring includes `AGENTS.md`, `.codex/config.toml`,
`.codex/hooks/*`, `.codex/skills/*` (symlinks), `.codex/agents/*.toml` (the
reviewer-role projection, generated by `scripts/sync-codex-agents.sh`), and this
adapter document. The shared reviewer roles under `.claude/agents/` and the
shared `$review` skill remain the repository contract. Claude-only settings
remain host-local.

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
