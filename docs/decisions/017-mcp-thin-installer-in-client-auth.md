# 017: MCP entries are thin client-config installers; auth happens in-client

**Status:** Accepted
**Date:** 2026-07-13
**Drives:** v0.3.6 ENABLE-02 (MCP entry kind); MCP-01..MCP-09 (Phases 34–43)
**Supersedes (in part):** the credential-injection approach shipped in the first
cut of MCP-03 (github-mcp, Phase 36), which this ADR retrofits.

## Status

Accepted (2026-07-13), locked by maintainer decision during the Phase 37
(`/gsd-autonomous`) discuss.

## Context

The catalog's `mcp` source kind registers a Model Context Protocol server into
each installed coding agent. Two mental models collided while planning the MCP
cluster (Phases 34–43):

1. **Server-runner / credential-manager** (the direction the first github-mcp cut
   drifted): AgentLinux stands the server up and wires the credential — e.g. it
   stored an env-var *reference* (`Authorization: Bearer ${GITHUB_MCP_PAT}`) into
   each agent's config and printed a "export this token" instruction, so the
   server would be authenticated the moment the agent launched it.

2. **Thin config installer** (the maintainer's intent): AgentLinux only appends
   the server to each client's MCP list so the client *knows the server exists*.
   It does not run the server and does not manage credentials. The user completes
   authentication **inside the client** afterwards — for a hosted/remote MCP
   server that means the client's own OAuth prompt on first use.

Model 1 is more than the product should do. It couples AgentLinux to each tool's
credential format, invites secret-handling surface (even as "just a reference"),
and pins us to whichever auth scheme a given server expects (GitHub `Bearer`,
Sentry's custom `Sentry-Bearer`, per-tool env-var names). Model 2 is a thin,
uniform installer: the same "write a bare server entry into N clients" for every
tool, with auth delegated to the client where it belongs.

## Decision

**An MCP catalog entry is a thin client-config installer. It registers the bare
server (URL for a remote server; launch command for a stdio-only server) into
every installed MCP-capable client, and stops there. AgentLinux does not run the
server and bakes NO credential — not the literal, not an env-var reference, not a
header. The user authenticates inside the client (in-client OAuth for a remote
server; the client passes through whatever env the user has set for a stdio
server).**

Concretely:

- **Prefer the hosted/remote endpoint** wherever a tool offers one. Register the
  URL (`claude mcp add --transport http <name> <url>` with **no** `--header`; the
  Codex/Gemini/opencode/qwen equivalents with **no** headers/token field). The
  client handles the connection and prompts the user for OAuth.
- **stdio (npx) is a fallback**, only for tools with no hosted option. Register
  the launch command (`npx -y <pkg>@<pin>`) with **no** baked env/token; the
  client spawns the process and it inherits whatever credential the user exported
  into the environment. There is no interactive in-client auth for stdio — that is
  an inherent property of stdio servers, not something AgentLinux papers over.
- **The install recipe prints a one-line pointer** telling the user that auth is
  completed in their client (e.g. "Claude Code will prompt an OAuth login on first
  use"). It never prints "export TOKEN=…" as a requirement we manage.
- **`requires_secret`** stays meaningful as a *documentation* flag ("this server
  needs the user to authenticate") but no longer implies AgentLinux carries a
  secret. **`secret_env` is dropped** from register-only MCP entries — there is no
  env var we reference.
- **`remove` deregisters** the entry from every client symmetrically (unchanged).

## Consequences

- The shared helper `plugin/catalog/lib/mcp-register.sh` becomes credential-free:
  `al_mcp_register_http <server> <url>` writes a bare remote entry; the never-bake
  header/reference machinery and the `secret_env` plumbing are removed. Simpler,
  and there is no secret to leak by construction.
- **github-mcp (Phase 36) is retrofitted** to register the bare
  `https://api.githubcopilot.com/mcp/` (GitHub's hosted MCP supports in-client
  OAuth); its `GITHUB_MCP_PAT` reference, `secret_env`, and never-bake assertions
  are removed. Its bats gate asserts bare-URL registration + no credential in any
  config + symmetric removal.
- **All later MCP phases (37 sentry, 38 gitlab, 39 brave, 40 firecrawl, 41 slack,
  42 linear, 43 jira) follow this convention.** Where a tool is hosted+OAuth
  (sentry `mcp.sentry.dev`, linear, jira, GitHub) we register the URL. Where a
  tool is npx-only we register the command, no baked token.
- The roadmap's per-phase "PAT/token supplied post-install (`secret_env`)" wording
  is reinterpreted: the user supplies auth **in-client**, not via an AgentLinux-
  managed env var. Success criteria about "never baked" are satisfied trivially
  (nothing is baked); criteria naming a specific env var are advisory.

## Source-selection policy (addendum, 2026-07-13)

When choosing *which* server an MCP entry registers:

- **A FREE official first-party hosted endpoint is auto-preferred** — no
  discussion needed. It is the ideal thin-installer fit (first-party trust + clean
  in-client OAuth + usable by the whole user base). This is the case for
  github-mcp and sentry-mcp.
- **Every other case needs per-entry maintainer discussion/review** — a *paid*
  first-party endpoint, a third-party server, a beta with caveats, etc. There is
  no blanket rule that first-party always wins; usability for the broad user base
  is weighed against trust and convenience per entry.

A `pinned_version` for a hosted endpoint names the vendor release it is validated
against.

**Worked outcome — gitlab-mcp (Phase 38) was DROPPED (not shipped).** GitLab's
official hosted endpoint (`https://gitlab.com/api/v4/mcp`) is **paywalled**:
Premium/Ultimate only — a free GitLab.com user is blocked at the endpoint (404,
per GitLab docs `Tier: Premium, Ultimate` and issue #579602). The only free
alternative was the third-party `@zereight/mcp-gitlab` npx server, which the
maintainer declined to auto-adopt (non-first-party). With no free first-party
option and no clear winner among the rest, the maintainer chose to **drop
gitlab-mcp for now** rather than ship a paywalled or third-party entry. (An earlier
cut of this addendum recorded the opposite — "prefer first-party even if beta,"
which had picked the official endpoint before the paywall was confirmed; that is
superseded by this corrected policy.)

## Considered alternatives

### Keep the env-var-reference model (github-mcp's first cut)

Rejected by the maintainer. It works and is headless-friendly (no browser), but it
is heavier than the product should be: it makes AgentLinux a credential broker,
couples each entry to a tool-specific auth scheme (and Sentry's `Sentry-Bearer`
already broke the hardcoded `Bearer` assumption), and adds secret-handling surface
for no benefit over letting the client own auth.

### Optional commented credential hint in the written config

Considered and dropped for register-only entries: even a commented hint is
tool-specific coupling, and the install-time pointer already tells the user how
auth completes. Keeping the on-disk entry a bare URL is the cleaner contract.
