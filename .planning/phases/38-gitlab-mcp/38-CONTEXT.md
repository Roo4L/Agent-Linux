# Phase 38: gitlab-mcp - Context

**Gathered:** 2026-07-13
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous)

<domain>
## Phase Boundary

Make GitLab's MCP server installable/removable via the catalog (MCP-05) as a thin
client-config installer per ADR-017: register the official hosted endpoint (bare
URL) into every installed MCP-capable agent; the user authenticates in-client.
Reuses the credential-free ENABLE-02 helper.
</domain>

<decisions>
## Implementation Decisions

### Source: official first-party hosted endpoint (maintainer decision)
- **Register GitLab's official hosted MCP** `https://gitlab.com/api/v4/mcp`
  (GitLab Duo Agent Platform, OAuth Dynamic Client Registration) — NOT the
  third-party npx `@zereight/mcp-gitlab`. First-party trust + clean in-client
  OAuth; a textbook thin-installer fit.
- **Catalog source-selection policy (ADR-017 addendum, locked this phase):**
  prefer the official first-party hosted endpoint **even if beta** over a
  third-party server; fall back to third-party only when no first-party exists.
  GitLab's endpoint is beta (from GitLab 18.6) — accepted.
- `pinned_version: 18.6.0` (the GitLab release the endpoint is validated against;
  the endpoint is a rolling API surface, no npm package). `license: MIT` (GitLab
  CE). `requires_secret: true` (doc flag — needs in-client auth), no `secret_env`.
- Self-managed GitLab users re-register against their own `https://<host>/api/v4/mcp`
  (surfaced in the install note).
</decisions>

<code_context>
## Existing Code Insights
- `plugin/catalog/lib/mcp-register.sh` (credential-free) + the sentry-mcp /
  github-mcp recipe pattern — gitlab-mcp mirrors them exactly (bare URL, friendly
  no-agent error, in-client-auth note).
- `tests/bats/62-catalog-gitlab-mcp.bats` (MCP-05) mirrors 60/61; the entry-shape
  test additionally asserts the recipe uses the official hosted endpoint (no
  docker/npx/zereight third-party).
</code_context>

<specifics>
## Specific Ideas
- Maintainer chose the official beta endpoint over the GA third-party npx, and set
  the standing "prefer first-party, beta OK" policy.
</specifics>

<deferred>
## Deferred Ideas
- Third-party `@zereight/mcp-gitlab` stdio fallback (only if the official endpoint
  is later disqualified).
- PAT-header auth for the official endpoint (GitLab issue #586184, unshipped).
</deferred>
