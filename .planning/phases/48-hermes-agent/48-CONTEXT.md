# Phase 48: hermes-agent — Context

**Gathered:** 2026-07-14
**Status:** Ready for planning
**Requirements:** ASST-02 (reuses ENABLE-04, + OPS-01 real-op gate)
**Jira:** AL-95

<domain>
## Phase Boundary

Make **hermes-agent** (Hermes Agent, `NousResearch/hermes-agent`, Nous Research, open
source) installable + removable via the catalog — the second AI-assistant daemon tool,
reusing the ENABLE-04 lifecycle helper from Phase 47. Per-user daemon/gateway, BYO
provider key. Out of scope: baking any provider key; the systemd-user daemon lifecycle
(QEMU-gated, same as openclaw).
</domain>

<decisions>
## Implementation Decisions (grey areas — resolved by source review + installer inspection)

### D1 — Source: official = NousResearch/hermes-agent, GO (build both, maintainer 2026-07-14)
The official channel is the curl installer `https://hermes-agent.nousresearch.com/install.sh`
(clones `github.com/NousResearch/hermes-agent.git`, installs uv+Python 3.11+Node deps, no
sudo, per-user daemon/gateway). **Do NOT use the npm `hermes-agent` (wyrtensi)** — an
UNOFFICIAL third-party bridge (a different artifact). Approved alongside openclaw.

### D2 — Pinning: `--commit <SHA>` to an exact content-addressed commit
The installer supports `--branch NAME` + **`--commit SHA` (purpose-built: "pin checkout to
a specific commit")**. The catalog pin `2026.6.19` maps to git tag `v2026.6.19`, which peels
to commit **`2bd1977d8fad185c9b4be47884f7e87f1add0ce3`** (resolved via `git ls-remote`). The
recipe pins with `--commit 2bd1977…` — a content-addressed SHA is immutable, a STRONGER
integrity anchor than spec-kit's mutable git tag. The version-lock (`hermes --version`
contains `2026.6.19`) catches drift.

### D3 — Supply-chain posture (third-party curl-pipe-bash)
The `install.sh` is fetched live over HTTPS with no script-level checksum/signature — the
realistic bar for an official third-party installer (rustup/uv/nvm shape). Mitigations: the
recipe **downloads the installer to a temp file, then runs it** (never blind `curl | bash`),
pins the CODE to an immutable commit SHA, and installs no-root into agent-owned dirs. As a
non-root install the installer uses `$HERMES_HOME/hermes-agent` + `~/.local/bin/hermes` —
**no /usr/local shim** (the anti-pattern is avoided automatically). This is documented as a
known posture: strong code-pin, HTTPS-fetched bootstrap script.

### D4 — Non-interactive, no-secret install
`bash install.sh --commit <SHA> --non-interactive` — `--non-interactive` skips the two
user-input stages (`setup` = API keys, `gateway` = service), so it installs the `hermes`
CLI + config + deps and bakes NO provider key and NO gateway service. The daemon is then
brought up via ENABLE-04 (below), and the user adds a key in-tool.

### D5 — ENABLE-04 reuse for the gateway daemon
hermes ships `hermes gateway install/start/stop/status/uninstall` (systemd service) — the
same daemon shape as openclaw. The recipe reuses `plugin/catalog/lib/daemon-lifecycle.sh`:
`al_daemon_user_systemd_available` probe → where a user bus exists, `al_daemon_enable_linger`
+ `hermes gateway install && start` + `al_daemon_mark hermes-agent`; where absent (container),
config-only with guidance. systemd-user lifecycle QEMU-gated (ADR-007).

### D6 — Symmetric remove + CAT-04 preserve
`agentlinux remove hermes-agent`: `hermes gateway stop/uninstall`, remove the install dir +
`~/.local/bin/hermes`, revert linger if AgentLinux enabled it (helper), drop the daemon
marker. The user config/state dir (holds any provider key + persona) is preserved on remove
per CAT-04 (`preserve_paths.json`), wiped only on `--purge` — same as openclaw. [Exact state
dir path from the installer probe.]
</decisions>

<code_context>
## Existing Code Insights (reuse — CAT-03)

- **ENABLE-04 helper** `plugin/catalog/lib/daemon-lifecycle.sh` (Phase 47) — reused verbatim.
- **openclaw recipe pair** is the template: `source_kind: script`, version-lock, no-secret
  onboard, daemon-via-helper, CAT-04 preserve gate (`_should_remove`), QEMU-gated systemd path.
- **git** is a host prereq (added to the 3 Docker images for spec-kit) — the installer clones.
- **Docker vs QEMU**: the Docker bats verifies the process-level gateway path; systemd-user
  lifecycle self-gates with `skip` and runs under QEMU (one bats file, ADR-007).
</code_context>

<specifics>
## Success Criteria (must be TRUE)

1. `agentlinux install hermes-agent` installs the pinned `hermes` (official Nous Research
   installer + per-user daemon/gateway) as the agent user (no root, zero EACCES, no
   /usr/local shim); daemon runs per-user (QEMU-verified).
2. Secrets NOT baked — any gateway/provider credential supplied post-install in-tool.
3. `agentlinux remove hermes-agent` tears down the daemon + gateway symmetrically — no stray
   unit/process; user state preserved per CAT-04, --purge wipes.
4. ≥1 Docker bats @test (install → gateway/health up → remove → gone) green — TST-07.
5. systemd-user daemon lifecycle covered by the self-gating QEMU test.
</specifics>

<deferred>
## Deferred Ideas
- Desktop app bootstrap (`--include-desktop`) — out of scope (headless server tool).
- npm bridge variant — explicitly rejected (unofficial).
</deferred>
