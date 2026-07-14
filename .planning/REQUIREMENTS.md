# Requirements — v0.3.6 Catalog Expansion

**Milestone goal:** Grow the AgentLinux catalog from 3 entries to 26 of the most trusted/popular AI-agent-community tools — *availability only* (CAT-02 holds: nothing installed by default) — so first-release users don't hit "I miss tool X."

**Selection method:** gates+scoring funnel (agent-relevance · clean per-user install + symmetric uninstall, no root, no `/usr/local` shim · free license · liveness ≤6mo release & ≤3mo commits · maturity), then owner curation. Research + audit trail: `.planning/research/v0.3.6/` (to be migrated from session scratchpad).

**Contract:** every requirement below carries ≥1 bats @test (catalog `install` → `post_install_verify` → symmetric `remove`, no residue) per the project's TST-07 phase-close gate, **plus an OPS-01 operational smoke that runs the tool in a real (minimal) scenario** — "installs cleanly" is necessary but not sufficient. Each tool is pinned per ADR-011 (pins in Appendix A). Credentials needed for operational smokes are catalogued in Appendix C. One tool per phase (phases 23–49).

---

## v0.3.6 Requirements

### Machinery enablers (catalog capability additions; each folded into its first-consumer phase)

- [x] **ENABLE-01**: Catalog supports a **prebuilt-binary** entry kind — fetches a pinned release, verifies its checksum, installs the binary to `~/.local/bin` (agent-owned, no root, no `/usr/local` shim), and `remove` deletes the binary + its config/cache symmetrically.
- [x] **ENABLE-02**: Catalog supports **MCP-server** entries — `install` registers via `claude mcp add --scope user` (npx-stdio and remote-http shapes) into every installed MCP-capable client; `remove` deregisters symmetrically. **Governing convention (ADR-017, locked 2026-07-13): MCP entries are THIN CLIENT-CONFIG INSTALLERS — register the BARE server (URL for remote; launch command for stdio-only), bake NO credential (no literal, no env-var reference, no header), and let the user authenticate IN-CLIENT (in-client OAuth for remote servers). Prefer the hosted/remote endpoint wherever one exists; stdio is a fallback for npx-only tools. `requires_secret` remains a documentation flag ("needs in-client auth"); `secret_env` is dropped from register-only entries. The install prints a one-line "authenticate in your client" pointer.** Supersedes the credential-injection approach in the first github-mcp cut (now retrofitted). *(Phase 34 delivers the npx-stdio shape + `source_kind: "mcp"` + the `requires_secret`/`secret_env` schema convention; the secret-instruction path is first exercised by Phase 35 (context7); the **remote-http shape + a shared cross-agent registration helper (fan-out into claude-code/codex/gemini-cli/opencode/qwen-code) landed early in Phase 36 (github-mcp)** — pulled forward from the tentative Phase 42 slot per the maintainer's cross-agent decision — and Phase 42 (linear-mcp) adds only the OAuth-login nuance on top.)*
- [ ] **ENABLE-03**: Catalog supports **Python+uv** entries via a per-user `uv` bootstrap (`~/.local/bin`, no root); install via `uv tool`/`uvx`, with symmetric uninstall.
- [ ] **ENABLE-04**: Catalog supports **AI-assistant daemon** entries — `install` sets up a per-user background service; `remove` tears it down symmetrically (no stray daemon, unit, or state).
- [x] **ENABLE-05**: **Self-updater coexistence** — for catalog tools that ship a built-in self-updater, AgentLinux's pinned version stays authoritative (in-app updater disabled or documented; the pin is not silently clobbered). Re-exercises the AGT-02 canonical concern. *(Phase 23 — codex `check_for_update_on_startup=false`)*
- [ ] **ENABLE-06**: `agentlinux list` groups catalog entries by **category/tags** (coding-agent · mcp · devops · token/workflow · assistant).
- [ ] **ENABLE-07**: **Catalog growth kit** — a contributor recipe template + the selection-rubric doc are published so a new entry can be added without touching CLI source (extends CAT-03).
- [x] **ENABLE-08**: **Passive autoupdate freeze** — for catalog tools that *auto-install* updates in the background (not merely notify), the install recipe disables that passive self-update via the tool's own **launch-mode-independent** config, so the catalog pin is never silently replaced out of band. The **explicit, user-initiated** update path (`agentlinux upgrade`, the tool's own `upgrade` command, or an npm reinstall) must stay functional — only the passive path is frozen. Strengthens ENABLE-05 by distinguishing three updater classes: **auto-install ⇒ must freeze** — opencode (`~/.config/opencode/opencode.json` → `autoupdate:false`), gemini-cli + qwen-code (`settings.json` → `general.enableAutoUpdate:false`); **notify-only ⇒ no freeze needed** — codex (`check_for_update_on_startup=false` applied anyway as belt-and-braces per ENABLE-05); **no updater** — ccusage. Why it matters: a passive auto-install re-introduces the canonical AGT-02 hazard (and on a non-agent-owned prefix qwen-code's auto-update silently migrates the tool off npm onto a curl|bash binary). Empirically verified under AgentLinux: an interactive session auto-bumped gemini-cli N-1→latest with **no** freeze, and stayed pinned **with** the freeze; the explicit npm update still bumped with the freeze in place. *(Phases 24–26; codex Phase 23 via ENABLE-05.)*

### Cross-agent skill wiring (cross-cutting — applies to skill-provider entries)

- [x] **WIRE-01**: A catalog entry that installs **skills/commands** for one coding agent must wire them into **every other shipped coding agent for which the concept applies** — so a tool installed via AgentLinux is lit up across the whole installed agent fleet, not just Claude Code. **Order-independent**: the wiring is applied unconditionally at the *provider's* install time (writing each target agent's own config dir), so an agent installed *later* still finds the skills present; `remove` tears the wiring down symmetrically across all targets. Applicability is classified per (provider, target): **DIRECT** (drop or convert into the target's extension dir) or **N/A** (target has no comparable extension host — documented, never silently skipped). Current providers:
  - **GSD** (`get-shit-done-cc`, a natively multi-runtime bootstrapper): wired into Claude Code, opencode (`~/.config/opencode/command/gsd-*.md`), gemini-cli (`~/.gemini/commands/gsd/`), codex (`~/.codex/skills/gsd-*`), qwen-code (`~/.qwen/skills/gsd-*`) — GSD owns the per-tool format conversion.
  - **playwright-cli**: skill mirrored into the cross-tool `~/.agents/skills/playwright-cli/` (the scan path **both** codex and opencode honor); opencode additionally reads `~/.claude/skills/` natively. gemini-cli + qwen-code: **N/A** (prompt-command host only — a multi-file skill with a `references/` tree does not round-trip to a single command prompt).

### Operational verification (cross-cutting — applies to every catalog entry)

- [ ] **OPS-01**: Beyond install / `post_install_verify` / symmetric remove, **every catalog entry ships a minimal real-operation smoke test** that exercises the tool's primary function under AgentLinux, as the agent user — proving the tool actually *operates correctly*, not merely that its binary resolves. Rules:
  - **Real but minimal** — one small operation (cheapest model, smallest input, shortest run); cost and time kept negligible.
  - **Auth at runtime only** — any required provider credential is supplied via the environment at test time, **never** baked into a recipe, the catalog, the image, or a commit (preserves CAT-02 + the secret-free contract; the recipe still bakes nothing). Credential matrix: Appendix C.
  - **Credential-absent ⇒ skip** — the functional smoke `skip`s cleanly when its required credential env var is unset, so credential-free CI and contributors stay green; it must **run and pass** when the credential is present (locally, or in a secrets-enabled CI job).
  - **No-auth tools run unconditionally** against seeded/local data (e.g. ccusage parses a seeded `~/.claude` usage record and prints a cost table; offline scanners scan a fixture).
  - **Phase-close gate (extends TST-07):** a phase is *done* only once its OPS-01 smoke has been run + passed at least once with the relevant credential, recorded in the phase SUMMARY.
  - Minimal real scenario by category: **coding-agent CLI** → one tiny non-interactive prompt, assert a sensible model reply; **MCP server** → register, confirm it appears live (`claude mcp list` / a trivial tool call), deregister; **DevOps CLI** → one real read-only/offline op (e.g. `trivy fs`/`gitleaks detect` on a fixture; `gh api` / `glab` a read with a token); **token/workflow** → one real local op (ccusage on seeded usage; spec-kit scaffolds a temp project; etc.); **AI-assistant daemon** → start → health/ping → stop.

### Coding-agent CLIs (npm)

- [x] **AGT-05**: `agentlinux install opencode` installs opencode (npm `opencode-ai`); CLI resolves on PATH; passive autoupdate frozen (ENABLE-08); `remove` is symmetric.
- [x] **AGT-06**: `agentlinux install gemini-cli` installs Gemini CLI (npm `@google/gemini-cli`, bin `gemini`); passive autoupdate frozen (ENABLE-08); symmetric remove.
- [x] **AGT-07**: `agentlinux install codex` installs OpenAI Codex (npm `@openai/codex`); self-updater coexistence (ENABLE-05) verified — pin survives; symmetric remove.
- [x] **AGT-08**: `agentlinux install qwen-code` installs Qwen Code (npm `@qwen-code/qwen-code`, bin `qwen`); passive autoupdate frozen (ENABLE-08); symmetric remove.

### MCP servers

- [x] **MCP-01**: `agentlinux install chrome-devtools-mcp` registers the Chrome DevTools MCP server (npx, no secret); requires Chrome present (documented); `remove` deregisters.
- [x] **MCP-02**: `agentlinux install context7` registers Context7 (npx `@upstash/context7-mcp`); optional `CONTEXT7_API_KEY` handled per ENABLE-02 (registered keyless, install prints the optional key instruction, key never baked); symmetric residue-free remove.
- [x] **MCP-03**: `agentlinux install github-mcp` registers the GitHub hosted MCP server (**remote-http**, `https://api.githubcopilot.com/mcp/` — **never** the Docker recipe) into **every installed MCP-capable agent** (claude-code, codex, gemini-cli, opencode, qwen-code) via the shared cross-agent helper; symmetric multi-agent remove, no residue. *(Phase 36 folds in the ENABLE-02 **remote-http** shape + the shared cross-agent MCP registration helper, reused by 37/42/43. **Retrofitted to ADR-017 thin-installer**: registers the bare URL, bakes NO credential — the user authenticates in-client via GitHub OAuth; the first-cut env-var-reference PAT was removed.)*
- [x] **MCP-04**: `agentlinux install sentry-mcp` registers Sentry's **hosted remote** MCP (`https://mcp.sentry.dev/mcp`) into every installed MCP-capable agent via the shared helper — **thin installer per ADR-017**: bare URL, no credential; the user authenticates in-client (Sentry OAuth). Symmetric residue-free remove. FSL-1.1-ALv2 license recorded. *(chose the hosted-remote shape over npx-stdio; reuses the Phase 36 remote-http helper.)*
- [ ] **MCP-05** *(DROPPED 2026-07-13 — deferred)*: gitlab-mcp not shipped. GitLab's official hosted MCP endpoint is **paywalled** (Premium/Ultimate; free GitLab.com users 404), and the maintainer declined the free third-party `@zereight/mcp-gitlab`. Per the corrected ADR-017 source-selection policy (free first-party = auto; everything else = per-case review), no entry was shipped. Revisit if GitLab frees the endpoint.
- [ ] **MCP-06** *(DROPPED 2026-07-14 — deferred)*: brave-search-mcp not shipped. The "free tier" premise is falsified — Brave removed the card-free Search API tier in Feb 2026; new users get only a metered ~$5/mo credit (~1,000 queries) requiring a **mandatory credit card as a live billing instrument** (no spend cap on overages) + a Brave-attribution condition. Per the corrected ADR-017 source-selection policy (free first-party = auto; everything else = per-case review) the maintainer dropped it — same gate gitlab-mcp (MCP-05) failed. Server itself is official + MIT + a clean thin-installer fit; revisit if Brave restores a genuine no-card free tier.
- [x] **MCP-07**: `agentlinux install firecrawl-mcp` registers Firecrawl MCP into every installed MCP-capable agent as a **bare KEYLESS hosted remote-http URL** `https://mcp.firecrawl.dev/v2/mcp` (ADR-017 thin installer; prefer-hosted supersedes the roadmap's npx-stdio plan); NO credential baked (`requires_secret: false`, no `secret_env`); `install` prints the optional personal-key upgrade pointer; symmetric residue-free remove. `pinned_version 3.22.3`, MIT. Firecrawl **cleared** the free-tier gate that gitlab (MCP-05) + brave (MCP-06) failed (card-free recurring 1,000 credits/month). Covered by `tests/bats/62-catalog-firecrawl-mcp.bats` (MCP-07).
- [x] **MCP-08**: `agentlinux install slack-mcp` registers Slack's **official first-party hosted MCP** into every installed MCP-capable agent as a **bare remote-http URL** `https://mcp.slack.com/mcp` (ADR-017 thin installer; supersedes the roadmap's third-party `slack-mcp-server` npx + stealth-token plan — using the official admin-governed endpoint sidesteps the xoxc/xoxd governance-bypass footgun); NO credential baked (`requires_secret: true` doc flag, no `secret_env`, no Slack token in any config); `install` prints the in-client Slack-OAuth pointer; symmetric residue-free remove. `pinned_version 2026.2.17` (GA date), no package license (proprietary hosted). Free for workspace members (no paywall). Covered by `tests/bats/63-catalog-slack-mcp.bats` (MCP-08).
- [x] **MCP-09**: `agentlinux install linear-mcp` registers the official Linear MCP into every installed MCP-capable agent as a **bare remote-http URL** `https://mcp.linear.app/mcp` (ADR-017 thin installer). NO credential baked (`requires_secret: true` doc flag, no `secret_env`, no `lin_api_`/`lin_oauth_` token in any config); `install` prints the in-client Linear-OAuth pointer; `remove` deregisters symmetrically (nothing to log out — no AgentLinux-held token). `pinned_version 2025.5.1` (GA date), no package license (proprietary hosted). Free-tier usable (MCP not paid-plan-gated). The roadmap's `claude mcp login/logout` driving is superseded by ADR-017. Covered by `tests/bats/64-catalog-linear-mcp.bats` (MCP-09).
- [x] **MCP-10**: `agentlinux install jira-atlassian-mcp` registers the official Atlassian Rovo MCP into every installed MCP-capable agent as a **bare remote-http URL** `https://mcp.atlassian.com/v1/mcp/authv2` (Streamable-HTTP; **cloud-only**; Jira + Confluence at GA, more rolling out). ADR-017 thin installer: NO credential baked (`requires_secret: true` doc flag, no `secret_env`, no `ATATT`/`ATCTT` token in any config); `install` prints the in-client Atlassian-OAuth pointer + cloud-only note; `remove` deregisters symmetrically (no token to log out). `pinned_version 2026.2.4` (GA date), `license Apache-2.0` (official repo). Free-tier usable (500 calls/hr; not paid-plan-gated). The roadmap's `logout` step is superseded by ADR-017. Covered by `tests/bats/65-catalog-jira-atlassian-mcp.bats` (MCP-10).

### DevOps / git / observability CLIs (prebuilt binary, ENABLE-01)

- [x] **DEVT-01**: `agentlinux install gh` installs GitHub CLI (binary → `~/.local/bin`); remove drops the binary and preserves `~/.config/gh` (auth) per CAT-04 — consistent with every other authenticated agent; only `--purge` wipes it.
- [x] **DEVT-02**: `agentlinux install glab` installs GitLab CLI (binary, from `gitlab-org/cli` — **not** the archived `profclems/glab`); remove drops the binary and preserves `~/.config/glab` (auth) per CAT-04.
- [x] **DEVT-03**: `agentlinux install sentry-cli` installs Sentry CLI (npm `@sentry/cli` or binary); symmetric remove. *(FSL — Appendix B.)*
- [x] **DEVT-04**: `agentlinux install trivy` installs Trivy (binary); fs/repo scans need no Docker; symmetric remove (+ `~/.cache/trivy`).
- [x] **DEVT-05**: `agentlinux install gitleaks` installs Gitleaks (binary); symmetric remove.

### Token / context / workflow tools

- [x] **WORK-01**: `agentlinux install ccusage` installs ccusage (npm; read-only cost reporter); symmetric remove.
- [x] **WORK-02**: `agentlinux install rtk` installs RTK / Rust Token Killer (**prebuilt binary, source-pinned to `rtk-ai/rtk` — never `cargo install rtk`** = the crates.io "Rust Type Kit" collision); optional `rtk init` hook into `~/.claude` is opt-in with symmetric `--uninstall`; `remove` reverts binary + hook.
- [ ] **WORK-03**: `agentlinux install spec-kit` installs GitHub Spec Kit (`specify-cli` via uv, ENABLE-03); symmetric remove (+ project `.specify/` documented as user-owned).
- [ ] **WORK-04**: `agentlinux install claude-flow` installs Claude-Flow (npm); `remove` cleans its full footprint (`.claude`/`.swarm`/`.hive-mind`, MCP regs, hooks) symmetrically.
- [ ] **WORK-05**: `agentlinux install bmad` installs BMAD-METHOD (npm `bmad-method`); symmetric remove of installed agents/packs.

### AI assistants (daemon-class, ENABLE-04)

- [ ] **ASST-01**: `agentlinux install openclaw` installs OpenClaw (npm + per-user daemon); `remove` tears down the daemon + state symmetrically. Self-updater coexistence per ENABLE-05.
- [ ] **ASST-02**: `agentlinux install hermes-agent` installs Hermes Agent (curl installer + per-user daemon/gateway); symmetric teardown.

---

## Future Requirements (deferred — backlog with scores)

- **Platform-deploy CLIs** (deselected this milestone): wrangler, vercel, netlify-cli, flyctl, supabase, stripe-cli — agent-driven deploys; re-open when there's demand.
- **Secret-injection CLIs**: doppler, 1Password `op` (proprietary).
- **Re-openable uv tools** (now that ENABLE-03 exists): llm (simonw), claude-monitor, gptme, and uvx MCP servers (time, fetch, aws-docs).
- **Additional coding agents** revisited as they mature: cline, continue, crush, forge, goose, OpenHands.
- **Additional MCP servers**: notion, sequential-thinking, memory, sqlite (when bus factor improves), playwright-mcp (if the playwright-cli overlap is resolved).

## Out of Scope (explicit exclusions, with reasoning)

- **aider** — fails liveness gate (no release in ~10.5 months; commits tapering).
- **claude-code-router** — no LICENSE file (legal blocker until licensed).
- **task-master-ai** — MIT + Commons Clause (not OSI / not freely redistributable).
- **terraform** — BUSL-1.1 (source-available, not OSS); `opentofu` would be the OSS alternative if IaC is ever in scope (also deferred).
- **playwright-mcp** — overlaps the existing `playwright-cli` entry + needs root for browser system-deps.
- **filesystem-MCP, git-MCP** — redundant with Claude Code's built-in Read/Edit/Glob and Bash+git.
- **puppeteer-MCP** — deprecated/archived, unpatched advisory.
- **jq / ripgrep / fd / lazygit / k9s / delta / difftastic** — general OS tooling (apt-shipped) or human-facing TUIs, not autonomous-agent tools.
- **Amp** — proprietary + paid account (vendor lock).
- **act / dagger** — hard Docker-daemon dependency.

---

## Appendix A — Pinned-version candidates (ADR-011; verified 2026-06-28)

opencode `opencode-ai@1.17.11` · gemini-cli `@google/gemini-cli@0.49.0` · codex `@openai/codex@0.142.3` · qwen-code `@qwen-code/qwen-code@0.19.2` · ccusage `ccusage@20.0.14` · rtk `rtk-ai/rtk@0.42.4` (binary) · gh `2.95.0` · glab `1.105.0` · sentry-cli `@sentry/cli@3.6.0` · trivy `0.71.2` · gitleaks `8.30.1` · chrome-devtools-mcp `1.4.0` · context7 `@upstash/context7-mcp@3.2.2` · github-mcp `1.5.0` · sentry-mcp `@sentry/mcp-server@0.36.0` · gitlab-mcp `@zereight/mcp-gitlab@2.1.27` · brave-search-mcp `@brave/brave-search-mcp-server@2.0.85` · firecrawl-mcp `firecrawl-mcp@3.22.3` (hosted-remote; pin = validated release) · slack-mcp `mcp.slack.com` official hosted (pin GA date 2026.2.17) · linear-mcp `mcp.linear.app` official hosted (pin GA date 2025.5.1) · jira-atlassian-mcp `mcp.atlassian.com/v1/mcp/authv2` official hosted (pin GA date 2026.2.4, Apache-2.0) · spec-kit `specify-cli@0.11.9` · claude-flow `claude-flow@3.14.4` · bmad `bmad-method@6.9.0` · openclaw `openclaw@2026.6.10` · hermes-agent `2026.6.19` (curl).

## Appendix B — License flags

FSL-1.1 (source-available, not OSI; converts to MIT/Apache after 2 yrs), passes the "free to use" gate but flag if an OSI-only catalog is ever required: **sentry-cli** (FSL-1.1-MIT), **sentry-mcp** (FSL-1.1-Apache). All others MIT/Apache-2.0 (verified LICENSE files; some show GitHub `NOASSERTION` but are MIT: openclaw, bmad, ccusage).

## Appendix C — Operational-smoke credentials (OPS-01)

Credential each tool's minimal real op needs. **Supplied at runtime via env only — never baked into a recipe, catalog, image, or commit.** Each smoke `skip`s when its var is unset.

**Coding-agent CLIs (cluster, Phases 23–27):**

| Tool | Env var(s) | Notes / minimal op |
|------|-----------|--------------------|
| codex | `OPENAI_API_KEY` | OpenAI's own CLI — OpenAI key required. Op: `codex exec` a one-line prompt with a cheap model. |
| gemini-cli | `GEMINI_API_KEY` | Google AI Studio — **free tier**. Op: `gemini -p "…"`. |
| qwen-code | `DASHSCOPE_API_KEY` *or* `OPENAI_API_KEY`+`OPENAI_BASE_URL`+`OPENAI_MODEL` | Native Qwen (DashScope free quota) or any OpenAI-compatible endpoint. Op: `qwen -p "…"`. |
| opencode | any one of `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / OpenRouter key | Provider-agnostic — reuse a key already supplied. Op: `opencode run "…"`. |
| ccusage | **none** | Read-only; smoke seeds a synthetic `~/.claude` usage record and asserts a cost table. |

**Minimal set to cover the cluster:** `OPENAI_API_KEY` (codex + opencode + qwen via OpenAI-compat) **+** `GEMINI_API_KEY` (free; gemini-cli). Add `DASHSCOPE_API_KEY` only to test qwen against native Qwen models.

**Later phases (recorded so they aren't re-litigated):** github-mcp/gh → `GITHUB_TOKEN` (read PAT) · gitlab-mcp/glab → `GITLAB_PERSONAL_ACCESS_TOKEN` (`read_api`) · context7 → optional `CONTEXT7_API_KEY` (free tier) · brave-search-mcp → `BRAVE_API_KEY` (free) · firecrawl-mcp → `FIRECRAWL_API_KEY` · sentry-cli/sentry-mcp → `SENTRY_AUTH_TOKEN` · slack-mcp → official hosted, in-client Slack OAuth (admin-approved), no static key (roadmap's third-party xoxp/xoxc plan superseded) · linear-mcp → official hosted, in-client Linear OAuth, no static key (ADR-017: recipe registers bare URL, does NOT drive `claude mcp login`) · jira-atlassian-mcp → official hosted, in-client Atlassian OAuth, no static key (ADR-017: bare URL, no `logout` driving; cloud-only) · trivy/gitleaks/rtk/spec-kit/claude-flow/bmad → **no credential** (offline/local ops) · openclaw/hermes-agent → reuse a provider key (`OPENAI_API_KEY`/`ANTHROPIC_API_KEY`).

---

## Traceability

Each v0.3.6 requirement maps to exactly one phase (phases 23–49). 🔧 = enabler folded into its first-consumer phase. **Coverage: 33/33 mapped, 0 orphans.**

| Requirement | Phase | Tool / Deliverable | Status |
|-------------|-------|--------------------|--------|
| AGT-07 | Phase 23 | codex 🔧 | Done |
| ENABLE-05 | Phase 23 | self-updater coexistence 🔧 | Done |
| AGT-06 | Phase 24 | gemini-cli | Done |
| AGT-05 | Phase 25 | opencode | Done |
| AGT-08 | Phase 26 | qwen-code | Done |
| WORK-01 | Phase 27 | ccusage | Done |
| ENABLE-08 | Phases 24–26 | passive autoupdate freeze (opencode/gemini-cli/qwen-code) 🔧 | Done |
| WIRE-01 | Phases 24–27 (retrofit) | cross-agent skill wiring (GSD + playwright-cli → all shipped agents) 🔧 | Done |
| WORK-02 | Phase 28 | rtk 🔧 | Done |
| ENABLE-01 | Phase 28 | prebuilt-binary installer 🔧 | Done |
| DEVT-01 | Phase 29 | gh | Done |
| DEVT-02 | Phase 30 | glab | Done |
| DEVT-04 | Phase 31 | trivy | Done |
| DEVT-05 | Phase 32 | gitleaks | Done |
| DEVT-03 | Phase 33 | sentry-cli | Done |
| MCP-01 | Phase 34 | chrome-devtools-mcp 🔧 | Done |
| ENABLE-02 | Phase 34 | MCP recipe pattern 🔧 | Done |
| MCP-02 | Phase 35 | context7 (first secret-carrying MCP; optional key) | Done |
| MCP-03 | Phase 36 | github-mcp (remote-http + cross-agent fan-out; ENABLE-02 remote-http enabler) | Done |
| MCP-04 | Phase 37 | sentry-mcp (hosted remote, thin installer ADR-017) | Done |
| MCP-05 | Phase 38 | gitlab-mcp — DROPPED (official paywalled; third-party declined) | Deferred |
| MCP-06 | Phase 39 | brave-search-mcp — DROPPED (Feb-2026 free tier removed; card required) | Deferred |
| MCP-07 | Phase 40 | firecrawl-mcp — hosted keyless bare-URL (ADR-017); cleared free-tier gate | ✓ Covered (Docker 2/2 green) |
| MCP-08 | Phase 41 | slack-mcp — official first-party hosted bare-URL (ADR-017); stealth-token plan superseded | ✓ Covered (Docker 2/2 green) |
| MCP-09 | Phase 42 | linear-mcp — official first-party hosted bare-URL (ADR-017); free-tier confirmed | ✓ Covered (Docker 2/2 green) |
| MCP-10 | Phase 43 | jira-atlassian-mcp — official first-party hosted bare-URL (ADR-017); free-tier confirmed; cloud-only | ✓ Covered (Docker 2/2 green) |
| WORK-03 | Phase 44 | spec-kit 🔧 | Pending |
| ENABLE-03 | Phase 44 | Python+uv bootstrap 🔧 | Pending |
| WORK-04 | Phase 45 | claude-flow | Pending |
| WORK-05 | Phase 46 | bmad | Pending |
| ASST-01 | Phase 47 | openclaw 🔧 | Pending |
| ENABLE-04 | Phase 47 | AI-assistant daemon lifecycle 🔧 | Pending |
| ASST-02 | Phase 48 | hermes-agent | Pending |
| ENABLE-06 | Phase 49 | `list` category/tags UX | Pending |
| ENABLE-07 | Phase 49 | catalog growth kit (template + rubric) | Pending |

**Coverage validation:** 7 ENABLE + 4 AGT (05-08) + 10 MCP (01-10) + 5 DEVT (01-05) + 5 WORK (01-05) + 2 ASST (01-02) = **33/33 requirements mapped to exactly one phase across phases 23–49**. No orphans, no duplicates.
