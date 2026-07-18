# Phase 50 Durable Evidence Excerpts

These are redacted excerpts retained from the disposable RC containers. They
preserve the user-visible result needed to audit the findings and stop gate
without retaining credentials or relying on a container's `/tmp` filesystem.

## K-002 — Playwright browser libraries (known before this campaign)

Source: `agentlinux-rc:/tmp/phase50-findings/F-002-playwright-runtime.txt`.

```text
finding=F-002
package=playwright-cli
command=playwright-cli open http://127.0.0.1:8765
error while loading shared libraries: libglib-2.0.so.0: cannot open shared object file
exit=1
```

This replays the existing browser-launch prerequisite issue documented by the
prior Phase 50 QA handoff; it is not a new finding in this run.

## B-001 — Spec Kit git prerequisite (expected boundary)

Source: `agentlinux-rc:/tmp/phase50-findings/F-001-spec-kit-install.txt`.

```text
package=spec-kit
command=agentlinux install spec-kit
git_path=absent
spec-kit install: git is required (uv installs Spec Kit from a git tag).
spec-kit: install.sh failed (exit 1)
```

## B-002 — Chrome runtime prerequisite (expected boundary)

Source: `agentlinux-rc:/tmp/phase50-page/chrome-mcp.out`.

Redacted replay: install `chrome-devtools-mcp`, then invoke Claude Code's
`mcp__chrome-devtools-mcp__list_pages` with no arguments and
`mcp__chrome-devtools-mcp__new_page` for the local HTTP fixture.

```text
The Chrome DevTools MCP server requires Google Chrome to be installed, but it's
not found at the expected path (/opt/google/chrome/chrome).
Both list_pages and new_page return the same error.
```

The explicit `--browserUrl http://127.0.0.1:9222` workaround succeeded; that
workaround is not claimed as the default catalog workflow.

## F-004 — Firecrawl keyless endpoint

Sources: `agentlinux-rc:/tmp/phase50-page/firecrawl.out` and the redacted
authenticated transcript.

Redacted replay: install `firecrawl-mcp`, then ask Claude Code to call
`mcp__firecrawl-mcp__scrape` for `https://example.com` against the catalog's
bare endpoint. The supplied-key variant used the same target through a
runtime-only URL-path credential, which is omitted here.

```text
The Firecrawl MCP server requires OAuth authentication before its scraping
tools become available; no keyless scrape tool is available.
```

The runtime-only user-supplied URL-path key enabled an authenticated scrape of
Example Domain. The key itself is intentionally absent here.

## F-005 — OpenCode GitHub MCP OAuth

Source: `agentlinux-rc:/tmp/phase50-opencode-github-auth.out`.

```text
Authentication failed
Incompatible auth server: does not support dynamic client registration
```

This finding is limited to the captured GitHub MCP authentication attempt.
Slack and other hosted MCP paths remain blocked without captured OAuth output.

## F-006 — Playwright invalid-target status

Sources: `agentlinux-rc:/tmp/phase50-page/missing-target-fill` and
`missing-target-click`.

```text
### Error
Error: "textbox" does not match any elements.
process status: 0
```

The `fill textbox value` and `click missing-target` actions both printed a
target-resolution error while returning status zero.

## F-007 — Gemini invalid stream (unconfirmed observation)

Source: `agentlinux-rc:/tmp/phase50-post-f007-gemini-read.out`.

```text
GEMINI_READ_POST_F007 label: QA-λ
[ERROR] Invalid stream: The model returned an empty response or malformed tool call.
```

The real authenticated prompt emitted the marker and then a visible stream
error. The first later retry was blocked because the disposable runtime no
longer had the provided Gemini credential. After restoring runtime-only
credential injection and using Gemini's documented `--skip-trust` option for
the disposable container, two retries completed without the error:

```text
GEMINI_REPRO_02
GEMINI_REPRO_02
phase50 gemini reproducibility fixture
```

The two clean retries are retained at `/tmp/phase50-current-qa/gemini-repro-02b.out`
and `gemini-repro-02c.out`. F-007 remains an unconfirmed intermittent
observation, not a confirmed new finding and not a stop-gate reset.

## K-001 — GSD/Codex configuration compatibility

Sources: the catalog-documented reproduction and
`agentlinux-rc:/tmp/phase50-post-f006-agent-fleet-02.out`.

```text
Error loading config.toml: invalid type: sequence, expected struct HooksToml in hooks
```

The catalog recipe already skips the incompatible GSD `--codex` fan-out. This
reproduction is known, not new, and neither resets nor advances the clean-idea
counter.

## Gate-qualifying clean ideas

The first ten qualifying clean ideas after the F-007 observation completed in this order:
OpenCode local read, Playwright valid flow, GitHub API workflow, catalog
boundary check, RTK rewire, Context7 lookup, authenticated Firecrawl scrape,
Spec Kit recovery after the known prerequisite replay, reconciliation stress,
and the combined MCP pair. The Gemini idea is intentionally absent because it
surfaced F-007.
The corresponding per-idea intervals and container provenance remain in
`50-SCENARIO-LEDGER.md`.

The following redacted excerpts preserve the invocation shape, user-visible
result, and cleanup assertion for each gate candidate. Secret-bearing values,
temporary paths, and full transcripts are omitted or replaced with markers.

| Order / idea | Redacted invocation and input | User-visible result | Cleanup assertion |
|---:|---|---|---|
| 1 — OPENCODE-READ-02 | `opencode run 'Read [fixture] and reply with marker AL-QA-OPENCODE'` | OpenCode response contained `AL-QA-OPENCODE` | OpenCode package removed; provider config retained |
| 2 — PLAYWRIGHT-FLOW-03 | `playwright-cli open [local URL]; snapshot; eval; resize 1024 768; screenshot; requests; close` | Page reopened, DOM/eval/resize/screenshot/request inspection all returned expected results | Browser state closed and package removed |
| 3 — GH-WORKFLOW-02 | `gh api user`; `gh api repos/cli/cli`; `gh api repos/cli/cli/commits?per_page=1`; nonexistent repository read | Authenticated fields returned; the deliberate nonexistent-repository request failed nonzero as expected | `gh` removed; config and repository fixture retained |
| 4 — CLI-BOUNDARY-03 | `agentlinux list --json`; full/test catalog inventory; invalid package IDs; forbidden `/usr/local/bin` shim scan | JSON inventory and category boundaries were valid; invalid IDs failed; no forbidden shims or residue remained | Catalog package wave removed; no package residue |
| 5 — RTK-REWIRE-03 | `rtk verify`; `ls`; `read`; `git status`; `grep` in a temporary Git repository with three agents | Hooks converged and representative commands returned usable output | RTK and agents removed in sibling-preserving order; repository fixture retained |
| 6 — CONTEXT7-LIVE-02 | Claude `mcp__context7__resolve-library-id` followed by `mcp__context7__get-library-docs` for a stable library query | Keyless Context7 returned documentation content | Context7 registration and Claude package removed; unrelated config retained |
| 7 — FIRECRAWL-SCRAPE-02 | Claude Firecrawl scrape call for `https://example.com` through the runtime-only supplied URL-path key (redacted) | Authenticated scrape returned Example Domain content; no key was printed in the transcript | Temporary registration and Firecrawl package removed |
| 8 — SPECKIT-RECOVERY-02 | After a container-only `git` prerequisite workaround: `specify check`; `specify init [temporary project]`; inspect generated workflow | `specify check/init` completed and generated the expected `.specify/` workflow | `spec-kit` removed; project `.specify/` directory retained |
| 9 — RECONCILE-STRESS-01 | Ten repeated Claude/Context7/RTK/ccusage install-converge-remove cycles | All cycles converged without sentinel residue | Package wave removed; fixture retained |
| 10 — MCP-PAIR-01 | Claude + Context7 lookup + authenticated Firecrawl scrape in one workflow | Both MCP calls returned expected content; all registrations reconciled | All packages and temporary registrations removed |

Additional qualifying clean ideas completed after the first ten:

| Idea | Redacted invocation | User-visible result | Cleanup assertion |
|---|---|---|---|
| QA-CRED-FREE-01 | Three `agentlinux install` / scan / JSON-output / `agentlinux remove` cycles for ccusage, Gitleaks, and Trivy | Usage totals returned; Gitleaks reported no leaks for the fixture; Trivy secret scan completed; catalog list stayed valid | All three packages removed; reports and fixture retained |
| QA-CRED-FREE-02 | Two RTK repository checks plus two `specify init` / remove cycles | RTK checks completed; Spec Kit projects initialized successfully | RTK and Spec Kit removed; both generated `.specify/` directories retained |

## Durable lifecycle evidence index

This compact redacted index is the durable lifecycle handback for every
included package. It preserves the user-visible operation result and the
install/remove/residue assertion after the disposable RC containers were
cleaned up. The `/tmp` paths in the scenario ledger are supplemental original
artifacts, not the sole record of these outcomes.

| Package | Redacted lifecycle excerpt | Result / residue assertion |
|---|---|---|
| `claude-code` | Authenticated PTY prompt returned a fixture marker at 80 and 132 columns | Agent-owned config survived removal/reinstall; package removed |
| `gsd` | Temporary workflow files appeared for Claude, OpenCode, Gemini, and Qwen; Codex fan-out was skipped by the recipe | GSD content removed from supported agent paths; fixture and unrelated config retained; Codex compatibility is known K-001 |
| `playwright-cli` | Local page snapshot/eval/resize/screenshot/request lifecycle passed; invalid `fill textbox` and `click missing-target` printed errors with status 0 | Browser state and package removed; F-006 recorded; bundled-library K-002 replayed |
| `codex` | Authenticated local-fixture prompt passed before the known GSD/Codex config state was exercised | Package removed; agent config preserved; K-001 recorded as known/non-clean |
| `gemini-cli` | Original prompt showed marker plus invalid-stream error; two later authorized `--skip-trust` retries returned markers cleanly | Package removed; F-007 retained as unconfirmed observation, not a confirmed new finding |
| `opencode` | OpenAI-backed local-fixture prompts returned exact markers | Provider configuration survived remove/reinstall; package removed |
| `qwen-code` | Install, version/path, config-preservation, and removal passed; real prompt was not attempted without the requested OpenAI-compatible endpoint/model | Package removed; real operation remains blocked, not clean |
| `ccusage` | Seeded usage records produced expected totals and malformed trailing input did not corrupt the fixture | Package removed; usage fixture retained |
| `rtk` | `rtk verify`, `ls`, `read`, `git status`, and `grep` returned usable reduced output with three-agent hook convergence | Hooks and binary removed in sibling-preserving order; repository fixture retained |
| `gh` | Authenticated `gh api` user/repository/commit reads returned expected fields; deliberate nonexistent-repository read failed nonzero | Package removed; auth config and fixture retained |
| `glab` | `glab api user` reached the explicit unauthenticated block because GitLab access was unavailable | Package removed; no help-only pass claimed |
| `trivy` | Clean fixture scan completed; synthetic secret fixture produced the expected finding without leaking the token | Package removed; scan reports and fixture retained |
| `gitleaks` | Clean and synthetic-secret repository scans returned expected outcomes with redacted reports | Package removed; fixture retained |
| `sentry-cli` | Read-only release operation reached the explicit authentication block because Sentry access was unavailable | Package removed; no help-only pass claimed |
| `chrome-devtools-mcp` | MCP registration/health connected; browser calls could not discover the separately installed Chrome required by the catalog contract, while an explicit browser URL workaround passed | Registration removed; B-002 expected boundary retained; local page retained |
| `context7` | Claude resolved a stable library and retrieved documentation through the keyless MCP path | Registration and package removed; unrelated client configuration retained |
| `github-mcp` | Five-client registration converged; client-visible read remained blocked on in-client OAuth | Registrations removed with sibling configs preserved; blocked, not clean |
| `sentry-mcp` | Five-client registration converged; health required unavailable OAuth | Registrations removed with sibling configs preserved; blocked, not clean |
| `firecrawl-mcp` | Bare endpoint exposed OAuth-only behavior; supplied runtime URL-path key returned Example Domain content | Registration/package removed; F-004 recorded for keyless behavior; key-bearing transcript redacted |
| `slack-mcp` | Five-client registration converged; read-only operation remained blocked on Slack OAuth | Registrations removed with sibling configs preserved; blocked, not clean |
| `linear-mcp` | Five-client registration converged; read-only operation remained blocked on Linear OAuth | Registrations removed with sibling configs preserved; blocked, not clean |
| `jira-atlassian-mcp` | Five-client registration converged; read-only operation remained blocked on Atlassian OAuth | Registrations removed with sibling configs preserved; blocked, not clean |
| `spec-kit` | Fresh install stopped with absent `git`; after a container-only prerequisite setup, `specify check/init` generated the expected project workflow | Package removed while `.specify/` projects were retained; B-001 expected boundary retained |

### Canonical path, ownership, and shim index

The following durable index records where each included package or registration
landed, who owned it, and whether a forbidden `/usr/local/bin` wrapper was
observed. All package paths were owned by `agent`; MCP registrations were
written to the user-scoped client configuration owned by `agent`.

| Package | Canonical path/config | Owner | `/usr/local/bin` shim |
|---|---|---|---|
| `claude-code` | `/home/agent/.local/bin/claude` | `agent` | none observed |
| `gsd` | `/home/agent/.npm-global/bin/get-shit-done-cc` | `agent` | none observed |
| `playwright-cli` | `/home/agent/.npm-global/bin/playwright-cli` | `agent` | none observed |
| `codex` | `/home/agent/.npm-global/bin/codex` | `agent` | none observed |
| `gemini-cli` | `/home/agent/.npm-global/bin/gemini` | `agent` | none observed |
| `opencode` | `/home/agent/.npm-global/bin/opencode` | `agent` | none observed |
| `qwen-code` | `/home/agent/.npm-global/bin/qwen` | `agent` | none observed |
| `ccusage` | `/home/agent/.npm-global/bin/ccusage` | `agent` | none observed |
| `rtk` | `/home/agent/.local/bin/rtk` | `agent` | none observed |
| `gh` | `/home/agent/.local/bin/gh` | `agent` | none observed |
| `glab` | `/home/agent/.local/bin/glab` | `agent` | none observed |
| `trivy` | `/home/agent/.local/bin/trivy` | `agent` | none observed |
| `gitleaks` | `/home/agent/.local/bin/gitleaks` | `agent` | none observed |
| `sentry-cli` | `/home/agent/.npm-global/bin/sentry-cli` | `agent` | none observed |
| `chrome-devtools-mcp` | Claude Code user-scope registration in `~/.claude.json` | `agent` | none observed |
| `context7` | Claude Code user-scope registration in `~/.claude.json` | `agent` | none observed |
| `github-mcp` | user-scope registrations in `~/.claude.json`, `~/.codex/config.toml`, `~/.gemini/settings.json`, `~/.qwen/settings.json`, and `~/.config/opencode/opencode.json` | `agent` | none observed |
| `sentry-mcp` | user-scope registrations in `~/.claude.json`, `~/.codex/config.toml`, `~/.gemini/settings.json`, `~/.qwen/settings.json`, and `~/.config/opencode/opencode.json` | `agent` | none observed |
| `firecrawl-mcp` | user-scope registrations in `~/.claude.json`, `~/.codex/config.toml`, `~/.gemini/settings.json`, `~/.qwen/settings.json`, and `~/.config/opencode/opencode.json` | `agent` | none observed |
| `slack-mcp` | user-scope registrations in `~/.claude.json`, `~/.codex/config.toml`, `~/.gemini/settings.json`, `~/.qwen/settings.json`, and `~/.config/opencode/opencode.json` | `agent` | none observed |
| `linear-mcp` | user-scope registrations in `~/.claude.json`, `~/.codex/config.toml`, `~/.gemini/settings.json`, `~/.qwen/settings.json`, and `~/.config/opencode/opencode.json` | `agent` | none observed |
| `jira-atlassian-mcp` | user-scope registrations in `~/.claude.json`, `~/.codex/config.toml`, `~/.gemini/settings.json`, `~/.qwen/settings.json`, and `~/.config/opencode/opencode.json` | `agent` | none observed |
| `spec-kit` | `/home/agent/.local/bin/specify` (uv tool) | `agent` | none observed |

### Durable workflow and distro excerpts

| Idea | Redacted result | Cleanup / boundary |
|---|---|---|
| `WF-01` coding-agent fleet + GSD + Playwright | Four authenticated agent prompts, GSD wiring/removal, and valid browser interaction were observed; F-006 and K-002 remain recorded | Sibling configs and temporary workflow data preserved; no product fix |
| `WF-02` MCP fan-out | Provider-first and consumer-first registration converged across compatible agents; OpenCode GitHub OAuth produced F-005 | All provider registrations removed; unavailable OAuth paths remain blocked |
| `WF-03` RTK + agent fleet | Hook convergence, representative repository commands, reinstall, and sibling removal passed | RTK artifacts removed without deleting repository fixtures |
| `WF-04` scanner/VCS/workflow mix | Authenticated `gh`, Trivy/Gitleaks clean/finding scans, ccusage, RTK, repeated install, and reverse removal passed | Siblings and fixtures retained; all packages removed |
| `WF-05` MCP + browser | Context7 and authenticated Firecrawl passed; the documented Chrome prerequisite blocked the default browser path and keyless Firecrawl behavior produced F-004 | Temporary registrations removed; explicit workaround evidence retained |
| `WF-06` usage + GSD/spec-kit | Usage parsing, workflow wiring, and Spec Kit project preservation passed after the documented `git` prerequisite was isolated as B-001 | User workflow directories retained; packages removed |
| `DIST-01` Ubuntu 22.04 | Fresh RC install, ownership/PATH checks, ccusage/Gitleaks/Context7 operations, and removal passed | Container cleaned; no QEMU/systemd claim |
| `DIST-02` Ubuntu 26.04 | Fresh RC install, bootstrap/ownership/PATH checks, ccusage/Gitleaks/Context7 operations, and removal passed | Container cleaned; no QEMU/systemd claim |
