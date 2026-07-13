# Phase 37: sentry-mcp - Context

**Gathered:** 2026-07-13
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — grey areas resolved with the user

<domain>
## Phase Boundary

Make Sentry's MCP server installable/removable via the catalog (MCP-04), as a
**thin client-config installer** per ADR-017: register the hosted remote endpoint
(bare URL) into every installed MCP-capable agent; the user authenticates
in-client. Reuses the ENABLE-02 remote-http cross-agent helper from Phase 36.

Out of scope: the npx-stdio `@sentry/mcp-server` variant; any token/OAuth handling
by AgentLinux.
</domain>

<decisions>
## Implementation Decisions

### The governing convention — ADR-017 (locked this phase, applies to all MCP entries)
- An MCP entry is a **thin client-config installer**: register the BARE server
  (URL for remote; command for stdio-only), bake **NO credential**, and let the
  user authenticate **in-client** (OAuth on first use for a hosted server).
- **Prefer the hosted/remote endpoint** wherever one exists. Drop `secret_env`;
  `requires_secret` stays as a doc flag ("needs in-client auth").
- Recorded in `docs/decisions/017-mcp-thin-installer-in-client-auth.md` +
  REQUIREMENTS ENABLE-02. **github-mcp (36) retrofitted** to match; the shared
  helper `mcp-register.sh` is now credential-free (`al_mcp_register_http <server>
  <url>` writes a bare entry into all present agents).

### sentry-mcp specifics
- **Transport: hosted remote.** Endpoint `https://mcp.sentry.dev/mcp`. Chosen over
  the npx-stdio `@sentry/mcp-server` variant (research: the hosted server's static
  path uses a custom `Sentry-Bearer` scheme, but under ADR-017 we bake nothing and
  the user OAuths in-client, so the hosted URL is the clean fit and reuses the
  Phase 36 helper unchanged).
- `pinned_version: 0.37.0` (the current `@sentry/mcp-server` release the endpoint
  is validated against; roadmap's `0.36.0` was stale). `endpoint_url` records the
  URL.
- **License FSL-1.1-ALv2** (research-confirmed; the roadmap's "FSL-1.1-Apache" is
  the intent — FSL 1.1 with an Apache-2.0 future grant). Recorded in the entry.
- `requires_secret: true` (needs in-client auth); **no `secret_env`**.
- Install prints the in-client-auth pointer (Claude Code prompts a Sentry OAuth
  login); remove deregisters from all agents; residue-free.
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `plugin/catalog/lib/mcp-register.sh` — the register-only cross-agent helper
  (`al_mcp_register_http <server> <url>` / `al_mcp_deregister` /
  `al_mcp_assert_absent`), built in Phase 36 and made credential-free per ADR-017.
- `plugin/catalog/agents/github-mcp/{install,uninstall}.sh` — the thin-installer
  recipe pattern sentry-mcp mirrors (bare URL, friendly no-agent error,
  in-client-auth note).
- `endpoint_url` schema field (Phase 36) models the versionless hosted endpoint.

### Established Patterns
- One bats gate per requirement (`tests/bats/61-catalog-sentry-mcp.bats`, MCP-04),
  mirroring 60 (github-mcp): bare-URL fan-out into claude+codex, no-credential
  grep across all 5 configs, symmetric residue-free removal, entry-shape check.
</code_context>

<specifics>
## Specific Ideas

- Maintainer reframe (verbatim intent): MCP entries are thin installers that just
  configure the clients so the user can auth inside the client — "Not necessarily
  credentials themselves … register bare URL, no credentials; retrofit github-mcp
  to match. Record this decision so we adhere to it in later MCP phases too."
</specifics>

<deferred>
## Deferred Ideas

- npx-stdio `@sentry/mcp-server` variant (offline/self-hosted alternative).
- Retrofit chrome-devtools-mcp (34) + context7 (35) onto the cross-agent helper
  (still Claude-Code-only stdio entries).
- Install-order-independence (agent installed after the server misses the entry).
</deferred>
