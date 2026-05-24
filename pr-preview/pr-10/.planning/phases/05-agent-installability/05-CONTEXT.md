# Phase 5: Agent Installability - Context

**Gathered:** 2026-04-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Each of the three v0.3.0 catalog agents — claude-code, gsd (npm: get-shit-done-cc), playwright — is installable via `agentlinux install <name>` and runs correctly for the agent user across all six invocation modes. AGT-02 (Claude Code self-updates without sudo/EACCES) is the canonical v0.3.0 acceptance test. AGT-02b proves the stability-first mechanism from ADR-011 works end-to-end (installed version == catalog `pinned_version`).

Requirements in scope: AGT-01, AGT-02, AGT-02b, AGT-03, AGT-04, AGT-05.

Out of scope: SHA256 curl-installer (Phase 6), release pipeline + catalog snapshot sibling (Phase 6), TST-08 release-gate CI (Phase 6), QEMU release-gate suite (Phase 6).

Phase 5.1 (completed) established that the agent user has passwordless sudo via ADR-012 — Playwright's `install-deps` works without special handling.

</domain>

<decisions>
## Implementation Decisions

### Claude Code Install Path (AGT-02 load-bearer)
- Install via **native installer**: `curl -fsSL https://claude.ai/install.sh | bash -s "$AGENTLINUX_PINNED_VERSION"` invoked via `as_user -- bash -c` — research finding 1 (Phase 4 RESEARCH) confirms positional version pinning works.
- Binary lands under `/home/agent/.local/bin/claude` — agent-owned, matches Anthropic's auto-updater detection mechanics.
- Post-install verify: `claude --version` returns exactly the pinned_version (AGT-02b).
- `claude update` self-update path runs in the user-owned prefix; AGT-02 asserts zero EACCES/permission-denied in its transcript and that `claude --version` is monotonic (≥ pinned).
- Uninstall: `uninstall.sh` removes `/home/agent/.local/bin/claude` + `/home/agent/.claude/` config dir (symmetric). Leaves agent-owned secrets/credentials intact only if agent has placed them; catalog uninstall is for binaries and first-install artifacts.

### GSD Install Path
- `as_user -- bash --login -c "npm install -g get-shit-done-cc@$AGENTLINUX_PINNED_VERSION"`
- Binary at `/home/agent/.npm-global/bin/gsd` (verified via `npm view get-shit-done-cc bin`).
- Post-install verify: `gsd --version` (or `gsd --help` if `--version` isn't supported — planner decides based on real package behavior).
- Uninstall: `as_user -- bash --login -c "npm uninstall -g get-shit-done-cc"`.

### Playwright Install Path
- `as_user -- bash --login -c "npm install -g playwright@$AGENTLINUX_PINNED_VERSION"` for the CLI/bindings.
- `as_user -- bash --login -c "npx playwright install chromium"` to download the chromium browser into `/home/agent/.cache/ms-playwright/` (agent-owned, no sudo/EACCES). Only chromium to bound CI time; full browser matrix is a Phase 6+ optimization.
- System deps: `sudo -n -- bash -c "playwright install-deps chromium"` now runs because of ADR-012 (agent has passwordless sudo). Don't swallow its exit code — if apt fails, the install.sh exits non-zero.
- Post-install verify: `npx playwright --version` (exits 0, version string visible) + `npx playwright --help` basic smoke.
- Uninstall: `npm uninstall -g playwright`; optional browser cache cleanup.

### Phase 5 Test Shape
- New bats file: `tests/bats/50-agents.bats` — each `@test` cites its AGT-XX ID.
- Real agent installs run in every PR Docker matrix (AGT-02 is the v0.3.0 core value — it must be live-tested on PR, not only in nightly QEMU).
- **AGT-01**: `claude --version` + `gsd --version` + `npx playwright --version` exit 0 in all six invocation modes (loops `${INVOKE_MODES[@]}`).
- **AGT-02** (canonical): after install, `claude update` (or Anthropic-supplied self-update command for v2.1.x) runs as agent user, exit 0, transcript zero `EACCES|permission denied`, `claude --version` is monotonic. The test is tagged `@release-gate` so Phase 6 CI can enforce it.
- **AGT-02b** (version lock): immediately after `agentlinux install claude-code`, `claude --version` matches `catalog.json`'s pinned_version exactly (string match, not semver range).
- **AGT-03**: `claude doctor` (if supported in pinned version) or substitute `claude --help` — exit 0 + no error strings.
- **AGT-04**: `gsd --version` or equivalent exits 0.
- **AGT-05**: `npx playwright --version` exits 0; `npx playwright install chromium` completes without sudo/EACCES (the install-deps step does use sudo — that's fine per ADR-012).

### Claude's Discretion
- Exact shell wording of the three install.sh scaffolds (from Phase 4) being replaced with real bodies — match existing `${VAR:?msg}` guard pattern + strict-mode.
- Whether `claude update --dry-run` is substituted for `claude update` in AGT-02 to avoid actually updating (if Anthropic v2.1.x supports it). Otherwise the test runs a real update and requires network access inside Docker.
- Whether AGT-03's `claude doctor` substitute is `--help` or `--version`. Whatever gives a clear positive signal.
- Plan count: research-recommended is 3 plans (one per agent) + 1 bats plan = 4 plans; planner may collapse per-agent recipes into a single plan if scope is tight.
- How to bound Playwright browser download time in CI (chromium only? cache the browser in Dockerfile? skip the real download and trust `install` exit code?).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `plugin/catalog/agents/{claude-code,gsd,playwright}/install.sh` — Phase 4 SCAFFOLDS. Phase 5 replaces their bodies with real install bodies. uninstall.sh files are similarly scaffolded.
- `plugin/catalog/catalog.json` — pinned versions: claude-code 2.1.98, gsd 1.37.1, playwright 1.59.1. Bump to current stable if research recommends.
- `plugin/cli/src/runner.ts` — dispatches recipes with `AGENTLINUX_PINNED_VERSION` env var. No change needed in Phase 5.
- `plugin/provisioner/20-sudoers.sh` (Phase 5.1) — agent has passwordless sudo. Playwright install-deps works.
- `tests/bats/helpers/invoke_modes.bash` — six-mode helpers. Each AGT-01 test loops them.
- `tests/bats/helpers/assertions.bash` — `assert_no_eacces`, `assert_path_has`, `assert_exit_zero`, `assert_user_prefix_in_home`.
- `tests/bats/40-registry-cli.bats` — test-dummy exercises the dispatch. Phase 5 exercises real agents.

### Established Patterns
- Per-task atomic commits.
- Every `@test` cites its requirement ID.
- Review loop: bash-engineer + security-engineer + qa-engineer for recipe bash; qa-engineer + behavior-coverage-auditor for bats; TST-07 phase-close auditor mandatory.
- Threat model block (T-05-NN).
- `as_user -- ...` for all recipe commands (never raw `sudo -u` outside as_user.sh).

### Integration Points
- `plugin/cli/src/runner.ts` sets `AGENTLINUX_PINNED_VERSION`; recipes consume it.
- Network access in Docker: Phase 4 Dockerfiles already connect to npm; Claude Code's native installer reaches claude.ai. CI matrix running live may need `curl` + HTTPS + npm registry reachability — already present.
- AGT-02 release-gate tagging: a bats `@tag` or filename convention (e.g., `51-agt02-release-gate.bats`) so Phase 6's release.yml can select only that file for its release-gate CI step. Planner decides convention.

</code_context>

<specifics>
## Specific Ideas

- **AGT-02 is the canonical acceptance test.** Everything else in Phase 5 supports it. If AGT-02 is red on PR, Phase 5 isn't done.
- **Pinned versions should be validated on plan.** If `npm view @anthropic-ai/claude-code 2.1.98` returns "not found" (Anthropic yanks old versions), update the pin to current stable. Same for get-shit-done-cc 1.37.1 and playwright 1.59.1.
- **Playwright browser downloads are ~150MB.** Cache in Dockerfile if possible, or tolerate the CI time cost.
- **Don't chase Chrome DevTools MCP** — it's retired per the v0.3.0 pivot.
- **`claude update` in a test is destructive** — it mutates the installed binary. Run AGT-02 AFTER AGT-01 / AGT-02b so the other tests aren't affected. Or use `--dry-run` if available.
- **AGT-04 needs to confirm `gsd --version` actually exists** — the npm package's bin entries may be `gsd` or `get-shit-done` or something else; verify at plan time.

</specifics>

<deferred>
## Deferred Ideas

- Full browser matrix for Playwright (firefox + webkit) — Phase 6 or v0.4+.
- MCP server agents (beyond Playwright) — v0.4+.
- Agent-specific doctor/diagnostic subcommands beyond AGT-03 — v0.4+.
- `agentlinux info <name>` surfacing post-install status (CLI-08 renumbered) — v0.4+.
- Claude Code authentication setup (API keys, OAuth) — explicitly out of scope for install; user's concern.

</deferred>
