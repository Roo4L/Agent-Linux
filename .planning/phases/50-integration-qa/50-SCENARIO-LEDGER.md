# Phase 50 Scenario Ledger

Generated from `plugin/catalog/catalog.json` on 2026-07-18. The catalog has 26
entries: 23 included product packages and exactly three explicit exclusions.
This ledger is an execution record, not a claim that a pending idea passed.

## Evidence contract

Every included package gets an install → path/version/ownership → meaningful
operation → remove → residue/sibling check. Each row records the productive
interval, novelty result, finding link, and cleanup result after execution. A
`blocked` row is not clean and cannot advance the stop gate. Evidence paths must
contain redacted output only.

| Field | Meaning |
|---|---|
| `idea` | One materially distinct user-facing hypothesis; repeated shell commands are not separate ideas. |
| `packages` / `distro` | Catalog IDs and fresh RC container under test. |
| `order` | Provider-first, consumer-first, or standalone lifecycle order. |
| `operation` | Real capability beyond `--help`/`--version`. |
| `credential` | Runtime credential class only; never a value. |
| `productive` | Bounded UTC interval for active execution, observation, analysis, or reproduction; user wait and external block are excluded. Older package rows use the bounded execution wave below; post-K-001 rows have per-idea intervals. |
| `novelty` | `pending`, `clean`, `known`, `new`, `observation`, `blocked`, or `incomplete`. |
| `finding` | New finding ID or an existing finding link; blank while pending. |
| `cleanup` / `evidence` | Removal, residue, sibling-preservation result, and redacted artifact path. |

## Included package lifecycle ideas

The package/version/source columns are copied from the catalog snapshot. Each
idea uses a fresh Ubuntu 24.04 RC container unless a targeted distro row says
otherwise. The default order is standalone; shared-surface rows add both
provider-first and consumer-first permutations where applicable.

| Idea | Package | Version / source | Distro/container | Operation hypothesis | Expected user-visible result | Credential | Order variations | Productive | Novelty | Finding | Cleanup / evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|
| PKG-01 | `claude-code` | 2.1.98 / script | Ubuntu 24.04 RC `agentlinux-rc` | PTY prompt against a tiny local fixture; observe streamed response and config ownership | Streamed response contains the exact fixture marker and the agent config remains owned by the agent user | Anthropic/model — provided | standalone; PTY 80-column and wider | 18:28–18:52 UTC (bounded wave) | clean | — | Authenticated default and 132-column PTY prompts returned exact markers; native remove/reinstall preserved `~/.claude.json`, settings, GSD/Playwright siblings; transcript observed during execution |
| PKG-02 | `gsd` | 1.37.1 / npm | Ubuntu 24.04 RC `agentlinux-rc` | Create a temporary GSD workflow, inspect generated phase/plan behavior, and remove without touching the fixture owner | Workflow files are generated for supported clients and the fixture owner remains untouched | none | standalone; consumer-first/provider-first with Claude Code | 18:28–18:52 UTC (bounded wave) | incomplete | K-001 (known) | Installed and wired Claude/OpenCode/Gemini/Qwen; Codex was intentionally skipped by the recipe. Generated files were verified for each wired client, but Gemini/Qwen workflow execution was not attempted after upstream `.claude`-path warnings; client-specific clean/known/incomplete details: `/tmp/phase50-after-f006/gsd-*.out`, `/tmp/phase50-post-f006-gsd-qwen.out` |
| PKG-03 | `playwright-cli` | 0.1.15 / npm | Ubuntu 24.04 RC `agentlinux-rc` | Launch a local page, perform a meaningful interaction, exercise valid and invalid action targets, and inspect returned state/status | Valid actions mutate/read the page; invalid actions produce a nonzero status | none | standalone; with GSD and a coding agent | 18:52–18:58 UTC (bounded wave) | new | F-006; K-002 (known) | Bundled Chrome launch failed on the fresh image because `libglib-2.0.so.0` was absent, replaying known K-002; after container-only runtime setup, valid interaction passed but `fill textbox value` and `click missing-target` printed errors with status 0 (`/tmp/phase50-page/missing-target-*`); no product fix applied |
| PKG-04 | `codex` | 0.142.3 / npm | Ubuntu 24.04 RC `agentlinux-rc` | Run a tiny authenticated prompt against a local fixture and inspect the agent-owned update/config path | Prompt returns the exact fixture marker and config/update paths remain agent-owned | OpenAI — provided | standalone; MCP provider-first/consumer-first | 18:28–18:52 UTC (bounded wave) | known | K-001 (known) | Initial authenticated ephemeral prompts passed; a later GSD/Codex configuration state made real `codex exec` fail while `codex --version` still passed; this is a known follow-up, not a clean idea; `/tmp/phase50-after-f006` prompt outputs and `/tmp/phase50-post-f007-codex-recheck.out` |
| PKG-05 | `gemini-cli` | 0.49.0 / npm | Ubuntu 24.04 RC `agentlinux-rc` | Run a tiny authenticated prompt and inspect interactive/non-interactive behavior | Prompt returns the exact fixture marker without a hang or trailing stream error | Google — provided | standalone; MCP provider-first/consumer-first | 19:38:09–19:38:19 UTC; rechecked 22:16–22:18 UTC | observation | F-007 | The original authenticated prompt emitted the marker and then an invalid-stream error, but two later authorized `--skip-trust` retries returned cleanly. F-007 remains an unconfirmed intermittent observation, not a confirmed new finding or gate reset; evidence `/tmp/phase50-post-f007-gemini-read.out`, `/tmp/phase50-current-qa/gemini-repro-02b.out`, and `gemini-repro-02c.out` |
| PKG-06 | `opencode` | 1.17.11 / npm | Ubuntu 24.04 RC `agentlinux-rc` | Run a tiny prompt through the OpenAI provider and inspect config, output, and cleanup | Prompt returns the exact fixture marker and config survives reinstall | OpenAI — provided | standalone; MCP provider-first/consumer-first | 18:28–18:52 UTC (bounded wave) | clean | — | OpenAI `gpt-5-mini` prompts returned exact markers; config preserved through remove/reinstall; `/tmp/phase50-after-f006` prompt outputs |
| PKG-07 | `qwen-code` | 0.19.2 / npm | Ubuntu 24.04 RC `agentlinux-rc` | Run a tiny prompt through the user-selected OpenAI-compatible endpoint/model | Prompt returns the exact fixture marker through the selected endpoint | OpenAI-compatible base/model — blocked pending `OPENAI_BASE_URL` + `OPENAI_MODEL` | standalone; MCP provider-first/consumer-first | 18:28–18:52 UTC (bounded wave) | blocked | — | Installed/removed and preserved `~/.qwen` configuration; real prompt remains blocked; do not substitute DashScope/native Qwen |
| PKG-08 | `ccusage` | 20.0.14 / npm | Ubuntu 24.04 RC `agentlinux-rc` | Parse seeded local usage records and inspect totals/empty/malformed input behavior | Totals match the seeded records and malformed input is handled without corrupting the fixture | none | standalone; after Claude usage fixture | 18:28–18:52 UTC (bounded wave) | clean | — | Correctly totaled seeded records, tolerated malformed trailing input, preserved the usage fixture, and removed cleanly; `/tmp/phase50-after-f006/devops-repo/ccusage.json` |
| PKG-09 | `rtk` | 0.42.4 / binary | Ubuntu 24.04 RC `agentlinux-rc` | Run representative commands through the hook/rewire flow and inspect output reduction | Hooks converge for supported agents and commands return usable reduced output | none | standalone; agent fleet permutations in WF-03 | 18:28–18:52 UTC (bounded wave) | clean | — | `ls`, `read`, `git status`, `grep`, and `rtk verify` passed; four compatible-agent hooks converged and were removed without deleting fixtures; `/tmp/phase50-after-f006/devops-repo/` |
| PKG-10 | `gh` | 2.95.0 / binary | Ubuntu 24.04 RC `agentlinux-rc` | Perform a read-only repository/API query and an empty/non-repository error path | Authenticated query returns expected repository data and the negative path fails nonzero | GitHub CLI token — provided | standalone; with scanner/workflow mix | 18:28–18:52 UTC (bounded wave) | clean | — | Authenticated `gh api` returned `cli/cli`; negative repository path failed nonzero; config and fixture survived removal; `/tmp/phase50-after-f006/devops-repo/gh-name` |
| PKG-11 | `glab` | 1.105.0 / binary | Ubuntu 24.04 RC `agentlinux-rc` | Perform a read-only project/API query if authorized; otherwise preserve explicit credential block | Authorized query returns project data; without access the block is explicit and nonzero | GitLab — unavailable | standalone | 18:28–18:52 UTC (bounded wave) | blocked | — | Installed, attempted `glab api user` (explicit unauthenticated block), and removed cleanly; no help-only substitution |
| PKG-12 | `trivy` | 0.71.2 / binary | Ubuntu 24.04 RC `agentlinux-rc` | Scan a small fixture with a known finding and an empty/clean fixture | Clean scan is zero/findings-free; synthetic secret scan is nonzero without secret leakage | none | standalone; with Gitleaks in WF-04 | 18:28–18:52 UTC (bounded wave) | clean | — | Clean fixture returned SchemaVersion 2; synthetic secret returned nonzero without leaking the token; removed with siblings preserved; `/tmp/phase50-after-f006/devops-repo/trivy.json` |
| PKG-13 | `gitleaks` | 8.30.1 / binary | Ubuntu 24.04 RC `agentlinux-rc` | Scan a fixture containing a synthetic secret pattern and a clean/empty repository | Clean scan passes and secret fixture is detected with a redacted report | none | standalone; with Trivy in WF-04 | 18:28–18:52 UTC (bounded wave) | clean | — | Clean and synthetic-secret scans behaved as expected with redacted report; removed with fixture preserved; `/tmp/phase50-after-f006/devops-repo/gitleaks.json` |
| PKG-14 | `sentry-cli` | 3.6.0 / npm | Ubuntu 24.04 RC `agentlinux-rc` | Perform the smallest read-only Sentry project/release operation if authorized | Authorized query returns project/release data; without access the block is explicit and nonzero | Sentry — unavailable | standalone | 18:28–18:52 UTC (bounded wave) | blocked | — | Installed, attempted `sentry-cli releases list` (explicit auth-token block), and removed cleanly; no help-only substitution |
| PKG-15 | `chrome-devtools-mcp` | 1.4.0 / MCP | Ubuntu 24.04 RC `agentlinux-rc` | Register into installed MCP-capable clients and use it against a local page | Client tools list/open the local page through the registered MCP server when the separately installed Chrome prerequisite is present | local browser; no static credential | standalone; Claude-only registration | 18:28–18:52 UTC (bounded wave) | blocked | — | Claude MCP health connected, but the supported Chrome prerequisite was absent at `/opt/google/chrome/chrome`; evidence `/tmp/phase50-page/chrome-mcp.out`; explicit `--browserUrl` workaround passed in `/tmp/phase50-after-f006/chrome-mcp-custom.out`; documented boundary B-002, not a product finding |
| PKG-16 | `context7` | 3.2.3 / MCP | Ubuntu 24.04 RC `agentlinux-rc` | Register and perform a keyless documentation lookup through a client | Client returns relevant documentation for a stable query | keyless | standalone; MCP fan-out permutations | 18:28–18:52 UTC (bounded wave) | clean | — | Duplicate install was a no-op; Claude performed a real keyless lookup; removal removed only Context7 and preserved client config; `/tmp/phase50-after-f006/context7.out` |
| PKG-17 | `github-mcp` | 1.5.0 / MCP | Ubuntu 24.04 RC `agentlinux-rc` | Register and make a client-visible read-only GitHub MCP call | Client exposes the registered GitHub tool and returns repository data after OAuth | GitHub in-client OAuth — blocked | provider-first/consumer-first fan-out | 18:28–18:52 UTC (bounded wave) | blocked | — | Registered into five MCP-capable clients (Claude, Codex, Gemini, OpenCode, Qwen), attempted client operation (OAuth block), and removed with sibling configs preserved |
| PKG-18 | `sentry-mcp` | 0.37.0 / MCP | Ubuntu 24.04 RC `agentlinux-rc` | Register and make a client-visible read-only Sentry MCP call | Client exposes the registered Sentry tool and returns project data after OAuth | Sentry in-client OAuth — unavailable | provider-first/consumer-first fan-out | 18:28–18:52 UTC (bounded wave) | blocked | — | Registered into five MCP-capable clients (Claude, Codex, Gemini, OpenCode, Qwen), health showed authentication required, and removed with sibling configs preserved |
| PKG-19 | `firecrawl-mcp` | 3.22.3 / MCP | Ubuntu 24.04 RC `agentlinux-rc` | Register and use keyless scrape/search against a stable local or public page, then retry with the user-supplied URL-path key | Keyless scrape returns page content as promised; supplied key returns page content | keyless path blocked; `FIRECRAWL_API` provided for authenticated variant | standalone; MCP fan-out permutations | 18:28–18:52 UTC (bounded wave) | new | F-004 | Keyless server exposed only OAuth (`/tmp/phase50-page/firecrawl.out`); authenticated custom runtime endpoint scraped Example Domain successfully (`/tmp/phase50-page/firecrawl-auth.out`); the authenticated variant passed, but the keyless behavior is the new finding and no keyless pass is claimed |
| PKG-20 | `slack-mcp` | 2026.2.17 / MCP | Ubuntu 24.04 RC `agentlinux-rc` | Register and make a client-visible read-only workspace/channel call | Client exposes the Slack tool and returns workspace data after OAuth | Slack OAuth — blocked | provider-first/consumer-first fan-out | 18:28–18:52 UTC (bounded wave) | blocked | — | Registered into five MCP-capable clients (Claude, Codex, Gemini, OpenCode, Qwen), health/auth path remained blocked, and removed with sibling configs preserved |
| PKG-21 | `linear-mcp` | 2025.5.1 / MCP | Ubuntu 24.04 RC `agentlinux-rc` | Register and make a client-visible read-only issue/project call | Client exposes the Linear tool and returns issue data after OAuth | Linear OAuth — blocked | provider-first/consumer-first fan-out | 18:28–18:52 UTC (bounded wave) | blocked | — | Registered into five MCP-capable clients (Claude, Codex, Gemini, OpenCode, Qwen), health required auth, and removed with sibling configs preserved |
| PKG-22 | `jira-atlassian-mcp` | 2026.2.4 / MCP | Ubuntu 24.04 RC `agentlinux-rc` | Register and make a client-visible read-only Jira/Confluence call | Client exposes the Atlassian tool and returns issue/page data after OAuth | Atlassian OAuth — blocked | provider-first/consumer-first fan-out | 18:28–18:52 UTC (bounded wave) | blocked | — | Registered into five MCP-capable clients (Claude, Codex, Gemini, OpenCode, Qwen), health required auth, and removed with sibling configs preserved |
| PKG-23 | `spec-kit` | 0.12.11 / script | Ubuntu 24.04 RC `agentlinux-rc` | Scaffold a temporary spec-driven project and inspect generated workflow files | Install succeeds on the fresh image; `specify check/init` creates the expected workflow and uninstall preserves user files | none | standalone; with GSD/coding agent | 18:28–18:52 UTC (bounded wave) | blocked | — | Initial fresh-container install stopped because the documented system `git` prerequisite is absent (`/tmp/phase50-findings/F-001-spec-kit-install.txt`); after the container-only prerequisite workaround, `specify check/init` succeeded and uninstall preserved `.specify/`; boundary B-001, not a product finding: `/tmp/phase50-after-f006/specify-*` |

## Workflow and interaction ideas

These are selected for shared surfaces and realistic user workflows, not an
arbitrary pairwise matrix. Each row requires both installation orders when
listed, reconciliation after each install, remove-one-keep-sibling checks, and
preservation of unrelated user configuration.

| Idea | Packages / workflow | Distro | Order | Exact hypothesis and operation | Credential | Productive | Novelty | Finding | Cleanup / evidence |
|---|---|---|---|---|---|---|---|---|---|
| WF-01 | coding-agent fleet + `gsd` + `playwright-cli` | 24.04 | agent-first and workflow-first | Install Claude/Codex/Gemini/OpenCode, then GSD/Playwright (and reverse); run a temporary plan, local browser interaction, and one provider prompt; check generated files and PATH | model credentials as available; Qwen blocked | 18:28–18:52 UTC (bounded wave) | new | F-006; K-002 (known) | Four authenticated agent prompts, GSD multi-client wiring/removal, and valid local browser interaction passed; K-002 was a known browser-library replay and F-006 was the new invalid-action finding; `/tmp/phase50-after-f006` |
| WF-02 | each MCP provider × Claude/Codex/Gemini/OpenCode/Qwen | 24.04 | provider-first and consumer-first | For every compatible provider, install before each client and after each client; rerun reconciliation; compare client registrations, duplicate resistance, unrelated entries, and remove-one-keep-sibling behavior | keyless where supported; OAuth paths blocked | 18:28–18:52 UTC (bounded wave) | new | F-005 | Registration syncs across five clients; captured OpenCode GitHub auth fails on unsupported dynamic client registration (`/tmp/phase50-opencode-github-auth.out`); Slack and remaining OAuth paths await authorization without a captured new finding; blocked portions do not advance the stop gate |
| WF-03 | `rtk` + installed coding-agent fleet | 24.04 | RTK-first and agent-first | Install RTK before and after each compatible agent; run representative commands, retain unrelated hook entries, reinstall, remove one sibling, and verify hook convergence | none | 18:28–18:52 UTC (bounded wave) | clean | — | Fleet hooks converged; representative compact commands and `rtk verify` passed; integrated reinstall/remove preserved scanner fixtures; `/tmp/phase50-after-f006/devops-repo/` |
| WF-04 | `trivy` + `gitleaks` + `gh` + `ccusage` + `rtk` | 24.04 | binary-first and npm-first | Create a temporary repository with synthetic scanner fixture; scan finding/clean cases, query GitHub read-only, parse seeded ccusage data, run an RTK command, compose outputs, repeat install, then remove one tool while preserving siblings | GitHub CLI token | 18:28–18:52 UTC (bounded wave) | clean | — | Integrated authenticated GitHub query, scanner finding/clean outputs, ccusage parse, RTK command, reverse removal, and fixture preservation passed; `/tmp/phase50-after-f006/devops-repo/` |
| WF-05 | MCP registrations + local browser | 24.04 | provider-first and consumer-first | Register Chrome DevTools, Context7, and Firecrawl; use local browser/keyless tools through a real client; inspect config scopes, repeated registration, and symmetric removal | keyless plus `FIRECRAWL_API` authenticated variant | 18:28–18:52 UTC (bounded wave) | new | F-004 | Default Chrome path was blocked by documented boundary B-002; Firecrawl keyless behavior produced F-004; explicit browser URL and runtime Firecrawl key variants passed and removed cleanly; `/tmp/phase50-after-f006/chrome-mcp-custom.out`, `firecrawl-auth.out` |
| WF-06 | `ccusage` + Claude fixture + GSD/spec-kit | 24.04 | workflow-first | Seed local usage data, parse it, scaffold a temporary spec/GSD workflow, inspect path/config ownership, and remove tools without deleting user workflow data | none | 18:28–18:52 UTC (bounded wave) | blocked | — | Usage parsing, GSD wiring/uninstall, and spec-kit scaffold/uninstall preservation passed after documented boundary B-001 was isolated; `/tmp/phase50-after-f006/ccusage.json`, `specify-*`, `gsd-*.out` |
| PTY-01 | Claude Code or another installed coding agent | 24.04 | standalone | Use `tests/bats/helpers/tty-driver.py` or equivalent PTY with `TERM=xterm-256color`, ANSI/color enabled, default 80 columns and a wider geometry; gate input on observed prompts and observe streamed output/apparent freezes | selected model credential | 18:28–18:52 UTC (bounded wave) | clean | — | Default PTY and 132×40 ANSI-enabled PTY prompts returned exact markers without hangs; session transcript recorded during execution |
| EDGE-01 | high-risk shared surfaces (`rtk`, GSD, Playwright, MCP) | 24.04 | each relevant order | Retry after malformed/empty input, repeat install, emulate interrupted/partial progress where safe, and verify atomic cleanup rather than merely rerunning help | per workflow | 18:28–18:52 UTC (bounded wave) | new | F-006 | `playwright-cli` invalid-target commands surfaced errors but returned 0; evidence `/tmp/phase50-page/missing-target-fill` and `missing-target-click`; valid retry/state lifecycle passed in `/tmp/phase50-after-f006/playwright-state-*` |

## Post-F-007-observation clean-idea detail (gate candidates)

The following rows are the clean sequence used for the final stop decision. They
exclude the K-001 reproduction, blocked credential paths, known-issue replays,
and commands that failed only because the disposable shell harness was written
incorrectly. Evidence is stored in the named disposable container; Firecrawl
transcripts were redacted to remove the URL-path credential before retention.

| Idea | Productive interval (UTC) | Operation | Novelty | Evidence / cleanup |
|---|---|---|---|---|
| OPENCODE-READ-02 | 19:38:19–19:38:36 | Authenticated OpenCode local-fixture read | clean | `50-EVIDENCE.md#gate-qualifying-clean-ideas` (original: `agentlinux-rc:/tmp/phase50-post-f007-opencode-read.out`); agent removed |
| PLAYWRIGHT-FLOW-03 | 19:39:32–19:39:36 | Reopen, snapshot, eval, resize, screenshot, request inspection, close | clean | `50-EVIDENCE.md#gate-qualifying-clean-ideas` (original: `agentlinux-rc:/tmp/phase50-post-f007-playwright-flow.out`); package removed |
| GH-WORKFLOW-02 | 19:40:22–19:40:25 | Authenticated user/repository/commit API reads plus nonexistent-repository error | clean | `50-EVIDENCE.md#gate-qualifying-clean-ideas` (original: `agentlinux-rc:/tmp/phase50-post-f007-gh-workflow.out`); package removed |
| CLI-BOUNDARY-03 | 19:41:39–19:41:40 | Full/test catalog inventory, invalid IDs, and forbidden shim check | clean | `50-EVIDENCE.md#gate-qualifying-clean-ideas` (original: `agentlinux-rc:/tmp/phase50-post-f007-catalog.json` and `catalog-test.json`); no package residue |
| RTK-REWIRE-03 | 19:42:31–19:42:34 | RTK hook verification and Git-repository commands with three agents | clean | `50-EVIDENCE.md#gate-qualifying-clean-ideas` (original: `agentlinux-rc:/tmp/phase50-post-f007-rtk-rewire.out`); repo fixture retained, packages removed |
| CONTEXT7-LIVE-02 | 19:42:54–19:43:32 | Fresh keyless Context7 lookup through authenticated Claude | clean | `50-EVIDENCE.md#gate-qualifying-clean-ideas` (original: `agentlinux-rc:/tmp/phase50-post-f007-context7-live.out`); MCP and Claude removed |
| FIRECRAWL-SCRAPE-02 | 19:43:52–19:44:18 | Supplied-key Firecrawl scrape through Claude | clean | `50-EVIDENCE.md#gate-qualifying-clean-ideas` (original: `agentlinux-rc:/tmp/phase50-post-f007-firecrawl-scrape.out`, redacted); temporary registration and package removed |
| SPECKIT-RECOVERY-02 | 19:45:03–19:45:04 | Help, init, and project check on an existing package workflow | clean | `agentlinux-rc:/tmp/phase50-post-f007-speckit-check.out`; `.specify/` retained, package removed |
| RECONCILE-STRESS-01 | 19:45:39–19:48:06 | Ten repeated Claude/Context7/RTK/ccusage install-converge-remove cycles | clean | `agentlinux-rc:/tmp/phase50-post-f007-reconcile-stress.out`; zero sentinel residue |
| MCP-PAIR-01 | 19:50:36–19:51:23 | Claude + Context7 lookup + authenticated Firecrawl scrape in one workflow | clean | `agentlinux-rc-order:/tmp/phase50-post-f007-mcp-pair.out` (redacted); all removed |
| BROWSER-STRESS-01 | 19:51:46–19:52:28 | Twenty valid Playwright eval/screenshot/request rounds plus tab lifecycle | clean | `agentlinux-rc:/tmp/phase50-post-f007-browser-stress.out`; package removed |
| MCP-STRESS-01 | 19:53:03–19:54:25 | Five repeated Claude/Context7/Chrome DevTools/Firecrawl registration cycles | clean | `agentlinux-rc:/tmp/phase50-post-f007-mcp-stress.out`; zero sentinel residue |
| FRESH-RC-01 | 19:54–19:57 | Fresh Ubuntu 24.04 RC install, Claude prompt, ccusage, scanners, reverse cleanup | clean | `agentlinux-rc-f007fresh:/tmp/phase50-post-f007-fresh-*`; redacted reports and zero sentinel residue |
| AGENT-WRITE-01 | 19:58:10–19:58:27 | Claude created and returned a marker in a disposable file | clean | `agentlinux-rc:/tmp/phase50-post-f007-agent-write.out`; agent removed |
| TOOLS-STRESS-01 | 20:00:51–20:03:01 | Eight repeated ccusage/Gitleaks/Trivy/Spec Kit/Playwright lifecycle cycles | clean | `agentlinux-rc:/tmp/phase50-post-f007-tools-stress.out`; zero sentinel residue |
| GSD-STRESS-01 | 20:03:32–20:03:39 | Four repeated GSD install/wire/remove cycles | clean | `agentlinux-rc:/tmp/phase50-post-f007-gsd-stress.out`; binary absent after cleanup |
| BROWSER-STRESS-02 | 20:04:00–20:05:16 | Fifty valid Playwright eval/screenshot rounds | clean | `agentlinux-rc:/tmp/phase50-post-f007-browser-stress-50.out`; package removed |
| QA-CRED-FREE-01 | 21:55:49–21:56:07 | Three ccusage/Gitleaks/Trivy install, real scan, JSON-output, and removal cycles against clean/synthetic fixtures | clean | `agentlinux-rc:/tmp/phase50-current-qa/idea-01.log`; all packages removed; reports retained; no leaks found |
| QA-CRED-FREE-02 | 21:56:26–21:56:44 | Two RTK Git-repository checks plus Spec Kit init/remove cycles with preserved `.specify/` output | clean | `agentlinux-rc:/tmp/phase50-current-qa/idea-02.log`; RTK/spec-kit removed; both `.specify/` projects retained |

## Additional non-gate observations

These observations are recorded for coverage context but are not part of the
ten-row stop gate because the targeted-distro rows and final-state pass use
broader activity intervals than a single test idea.

| Idea | Productive interval | Operation | Novelty | Evidence / cleanup |
|---|---|---|---|---|
| FINAL-STATE-01 | 19:58–20:05 UTC activity interval | Upgrade/pin reset, final inventory, and `/usr/local/bin` shim check | clean | `agentlinux-rc:/tmp/phase50-post-f007-final-state.out`; no installed sentinels |

## Targeted distro ideas

| Idea | Distro | Packages | Operation | Outcome / evidence |
|---|---|---|---|---|
| DIST-01 | Ubuntu 22.04 | `ccusage`, `gitleaks`, `context7`, Claude fixture | Fresh RC install, PATH/config/ownership checks, representative operation, removal and residue | clean; `agentlinux-rc-22`, `/tmp/qa22-ccusage`, gitleaks redacted scan, Context7 registration/removal |
| DIST-02 | Ubuntu 26.04 | `ccusage`, `gitleaks`, `context7`, Claude fixture | Fresh RC install, bootstrap/permission/PATH checks, representative operation, removal and residue | clean; `agentlinux-rc-26`, `/tmp/qa26-ccusage`, gitleaks scan, Context7 registration/removal |

## Explicit exclusions

| Catalog ID | Reason | Status |
|---|---|---|
| `openclaw` | Primary per-user systemd service is unavailable in the requested Docker environment | excluded; not pass/fail |
| `hermes-agent` | Primary per-user systemd service is unavailable in the requested Docker environment | excluded; not pass/fail |
| `test-dummy` | Test fixture, not a product package | excluded; not pass/fail |

## Container and activity record

Preparation uses `tests/docker/rc-sandbox.sh` and the real local RC installer
path. Build one release candidate, then use fresh containers for each
order-sensitive scenario. Full included coverage belongs on Ubuntu 24.04;
Ubuntu 22.04 and 26.04 are targeted only. Host-installed tools and the broad
behavior-suite runner are not package-QA evidence. QEMU/systemd daemon behavior
is outside this Docker ledger.

| Interval | Container / distro | Activity | Productive? | Exclusion reason if not |
|---|---|---|---|---|
| 18:28–18:52 UTC | Ubuntu 24.04 RC `agentlinux-rc` | Full package wave: no-auth tools, authenticated coding agents, MCP registration/real calls, spec-kit, Playwright, and first five findings | yes | active install, operation, observation, cleanup, and finding analysis |
| 18:52–18:58 UTC | Ubuntu 24.04 RC `agentlinux-rc` | MCP sibling removal, coding-agent removal/reinstall, PTY prompts, mixed scanner workflow, RTK workflow, Playwright valid/invalid actions | yes | F-006 discovered at 18:58:59 UTC; clean sequence reset |
| 18:59–19:06 UTC | Ubuntu 22.04 and 26.04 RC containers | Fresh targeted distro installs, ccusage, Gitleaks, Context7, Claude consumer ordering, cleanup | yes | active distro/package execution; no new finding |
| 19:06–19:15 UTC | Ubuntu 24.04 RC `agentlinux-rc` and fresh `agentlinux-rc-order` | Post-F-006 agent prompts, Context7, authenticated Firecrawl, Chrome MCP workaround, spec-kit follow-up, CLI edge checks, GSD cleanup, provider/consumer order, integrated DevOps workflow, Playwright state lifecycle | yes | workflow follow-up activity; no per-idea clean count claimed |
| 19:35–19:37 UTC | Ubuntu 24.04 RC `agentlinux-rc` | K-001 Codex execution failure reproduction, disposable config isolation, and real prompt recovery check | yes | known issue only; clean sequence and timer unchanged |
| 19:37–19:45 UTC | Ubuntu 24.04 RC `agentlinux-rc` | Coding-agent reads, the Gemini stream-error discovery, Playwright flow, GitHub API, RTK, Context7, Firecrawl authenticated variant, Spec Kit, and CLI boundary | yes | F-007 was discovered during this interval; later ideas are listed individually below and the invalid Gemini result is excluded from the clean count |
| 19:45–19:54 UTC | Ubuntu 24.04 RC plus Ubuntu 22.04/26.04 targeted containers | Reconciliation stress, targeted distro suites, combined MCP provider workflow, browser/MCP stress | yes | clean operations; blocked/OAuth and known-issue paths excluded from clean counter |
| 19:54–19:57 UTC | Fresh Ubuntu 24.04 RC `agentlinux-rc-f007fresh` | Real RC installer, Claude prompt, ccusage, Gitleaks, Trivy, and reverse cleanup | yes | fresh-state clean evidence; harness assertion correction excluded |
| 19:58–20:05 UTC | Ubuntu 24.04 RC `agentlinux-rc` | Claude file-write operation, tool lifecycle stress, final state/pin checks, GSD stress, and 50-round Playwright stress | yes | candidate clean sequence maintained; the earlier stop claim was invalidated by F-007 |
| 21:51–21:57 UTC | Ubuntu 24.04 RC `agentlinux-rc` | Reproduced the blocked Gemini retry, corrected F-007 evidence, ran credential-free package workflows, observed outputs, and verified final cleanup | yes | active QA reproduction, observation, analysis, and cleanup; no new finding |
| 22:16:47–22:18:18 UTC | Ubuntu 24.04 RC `agentlinux-rc` | Restored runtime-only Gemini credential injection, corrected the disposable trust precondition, and ran two authorized F-007 retries | yes | both retries returned the expected marker without the invalid-stream error; F-007 remains an unconfirmed observation |

The final report must show at least 30 minutes of productive activity and the
latest 10 distinct clean ideas with no newly discovered issue since the latest
new finding. A new reproducible issue resets both measures. Already-known issue
reproductions do not reset the post-finding timer or advance the clean counter,
but active reproduction and analysis are still productive work. Blocked ideas,
harness-only corrections, user wait, usage limits, idle chat, and external
blocks do not advance either measure. K-001 therefore does not alter the
post-F-007-observation clean-idea arithmetic, while its active interval remains part of the
productive-minute total.
