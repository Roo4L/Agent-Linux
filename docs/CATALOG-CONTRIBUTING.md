# Adding a catalog entry — the growth kit

AgentLinux ships a curated catalog of agent tools (`agentlinux list`). This is the
contributor guide for **adding a new entry**: the bar an entry must clear, how the CLI
categorizes it, and the mechanical steps. The design goal is that a new tool is a
**catalog entry plus a recipe pair — no CLI TypeScript changes**. The
`plugin/catalog/agents/_template/` recipe skeletons and the
`plugin/catalog/agents/test-dummy/` entry are the worked examples.

## 1. Selection rubric — does the tool belong?

An entry must pass every **gate**, then is ranked by **score**. This is the same funnel the
initial catalog used; it keeps the roster trustworthy and small.

**Gates (all required):**

1. **Agent-relevant** — it is used by, or directly supports, AI coding/agent workflows.
2. **Clean per-user install** — installs and uninstalls as the agent user with **no root**,
   **no `/usr/local` shim**, and a **symmetric remove** (no residue). If it can only install
   system-wide or with sudo, it does not qualify.
3. **Free to use** — an OSS licence (MIT/Apache/BSD) or a genuinely card-free tier. A tool
   gated behind a paid plan or a mandatory credit card fails this gate (this is why several
   MCP servers were dropped). "Source-available" licences (e.g. FSL) pass the *free-to-use*
   gate but are flagged.
4. **Live** — a release within ~6 months and commits within ~3 months. Abandoned projects
   are out.
5. **Source integrity** — prefer the **official first-party** distribution. A **free,
   official, first-party hosted** endpoint is an automatic yes. Anything else — third-party
   packages, self-hosted daemons, curl-pipe-bash installers, paid or beta tiers — needs
   explicit maintainer review, and the recipe must pin hard (exact version or immutable
   commit) and, for installer scripts, download-then-run over pinned TLS rather than
   `curl | bash`.

**Score (tie-breakers among tools that pass the gates):** popularity/adoption, breadth of
usefulness to the first-release cohort, maturity, and how cleanly it fits an existing recipe
shape. Prefer tools that reuse a shared helper over ones needing bespoke machinery.

## 2. Pick a category

`agentlinux list --by-category` groups entries by a small fixed set. The category is
**derived from the entry's `tags`** (see `plugin/cli/src/catalog/category.ts`) — you do not
set it directly; you choose a canonical category tag. First matching tag wins, in this
precedence:

| Put this tag in `tags` | Category |
|------------------------|----------|
| `coding-agent`         | Coding agents |
| `assistant`            | AI assistants |
| `mcp`                  | MCP servers |
| `workflow` or `token`  | Token & workflow |
| `devops`               | DevOps & security |
| `browser`/`automation` | Browser & automation |
| `agent` (fallback)     | Coding agents |

The **first canonical tag in this table's order wins** — regardless of how you order tags in
your `tags` array. So a tool tagged both `workflow` and `devops` groups under **Token &
workflow** (a token/workflow tool that happens to touch DevOps), and a coding agent that
lists `["agent", "coding-agent"]` still groups under **Coding agents**. As a safety net an
`mcp`-`source_kind` entry lands under **MCP servers** even if its `tags` omit `mcp`. Add
descriptive secondary tags freely (`git`, `security`, `sentry`, …) — only the first canonical
one picks the group. An entry with no canonical tag falls under **Other**, never dropped.

## 3. Add the entry (no CLI edits)

1. **Copy the template:** `cp -r plugin/catalog/agents/_template plugin/catalog/agents/<id>`
   and fill in `install.sh` + `uninstall.sh`. Reuse a shared helper from
   `plugin/catalog/lib/` where one fits — `prebuilt-binary.sh`, `uv-bootstrap.sh`,
   `mcp-register.sh`, `daemon-lifecycle.sh` — sourced via
   `"${AGENTLINUX_CATALOG_DIR}/lib/<helper>.sh"` (the template header shows the idiom).
2. **Add the catalog entry** to `plugin/catalog/catalog.json` `agents[]`:
   ```json
   {
     "id": "<id>",
     "display_name": "<Display Name>",
     "description": "<one line — what it is, how to authenticate if needed>",
     "source_kind": "npm | binary | script | mcp",
     "npm_package_name": "<pkg>",
     "pinned_version": "X.Y.Z",
     "install_recipe_path": "install.sh",
     "uninstall_recipe_path": "uninstall.sh",
     "tags": ["<category-tag>", "<extra>", "…"]
   }
   ```
   Required: `id`, `display_name`, `description`, `source_kind`, `pinned_version`,
   `install_recipe_path`, `uninstall_recipe_path`. `npm_package_name` is required **only** when
   `source_kind` is `npm` (drop it otherwise). Optional: `homepage`, `license`,
   `requires_secret`/`secret_env` (declare a credential — never bake it), `endpoint_url`
   (hosted MCP), `preserve_paths_file` (config preserved across uninstall),
   `compatibility_window` (version-adoption window), `post_install_verify`. The full field
   list + validation rules live in `plugin/catalog/schema.json`.
3. **Validate:** `node plugin/cli/scripts/validate-catalog.mjs` (also runs in pre-commit).
4. **Add a behavior test** in `tests/bats/` that proves the round trip: install →
   `post_install_verify` → symmetric remove, no residue. Copy the shape of the sibling test
   for your source kind: `53-catalog-npm-cluster.bats` (npm), `57-catalog-binary.bats`
   (binary), `59-catalog-mcp.bats` (mcp), `66-catalog-spec-kit.bats` (script/uv).
5. **Run the review loop** (see `CLAUDE.md` → Review Loop) and the Docker suite.

Because install/remove dispatch is generic, steps 1–2 are the entire code change — no
TypeScript is touched. `test-dummy` is the minimal end-to-end proof of exactly this path.

## 4. Recipe rules (enforced by review + tests)

- Run as the agent user; **no `sudo npm install -g`**, **no `/usr/local` shim** — both break
  a tool's self-update, the bug class AgentLinux exists to eliminate.
- Install into agent-owned paths; **pin** the version and **version-lock** against
  `AGENTLINUX_PINNED_VERSION`.
- **Never bake a secret.** Declare it with `requires_secret`/`secret_env`, print the
  post-install instruction, and let the user authenticate in-tool.
- Make remove **symmetric and idempotent**; preserve user config/credentials
  (only `--purge` wipes them).
