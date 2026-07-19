# Phase 51: unified integration-QA remediation — Research

**Researched:** 2026-07-19
**Status:** Ready for planning

## Findings

### Firecrawl MCP authentication

- The Phase 50 finding is a contract mismatch, not evidence that the endpoint is unavailable. Firecrawl's current OAuth guide documents both the API-key URL form (`https://mcp.firecrawl.dev/<API_KEY>/v2/mcp`) and the bare endpoint (`https://mcp.firecrawl.dev/v2/mcp`) with OAuth authorization-code + PKCE, protected-resource metadata, authorization-server discovery, and dynamic client registration.
- Firecrawl's guide says the bare endpoint requires a client that implements MCP authorization and accepts HTTPS or loopback redirects. Clients without suitable OAuth support may use the API-key URL or an `mcp-remote` loopback wrapper.
- The current recipe and tests assert `requires_secret: false`, advertise keyless operation, and intentionally write no credential. The Phase 50 report used a bare endpoint and observed an OAuth gate, which is consistent with the documentation but invalidates the old “works immediately with no signup” claim.
- Planning should separate an authenticated live-operation check from catalog secret handling: use a runtime-only `FIRECRAWL_API` value for the API-key URL experiment; never place it in recipes, tests, reports, commits, or persistent fixture files. Then exercise the bare OAuth path in each client that can perform the authorization flow. The eventual metadata and install note must describe the tested behavior.

### OpenCode GitHub MCP OAuth

- OpenCode's official MCP documentation says remote servers automatically trigger OAuth after a 401, attempt dynamic client registration when no client ID is configured, store tokens under `~/.local/share/opencode/mcp-auth.json`, and expose `opencode mcp auth`, `opencode mcp logout`, `opencode mcp auth list`, and `opencode mcp debug`.
- The Phase 50 failure (`Incompatible auth server: does not support dynamic client registration`) therefore needs protocol-level diagnosis. The plan should capture the endpoint's protected-resource metadata, authorization-server metadata, DCR response, redirect URI, and OpenCode's version/auth-state output, then compare those with a clean temporary OpenCode home. A stale auth state, endpoint-specific metadata, redirect mismatch, or a client/version regression are all plausible; none is proven from the Phase 50 transcript alone.
- The existing shared helper correctly registers the GitHub bare URL into all five MCP-capable clients. The repair should retain that fan-out and ADR-017's no-baked-credential rule. A fallback PAT in catalog-managed config would contradict the current thin-installer policy unless the maintainer explicitly changes that policy.
- `npm view opencode-ai` currently reports `1.18.3` as latest while the catalog pins `1.17.11`; the plan should test the pinned version first for reproducibility, then evaluate a newer exact pin only if it fixes the OAuth path and remains compatible with the catalog's passive-update freeze.

### Playwright CLI failures and runtime libraries

- The catalog currently pins `@playwright/cli` `0.1.15`; the npm registry currently reports `0.1.17` latest. The official `microsoft/playwright-cli` project documents the same global package and action surface (`click`, `fill`, `select`, `check`, `upload`, and others), but the Phase 50 invalid-target behavior is an exit-status contract defect not covered by the existing catalog lifecycle test.
- The first implementation seam to test is an exact upstream version bump: install the current pinned version in a disposable RC image and reproduce invalid `click`/`fill` plus representative valid actions. If the upstream release still returns zero, the planner must identify a minimal AgentLinux-owned adapter or wrapper that preserves stdout/stderr and turns action-resolution failures into nonzero status without changing successful action behavior. The wrapper must not create a `/usr/local/bin` shim.
- Phase 50 also replayed a known browser-launch failure because bundled Chromium could not load `libglib-2.0.so.0` in a fresh image. Official Playwright documentation uses an install-with-dependencies model for browser runtime packages, but the current catalog recipe only installs the npm CLI as the agent user. Dependency ownership and escalation need explicit tests rather than assuming the npm package can install OS libraries.

### System prerequisites

- Spec Kit installs from a Git tag using uv, so its current recipe correctly detects missing `git` but leaves the user with a documented prerequisite. The approved Phase 51 decision is to make required dependencies automatic where possible.
- The repository already has distro-aware detection for the installed user's ability to run the system package manager through non-interactive sudo (`plugin/lib/detect/user.sh`, `DETECT_USER_CAN_SUDO_APT`, with `/usr/bin/apt-get` or `/usr/bin/dnf` selected by distro family). This is a reusable capability signal, not yet a catalog dependency installer.
- Planning should choose a single, idempotent dependency seam that works on Ubuntu 22.04/24.04/26.04 and the project's supported RHEL-family path where applicable. It must attempt agent-user package-manager access first, detect failure without hanging, and emit an explicit sudo/root request or actionable command when escalation is required. Tests must not silently turn a blocked dependency into a help/version-only pass.
- Chrome DevTools MCP currently registers successfully but requires a separately installed Chrome binary. The plan should decide whether the dependency bootstrap installs Google Chrome or a compatible system browser and how the MCP recipe communicates the exact executable path. Playwright's missing shared libraries and Chrome DevTools MCP's missing browser are related runtime prerequisites but may have different ownership and licensing handling.

### GSD/Open GSD and Codex

- The catalog currently installs `get-shit-done-cc` `1.42.3`, and its recipe intentionally skips Codex because the generated `[[hooks]]` configuration is incompatible with Codex's expected `HooksToml` shape.
- The official Open GSD project is `open-gsd/gsd-core`; its README describes support for Codex and installs via `npx @opengsd/gsd-core@latest`. The npm registry currently reports `@opengsd/gsd-core` `1.7.0` latest, with Node `>=22.0.0` and npm `>=10.0.0` requirements. AgentLinux already provisions Node 22, so the runtime floor is compatible; the implementation must still pin the exact release rather than use an unbounded latest tag.
- The Open GSD package exposes an installer binary (`gsd-core`) and related tools rather than the old `get-shit-done-cc` binary shape. The plan must verify the official installer’s runtime selection, preserve the `agentlinux install gsd` catalog identity where possible, and explicitly test Claude Code, OpenCode, Gemini CLI, Qwen Code, and Codex wiring plus removal.
- Codex integration is a hard requirement from the approved context. The current skip path must be removed or replaced by a valid Open GSD/Codex integration. A source-compatible Open GSD upgrade is the first candidate; if an incompatibility remains, the plan needs a narrowly scoped config conversion or upstream-compatible adapter with a regression fixture for the exact Codex TOML shape.

### Gemini observation

- Phase 50's Gemini invalid-stream message was not reproduced in two later authorized retries after correcting the disposable-container trust precondition. There is no demonstrated AgentLinux-owned failure to fix. The follow-up should rerun the corrected invocation, record the result, and close the observation without adding speculative retry logic.

## Recommended Plan Implications

1. Establish a small, credential-safe live diagnostic harness for Firecrawl and OpenCode before changing catalog metadata. It should use temporary homes/configs, redacted transcripts, and explicit cleanup.
2. Split the implementation into disjoint seams: hosted MCP authentication/diagnostics, Playwright status/runtime behavior, shared OS dependency bootstrap, and GSD/Open GSD migration/Codex wiring. Keep regression tests beside each seam, then run the full follow-up QA sweep in a final plan.
3. Treat package upgrades as exact pins. Validate `@opengsd/gsd-core@1.7.0`, `@playwright/cli@0.1.17`, and any OpenCode upgrade in fresh RC images before updating catalog metadata.
4. Use existing `mcp-register.sh`, catalog recipe contracts, `tests/docker/rc-sandbox.sh`, and Bats helpers rather than adding parallel lifecycle machinery.
5. Include explicit negative tests: no literal Firecrawl key in repository/config artifacts, OpenCode auth failure is non-silent, failed Playwright targets return nonzero, dependency installation does not hang or downgrade to help-only verification, Codex wiring is present, and all removals preserve unrelated user state.
6. Reserve the final wave for targeted regressions plus the Phase 50-style `qa-testing` follow-up. The exit artifact must list each finding/boundary as resolved, remaining blocked, or newly discovered, and must retain openclaw/hermes-agent exclusions when systemd is unavailable.

## Risks

- Firecrawl OAuth may work in Claude Code but not in every fan-out client because redirect URI support differs. The catalog must distinguish “registered” from “live authenticated operation.”
- Hosted OAuth behavior can change independently of a package pin. Durable tests should validate discovery and user-visible auth outcomes without storing tokens.
- Adding OS dependencies from a per-user catalog command may require root and may be inappropriate for a recipe executed under `agent`. A shared installer/provisioner seam is safer if it can preserve idempotency and explicit escalation.
- Chrome installation can introduce repository/key, licensing, architecture, or offline-test concerns. The plan should prefer the smallest supported runtime and document any unavoidable host boundary.
- Open GSD changes the package identity and installer behavior, not just a version string. Existing detection, preservation, WIRE-01 tests, and uninstall logic all need review.
- Playwright upstream may fix the status bug without fixing the browser-library gap; the two regressions must remain independently testable.

## Sources

### Official external sources
- https://docs.firecrawl.dev/developer-guides/mcp-setup-guides/oauth — API-key URL, keyless OAuth, dynamic client registration, PKCE, redirect requirements, and `mcp-remote` fallback.
- https://opencode.ai/docs/mcp-servers/#oauth — remote MCP OAuth, DCR, auth storage, auth commands, and `opencode mcp debug`.
- https://github.com/open-gsd/gsd-core — Open GSD supported runtimes, installer, release history, and Codex support.
- https://www.npmjs.com/package/@opengsd/gsd-core — package metadata and exact release to pin.
- https://github.com/microsoft/playwright-cli — official CLI package, supported command surface, and runtime requirements.
- https://github.com/microsoft/playwright-cli/releases — official CLI release history and upgrade path.
- https://github.com/microsoft/playwright/blob/main/docs/src/ci.md — official Playwright dependency-install guidance, including `install --with-deps` patterns.

### Repository sources
- `.planning/phases/50-integration-qa/50-QA-REPORT.md` and `50-EVIDENCE.md` — Phase 50 findings and redacted reproductions.
- `.planning/phases/51-fix-all-phase-50-integration-qa-findings-known-issues-and-pr/51-CONTEXT.md` — approved decisions.
- `plugin/catalog/lib/mcp-register.sh` — current five-client remote-MCP fan-out.
- `plugin/lib/detect/user.sh` — distro-aware package-manager privilege detection.
- `plugin/catalog/agents/{firecrawl-mcp,github-mcp,playwright-cli,spec-kit,chrome-devtools-mcp,gsd}/install.sh` — direct remediation seams.
- `tests/bats/{60-catalog-github-mcp,62-catalog-firecrawl-mcp,66-catalog-spec-kit,70-catalog-cross-wire}.bats` — reusable regression patterns.

## Validation Architecture

- **Fast static/unit checks:** catalog schema validation, shellcheck/shfmt, targeted Bats files for MCP recipes, dependency helpers, GSD wiring, and Playwright status behavior; `npm test`/TypeScript checks where CLI code changes.
- **Fresh-image checks:** `./tests/docker/run.sh ubuntu-24.04` for the affected targeted suite, plus Ubuntu 22.04 and 26.04 checks for distro-sensitive dependency behavior. No host-installed package state may satisfy the test accidentally.
- **Credential-safe live checks:** Firecrawl API-key and OAuth attempts, OpenCode GitHub MCP authorization/debug, and any model prompt use runtime-only credentials with redacted durable evidence. A blocked credential path is recorded as blocked, never passed via help/version.
- **Lifecycle checks:** install → ownership/path/version → real operation → sibling-preserving remove → residue/shim scan, including both MCP registration orders and GSD/Codex wiring.
- **Final gate:** rerun `.claude/skills/qa-testing/` across Phase 50's in-scope packages and representative co-installed workflows, recording resolved findings, remaining boundaries, and new issues. `openclaw` and `hermes-agent` remain excluded without a systemd-capable environment.
