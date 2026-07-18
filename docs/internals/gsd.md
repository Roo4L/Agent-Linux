# GSD (Get Shit Done)

GSD is a Claude Code workflow framework — slash commands and skills for
planning multi-step engineering work, executing it phase by phase, and
verifying the result. AgentLinux ships it as an opt-in catalog entry
pinned to a version the project's CI matrix has exercised, so an upstream
GSD regression does not immediately reach users.

## The problem

GSD has two intertwined installation problems on a fresh Ubuntu host.

The first is the same ownership trap every npm-installed agent hits. The
naive `sudo npm install -g get-shit-done-cc` lands a root-owned tree
under `/usr/lib/node_modules`, leaves a wrapper at `/usr/local/bin/`,
and turns every later `npm update` or in-tool self-update into an
EACCES-then-`sudo` cycle. Once root has touched the global tree the
agent user can no longer install or update without climbing the
privilege ladder again — see [Agent user](agent-user.md) for the full
bug class.

The second is upstream cadence. GSD ships fast — multiple releases per
week are normal, and the project has hit upstream regressions in
production: a bug present in `latest` for several days before a fix
shipped. A thin-wrapper distribution that always pulls `latest` exposes
every user to every wobble in the upstream release cadence the moment
it publishes, with no safety net between the broken version and the
operator's machine.

GSD also expects a follow-on bootstrap step that no thin wrapper can
discover automatically: after the npm install, the binary is on PATH but
no coding agent yet sees any `/gsd-*` slash commands or skills.
GSD's bootstrapper has to be invoked once to copy its skill set into
each agent's own config directory. Operators who skipped that step on
the first GSD release reported "I installed it and my agent doesn't see
it" — technically correct, intent-wise wrong.

GSD's bootstrapper is multi-runtime — the same install can light up
Claude Code, opencode, Gemini CLI, Codex, and Qwen Code, each in that
tool's own command/skill format. So "install GSD" should mean GSD shows
up in *every* coding agent the machine has, not just one.

## What AgentLinux does

`agentlinux install gsd` runs the catalog recipe via the agent user.
The recipe runs `npm install -g get-shit-done-cc@<pinned>` into the
agent's per-user prefix at `~/.npm-global/`, so the binary
(`get-shit-done-cc`, the npm-published name — there is no symlink
shortening it to `gsd`) lands at
`/home/agent/.npm-global/bin/get-shit-done-cc`, agent-owned.

The pinned version comes from the catalog entry's `pinned_version`
field — the version AgentLinux's release-gate exercised against the
full Docker + QEMU matrix before the tag shipped. After the install,
the recipe asserts the help banner contains `v<pinned>` so a mispin or
upstream-channel drift fails the install rather than silently writing
a sentinel for the wrong version. The recipe then runs the GSD
bootstrapper for every coding agent AgentLinux ships
(`get-shit-done-cc --global --claude --opencode --gemini --codex
--qwen`), which copies the skill set into each agent's own config
directory — Claude Code, Codex, and Qwen Code under a `skills/` tree,
opencode under a `command/` directory, Gemini CLI under a namespaced
`commands/` directory — and asserts the GSD surface actually landed for
each one. GSD owns the per-tool format conversion; AgentLinux just
invokes it and verifies the result, so the user's intent ("install
GSD") is satisfied across the whole agent fleet, not just in the
binary-on-PATH technical sense. The wiring is written unconditionally,
so a coding agent installed *after* GSD still finds the skill set
already present.

`agentlinux upgrade` later compares installed, curated, and (with
`--check-upstream`) upstream-latest, and surfaces the three divergence
states (`synced`, `override-ahead`, `override-behind`) per
[STABILITY-MODEL.md](../STABILITY-MODEL.md). When the operator runs
`get-shit-done-cc` past the curated pin (or `npm install -g
get-shit-done-cc` themselves), AgentLinux notices and asks rather than
silently overwriting.

## Worked example

```
$ agentlinux install gsd
gsd: installing get-shit-done-cc@1.37.1
gsd: wiring GSD skill set into all shipped agents via get-shit-done-cc --global --claude --opencode --gemini --codex --qwen
gsd: wired into Claude Code (/home/agent/.claude/skills)
gsd: wired into opencode (/home/agent/.config/opencode/command)
gsd: wired into gemini-cli (/home/agent/.gemini/commands)
gsd: wired into codex (/home/agent/.codex/skills)
gsd: wired into qwen-code (/home/agent/.qwen/skills)
gsd: install complete (resolves at /home/agent/.npm-global/bin/get-shit-done-cc;
     banner matches pin; skill set wired into Claude Code + opencode + gemini-cli + codex + qwen-code)

$ sudo -u agent get-shit-done-cc --help | head -1
Get Shit Done v1.37.1

$ agentlinux upgrade
  gsd  installed=1.37.1  curated=1.37.1  state=synced
```

## Value vs the naive approach

Without AgentLinux, the naive path is `sudo npm install -g
get-shit-done-cc`. Two problems:

1. **The agent's own workflow tools end up root-owned.** GSD lives in
   the same EACCES + recursive-shim story as Claude Code: once the
   install tree is root-owned, no later operation under `~/.npm/` can
   succeed without `sudo`, and every operator-side `sudo` corrupts
   another layer. See [Agent user](agent-user.md) for the full bug
   class — GSD is just one more victim of the naive global-install
   path.
2. **Upstream regressions hit immediately.** GSD ships fast, and
   broken releases occasionally land in `latest`. A thin-wrapper
   AgentLinux that always pulls `latest` would expose every user to
   every upstream regression the moment it publishes. AgentLinux's
   curated pin gives the project the freedom to test upstream movement
   on the full Docker + QEMU matrix before it reaches users.

**Pinning is the explicit contract — AgentLinux tests what it ships,
and the operator opts past the pin when they are ready.** The
escape hatches (`agentlinux pin gsd=latest` for sticky-follow-upstream,
`agentlinux pin gsd=<semver>` to bisect a regression) are first-class;
the silent-drift path is the one that does not exist.

## Related

- [Agent user](agent-user.md) — the user that owns the per-user npm
  prefix this install lands in.
- [Catalog](catalog.md) — where the `gsd` entry's `pinned_version`
  lives.
- [Registry CLI](registry-cli.md) — the `agentlinux` command that
  drives install / upgrade / pin against the catalog.
- [../STABILITY-MODEL.md](../STABILITY-MODEL.md) — curated combos and
  the three divergence states.
