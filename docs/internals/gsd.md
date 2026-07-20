# Open GSD (Get Shit Done)

Open GSD is a multi-runtime workflow framework for planning multi-step
engineering work, executing it phase by phase, and verifying the result.
AgentLinux ships it as an opt-in catalog entry pinned to a tested release.

## The problem

The naive root-global npm install path creates the same root-owned npm tree and
`/usr/local` shim problem as every other privileged global install. Later
agent-owned updates then fail with EACCES or require another privileged
install.

Open GSD also needs a bootstrap step after npm installation. A binary on PATH
is not enough: each coding agent needs its own commands or skills. Skipping
that step produces the misleading result “GSD is installed, but my agent
cannot see it.”

## What AgentLinux does

`agentlinux install gsd` runs the catalog recipe as `agent` and installs
`@opengsd/gsd-core@<pinned>` into `/home/agent/.npm-global/`. The package-native
command is `gsd-core`; AgentLinux creates no compatibility alias and no
`/usr/local/bin` shim. The recipe checks the installed package manifest
against the catalog pin before bootstrapping; it does not invoke the upstream
command's side-effectful default installer as a version probe.

The recipe then runs:

```text
gsd-core --global --claude --opencode --codex --qwen
```

Open GSD owns each runtime's format conversion. AgentLinux verifies the
resulting skill files and command directories: Claude Code skills under
`~/.claude/skills`, OpenCode skills under `~/.config/opencode/skills`, Codex skills under the shared
`~/.agents/skills` root, and Qwen skills under `~/.qwen/skills`. Antigravity CLI
automatic integration is not currently provided by upstream; users should use
Antigravity's documented migration/import flow manually if needed. Uninstall
invokes the same upstream cleanup and removes only GSD-owned files before
uninstalling the npm package.

`agentlinux upgrade` compares installed, curated, and (with
`--check-upstream`) upstream versions. If an operator moves `gsd-core` beyond
the curated pin, AgentLinux reports the divergence instead of silently
overwriting it.

## Worked example

```text
$ agentlinux install gsd
gsd: installing @opengsd/gsd-core@1.7.0
gsd: enabling Open GSD for Claude Code, OpenCode, Codex, and Qwen
gsd: enabled for Claude Code (/home/agent/.claude/skills)
gsd: enabled for OpenCode (/home/agent/.config/opencode)
gsd: enabled for Codex (/home/agent/.agents/skills)
gsd: enabled for Qwen Code (/home/agent/.qwen/skills)

$ sudo -u agent -H npm list -g --depth=0 @opengsd/gsd-core
└── @opengsd/gsd-core@1.7.0
```

## Value vs the naive approach

AgentLinux preserves two user-visible guarantees in one catalog action:

1. **Agent-owned runtime.** The agent owns the npm runtime and can update it
   without EACCES or a root shim.
2. **Cross-runtime discovery.** The pinned, tested Open GSD release is
   discoverable by every supported runtime, including Codex; Antigravity's
   separate import flow is explicitly reported rather than guessed at by the
   recipe.

The curated pin gives the project room to test new upstream releases through
the container and virtual-machine test suites before they reach users.

## Related

- [Agent user](agent-user.md) — owns the per-user npm prefix.
- [Catalog](catalog.md) — stores the `gsd` entry and pin.
- [Registry CLI](registry-cli.md) — drives install, remove, upgrade, and pin.
- [../STABILITY-MODEL.md](../STABILITY-MODEL.md) — curated version states.
