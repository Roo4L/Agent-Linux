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
originals claude-code, gsd, playwright-cli plus the v0.3.6 coding-agent
cluster codex, gemini-cli, opencode, qwen-code, ccusage) plus one
`test_only` fixture exercised only by bats. Pre-commit and CI both run the catalog
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

## Source kinds: npm, script, and prebuilt binary

Not every tool ships on npm. Some of the most useful developer CLIs are
distributed only as a compiled, per-architecture binary attached to a
GitHub release. The catalog's `source_kind` field names how an entry is
installed, and it now understands three values:

- `npm` — install the pinned package into the agent-owned npm prefix.
- `script` — run the upstream's own install script (how Claude Code
  installs).
- `binary` — fetch a pinned release artifact, verify its checksum, and
  drop the binary into the agent's own `~/.local/bin`.

The prebuilt-binary kind is the one that needs the most care, because
"download a binary from the internet and run it" is exactly where a
supply-chain mistake does the most damage. AgentLinux installs a binary
the same disciplined way its own curl-installer verifies a release: the
asset is staged to a scratch directory, its gzip signature and its
SHA-256 are checked against the release's published `checksums.txt`
**before anything is extracted**, and any mismatch aborts the install
without unpacking or replacing a single file. Verification happens
before extraction, never after.

The mechanics live in one shared helper,
`plugin/catalog/lib/prebuilt-binary.sh`, that every binary recipe
sources. It maps the running architecture to the right release asset,
performs the verify-before-extract download, installs the binary
`0755` into `~/.local/bin` — agent-owned, no root, and deliberately no
`/usr/local/bin` shim (the shim is the anti-pattern that breaks a
tool's own self-update) — then asserts the installed binary reports the
pinned version. Because the helper is generic over
repo/tag/asset/binary-name, adding the next binary-distributed tool is
a catalog entry plus a thin recipe, with no shared code to touch.

`rtk` (the Rust Token Killer, a token-optimizing CLI proxy) is the
first tool installed this way. Its entry pins an exact release, its
recipe is a handful of lines over the shared helper, and its optional
Claude Code hook is strictly opt-in — installing `rtk` never writes to
`~/.claude` on its own; a user runs `rtk init` themselves if they want
it, and `agentlinux remove rtk` reverts that hook along with the binary
and rtk's own config and cache, leaving no residue behind.

## Worked example

```
$ jq '.agents[] | {id, source_kind, pinned_version}' \
    /opt/agentlinux/catalog/0.3.4/catalog.json
{ "id": "claude-code",    "source_kind": "script", "pinned_version": "2.1.98" }
{ "id": "gsd",            "source_kind": "npm",    "pinned_version": "1.37.1" }
{ "id": "playwright-cli", "source_kind": "npm",    "pinned_version": "0.1.11" }
{ "id": "codex",          "source_kind": "npm",    "pinned_version": "0.142.3" }
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
