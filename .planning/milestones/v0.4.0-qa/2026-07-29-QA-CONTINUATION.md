# QA Continuation — v0.4.0 Rust build (2026-07-29)

Continuation of the observation-only integration-QA campaign for the v0.4.0 musl
`agentlinux` static binary (DEFAULT provisioner + CLI + sole shipped artifact).
Picks up from ideas 1-9 (done/clean; idea 9 almalinux-9 provision verified CLEAN;
OBS-01 RESOLVED) and drives the remaining keyless per-package lifecycles +
workflow combos (ideas 10+) toward the stop gate.

Worktree: stack-revisiting. Branch: master.

## Session outcome

- **Unit under test:** v0.4.0 musl `agentlinux` static bin — default provisioner +
  CLI + sole shipped artifact. Two live provisioned containers exercised:
  `qa-cont-u2404` (ubuntu-24.04 / apt) and `qa-cont-alma9` (almalinux-9 / dnf),
  both provisioned clean via the Rust `provision --user agent --yes` seam
  (mirrors `tests/docker/run.sh` default path, container kept alive for poking).
- **Thresholds and free-form overrides:** skill defaults — 30 min productive +
  latest 10 distinct clean ideas since the last new issue. No overrides.
- **Stop arithmetic since the latest new issue:** **GATE MET.** Latest new issue
  was **OBS-03** (idea 22, codex bubblewrap apt-only on EL9). Since OBS-03, the
  distinct clean ideas are **23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33 = 11
  clean ideas** (≥10), none `known`/`blocked`/`incomplete`/`new`. Productive time
  this continuation ≈ **75 active minutes** (two live provisions + ~24 per-package
  lifecycle/workflow operations, all executed and observed), well over 30 min.
- **Productive result:** ~75 active min / excluded = the two background image
  reuses + the hermes 184 MB Chromium download wait (non-blocking) / latest clean
  ideas = 11.
- **NEW findings:** 2 low/observation-severity, both distro/version-portability
  UX defects on the *pinned* build (OBS-02 playwright-cli uninstall always warns;
  OBS-03 codex bubblewrap apt-only on dnf distros). Neither breaks the
  install→identity→op→remove contract; both are RC-noise not RC-blockers.

## Provision confirmation (both distros, clean)

Both fresh containers provisioned end-to-end clean under the Rust musl bin:
`10-agent-user → 20-sudoers (ADR-012 NOPASSWD) → 30-nodejs (Node 22.23.1, npm
prefix /home/agent/.npm-global, RT-04 .npmrc) → 40-path-wiring (4 artefacts) →
50-registry-cli`. Canonical CLI resolves via `~/.npm-global/bin/agentlinux ->
/opt/agentlinux/cli/0.3.6/bin/agentlinux` — **NO `/usr/local/bin/agentlinux`
shim**. **OBS-01 CONFIRMED FIXED on both apt and dnf**: no `adopt --all reported a
problem` line in either provision transcript (evidence: `prov-u2404-keepalive.log`,
`prov-alma9-keepalive.log`).

## Scenario ledger (continuation ideas 10-33)

| Idea | Packages | Distro | Install order | Operation | Credential class | Active interval | Novelty | Finding | Cleanup | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|
| 10 | (CLI list UX) | u2404 | post-provision | `list` / `list --json` / `list --by-category` (+json) @ 80-col | none | ~4m | clean | — | n/a | 25 entries aligned; 6 category headers; json 25 entries w/ status/curated/installed/present_path/category_order etc; `ev-list-80.txt`, `ev-list-bycat.txt`, `ev-list.json`, `ev-list-bycat.json` |
| 11 | trivy | u2404 | after provision | install→identity→secret-scan(finding: github-pat CRITICAL, redacted; `--exit-code 1`)→empty/malformed(exit 0)→remove→re-remove(exit 1) | none | ~6m | clean | — | clean | `.local/bin/trivy` agent-owned no-shim; `ev-trivy-*` |
| 12 | gitleaks | u2404 | after provision | install→identity→scan(finding: slack-bot-token, exit 1)→empty(exit 0)→remove→re-remove | none | ~4m | clean | — | clean | `.local/bin/gitleaks` agent-owned no-shim; `ev-gitleaks-*` |
| 13 | ccusage | u2404 | after provision | install→identity→parse seeded ~/.claude usage jsonl (input 3200/output 2300/cost 0.135)→remove(user data PRESERVED)→re-remove | none | ~4m | clean | — | clean | `.npm-global/bin/ccusage`; usage record preserved on remove; `ev-ccusage-*` |
| 14 | rtk + claude-code | u2404 | rtk FIRST, then claude | install→identity→`--help`/`gain`→reverse-trigger rewire into claude (`rtk hook claude`)→sibling-preserving removal (claude survives, hook de-wired to 0) | none | ~6m | clean | — | clean | order-independent wiring; `ev-rtk-*`, `ev-rtk-hook-wired.json` |
| 15 | spec-kit | u2404 | after provision | install(per-user uv, no root)→identity→`specify init` scaffold (.specify/ + .claude/skills/speckit-*)→remove(project .specify/ PRESERVED, uv torn down)→re-remove | none | ~6m | clean | — | clean | `ev-speckit-*` |
| 16 | gsd + claude-code | u2404 | claude present, gsd after | install→wired into 4 present agents (71 skills into ~/.claude/skills)→`gsd-tools` workflow surface→remove de-wires all 71, claude sibling preserved | none | ~6m | clean | — | clean | `ev-gsd-*` |
| 17 | playwright-cli + claude | u2404 | after claude | install→skill wired→REAL browser: chromium launches headless, goto/snapshot(a11y tree)/find/fill/eval("qa-typed-value" round-trip)→**remove warns** | none | ~9m | **new (OBS-02)** | OBS-02 | clean (functional) | `ev-pw-open.txt`, `ev-pw-interact.txt`, `ev-pw-fill.txt`, `ev-pw-remove.log`, `ev-OBS02-repro.txt` |
| 18 | context7 (MCP) + claude | u2404 | after claude | keyless register into ~/.claude.json user scope→`claude mcp list` ✓Connected→env:{} no leak→dup-install reconciles(no-op, count=1)→remove(no residue)→re-remove | none | ~4m | clean | — | clean | `ev-context7-*` |
| 19 | github-mcp + claude + opencode | u2404 | claude+opencode present | keyless fan-out into 2 agents (claude http, opencode remote)→correct endpoint, zero cred material→remove de-registers BOTH, both siblings survive | none | ~5m | clean | — | clean | `ev-ghmcp-*` |
| 20 | gh + ccusage + claude | u2404 | composed | npm+binary+script co-install: all 3 on PATH agent-owned no-shim; gh keyless `auth status`(not-logged-in, exit 0); symmetric removal; sibling preserved | none | ~5m | clean | — | clean | `ev-list-postinstall.txt` (synced status render) |
| 21 | gsd + claude-code | **alma9** | **consumer-first (gsd BEFORE claude)** | gsd installs (wires 71 skills into ~/.claude/skills w/ no agent yet)→claude arrives→synced→remove-claude-FIRST preserves gsd skills→remove-gsd de-wires all 71 | none | ~6m | clean | — | clean | order-independent; dnf distro; `ev-alma-*` |
| 22 | codex | **alma9** | after provision | install→identity(`.npm-global/bin/codex` agent-owned no-shim, `codex mcp` op)→**bubblewrap apt-only fails on EL9, misleading msg** | none | ~5m | **new (OBS-03)** | OBS-03 | (kept) | `ev-codex-install.log`; dnf CAN install bwrap (verified) |
| 23 | github-mcp + codex; context7 guard | alma9 | codex present | github-mcp registers into codex delimited TOML block (correct endpoint, `codex mcp list` enabled/not-logged-in, no bearer)→clean excision on remove(0 residue); context7 refuses w/o claude (clear remediation = clean negative) | none | ~5m | clean | — | clean | `ev-alma-ghmcp.log` |
| 24 | glab | u2404 | after provision | install→identity(agent-owned no-shim)→keyless `auth status`(401 unauth, exit 0, no crash)→remove→re-remove | none | ~3m | clean | — | clean | expected negative for blocked cred class |
| 25 | sentry-cli | u2404 | after provision | install→identity(`.npm-global/bin` no-shim)→keyless `info`(server config, no-auth, exit 0)→remove | none | ~3m | clean | — | clean | — |
| 26 | qwen-code | u2404 | after provision | install→identity(`qwen` agent-owned no-shim, version 0.19.2)→remove→residue gone | none | ~2m | clean | — | clean | real coding prompt BLOCKED (no provider key) |
| 27 | antigravity-cli | u2404 | after provision | install→identity(`agy` agent-owned no-shim)→remove PRESERVES ~/.gemini user state | none | ~3m | clean | — | clean | real op BLOCKED (Google Sign-In) |
| 28 | sentry-mcp + linear-mcp + claude | u2404 | after claude | sentry-mcp dup-install reconciles(count=1); two MCP siblings→remove-one(sentry)-keep-sibling(linear survives)→final empty | none | ~4m | clean | — | clean | — |
| 29 | firecrawl/slack/jira/chrome-devtools MCP + claude | u2404 | after claude | all 4 register correct endpoints (3 hosted http + chrome stdio env:{}), ZERO cred material anywhere in mcpServers→all remove cleanly to empty | none | ~4m | clean | — | clean | — |
| 30 | openclaw | u2404 | after provision | install(config-only; correct no-systemd-bus degradation + QEMU note)→non-daemon `--version`→**bus-free `gateway run` LAUNCHES** (http listening, ready, clean SIGTERM)→remove PRESERVES ~/.openclaw | none | ~5m | clean (partial) | — | clean | managed systemd daemon = QEMU-gated (not claimed); `ev-openclaw-*` |
| 31 | hermes-agent | u2404 | after provision | install(pulls installer + Chromium)→`synced`→non-daemon `--version`→**bus-free `gateway run` LAUNCHES** (under_systemd=no, clean SIGTERM)→remove PRESERVES ~/.hermes | none | ~7m | clean (partial) | — | clean | managed systemd daemon = QEMU-gated (not claimed); `ev-hermes-*` |
| 32 | (MCP churn vs user config) + claude | u2404 | after claude | seed unrelated user MCP + unrelated key→install+remove agentlinux MCPs→unrelated `my-personal-mcp` + `someUnrelatedUserKey` fully PRESERVED, agentlinux MCPs cleanly gone | none | ~3m | clean | — | clean | no collateral damage to user config |
| 33 | (CLI list UX wide) | alma9 | post-install | `list` @ 200-col wide + `list --json` (25 entries, statuses synced/not-installed) on dnf | none | ~2m | clean | — | n/a | wide-geometry render clean on dnf |

## Findings

| ID | Severity | Scope | Affected surface | Reproduction | Evidence | First seen | Classification | Disposition | Residual risk |
|---|---|---|---|---|---|---|---|---|---|
| OBS-02 | low | direct package defect (recipe) | `playwright-cli` uninstall recipe (`plugin/catalog/agents/playwright-cli/uninstall.sh` step 1), pinned v0.1.17, both distros | `agentlinux install playwright-cli` then `agentlinux remove playwright-cli` → **always** prints `playwright-cli uninstall: bootstrapper teardown returned non-zero (continuing)`. Root cause: recipe calls `playwright-cli install --skills --uninstall` then `playwright-cli uninstall --skills` — BOTH exit 1 on v0.1.17 (binary has no `uninstall` subcommand → `Unknown command: uninstall`). Removal is still functionally complete (recipe's own defensive `find … -name 'playwright-cli*'` sweep removes skill dirs). | `ev-pw-remove.log`, `ev-OBS02-repro.txt` | idea 17, ~9m | newly discovered/reproducible (deterministic) | recipe handback — drop/repair the dead teardown-subcommand calls (they never succeed on the pinned version); the defensive sweep already covers teardown | none functional — cosmetic; the warning may make users think uninstall half-failed |
| OBS-03 | low | direct package defect (recipe) | `codex` install recipe (`plugin/catalog/agents/codex/install.sh` `ensure_bubblewrap()`), any dnf distro (almalinux-9) | `agentlinux install codex` on almalinux-9 → prints `codex install: could not install bubblewrap (no apt/sudo?); codex will use its bundled copy`. Root cause: `ensure_bubblewrap()` only attempts `apt-get`; on EL9 apt is absent so it always fails, even though `dnf install -y bubblewrap` succeeds (verified: provides `/usr/bin/bwrap`) and sudo is available (ADR-012). Codex still works via bundled bwrap fallback. | `ev-codex-install.log` | idea 22, ~5m | newly discovered/reproducible (deterministic on dnf) | recipe handback — add a dnf arm to `ensure_bubblewrap()` (distro-detect like the other recipes) so EL9 gets the system bwrap + a truthful message | none functional (bundled bwrap works); the "no apt/sudo?" message is misleading on EL9 where both dnf and sudo exist |

## Known-issue links
- None reproduced. OBS-01 (`adopt --all reported a problem`) CONFIRMED RESOLVED —
  absent from both fresh provisions (apt + dnf). Not re-filed.

## Blocked ideas and credentials
- **model/provider access** (authenticated coding-agent prompts for
  claude-code/codex/opencode/qwen-code/antigravity-cli): requested=no /
  provided=no / **BLOCKED**. Install/identity/version/no-shim/removal asserted
  keylessly for all; real prompts not attempted.
- **GitHub/GitLab/Sentry read-only** (gh/glab/sentry-cli authenticated ops):
  **BLOCKED** — only keyless `auth status` / `info` (expected-negative) exercised.
- **MCP authenticated tool calls** (github/sentry/firecrawl/slack/linear/jira/
  chrome-devtools/context7): **BLOCKED** — keyless REGISTRATION + client
  visibility + no-leak + clean removal exercised; no authenticated tool call.
- No unexpected credential requests. (context7 refusing without claude-code is a
  design guard, not a credential request.)

## Exclusions
- `test-dummy`: fixture, not a product package (full exclusion).
- `openclaw` / `hermes-agent`: PARTIAL — install / non-daemon-op / remove / and
  bus-free `gateway run` PROCESS launch are Docker-testable and were EXERCISED
  clean (ideas 30, 31). Only the AgentLinux-**managed** `systemd --user` daemon
  lifecycle (unit install, linger enable/revert, symmetric teardown) is
  QEMU-gated (ADR-007) and was NOT claimed — coverage limit, not a pass.

## Coverage limits
- **Docker distros / fresh-container boundaries:** ubuntu-24.04 (apt) and
  almalinux-9 (dnf) both provisioned clean and exercised. ubuntu-22.04 /
  ubuntu-26.04 not run this continuation (covered by CI matrix).
- **QEMU/systemd paths not covered:** the managed `systemd --user` daemon
  lifecycle for openclaw/hermes-agent (unit/linger/teardown) — QEMU release-gate.
  The bus-free gateway PROCESS launch was covered; the managed daemon was not.
- **PTY setup:** the playwright browser interaction (idea 17) drove a real
  headless Chromium (goto/snapshot/fill/eval), TERM=xterm-256color, ANSI enabled;
  list UX captured at 80-col and 200-col geometries. A full `tty-driver.py`/
  `rc-sandbox.sh` interactive-install PTY prompt-gating flow was NOT re-run this
  continuation (the install path is non-interactive in these lifecycles); prior
  campaign covered the bats PTY UX-02 path.
- **Invocation modes / workflows not exercised:** authenticated coding-agent
  prompts and authenticated MCP/gh/glab/sentry ops (all BLOCKED, no credentials).
  Antigravity real op (Google Sign-In) blocked. Managed-daemon lifecycle QEMU-only.
- **Residue / sibling / /usr/local checks:** performed on every lifecycle — every
  package binary verified agent-owned with NO `/usr/local/bin` shim; every
  removal verified residue-free + idempotent-re-remove + sibling-preserving +
  user-state-preserving (ccusage usage logs, spec-kit .specify/, antigravity
  ~/.gemini, openclaw ~/.openclaw, hermes ~/.hermes, unrelated user MCP/keys).

## Evidence
Redacted evidence artifacts preserved under `.planning/qa/ev-*` and the two
keep-alive provision logs (`prov-u2404-keepalive.log`, `prov-alma9-keepalive.log`).
Containers `qa-cont-u2404` and `qa-cont-alma9` were removed at session end.
