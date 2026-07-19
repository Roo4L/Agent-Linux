# Phase 50 Integration QA Report

Date: 2026-07-18
Status: complete — available-scope stop gate met; 3 confirmed new findings and 1 unconfirmed observation recorded; two known issues and two expected boundary blocks recorded; Qwen and unavailable OAuth paths remain blocked; observation-only, no product fix

## Scope

This is an observation-only black-box QA campaign against the installed
AgentLinux catalog packages and realistic co-install workflows. It uses fresh
Docker release-candidate environments, with included-package coverage
performed on Ubuntu 24.04 and targeted checks performed on Ubuntu 22.04 and
26.04. It does not audit GSD files or the repository harness and does not claim
QEMU capability.

The campaign covered all 23 real entries: claude-code, gsd,
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
| Claude/model provider | provided for runtime trial | PKG-01, PTY-01, WF-01 | Tiny authenticated prompt |
| OpenAI/Codex account with usable quota | provided for runtime trial | PKG-04, WF-01 | Tiny Codex prompt; later `codex exec` path reproduced known K-001 config state |
| Google/Gemini access | provided for runtime trial | PKG-05, WF-01 | Tiny Gemini prompt |
| OpenCode provider | provided through OpenAI runtime | PKG-06, WF-01 | Tiny OpenCode prompt |
| Qwen OpenAI-compatible base URL and model | blocked — `OPENAI_BASE_URL` and `OPENAI_MODEL` still need to be declared; detected DashScope credential is intentionally not used | PKG-07, WF-01 | Tiny Qwen prompt using the user-selected OpenAI-compatible model |
| GitHub CLI read-only token | provided for runtime trial | PKG-10, WF-04 | Read-only repository/API query |
| GitHub MCP OAuth | blocked — static token is not substituted for the catalog's in-client OAuth path | PKG-17, WF-02 | GitHub MCP read-only tool |
| GitLab read-only account/token | blocked — user has no GitLab access for this campaign | PKG-11 | Read-only project/API query |
| Sentry read-only account/token or OAuth | blocked — user has no Sentry access for this campaign | PKG-14, PKG-18 | Read-only project/release query and Sentry MCP tool |
| Slack workspace OAuth/access | blocked — no in-client OAuth authorization supplied | PKG-20, WF-02 | Read-only channel/workspace query |
| Linear workspace OAuth/access | blocked — no in-client OAuth authorization supplied | PKG-21, WF-02 | Read-only issue/project query |
| Atlassian Cloud/Jira OAuth/access | blocked — no in-client OAuth authorization supplied | PKG-22, WF-02 | Read-only Jira/Confluence query |
| Context7 API key | not required for keyless idea | PKG-16, WF-05 | Keyless documentation lookup; optional key not requested |
| Firecrawl API key | provided for authenticated variant via runtime-only `FIRECRAWL_API` | PKG-19, WF-05 | Authenticated scrape operation; keyless variant remains blocked by F-004 |
| Local browser runtime | not a credential | PKG-03, PKG-15, WF-05, EDGE-01 | Local page/Chrome DevTools operation |

User action required: add the user-selected `OPENAI_BASE_URL` and
`OPENAI_MODEL` to the secure runtime file before the Qwen idea is attempted. The
values need to identify the OpenAI-compatible endpoint and model that the
provided OpenAI key can call; no model is assumed silently. Do not paste secret
values into this report or commit them. If a class is unavailable, its affected
ideas will be marked `blocked`, not clean. An unexpected credential request will
create a new blocked record and pause that path for another user checkpoint.

## Current activity and stop gate

Package operations ran in fresh Ubuntu 24.04, 22.04, and 26.04 RC containers.
The latest confirmed new finding is F-006, identified at 18:58:59 UTC. The
earlier F-006-based stop claim is invalid because GEMINI-READ-02 was recorded
as clean despite a visible invalid-stream error. That Gemini symptom was not
reproduced in two later authorized retries, so it is retained as unconfirmed
observation F-007 rather than used as a new-finding reset. After that
observation, the listed active intervals total 33 minutes 12 seconds
(6:41 + 9:00 + 3:00 + 7:00 + 6:00 + 1:31), exceeding the 30-minute threshold, and
the ledger has more than ten clean ideas, including two additional
credential-free lifecycle/workflow ideas recorded at 21:55–21:57 UTC. The later
Codex/GSD incompatibility was already
documented in the
catalog and is recorded only as known K-001; the reproduced Playwright
browser-library issue was already documented by the prior Phase 50 handoff and
is recorded only as known K-002. The documented Spec Kit `git` prerequisite and
the documented Chrome prerequisite are recorded as expected boundary blocks
B-001 and B-002; none of these resets or advances the clean-idea counter. User
waiting, usage limits, external credential blocks, and
harness-command corrections are excluded.

| Gate | Result | Basis |
|---|---|---|
| Productive time | met: 33 minutes 12 seconds after the F-007 observation (>=30 minutes; latest confirmed finding is F-006) | Active package install, real operations, reproductions, cleanup, stress runs, and analysis recorded across the listed 19:38–20:05, 21:51–21:57, and 22:16:47–22:18:18 UTC intervals; idle/user-wait intervals excluded |
| Latest-10 novelty gate | met: 10 distinct clean ideas after the F-007 observation, 0 new findings | The sequence below excludes the invalid Gemini idea and its retries; K-001, K-002, blocked ideas, known-issue replays, and harness corrections are excluded |
| Credential completeness | not met for all catalog paths | Qwen still needs `OPENAI_BASE_URL` + `OPENAI_MODEL`; GitLab, Sentry, GitHub MCP, Slack, Linear, and Atlassian OAuth paths remain explicitly blocked |

Qualifying clean-idea sequence after the F-007 observation (later clean ideas are listed in the
scenario ledger; this sequence is shown in completion order):

| Order | Idea | Result |
|---:|---|---|
| 1 | OPENCODE-READ-02 authenticated local-fixture read | clean |
| 2 | PLAYWRIGHT-FLOW-03 reopen, snapshot, eval, resize, screenshot, requests, close | clean |
| 3 | GH-WORKFLOW-02 authenticated API fields plus 404 path | clean |
| 4 | CLI-BOUNDARY-03 full/test inventory, invalid IDs, and shim check | clean |
| 5 | RTK-REWIRE-03 agent-hook convergence in a Git repository | clean |
| 6 | CONTEXT7-LIVE-02 fresh keyless lookup through Claude | clean |
| 7 | FIRECRAWL-SCRAPE-02 supplied-key scrape through Claude | clean (authenticated variant; keyless F-004 remains separate) |
| 8 | SPECKIT-RECOVERY-02 help, init, and project check | clean |
| 9 | RECONCILE-STRESS-01 repeated install-converge-remove cycles | clean |
| 10 | MCP-PAIR-01 combined Context7 and authenticated Firecrawl workflow | clean |

Additional non-gate clean observations included DIST-01, DIST-02,
BROWSER-STRESS-01, MCP-STRESS-01, FRESH-RC-01,
AGENT-WRITE-01, TOOLS-STRESS-01, FINAL-STATE-01, GSD-STRESS-01, and
BROWSER-STRESS-02. These are recorded in the scenario ledger; the final-state
and targeted-distro rows are not used as the ten-row gate because their
intervals are not bounded at idea granularity.

The available-scope stop gate is met, but the phase remains paused at the
credential checkpoint rather than silently declaring the blocked paths clean. Add `OPENAI_BASE_URL` and `OPENAI_MODEL` to
the secure runtime file to unlock Qwen Code; the other unavailable OAuth and
service paths remain recorded as blocked or excluded.

## Findings

| ID | Severity | Classification | Scope | Affected package/workflow | Exact redacted reproduction | First-seen idea | Evidence | Disposition | Residual risk |
|---|---|---|---|---|---|---|---|---|---|
| F-004 | medium | new | direct remote-MCP operation / adjacent catalog-to-upstream contract | `firecrawl-mcp` keyless path on Ubuntu 24.04 RC | After `agentlinux install firecrawl-mcp`, invoke Claude Code's `mcp__firecrawl-mcp__scrape` for `https://example.com` against the catalog's bare endpoint; the server exposes only `mcp__firecrawl-mcp__authenticate` and says OAuth is required, so no keyless scrape tool is available. | PKG-19 / WF-05 | `50-EVIDENCE.md#f-004--firecrawl-keyless-endpoint` (original: `/tmp/phase50-page/firecrawl.out`; authenticated variant redacted) | proposed Phase 50.2 follow-up: browser/MCP integration; keyless path blocked, authenticated variant passed; no fix during QA | The catalog's keyless scrape/search promise is not currently reproducible against the live endpoint, although a user-supplied URL-path key enables the scrape operation. |
| F-005 | medium | new | adjacent client compatibility / remote-MCP authentication | `github-mcp` through OpenCode | `opencode mcp list` registers the endpoint, but `opencode mcp auth github-mcp` exits through an authentication failure: the auth server does not support dynamic client registration. | WF-02 | `50-EVIDENCE.md#f-005--opencode-github-mcp-oauth` (original: `/tmp/phase50-opencode-github-auth.out`) | proposed Phase 50.3 follow-up: hosted-MCP OAuth compatibility; no fix during QA | Users of OpenCode cannot complete the documented GitHub MCP in-client OAuth path through the tested OpenCode release; Slack and other hosted MCP authorization paths remain blocked but are not included in this finding. |
| F-006 | medium | new | direct CLI error propagation | `playwright-cli` action commands on Ubuntu 24.04 RC | With a local page open, `playwright-cli fill textbox value` and `playwright-cli click missing-target` both print a target-resolution error but return status 0. | PKG-03 / EDGE-01 | `50-EVIDENCE.md#f-006--playwright-invalid-target-status` (original: `/tmp/phase50-page/missing-target-fill` and `missing-target-click`) | proposed Phase 50.4 follow-up: Playwright error-status propagation; no fix during QA | Scripts and agents that rely on the process status can continue after a failed browser action and report a false success unless they parse human-readable output. |
| F-007 | observation | observation | direct coding-agent operation | `gemini-cli` authenticated prompt on Ubuntu 24.04 RC | One real `gemini -p` local-fixture read emitted the expected marker, then ended with `[ERROR] Invalid stream: The model returned an empty response or malformed tool call`; two later authorized `--skip-trust` retries returned the expected marker without that error. | PKG-05 / GEMINI-READ-02 | `50-EVIDENCE.md#f-007--gemini-invalid-stream` (original: `/tmp/phase50-post-f007-gemini-read.out`; retries: `/tmp/phase50-current-qa/gemini-repro-02b.out` and `gemini-repro-02c.out`) | proposed Phase 50.5 follow-up: Gemini intermittent stream/error investigation; no fix during QA; not a confirmed new finding | A transient stream error may still occur under an unisolated provider/runtime condition, but this campaign did not reproduce it after correcting the trust precondition. |

No secret values are present in the evidence. A manual `git` installation was
used only inside the disposable container to continue downstream behavior
exploration; it does not change B-001 or make the original blocked install idea
clean.

## Follow-up routing

The QA run did not implement fixes or file Jira tickets. The approved unified
Phase 51 remediation phase is the follow-up handoff; no finding is silently
treated as resolved.

| Finding(s) | Destination | Follow-up scope |
|---|---|---|
| F-004 | Phase 51 | Browser/MCP discovery and live endpoint contract |
| F-005 | Phase 51 | Hosted-MCP OAuth compatibility |
| F-006 | Phase 51 | Playwright action error-status propagation |
| F-007 (observation) | Phase 51 | Gemini intermittent stream/error investigation |

## Expected boundary observations

These are explicit blocked paths, not product findings: each behavior matches a
prerequisite already documented by the package or phase contract. They are
neither new nor clean and do not advance the stop gate.

| ID | Package | Boundary | Evidence | Treatment |
|---|---|---|---|---|
| B-001 | `spec-kit` | Fresh-image install stops when system `git` is absent; the recipe prints the documented prerequisite command. | `50-EVIDENCE.md#b-001--spec-kit-git-prerequisite` | blocked/expected; downstream operation was explored only after a disposable container-only prerequisite setup |
| B-002 | `chrome-devtools-mcp` | MCP registration succeeds, but browser operation cannot start without separately installed Chrome at the expected path. | `50-EVIDENCE.md#b-002--chrome-runtime-prerequisite` | blocked/expected; explicit browser URL workaround was exploratory and not the default catalog path |

## Known issue reproductions

| ID | Existing issue | Reproduction and evidence | Stop-gate treatment |
|---|---|---|---|
| K-002 | Playwright bundled Chromium lacks required system libraries in the fresh RC image | `playwright-cli open http://127.0.0.1:8765` exits 1 with `libglib-2.0.so.0` missing. Durable excerpt: `50-EVIDENCE.md#k-002--playwright-browser-libraries`; original container artifact: `/tmp/phase50-findings/F-002-playwright-runtime.txt`. This replays the prior Phase 50 Playwright browser-runtime finding. | Known before this campaign; does not reset or advance the clean counter |
| K-001 | GSD Codex fan-out writes `[[hooks]]`, while Codex expects a `HooksToml` table | `codex exec` rejects the persisted config although `codex --version` succeeds; moving the disposable config aside allows the prompt. Durable excerpt: `50-EVIDENCE.md#k-001--gsdcodex-configuration-compatibility`; original artifacts: `/tmp/phase50-post-f006-agent-fleet-02.out`, `/tmp/phase50-post-f006-F007-codex-config.toml`, `/tmp/phase50-post-f007-codex-recheck.out` | Known before this campaign from `plugin/catalog/agents/gsd/install.sh`; neither resets nor advances the clean counter |

## Coverage limits

- Qwen's primary prompt remains blocked pending `OPENAI_BASE_URL` and
  `OPENAI_MODEL`; GitLab and Sentry CLI operations remain blocked because those
  accounts are unavailable.
- GitHub MCP, Sentry MCP, Slack, Linear, and Atlassian MCP operations remain
  blocked on in-client OAuth; the supplied GitHub token was used only for the
  separate `gh` CLI path.
- Docker cannot prove per-user systemd daemon behavior; openclaw and
  hermes-agent are excluded rather than passed.
- QEMU coverage is outside this Docker campaign and will not be inferred from
  host capabilities.
- Findings will be documented and routed after discovery; the campaign will
  not modify product source, recipes, tests, or documentation in response.
