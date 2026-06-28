# Requirements — v0.3.6 Catalog Expansion

**Milestone goal:** Grow the AgentLinux catalog from 3 entries to 26 of the most trusted/popular AI-agent-community tools — *availability only* (CAT-02 holds: nothing installed by default) — so first-release users don't hit "I miss tool X."

**Selection method:** gates+scoring funnel (agent-relevance · clean per-user install + symmetric uninstall, no root, no `/usr/local` shim · free license · liveness ≤6mo release & ≤3mo commits · maturity), then owner curation. Research + audit trail: `.planning/research/v0.3.6/` (to be migrated from session scratchpad).

**Contract:** every requirement below carries ≥1 bats @test (catalog `install` → `post_install_verify` → symmetric `remove`, no residue) per the project's TST-07 phase-close gate. Each tool is pinned per ADR-011 (pins in Appendix A). One tool per phase (phases 23–49).

---

## v0.3.6 Requirements

### Machinery enablers (catalog capability additions; each folded into its first-consumer phase)

- [ ] **ENABLE-01**: Catalog supports a **prebuilt-binary** entry kind — fetches a pinned release, verifies its checksum, installs the binary to `~/.local/bin` (agent-owned, no root, no `/usr/local` shim), and `remove` deletes the binary + its config/cache symmetrically.
- [ ] **ENABLE-02**: Catalog supports **MCP-server** entries — `install` registers via `claude mcp add --scope user` (npx-stdio and remote-http shapes); `remove` deregisters via `claude mcp remove` (+ `claude mcp logout` for OAuth). Secrets are never baked into the recipe/image: entries declare `requires_secret`/`secret_env`, and `install` prints a post-install token/login instruction.
- [ ] **ENABLE-03**: Catalog supports **Python+uv** entries via a per-user `uv` bootstrap (`~/.local/bin`, no root); install via `uv tool`/`uvx`, with symmetric uninstall.
- [ ] **ENABLE-04**: Catalog supports **AI-assistant daemon** entries — `install` sets up a per-user background service; `remove` tears it down symmetrically (no stray daemon, unit, or state).
- [ ] **ENABLE-05**: **Self-updater coexistence** — for catalog tools that ship a built-in self-updater, AgentLinux's pinned version stays authoritative (in-app updater disabled or documented; the pin is not silently clobbered). Re-exercises the AGT-02 canonical concern.
- [ ] **ENABLE-06**: `agentlinux list` groups catalog entries by **category/tags** (coding-agent · mcp · devops · token/workflow · assistant).
- [ ] **ENABLE-07**: **Catalog growth kit** — a contributor recipe template + the selection-rubric doc are published so a new entry can be added without touching CLI source (extends CAT-03).

### Coding-agent CLIs (npm)

- [ ] **AGT-05**: `agentlinux install opencode` installs opencode (npm `opencode-ai`); CLI resolves on PATH; `remove` is symmetric.
- [ ] **AGT-06**: `agentlinux install gemini-cli` installs Gemini CLI (npm `@google/gemini-cli`, bin `gemini`); symmetric remove.
- [ ] **AGT-07**: `agentlinux install codex` installs OpenAI Codex (npm `@openai/codex`); self-updater coexistence (ENABLE-05) verified — pin survives; symmetric remove.
- [ ] **AGT-08**: `agentlinux install qwen-code` installs Qwen Code (npm `@qwen-code/qwen-code`, bin `qwen`); symmetric remove.

### MCP servers

- [ ] **MCP-01**: `agentlinux install chrome-devtools-mcp` registers the Chrome DevTools MCP server (npx, no secret); requires Chrome present (documented); `remove` deregisters.
- [ ] **MCP-02**: `agentlinux install context7` registers Context7 (npx); optional `CONTEXT7_API_KEY` handled per ENABLE-02; symmetric remove.
- [ ] **MCP-03**: `agentlinux install github-mcp` registers the GitHub MCP server (remote-http + PAT header, or Go binary stdio — **never** the Docker recipe); PAT supplied post-install; symmetric remove.
- [ ] **MCP-04**: `agentlinux install sentry-mcp` registers Sentry MCP (npx + `SENTRY_ACCESS_TOKEN`, or hosted OAuth); symmetric remove. *(FSL license — see Appendix B.)*
- [ ] **MCP-05**: `agentlinux install gitlab-mcp` registers GitLab MCP (npx `@zereight/mcp-gitlab` + `GITLAB_PERSONAL_ACCESS_TOKEN`); symmetric remove.
- [ ] **MCP-06**: `agentlinux install brave-search-mcp` registers Brave Search MCP (npx + `BRAVE_API_KEY`, free tier); symmetric remove.
- [ ] **MCP-07**: `agentlinux install firecrawl-mcp` registers Firecrawl MCP (npx `firecrawl-mcp` + `FIRECRAWL_API_KEY`); **pinned from npm**, not the stale GitHub tag; symmetric remove.
- [ ] **MCP-08**: `agentlinux install slack-mcp` registers Slack MCP (npx `slack-mcp-server` + token); `xoxp` OAuth preferred, `xoxc/xoxd` stealth-mode admin-bypass warned; symmetric remove.
- [ ] **MCP-09**: `agentlinux install linear-mcp` registers the official Linear MCP (remote-http `https://mcp.linear.app/mcp`, OAuth via `claude mcp login --no-browser`); no version pin (hosted); `remove` deregisters + logs out.
- [ ] **MCP-10**: `agentlinux install jira-atlassian-mcp` registers the official Atlassian Rovo MCP (remote-http, OAuth, **cloud-only**); no version pin (hosted); symmetric remove + logout.

### DevOps / git / observability CLIs (prebuilt binary, ENABLE-01)

- [ ] **DEVT-01**: `agentlinux install gh` installs GitHub CLI (binary → `~/.local/bin`); symmetric remove (+ `~/.config/gh`).
- [ ] **DEVT-02**: `agentlinux install glab` installs GitLab CLI (binary, from `gitlab-org/cli` — **not** the archived `profclems/glab`); symmetric remove (+ `~/.config/glab`).
- [ ] **DEVT-03**: `agentlinux install sentry-cli` installs Sentry CLI (npm `@sentry/cli` or binary); symmetric remove. *(FSL — Appendix B.)*
- [ ] **DEVT-04**: `agentlinux install trivy` installs Trivy (binary); fs/repo scans need no Docker; symmetric remove (+ `~/.cache/trivy`).
- [ ] **DEVT-05**: `agentlinux install gitleaks` installs Gitleaks (binary); symmetric remove.

### Token / context / workflow tools

- [ ] **WORK-01**: `agentlinux install ccusage` installs ccusage (npm; read-only cost reporter); symmetric remove.
- [ ] **WORK-02**: `agentlinux install rtk` installs RTK / Rust Token Killer (**prebuilt binary, source-pinned to `rtk-ai/rtk` — never `cargo install rtk`** = the crates.io "Rust Type Kit" collision); optional `rtk init` hook into `~/.claude` is opt-in with symmetric `--uninstall`; `remove` reverts binary + hook.
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

opencode `opencode-ai@1.17.11` · gemini-cli `@google/gemini-cli@0.49.0` · codex `@openai/codex@0.142.3` · qwen-code `@qwen-code/qwen-code@0.19.2` · ccusage `ccusage@20.0.14` · rtk `rtk-ai/rtk@0.42.4` (binary) · gh `2.95.0` · glab `1.105.0` · sentry-cli `@sentry/cli@3.6.0` · trivy `0.71.2` · gitleaks `8.30.1` · chrome-devtools-mcp `1.4.0` · context7 `@upstash/context7-mcp@3.2.2` · github-mcp `1.5.0` · sentry-mcp `@sentry/mcp-server@0.36.0` · gitlab-mcp `@zereight/mcp-gitlab@2.1.27` · brave-search-mcp `@brave/brave-search-mcp-server@2.0.85` · firecrawl-mcp `firecrawl-mcp@3.22.1` (npm) · slack-mcp `slack-mcp-server@1.3.0` · spec-kit `specify-cli@0.11.9` · claude-flow `claude-flow@3.14.4` · bmad `bmad-method@6.9.0` · openclaw `openclaw@2026.6.10` · hermes-agent `2026.6.19` (curl). **No pin:** linear-mcp, jira-atlassian-mcp (hosted-remote, rolling).

## Appendix B — License flags

FSL-1.1 (source-available, not OSI; converts to MIT/Apache after 2 yrs), passes the "free to use" gate but flag if an OSI-only catalog is ever required: **sentry-cli** (FSL-1.1-MIT), **sentry-mcp** (FSL-1.1-Apache). All others MIT/Apache-2.0 (verified LICENSE files; some show GitHub `NOASSERTION` but are MIT: openclaw, bmad, ccusage).

---

## Traceability

(Filled by the roadmapper — each requirement → exactly one phase, phases 23–49.)
