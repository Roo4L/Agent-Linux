# Phase 50: integration QA - Context

**Gathered:** 2026-07-18
**Status:** Ready for planning
**Mode:** Interactive discuss

<domain>
## Phase Boundary

Run black-box, user-oriented QA against the AgentLinux catalog packages
themselves. Every real non-test, non-daemon package must be installed in a
fresh Docker release-candidate environment, exercised through realistic
day-to-day workflows, removed, and checked for residue or sibling breakage.

This is not a repository-quality audit: GSD planning files, internal harness
implementation, and the host's ability to run QEMU are not QA targets. The
`qa-testing` skill remains the reusable mechanism and the QA report remains the
evidence artifact, but the product under test is AgentLinux plus its catalog
packages.

</domain>

<decisions>
## Implementation Decisions

### Package breadth
- Test every real catalog entry except `openclaw`, `hermes-agent`, and
  `test-dummy`.
- `openclaw` and `hermes-agent` are deferred because their primary behavior
  requires a working per-user systemd service, which the Docker environment
  cannot currently provide. Their exclusion is a coverage boundary, not a
  product failure.
- Every included package gets install, version/path/ownership verification,
  realistic operation, removal, and post-removal residue checks.

### Real operation and scenario depth
- A version check or `--help` invocation alone is insufficient.
- For each package, exercise the cheapest meaningful primary capability as a
  real user would, then add creative edge cases where they can expose hidden
  defects: retries, repeated installs, reinstall/upgrade-like flows, malformed
  or empty local inputs, sibling packages remaining installed, and cleanup
  after partial progress.
- Operation scenarios are category-aware: coding agents use real prompts when
  authenticated; MCP packages are registered and used through their client;
  DevOps tools perform read-only or fixture-backed operations; workflow tools
  perform their local workflow; browser tooling launches and drives a page.
- The exact scenario set is the agent's discretion, but every scenario must
  have a user-visible reason to exist and must be recorded in the QA report.

### Credentials
- Before testing, inventory every credential needed by the selected real
  operations and ask the user to provide those credentials at runtime.
- Credentials are never written to the repository, catalog, report, or
  persistent test fixture.
- If an operation unexpectedly needs a credential that was not requested,
  stop that path and ask for it. Do not silently skip or downgrade it to a
  version/help check.
- A credential-dependent path is considered covered only after its real
  operation passes, or explicitly blocked when the credential is unavailable.

### Co-install and workflow combinations
- Use maximum practical coverage, selected from plausible user workflows
  rather than arbitrary package pairs.
- Test every cross-agent fan-out provider against every compatible installed
  agent, including both installation orders, repeated reconciliation, and
  sibling-preserving removal.
- Add realistic workflows combining packages that users would use together,
  especially where they share PATH entries, config files, hooks, MCP
  registration, update behavior, or cleanup paths.
- Exercise retries, reinstall/upgrade-like sequences, removal permutations,
  and residue checks wherever the workflow exposes a meaningful interaction.
- Do not spend time on combinations with no plausible shared surface merely to
  increase a pairwise count.

### Docker coverage and boundaries
- Run the package QA inside fresh Docker RC containers rather than against
  the host checkout or host-installed tools.
- Run the full package workflow on Ubuntu 24.04.
- Run targeted distro-sensitive package and workflow checks on Ubuntu 22.04
  and 26.04.
- Do not treat missing QEMU or unavailable host capabilities as product QA
  findings. The daemon packages remain explicitly deferred until a
  systemd-capable Docker/VM environment is available.

### Findings and disposition
- This phase is observation-only once execution begins: reproduce, document,
  classify, and gather evidence; do not fix findings during the QA run.
- Every finding records severity, direct/adjacent scope, exact reproduction,
  evidence, affected package/workflow, and residual risk.
- Fixes and follow-up routing happen after the QA report is complete, through
  later implementation work or explicitly approved issue/phase artifacts.

### the agent's Discretion
- Choose concrete workflow scenarios and package orderings using the above
  principles.
- Choose the smallest safe fixture and runtime duration for each operation.
- Decide when a repeated symptom is a duplicate of an existing finding.
- Apply the regression-to-zero loop to the package-level findings: newly
  reproducible bugs reset the quiet-round count; quiet rounds end the session
  only after the report is complete.

</decisions>

<specifics>
## Specific Ideas

- The owner wants QA to behave like a persistent, curious user session: go
  beyond superficial launch checks and actively search for problems that could
  appear during normal day-to-day use.
- The test suite should be smart about combinations: model real workflows and
  shared integration surfaces instead of mechanically testing meaningless
  pairs.
- Missing credentials must be surfaced as a request, never hidden as a skip.
- The owner explicitly wants findings gathered first and fixes handled later.

</specifics>

<canonical_refs>
## Canonical References

### Phase and requirements
- `.planning/ROADMAP.md` §Phase 50 — milestone-close integration-QA intent and
  reusable skill boundary.
- `.planning/REQUIREMENTS.md` §Operational verification (OPS-01) — real
  primary-function smoke expectations for catalog categories.
- `.planning/REQUIREMENTS.md` §Integration QA (TST-08) — co-install,
  install-order, residue, and honest-handback expectations.

### QA workflow and harness
- `.claude/skills/qa-testing/SKILL.md` — scoped QA workflow, finding schema,
  time-boxed rounds, and coverage handback.
- `tests/docker/rc-sandbox.sh` — disposable Docker release-candidate setup.
- `tests/bats/helpers/tty-driver.py` — reusable PTY interaction primitive when
  a package workflow genuinely needs a terminal.
- `docs/HARNESS.md` §4 — project review and harness boundaries.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tests/docker/rc-sandbox.sh` provisions the real curl-installer path into a
  disposable Ubuntu environment and is the preferred package-QA fixture.
- Catalog recipes under `plugin/catalog/agents/` define each package's native
  install, verification, and removal contract.
- `plugin/cli/src/commands/{install,remove,list}.ts` exposes the user-facing
  lifecycle commands to exercise.
- `tests/bats/helpers/tty-driver.py` supplies a real PTY for workflows whose
  interactive behavior matters.

### Established Patterns
- Catalog packages are agent-owned and must resolve from their canonical
  per-user paths; `/usr/local` shims and root-owned installs are defects.
- Recipes have package-specific operation surfaces; a generic version check
  cannot establish that the package works.
- Docker is appropriate for package lifecycle and foreground operations;
  systemd-user daemon lifecycle requires a separate VM-capable environment.

### Integration Points
- `plugin/cli/src/runner.ts` dispatches recipes and carries the configured
  install-user environment.
- `plugin/cli/src/rewire.ts` and catalog cross-agent helpers implement
  install-order reconciliation and fan-out behavior.
- Package configuration under the agent home, npm/binary PATH wiring, and
  preserve/remove paths are the primary shared surfaces for interaction QA.

</code_context>

<deferred>
## Deferred Ideas

- `openclaw` and `hermes-agent` systemd-user operation — run in a
  systemd-capable Docker/VM environment later.
- Fixing findings discovered during this sweep — execute only after the QA
  report and evidence are complete.
- Repository/harness refactoring unrelated to a user-visible package defect.

</deferred>

---

*Phase: 50-integration-qa*
*Context gathered: 2026-07-18*
