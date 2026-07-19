# Phase 51: unified integration-QA remediation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `51-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-07-19
**Phase:** 51-unified integration-QA remediation
**Areas discussed:** Firecrawl authentication, hosted MCP/OpenCode compatibility, Playwright failures, system prerequisites, GSD/Codex integration, Gemini observation closure

---

## Firecrawl authentication

| Option | Description | Selected |
|--------|-------------|----------|
| Keep the current keyless-only promise | Treat the Phase 50 OAuth-only observation as a product failure but retain the existing claim without a second authentication path | |
| Test API-key URL first, then OAuth | Reproduce the documented API-key URL with a runtime-only key, then validate the bare endpoint's OAuth flow; make the final catalog contract match the working behavior | ✓ |
| Switch immediately to OAuth-only | Remove API-key investigation and make OAuth the only supported path | |

**User's choice:** Test the API-key approach one more time using Firecrawl's OAuth/MCP setup documentation; if that fails, find the correct OAuth path.

**Notes:** Firecrawl documentation was read during discussion. It documents both `https://mcp.firecrawl.dev/<API_KEY>/v2/mcp` and the bare endpoint with OAuth/dynamic client registration. Runtime credentials must not enter repository artifacts.

## Hosted MCP/OpenCode compatibility

| Option | Description | Selected |
|--------|-------------|----------|
| Skip OpenCode | Stop registering GitHub MCP into OpenCode when OAuth fails | |
| Keep registration and document the failure | Preserve fan-out but accept that the advertised OpenCode OAuth path may not work | |
| Debug and repair the root cause | Use current OpenCode diagnostics and OAuth discovery to fix the client, recipe, or compatibility issue while retaining OpenCode support | ✓ |

**User's choice:** OpenCode documentation claims dynamic client registration support, so investigate the root cause and address it properly. Skipping the integration is unacceptable.

**Notes:** OpenCode documentation was read during discussion. It documents automatic OAuth, dynamic registration, `opencode mcp auth`, stored auth state, and `opencode mcp debug`.

## Playwright failures

| Option | Description | Selected |
|--------|-------------|----------|
| Test only the observed commands | Add regressions for the recorded `click` and `fill` cases | |
| Universal action failure status | All unresolved action targets return nonzero while successful actions remain zero | ✓ |

**User's choice:** Yes — use the universal action failure-status contract.

## System prerequisites and runtime dependencies

| Option | Description | Selected |
|--------|-------------|----------|
| Leave prerequisites to the image/user | Keep `git`, Chrome, and browser libraries as documented manual prerequisites | |
| Automate dependency installation | Install through the agent user's apt/dnf access where possible; explicitly request sudo/root only when needed | ✓ |

**User's choice:** Make the dependencies automatic. The agent user already has package-manager access; if that is insufficient, request permission for sudo/root during dependency installation.

## GSD and Codex integration

| Option | Description | Selected |
|--------|-------------|----------|
| Keep the Codex skip | Preserve the current known incompatibility and document it | |
| Repair the current package only | Keep the old GSD package and patch its Codex configuration | |
| Upgrade to Open GSD and preserve Codex | Replace the old package with the latest official Open GSD release, verify Codex support, and repair any remaining incompatibility | ✓ |

**User's choice:** Update the GSD package to the latest Open GSD distribution, verify whether the problem remains, and fix it if necessary. Codex integration must not be skipped.

**Notes:** The official Open GSD repository was read during discussion. It advertises Codex support and currently lists v1.7.0 as its latest release; the exact release must be researched and pinned before implementation.

## Gemini observation closure

| Option | Description | Selected |
|--------|-------------|----------|
| Add speculative recovery | Add retry/stream handling despite the symptom not reproducing | |
| Close as unconfirmed | Re-run the corrected invocation, preserve the observation in the QA handback, and avoid an AgentLinux fix without a reproducible defect | ✓ |

**User's choice:** Close the Gemini symptom as unconfirmed.

## Scope selection and deferred ideas

All remediation areas were selected for discussion. The unrelated website PR-preview todo was reviewed and deferred. The systemd-dependent OpenClaw and Hermes workflows remain outside the Docker follow-up boundary.

## Canonical references added during discussion

- `https://docs.firecrawl.dev/developer-guides/mcp-setup-guides/oauth`
- `https://opencode.ai/docs/mcp-servers/#oauth`
- `https://github.com/open-gsd/gsd-core`
