# Phase 50: integration QA - Context

**Gathered:** 2026-07-18
**Status:** Ready for planning
**Mode:** Autonomous smart-discuss defaults applied

<domain>
## Phase Boundary

Deliver the reusable `.claude/skills/qa-testing/` Claude Code workflow and use it to run a recorded integration-QA sweep over the feature-complete v0.3.6 catalog. The sweep targets emergent co-install, install-order, configuration/PATH, CLI UX, and representative terminal-interface defects that per-entry bats, Docker, and QEMU gates can miss. This phase does not add another catalog entry or silently claim coverage that the available harnesses cannot provide.

</domain>

<decisions>
## Implementation Decisions

### Scope and test selection
- Derive scope from the phase/milestone diff, roadmap success criteria, and requirement IDs; treat Phase 50's QA workflow plus the catalog-wide integration surface as direct scope.
- Exercise direct deliverables heavily and creatively; give adjacent installer, catalog, CLI, wiring, and release surfaces a lighter sanity pass.
- Prioritize high-traffic combinations: gsd + codex, a coding agent plus a fan-out MCP provider, and a `[bin]` + `[npm]` + `[daemon]` mix.
- Use disposable environments and preserve the existing behavior-test contract; findings become inline fixes or explicitly routed decimal phases/Jira tickets.

### Regression-to-zero loop
- Use configurable time-boxed rounds with a default 20-minute box; a newly discovered bug resets the quiet-round count.
- Treat two consecutive quiet boxes as the default "done from my side" signal, while allowing the maintainer to raise N for a higher-confidence sweep.
- Keep a short session log and triage every finding by severity, reproducibility, direct/adjacent scope, and disposition; checklist completion alone is not the stop condition.

### Representative terminal session
- Use a genuine PTY, not a captured pipe: the existing `tests/bats/helpers/tty-driver.py`/interactive helpers and `tests/docker/rc-sandbox.sh` are the starting points.
- Exercise `TERM=xterm-256color`, color/ANSI enabled, default approximately 80-column geometry, and at least one documented wider geometry.
- Observe live/streaming output and background work for apparent freezes; record terminal geometry, environment, and invocation mode in the QA report.

### Coverage and handback
- Run co-install and removal-order checks in Docker where available; mark systemd-user daemon paths and other QEMU-only behavior as not reachable locally unless a real QEMU run is available.
- Record exact combinations, invocation modes, and harness limits in `.planning/phases/50-integration-qa/50-QA-REPORT.md`.
- Register the skill in the project skill list and include a lightweight discoverability/load self-check.

### the agent's Discretion
- Choose the concrete disposable-environment commands, round duration adjustments, and minimal interaction scripts while preserving the scope, PTY, stop-condition, and honest-handback contracts above.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tests/docker/rc-sandbox.sh` provides an interactive local-RC sandbox for realistic user-shell setup.
- `tests/bats/helpers/tty-driver.py` and `tests/bats/helpers/interactive.bash` provide PTY-oriented interaction primitives and prompt sentinels.
- `plugin/cli/src/commands/{list,install,remove}.ts`, `plugin/cli/src/rewire.ts`, and the catalog recipes expose the integration surfaces that co-install QA must drive.

### Established Patterns
- Bats tests are the behavior contract; catalog lifecycle tests assert install, verification, symmetric remove, and no residue.
- Docker is the fast PR gate; QEMU is the release gate for systemd, logind, cloud-init, and other real-VM behavior.
- Skills are project-scoped under `.claude/skills/` and must be listed in `CLAUDE.md`; planning artifacts remain under `.planning/` until milestone cleanup.

### Integration Points
- `plugin/cli/src/runner.ts` dispatches catalog recipes and owns environment/PATH handoff.
- `plugin/cli/src/rewire.ts` and `plugin/catalog/lib/mcp-register.sh` implement cross-agent fan-out and install-order reconciliation.
- `tests/docker/run.sh`, `tests/docker/run-smoke.sh`, and the QEMU harness define the available execution boundaries.

</code_context>

<specifics>
## Specific Ideas

The owner explicitly wants QA that behaves like a human session: creative testing of direct deliverables, a lighter adjacent pass, a bug-arrival-rate stop condition, and a real terminal view rather than frozen captured-pipe output. The skill should be reusable at future milestone close, not a one-off checklist.

</specifics>

<deferred>
## Deferred Ideas

No new catalog tools or unrelated harness redesign belongs in this phase. Deeper defects become inline fixes only when small and safe; otherwise they are filed as decimal phases or Jira deliverables.

</deferred>
