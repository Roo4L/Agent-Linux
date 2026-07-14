# Catalog

The catalog is the JSON-Schema-validated registry of agents AgentLinux
can install. It ships a growing, curated set of opt-in entries —
coding-agent CLIs and developer tooling — with zero installed by
default; the live roster is `plugin/catalog/catalog.json`. New agents
are added by submitting a catalog entry plus an install recipe — no CLI
source changes required.

## The problem

There are two naive alternatives to a schema-validated catalog, and
both fail the project's "fresh contributor adds an agent in one PR"
test.

The first is hardcoding the agent set into CLI source. This is the
shape AgentLinux briefly considered before the v0.2.0 → v0.3.0 pivot:
every supported agent's install logic lives as a TypeScript module
that the CLI dispatches by name. Adding a new agent then requires
editing TypeScript, running the test suite, and cutting a CLI release.
The friction kills contribution velocity, and worse, it conflates two
concerns — "what does the CLI do" and "what does AgentLinux know how
to install" — that ought to evolve at different speeds.

The second is "no machine-readable contract at all" — every install
command lives only in someone's README, drifts immediately, and
cannot be programmatically validated. There is no field a CLI could
read to know an agent's pinned version, no way to assert that every
agent has a symmetric uninstall path, no way to enforce that recipe
filenames look like `*.sh`. Bugs that schema validation would catch in
milliseconds (a typo in `pinned_version`, a missing
`uninstall_recipe_path`, a recipe that points at a file that does not
exist) ship to users instead.

Both naive paths also fail the version-pinning story
([STABILITY-MODEL.md](../STABILITY-MODEL.md)). Without a per-entry
`pinned_version` that is part of the release artifact, "AgentLinux
ships curated combos" reduces to "AgentLinux ships whatever npm
serves today" — and the project's product-level answer to "why use
AgentLinux instead of `npm install -g`?" collapses.

## What AgentLinux does

The catalog is three pieces working together.

The first is `plugin/catalog/schema.json` — a JSON Schema 2020-12
contract with `additionalProperties: false`, so unknown fields are
a hard fail rather than silently ignored. The schema declares the
required fields per entry (`id`, `display_name`, `description`,
`source_kind`, `pinned_version`, `install_recipe_path`,
`uninstall_recipe_path`) and conditional rules (`source_kind: "npm"`
implies `npm_package_name` is required). `pinned_version` is regex-bound
to exact semver (no ranges, no partials), `id` is regex-bound to
`[a-z][a-z0-9-]*`. The schema is the machine-readable spec the
catalog auditor and the install path both read from.

The second is `plugin/catalog/catalog.json` — the embedded agent list
shipped in every release tarball. It holds the real entries (the
originals claude-code, gsd, playwright-cli; the coding-agent CLIs
codex, gemini-cli, opencode, qwen-code, and ccusage; the
prebuilt-binary tools rtk, gh, glab, trivy, and gitleaks; the
npm-distributed Sentry CLI; the MCP servers chrome-devtools-mcp,
context7, and the hosted github-mcp, sentry-mcp, firecrawl-mcp,
slack-mcp, linear-mcp, and jira-atlassian-mcp; the uv-bootstrapped
GitHub Spec Kit CLI spec-kit; and the per-user assistant daemon
openclaw) plus one `test_only` fixture exercised only by
bats. Pre-commit and CI both run the catalog
through ajv; a malformed entry never reaches `master`, let alone a
release.

The third is per-agent recipes under
`plugin/catalog/agents/<id>/install.sh` and `uninstall.sh`. The
recipes are plain bash. Each recipe receives
`AGENTLINUX_PINNED_VERSION` in its environment (with a `:?` fail-fast
guard at the top), runs as the agent user, and asserts a post-install
invariant (binary on PATH, version banner matches pin, skill directory
exists where the agent looks for it). Adding an agent requires a
catalog entry plus a recipe pair — no TypeScript edits anywhere.

Three invariants govern the catalog:

- Agents are *available*, not installed by default — `agentlinux list`
  on a fresh host shows every entry with `STATUS: not installed`. The
  rationale is recorded in [the no-default-installs decision record](../decisions/003-no-default-agents-installed.md).
- The catalog is schema-validated at pre-commit and CI time — our
  catalog reviewer runs `ajv` against `schema.json` and refuses to ship
  malformed entries.
- Adding a new agent is a one-PR change against the catalog — no CLI
  source edit, no release tag. The schema is the contract; the
  recipe is the implementation.

Every release pins each catalog entry to a version AgentLinux's CI
matrix (Docker × Ubuntu 22.04 / 24.04 / 26.04 plus QEMU on the same
versions) exercised end-to-end before tag — the curated combo
([STABILITY-MODEL.md](../STABILITY-MODEL.md)). The catalog snapshot
is staged on disk at `/opt/agentlinux/catalog/<version>/catalog.json`
and is the source of truth `agentlinux install` reads.

That curated pin only stays meaningful if the tool does not quietly
update itself. Several modern coding agents auto-install a newer
version in the background the next time they start — the same
self-update reflex that, with a badly-owned install, produces the
permission breakage AgentLinux exists to prevent. So recipes for those
tools turn the background auto-update off (via each tool's own config)
at install time, leaving the curated pin authoritative and routing all
version changes through `agentlinux upgrade`. The explicit, operator-run
update path is untouched — only the silent one is frozen.

## Source kinds: npm, script, prebuilt binary, and MCP server

Not every tool ships on npm. Some of the most useful developer CLIs are
distributed only as a compiled, per-architecture binary attached to a
GitHub release; others are not installed at all but *registered* — MCP
servers a coding agent talks to. The catalog's `source_kind` field names
how an entry is installed, and it now understands four values:

- `npm` — install the pinned package into the agent-owned npm prefix.
- `script` — run the recipe's own install logic. This covers a tool
  that ships its own installer (how Claude Code installs), one that
  needs a small bootstrap first (Spec Kit's recipe bootstraps a per-user
  `uv` and then installs a git-pinned Python CLI — see "The uv bootstrap"
  below), and one that installs a background service (OpenClaw sets up a
  per-user daemon — see "Per-user daemons" below).
- `binary` — fetch a pinned release artifact, verify its checksum, and
  drop the binary into the agent's own `~/.local/bin`.
- `mcp` — register a Model Context Protocol server into the coding
  agent's own config, so the agent can call its tools.

The prebuilt-binary kind is the one that needs the most care, because
"download a binary from the internet and run it" is exactly where a
supply-chain mistake does the most damage. AgentLinux installs a binary
the same disciplined way its own curl-installer verifies a release: the
asset is staged to a scratch directory, its gzip magic bytes are
checked, and its SHA-256 is verified against the release's published
`checksums.txt`
**before anything is extracted**, and any mismatch aborts the install
without unpacking or replacing a single file.

The mechanics live in one shared helper,
`plugin/catalog/lib/prebuilt-binary.sh`, that every binary recipe
sources. The helper owns the security-critical, tool-agnostic core:
the architecture dispatch (x86-64 or ARM64, abort otherwise), the
verify-before-extract download, the single-member extract, and the
version-lock assertion. It installs the binary `0755` into
`~/.local/bin` — agent-owned, no root, and deliberately no
`/usr/local/bin` shim (the shim is the anti-pattern that breaks a
tool's own self-update). The recipe owns only what genuinely differs
per upstream: which host serves the release, how the per-architecture
asset and checksum files are named, and where the binary sits inside
the archive. So adding the next binary-distributed tool is a catalog
entry plus a thin recipe, with no shared code to touch.

That split earns its keep across a mix of real upstreams. `rtk` (the
Rust Token Killer, a token-optimizing CLI proxy) names its assets with
Rust target triples and ships the binary flat. The GitHub CLI (`gh`)
uses Go-style `os_arch` names, a per-version checksums file, and nests
its binary under an architecture-named directory. `trivy` and
`gitleaks` (a vulnerability scanner and a secret scanner — both run
their scans with no Docker daemon) each spell the architecture their
own way. And the GitLab CLI (`glab`) is served from `gitlab.com`
rather than `github.com` entirely — which is why the recipe, not the
helper, supplies the release base URL. Every one of them is a handful
of lines over the same helper.

`rtk`'s optional Claude Code hook is strictly opt-in — installing `rtk`
never writes to `~/.claude` on its own; a user runs `rtk init`
themselves if they want it, and `agentlinux remove rtk` reverts that
hook along with the binary and rtk's own config and cache. The other
binary tools remove just as symmetrically: `remove trivy` clears the
binary and `~/.cache/trivy`, `remove gitleaks` (stateless) just the
binary. The authenticated ones — `gh` and `glab` — delete the binary
but *preserve* their auth config (`~/.config/gh`, `~/.config/glab`) on
remove, the same way every other authenticated agent keeps its
credentials; only a full agent-home purge wipes them.

## The uv bootstrap: Python tools without a system Python

AgentLinux provisions a Node.js runtime, not Python — but some of the
best agent tooling is written in Python. GitHub Spec Kit is the first
such tool, and it exposed a general need: install a pinned Python CLI
per-user, with no root, no system Python, and a clean remove. The answer
is [Astral's `uv`](https://github.com/astral-sh/uv) — a single static
binary that both manages its own CPython and installs Python CLIs as
isolated "tools." A second shared helper,
`plugin/catalog/lib/uv-bootstrap.sh`, packages the pattern so any Python
tool is again a catalog entry plus a thin recipe.

The helper bootstraps `uv` itself through the *same* checksum-verified
fetch the prebuilt-binary tools use (uv ships static musl builds and a
combined checksum file), dropping it into the agent's own `~/.local/bin`.
`uv tool install` then builds the CLI from its pinned upstream — Spec Kit
installs from a git tag, `uv tool install specify-cli --from
git+…@v0.12.11`, and `uv` downloads a managed CPython so the host needs
none. Because that source is a git ref, `git` is the one host prerequisite
(Spec Kit is a git-centric workflow tool anyway); the recipe checks for it
and fails with a clear message rather than a cryptic build error. The
installed `specify` lands on `~/.local/bin`, already on PATH.

Two ownership rules keep remove honest. First, the helper never clobbers
a `uv` the user brought — if `uv` is already on PATH it is reused, and
only a `uv` AgentLinux installed itself (recorded by a marker file) is
ever removed. Second, that managed `uv` is torn down only once no `uv`
tools remain, so removing one Python tool never breaks another. And a
project's `.specify/` directory — the user's actual spec-driven work —
is outside the tool footprint entirely: `agentlinux remove spec-kit`
uninstalls the CLI and, if it owns the last `uv`, the runtime, but never
touches a `.specify/` anywhere.

## Per-user daemons: a background service with no root

A few tools are not a CLI a user invokes but a *service* that runs in the
background — a personal-AI-assistant gateway that stays up to bridge the
user's chat channels and coding agents to a model provider. OpenClaw is
the first, and it exposed a general need: bring up a long-lived per-user
service with no root, keep it alive across logout, and tear it down on
remove with nothing left running. A shared helper,
`plugin/catalog/lib/daemon-lifecycle.sh`, packages that lifecycle so the
next daemon tool is again a catalog entry plus a thin recipe.

The service runs under the user's own systemd instance — no root, no
system-wide unit. Two things make that reliable on a headless machine:
`XDG_RUNTIME_DIR` has to point at the user bus, and *linger* has to be
enabled so the user's systemd keeps running after the login session ends.
The helper handles both, and it is ownership-aware the same way the `uv`
bootstrap is: it enables linger only if it was off, records that it did,
and on remove reverts linger only when it turned it on *and* no other
AgentLinux daemon still needs it — so removing one daemon tool never cuts
the ground out from under another. OpenClaw is bring-your-own-key: the
install bakes no provider credential, and the user adds one in the tool
afterward.

Because a per-user systemd bus is not available everywhere — a plain
container has none — the helper probes for it and the recipe adapts:
where the user bus is present the daemon is installed and started; where
it is absent the tool is still installed and configured, with a note on
how to run it by hand. So `agentlinux install openclaw` succeeds on a
real host and in a container alike. On remove the service and its unit
are torn down completely, while the user's `~/.openclaw` state — the
assistant's persona, its conversation history, and any key the user
added — is preserved like every other authenticated agent's config; only
a full agent-home purge wipes it.

## The MCP source kind

An MCP server is not a program AgentLinux installs — it is a service a
coding agent is told about. So the `mcp` source kind does not put a file
on disk; it *registers* the server into the agent's own configuration.
For Claude Code that means `claude mcp add <name> --scope user`, which
writes the server (its launch command and args) into the user-scope
`mcpServers` block of `~/.claude.json`; `agentlinux remove` runs
`claude mcp remove` to take it back out, leaving no residue. Both halves
are idempotent, so a re-install or a double-remove is a clean no-op.

Because the registration lives in the coding agent's config, an MCP
entry has a real dependency: the agent has to be installed first. The
recipe checks for `claude` on PATH and fails with a plain pointer
(`agentlinux install claude-code`) rather than a cryptic
command-not-found. The pinned version rides in the launch command
itself — `chrome-devtools-mcp`, the first MCP entry, registers
`npx -y chrome-devtools-mcp@<pin>`, so npx fetches exactly the curated
version on first launch and nothing is installed into the agent prefix.

Two things about MCP entries are worth their own fields. First, whether a
server needs the user to authenticate. The catalog never bakes a secret;
an entry just *flags* the need with `requires_secret` — a documentation
signal that the user must sign in, not a value AgentLinux carries. How the
user signs in depends on the entry's shape. For the **hosted (remote-http)
servers** the answer is uniform and is described just below: the entry is a
thin installer that registers a bare URL and the user completes OAuth
in-client (the governing convention, [ADR-017](../decisions/017-mcp-thin-installer-in-client-auth.md)).
The earlier **locally-launched (npx-stdio) servers** predate that
convention and carry a lighter variant: `chrome-devtools-mcp` is keyless
(needs nothing), while `context7` names an *optional* key with
`secret_env: CONTEXT7_API_KEY` — the server works keyless and a free key
just raises the rate limit; its recipe registers the server keyless and
tells the user how to supply the key, which is never written into a recipe,
the catalog, or the committed image. Second, a server may need something
else present to actually do its job: `chrome-devtools-mcp` drives a real
Chrome/Chromium for its browser tools, so its install surfaces that
requirement (the AgentLinux `playwright-cli` entry provides a Chromium, or
a system Chrome works).

### Hosted (remote-http) servers, and registering into every agent

Some MCP servers are not launched locally at all — they are hosted web
services the agent talks to over HTTP. `github-mcp`, `sentry-mcp`,
`firecrawl-mcp`, `slack-mcp`, `linear-mcp`, and `jira-atlassian-mcp`
point at GitHub's, Sentry's, Firecrawl's, Slack's, Linear's, and
Atlassian's hosted endpoints (`https://api.githubcopilot.com/mcp/`,
`https://mcp.sentry.dev/mcp`, `https://mcp.firecrawl.dev/v2/mcp`,
`https://mcp.slack.com/mcp`, `https://mcp.linear.app/mcp`,
`https://mcp.atlassian.com/v1/mcp/authv2`). A
hosted service has no version number to pin, so the entry records the
endpoint in `endpoint_url` and uses `pinned_version` to name the upstream
server release the endpoint is validated against — the URL is the real
stability contract. When
a hosted service has no downloadable release — Slack's, Linear's, and
Atlassian's are rolling endpoints, not packages — `pinned_version`
carries the endpoint's GA date instead. Separately, when there is no
public source repository, the entry omits the `license` field a package
would carry (Slack, Linear); but a hosted service can still be backed by
an open-source repo, so `jira-atlassian-mcp` records `Apache-2.0` (the
Atlassian Rovo server's repo) while still pinning a GA date.

Not every hosted endpoint requires signing in. `firecrawl-mcp` registers
a **keyless** endpoint that works out of the box, so its `requires_secret`
is `false` — a user who wants their own recurring quota re-registers with
a personal key (Firecrawl embeds it in the URL path, not a header), the
same optional-upgrade shape `context7` uses for a local server. A tool
earns a hosted entry only when its free tier is genuinely usable without
payment; two candidates (a GitLab and a Brave Search server) were dropped
because their "free" tiers turned out to require a paid plan or a
mandatory payment card, which would have made the entry install to a
dead end.

Source choice also weighs governance. Where a vendor ships an official,
admin-governed endpoint, that is preferred over a popular third-party
server that authenticates by scraping a user's browser session tokens —
`slack-mcp` registers Slack's own OAuth endpoint precisely so a workspace
admin can see and revoke the integration, rather than a "stealth" server
that bypasses admin approval entirely.

Because an MCP server is useful to *any* coding agent, not just Claude
Code, an entry registers into all of them. `github-mcp` fans its
registration out to every installed MCP-capable agent (Claude Code,
Codex, Gemini CLI, opencode, qwen-code), writing each one's own config
format, and `remove` tears it back out of all of them. A shared helper
owns the per-agent writers so any remote entry gets the fan-out for free.

The important part is what an MCP entry *doesn't* do: it is a **thin
installer**. It writes the bare server — the URL, wrapped in whatever
minimal non-credential shape each client expects — into each agent's
config so the agent knows the server exists. It does not run the server
and it stores **no credential**: no token, no header, no env-var
reference. The user authenticates *inside their agent* afterwards
— for a hosted server that means the agent's own OAuth prompt on first
use. This keeps AgentLinux out of the credential business entirely (there
is no secret to leak, by construction) and avoids coupling each entry to
a tool-specific auth scheme. `requires_secret` stays on the entry as a
documentation flag — "this server needs you to sign in" — but AgentLinux
never carries the secret. An agent installed *after* the server does not
automatically receive the registration; re-running the install fans it
out again.

## Worked example

```
$ jq '.agents[] | {id, source_kind, pinned_version}' \
    /opt/agentlinux/catalog/0.3.4/catalog.json
{ "id": "claude-code",    "source_kind": "script", "pinned_version": "2.1.98" }
{ "id": "gsd",            "source_kind": "npm",    "pinned_version": "1.37.1" }
{ "id": "playwright-cli", "source_kind": "npm",    "pinned_version": "0.1.11" }
{ "id": "codex",          "source_kind": "npm",    "pinned_version": "0.142.3" }
{ "id": "rtk",            "source_kind": "binary", "pinned_version": "0.42.4" }
{ "id": "gh",             "source_kind": "binary", "pinned_version": "2.95.0" }
{ "id": "chrome-devtools-mcp", "source_kind": "mcp", "pinned_version": "1.4.0" }
# … (abridged — see catalog.json for the full roster)
```

Adding a new agent looks like:

```
$ mkdir plugin/catalog/agents/<new-id>
$ touch plugin/catalog/agents/<new-id>/{install,uninstall}.sh && chmod +x ...
$ $EDITOR plugin/catalog/catalog.json   # add the entry
$ pre-commit run --all-files            # ajv validation runs here
```

No CLI source edited. Our catalog reviewer validates the entry
against the schema; our PR review process flags any
`sudo npm install -g` or `/usr/local/bin/` shim in the recipe; the
release-gate matrix runs the recipe end-to-end on a clean host.

## Value vs the naive approach

Without a schema-validated catalog, the naive paths are "hardcoded
agent list in CLI source" or "README install commands." Two problems:

1. **Hardcoding means a CLI release per agent.** Every new agent
   requires a TypeScript edit, a CI run, a release tag — a friction
   tax that grows with every entry. The catalog inverts this: a new
   agent is one PR with no CLI source change, the schema is the
   contract, and the recipe is the implementation. Catalog and CLI
   evolve at different speeds because they are different artifacts.
2. **Without schema validation, every recipe is a snowflake.** The
   schema enforces required fields (`pinned_version`,
   `install_recipe_path`, `uninstall_recipe_path`); pre-commit and
   CI catch malformed entries before they ship. Without it, an entry
   missing `uninstall_recipe_path` or pointing at a recipe that does
   not exist passes review and breaks operators in production. The
   schema is also where "every install must declare a pinned
   version" — the load-bearing rule of
   [STABILITY-MODEL.md](../STABILITY-MODEL.md) — gets enforced.

**The catalog is the contract that lets AgentLinux ship as a curated
combo — pinned versions, opt-in installs, validated schema — while
keeping the cost of adding an agent to one PR.** The CLI reads the
catalog; the catalog auditor validates it; the release matrix
exercises every entry end-to-end. The single source of truth is one
JSON file with a published schema.

## Related

- [Registry CLI](registry-cli.md) — the `agentlinux` command that
  reads this catalog and dispatches its recipes.
- [../STABILITY-MODEL.md](../STABILITY-MODEL.md) — curated combos and
  the three-way divergence model the `pinned_version` field anchors.
- [Claude Code](claude-code.md) — the `claude-code` entry's home.
- [GSD](gsd.md) — the `gsd` entry's home.
- [Playwright](playwright.md) — the `playwright-cli` entry's home.
