# Phase 21: Catalog Verify on AlmaLinux 9 — Context

**Gathered:** 2026-06-29
**Status:** Complete
**Mode:** On-box-smoke-driven (the open question is resolved by live evidence, not guesswork)

<domain>
## Phase Boundary

Verify the three catalog agents install and pass their health checks on
AlmaLinux 9, and resolve the one open EL9 question — whether any Playwright
code path launches Chromium and thus needs an explicit `dnf` runtime-deps
block — by on-box `almalinux:9` smoke rather than pre-scoped guesswork.
Requirement: REC-01.

In scope:
- **REC-01:** `claude-code` (distro-agnostic native installer → `~agent/.local/bin/claude`)
  and `gsd` (pure npm) port unchanged; both already proven green on the EL9
  Docker row in Phase 20 (`50-agents.bats` 11/11 + `51/52-agt02` real installs).
  For `playwright-cli`, a live install + health smoke runs on `almalinux:9` to
  resolve the Chromium question.

Out of scope: the QEMU release-gate row + real-enforcing-SELinux re-confirmation
+ the milestone-close AGT-02 gate (Phase 22).
</domain>

<decisions>
## Implementation Decisions

### Locked (from REQUIREMENTS.md)
- No dnf-deps work is pre-scoped before the smoke result is in hand.
- Generalize, never weaken: the EL9 observable must match Ubuntu's.

### Resolved by this phase (the open question + a user scope decision)
The on-box smoke (see 21-RESEARCH.md) showed `playwright-cli install --skills`
downloads a Chromium binary whose ~20-lib shared-object closure is unsatisfied
on **both** EL9 (20 missing libs) and stock Ubuntu (24 missing) — a symmetric
gap, not an EL9 regression. The CLI/skill/`--version` health checks pass on EL9
without any deps.

Given that, the user chose (2026-06-29) to **make the browser actually
launchable on both families** rather than leave the gap. So the recipe now
installs Chromium's browser-launch deps, family-dispatched:
- **Debian/Ubuntu:** Playwright's own bundled `install-deps` (knows apt names
  across 22.04/24.04/26.04, incl. the `t64` transition).
- **AlmaLinux 9:** an explicit, on-box-verified `dnf install` list (Playwright's
  `install-deps` has no dnf path and dies on EL9).

Both verified end-to-end: post-deps `ldd chrome` is clean and a headless
`--dump-dom about:blank` launch exits 0. Locked by AGT-06.
</decisions>

<code_context>
## Existing Code Insights

- `plugin/catalog/agents/playwright-cli/install.sh` — the recipe; gains a
  family-dispatched browser-launch-deps step after `install --skills`.
- `plugin/cli/src/runner.ts` — the recipe env does NOT include
  `AGENTLINUX_DISTRO_FAMILY`, so the recipe detects family inline via
  `/etc/os-release` (the `distro.bash` standalone precedent).
- `tests/bats/50-agents.bats` — AGT-01..05 already green on EL9 (Phase 20);
  AGT-06 added here to lock the launch capability on both families.
- ADR-012 NOPASSWD sudo drop-in — what lets the `sudo apt`/`sudo dnf` deps
  step run without stalling a non-interactive loop.
</code_context>
