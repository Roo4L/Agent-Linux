# Roadmap

**Current milestone:** 🚧 **v0.3.6 Catalog Expansion** — IN PROGRESS (phases **23–49**, one tool per phase; 26 new catalog entries + a categorization/growth-kit capstone). v0.3.4 Aware Installation Process **SHIPPED 2026-06-08** (final release v0.3.4, marked Latest).

## Current Milestone: v0.3.6 Catalog Expansion

**Milestone goal:** Grow the AgentLinux catalog from its 3 shipped entries (claude-code, gsd, playwright) by **26 of the most trusted/popular AI-agent-community tools** — *availability only* (CAT-02 holds: nothing installed by default) — so first-release users don't hit "I miss tool X." Tools were selected via a documented gates+scoring funnel (agent-relevance · clean per-user install + symmetric uninstall, no root, no `/usr/local` shim · free license · liveness ≤6mo release & ≤3mo commits · maturity).

**Structure (owner's always-shippable preference): ONE TOOL PER PHASE.** Each phase ends with exactly one working, tested, installable+removable catalog entry. The 4 machinery enablers are **folded into their first-consumer phase** (marked 🔧): those phases deliver both the enabler *and* a working tool. Every entry carries ≥1 bats @test (catalog `install` → `post_install_verify` → symmetric `remove`, no residue) per the project's TST-07 phase-close gate; every tool is pinned per ADR-011 (pins in REQUIREMENTS.md Appendix A).

**Machinery tags:** `[npm]` global install via `as_user` (per-user npm prefix; pre-existing since v0.3.0) · `[bin]` prebuilt-binary fetch+checksum → `~/.local/bin` (ENABLE-01) · `[mcp]` `claude mcp add/remove --scope user` (ENABLE-02) · `[uv]` per-user `uv` bootstrap (ENABLE-03) · `[daemon]` per-user background service (ENABLE-04) · `[meta]` catalog-wide UX/contributor work.

> **Parallel-milestone note (numbering rationale — KEEP).** v0.3.5 (AlmaLinux 9 support, AL-64..68, Epic AL-48) is in flight on the **`worktree-almalinux-support`** branch and **owns phases 18–22**. Catalog Expansion was deliberately numbered **v0.3.6 / phases 23–49** so the two parallel milestones never collide on version *or* phase number at merge. Phases 18–22 are RESERVED for v0.3.5; do not reuse them here. PROJECT.md / MILESTONES.md / ROADMAP.md will need merge reconciliation between the two branches when both land.

### Phases

Execution is strictly sequential (23 → 49); each phase ships independently. 🔧 = also delivers a folded machinery enabler.

- [x] **Phase 23: codex** 🔧 `[npm]` - OpenAI Codex CLI + self-updater-coexistence enabler (ENABLE-05) ✓ COMPLETE
- [x] **Phase 24: gemini-cli** `[npm]` - Google Gemini CLI installable + removable ✓ COMPLETE
- [x] **Phase 25: opencode** `[npm]` - opencode CLI installable + removable ✓ COMPLETE
- [x] **Phase 26: qwen-code** `[npm]` - Qwen Code CLI installable + removable ✓ COMPLETE
- [x] **Phase 27: ccusage** `[npm]` - read-only Claude cost reporter installable + removable ✓ COMPLETE
- [ ] **Phase 28: rtk** 🔧 `[bin]` - Rust Token Killer + prebuilt-binary installer enabler (ENABLE-01)
- [ ] **Phase 29: gh** `[bin]` - GitHub CLI installable + removable
- [ ] **Phase 30: glab** `[bin]` - GitLab CLI (gitlab-org/cli) installable + removable
- [ ] **Phase 31: trivy** `[bin]` - Trivy scanner (no-Docker fs/repo scans) installable + removable
- [ ] **Phase 32: gitleaks** `[bin]` - Gitleaks secret scanner installable + removable
- [ ] **Phase 33: sentry-cli** `[npm]` - Sentry CLI (FSL) installable + removable
- [ ] **Phase 34: chrome-devtools-mcp** 🔧 `[mcp]` - Chrome DevTools MCP + MCP-recipe-pattern enabler (ENABLE-02)
- [ ] **Phase 35: context7** `[mcp]` - Context7 MCP server registerable + deregisterable
- [ ] **Phase 36: github-mcp** `[mcp]` - GitHub MCP (remote-http/PAT or Go-binary stdio, never Docker)
- [ ] **Phase 37: sentry-mcp** `[mcp]` - Sentry MCP (npx+token or hosted OAuth; FSL)
- [ ] **Phase 38: gitlab-mcp** `[mcp]` - GitLab MCP registerable + deregisterable
- [ ] **Phase 39: brave-search-mcp** `[mcp]` - Brave Search MCP registerable + deregisterable
- [ ] **Phase 40: firecrawl-mcp** `[mcp]` - Firecrawl MCP (pinned from npm) registerable + deregisterable
- [ ] **Phase 41: slack-mcp** `[mcp]` - Slack MCP (xoxp preferred; stealth-mode warned)
- [ ] **Phase 42: linear-mcp** 🔧 `[mcp]` - Linear MCP + remote-http/OAuth handling enabler
- [ ] **Phase 43: jira-atlassian-mcp** `[mcp]` - Atlassian Rovo MCP (remote-http OAuth, cloud-only)
- [ ] **Phase 44: spec-kit** 🔧 `[uv]` - GitHub Spec Kit + Python+uv-bootstrap enabler (ENABLE-03)
- [ ] **Phase 45: claude-flow** `[npm]` - Claude-Flow (full-footprint symmetric remove)
- [ ] **Phase 46: bmad** `[npm]` - BMAD-METHOD installable + removable
- [ ] **Phase 47: openclaw** 🔧 `[daemon]` - OpenClaw + AI-assistant daemon-lifecycle enabler (ENABLE-04)
- [ ] **Phase 48: hermes-agent** `[daemon]` - Hermes Agent (curl + per-user daemon/gateway)
- [ ] **Phase 49: catalog growth kit** `[meta]` - `list` category/tags UX (ENABLE-06) + contributor template & selection-rubric doc (ENABLE-07)

## Phase Details

### Phase 23: codex
**Goal**: Make codex (OpenAI Codex CLI) installable + removable via the catalog, AND deliver the self-updater-coexistence enabler (ENABLE-05).
**Depends on**: v0.3.0 catalog + registry CLI (shipped); npm install machinery (pre-existing). First v0.3.6 phase.
**Requirements**: AGT-07, ENABLE-05
**Machinery**: `[npm]` · 🔧 ENABLE-05 self-updater coexistence · pin `@openai/codex@0.142.3`
**Success Criteria** (what must be TRUE):
  1. `agentlinux install codex` installs `@openai/codex@0.142.3` as the agent user (no root, zero EACCES/permission-denied); `codex` resolves on PATH under the agent home (no `/usr/local` shim).
  2. ENABLE-05: codex's built-in self-updater does not silently clobber the pin — the in-app updater is disabled or documented, and AgentLinux's pinned version stays authoritative after a self-update attempt (re-exercises the AGT-02 canonical concern).
  3. Secrets are NOT baked — codex auth is supplied post-install (login/env), never in the recipe/snapshot.
  4. `agentlinux remove codex` is symmetric (npm global gone, no residue) and idempotent.
  5. ≥1 bats @test (install → version-pin verify → self-updater-coexistence → remove) is green — TST-07 phase-close gate.
**Plans**: TBD

### Phase 24: gemini-cli
**Goal**: Make gemini-cli (Google Gemini CLI) installable + removable via the catalog.
**Depends on**: Phase 23 (npm recipe pattern; self-updater-coexistence convention available)
**Requirements**: AGT-06
**Machinery**: `[npm]` · pin `@google/gemini-cli@0.49.0`, bin `gemini`
**Success Criteria** (what must be TRUE):
  1. `agentlinux install gemini-cli` installs `@google/gemini-cli@0.49.0` as the agent user (no root, zero EACCES); `gemini` resolves on PATH.
  2. `post_install_verify` passes — `gemini --version` reports the pinned `0.49.0`.
  3. Secrets are NOT baked — Google auth is supplied post-install.
  4. `agentlinux remove gemini-cli` is symmetric and idempotent — no residue.
  5. ≥1 bats @test covers install → verify → remove — TST-07 gate.
**Plans**: TBD

### Phase 25: opencode
**Goal**: Make opencode installable + removable via the catalog.
**Depends on**: Phase 24
**Requirements**: AGT-05
**Machinery**: `[npm]` · pin `opencode-ai@1.17.11`, bin `opencode`
**Success Criteria** (what must be TRUE):
  1. `agentlinux install opencode` installs `opencode-ai@1.17.11` as the agent user (no root, zero EACCES); `opencode` resolves on PATH.
  2. `post_install_verify` passes — the pinned `1.17.11` is the resolved version.
  3. Secrets are NOT baked — provider auth supplied post-install.
  4. `agentlinux remove opencode` is symmetric and idempotent — no residue.
  5. ≥1 bats @test covers install → verify → remove — TST-07 gate.
**Plans**: TBD

### Phase 26: qwen-code
**Goal**: Make qwen-code (Qwen Code CLI) installable + removable via the catalog.
**Depends on**: Phase 25
**Requirements**: AGT-08
**Machinery**: `[npm]` · pin `@qwen-code/qwen-code@0.19.2`, bin `qwen`
**Success Criteria** (what must be TRUE):
  1. `agentlinux install qwen-code` installs `@qwen-code/qwen-code@0.19.2` as the agent user (no root, zero EACCES); `qwen` resolves on PATH.
  2. `post_install_verify` passes — `qwen --version` reports the pinned `0.19.2`.
  3. Secrets are NOT baked — provider auth supplied post-install.
  4. `agentlinux remove qwen-code` is symmetric and idempotent — no residue.
  5. ≥1 bats @test covers install → verify → remove — TST-07 gate.
**Plans**: TBD

### Phase 27: ccusage
**Goal**: Make ccusage (read-only Claude cost reporter) installable + removable via the catalog.
**Depends on**: Phase 26
**Requirements**: WORK-01
**Machinery**: `[npm]` · pin `ccusage@20.0.14` · LICENSE shows GitHub `NOASSERTION` but is MIT (Appendix B)
**Success Criteria** (what must be TRUE):
  1. `agentlinux install ccusage` installs `ccusage@20.0.14` as the agent user (no root, zero EACCES); `ccusage` resolves on PATH.
  2. `post_install_verify` passes — the pinned `20.0.14` runs; it is read-only (no token/secret required — reads local Claude usage).
  3. `agentlinux remove ccusage` is symmetric and idempotent — no residue.
  4. ≥1 bats @test covers install → verify → remove — TST-07 gate.
**Plans**: TBD

### Phase 28: rtk
**Goal**: Make rtk (RTK / Rust Token Killer) installable + removable via the catalog, AND deliver the prebuilt-binary installer enabler (ENABLE-01).
**Depends on**: Phase 27. First consumer of the prebuilt-binary entry kind.
**Requirements**: WORK-02, ENABLE-01
**Machinery**: `[bin]` · 🔧 ENABLE-01 prebuilt-binary kind · pin `rtk-ai/rtk@0.42.4` (binary) · crates.io "Rust Type Kit" collision — source-pinned to `rtk-ai/rtk`, NEVER `cargo install rtk`
**Success Criteria** (what must be TRUE):
  1. ENABLE-01: the catalog supports a prebuilt-binary entry kind — `install` fetches the pinned `rtk-ai/rtk@0.42.4` release, verifies its checksum, and installs the binary to `~/.local/bin` (agent-owned, no root, no `/usr/local` shim).
  2. `agentlinux install rtk` resolves the correct upstream (`rtk-ai/rtk`) — NOT the crates.io "Rust Type Kit" collision (`cargo install rtk` is never used); `rtk --version` reports `0.42.4`.
  3. The optional `rtk init` hook into `~/.claude` is opt-in; `remove` reverts the binary AND the hook symmetrically (`--uninstall`) — no residue.
  4. `agentlinux remove rtk` deletes the binary + its config/cache symmetrically; idempotent.
  5. ≥1 bats @test (binary fetch → checksum → version → optional-hook → remove) is green — TST-07 gate.
**Plans**: 4 plans

Plans:
- [x] 28-01-PLAN.md — Add "binary" to the source_kind enum (schema.json + types.ts) + unit test
- [x] 28-02-PLAN.md — Shared prebuilt-binary helper (arch-detect + verify-before-extract + install + version-lock)
- [ ] 28-03-PLAN.md — rtk recipe pair (install/uninstall) + catalog.json entry (source_kind binary, pin 0.42.4)
- [ ] 28-04-PLAN.md — ENABLE-01/WORK-02/OPS-01 bats lifecycle test + docs/internals/catalog.md note

### Phase 29: gh
**Goal**: Make gh (GitHub CLI) installable + removable via the catalog.
**Depends on**: Phase 28 (ENABLE-01 prebuilt-binary kind)
**Requirements**: DEVT-01
**Machinery**: `[bin]` · pin `2.95.0` · removes `~/.config/gh`
**Success Criteria** (what must be TRUE):
  1. `agentlinux install gh` fetches + checksum-verifies the pinned `2.95.0` binary into `~/.local/bin` as the agent user (no root, zero EACCES); `gh --version` reports `2.95.0`.
  2. Secrets are NOT baked — `gh auth login` is run post-install by the user.
  3. `agentlinux remove gh` deletes the binary + `~/.config/gh` symmetrically; idempotent — no residue.
  4. ≥1 bats @test covers install → verify → remove — TST-07 gate.
**Plans**: TBD

### Phase 30: glab
**Goal**: Make glab (GitLab CLI) installable + removable via the catalog.
**Depends on**: Phase 29 (ENABLE-01 prebuilt-binary kind)
**Requirements**: DEVT-02
**Machinery**: `[bin]` · pin `1.105.0` · source `gitlab-org/cli` (NOT the archived `profclems/glab`) · removes `~/.config/glab`
**Success Criteria** (what must be TRUE):
  1. `agentlinux install glab` fetches the pinned `1.105.0` binary from `gitlab-org/cli` (NOT `profclems/glab`) into `~/.local/bin` as the agent user (no root, zero EACCES); `glab --version` reports `1.105.0`.
  2. Secrets are NOT baked — `glab auth login` is run post-install by the user.
  3. `agentlinux remove glab` deletes the binary + `~/.config/glab` symmetrically; idempotent — no residue.
  4. ≥1 bats @test covers install (correct upstream) → verify → remove — TST-07 gate.
**Plans**: TBD

### Phase 31: trivy
**Goal**: Make trivy (vulnerability/secret scanner) installable + removable via the catalog.
**Depends on**: Phase 30 (ENABLE-01 prebuilt-binary kind)
**Requirements**: DEVT-04
**Machinery**: `[bin]` · pin `0.71.2` · removes `~/.cache/trivy`
**Success Criteria** (what must be TRUE):
  1. `agentlinux install trivy` fetches + checksum-verifies the pinned `0.71.2` binary into `~/.local/bin` as the agent user (no root, zero EACCES); `trivy --version` reports `0.71.2`.
  2. `post_install_verify` passes — a `trivy fs`/repo scan runs with no Docker daemon required.
  3. `agentlinux remove trivy` deletes the binary + `~/.cache/trivy` symmetrically; idempotent — no residue.
  4. ≥1 bats @test covers install → no-Docker scan verify → remove — TST-07 gate.
**Plans**: TBD

### Phase 32: gitleaks
**Goal**: Make gitleaks (secret scanner) installable + removable via the catalog.
**Depends on**: Phase 31 (ENABLE-01 prebuilt-binary kind)
**Requirements**: DEVT-05
**Machinery**: `[bin]` · pin `8.30.1`
**Success Criteria** (what must be TRUE):
  1. `agentlinux install gitleaks` fetches + checksum-verifies the pinned `8.30.1` binary into `~/.local/bin` as the agent user (no root, zero EACCES); `gitleaks version` reports `8.30.1`.
  2. `post_install_verify` passes — `gitleaks` runs a scan on a sample repo/dir.
  3. `agentlinux remove gitleaks` deletes the binary symmetrically; idempotent — no residue.
  4. ≥1 bats @test covers install → verify → remove — TST-07 gate.
**Plans**: TBD

### Phase 33: sentry-cli
**Goal**: Make sentry-cli installable + removable via the catalog.
**Depends on**: Phase 32 (npm machinery, or ENABLE-01 binary path)
**Requirements**: DEVT-03
**Machinery**: `[npm]` (`@sentry/cli`, or binary) · pin `@sentry/cli@3.6.0` · **FSL-1.1-MIT** license — passes the "free to use" gate; flag in entry metadata if an OSI-only catalog is ever required (Appendix B)
**Success Criteria** (what must be TRUE):
  1. `agentlinux install sentry-cli` installs the pinned `@sentry/cli@3.6.0` as the agent user (no root, zero EACCES); `sentry-cli --version` reports `3.6.0`.
  2. The FSL-1.1-MIT license flag is recorded in the catalog entry (license-gate honesty).
  3. Secrets are NOT baked — `SENTRY_AUTH_TOKEN` is supplied post-install.
  4. `agentlinux remove sentry-cli` is symmetric and idempotent — no residue.
  5. ≥1 bats @test covers install → verify → remove — TST-07 gate.
**Plans**: TBD

### Phase 34: chrome-devtools-mcp
**Goal**: Make chrome-devtools-mcp registerable + deregisterable via the catalog, AND deliver the MCP-recipe-pattern enabler (ENABLE-02).
**Depends on**: Phase 33. First consumer of the MCP-server entry kind.
**Requirements**: MCP-01, ENABLE-02
**Machinery**: `[mcp]` · 🔧 ENABLE-02 MCP recipe pattern (npx-stdio + remote-http shapes; secret convention) · pin `chrome-devtools-mcp@1.4.0` · npx, no secret · requires Chrome present (documented)
**Success Criteria** (what must be TRUE):
  1. ENABLE-02: the catalog supports MCP-server entries — `install` registers via `claude mcp add --scope user` (npx-stdio shape working); entries declare `requires_secret`/`secret_env` and `install` prints a post-install token/login instruction (secrets never baked); `remove` deregisters via `claude mcp remove`.
  2. `agentlinux install chrome-devtools-mcp` registers the pinned `1.4.0` server (npx, no secret) — it appears in `~/.claude.json` / `claude mcp list`.
  3. The Chrome-present requirement is documented in the entry and surfaced by `install`.
  4. `agentlinux remove chrome-devtools-mcp` deregisters cleanly — no residue in `~/.claude.json`.
  5. ≥1 bats @test (register → `~/.claude.json` verify → deregister) is green — TST-07 gate.
**Plans**: TBD

### Phase 35: context7
**Goal**: Make context7 (Context7 MCP) registerable + deregisterable via the catalog.
**Depends on**: Phase 34 (ENABLE-02 MCP entry kind)
**Requirements**: MCP-02
**Machinery**: `[mcp]` · pin `@upstash/context7-mcp@3.2.2` · npx · optional `CONTEXT7_API_KEY` per ENABLE-02
**Success Criteria** (what must be TRUE):
  1. `agentlinux install context7` registers the pinned `@upstash/context7-mcp@3.2.2` via `claude mcp add --scope user` as the agent user (no root, zero EACCES); it appears in `~/.claude.json`.
  2. The optional `CONTEXT7_API_KEY` is NOT baked — `install` prints the post-install instruction; the server works keyless by default.
  3. `agentlinux remove context7` deregisters symmetrically — no residue.
  4. ≥1 bats @test covers register → verify → deregister — TST-07 gate.
**Plans**: TBD

### Phase 36: github-mcp
**Goal**: Make github-mcp (GitHub MCP server) registerable + deregisterable via the catalog, with secret/PAT handling.
**Depends on**: Phase 35 (ENABLE-02 MCP entry kind)
**Requirements**: MCP-03
**Machinery**: `[mcp]` · pin `github-mcp@1.5.0` · remote-http + PAT header, OR Go-binary stdio — **never** the Docker recipe
**Success Criteria** (what must be TRUE):
  1. `agentlinux install github-mcp` registers the GitHub MCP server (remote-http + PAT header, or Go-binary stdio — NEVER the Docker recipe) — it appears in `~/.claude.json`.
  2. The PAT is supplied post-install (`requires_secret`/`secret_env`) — never baked into the recipe/snapshot; `install` prints the token instruction.
  3. `agentlinux remove github-mcp` deregisters symmetrically — no residue, no leaked PAT.
  4. ≥1 bats @test (register, no-Docker shape → verify → deregister, secret-not-baked grep) is green — TST-07 gate.
**Plans**: TBD

### Phase 37: sentry-mcp
**Goal**: Make sentry-mcp (Sentry MCP server) registerable + deregisterable via the catalog.
**Depends on**: Phase 36 (ENABLE-02 MCP entry kind)
**Requirements**: MCP-04
**Machinery**: `[mcp]` · pin `@sentry/mcp-server@0.36.0` · npx + `SENTRY_ACCESS_TOKEN`, or hosted OAuth · **FSL-1.1-Apache** license (Appendix B)
**Success Criteria** (what must be TRUE):
  1. `agentlinux install sentry-mcp` registers the pinned `@sentry/mcp-server@0.36.0` (npx + `SENTRY_ACCESS_TOKEN`, or hosted OAuth) via `claude mcp add --scope user` (no root, zero EACCES); it appears in `~/.claude.json`.
  2. The token/OAuth is NOT baked — `install` prints the post-install instruction; the FSL-1.1-Apache flag is recorded in the entry.
  3. `agentlinux remove sentry-mcp` deregisters symmetrically (+ logout for OAuth) — no residue.
  4. ≥1 bats @test covers register → verify → deregister — TST-07 gate.
**Plans**: TBD

### Phase 38: gitlab-mcp
**Goal**: Make gitlab-mcp (GitLab MCP server) registerable + deregisterable via the catalog.
**Depends on**: Phase 37 (ENABLE-02 MCP entry kind)
**Requirements**: MCP-05
**Machinery**: `[mcp]` · pin `@zereight/mcp-gitlab@2.1.27` · npx + `GITLAB_PERSONAL_ACCESS_TOKEN`
**Success Criteria** (what must be TRUE):
  1. `agentlinux install gitlab-mcp` registers the pinned `@zereight/mcp-gitlab@2.1.27` (npx + `GITLAB_PERSONAL_ACCESS_TOKEN`) via `claude mcp add --scope user` (no root, zero EACCES); it appears in `~/.claude.json`.
  2. The PAT is NOT baked — `install` prints the post-install instruction.
  3. `agentlinux remove gitlab-mcp` deregisters symmetrically — no residue.
  4. ≥1 bats @test covers register → verify → deregister — TST-07 gate.
**Plans**: TBD

### Phase 39: brave-search-mcp
**Goal**: Make brave-search-mcp (Brave Search MCP server) registerable + deregisterable via the catalog.
**Depends on**: Phase 38 (ENABLE-02 MCP entry kind)
**Requirements**: MCP-06
**Machinery**: `[mcp]` · pin `@brave/brave-search-mcp-server@2.0.85` · npx + `BRAVE_API_KEY` (free tier)
**Success Criteria** (what must be TRUE):
  1. `agentlinux install brave-search-mcp` registers the pinned `@brave/brave-search-mcp-server@2.0.85` (npx + `BRAVE_API_KEY`, free tier) via `claude mcp add --scope user` (no root, zero EACCES); it appears in `~/.claude.json`.
  2. The `BRAVE_API_KEY` is NOT baked — `install` prints the post-install (free-tier) instruction.
  3. `agentlinux remove brave-search-mcp` deregisters symmetrically — no residue.
  4. ≥1 bats @test covers register → verify → deregister — TST-07 gate.
**Plans**: TBD

### Phase 40: firecrawl-mcp
**Goal**: Make firecrawl-mcp (Firecrawl MCP server) registerable + deregisterable via the catalog.
**Depends on**: Phase 39 (ENABLE-02 MCP entry kind)
**Requirements**: MCP-07
**Machinery**: `[mcp]` · pin `firecrawl-mcp@3.22.1` (**from npm**, NOT the stale GitHub tag) · npx + `FIRECRAWL_API_KEY`
**Success Criteria** (what must be TRUE):
  1. `agentlinux install firecrawl-mcp` registers the pinned `firecrawl-mcp@3.22.1` resolved **from npm** (NOT the stale GitHub tag) via `claude mcp add --scope user` (no root, zero EACCES); it appears in `~/.claude.json`.
  2. The `FIRECRAWL_API_KEY` is NOT baked — `install` prints the post-install instruction.
  3. `agentlinux remove firecrawl-mcp` deregisters symmetrically — no residue.
  4. ≥1 bats @test (register at npm pin → verify → deregister) is green — TST-07 gate.
**Plans**: TBD

### Phase 41: slack-mcp
**Goal**: Make slack-mcp (Slack MCP server) registerable + deregisterable via the catalog.
**Depends on**: Phase 40 (ENABLE-02 MCP entry kind)
**Requirements**: MCP-08
**Machinery**: `[mcp]` · pin `slack-mcp-server@1.3.0` · npx + token · `xoxp` OAuth preferred; `xoxc/xoxd` stealth-mode admin-bypass warned
**Success Criteria** (what must be TRUE):
  1. `agentlinux install slack-mcp` registers the pinned `slack-mcp-server@1.3.0` via `claude mcp add --scope user` (no root, zero EACCES); it appears in `~/.claude.json`.
  2. The token is NOT baked — `install` prints the post-install instruction, prefers `xoxp` OAuth, and warns that `xoxc/xoxd` stealth-mode tokens bypass workspace admin controls.
  3. `agentlinux remove slack-mcp` deregisters symmetrically — no residue.
  4. ≥1 bats @test (register → verify → stealth-mode-warning present → deregister) is green — TST-07 gate.
**Plans**: TBD

### Phase 42: linear-mcp
**Goal**: Make linear-mcp (official Linear MCP) registerable + deregisterable via the catalog, AND deliver the remote-http/OAuth handling enabler.
**Depends on**: Phase 41. First consumer of the remote-http + OAuth MCP shape (extends ENABLE-02).
**Requirements**: MCP-09
**Machinery**: `[mcp]` · 🔧 remote-http/OAuth handling · remote-http `https://mcp.linear.app/mcp` · OAuth via `claude mcp login --no-browser` · **no version pin** (hosted, rolling)
**Success Criteria** (what must be TRUE):
  1. Remote-http/OAuth handling: catalog MCP entries support the remote-http shape with OAuth — `install` registers `https://mcp.linear.app/mcp` and drives `claude mcp login --no-browser`; `remove` deregisters AND runs `claude mcp logout`.
  2. `agentlinux install linear-mcp` registers the official hosted Linear MCP (no version pin — hosted/rolling); it appears in `~/.claude.json`.
  3. OAuth credentials are user-supplied via login — never baked.
  4. `agentlinux remove linear-mcp` deregisters AND logs out — no residue, no lingering OAuth token.
  5. ≥1 bats @test (remote-http register → verify → deregister+logout) is green — TST-07 gate.
**Plans**: TBD

### Phase 43: jira-atlassian-mcp
**Goal**: Make jira-atlassian-mcp (official Atlassian Rovo MCP) registerable + deregisterable via the catalog.
**Depends on**: Phase 42 (remote-http/OAuth handling)
**Requirements**: MCP-10
**Machinery**: `[mcp]` · official Atlassian Rovo MCP · remote-http, OAuth, **cloud-only** · **no version pin** (hosted, rolling)
**Success Criteria** (what must be TRUE):
  1. `agentlinux install jira-atlassian-mcp` registers the official hosted Atlassian Rovo MCP (remote-http, OAuth, cloud-only; no version pin) via the remote-http/OAuth path (no root, zero EACCES); it appears in `~/.claude.json`.
  2. OAuth credentials are user-supplied via login — never baked; the cloud-only constraint is documented in the entry.
  3. `agentlinux remove jira-atlassian-mcp` deregisters AND logs out symmetrically — no residue.
  4. ≥1 bats @test (remote-http register → verify → deregister+logout) is green — TST-07 gate.
**Plans**: TBD

### Phase 44: spec-kit
**Goal**: Make spec-kit (GitHub Spec Kit) installable + removable via the catalog, AND deliver the Python+uv-bootstrap enabler (ENABLE-03).
**Depends on**: Phase 43. First consumer of the Python+uv entry kind.
**Requirements**: WORK-03, ENABLE-03
**Machinery**: `[uv]` · 🔧 ENABLE-03 Python+uv bootstrap · pin `specify-cli@0.11.9` (via uv) · project `.specify/` documented as user-owned
**Success Criteria** (what must be TRUE):
  1. ENABLE-03: the catalog supports Python+uv entries — a per-user `uv` bootstraps into `~/.local/bin` (no root); install uses `uv tool`/`uvx`; uninstall is symmetric.
  2. `agentlinux install spec-kit` installs `specify-cli@0.11.9` via uv as the agent user (no root, zero EACCES); `specify` resolves on PATH.
  3. Project `.specify/` is documented as user-owned and is NOT removed by `agentlinux remove`.
  4. `agentlinux remove spec-kit` uninstalls the uv tool symmetrically — no residue (user `.specify/` preserved); idempotent.
  5. ≥1 bats @test (uv bootstrap → install → verify → remove) is green — TST-07 gate.
**Plans**: TBD

### Phase 45: claude-flow
**Goal**: Make claude-flow (Claude-Flow) installable + removable via the catalog, with full-footprint symmetric remove.
**Depends on**: Phase 44 (npm machinery)
**Requirements**: WORK-04
**Machinery**: `[npm]` · pin `claude-flow@3.14.4` · remove cleans `.claude`/`.swarm`/`.hive-mind`, MCP regs, hooks
**Success Criteria** (what must be TRUE):
  1. `agentlinux install claude-flow` installs `claude-flow@3.14.4` as the agent user (no root, zero EACCES); it resolves on PATH.
  2. Secrets are NOT baked — provider auth supplied post-install.
  3. `agentlinux remove claude-flow` cleans the FULL footprint symmetrically — `.claude`/`.swarm`/`.hive-mind`, MCP registrations, and hooks all gone, no residue; idempotent.
  4. ≥1 bats @test (install → full-footprint remove, residue grep) is green — TST-07 gate.
**Plans**: TBD

### Phase 46: bmad
**Goal**: Make bmad (BMAD-METHOD) installable + removable via the catalog.
**Depends on**: Phase 45 (npm machinery)
**Requirements**: WORK-05
**Machinery**: `[npm]` · pin `bmad-method@6.9.0` · LICENSE shows GitHub `NOASSERTION` but is MIT (Appendix B) · remove of installed agents/packs symmetric
**Success Criteria** (what must be TRUE):
  1. `agentlinux install bmad` installs `bmad-method@6.9.0` as the agent user (no root, zero EACCES); it resolves on PATH.
  2. `post_install_verify` passes — the pinned `6.9.0` is resolved.
  3. `agentlinux remove bmad` removes the installed agents/packs symmetrically — no residue; idempotent.
  4. ≥1 bats @test (install → verify → remove) is green — TST-07 gate.
**Plans**: TBD

### Phase 47: openclaw
**Goal**: Make openclaw (OpenClaw) installable + removable via the catalog, AND deliver the AI-assistant daemon-lifecycle enabler (ENABLE-04).
**Depends on**: Phase 46. First consumer of the AI-assistant daemon entry kind.
**Requirements**: ASST-01, ENABLE-04
**Machinery**: `[daemon]` · 🔧 ENABLE-04 AI-assistant daemon lifecycle · pin `openclaw@2026.6.10` (npm + per-user daemon) · self-updater coexistence per ENABLE-05
**Success Criteria** (what must be TRUE):
  1. ENABLE-04: the catalog supports AI-assistant daemon entries — `install` sets up a per-user background service (no root); `remove` tears it down with no stray daemon, unit, or state.
  2. `agentlinux install openclaw` installs `openclaw@2026.6.10` (npm + per-user daemon) as the agent user (no root, zero EACCES); the daemon runs per-user.
  3. Self-updater coexistence (ENABLE-05) holds — openclaw's pin stays authoritative; secrets are NOT baked.
  4. `agentlinux remove openclaw` tears down the daemon + state symmetrically — no stray unit/process/files; idempotent.
  5. ≥1 bats @test (install → daemon-up verify → remove → daemon-gone) is green — TST-07 gate.
**Plans**: TBD

### Phase 48: hermes-agent
**Goal**: Make hermes-agent (Hermes Agent) installable + removable via the catalog.
**Depends on**: Phase 47 (ENABLE-04 AI-assistant daemon entry kind)
**Requirements**: ASST-02
**Machinery**: `[daemon]` · pin `2026.6.19` (curl installer + per-user daemon/gateway)
**Success Criteria** (what must be TRUE):
  1. `agentlinux install hermes-agent` installs `hermes-agent` `2026.6.19` (curl installer + per-user daemon/gateway) as the agent user (no root, zero EACCES); the daemon/gateway runs per-user.
  2. Secrets are NOT baked — any gateway credentials supplied post-install.
  3. `agentlinux remove hermes-agent` tears down the daemon + gateway + state symmetrically — no residue; idempotent.
  4. ≥1 bats @test (install → daemon/gateway-up verify → remove → gone) is green — TST-07 gate.
**Plans**: TBD

### Phase 49: catalog growth kit
**Goal**: Deliver the `list` category/tags UX (ENABLE-06) and the catalog growth kit — a contributor recipe template + the selection-rubric doc (ENABLE-07). Milestone capstone — no new tool.
**Depends on**: Phases 23–48 (needs the full 26-entry catalog to categorize and to validate template-only additions against)
**Requirements**: ENABLE-06, ENABLE-07
**Machinery**: `[meta]` · catalog-wide UX + contributor surface (extends CAT-03)
**Success Criteria** (what must be TRUE):
  1. ENABLE-06: `agentlinux list` groups catalog entries by category/tags (coding-agent · mcp · devops · token/workflow · assistant) — all 26 new entries appear under the correct category.
  2. ENABLE-07: a contributor recipe template + the selection-rubric doc are published — a new catalog entry can be added without touching CLI source (extends CAT-03).
  3. The growth kit is exercised end-to-end: a sample entry added via the template alone passes validate-catalog + install/remove with zero TypeScript edits.
  4. ≥1 bats @test covers `list` category grouping + the template-only-add path — TST-07 gate; milestone-close: all 26 catalog entries install → verify → remove green across the Docker + QEMU gates.
**Plans**: TBD

## Progress

**Execution Order:** Phases execute strictly in numeric order: 23 → 24 → … → 49.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 23. codex 🔧 | 0/TBD | Not started | - |
| 24. gemini-cli | 0/TBD | Not started | - |
| 25. opencode | 0/TBD | Not started | - |
| 26. qwen-code | 0/TBD | Not started | - |
| 27. ccusage | 0/TBD | Not started | - |
| 28. rtk 🔧 | 2/4 | In Progress|  |
| 29. gh | 0/TBD | Not started | - |
| 30. glab | 0/TBD | Not started | - |
| 31. trivy | 0/TBD | Not started | - |
| 32. gitleaks | 0/TBD | Not started | - |
| 33. sentry-cli | 0/TBD | Not started | - |
| 34. chrome-devtools-mcp 🔧 | 0/TBD | Not started | - |
| 35. context7 | 0/TBD | Not started | - |
| 36. github-mcp | 0/TBD | Not started | - |
| 37. sentry-mcp | 0/TBD | Not started | - |
| 38. gitlab-mcp | 0/TBD | Not started | - |
| 39. brave-search-mcp | 0/TBD | Not started | - |
| 40. firecrawl-mcp | 0/TBD | Not started | - |
| 41. slack-mcp | 0/TBD | Not started | - |
| 42. linear-mcp 🔧 | 0/TBD | Not started | - |
| 43. jira-atlassian-mcp | 0/TBD | Not started | - |
| 44. spec-kit 🔧 | 0/TBD | Not started | - |
| 45. claude-flow | 0/TBD | Not started | - |
| 46. bmad | 0/TBD | Not started | - |
| 47. openclaw 🔧 | 0/TBD | Not started | - |
| 48. hermes-agent | 0/TBD | Not started | - |
| 49. catalog growth kit | 0/TBD | Not started | - |

---

## Last Completed Phase

<details>
<summary>Phase 17: Changes Delivery and Release Candidate ✓ COMPLETE (v0.3.4 SHIPPED 2026-06-08)</summary>

### Phase 17: Changes Delivery and Release Candidate ✓ COMPLETE (v0.3.4 shipped)

**Goal:** Ship the feature-complete v0.3.4 "Aware Installation Process" to a maintainer-testable release candidate and gate the final release on live brownfield review. Polish the worktree branch diff (tests green, commit hygiene), merge to master, cut `v0.3.4-rc1` (tarball + sibling `.sha256` via `scripts/build-release.sh`; push the rc tag to exercise `release.yml` end-to-end — the shipping event), hand the maintainer concrete live-test instructions for his real brownfield VM, then await maintainer feedback as an explicit checkpoint. Outcome: 4 rc iterations (rc1→rc4) each fixing a maintainer-found bug (AL-60/AL-61/AL-62), then LGTM → promoted to final v0.3.4.

**Requirements:** Delivery gate — no new behavior requirements. Re-exercised AGT-02 (zero-EACCES `claude update`) on the maintainer's real brownfield VM.

**Depends on:** Phase 16 (v0.3.4 feature-complete, GATE: GREEN)
**Anchor:** [AL-38](https://copiedwonder.atlassian.net/browse/AL-38)

**Plans:** 3 plans (3 waves — strict delivery ordering with 2 human checkpoints)

Plans:
- [x] 17-01-PLAN.md — DEL-02a + DEL-01: lockstep version bump 0.3.2→0.3.4 + merge-integrate origin/master + full suite green
- [x] 17-02-PLAN.md — DEL-01b/DEL-02b/DEL-03/DEL-04: push branch + open PR → merge PR → push rc tag + watch release → brownfield-VM runbook → VM validation
- [x] 17-03-PLAN.md — DEL-05: promote-or-iterate decision gate. Outcome: 4 rc iterations then LGTM → promoted to final v0.3.4.

</details>

## Shipped / Feature-Complete Milestones

| Version | Name | Phases | Status | Archive |
|---------|------|--------|--------|---------|
| v0.3.4 | Aware Installation Process | 6 (Phase 12-17) | **SHIPPED 2026-06-08** (final v0.3.4, Latest; rc1→rc4 maintainer-validated) | [v0.3.4-ROADMAP.md](milestones/v0.3.4-ROADMAP.md) · [v0.3.4-REQUIREMENTS.md](milestones/v0.3.4-REQUIREMENTS.md) · [v0.3.4-MILESTONE-AUDIT.md](v0.3.4-MILESTONE-AUDIT.md) |
| v0.3.3 | Agenda Redefinition | 5 (Phase 13-17) | shipped 2026-05-24 (docs/vision/website) | [v0.3.3-ROADMAP.md](milestones/v0.3.3-ROADMAP.md) · [v0.3.3-REQUIREMENTS.md](milestones/v0.3.3-REQUIREMENTS.md) · phases archived under [milestones/v0.3.3-phases/](milestones/v0.3.3-phases/) |
| v0.4.0 | Open-Source Release | 5 (Phase 7-11) | feature-complete (formal closeout pending) | [v0.4.0-ROADMAP.md](milestones/v0.4.0-ROADMAP.md) · [v0.4.0-REQUIREMENTS.md](milestones/v0.4.0-REQUIREMENTS.md) |
| v0.3.0 | AgentLinux Plugin (Ubuntu) | 6 + 1 inserted (Phase 1-6, 5.1) | shipped 2026-04-20 | [v0.3.0-ROADMAP.md](milestones/v0.3.0-ROADMAP.md) · [v0.3.0-REQUIREMENTS.md](milestones/v0.3.0-REQUIREMENTS.md) |
| v0.2.0 | First Distro Image | 4 (Phase 1-4) | retired 2026-04-18 (pivot) | [v0.2.0-ROADMAP.md](milestones/v0.2.0-ROADMAP.md) · [v0.2.0-REQUIREMENTS.md](milestones/v0.2.0-REQUIREMENTS.md) |
| v0.1.0 | (initial) | — | — | [v0.1.0-ROADMAP.md](milestones/v0.1.0-ROADMAP.md) · [v0.1.0-REQUIREMENTS.md](milestones/v0.1.0-REQUIREMENTS.md) |

> **Phase-numbering note (parallel-milestone overlap).** Two layers of overlap are recorded here:
>
> 1. **Historical (already shipped):** v0.3.3 (Agenda Redefinition, phases **13–17**) and v0.3.4 (Aware Installation, phases **12–17**) were developed concurrently on separate branches and **reused phase numbers** — frozen in immutable git commit prefixes (`feat(13-…)` etc.). Reconciliation: v0.3.3's completed phase dirs are **archived** under `milestones/v0.3.3-phases/`, leaving the active `phases/` dir to v0.3.4's 12–17. One residual reuse remains — **phase 12** is both v0.3.4's `12-detection-layer` and v0.4.0's AL-22 addendum `12-developer-documentation-…`; both completed, distinguished by dir-slug. This mirrors v0.2.0's archived 1–4 vs v0.3.0's 1–6.
> 2. **Current (in flight, two parallel branches):** v0.3.5 (AlmaLinux 9 support) owns phases **18–22** on `worktree-almalinux-support`; v0.3.6 (Catalog Expansion, this file) owns phases **23–49** on its own branch. The 18–22 / 23–49 split was chosen up front so the two never collide on version *or* phase number. Phases 18–22 are RESERVED for v0.3.5 and must not be reused by Catalog Expansion. Merge reconciliation (PROJECT.md / MILESTONES.md / ROADMAP.md) is expected when both branches land.

## Next Milestone Candidates

- **v0.3.5 AlmaLinux support** — port the aware-install pipeline (Phase 12-15 detection + REUSE/REMEDIATE) to AlmaLinux 9. Anchored under [AL-47](https://copiedwonder.atlassian.net/browse/AL-47) (grouped with AL-38 under Epic AL-48 — maintainer-VM daily-driver readiness). *In flight on `worktree-almalinux-support` as v0.3.5 / phases 18–22.*
- **AL-59 alt-user hollow-install** (carried forward from v0.3.4, under Epic AL-48): the installer's alt-user path needs end-to-end wiring (20-sudoers.sh / 30-nodejs.sh / 40-path-wiring.sh still hardcode `agent`).
