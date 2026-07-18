# Phase 50 Integration QA Report

Date: 2026-07-18
Status: credential checkpoint — package operations not started

## Scope

This is an observation-only black-box QA campaign against the installed
AgentLinux catalog packages and realistic co-install workflows. It uses fresh
Docker release-candidate environments, with full included-package coverage
planned for Ubuntu 24.04 and targeted checks planned for Ubuntu 22.04 and
26.04. It does not audit GSD files or the repository harness and does not claim
QEMU capability.

Included package ideas will cover all 23 real entries: claude-code, gsd,
playwright-cli, codex, gemini-cli, opencode, qwen-code, ccusage, rtk, gh, glab,
trivy, gitleaks, sentry-cli, chrome-devtools-mcp, context7, github-mcp,
sentry-mcp, firecrawl-mcp, slack-mcp, linear-mcp, jira-atlassian-mcp, and
spec-kit.

Explicit exclusions are openclaw and hermes-agent because their primary
systemd services are unavailable in the requested Docker environment, plus
test-dummy because it is a fixture rather than a product package.

## Credential matrix and checkpoint

Only credential class and status are recorded here; no secret values are stored.
`requested` means the user checkpoint has been raised and the status is awaiting
runtime authorization. Credential-dependent ideas remain blocked until their
real operation is authorized and exercised.

| Credential class | Status | Affected idea IDs | Minimal operation |
|---|---|---|---|
| Claude/model provider | requested | AGT-01, WF-01, MCP-01..08 | Tiny authenticated prompt or client-visible MCP read-only call |
| OpenAI/Codex account with usable quota | requested | AGT-02, WF-01, MCP-01..08 | Tiny Codex prompt and MCP client visibility/read-only call |
| Google/Gemini access | requested | AGT-03, WF-01, MCP-01..08 | Tiny Gemini prompt and MCP client visibility/read-only call |
| OpenCode provider | requested | AGT-04, WF-01, MCP-01..08 | Tiny OpenCode prompt and MCP client visibility/read-only call |
| Qwen provider | requested | AGT-05, WF-01, MCP-01..08 | Tiny Qwen prompt and MCP client visibility/read-only call |
| GitHub read-only account/token or OAuth | requested | DEV-01, MCP-02, WF-02 | Read-only repository/API query and GitHub MCP read-only tool |
| GitLab read-only account/token | requested | DEV-02 | Read-only project/API query |
| Sentry read-only account/token or OAuth | requested | DEV-05, MCP-03 | Read-only project/release query and Sentry MCP tool |
| Slack workspace OAuth/access | requested | MCP-06 | Read-only channel/workspace query |
| Linear workspace OAuth/access | requested | MCP-07 | Read-only issue/project query |
| Atlassian Cloud/Jira OAuth/access | requested | MCP-08 | Read-only Jira/Confluence query |
| Context7 API key | not required for keyless idea | MCP-04 | Keyless documentation lookup; optional key not requested |
| Firecrawl API key | not required for keyless idea | MCP-05 | Keyless scrape/search operation; key-gated tools are separate |
| Local browser runtime | not a credential | BROWSER-01, MCP-01 | Local page/Chrome DevTools operation |

User action required: provide or authorize only the credential classes above
that should be tested, through runtime injection into the disposable test
environment. Do not paste secret values into this report or commit them. If a
class is unavailable, its affected ideas will be marked `blocked`, not clean.
An unexpected credential request will create a new blocked record and pause that
path for another user checkpoint.

## Current activity and stop gate

No package operation has started. Productive time: 0 minutes. Clean-idea
sequence: 0. The default stop gate is 30 minutes of productive activity plus
the latest 10 distinct completed ideas without a newly discovered issue since
the latest finding. User waiting time is excluded from both measures.

## Coverage limits

- Credentialed model, VCS, Sentry, Slack, Linear, and Atlassian operations are
  blocked pending runtime authorization.
- Docker cannot prove per-user systemd daemon behavior; openclaw and
  hermes-agent are excluded rather than passed.
- QEMU coverage is outside this Docker campaign and will not be inferred from
  host capabilities.
- Findings will be documented and routed after discovery; the campaign will
  not modify product source, recipes, tests, or documentation in response.
