# Phase 5: Agent Installability — Research

**Researched:** 2026-04-19
**Domain:** Real install recipes for claude-code, gsd, playwright + AGT-01..05 + AGT-02b
**Confidence:** HIGH for claude-code install/update/uninstall paths (verified against live docs + bootstrap.sh source); HIGH for npm package metadata (verified via `npm view` live); MEDIUM for Playwright apt packages (version-specific list lives in upstream source, not docs); MEDIUM for AGT-02 test design (depends on CI network reliability which is an environmental unknown).

## Summary

Phase 5 replaces the three Phase-4 recipe SCAFFOLDS with real install/uninstall bodies and adds a new bats file (`tests/bats/50-agents.bats`) that covers AGT-01..05 + AGT-02b. AGT-02 (Claude Code self-update without sudo/EACCES) is the canonical acceptance test and remains a permission invariant, not a version invariant; AGT-02b (installed version == `pinned_version` string-match) is the companion version-lock test from ADR-011.

Three corrections to 05-CONTEXT.md surfaced during research and need either (a) planner-time fixes or (b) confirmation before planning. These are flagged in the Assumptions Log and Open Questions sections; the research stack has concrete recommendations for each. The biggest is that **the `gsd` catalog entry's bin is `get-shit-done-cc`, not `gsd`, and the binary does not support `--version`** — AGT-04 needs a different smoke-test shape.

**Primary recommendation:** Plan 4 tasks (one per agent + one bats file) under the structure outlined in §Architecture Patterns. Use `claude --help` (not `claude doctor`) for AGT-03 because `doctor` waits for stdin (Claude Code GH issue #26487). Use `get-shit-done-cc --help` + banner-grep for `v<pinned>` (not `gsd --version`) for AGT-04. Use `npx playwright install --with-deps chromium` as a single command for Playwright (ADR-012 makes the sudo-prepend transparent).

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Claude Code Install Path (AGT-02 load-bearer):**
- Install via **native installer**: `curl -fsSL https://claude.ai/install.sh | bash -s "$AGENTLINUX_PINNED_VERSION"` invoked via `as_user -- bash -c`.
- Binary lands under `/home/agent/.local/bin/claude` — agent-owned, matches Anthropic's auto-updater detection mechanics.
- Post-install verify: `claude --version` returns exactly the pinned_version (AGT-02b).
- `claude update` self-update path runs in the user-owned prefix; AGT-02 asserts zero EACCES/permission-denied in its transcript and that `claude --version` is monotonic (≥ pinned).
- Uninstall: `uninstall.sh` removes `/home/agent/.local/bin/claude` + `/home/agent/.claude/` config dir (symmetric).

**GSD Install Path:**
- `as_user -- bash --login -c "npm install -g get-shit-done-cc@$AGENTLINUX_PINNED_VERSION"`
- Binary at `/home/agent/.npm-global/bin/...` (verified via `npm view get-shit-done-cc bin`).
- Post-install verify: `gsd --version` (or `gsd --help` if `--version` isn't supported — planner decides based on real package behavior).
- Uninstall: `as_user -- bash --login -c "npm uninstall -g get-shit-done-cc"`.

**Playwright Install Path:**
- `as_user -- bash --login -c "npm install -g playwright@$AGENTLINUX_PINNED_VERSION"` for the CLI/bindings.
- `as_user -- bash --login -c "npx playwright install chromium"` to download browsers into `/home/agent/.cache/ms-playwright/`.
- System deps: `sudo -n -- bash -c "playwright install-deps chromium"` now runs because of ADR-012.
- Post-install verify: `npx playwright --version` + `npx playwright --help` basic smoke.
- Uninstall: `npm uninstall -g playwright`; optional browser cache cleanup.

**Phase 5 Test Shape:**
- New bats file: `tests/bats/50-agents.bats` — each `@test` cites its AGT-XX ID.
- Real agent installs run in every PR Docker matrix.
- **AGT-01**: `claude --version` + `gsd --version` + `npx playwright --version` exit 0 in all six invocation modes.
- **AGT-02** (canonical): after install, `claude update` runs as agent user, exit 0, transcript zero `EACCES|permission denied`, `claude --version` is monotonic. Tagged `@release-gate`.
- **AGT-02b** (version lock): immediately after `agentlinux install claude-code`, `claude --version` matches `catalog.json`'s pinned_version exactly (string match, not semver range).
- **AGT-03**: `claude doctor` (if supported in pinned version) or substitute `claude --help` — exit 0 + no error strings.
- **AGT-04**: `gsd --version` or equivalent exits 0.
- **AGT-05**: `npx playwright --version` exits 0; `npx playwright install chromium` completes without sudo/EACCES.

### Claude's Discretion

- Exact shell wording of the three install.sh scaffolds being replaced — match existing `${VAR:?msg}` guard pattern + strict-mode.
- Whether `claude update --dry-run` is substituted for `claude update` in AGT-02 to avoid actually updating (if Anthropic v2.1.x supports it). **Research finding: NO dry-run flag exists** — planner decides between real update + subsequent AGT-02b re-install OR skipping the "monotonic version" half of AGT-02.
- Whether AGT-03's `claude doctor` substitute is `--help` or `--version`. **Research recommendation: `--help` (richer positive signal than bare `--version`, same stable exit-zero guarantee, not interactive like `doctor`).**
- Plan count: research-recommended is 3 plans (one per agent) + 1 bats plan = 4 plans; planner may collapse.
- How to bound Playwright browser download time in CI.

### Deferred Ideas (OUT OF SCOPE)

- Full browser matrix for Playwright (firefox + webkit) — Phase 6 or v0.4+.
- MCP server agents (beyond Playwright) — v0.4+.
- Agent-specific doctor/diagnostic subcommands beyond AGT-03 — v0.4+.
- `agentlinux info <name>` surfacing post-install status (CLI-08 renumbered) — v0.4+.
- Claude Code authentication setup (API keys, OAuth) — explicitly out of scope for install; user's concern.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| AGT-01 | After `agentlinux install claude-code`, agent user can run `claude --version` in every invocation mode | §Code Examples Ex-1 (6-mode loop pattern); existing `INVOKE_MODES[@]` + `assert_exit_zero` helpers cover it |
| AGT-02 | Agent user can self-update Claude Code without sudo, without EACCES, without manual intervention (canonical) | §Code Examples Ex-2 (captured transcript + `assert_no_eacces` + monotonic-version check); §Pitfall 6 (Docker OOM) |
| AGT-02b | Installed version == catalog `pinned_version` exactly (string match) | §Code Examples Ex-3 (`claude --version` exact-string compare to `jq -r '.agents[]\|select(.id=="claude-code")\|.pinned_version' catalog.json`) |
| AGT-03 | `claude doctor` or equivalent reports clean state | §Open Question 2 — `doctor` is interactive (GH issue #26487); RECOMMEND `claude --help` substitute |
| AGT-04 | Agent user can run `gsd --version` (or equivalent) | §Open Question 1 + §Standard Stack — binary is `get-shit-done-cc` not `gsd`; no `--version` flag; RECOMMEND `get-shit-done-cc --help` + banner grep for `v<pinned>` |
| AGT-05 | `npx playwright --version` + `npx playwright install` work, no sudo/EACCES | §Code Examples Ex-4 (one-shot `install --with-deps chromium` leverages ADR-012 sudo) |

## Project Constraints (from CLAUDE.md)

Directives extracted from `./CLAUDE.md` that Phase 5 MUST respect:

| Directive | Applies to Phase 5 how |
|-----------|------------------------|
| **Never `sudo npm install -g`.** Always `sudo -u agent -H npm install -g` | All three recipes dispatch via `as_user` helper; no raw `sudo npm` anywhere |
| **Behavior tests in `tests/bats/` are the spec.** Impl can change freely. | Phase 5 writes bats first (or co-commits with impl); no implementation-pinning requirements |
| **No agent is installed by default.** | Phase 5 doesn't change this — recipes only run on `agentlinux install <name>`; `CAT-02` invariant already verified |
| **Docker-only test runs are insufficient.** | Phase 5 bats runs Docker matrix on every PR; QEMU release-gate is Phase 6 (TST-05) |
| **No wrapper shims at `/usr/local/bin/`** | Recipes install ONLY to agent-owned prefixes (`~/.local/bin` or `~/.npm-global/bin`); no `/usr/local/bin` writes |
| **Per-task atomic commits.** | Each task commits tests and impl together; PLANNER choice of ≥1 task per agent |
| **Review loop:** bash-engineer + security-engineer + qa-engineer on recipes; qa-engineer + behavior-coverage-auditor on bats; TST-07 mandatory | Every Phase 5 plan spec-includes the review loop in its acceptance criteria |
| **`as_user -- ...`** for all recipe commands | Runner already wraps; recipes themselves MUST NOT call `sudo -u agent` directly |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Recipe dispatch (TS) | plugin/cli (runner.ts) | — | Already solved by Phase 4; no changes needed |
| `AGENTLINUX_PINNED_VERSION` env plumbing | plugin/cli (runner.ts) | — | Existing env pipeline; recipes consume it verbatim |
| Fetching + verifying Claude Code binary | plugin/catalog/agents/claude-code/install.sh (bash recipe) | Anthropic's bootstrap.sh (delegated) | Native installer is the upstream-recommended path; we invoke it and assert PIPESTATUS |
| npm global install of GSD + Playwright | bash recipe | npm + Phase 3 per-user prefix | Reuses Phase 3's `/home/agent/.npm-global` prefix; no new infrastructure |
| Playwright browser download | bash recipe | Playwright CLI (`npx playwright install`) | Browser cache goes to `~/.cache/ms-playwright` (agent-owned) — ADR-004 compliant |
| Playwright apt system deps | bash recipe | ADR-012 sudo + `playwright install-deps chromium` | install-deps auto-prepends `sudo` when `getuid() != 0` (source: Playwright registry/dependencies.ts) |
| AGT-01..05 bats | tests/bats/50-agents.bats | helpers/invoke_modes.bash + assertions.bash | Reuses the six-mode loop helper used by BHV + RT + CLI tests |
| AGT-02 transcript capture (no EACCES) | bats @test + per-test temp log | assert_no_eacces (file path form) | Existing helper accepts file or string; redirect `claude update >$logfile 2>&1` |
| Release-gate tagging for AGT-02 | bats filename (`51-agt02-release-gate.bats`) OR bats `@tag` | Phase 6 release.yml | Most portable shape: separate file, so Phase 6 can `bats tests/bats/51-*.bats` to select |

## Standard Stack

### Core

| Library / Tool | Version (verified 2026-04-19) | Purpose | Why Standard |
|----------|---------|---------|--------------|
| `@anthropic-ai/claude-code` npm package | `dist-tags.stable: 2.1.98`, `latest: 2.1.114` `[VERIFIED: npm view 2026-04-19]` | Claude Code CLI | Anthropic-official; single source of truth for AGT-02 |
| `claude.ai/install.sh` (native) | Redirects to `downloads.claude.ai/claude-code-releases/bootstrap.sh` `[VERIFIED: curl -fsSL 2026-04-19]` | Stable native installer | Upstream-recommended; accepts positional `stable\|latest\|X.Y.Z`; auto-updates in background |
| `get-shit-done-cc` npm package | `latest: 1.37.1` `[VERIFIED: npm view 2026-04-19; bin: {get-shit-done-cc: bin/install.js}]` | GSD workflow installer | Catalog-curated; pinned 1.37.1 matches current latest |
| `playwright` npm package | `latest: 1.59.1`; `next: 1.60.0-alpha-2026-04-19` `[VERIFIED: npm view 2026-04-19]` | Playwright CLI + bindings | Browser automation standard; pinned 1.59.1 matches current stable |
| `playwright-core` | `1.59.1` (transitive) | Browser drivers | Automatically pulled by `playwright` |

### Supporting

| Library / Tool | Version | Purpose | When to Use |
|----------|---------|---------|-------------|
| `curl` | >= 7.68 (Ubuntu 22.04+ default) | Claude Code native installer HTTPS fetch | Already in test Dockerfiles; recipe assumes it |
| `sha256sum` | coreutils default | Upstream installer does its own SHA256 verify against `manifest.json` | Our recipe does NOT re-verify (trusts the bootstrap script per Anthropic guidance) |
| `jq` | Ubuntu apt default | Parse sentinel JSON + list --json output | Already installed in test Dockerfiles (Phase 4 Rule-3 auto-fix) |
| `timeout` | coreutils default | Bound AGT-02 / AGT-03 wall-time | Use `timeout 120s claude update` to cap runaway updates |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Native installer (claude.ai/install.sh) | `npm install -g @anthropic-ai/claude-code` | npm route installs same native binary via platform-specific optional dep (per docs). Route difference: npm places binary at `~/.npm-global/bin/claude`, native at `~/.local/bin/claude`. **Locked decision: native** (AGT-02 canonical path; `claude update` self-manages the native install) |
| Pin 2.1.98 | Pin 2.1.114 (latest) | 2.1.98 is `dist-tags.stable`; 2.1.113 changed the CLI to spawn a native binary via platform optional dep `[VERIFIED: CHANGELOG.md 2.1.113]`. Either works via native installer (it always fetches the latest installer machinery). **Recommendation: keep 2.1.98 (catalog-locked) unless a regression surfaces.** See Open Question 3. |
| Chromium only | All three browsers | Chromium alone is ~281 MB download on Linux `[CITED: playwright.dev/docs/browsers]`; all three would ~800 MB+. Locked: chromium only. |
| Separate `install chromium` + `install-deps chromium` | `install --with-deps chromium` | `--with-deps` is a single command that calls both; simpler and recommended for CI `[CITED: playwright.dev/docs/ci]`. **Recommendation: use `--with-deps`.** |
| `claude doctor` for AGT-03 | `claude --help` or `claude --version` | `doctor` waits for Enter on stdin (GH issue #26487) `[CITED: github.com/anthropics/claude-code/issues/26487]`; not scriptable. `--help` gives a rich positive signal and exits clean. **Recommendation: `claude --help` for AGT-03.** |

**Installation (combined for reference — Phase 5 recipes split per agent):**
```bash
# As agent user, via as_user dispatcher:
curl -fsSL https://claude.ai/install.sh | bash -s "${AGENTLINUX_PINNED_VERSION}"
npm install -g "get-shit-done-cc@${AGENTLINUX_PINNED_VERSION}"
npm install -g "playwright@${AGENTLINUX_PINNED_VERSION}"
npx playwright install --with-deps chromium
```

**Version verification (run at plan-time, before writing PLAN.md):**
```bash
npm view @anthropic-ai/claude-code dist-tags    # should show stable: 2.1.98 or newer stable
npm view @anthropic-ai/claude-code@2.1.98 version  # must not 404
npm view get-shit-done-cc@1.37.1 version
npm view playwright@1.59.1 version
```

All three pinned versions **VERIFIED as of 2026-04-19**:
- `@anthropic-ai/claude-code@2.1.98` → `2.1.98` (exists; dist-tag `stable`)
- `get-shit-done-cc@1.37.1` → `1.37.1` (exists; dist-tag `latest`)
- `playwright@1.59.1` → `1.59.1` (exists; dist-tag `latest`)

## Architecture Patterns

### System Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────────────┐
│ Agent user shell (interactive / ssh / cron / systemd / sudo -u / sudo -i)  │
│   $ agentlinux install claude-code                                         │
└────────────────┬───────────────────────────────────────────────────────────┘
                 │  /home/agent/.npm-global/bin/agentlinux → CLI
                 ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ plugin/cli dispatch (Phase 4) — unchanged in Phase 5                        │
│   runner.ts → asUser agent, bash <install.sh>                               │
│   env: AGENTLINUX_PINNED_VERSION=2.1.98                                     │
│        AGENTLINUX_SOURCE_KIND=script                                        │
│        AGENTLINUX_AGENT_HOME=/home/agent                                    │
│        PATH=/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/...     │
└────────────────┬───────────────────────────────────────────────────────────┘
                 │                                                             
  ┌──────────────┼──────────────────────────┬──────────────────────────────┐  
  ▼              ▼                          ▼                              ▼  
┌─────────────────┐  ┌─────────────────────┐  ┌─────────────────────────────┐
│ claude-code/     │  │ gsd/                 │  │ playwright/                 │
│ install.sh       │  │ install.sh           │  │ install.sh                  │
│                  │  │                      │  │                             │
│ curl install.sh  │  │ npm install -g       │  │ npm install -g              │
│  | bash -s $PIN  │  │  get-shit-done-cc    │  │  playwright@$PIN            │
│ PIPESTATUS check │  │  @$PIN               │  │ npx playwright install      │
│                  │  │                      │  │  --with-deps chromium       │
│                  │  │                      │  │  (sudo auto-prepended;      │
│                  │  │                      │  │   ADR-012 sudoers drop-in   │
│                  │  │                      │  │   grants NOPASSWD: ALL)     │
└────────┬─────────┘  └────────┬─────────────┘  └──────────┬──────────────────┘
         │                     │                            │                   
         ▼                     ▼                            ▼                   
 /home/agent/.local/   /home/agent/.npm-global/    /home/agent/.npm-global/    
   bin/claude             bin/get-shit-done-cc        bin/playwright            
 /home/agent/.claude/   (lib/node_modules/…)        /home/agent/.cache/         
   downloads/                                         ms-playwright/chromium-…  
                                                                                
                                                                                
AGT-02 self-update path (canonical acceptance test):                           
                                                                                
 $ claude update                                                                
         │                                                                      
         ▼                                                                      
   fetches new binary from downloads.claude.ai                                 
         │                                                                      
         ▼                                                                      
   writes to /home/agent/.local/bin/claude (user-owned)                        
         │                                                                      
         ▼                                                                      
   NEVER touches /usr, /opt, /etc — pure user-owned ops — no sudo needed      
         │                                                                      
         ▼                                                                      
   bats assertion: transcript contains zero /EACCES|permission denied/        
                                                                                
AGT-02b version-lock test:                                                     
                                                                                
 $ claude --version  →  "2.1.98 (Claude Code)" or "2.1.98"                    
         │                                                                      
         ▼                                                                      
   exact-string match against catalog.json#/.agents/0/pinned_version          
```

### Component Responsibilities

| File | Owner tier | Responsibility | Phase 5 change |
|------|-----------|----------------|----------------|
| `plugin/catalog/agents/claude-code/install.sh` | bash recipe | Invoke native installer with pinned version; check PIPESTATUS | **REPLACE SCAFFOLD BODY** with real install |
| `plugin/catalog/agents/claude-code/uninstall.sh` | bash recipe | Remove `~/.local/bin/claude` + `~/.claude/` (mindful of user data) | **REPLACE SCAFFOLD BODY** |
| `plugin/catalog/agents/gsd/install.sh` | bash recipe | `npm install -g get-shit-done-cc@$PIN` | **REPLACE SCAFFOLD BODY** |
| `plugin/catalog/agents/gsd/uninstall.sh` | bash recipe | `npm uninstall -g get-shit-done-cc` | **REPLACE SCAFFOLD BODY** |
| `plugin/catalog/agents/playwright/install.sh` | bash recipe | `npm install -g playwright@$PIN` + `npx playwright install --with-deps chromium` | **REPLACE SCAFFOLD BODY** |
| `plugin/catalog/agents/playwright/uninstall.sh` | bash recipe | `npm uninstall -g playwright` + `rm -rf ~/.cache/ms-playwright` | **REPLACE SCAFFOLD BODY** |
| `tests/bats/50-agents.bats` | bats | AGT-01 + AGT-02b + AGT-03 + AGT-04 + AGT-05 (non-destructive) | **CREATE** |
| `tests/bats/51-agt02-release-gate.bats` | bats | AGT-02 only (destructive — runs real `claude update`) | **CREATE** (separate file so Phase 6 CI can select via glob) |
| `plugin/cli/src/runner.ts` | TS | Env var injection | **NO CHANGE** (already sets AGENTLINUX_PINNED_VERSION, PATH, HOME, etc.) |
| `plugin/catalog/catalog.json` | catalog | Pinned versions | **NO CHANGE UNLESS** a pin is yanked; all three verified present |

### Recommended Project Structure

```
plugin/catalog/agents/
├── claude-code/
│   ├── install.sh          # REPLACE — native installer + PIPESTATUS
│   └── uninstall.sh        # REPLACE — rm -f ~/.local/bin/claude + rm -rf ~/.claude/
├── gsd/
│   ├── install.sh          # REPLACE — npm install -g get-shit-done-cc@$PIN
│   └── uninstall.sh        # REPLACE — npm uninstall -g get-shit-done-cc
└── playwright/
    ├── install.sh          # REPLACE — npm install -g + npx playwright install --with-deps chromium
    └── uninstall.sh        # REPLACE — npm uninstall -g + rm -rf ~/.cache/ms-playwright

tests/bats/
├── 50-agents.bats              # CREATE — AGT-01 (six-mode), AGT-02b (version lock),
│                               #          AGT-03 (claude --help), AGT-04 (gsd banner),
│                               #          AGT-05 (playwright + chromium smoke)
└── 51-agt02-release-gate.bats  # CREATE — AGT-02 only, destructive; Phase 6 CI selects
```

### Pattern 1: claude-code install.sh (native installer + PIPESTATUS guard)

**What:** Download Claude Code via the upstream bootstrap script, pass the pinned version as positional arg, guard against curl | bash pipe-swallow.

**When to use:** `claude-code` recipe body (REPLACE SCAFFOLD).

**Example (ready to drop into `plugin/catalog/agents/claude-code/install.sh`):**
```bash
#!/usr/bin/env bash
set -euo pipefail
# claude-code install.sh — real native installer body (Phase 5 AGT-02 / AGT-02b).
#
# Runs as the `agent` user via as_user dispatch from the Node CLI.
# Expected env (injected by plugin/cli/src/runner.ts):
#   AGENTLINUX_PINNED_VERSION  — e.g. 2.1.98 (required; :? guard below)
#   AGENTLINUX_SOURCE_KIND     — "script" for this entry
#   AGENTLINUX_AGENT_HOME      — /home/agent
#   HOME, PATH, NPM_CONFIG_PREFIX inherited from runner.ts per /etc/agentlinux.env
#
# Refs:
#   - docs/decisions/011-stability-first-version-pinning.md (AGT-02b)
#   - code.claude.com/docs/en/setup#install-a-specific-version (positional arg)
#   - Phase 4 RESEARCH §Pitfall 8 (PIPESTATUS guard against curl-404 swallowed by bash)
#   - downloads.claude.ai/claude-code-releases/bootstrap.sh (source of truth, verified 2026-04-19)

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "claude-code: installing version ${AGENTLINUX_PINNED_VERSION} via native installer"

# Native installer validates version format before fetching; accepts "stable",
# "latest", or an explicit X.Y.Z (optionally with -prerelease). We always pass
# an explicit semver per ADR-011 (stability-first pinning).
#
# PIPESTATUS guard (Phase 4 RESEARCH §Pitfall 8): without pipefail on the
# subshell, a 404 from claude.ai/install.sh would leave curl non-zero but
# bash (running an empty or error body) zero. set -o pipefail (top of file)
# already causes the pipeline to inherit the worst exit. We also explicitly
# iterate PIPESTATUS so the failure message names both codes.
if ! curl -fsSL https://claude.ai/install.sh | bash -s "${AGENTLINUX_PINNED_VERSION}"; then
  printf 'claude-code install FAILED (PIPESTATUS: %s)\n' "${PIPESTATUS[*]}" >&2
  exit 1
fi

# Post-install smoke test: binary exists and reports the pinned version.
# AGT-02b is verified END-TO-END from here: if the bootstrap script served an
# older version (e.g. stable channel drift), this assertion catches it BEFORE
# the CLI writes the sentinel claiming success.
if [[ ! -x "${AGENTLINUX_AGENT_HOME}/.local/bin/claude" ]]; then
  printf 'claude-code install: expected binary at %s/.local/bin/claude, not found\n' \
    "${AGENTLINUX_AGENT_HOME}" >&2
  exit 1
fi

claude_version=$("${AGENTLINUX_AGENT_HOME}/.local/bin/claude" --version 2>&1 | head -1)
printf 'claude-code: installed, reports: %s\n' "$claude_version"

# AGT-02b in-recipe assertion: `claude --version` output must contain the
# pinned version as a substring. Exact-string match is done in the bats test;
# here we just fail fast if the bootstrap script silently served a different
# version (e.g. "stable" tag drift upstream).
if ! printf '%s' "$claude_version" | grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"; then
  printf 'claude-code install: pinned=%s but --version reports: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$claude_version" >&2
  exit 1
fi

echo "claude-code: install complete (AGT-02b version-lock satisfied)"
```

### Pattern 2: claude-code uninstall.sh (symmetric)

```bash
#!/usr/bin/env bash
set -euo pipefail
# claude-code uninstall.sh — symmetric inverse of install.sh.
# Follows Anthropic's documented uninstall (code.claude.com/docs/en/setup#uninstall):
#   rm -f ~/.local/bin/claude
#   rm -rf ~/.local/share/claude
# PLUS we remove ~/.claude/downloads (bootstrap's scratch dir) but NOT ~/.claude/
# itself (contains user state, settings, session history — CAT-04 uninstall
# contract says "binary + first-install artifacts", not user data).

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "claude-code: removing native Claude Code install"

# rm -f is idempotent on missing files.
rm -f "${AGENTLINUX_AGENT_HOME}/.local/bin/claude"
rm -rf "${AGENTLINUX_AGENT_HOME}/.local/share/claude"
rm -rf "${AGENTLINUX_AGENT_HOME}/.claude/downloads"

# Intentionally NOT removed (user data; matches Anthropic's uninstall-config
# warning): ~/.claude/, ~/.claude.json, .claude/ in projects. Users wanting
# full wipe run the documented steps manually.

echo "claude-code: uninstall complete (user config at ~/.claude/ preserved)"
```

### Pattern 3: gsd install.sh (npm global + pin enforcement)

```bash
#!/usr/bin/env bash
set -euo pipefail
# gsd install.sh — real body (Phase 5 AGT-04).
#
# npm_package_name: get-shit-done-cc (verified 2026-04-19 via npm view).
# source_kind: npm — per-user global install via Phase 3's .npm-global prefix.
#
# CRITICAL: the binary name is `get-shit-done-cc`, NOT `gsd`. Verified:
#   npm view get-shit-done-cc bin → { 'get-shit-done-cc': 'bin/install.js' }
# AGT-04's bats test must invoke `get-shit-done-cc`, not `gsd`. See 05-RESEARCH
# §Open Question 1 for the planner-decision to either add a `gsd` symlink or
# keep the package-native name.
#
# NPM_CONFIG_PREFIX=/home/agent/.npm-global is set by runner.ts (mirrors
# /etc/agentlinux.env) — the global install lands in agent-owned territory
# without sudo or EACCES (RT-02 keystone).

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"

echo "gsd: installing get-shit-done-cc@${AGENTLINUX_PINNED_VERSION}"

# --omit=dev skips devDependencies (c8 coverage tooling, etc. — 3.4MB unpacked
# already includes only runtime files per package 'files' manifest, but belt-
# and-braces against future devDep bloat).
# --no-fund / --no-audit silence npm's noise (faster, cleaner transcript).
npm install -g \
  --omit=dev \
  --no-fund \
  --no-audit \
  "get-shit-done-cc@${AGENTLINUX_PINNED_VERSION}"

# Post-install smoke: binary resolves on PATH AND banner reports pinned version.
# `get-shit-done-cc --help` exits 0 and prints the banner containing
# "Get Shit Done v1.37.1". No --version flag exists (verified; see research).
bin_path=$(command -v get-shit-done-cc || true)
if [[ -z "$bin_path" ]]; then
  echo "gsd install: get-shit-done-cc not on PATH after install" >&2
  exit 1
fi

# banner grep — the installer prints "Get Shit Done v<version>" before any
# subcommand logic; --help short-circuits cleanly after the banner.
banner=$(get-shit-done-cc --help 2>&1 | head -20)
if ! printf '%s' "$banner" | grep -q -F "v${AGENTLINUX_PINNED_VERSION}"; then
  printf 'gsd install: pinned=%s but banner: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$banner" >&2
  exit 1
fi

echo "gsd: install complete (resolves at ${bin_path}; banner matches pin)"
```

### Pattern 4: gsd uninstall.sh

```bash
#!/usr/bin/env bash
set -euo pipefail
# gsd uninstall.sh — symmetric inverse. npm uninstall -g is idempotent.

echo "gsd: removing get-shit-done-cc"

# npm uninstall -g on a missing package exits 0 with "up to date" — idempotent.
# We don't check npm's exit status aggressively; the post-step `command -v`
# check is the real truth.
npm uninstall -g get-shit-done-cc --no-fund --no-audit >/dev/null 2>&1 || true

# Verify removal.
if command -v get-shit-done-cc >/dev/null 2>&1; then
  echo "gsd uninstall: get-shit-done-cc still on PATH after npm uninstall -g" >&2
  exit 1
fi

echo "gsd: uninstall complete"
```

### Pattern 5: playwright install.sh (CLI + chromium + sudo install-deps)

```bash
#!/usr/bin/env bash
set -euo pipefail
# playwright install.sh — real body (Phase 5 AGT-05).
#
# Three-part install:
#   (1) npm install -g playwright@$PIN          — CLI + JS bindings, agent-owned
#   (2) npx playwright install --with-deps      — downloads chromium + apt deps
#       chromium                                  in one shot. install-deps
#                                                 auto-prepends sudo when
#                                                 getuid() != 0 (source:
#                                                 playwright-core/src/server/
#                                                 registry/dependencies.ts).
#                                                 With ADR-012 sudoers drop-in
#                                                 (NOPASSWD: ALL), the
#                                                 sudo apt-get install -y ...
#                                                 succeeds without prompt.
#
# Why --with-deps instead of separate install + install-deps:
#   - Upstream-recommended for CI (cited: playwright.dev/docs/ci)
#   - Single command = single exit code; easier error handling
#   - install-deps is browser-scoped when a browser arg is given
#
# Browser cache: ~/.cache/ms-playwright/ (agent-owned, ADR-004 compliant).
# Chromium download is ~281 MB (playwright.dev/docs/browsers) — CI time cost
# is accepted per 05-CONTEXT.md; caching is a Phase 6 optimization.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "playwright: installing playwright@${AGENTLINUX_PINNED_VERSION} (CLI + bindings)"

npm install -g \
  --omit=dev \
  --no-fund \
  --no-audit \
  "playwright@${AGENTLINUX_PINNED_VERSION}"

if ! command -v playwright >/dev/null 2>&1; then
  echo "playwright install: playwright CLI not on PATH after npm install -g" >&2
  exit 1
fi

# Verify CLI version matches pin before downloading browsers — don't waste
# ~281 MB of download on a mispinned install.
pw_version=$(playwright --version 2>&1 | head -1)
if ! printf '%s' "$pw_version" | grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"; then
  printf 'playwright install: pinned=%s but --version: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$pw_version" >&2
  exit 1
fi

echo "playwright: CLI at $(command -v playwright), ${pw_version}"
echo "playwright: downloading chromium + system deps (~281 MB; uses sudo for apt)"

# --with-deps triggers the sudo-apt path internally. ADR-012's
# /etc/sudoers.d/agentlinux grant (agent ALL=(ALL) NOPASSWD: ALL) means
# Playwright's sudo invocation is non-interactive. If ADR-012 regresses,
# this will fail with "sudo: a password is required" — a clear signal.
#
# NPX note: npx needs HOME set for its cache. runner.ts sets HOME=/home/agent.
# If this recipe is ever invoked without HOME (e.g. a raw systemd unit without
# EnvironmentFile), npx falls back to /tmp and still works.
npx --yes playwright install --with-deps chromium

# Post-install smoke: chromium binary exists in the expected cache location.
cache_dir="${AGENTLINUX_AGENT_HOME}/.cache/ms-playwright"
if [[ ! -d "$cache_dir" ]]; then
  printf 'playwright install: browser cache dir %s not created\n' "$cache_dir" >&2
  exit 1
fi

# Find at least one chromium-* dir (name is like chromium-1234).
if ! find "$cache_dir" -maxdepth 1 -type d -name 'chromium-*' | head -1 | grep -q .; then
  printf 'playwright install: no chromium-* dir in %s\n' "$cache_dir" >&2
  exit 1
fi

echo "playwright: install complete (chromium in ${cache_dir})"
```

### Pattern 6: playwright uninstall.sh (symmetric, with cache cleanup)

```bash
#!/usr/bin/env bash
set -euo pipefail
# playwright uninstall.sh — symmetric inverse.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "playwright: removing playwright CLI and browser cache"

npm uninstall -g playwright --no-fund --no-audit >/dev/null 2>&1 || true

# Browser cache is large; removal is part of the uninstall contract. Phase 5
# uninstall recipes follow the Phase 4 pattern: first-install artifacts
# cleaned; user config (if any) preserved. ms-playwright cache is purely
# a cached download — removing it is pure space reclamation, not data loss.
rm -rf "${AGENTLINUX_AGENT_HOME}/.cache/ms-playwright"

if command -v playwright >/dev/null 2>&1; then
  echo "playwright uninstall: playwright still on PATH after npm uninstall -g" >&2
  exit 1
fi

echo "playwright: uninstall complete"
```

### Pattern 7: tests/bats/50-agents.bats (AGT-01, AGT-02b, AGT-03, AGT-04, AGT-05)

```bash
#!/usr/bin/env bats
# tests/bats/50-agents.bats — Phase 5 integration: AGT-01, AGT-02b, AGT-03, AGT-04, AGT-05.
#
# Non-destructive tests. AGT-02 (real `claude update`) lives in
# tests/bats/51-agt02-release-gate.bats so Phase 6 CI can select it.

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
CATALOG=/opt/agentlinux/catalog/0.3.0/catalog.json

setup_file() {
  # Install all three agents once for the file. Each @test assumes the install
  # has already happened; we trade setup-file time for test-case simplicity.
  # Serial installs keep sentinel writes unambiguous (no flock dance).
  sudo -u agent -H bash --login -c 'agentlinux install claude-code' >/dev/null 2>&1
  sudo -u agent -H bash --login -c 'agentlinux install gsd' >/dev/null 2>&1
  sudo -u agent -H bash --login -c 'agentlinux install playwright' >/dev/null 2>&1
}

teardown_file() {
  # Symmetric removal so downstream @test files see a clean slate.
  # If the binary is gone (INST-04 --purge upstream from some other file),
  # skip to avoid confusing errors.
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux remove --force claude-code' >/dev/null 2>&1 || true
    sudo -u agent -H bash --login -c 'agentlinux remove --force gsd' >/dev/null 2>&1 || true
    sudo -u agent -H bash --login -c 'agentlinux remove --force playwright' >/dev/null 2>&1 || true
  fi
}

# ---------- AGT-01: claude --version in every invocation mode ----------

@test "AGT-01: claude --version exits 0 in every invocation mode" {
  local mode
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'claude --version'
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "AGT-01 (${mode}): systemd PID 1 not running in this container"
    fi
    assert_exit_zero "AGT-01 (${mode})"
    # Additional invariant: the output contains digits+dots (a plausible version).
    # Prevents false-positive on a binary that exits 0 but prints nothing.
    if ! printf '%s' "${output}" | grep -Eq '[0-9]+\.[0-9]+\.[0-9]+'; then
      __fail "AGT-01 (${mode})" \
        "claude --version prints a semver-shaped string" \
        "${output:-<empty>}" \
        "$LOG"
    fi
  done
}

@test "AGT-01: get-shit-done-cc --help exits 0 in every invocation mode" {
  local mode
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'get-shit-done-cc --help'
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "AGT-01 (${mode}): systemd PID 1 not running"
    fi
    assert_exit_zero "AGT-01/GSD (${mode})"
  done
}

@test "AGT-01: npx playwright --version exits 0 in every invocation mode" {
  local mode
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'npx --yes playwright --version'
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "AGT-01 (${mode}): systemd PID 1 not running"
    fi
    assert_exit_zero "AGT-01/Playwright (${mode})"
  done
}

# ---------- AGT-02b: claude --version matches pinned_version exactly ----------

@test "AGT-02b: claude --version returns exactly pinned_version from catalog.json" {
  local pinned
  pinned=$(jq -r '.agents[] | select(.id=="claude-code") | .pinned_version' "$CATALOG")
  run sudo -u agent -H bash --login -c 'claude --version'
  assert_exit_zero "AGT-02b"
  # Exact-string presence: the version token must appear as a substring.
  # We don't assert full equality because upstream format may be "X.Y.Z (Claude Code)".
  if ! printf '%s' "${output}" | grep -q -F -- "$pinned"; then
    __fail "AGT-02b" \
      "claude --version contains pinned=${pinned}" \
      "${output:-<empty>}" \
      "$LOG"
  fi
}

# ---------- AGT-03: claude diagnostic (substituted by --help; see research §Open Q2) ----------

@test "AGT-03: claude --help exits 0 and prints no error strings" {
  # `claude doctor` waits for stdin (github.com/anthropics/claude-code/issues/26487),
  # unusable in bats non-interactive context. `claude --help` is the closest
  # scriptable positive-signal substitute: exits 0, rich output, no network.
  run sudo -u agent -H bash --login -c 'claude --help'
  assert_exit_zero "AGT-03"
  # Negative asserts: no obvious error/stack-trace leakage.
  if printf '%s' "${output:-}" | grep -Eiq 'error|traceback|permission denied|EACCES'; then
    __fail "AGT-03" \
      "claude --help output free of error/EACCES strings" \
      "${output}" \
      "$LOG"
  fi
}

# ---------- AGT-04: gsd version-equivalent smoke ----------

@test "AGT-04: get-shit-done-cc --help banner reports pinned version" {
  local pinned
  pinned=$(jq -r '.agents[] | select(.id=="gsd") | .pinned_version' "$CATALOG")
  run sudo -u agent -H bash --login -c 'get-shit-done-cc --help'
  assert_exit_zero "AGT-04"
  # GSD has no --version flag; its banner prints "Get Shit Done vX.Y.Z".
  if ! printf '%s' "${output}" | grep -q -F -- "v${pinned}"; then
    __fail "AGT-04" \
      "get-shit-done-cc --help banner contains v${pinned}" \
      "${output:-<empty>}" \
      "$LOG"
  fi
}

# ---------- AGT-05: playwright + chromium ----------

@test "AGT-05: npx playwright --version exits 0 with pinned version string" {
  local pinned
  pinned=$(jq -r '.agents[] | select(.id=="playwright") | .pinned_version' "$CATALOG")
  run sudo -u agent -H bash --login -c 'npx --yes playwright --version'
  assert_exit_zero "AGT-05"
  if ! printf '%s' "${output}" | grep -q -F -- "$pinned"; then
    __fail "AGT-05" \
      "playwright --version contains pinned=${pinned}" \
      "${output:-<empty>}" \
      "$LOG"
  fi
}

@test "AGT-05: chromium cached under ~agent/.cache/ms-playwright (no sudo/EACCES)" {
  # Install.sh already downloaded chromium. Re-verify cache exists and is
  # agent-owned (ADR-004 keystone).
  run sudo -u agent -H bash --login -c 'find /home/agent/.cache/ms-playwright -maxdepth 1 -type d -name "chromium-*" | head -1'
  assert_exit_zero "AGT-05"
  if [[ -z "${output}" ]]; then
    __fail "AGT-05" \
      "at least one chromium-* dir under ~agent/.cache/ms-playwright" \
      "none" \
      "$LOG"
  fi
  # Ownership check: chromium dir must be agent:agent (not root-owned via
  # a sudo-path bug). stat -c '%U' prints owner username.
  local owner
  owner=$(stat -c '%U' "${output}")
  if [[ "$owner" != "agent" ]]; then
    __fail "AGT-05" \
      "chromium cache owned by agent" \
      "owner=${owner} (path: ${output})" \
      "$LOG"
  fi
}

# ---------- AGT-05 install-idempotency (re-install == no-op) ----------

@test "AGT-05: re-install playwright is idempotent (CLI-03 invariant on real agent)" {
  # setup_file already installed; a second install with the same pin should
  # print "already installed" and not re-download chromium.
  run sudo -u agent -H bash --login -c 'agentlinux install playwright'
  assert_exit_zero "AGT-05 re-install"
  echo "$output" | grep -q 'already installed' \
    || __fail "AGT-05" "idempotent re-install prints 'already installed'" "${output:-<empty>}" "$LOG"
}
```

### Pattern 8: tests/bats/51-agt02-release-gate.bats (destructive; release-gate)

```bash
#!/usr/bin/env bats
# tests/bats/51-agt02-release-gate.bats — Phase 5 canonical acceptance test.
#
# AGT-02: agent user can self-update Claude Code without sudo / EACCES.
# This is THE test that v0.3.0 exists to make green. It runs a REAL
# `claude update` against the live Anthropic CDN, captures the transcript,
# and asserts zero EACCES / "permission denied" lines.
#
# PLACED IN A SEPARATE FILE so Phase 6 CI can select it via:
#   bats tests/bats/51-*.bats
# for the TST-05 release-gate step. The file is named with a sortable prefix
# so the destructive test runs AFTER all non-destructive Phase 5 tests.

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
CATALOG=/opt/agentlinux/catalog/0.3.0/catalog.json

setup_file() {
  # Ensure claude-code is installed at the pinned version before exercising
  # the update path. If a previous 50-agents.bats run left it installed,
  # re-install with --force to guarantee we start at the pin (not at whatever
  # version a prior AGT-02 run bumped us to).
  sudo -u agent -H bash --login -c 'agentlinux install --force claude-code' >/dev/null 2>&1
}

# AGT-02 is NOT looped across all six invocation modes — the update path is
# identical regardless of invocation mode; looping would multiply the network
# fetch time by 6. Sampling rate: one invocation per release-gate CI run.

@test "AGT-02 (release-gate): claude update exits 0 with zero EACCES/permission-denied lines" {
  local pinned
  pinned=$(jq -r '.agents[] | select(.id=="claude-code") | .pinned_version' "$CATALOG")

  # Before-state: record current version for monotonicity check.
  local before_version
  before_version=$(sudo -u agent -H bash --login -c 'claude --version' | head -1)

  # Capture the update transcript to a dedicated log so assert_no_eacces
  # can inspect file rather than $output (more robust against binary stderr
  # interleaving; Pitfall 4 below).
  local transcript
  transcript=$(mktemp /tmp/agt02-claude-update.XXXXXX.log)

  # Bound wall-time to 120s: real update downloads a ~8 MB binary; 120s gives
  # a safety margin against slow CI network + installer-side checksum verify.
  run bash -c "timeout 120s sudo -u agent -H bash --login -c 'claude update' >${transcript} 2>&1"

  # Primary assertion: exit 0. Non-zero = update failed (network, disk, perms).
  assert_exit_zero "AGT-02"

  # Canonical permission-invariant assertion (the whole reason v0.3.0 exists):
  # zero EACCES / "permission denied" in the transcript.
  assert_no_eacces "AGT-02" "$transcript"

  # Monotonicity: post-update version >= pinned. Using sort -V to get a
  # semver comparison. If `claude update` is a no-op (already at latest),
  # post_version == before_version, which satisfies >= pinned.
  local after_version
  after_version=$(sudo -u agent -H bash --login -c 'claude --version' | head -1)
  local pinned_v after_v
  pinned_v=$(printf '%s' "$pinned" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  after_v=$(printf '%s' "$after_version" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  # sort -V orders lowest first; if after_v is NOT less than pinned_v, head -1
  # of the sorted pair is pinned_v.
  local lowest
  lowest=$(printf '%s\n%s\n' "$pinned_v" "$after_v" | sort -V | head -1)
  if [[ "$lowest" != "$pinned_v" ]]; then
    __fail "AGT-02" \
      "after-update version >= pinned (${pinned_v})" \
      "after=${after_v}, before=${before_version}" \
      "$transcript"
  fi

  # Cleanup (only on pass — on failure leave the log for post-mortem).
  rm -f "$transcript"
}
```

### Anti-Patterns to Avoid

- **Don't use `sudo npm install -g`.** CLAUDE.md's #1 rule. Runner.ts already dispatches as agent via `as_user`; recipes inherit that. A naked `sudo npm install -g` in a recipe would be THE regression AgentLinux exists to prevent.
- **Don't hand-roll SHA256 verification for Claude Code.** The upstream `bootstrap.sh` already verifies the binary against a signed manifest (GPG-signed since 2.1.89); duplicating that in our recipe adds complexity without benefit.
- **Don't run `claude update` in a `for mode in INVOKE_MODES` loop.** Each update is ~8 MB of network traffic; 6× that is wasteful. AGT-02 samples at one invocation per release-gate run.
- **Don't cache Playwright browsers in the test image.** Upstream (playwright.dev/docs/ci) advises against caching because restore time ≈ download time. For our Docker test image, let the install run fresh.
- **Don't test `claude doctor` non-interactively.** GH #26487 documents that it waits for Enter. Substitute `claude --help`.
- **Don't assume `gsd` is a binary name.** The binary is `get-shit-done-cc` (verified). If the planner wants `gsd` ergonomics, add a symlink during install (research discusses options in Open Question 1) but DO NOT rename it silently in tests.
- **Don't skip `PIPESTATUS` guards** on `curl | bash` flows. `set -o pipefail` covers 90%, but explicit iteration gives a better error message.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Fetching Claude Code binary | Custom curl + SHA256 + platform detection | `curl -fsSL https://claude.ai/install.sh \| bash -s <ver>` | Upstream handles platform detection, GPG-signed manifest verification, musl/glibc split, Rosetta detection, OOM hints |
| npm global install orchestration | Custom download + extract + symlink | `npm install -g <pkg>@<ver>` | Phase 3's per-user prefix + /etc/agentlinux.env makes this a one-liner; npm handles bin entry + deps |
| Playwright browser download | Custom Chromium binary management | `npx playwright install --with-deps chromium` | Upstream handles signed-URL download, OS-specific apt packages, version matching to playwright-core |
| Version matching (pin vs installed) | Custom semver compare | String-match `AGENTLINUX_PINNED_VERSION` + `sort -V` for monotonicity | Our stability model is exact-pin, not range-based; string match is the right primitive |
| "no EACCES" transcript check | Custom awk/sed pipeline | Existing `assert_no_eacces` helper | Phase 2's helper already covers both "file path" and "string" inputs |
| Six-mode test loop | Per-test boilerplate | Existing `invoke_mode "$mode"` helper + `${INVOKE_MODES[@]}` | Phase 2 pattern; CLI-01 and RT-XX already use it |
| Sentinel writes | Custom JSON + flock | Phase 4's `writeSentinel` (TS; called from runner.ts) | Already atomic; Phase 5 doesn't touch this |

**Key insight:** Phase 5 is mostly plumbing. Every substantive piece of logic (binary download, SHA256 verification, platform detection, sudo-apt-for-deps, npm global, version pin enforcement) is handled by an existing tool. Our recipes are 20–40 lines of thin glue plus PIPESTATUS guards + version-matching asserts.

## Runtime State Inventory

Phase 5 is NOT a rename/refactor, but installing three real agents creates runtime state that Phase 6 (INST-04 / --purge) needs to know about. Complete inventory:

| Category | Items Created | Action Required |
|----------|---------------|------------------|
| **Stored data** | `~/.claude/` (user config, session history) | Phase 5 uninstall DOES NOT remove — matches Anthropic's uninstall docs; INST-04 --purge already removes the entire agent user home, so user state evaporates with the user. |
| **Stored data** | `~/.cache/ms-playwright/chromium-*/` (browser binaries, ~300 MB) | Phase 5 uninstall.sh removes this; INST-04 --purge removes the entire home. No leakage. |
| **Stored data** | `/home/agent/.npm-global/lib/node_modules/{get-shit-done-cc,playwright}` | npm uninstall -g removes cleanly (Phase 3 RT-03 verified this pattern with cowsay); INST-04 --purge removes `.npm-global` as part of agent-home removal. |
| **Live service config** | None — neither claude-code, gsd, nor playwright runs a daemon | No service state. |
| **OS-registered state** | None — no systemd units registered, no cron jobs placed by recipes | No registration to revert. |
| **Secrets/env vars** | `ANTHROPIC_API_KEY` (if user sets it; not touched by Phase 5) | Not our concern — explicit deferred per 05-CONTEXT.md. |
| **Build artifacts** | `~/.claude/downloads/claude-<ver>-<platform>` (bootstrap.sh's scratch file; bootstrap.sh deletes after install — see source) | Bootstrap already cleans up; recipe is idempotent. |

**Phase 5 state additions are all agent-user-owned.** `INST-04 --purge` from Phase 4 already sweeps the agent user's home, so no new --purge steps are needed. Phase 5 recipes are symmetrically self-cleaning for `agentlinux remove <name>`.

## Common Pitfalls

### Pitfall 1: Binary shape change between 2.1.98 and 2.1.113

**What goes wrong:** Pinning `2.1.98` installs a JS-shape Claude Code; `claude update` upgrades to `2.1.113+` (native-binary shape); re-running `agentlinux install --force claude-code` expects to see `2.1.98` again but the sentinel may register a different binary shape than first install.

**Why it happens:** Per CHANGELOG 2.1.113, "Changed the CLI to spawn a native Claude Code binary (via a per-platform optional dependency) instead of bundled JavaScript." The native installer (`claude.ai/install.sh`) has always delivered native binaries; the CHANGE is in the npm package shape. Since we use the native installer, **this doesn't affect our install path directly**, but if a user runs `claude update`, the binary shape in place after the update differs from what the fresh install placed. Sentinels store only `version`, not shape.

**How to avoid:** 
- Use the native installer consistently (locked decision ✓).
- AGT-02b asserts version-match by string, not by binary signature — tolerant of shape change.
- After `claude update` in AGT-02, if AGT-02b runs next and the version has advanced, AGT-02b FAILS (correct — the pin was escaped). The test ordering in our bats files puts AGT-02b BEFORE AGT-02 so AGT-02b observes the just-installed pin.

**Warning signs:** AGT-02b fails with "pinned=2.1.98, --version reports 2.1.114" after an AGT-02 run that updated the binary.

### Pitfall 2: Claude Code install OOM-killed on low-memory CI runners

**What goes wrong:** Bootstrap.sh runs `binary install` (a native Rust binary that scans filesystem) in a container with <4 GB RAM; Linux OOM killer terminates the process mid-install. Transcript shows `Killed`, install.sh exits non-zero.

**Why it happens:** Documented by Anthropic: "Claude Code requires at least 4 GB of available RAM." The install step scans the current directory (under `/` this scans everything). GitHub Actions `ubuntu-latest` runners have 7 GB memory — safe. But if the test Dockerfile runs the install from `/`, the scan thrashes.

**How to avoid:** 
- Docs advise `WORKDIR /tmp` before running the installer. Our test Dockerfiles don't do this explicitly, but the bats test runs through `sudo -u agent -H bash --login -c ...`, which starts from `~agent/`, bounding the scan.
- Document in the install.sh comment that 4 GB RAM is an upstream requirement.
- If CI OOMs are observed: add `cd ~ &&` prefix inside the recipe, or set `ulimit -v` appropriately.

**Warning signs:** Transcript contains `Killed`; exit code 137 (128+SIGKILL); transcript ends at "Setting up Claude Code…".

### Pitfall 3: `npx playwright install-deps` fails silently when sudo is unavailable

**What goes wrong:** In a hypothetical environment without ADR-012's sudoers drop-in (e.g. a Phase 2 regression), `playwright install-deps` prepends `sudo` but sudo prompts for a password; stdin not connected → infinite hang OR immediate non-zero exit depending on sudo config.

**Why it happens:** Playwright's registry/dependencies.ts constructs commands as `sudo apt-get install -y <packages>` when the process UID is non-zero. The `--with-deps` path delegates to this. Without NOPASSWD, interactive or failure — neither produces a clean exit code.

**How to avoid:** 
- ADR-012 is now in place (Phase 5.1 ✓). Verify `/etc/sudoers.d/agentlinux` contains `NOPASSWD: ALL` on any host running the recipe.
- Install recipe's `timeout 120s` bounds any hang.
- Integration test: Phase 5.1's `22-agent-sudo.bats` already asserts `sudo -n true` exits 0 — if that goes red, Playwright install fails deterministically.

**Warning signs:** Install hangs at "Installing dependencies…"; transcript shows "sudo: a password is required"; Phase 5.1 bats have regressed.

### Pitfall 4: `claude update` output stream interleaving

**What goes wrong:** `claude update` downloads + extracts + replaces the binary; the output is bash-launched and stdout/stderr interleave non-deterministically across `tee`, `>&2` pipes, and raw writes to the tty. AGT-02's transcript capture sometimes misses lines depending on buffering.

**Why it happens:** Native binary writes diagnostic output to stderr, progress lines to stdout; `2>&1` merges them but the stdio buffering inside the binary is not line-synced with bash's redirection.

**How to avoid:** 
- Use a dedicated file for the transcript: `claude update >"$transcript" 2>&1` (NOT the bats `$output` variable alone).
- `assert_no_eacces "$req_id" "$transcript"` — the helper handles file-path form.
- Bats's `run` subshell has its own buffer; combining `run bash -c "..."` with redirection inside gives us the cleanest capture.

**Warning signs:** Intermittent AGT-02 failures in CI that don't reproduce locally; `assert_no_eacces` passes but the transcript file contains EACCES on manual inspection.

### Pitfall 5: `npx --yes` required to avoid install-prompt hang

**What goes wrong:** `npx playwright --version` in a fresh non-interactive shell prompts "Need to install the following packages: playwright. Ok to proceed? (y)" — and on non-TTY stdin, some npm versions hang; others silently time out.

**Why it happens:** npx 7+ prompts before auto-installing. In our case `playwright` is ALREADY installed globally at `/home/agent/.npm-global`, so npx should skip the prompt — but if `$PATH` is wrong or npm's prefix resolution fails, npx falls through to the install-prompt branch.

**How to avoid:** 
- Always pass `--yes` to `npx` in recipes and tests: `npx --yes playwright install`, `npx --yes playwright --version`.
- Verify PATH includes `.npm-global/bin` BEFORE the `.npm-global/lib/node_modules/.bin`; this is the Phase 3 default, confirmed by runner.ts AGENT_PATH.

**Warning signs:** AGT-01 Playwright test hangs; `timeout` bats wrapper triggers after bats's default 10s.

### Pitfall 6: Claude Code's `--version` format drift

**What goes wrong:** AGT-02b asserts `claude --version` contains `2.1.98` as a substring. If Anthropic changes the format to e.g. `Claude Code version: 2.1.98-stable` (with a build tag), substring match works. But if they change to `Claude-Code@2.1.98 (build abc123)` or localize to a different character set, the grep -F -- "2.1.98" might still pass, but an exact-equality check would fail.

**Why it happens:** Claude Code's `--version` flag is not documented with a stable format guarantee. The CLI-reference table just says "Output the version number."

**How to avoid:** 
- Use **substring match** (not equality): `grep -q -F -- "$pinned"` — tolerates format changes, catches wrong-version installs.
- `head -1` the output to defend against multi-line version banners.
- If Anthropic introduces a `--json` flag later, switch to structured parsing in a future plan.

**Warning signs:** AGT-02b regressions during a Claude Code upstream release that changed the version print format.

### Pitfall 7: Playwright CLI transitively fetches `playwright-core` at a different version than pinned

**What goes wrong:** `npm install -g playwright@1.59.1` resolves `playwright-core` from the published lockfile — which is `1.59.1` at the time of Phase 5. If the planner bumps the pin later (e.g. 1.60.0), `playwright-core` moves with it. If the planner's test asserts exact 1.59.1 presence in `npm ls -g`, it sees it. But if they introduce a test that looks up `playwright-core` and finds 1.60.0 while the catalog says 1.59.1, the mismatch is confusing.

**Why it happens:** `playwright`'s `dependencies` in its package.json pins `playwright-core: 1.59.1` exactly (verified `[VERIFIED: npm view playwright dependencies]`). That's good — no floating dep. But tests should only assert on `playwright`, not `playwright-core`.

**How to avoid:** 
- Assertions target `playwright`, the catalog-pinned package name.
- Sentinel records `{version: 1.59.1, source: curated}` for `playwright` only.

**Warning signs:** A test ever references `playwright-core` by name.

### Pitfall 8: `sudo apt-get` interactive if DEBIAN_FRONTEND not set

**What goes wrong:** `playwright install-deps chromium` runs `sudo apt-get install -y ...`. In some environments (e.g. minimal Docker images without pre-set `DEBIAN_FRONTEND=noninteractive`), apt-get prompts for user input on dialog questions (tzdata, needrestart, etc.), hanging or failing.

**Why it happens:** Our test Dockerfiles explicitly set `ENV DEBIAN_FRONTEND=noninteractive` (verified in Dockerfile.ubuntu-24.04); in a production environment where a user runs the recipe on a non-hardened host, this isn't set.

**How to avoid:** 
- Set `DEBIAN_FRONTEND=noninteractive` in the recipe itself (belt-and-braces):
  ```bash
  export DEBIAN_FRONTEND=noninteractive
  npx --yes playwright install --with-deps chromium
  ```
- Document the env in the install.sh comment.

**Warning signs:** AGT-05 regression in QEMU (fresh cloud image) but green in Docker; install hangs at "Configuring tzdata…".

## Code Examples

Verified patterns from official sources. See also §Architecture Patterns 1–8 for full recipe bodies.

### Example 1: AGT-01 six-mode loop (template already used by CLI-01 / RT-XX)

```bash
# tests/bats/50-agents.bats (fragment)
# Source: existing tests/bats/40-registry-cli.bats CLI-01 pattern.
@test "AGT-01: claude --version exits 0 in every invocation mode" {
  local mode
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'claude --version'
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "AGT-01 (${mode}): systemd PID 1 not running"
    fi
    assert_exit_zero "AGT-01 (${mode})"
  done
}
```

### Example 2: AGT-02 transcript capture (no-EACCES + monotonic version)

```bash
# tests/bats/51-agt02-release-gate.bats (fragment)
# Source: Phase 2 INST-05 pattern (assert_no_eacces on file path);
#         05-CONTEXT.md §Test Shape + §Specific Ideas.
@test "AGT-02 (release-gate): claude update exits 0 with zero EACCES/permission-denied lines" {
  local transcript
  transcript=$(mktemp /tmp/agt02-claude-update.XXXXXX.log)
  run bash -c "timeout 120s sudo -u agent -H bash --login -c 'claude update' >${transcript} 2>&1"
  assert_exit_zero "AGT-02"
  assert_no_eacces "AGT-02" "$transcript"
  # + monotonic version check (see Pattern 8 for full body)
  rm -f "$transcript"
}
```

### Example 3: AGT-02b exact-string version lock

```bash
# Source: Phase 4 CAT-04 pattern (jq on catalog.json); verified in plan.
@test "AGT-02b: claude --version returns exactly pinned_version" {
  local pinned
  pinned=$(jq -r '.agents[] | select(.id=="claude-code") | .pinned_version' \
    /opt/agentlinux/catalog/0.3.0/catalog.json)
  run sudo -u agent -H bash --login -c 'claude --version'
  assert_exit_zero "AGT-02b"
  printf '%s' "${output}" | grep -q -F -- "$pinned" \
    || __fail "AGT-02b" "contains pinned=${pinned}" "${output}" "/var/log/agentlinux-install.log"
}
```

### Example 4: Playwright one-shot install with deps

```bash
# Source: playwright.dev/docs/ci (recommended single-command flow).
# In plugin/catalog/agents/playwright/install.sh:
npx --yes playwright install --with-deps chromium
# Expands internally (per playwright-core/src/server/registry/dependencies.ts) to:
#   npx playwright install chromium                    # download browser
#   sudo apt-get install -y --no-install-recommends \   # deps (sudo auto-
#     fonts-liberation libasound2 libatk-bridge2.0-0 \   # prepended by
#     libatk1.0-0 libatspi2.0-0 libcairo2 libcups2 \     # playwright when
#     libdbus-1-3 libdrm2 libegl1 libgbm1 libglib2.0-0 \ # getuid() != 0)
#     libgtk-3-0 libnspr4 libnss3 libpango-1.0-0 \
#     libx11-6 libx11-xcb1 libxcb1 libxcomposite1 \
#     libxdamage1 libxext6 libxfixes3 libxrandr2 libxshmfence1
# ADR-012 sudoers drop-in means the sudo runs non-interactively.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `@anthropic-ai/claude-code` as pure-JS npm package | Per-platform native binary pulled via optional dep | 2.1.113 (2026-04-17) | Our native-installer route is unchanged; npm route now installs SAME binary as native installer (docs: "npm pulls the binary in through a per-platform optional dependency…a postinstall step links it into place") |
| `claude doctor` as diagnostics | `claude doctor` (still interactive) + `claude auth status --text` (scriptable) | 2.1.110 added `/doctor` warnings; CLI `doctor` still interactive per GH #26487 | AGT-03 substitutes `claude --help` (scriptable, rich output, no TTY needed) |
| Playwright `install-deps` separate from `install` | `install --with-deps` combined flow | (existing; docs recommend for CI) | Single command for recipes |
| Manual SHA256 verification of installers | GPG-signed manifest from Anthropic (since 2.1.89) | 2.1.89 | Phase 5 recipes trust the bootstrap script's built-in verification |

**Deprecated/outdated:**
- `get-shit-done` npm package (5-year-old, unrelated) is NOT `get-shit-done-cc`. Our catalog correctly uses `get-shit-done-cc`; don't regress to `get-shit-done`.
- `chrome-devtools-mcp` — retired per v0.3.0 pivot; Playwright replaces it (catalog already reflects this).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `claude --version` substring-matches `pinned_version` even after `claude update` regresses to a different format | §Pitfall 6, AGT-02b test | Test becomes a false positive if format changes; substring match tolerates typical format drift; structured-output would be stricter |
| A2 | Ubuntu 24.04 Docker runners (7 GB default) have enough RAM for Claude Code native install (4 GB requirement) | §Pitfall 2 | OOM in CI; mitigated by `cd ~` before install (bounded scan); observed only on <4GB hosts |
| A3 | The `claude update` network path reaches `downloads.claude.ai` + `storage.googleapis.com` from the Docker test runner in the PR matrix | AGT-02 test design | Firewalled GH Actions runners could block; no documented mitigation besides Phase 6 QEMU gate which has different network posture |
| A4 | `npx playwright install-deps` reliably prepends `sudo` on every Ubuntu release in-scope (22.04 + 24.04) | §Pattern 5, §Pitfall 3 | Verified via playwright-core source 2026-04-19; future Playwright release could change command construction; re-verify at plan time |
| A5 | `bats run` with `timeout 120s` terminates a hung `claude update` cleanly rather than leaving a half-applied binary | AGT-02 test design | Timeout could leave `.local/bin/claude` in a mid-swap state; subsequent `claude --version` would fail cleanly (non-zero exit), test regresses loudly, not silently |
| A6 | GSD banner format (`Get Shit Done v1.37.1`) remains stable across 1.37.x bumps | §Pattern 3, AGT-04 | Grep on `v<version>` could match a slightly different template; tolerant of minor whitespace changes |

All assumed claims are tagged `[ASSUMED]` in the recipe code comments OR in §Open Questions. Planner should surface A1, A3, A5 to the user for confirmation before task-commit.

## Open Questions

1. **Should the `gsd` catalog entry provide a `gsd` command, or keep the `get-shit-done-cc` name?**
   - What we know: Upstream npm bin is `get-shit-done-cc` (verified `[VERIFIED: npm view bin]`); no `gsd` alias published; 05-CONTEXT.md assumes a `gsd` command exists.
   - What's unclear: Is the project intent "keep upstream naming" or "alias to `gsd` for ergonomics"?
   - Recommendation: **Keep upstream name `get-shit-done-cc`.** Aligns with npm bin entry, avoids "what's the canonical name?" confusion when users read docs. Update catalog `post_install_verify` from `command -v get-shit-done-cc` (current, correct) — no change. Update 05-CONTEXT.md to reflect actual binary name; update AGT-04 test to use `get-shit-done-cc --help`. If ergonomics become a user complaint, add a symlink in Phase 6 or v0.4+.
   - Alternative if planner disagrees: During install.sh, `ln -sf /home/agent/.npm-global/bin/get-shit-done-cc /home/agent/.npm-global/bin/gsd`. Trivially reversed in uninstall.sh.

2. **Should AGT-03 use `claude doctor` (waits for stdin — potentially hangs) or `claude --help` (scriptable)?**
   - What we know: Anthropic docs recommend `claude doctor` for detailed diagnostic check. GH issue #26487 documents `claude doctor` waits for Enter; not usable non-interactively.
   - What's unclear: Does `echo '' | claude doctor` or `claude doctor </dev/null` unblock it? Has Anthropic shipped a `--no-input` flag since the issue was filed?
   - Recommendation: **Use `claude --help`** for AGT-03. Clean exit 0, rich output, no TTY dependency, no network. If Anthropic ships `--no-input` or `--json` in a future version, swap in a later phase.
   - Alternative: `timeout 10s claude doctor </dev/null 2>&1; status=$?` — accept either exit 0 (if Anthropic ships non-interactive mode) OR exit 124 (timeout) as pass. Brittle; not recommended.

3. **Should pinned_version be bumped from 2.1.98 to current stable / latest at plan time?**
   - What we know: 2.1.98 is still `dist-tags.stable` as of 2026-04-19; both routes (native + npm) install working binaries. 2.1.113 changed the npm package binary shape to "native via optional dep" — doesn't affect native-installer route.
   - What's unclear: Is there a reason to prefer the native-binary npm shape (users who go the npm route) over JS shape?
   - Recommendation: **Keep 2.1.98.** It's `dist-tags.stable`, catalog-locked, and AGT-02 exercises the update path from 2.1.98 to a newer version — which is a MORE realistic test than starting already at latest. If re-verifying at plan time shows 2.1.98 has been yanked, bump to the next `stable` tag.

4. **Should AGT-02 run in every PR Docker matrix, or only in Phase 6's release-gate?**
   - What we know: 05-CONTEXT.md says "Real agent installs run in every PR Docker matrix (AGT-02 is the v0.3.0 core value — it must be live-tested on PR)." ROADMAP Phase 6 wires AGT-02 as release-gate.
   - What's unclear: Does PR-matrix add CI flakiness (network-dependent; Anthropic CDN rate-limits)?
   - Recommendation: **Run in every PR Docker matrix.** Rationale: AGT-02 IS the value prop. A rare CI flake is less bad than silently regressing permission-hygiene on an in-scope PR. Mitigations: file-separate (`51-*.bats`), `timeout 120s`, wallclock-bounded.
   - Escalation path: If AGT-02 exhibits >5% CI flake rate after landing, the planner can gate it to `nightly-qemu` only + keep a fast "smoke-only" AGT-02 in the PR matrix that runs `claude update --help` to prove the subcommand exists without doing the real update.

5. **Does Phase 5 need to bump the catalog's `pinned_version` for Playwright to avoid the `linux-x64-musl` edge case?**
   - What we know: Playwright 1.59.1 is current stable. Our Docker test image is Ubuntu 24.04 (glibc). No musl concern.
   - What's unclear: Does running on a musl-based QEMU image (hypothetical Alpine scenario) change behavior? (Phase 6 QEMU matrix is Ubuntu cloud images per research — no Alpine — so this is theoretical.)
   - Recommendation: No change. Document "musl support not in scope for v0.3.0" — v0.4+ concern.

## Environment Availability

| Dependency | Required By | Available in Docker test image? | Version | Fallback |
|------------|------------|---------------------------------|---------|----------|
| `curl` | claude-code install.sh (fetch bootstrap) | ✓ (Ubuntu default + ca-certificates) | 8.5 (22.04) / 8.5 (24.04) | `wget` if curl missing (bootstrap handles both) |
| `bash` 4+ | all recipes (`${PIPESTATUS[@]}`, `[[ ]]`) | ✓ | 5.1 (22.04) / 5.2 (24.04) | — (required) |
| `sha256sum` | bootstrap.sh internal | ✓ (coreutils) | 8.32 | — |
| `jq` | bats tests (catalog + sentinel parsing) | ✓ (installed Phase 4 Rule-3 auto-fix) | 1.6 (22.04) / 1.7 (24.04) | — |
| `sudo` (NOPASSWD) | playwright install.sh (install-deps) | ✓ (Phase 5.1 + ADR-012) | 1.9+ | `playwright install chromium` without `--with-deps` (skips apt; system deps may still be needed) |
| `npm` + Node 22 LTS | gsd + playwright recipes | ✓ (Phase 3 provisioner) | 22.22.2 | — |
| `timeout` (coreutils) | AGT-02 bats wall-time bound | ✓ | 8.32 | — |
| Network to `downloads.claude.ai` | AGT-02 + claude-code install | Unknown — depends on GH Actions egress policy | HTTPS 443 | If blocked, recipe fails fast; Phase 6 QEMU has different policy |
| Network to `storage.googleapis.com` | Same (bootstrap fetches manifest + binary) | Unknown — same as above | HTTPS 443 | Same |
| Network to `npmjs.org` | npm install -g | ✓ (Phase 3 proven) | HTTPS 443 | — |
| Network to `playwright.azureedge.net` + downloads | Playwright browser download | Unknown — but Playwright is widely used in GH Actions CI → high confidence available | HTTPS 443 | None; AGT-05 would regress |
| 4 GB+ RAM | Claude Code install | ✓ for `ubuntu-latest` GHA (7 GB) | — | `cd ~` to bound FS scan; swap space on low-mem hosts (documented) |

**Missing dependencies with no fallback:** 
- None — all five network endpoints are expected to work in the PR Docker matrix (Phase 4 proved npm, Phase 5 uses the same posture for Anthropic CDN + Playwright).

**Missing dependencies with fallback:**
- `curl` missing → bootstrap uses `wget`. Test images have both; real concern is minimal.

## Validation Architecture

> Phase 5 honors nyquist validation (config default: enabled; not explicitly disabled).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `bats-core` (Ubuntu apt package) + `node:test` (plugin/cli/ unit tests, existing Phase 4) |
| Config file | `tests/docker/Dockerfile.ubuntu-{22.04,24.04}` (apt install bats); `plugin/cli/package.json` for Node tests |
| Quick run command | `./tests/docker/run.sh ubuntu-24.04` |
| Full suite command | `./tests/docker/run.sh ubuntu-22.04 && ./tests/docker/run.sh ubuntu-24.04` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AGT-01 | `claude --version` + `get-shit-done-cc --help` + `npx playwright --version` exit 0 in six modes | bats integration | `./tests/docker/run.sh ubuntu-24.04` (specifically `tests/bats/50-agents.bats "AGT-01:" @tests`) | ❌ Wave 0 — create 50-agents.bats |
| AGT-02 | `claude update` no sudo, no EACCES, monotonic version | bats integration (destructive; ~10s wall time + network) | `bats tests/bats/51-agt02-release-gate.bats` | ❌ Wave 0 — create 51-agt02-release-gate.bats |
| AGT-02b | `claude --version` exact pinned match | bats integration | `bats tests/bats/50-agents.bats -f "AGT-02b"` | ❌ Wave 0 — create 50-agents.bats |
| AGT-03 | `claude --help` (substituted for `claude doctor`) exits 0 + no error strings | bats integration | `bats tests/bats/50-agents.bats -f "AGT-03"` | ❌ Wave 0 |
| AGT-04 | `get-shit-done-cc --help` banner contains pinned version | bats integration | `bats tests/bats/50-agents.bats -f "AGT-04"` | ❌ Wave 0 |
| AGT-05 | `npx playwright --version` + chromium cache exists + agent-owned | bats integration | `bats tests/bats/50-agents.bats -f "AGT-05"` | ❌ Wave 0 |
| Scaffold contract | install.sh with missing `AGENTLINUX_PINNED_VERSION` exits 1 (same as Phase 4 scaffold contract) | inherited from Phase 4 | Existing 40-registry-cli.bats still covers via test-dummy | ✅ Already covered |
| Idempotency | Re-install is no-op ("already installed") | bats (reused CLI-03 pattern) | `bats tests/bats/50-agents.bats -f "idempotent"` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `./tests/docker/run.sh ubuntu-24.04` for the task's own agent recipe (runs Phase 4 tests + newly-added Phase 5 tests).
- **Per wave merge:** Both Ubuntu 22.04 + 24.04 matrix.
- **Phase gate (TST-07):** Full Docker matrix + behavior-coverage-auditor assert every Phase 5 AGT-XX has ≥1 @test citing it.
- **Phase 6 release-gate (inherited):** `bats tests/bats/51-*.bats` selects AGT-02 release-gate only; runs in nightly QEMU + on tag.

### Wave 0 Gaps

- [ ] `tests/bats/50-agents.bats` — covers AGT-01, AGT-02b, AGT-03, AGT-04, AGT-05 (all non-destructive). Template in §Pattern 7.
- [ ] `tests/bats/51-agt02-release-gate.bats` — covers AGT-02 only (destructive, real network fetch). Template in §Pattern 8.
- [ ] `plugin/catalog/agents/claude-code/install.sh` — real body (§Pattern 1).
- [ ] `plugin/catalog/agents/claude-code/uninstall.sh` — real body (§Pattern 2).
- [ ] `plugin/catalog/agents/gsd/install.sh` — real body (§Pattern 3).
- [ ] `plugin/catalog/agents/gsd/uninstall.sh` — real body (§Pattern 4).
- [ ] `plugin/catalog/agents/playwright/install.sh` — real body (§Pattern 5).
- [ ] `plugin/catalog/agents/playwright/uninstall.sh` — real body (§Pattern 6).
- [ ] Catalog sanity-check at plan start (re-verify `npm view` pins exist).

No framework install needed (bats + Node test infra from Phases 1 + 4 cover all of Phase 5).

## Security Domain

`security_enforcement` is enabled by default (not explicitly disabled). Phase 5 threats:

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Phase 5 installs CLIs; auth is the user's concern (ANTHROPIC_API_KEY, OAuth) — explicitly deferred per 05-CONTEXT.md |
| V3 Session Management | no | No sessions |
| V4 Access Control | yes | Recipes MUST run as `agent` (enforced by CLI-05 guard in Phase 4 CLI); `as_user -- ...` dispatcher already covers it |
| V5 Input Validation | partial | `AGENTLINUX_PINNED_VERSION` validated as semver at CATALOG schema level (Phase 4); `${VAR:?}` guards catch unset env vars |
| V6 Cryptography | yes | Upstream bootstrap.sh verifies SHA256 against GPG-signed manifest (2.1.89+); recipe trusts this. Do NOT hand-roll additional verification |
| V12 Files and Resources | yes | `rm -rf` paths in uninstall.sh use literal absolute paths (no `$var/`-joined-from-user-input); follows Phase 4's T-04-16 pattern |

### Known Threat Patterns for Phase 5 stack

| Threat ID | Pattern | STRIDE | Standard Mitigation |
|-----------|---------|--------|---------------------|
| T-05-01 | `curl \| bash` with 404 swallowed by bash (Pitfall 8 Phase 4) | Tampering | `set -o pipefail` + explicit `PIPESTATUS[@]` check |
| T-05-02 | `npm install -g` unsafe if npm resolution falls through to `/usr` prefix | Elevation of Privilege | Phase 3 keystone: NPM_CONFIG_PREFIX=/home/agent/.npm-global; runner.ts mirrors this in env |
| T-05-03 | Playwright `install-deps` apt install chosen packages with sudo | Elevation of Privilege | Packages chosen by upstream Playwright (trusted); ADR-012 sudoers grant is explicit user consent |
| T-05-04 | `claude update` writes to wrong path (e.g. `/usr/local/bin/claude`) | Tampering | Native installer path is `~/.local/bin/claude`; `claude update` self-manages this user-owned prefix — ADR-004 invariant |
| T-05-05 | Recipe reads from attacker-controlled env (e.g. `PINNED_VERSION=$(curl evil.com)`) | Tampering | `AGENTLINUX_PINNED_VERSION` is set only by runner.ts (TS dispatcher), which reads from catalog.json validated by JSON Schema — path is tamper-resistant |
| T-05-06 | Uninstall.sh `rm -rf` leaks into wrong directory if `AGENTLINUX_AGENT_HOME` is empty/unset | Tampering | `: "${AGENTLINUX_AGENT_HOME:?...}"` guard makes recipe fail-fast on unset var (Phase 4 scaffold pattern) |
| T-05-07 | Claude Code's native installer binary unsigned on Linux | Tampering | Mitigated by GPG-signed manifest (2.1.89+); recipe trusts Anthropic's chain |
| T-05-08 | Playwright's apt packages pulled from compromised Ubuntu mirror | Tampering | Out of scope; user's apt trust posture. Not AgentLinux's to solve |

Threats are addressed at recipe + runner level; no new Phase 5 infrastructure needed. Review-loop: `security-engineer` verifies all threats T-05-01..08 have inline mitigation comments or are documented as out-of-scope.

## Sources

### Primary (HIGH confidence)

- **Claude Code install docs** — https://code.claude.com/docs/en/setup `[VERIFIED 2026-04-19]` — authoritative install paths, `claude update`, `claude doctor` existence, binary locations, DISABLE_AUTOUPDATER env var, signed manifest, `minimumVersion` setting.
- **Claude Code troubleshooting docs** — https://code.claude.com/docs/en/troubleshooting `[VERIFIED 2026-04-19]` — PATH diagnostics, low-memory OOM, binary variant selection, npm-vs-native conflicts.
- **Claude Code CLI reference** — https://code.claude.com/docs/en/cli-reference `[VERIFIED 2026-04-19]` — subcommand list, `claude --version`, `claude update`, `claude auth status --text` for scriptable-ish diagnostics; note `claude doctor` not in main table.
- **Claude Code CHANGELOG** — https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md `[VERIFIED 2026-04-19 via raw.githubusercontent.com]` — 2.1.113 note on native-binary shape change, 2.1.110 `/doctor` changes.
- **Claude Code bootstrap.sh source** — https://downloads.claude.ai/claude-code-releases/bootstrap.sh `[VERIFIED 2026-04-19 via curl]` — first positional arg validation, `$HOME/.claude/downloads` scratch, delegates final install to the binary.
- **npm registry — `@anthropic-ai/claude-code`** — https://www.npmjs.com/package/@anthropic-ai/claude-code `[VERIFIED 2026-04-19]` — `bin: {claude: 'bin/claude.exe'}` on 2.1.114; `bin: {claude: 'cli.js'}` on 2.1.98; dist-tags `stable: 2.1.98, latest: 2.1.114`.
- **npm registry — `get-shit-done-cc`** — https://www.npmjs.com/package/get-shit-done-cc `[VERIFIED 2026-04-19]` — `bin: {"get-shit-done-cc": "bin/install.js"}`, no `gsd` alias, 1.37.1 published 2 days ago.
- **npm registry — `playwright`** — https://www.npmjs.com/package/playwright `[VERIFIED 2026-04-19]` — `bin: {playwright: "cli.js"}`, `dependencies.playwright-core: 1.59.1`.
- **Playwright browsers docs** — https://playwright.dev/docs/browsers `[VERIFIED 2026-04-19]` — `~/.cache/ms-playwright`, chromium ~281 MB, per-browser install syntax.
- **Playwright CI docs** — https://playwright.dev/docs/ci `[VERIFIED 2026-04-19]` — `--with-deps` recommended, cache-is-not-recommended.
- **Playwright source (registry/dependencies.ts)** — https://raw.githubusercontent.com/microsoft/playwright/main/packages/playwright-core/src/server/registry/dependencies.ts `[VERIFIED 2026-04-19]` — confirms `sudo` auto-prepend on non-root UID.

### Secondary (MEDIUM confidence)

- **Playwright apt package list for Chromium on Ubuntu 24.04** — compiled from web search `[CITED web search; exact package list not in official docs]`: fonts-liberation, libasound2, libatk-bridge2.0-0, libatk1.0-0, libatspi2.0-0, libcairo2, libcups2, libdbus-1-3, libdrm2, libegl1, libgbm1, libglib2.0-0, libgtk-3-0, libnspr4, libnss3, libpango-1.0-0, libx11-6, libx11-xcb1, libxcb1, libxcomposite1, libxdamage1, libxext6, libxfixes3, libxrandr2, libxshmfence1.
- **GH issue anthropics/claude-code#26487** — `claude doctor` non-interactive mode feature request — `[CITED]` — documents the TTY-wait bug that drives Open Question 2.

### Tertiary (LOW confidence / ASSUMED)

- Claude Code's `--version` output format stability — no API guarantee; substring match tolerates drift (Pitfall 6).
- `claude update` rate-limiting by Anthropic CDN — no documented quota; assumed "unlimited for realistic CI volume." If hit, AGT-02 flakes with network errors.

## Metadata

**Confidence breakdown:**
- Standard stack: **HIGH** — all three npm packages verified via `npm view` live; Claude Code native installer verified by curling the actual bootstrap.sh; Playwright apt package list cross-referenced with upstream source.
- Architecture: **HIGH** — reuses Phase 4 dispatch pipeline unchanged; only recipe bodies + bats tests are new.
- Pitfalls: **HIGH** for pitfalls 1, 3, 4, 5, 7, 8 (observable in upstream source/docs); **MEDIUM** for pitfalls 2, 6 (env-dependent and format-drift assumptions).
- Test design: **MEDIUM** — AGT-02 depends on CI network reliability (Anthropic CDN reachable from GH Actions Docker runners), which is an environmental variable we can't fully verify from research.

**Research date:** 2026-04-19
**Valid until:** 2026-05-19 (30 days; Claude Code + GSD + Playwright all publish weekly. Re-verify pin availability at plan time.)

## RESEARCH COMPLETE

**Phase:** 5 — Agent Installability
**Confidence:** HIGH (stack + architecture); MEDIUM (CI network posture for AGT-02)

### Key Findings

- **Three 05-CONTEXT.md corrections needed** before plan-commit:
  1. The GSD binary is `get-shit-done-cc`, not `gsd` (verified; no upstream `gsd` alias).
  2. `get-shit-done-cc` has no `--version` flag — AGT-04 must use `--help` + banner grep.
  3. `claude doctor` is interactive (GH #26487) — AGT-03 must substitute `claude --help`.
- **All three pinned versions still valid** on npm as of 2026-04-19 (2.1.98 stable, 1.37.1 latest, 1.59.1 latest).
- **ADR-012 makes Playwright trivial:** `npx playwright install --with-deps chromium` is one command; sudo auto-prepended by Playwright internally; NOPASSWD grant makes it non-interactive.
- **AGT-02 design:** separate file (`51-agt02-release-gate.bats`), `timeout 120s`, transcript-to-tmpfile, `assert_no_eacces` on the file path (robust against stdio interleaving). Monotonic version check via `sort -V`.
- **Claude Code binary shape changed at 2.1.113** (npm package now pulls native binary via optional dep); native installer route unaffected; pin 2.1.98 is pre-change and still works.
- **Playwright apt package list for Ubuntu 24.04 is upstream-managed** — don't hand-roll; rely on `install-deps chromium`.

### File Created

`/home/agent/agent-linux/.planning/phases/05-agent-installability/05-RESEARCH.md`

### Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Standard Stack | HIGH | All three packages verified via `npm view` live + bootstrap.sh curled + Playwright source read |
| Architecture | HIGH | Phase 4 dispatch + Phase 5.1 sudo + Phase 3 npm-prefix are all load-bearing and green; Phase 5 recipes are thin glue |
| Pitfalls | HIGH for docs-backed; MEDIUM for environmental (Docker OOM, CI network reliability for Anthropic CDN) |
| Test Design | MEDIUM | AGT-02's reliance on CI reaching downloads.claude.ai is the biggest unknown — Open Question 4 surfaces a fallback if it flakes |
| Security | HIGH | All threat surfaces have documented mitigations; security-engineer review-loop covers at task time |

### Open Questions

1. **Keep `get-shit-done-cc` binary name or symlink to `gsd`?** (Recommendation: keep; update 05-CONTEXT.md.)
2. **`claude doctor` vs `claude --help` for AGT-03?** (Recommendation: `claude --help`; `doctor` is interactive.)
3. **Bump `claude-code` pin past 2.1.113 to get native-binary npm shape?** (Recommendation: no; 2.1.98 works, native installer is unaffected.)
4. **Run AGT-02 in every PR matrix or only release-gate?** (Recommendation: every PR matrix per 05-CONTEXT.md; escalation path if flaky.)
5. **Does Phase 5 need Playwright musl support?** (Recommendation: no — Ubuntu-only scope for v0.3.0.)

### Ready for Planning

Research complete. Planner can now create PLAN.md files for:
- Plan 05-01 — `claude-code` install.sh + uninstall.sh + `51-agt02-release-gate.bats` shell (AGT-02 canonical).
- Plan 05-02 — `gsd` install.sh + uninstall.sh + `50-agents.bats` AGT-04 subset.
- Plan 05-03 — `playwright` install.sh + uninstall.sh + `50-agents.bats` AGT-05 subset.
- Plan 05-04 — Complete `50-agents.bats` (AGT-01 six-mode loop for all three, AGT-02b, AGT-03) + TST-07 phase-close.

Alternative collapse: Plans 05-01..05-03 each carry their bats additions; Plan 05-04 collapses into a phase-close commit only. Planner's call.
