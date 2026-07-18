# Phase 47: openclaw — Context

**Gathered:** 2026-07-14
**Status:** Ready for planning
**Requirements:** ASST-01, ENABLE-04 (+ ENABLE-05 self-updater coexistence, OPS-01 real-op gate)
**Jira:** AL-94

<domain>
## Phase Boundary

Make **openclaw** (OpenClaw, `openclaw/openclaw`, steipete, MIT) installable + removable
via the catalog, AND deliver the **ENABLE-04 AI-assistant daemon-lifecycle enabler** —
the machinery that lets a catalog entry set up a *per-user background service* (no root)
on install and tear it down with no stray daemon/unit/state on remove. openclaw is the
first consumer of this new daemon entry kind.

Out of scope: the systemd `--user`/linger lifecycle CANNOT be exercised in Docker (logind
masked — see the constraint below); that path is QEMU-gated per ADR-007. Baking any
provider key is out of scope (BYO key, in-tool).
</domain>

<decisions>
## Implementation Decisions (grey areas — resolved by source review + container probe)

### D1 — Source: GO, build both ASST daemon tools (maintainer, 2026-07-14)
openclaw = `openclaw/openclaw` (steipete), MIT, self-hosted per-user daemon, BYO provider
key, **no paid backend**. Daemon-class ⇒ NOT an auto-GO under the source policy; reviewed
and **approved** by the maintainer alongside hermes-agent (Phase 48). Node engines
`>=22.19.0` are satisfied by AgentLinux's Node 22 (latest v22.23.1).

### D2 — Install mechanic: npm global as the agent user
`npm install -g openclaw@2026.6.10` — per-user npm prefix, no root, `openclaw` on PATH.
Same `[npm]` shape as the Phase 23–27 cluster. Has a `postinstall` script (benign in the
probe; watched). `source_kind: "script"` (the recipe does more than a bare npm install —
it drives onboard + daemon lifecycle via the ENABLE-04 helper; the CLI runs script/mcp/
binary recipes identically, so no new enum — same modeling choice as spec-kit).

### D3 — ENABLE-04 helper `plugin/catalog/lib/daemon-lifecycle.sh`
A shared, sourced helper (beside prebuilt-binary.sh / uv-bootstrap.sh / mcp-register.sh)
owning the per-user daemon bookkeeping so every future daemon-class tool reuses it:
- `enable-linger` for the agent user (agent sudo per ADR-012 — `loginctl enable-linger`),
  so the per-user systemd instance survives logout (required for a persistent daemon).
- drive the tool's own daemon-install/start + a health probe.
- symmetric teardown: daemon uninstall + state dir removal + **linger revert** (only if
  AgentLinux enabled it — marker-gated, same ownership discipline as uv-bootstrap).
- Marker at `~/.local/share/agentlinux/<tool>.daemon` records what AgentLinux set up.

### D4 — Non-interactive, no-secret onboarding
`openclaw onboard --non-interactive --accept-risk --auth-choice skip` — sets up config
WITHOUT baking any provider key (confirmed in probe: secrets NOT baked). The user adds a
provider key in-tool post-install. Recipe prints that instruction.

### D5 — ENABLE-05 self-updater coexistence
openclaw ships a self-updater; the recipe disables the passive/auto path so the catalog
pin stays authoritative (same principle as the codex/opencode ENABLE-05/08 work). Exact
config key confirmed by the command-surface re-probe (config/update surface) before the
recipe encodes it.

### D6 — KEY CONSTRAINT: systemd --user is QEMU-gated (ADR-007)
`openclaw daemon install` uses **systemd `--user`** (linger). The **Docker harness masks
`systemd-logind`** (no `/run/user`, no user bus), so the systemd-user daemon path is **NOT
testable in Docker**. Therefore:
- **Docker bats** verifies the daemon via the **process-level `openclaw gateway` +
  `openclaw health`** path — install → gateway-up → health-ok → remove → gone. This is the
  TST-07 gate that runs on every PR.
- The **systemd-user install/linger lifecycle** gets a **QEMU test** (fresh cloud image,
  real logind) — nightly/release gate. The ENABLE-04 helper's linger + `daemon install`
  branch is exercised there.

### D7 — Symmetric remove (ASST-01 + CAT-04)
`agentlinux remove openclaw`: stop+uninstall the daemon, `npm rm -g openclaw`, tear down
`~/.openclaw` state, revert linger if AgentLinux enabled it, drop the marker. Idempotent
(re-remove is a clean no-op). Follows the aggressive-ownership stance; a user-brought
linger/daemon predating AgentLinux is left untouched (marker-gated).
</decisions>

<code_context>
## Existing Code Insights (reuse — CAT-03)

- **Helper convention** (`plugin/catalog/lib/*.sh`): sourced not executed; no top-level
  `set -euo pipefail` (the recipe owns shell opts); each fn returns non-zero on failure;
  marker-gated ownership so remove never clobbers user-brought infrastructure
  (`al_uv_remove_if_managed_and_unused` is the template). The provisioner stages the whole
  `lib/` subdir automatically (`50-registry-cli.sh` `cp -R`) — no provisioner edit needed.
- **Recipe env contract**: `AGENTLINUX_PINNED_VERSION`, `AGENTLINUX_CATALOG_DIR`,
  `AGENTLINUX_AGENT_HOME` (asserted with `: "${VAR:?}"`); source helper via
  `${AGENTLINUX_CATALOG_DIR}/lib/daemon-lifecycle.sh`.
- **Agent sudo (ADR-012)**: the agent user has NOPASSWD sudo — `loginctl enable-linger
  agent` is available; the recipe runs as the agent user and `sudo`s only for linger.
- **npm cluster pattern** (Phases 23–27): `npm install -g <pkg>@<pin>` as the agent user,
  version-lock, symmetric `npm rm -g`. ENABLE-08 freeze-config precedent for disabling a
  passive self-updater.
</code_context>

<specifics>
## Specific Ideas / Acceptance (success criteria — must be TRUE)

1. ENABLE-04: catalog supports AI-assistant daemon entries — install sets up a per-user
   background service (no root); remove tears it down with no stray daemon/unit/state.
2. `agentlinux install openclaw` installs `openclaw@2026.6.10` as the agent user (no root,
   zero EACCES); daemon runs per-user.
3. ENABLE-05 holds — openclaw's pin stays authoritative; secrets NOT baked.
4. `agentlinux remove openclaw` symmetric teardown — no stray unit/process/files;
   idempotent.
5. ≥1 Docker bats @test (install → gateway/health up → remove → gone) green — TST-07.
6. systemd-user install/linger lifecycle covered by a QEMU test (ADR-007 gate).
7. OPS-01 real-op: a credential-free operation proves the gateway actually serves
   (`openclaw health` returns healthy against a live process-level gateway).
</specifics>

<deferred>
## Deferred Ideas

- Multi-provider daemon key management — out of scope (BYO, in-tool).
- Any second daemon-class consumer beyond hermes-agent (Phase 48) — ENABLE-04 helper is
  designed for reuse but only these two consumers ship this milestone.
</deferred>
