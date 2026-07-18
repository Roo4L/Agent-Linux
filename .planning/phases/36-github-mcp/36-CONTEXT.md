# Phase 36: github-mcp - Context

**Gathered:** 2026-07-13
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — grey areas resolved with the user

<domain>
## Phase Boundary

Make the **GitHub MCP server** installable/removable via the AgentLinux catalog
(MCP-03), using the **remote-http** transport and registering it into **every
installed MCP-capable coding agent** — not just Claude Code. Delivers the
ENABLE-02 **remote-http** machinery (its true first consumer; reused by Phases
42 linear-mcp + 43 jira-atlassian-mcp) and a **shared cross-agent MCP
registration helper** that all MCP entries can adopt.

Out of scope: the local Go-binary stdio variant; OAuth login flows (PAT only);
retrofitting the Claude-Code-only entries chrome-devtools-mcp (34) / context7
(35) onto the cross-agent helper (noted as a deferred follow-up).
</domain>

<decisions>
## Implementation Decisions

### Transport & endpoint
- **Remote-http** transport (not the Go binary, not Docker). Hosted endpoint:
  `https://api.githubcopilot.com/mcp/`.
- A hosted remote MCP is a rolling service with **no semver** — the stability
  contract is the **URL**, not a version. The catalog entry pins the endpoint
  URL; `pinned_version` semantics for remote mcp entries handled in planning
  (schema: optional/sentinel for `source_kind: mcp` remote entries + an
  `endpoint_url` field).
- The **ENABLE-02 remote-http enabler is built in Phase 36** (folded into its
  first consumer), reused by 42/43. Phase 42 adds only the OAuth nuance.

### Cross-agent fan-out (all 5 MCP-capable agents)
- Register into **every currently-installed** MCP-capable agent, conditional on
  presence: **claude-code, codex, gemini-cli, opencode, qwen-code**.
- A **shared helper** `plugin/catalog/lib/mcp-register.sh` owns the per-agent
  writers (each agent uses a different config format); the github-mcp recipe is
  a thin consumer. Designed so 42/43 (and a later 34/35 retrofit) reuse it.
- Per-agent target formats (confirmed by research):
  - **claude-code** → `claude mcp add --transport http github <url> --scope user
    --header 'Authorization: Bearer ${GITHUB_MCP_PAT}'` → `~/.claude.json`
    `.mcpServers.github` `{type:http,url,headers}`. Remove-then-add idempotent.
  - **codex** → `~/.codex/config.toml` `[mcp_servers.github]` with `url` +
    `bearer_token_env_var = "GITHUB_MCP_PAT"` (token kept OFF disk by design).
    `codex mcp add` is stdio-only, so HTTP is written by editing config.toml
    (marker-delimited block for idempotent add/remove).
  - **gemini-cli** → `~/.gemini/settings.json` `mcpServers.github`
    `{httpUrl, headers:{Authorization:"Bearer ${GITHUB_MCP_PAT}"}}` (jq merge).
  - **opencode** → `~/.config/opencode/opencode.json` `mcp.github`
    `{type:"remote", url, enabled:true, headers:{...}}` (jq merge).
  - **qwen-code** → `~/.qwen/settings.json` `mcpServers.github` (gemini schema).
- **Order-dependency (WIRE-01 style):** applied at github-mcp install time to
  agents present THEN. An agent installed later won't carry it — documented;
  remedy is re-running `agentlinux install github-mcp`. (Same corner case as the
  GSD/playwright cross-agent wiring.)
- **Symmetric removal:** `remove` deregisters from ALL present agents; no
  residue in any config, no leaked PAT.

### Never-bake mandatory secret
- `requires_secret: true`, `secret_env: GITHUB_MCP_PAT` (avoids collision with
  gh CLI's `GITHUB_TOKEN`/`GH_TOKEN`).
- The recipe writes only an **env-var reference** — `Bearer ${GITHUB_MCP_PAT}`
  (single-quoted in bash so it is NOT expanded at write time) for the 4 disk
  writers, and `bearer_token_env_var` for codex. **Verified live**: Claude Code
  stores the literal `${GITHUB_MCP_PAT}` and expands it at server-launch from
  the environment. No literal token ever touches a config, the recipe, or a
  commit.
- `install` prints the mandatory post-install instruction: export
  `GITHUB_MCP_PAT` (a GitHub PAT; classic scopes `repo`, `read:org`,
  `read:packages`) in the environment the agents run in.
- A **defence-in-depth guard** fails the install if a literal token (e.g.
  `ghp_…` / `github_pat_…`) appears in any written config.

### Verification
- ≥1 bats @test (TST-07): install with ≥1 agent present → each present agent's
  config carries the github entry with the **env-var reference** (no literal
  token) → symmetric remove leaves no residue → idempotent re-remove. Absent
  agents are skipped cleanly. secret-not-baked grep asserted. NEVER the Docker
  recipe (no `docker`/`ghcr.io` in the recipe — grep guard).
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `plugin/catalog/agents/context7/{install,uninstall}.sh` + `chrome-devtools-mcp/`
  — the Claude-Code MCP register/deregister pattern (remove-then-add idempotent,
  jq assertions, no-baked-key guard, atomic jq-del uninstall).
- `plugin/catalog/lib/prebuilt-binary.sh` — precedent for a shared catalog lib
  under `plugin/catalog/lib/` with a functrace-guarded RETURN trap; mcp-register.sh
  will sit beside it.
- CLI runner env contract (`plugin/cli/src/runner.ts`): injects
  AGENTLINUX_AGENT_HOME=/home/agent, AGENTLINUX_PINNED_VERSION, PATH, etc. into
  every recipe. No secret is ever injected (never-bake).
- Schema/types secret convention (`requires_secret`/`secret_env`) already exists
  from ENABLE-02 (Phase 34) — github-mcp is the first `requires_secret: true`.

### Established Patterns
- `source_kind: "mcp"` dispatch in the CLI is generic (register = install,
  deregister = remove); only npm-specific upgrade branches on source_kind and
  treats mcp as "no upstream".
- CAT-04 preserve-on-remove convention for auth config; but MCP registrations
  are OUR artifacts in each agent's config, so remove SHOULD delete them (not
  preserve) — analogous to how `claude mcp remove` cleans its own entry.

### Integration Points
- New shared lib: `plugin/catalog/lib/mcp-register.sh`.
- Schema/types: add remote-mcp support (`endpoint_url`, pinned_version optional
  for remote mcp) in `plugin/catalog/schema.json` + `plugin/cli/src/types.ts`.
- New bats: `tests/bats/60-catalog-github-mcp.bats` (or extend 59).
- docs/internals/catalog.md: remote-http + cross-agent MCP section.
</code_context>

<specifics>
## Specific Ideas

- User (verbatim): "use remote http and register MCP server within all our AI
  agents and tools that might use it, like claude code and codex" → chose **all
  5** MCP-capable agents on the follow-up.
- Env-var reference (not literal) is the never-bake keystone — proven working in
  Claude Code this session.
- Codex is the cleanest (token off-disk via `bearer_token_env_var`).
</specifics>

<deferred>
## Deferred Ideas

- Retrofit chrome-devtools-mcp (34) + context7 (35) onto the shared cross-agent
  helper so they also fan out (currently Claude-Code-only). Cheap once the
  helper exists; own follow-up task.
- Local Go-binary stdio variant (`github-mcp-server@1.5.0`) as an offline/curated
  alternative to the hosted endpoint.
- OAuth login flow (Phase 42 linear-mcp introduces OAuth for remote MCP).
- Install-order-independence: an agent installed AFTER an MCP server does not
  auto-receive the registration (needs an agent-install-time rescan/reconcile).
</deferred>
