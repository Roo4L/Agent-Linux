# Roadmap

**Current milestone:** 🚧 **v0.3.6 Catalog Expansion** — IN PROGRESS (phases **23–49**, one tool per phase; **22 new catalog entries** shipping + a categorization/growth-kit capstone; 4 of the 26 originally-selected candidates dropped in-flight — gitlab/brave on the source-selection gate, claude-flow/bmad on first-cohort demand). v0.3.4 Aware Installation Process **SHIPPED 2026-06-08** (final release v0.3.4, marked Latest).

## Current Milestone: v0.3.6 Catalog Expansion

**Milestone goal:** Grow the AgentLinux catalog from its 3 shipped entries (claude-code, gsd, playwright) with the most trusted/popular AI-agent-community tools — *availability only* (CAT-02 holds: nothing installed by default) — so first-release users don't hit "I miss tool X." A documented gates+scoring funnel (agent-relevance · clean per-user install + symmetric uninstall, no root, no `/usr/local` shim · free license · liveness ≤6mo release & ≤3mo commits · maturity) shortlisted **26 candidates**; **22 ship** after 4 in-flight drops (gitlab/brave failed the source-selection free-tier gate; claude-flow/bmad dropped on first-cohort demand — spec-kit/GSD cover that need).

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
- [x] **Phase 28: rtk** 🔧 `[bin]` - Rust Token Killer + prebuilt-binary installer enabler (ENABLE-01)
- [x] **Phase 29: gh** `[bin]` - GitHub CLI installable + removable ✓ COMPLETE (also generalized the ENABLE-01 helper: GitHub+GitLab hosts, Go-style asset naming)
- [x] **Phase 30: glab** `[bin]` - GitLab CLI (gitlab-org/cli) installable + removable ✓ COMPLETE
- [x] **Phase 31: trivy** `[bin]` - Trivy scanner (no-Docker fs/repo scans) installable + removable ✓ COMPLETE
- [x] **Phase 32: gitleaks** `[bin]` - Gitleaks secret scanner installable + removable ✓ COMPLETE
- [x] **Phase 33: sentry-cli** `[npm]` - Sentry CLI (FSL) installable + removable ✓ COMPLETE
- [x] **Phase 34: chrome-devtools-mcp** 🔧 `[mcp]` - Chrome DevTools MCP + MCP-recipe-pattern enabler (ENABLE-02) ✓ COMPLETE
- [ ] **Phase 35: context7** `[mcp]` - Context7 MCP server registerable + deregisterable
- [ ] **Phase 36: github-mcp** `[mcp]` - GitHub MCP (remote-http/PAT or Go-binary stdio, never Docker)
- [ ] **Phase 37: sentry-mcp** `[mcp]` - Sentry MCP (npx+token or hosted OAuth; FSL)
- [ ] **Phase 38: gitlab-mcp** `[mcp]` - GitLab MCP registerable + deregisterable
- [ ] **Phase 39: brave-search-mcp** `[mcp]` - DROPPED 2026-07-14 (Feb-2026 free tier removed; mandatory card + metered billing) — MCP-06 deferred
- [x] **Phase 40: firecrawl-mcp** `[mcp]` - Firecrawl MCP registerable + deregisterable ✓ COMPLETE (hosted keyless bare-URL, ADR-017 thin installer; cleared the free-tier gate gitlab/brave failed)
- [x] **Phase 41: slack-mcp** `[mcp]` - Slack MCP registerable + deregisterable ✓ COMPLETE (official first-party hosted `mcp.slack.com`, ADR-017 thin installer; supersedes the third-party stealth-token plan)
- [x] **Phase 42: linear-mcp** `[mcp]` - Linear MCP registerable + deregisterable ✓ COMPLETE (official first-party hosted `mcp.linear.app`, ADR-017 thin installer; free-tier confirmed; OAuth enabler already shipped in 36/37)
- [x] **Phase 43: jira-atlassian-mcp** `[mcp]` - Atlassian Rovo MCP registerable + deregisterable ✓ COMPLETE (official first-party hosted `mcp.atlassian.com`, ADR-017 thin installer; free-tier 500 calls/hr confirmed; cloud-only)
- [x] **Phase 44: spec-kit** 🔧 `[uv]` - GitHub Spec Kit + Python+uv-bootstrap enabler (ENABLE-03) ✓ COMPLETE (Docker 3/3; uv bootstrap + git-tag `uv tool install`; pin corrected 0.11.9→v0.12.11)
- [ ] **Phase 45: claude-flow** `[npm]` - DROPPED 2026-07-14 (maintainer: niche for the first-release cohort) — WORK-04 deferred
- [ ] **Phase 46: bmad** `[npm]` - DROPPED 2026-07-14 (maintainer: spec-kit/GSD cover the need, far more popular) — WORK-05 deferred
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
- [x] 28-03-PLAN.md — rtk recipe pair (install/uninstall) + catalog.json entry (source_kind binary, pin 0.42.4)
- [x] 28-04-PLAN.md — ENABLE-01/WORK-02/OPS-01 bats lifecycle test + docs/internals/catalog.md note

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
**Machinery**: `[mcp]` · pin `@upstash/context7-mcp@3.2.3` · npx · optional `CONTEXT7_API_KEY` per ENABLE-02
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
**Machinery**: `[mcp]` · **hosted remote** `https://mcp.sentry.dev/mcp` · pin `0.37.0` (curated `@sentry/mcp-server` release the endpoint is validated against) · **FSL-1.1-ALv2** license (Appendix B) · **thin installer per ADR-017** (bare URL, no credential; user auths in-client). *(Reconciled 2026-07-13: chose the hosted-remote shape over npx-stdio; the ADR-017 reframe replaced the "npx + SENTRY_ACCESS_TOKEN / token-not-baked" model.)*
**Success Criteria** (what must be TRUE):
  1. `agentlinux install sentry-mcp` registers the bare hosted URL `https://mcp.sentry.dev/mcp` into every installed MCP-capable agent via `claude mcp add --transport http --scope user` (+ the codex/gemini/opencode/qwen equivalents) — no root, zero EACCES; it appears in each present agent's config.
  2. NO credential is baked (ADR-017): the entry stores only the URL; `install` prints the in-client-auth pointer (Sentry OAuth on first use); the **FSL-1.1-ALv2** flag is recorded in the entry (`requires_secret: true` as a doc flag, no `secret_env`).
  3. `agentlinux remove sentry-mcp` deregisters symmetrically across all agents — no residue.
  4. ≥1 bats @test covers register → verify → deregister — TST-07 gate.
**Plans**: 37-01 (recipe pair + entry + helper retrofit + bats)

### Phase 38: gitlab-mcp
**Goal**: Make gitlab-mcp (GitLab MCP server) registerable + deregisterable via the catalog.
**Depends on**: Phase 37 (ENABLE-02 MCP entry kind)
**Requirements**: MCP-05
**Status**: **DROPPED 2026-07-13.** GitLab's official hosted MCP endpoint is paywalled (Premium/Ultimate; free users 404), and the maintainer declined the free third-party `@zereight/mcp-gitlab`. No entry shipped; MCP-05 deferred. See ADR-017 source-selection addendum. May revisit if GitLab frees the endpoint or the third-party is later accepted.
**Machinery** (not shipped): `[mcp]` · official hosted `https://gitlab.com/api/v4/mcp` (paywalled) OR third-party npx `@zereight/mcp-gitlab` (free, declined).
**Success Criteria** (what must be TRUE):
  1. `agentlinux install gitlab-mcp` registers the bare `https://gitlab.com/api/v4/mcp` into every installed MCP-capable agent via `claude mcp add --transport http --scope user` (+ codex/gemini/opencode/qwen equivalents) — no root, zero EACCES; it appears in each present agent's config.
  2. NO credential is baked (ADR-017): the entry stores only the URL; `install` prints the in-client-auth pointer (GitLab OAuth on first use); `requires_secret: true` as a doc flag, no `secret_env`.
  3. `agentlinux remove gitlab-mcp` deregisters symmetrically across all agents — no residue.
  4. ≥1 bats @test covers register → verify → deregister — TST-07 gate.
**Plans**: 37-... reuse; 38-01 (recipe pair + entry + bats)

### Phase 39: brave-search-mcp
**Goal**: Make brave-search-mcp (Brave Search MCP server) registerable + deregisterable via the catalog.
**Depends on**: Phase 38 (ENABLE-02 MCP entry kind)
**Requirements**: MCP-06
**Status**: **DROPPED 2026-07-14.** The phase premise "(free tier)" is falsified: Brave removed the card-free Search API tier in Feb 2026. New users now get only a metered ~$5/mo credit (~1,000 queries) that **requires a mandatory credit card as a live billing instrument** (no disclosed spend cap on overages) plus a Brave-attribution condition. Per the ADR-017 source-selection policy (free first-party = auto; everything else = per-case review) the maintainer dropped it — same gate GitLab failed. The server itself is official + MIT + a clean thin-installer fit; may revisit if Brave restores a genuine no-card free tier. No entry shipped; MCP-06 deferred.
**Machinery** (not shipped): `[mcp]` · `@brave/brave-search-mcp-server@2.0.85` (MIT) · stdio or self-host HTTP · `BRAVE_API_KEY` (paid/metered, card required — NOT free)
**Plans**: n/a (dropped)

### Phase 40: firecrawl-mcp ✓ COMPLETE
**Goal**: Make firecrawl-mcp (Firecrawl MCP server) registerable + deregisterable via the catalog.
**Depends on**: Phase 37 (ADR-017 thin-installer + credential-free remote-http helper)
**Requirements**: MCP-07
**Machinery**: `[mcp]` · **hosted remote-http** (ADR-017 prefer-hosted) · bare KEYLESS endpoint `https://mcp.firecrawl.dev/v2/mcp` · `pinned_version 3.22.3` (the validated upstream `firecrawl-mcp` release) · MIT
**Source decision (2026-07-14)**: firecrawl **clears** the ADR-017 source-selection gate that gitlab (38) + brave (39) failed — official first-party MCP, MIT, and a **genuinely card-free recurring free tier** (Free plan: 1,000 credits/month, "no cost, no card"). Qualifies as "free first party = auto-GO." Roadmap's npx-stdio+`FIRECRAWL_API_KEY` plan **superseded**: Firecrawl offers an official hosted endpoint with a KEYLESS tier, so we register the bare keyless URL via the credential-free `al_mcp_register_http` helper (cross-agent fan-out, ADR-017), like sentry-mcp. Works out of the box; a personal key (or self-host) is the user's optional in-client upgrade.
**Success Criteria** (what must be TRUE):
  1. `agentlinux install firecrawl-mcp` registers the bare keyless `https://mcp.firecrawl.dev/v2/mcp` into every installed MCP-capable agent (claude/codex/gemini/opencode/qwen) — no root, zero EACCES; it appears in each present agent's config. ✓
  2. NO credential is baked (ADR-017): the entry stores only the URL; `install` prints the keyless / optional-key upgrade pointer; `requires_secret: false`, no `secret_env`. ✓
  3. `agentlinux remove firecrawl-mcp` deregisters symmetrically across all agents — no residue; idempotent re-remove. ✓
  4. ≥1 bats @test (register bare URL → verify no-credential fan-out → deregister) is green — TST-07 gate. ✓ (`tests/bats/62-catalog-firecrawl-mcp.bats`)
**Plans**: executed inline (recipe pair + catalog entry + bats 62 + docs); offline smoke green.

### Phase 41: slack-mcp ✓ COMPLETE
**Goal**: Make slack-mcp (Slack MCP server) registerable + deregisterable via the catalog.
**Depends on**: Phase 37 (ADR-017 thin-installer + credential-free remote-http helper)
**Requirements**: MCP-08
**Machinery**: `[mcp]` · **official first-party hosted remote-http** · bare endpoint `https://mcp.slack.com/mcp` · `pinned_version 2026.2.17` (GA date; no downloadable release to pin) · no package license (proprietary hosted service)
**Source decision (2026-07-14)**: The roadmap's plan (third-party `slack-mcp-server@1.3.0` npx + `xoxp`/stealth-token warning) is **superseded**. Research found that **Slack shipped an official first-party hosted MCP server (GA Feb 2026)** at `https://mcp.slack.com/mcp` — Streamable HTTP, Slack-brokered OAuth 2.0, **workspace-admin-governed by design**, and **free** for workspace members (no paywall — not a gitlab/brave repeat). This is a "free official first-party hosted endpoint" → **auto-GO**. Using it **sidesteps the korotovsky stealth-token (xoxc/xoxd) governance-bypass footgun entirely** — we ship the admin-governed official endpoint only. ADR-017-aligned: bare URL, no baked credential, user OAuths in-client (subject to admin approval).
**Success Criteria** (what must be TRUE):
  1. `agentlinux install slack-mcp` registers the bare `https://mcp.slack.com/mcp` into every installed MCP-capable agent — no root, zero EACCES; it appears in each present agent's config. ✓
  2. NO credential is baked (ADR-017): the entry stores only the URL; `install` prints the in-client-auth pointer (Slack OAuth, admin-approved); `requires_secret: true` as a doc flag, no `secret_env`. NO Slack token (xoxb/xoxp/xoxc/xoxd) in any config. ✓
  3. `agentlinux remove slack-mcp` deregisters symmetrically across all agents — no residue; idempotent re-remove. ✓
  4. ≥1 bats @test (register bare URL → verify no-token fan-out → first-party-only recipe → deregister) is green — TST-07 gate. ✓ (`tests/bats/63-catalog-slack-mcp.bats`)
**Plans**: executed inline (recipe pair + catalog entry + bats 63 + docs); offline smoke green.

### Phase 42: linear-mcp ✓ COMPLETE
**Goal**: Make linear-mcp (official Linear MCP) registerable + deregisterable via the catalog.
**Depends on**: Phase 37 (ADR-017 thin-installer + credential-free remote-http helper)
**Requirements**: MCP-09
**Machinery**: `[mcp]` · **official first-party hosted remote-http** · bare endpoint `https://mcp.linear.app/mcp` · `pinned_version 2025.5.1` (GA date; no downloadable release) · no package license (proprietary hosted service)
**Source decision (2026-07-14)**: **Auto-GO** — Linear ships an official first-party hosted MCP (GA May 2025) at `https://mcp.linear.app/mcp` (Streamable HTTP, OAuth 2.1), and research **confirmed it is free-tier usable** (MCP rides on Linear's GraphQL API, a Free-plan core feature — NOT gated behind a paid plan, unlike the dropped gitlab endpoint; a pricing-table "MCP=Business" claim was verified to be a page-scrape hallucination). The roadmap's 🔧 "remote-http/OAuth **enabler**" is moot — that machinery shipped in Phase 36/37 (`al_mcp_register_http`, credential-free). Per **ADR-017** the recipe does NOT drive `claude mcp login`/`logout`: it registers the bare URL and bakes nothing; the user OAuths in-client; `remove` just deregisters (there is no AgentLinux-held token to log out).
**Success Criteria** (what must be TRUE):
  1. `agentlinux install linear-mcp` registers the bare `https://mcp.linear.app/mcp` into every installed MCP-capable agent — no root, zero EACCES; it appears in each present agent's config. ✓
  2. NO credential is baked (ADR-017): entry stores only the URL; `install` prints the in-client Linear-OAuth pointer; `requires_secret: true` doc flag, no `secret_env`; no Linear token (`lin_api_`/`lin_oauth_`) in any config. ✓
  3. `agentlinux remove linear-mcp` deregisters symmetrically across all agents — no residue; idempotent re-remove. ✓
  4. ≥1 bats @test (register bare URL → verify no-token fan-out → hosted-only recipe → deregister) is green — TST-07 gate. ✓ (`tests/bats/64-catalog-linear-mcp.bats`)
**Plans**: executed inline (recipe pair + catalog entry + bats 64 + docs); offline smoke green.

### Phase 43: jira-atlassian-mcp ✓ COMPLETE
**Goal**: Make jira-atlassian-mcp (official Atlassian Rovo MCP) registerable + deregisterable via the catalog.
**Depends on**: Phase 37 (ADR-017 thin-installer + credential-free remote-http helper)
**Requirements**: MCP-10
**Machinery**: `[mcp]` · **official first-party hosted remote-http** · bare endpoint `https://mcp.atlassian.com/v1/mcp/authv2` (Streamable-HTTP; SSE `/v1/sse` deprecated) · `pinned_version 2026.2.4` (GA date) · `license Apache-2.0` (official repo) · **cloud-only**
**Source decision (2026-07-14)**: **Auto-GO** — Atlassian ships an official first-party hosted MCP (the Rovo MCP Server, GA Feb 4 2026) covering Jira + Confluence at GA (more Atlassian products rolling out); OAuth 2.1 in-client. Research **confirmed free-tier usable**: Atlassian's platform page lists Free at 500 calls/hour and states *all* Cloud customers have access — NOT gated behind a paid plan or paid Rovo add-on (unlike the dropped gitlab endpoint). Per **ADR-017** the recipe registers the bare URL and bakes nothing; the user OAuths in-client; `remove` just deregisters (no AgentLinux-held token to log out — supersedes the roadmap's `claude mcp logout` step). **Modeling first:** this hosted endpoint has NO downloadable release (→ GA-date pin, like slack/linear) but DOES have an official Apache-2.0 repo (→ record `license: Apache-2.0`, like github/sentry) — version and license are independent axes.
**Success Criteria** (what must be TRUE):
  1. `agentlinux install jira-atlassian-mcp` registers the bare `https://mcp.atlassian.com/v1/mcp/authv2` into every installed MCP-capable agent — no root, zero EACCES; it appears in each present agent's config. ✓
  2. NO credential is baked (ADR-017): entry stores only the URL; `install` prints the in-client Atlassian-OAuth pointer + the cloud-only note; `requires_secret: true` doc flag, no `secret_env`; no Atlassian token (`ATATT`/`ATCTT`) in any config. ✓
  3. `agentlinux remove jira-atlassian-mcp` deregisters symmetrically across all agents — no residue; idempotent re-remove. ✓
  4. ≥1 bats @test (register bare URL → verify no-token fan-out → hosted-only recipe → deregister) is green — TST-07 gate. ✓ (`tests/bats/65-catalog-jira-atlassian-mcp.bats`)
**Plans**: executed inline (recipe pair + catalog entry + bats 65 + docs); offline smoke green.

### Phase 44: spec-kit
**Goal**: Make spec-kit (GitHub Spec Kit) installable + removable via the catalog, AND deliver the Python+uv-bootstrap enabler (ENABLE-03).
**Depends on**: Phase 43. First consumer of the Python+uv entry kind.
**Requirements**: WORK-03, ENABLE-03
**Machinery**: `[uv]` · 🔧 ENABLE-03 Python+uv bootstrap · **source_kind `script`** (no new enum — the CLI runs script/binary/mcp recipes identically) · pin **`v0.12.11` git tag** (roadmap's `specify-cli@0.11.9` was stale + wrong shape — spec-kit installs `uv tool install specify-cli --from git+…@vX.Y.Z`, verified vs upstream README + a real smoke) · uv binary bootstrap pin `0.11.28` (static musl) · project `.specify/` user-owned · **git is a host prereq** (uv installs from a git ref; recipe preflights it)
**Source decision (2026-07-14)**: **Auto-GO** — GitHub Spec Kit is an official first-party GitHub project, MIT, free, actively maintained. Free-first-party = no maintainer review needed. No credential dimension (offline/local dev tool).
**Success Criteria** (what must be TRUE):
  1. ENABLE-03: the catalog supports Python+uv entries — a per-user `uv` bootstraps into `~/.local/bin` (no root); install uses `uv tool`; uninstall is symmetric. ✓
  2. `agentlinux install spec-kit` installs `specify-cli` (git tag v0.12.11) via uv as the agent user (no root, zero EACCES); `specify` resolves at `~/.local/bin`. ✓
  3. Project `.specify/` is user-owned and is NOT removed by `agentlinux remove`. ✓
  4. `agentlinux remove spec-kit` uninstalls the uv tool symmetrically + tears down the AgentLinux-managed uv (marker-gated, only if no uv tools remain), never a user-brought uv; idempotent. ✓
  5. ≥1 bats @test (uv bootstrap → install → OPS-01 `specify init` → symmetric remove) green — TST-07 gate. ✓ (`tests/bats/66-catalog-spec-kit.bats`, Docker 3/3)
**Plans**: executed inline (uv-bootstrap helper + recipe pair + catalog entry + bats 66 + docs); real end-to-end smoke + Docker 3/3 green.

### Phase 45: claude-flow
**Goal**: Make claude-flow (Claude-Flow) installable + removable via the catalog, with full-footprint symmetric remove.
**Depends on**: Phase 44 (npm machinery)
**Requirements**: WORK-04
**Status**: **DROPPED 2026-07-14 (maintainer decision).** Judged too niche for the first-release cohort — the structured multi-agent-workflow need is already covered by spec-kit (Phase 44) and GSD, both far more popular. This is a demand/prioritization drop, **not** a source-gate failure (unlike gitlab/brave): `claude-flow@3.14.4` is npm, MIT, and a clean per-user install fit. Revisitable later — cheaply addable via the Phase 49 growth-kit contributor template (ENABLE-07) without touching CLI source. WORK-04 deferred.
**Machinery** (not shipped): `[npm]` · pin `claude-flow@3.14.4` · remove would clean `.claude`/`.swarm`/`.hive-mind`, MCP regs, hooks
**Plans**: n/a (dropped)

### Phase 46: bmad
**Goal**: Make bmad (BMAD-METHOD) installable + removable via the catalog.
**Depends on**: Phase 45 (npm machinery)
**Requirements**: WORK-05
**Status**: **DROPPED 2026-07-14 (maintainer decision).** Same rationale as Phase 45 — too niche for the first-release cohort; spec-kit (Phase 44) and GSD cover the spec-driven-workflow need and are far more popular. Demand/prioritization drop, **not** a source-gate failure: `bmad-method@6.9.0` is npm and MIT (GitHub shows `NOASSERTION`; MIT per Appendix B), a clean install fit. Revisitable via the Phase 49 growth-kit template (ENABLE-07) without CLI edits. WORK-05 deferred.
**Machinery** (not shipped): `[npm]` · pin `bmad-method@6.9.0` · remove would be symmetric over installed agents/packs
**Plans**: n/a (dropped)

### Phase 47: openclaw
**Goal**: Make openclaw (OpenClaw) installable + removable via the catalog, AND deliver the AI-assistant daemon-lifecycle enabler (ENABLE-04).
**Depends on**: Phase 44 (npm machinery; Phases 45–46 dropped). First consumer of the AI-assistant daemon entry kind.
**Requirements**: ASST-01, ENABLE-04
**Machinery**: `[daemon]` · 🔧 ENABLE-04 AI-assistant daemon lifecycle · pin `openclaw@2026.6.10` (npm + per-user daemon) · self-updater coexistence per ENABLE-05
**Source decision (2026-07-14)**: **GO (maintainer: build both ASST tools)**. openclaw = `openclaw/openclaw` (steipete), MIT, ~383k stars, self-hosted per-user daemon, BYO provider key, no paid backend — vetted per policy (daemon-class = not auto-GO, reviewed + approved). Node engines `>=22.19.0` satisfied by AgentLinux's Node 22 (latest v22.23.1).
**De-risk research (2026-07-14, container probe — findings for the build):**
  - Install: `npm install -g openclaw@2026.6.10` works as agent (agent npm prefix, no root, 297 pkgs, `openclaw` on PATH). Has a `postinstall` script (benign in probe).
  - Daemon lifecycle commands: `openclaw daemon {install,start,stop,restart,status,uninstall}` (native launchd/systemd), `openclaw gateway …` (run gateway as a plain process — testable without systemd), `openclaw health` / `openclaw status`, `openclaw doctor`. State dir `~/.openclaw` (mode 0700).
  - **Non-interactive + no-secret**: `openclaw onboard --non-interactive --accept-risk --auth-choice skip` sets up without baking any provider key (secrets NOT baked ✓).
  - **KEY CONSTRAINT**: `openclaw daemon install` uses **systemd `--user`** (linger) — the **Docker harness masks `systemd-logind`** (no `/run/user`, no user bus), so the systemd-user daemon path is **NOT testable in Docker** → it is a **QEMU-gated behavior** (ADR-007). Docker bats must verify the daemon via the **process-level `openclaw gateway` + `openclaw health`** path; the systemd-user install/linger lifecycle gets a QEMU test.
  - ENABLE-04 helper (proposed): `plugin/catalog/lib/daemon-lifecycle.sh` — enable-linger (agent sudo per ADR-012) + `openclaw daemon install/start`, a health-probe, and a symmetric `daemon uninstall` + `~/.openclaw` teardown + linger revert. Disable openclaw auto-update for ENABLE-05.
**Success Criteria** (what must be TRUE):
  1. ENABLE-04: the catalog supports AI-assistant daemon entries — `install` sets up a per-user background service (no root); `remove` tears it down with no stray daemon, unit, or state.
  2. `agentlinux install openclaw` installs `openclaw@2026.6.10` (npm + per-user daemon) as the agent user (no root, zero EACCES); the daemon runs per-user.
  3. Self-updater coexistence (ENABLE-05) holds — openclaw's pin stays authoritative; secrets are NOT baked.
  4. `agentlinux remove openclaw` tears down the daemon + state symmetrically — no stray unit/process/files; idempotent.
  5. ≥1 bats @test (install → daemon-up verify → remove → daemon-gone) is green — TST-07 gate.
**Status**: ✓ COMPLETE 2026-07-14 — Docker 4/4 green (ubuntu-24.04); ENABLE-04 helper `plugin/catalog/lib/daemon-lifecycle.sh` (linger + XDG + marker-gated revert) + openclaw recipe (`source_kind: script`, npm install + no-secret `onboard --auth-choice skip --skip-health` + `config patch` self-updater freeze `update.auto.enabled=false` + daemon lifecycle). Docker verifies the process-level `openclaw gateway run` path (credential-free HTTP-200 + `health ok:true`); the systemd-user daemon lifecycle self-gates with `skip` and runs under QEMU (ADR-007). `~/.openclaw` preserved on remove (CAT-04). Corrections vs research: config key is `update.auto.enabled` (not `autoUpdate`), written via `config patch --stdin`; onboard needs `--skip-health` for RC 0. AL-94 → Done.
**Plans**: 1/1 (main-agent direct execution, milestone convention).

### Phase 48: hermes-agent
**Goal**: Make hermes-agent (Hermes Agent) installable + removable via the catalog.
**Depends on**: Phase 47 (ENABLE-04 AI-assistant daemon entry kind)
**Requirements**: ASST-02
**Machinery**: `[daemon]` · pin `2026.6.19` (curl installer + per-user daemon/gateway)
**Source decision (2026-07-14)**: **GO (maintainer: build both ASST tools)**. Official = **`NousResearch/hermes-agent`** (Nous Research), open-source, ~214k stars, official curl installer `curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash` (installs uv + Python 3.11 + clones repo, no sudo), per-user daemon/gateway, BYO provider key. **Do NOT use the npm `hermes-agent`** (wyrtensi) — that is an UNOFFICIAL third-party bridge (v0.18.2), a different artifact. Supply-chain note: the official install is curl-pipe-bash; assess pinning/verification against AgentLinux's own installer bar (the curl-installer verifies sha256). Reuses ENABLE-04 from Phase 47.
**Success Criteria** (what must be TRUE):
  1. `agentlinux install hermes-agent` installs `hermes-agent` `2026.6.19` (official Nous Research curl installer + per-user daemon/gateway) as the agent user (no root, zero EACCES); the daemon/gateway runs per-user.
  2. Secrets are NOT baked — any gateway credentials supplied post-install.
  3. `agentlinux remove hermes-agent` tears down the daemon + gateway + state symmetrically — no residue; idempotent.
  4. ≥1 bats @test (install → daemon/gateway-up verify → remove → gone) is green — TST-07 gate.
**Plans**: TBD

### Phase 49: catalog growth kit
**Goal**: Deliver the `list` category/tags UX (ENABLE-06) and the catalog growth kit — a contributor recipe template + the selection-rubric doc (ENABLE-07). Milestone capstone — no new tool.
**Depends on**: Phases 23–48 (needs the full shipped catalog — 22 new entries after the gitlab/brave/claude-flow/bmad drops — to categorize and to validate template-only additions against)
**Requirements**: ENABLE-06, ENABLE-07
**Machinery**: `[meta]` · catalog-wide UX + contributor surface (extends CAT-03)
**Success Criteria** (what must be TRUE):
  1. ENABLE-06: `agentlinux list` groups catalog entries by category/tags (coding-agent · mcp · devops · token/workflow · assistant) — all 22 new entries appear under the correct category.
  2. ENABLE-07: a contributor recipe template + the selection-rubric doc are published — a new catalog entry can be added without touching CLI source (extends CAT-03).
  3. The growth kit is exercised end-to-end: a sample entry added via the template alone passes validate-catalog + install/remove with zero TypeScript edits.
  4. ≥1 bats @test covers `list` category grouping + the template-only-add path — TST-07 gate; milestone-close: all 22 new catalog entries install → verify → remove green across the Docker + QEMU gates.
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
| 28. rtk 🔧 | 3/4 | In Progress|  |
| 29. gh | 1/1 | Complete | 2026-07-02 |
| 30. glab | 1/1 | Complete | 2026-07-02 |
| 31. trivy | 1/1 | Complete | 2026-07-02 |
| 32. gitleaks | 1/1 | Complete | 2026-07-02 |
| 33. sentry-cli | 1/1 | Complete | 2026-07-02 |
| 34. chrome-devtools-mcp 🔧 | 1/1 | Complete | 2026-07-12 |
| 35. context7 | 1/1 | Complete | 2026-07-12 |
| 36. github-mcp 🔧 | 1/1 | Complete | 2026-07-13 |
| 37. sentry-mcp | 1/1 | Complete | 2026-07-13 |
| 38. gitlab-mcp | 0/0 | Dropped | 2026-07-13 |
| 39. brave-search-mcp | 0/0 | Dropped | 2026-07-14 |
| 40. firecrawl-mcp | 1/1 | ✓ Complete (Docker 2/2 green) | 2026-07-14 |
| 41. slack-mcp | 1/1 | ✓ Complete (Docker 2/2 green) | 2026-07-14 |
| 42. linear-mcp | 1/1 | ✓ Complete (Docker 2/2 green) | 2026-07-14 |
| 43. jira-atlassian-mcp | 1/1 | ✓ Complete (Docker 2/2 green) | 2026-07-14 |
| 44. spec-kit 🔧 | 1/1 | ✓ Complete (Docker 3/3 green) | 2026-07-14 |
| 45. claude-flow | 0/0 | Dropped | 2026-07-14 |
| 46. bmad | 0/0 | Dropped | 2026-07-14 |
| 47. openclaw 🔧 | 1/1 | ✓ Complete (Docker 4/4 green; systemd-user QEMU-gated) | 2026-07-14 |
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
