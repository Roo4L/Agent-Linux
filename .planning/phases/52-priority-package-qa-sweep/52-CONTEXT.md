# Phase 52: priority-package-qa-sweep - Context

**Gathered:** 2026-07-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Run the reusable `qa-testing` skill as a focused, high-effort black-box QA
campaign against exactly the ten priority catalog packages named in the
roadmap: `claude-code`, `opencode`, `codex`, `gsd`, `spec-kit`,
`playwright-cli`, `gh`, `jira-atlassian-mcp`, `rtk`, and `context7`.

The campaign exercises realistic user operations, interactive behavior,
co-install workflows, installation/removal symmetry, and residue or sibling
preservation in a fresh Ubuntu 24.04 release-candidate environment. It records
factual evidence and findings only. Remediation, ticket creation, and follow-up
disposition happen only after the owner reviews the QA results.

</domain>

<decisions>
## Implementation Decisions

### Distro and terminal depth
- **D-01:** Phase 52 covers Ubuntu 24.04 only. Ubuntu 22.04 and 26.04 are
  explicitly out of scope for this campaign and must be named in the final
  coverage limits; no cross-distro claim should be made.
- **D-02:** Every priority package that exposes a genuine interactive
  interface receives real PTY coverage, including prompts, TUIs, and streaming
  behavior. Purely non-interactive tools remain command-driven.
- **D-03:** Interactive evidence consists of redacted PTY transcripts plus
  terminal metadata such as `TERM`, dimensions, color mode, observed prompts,
  and timing.
- **D-04:** Interactive operations use bounded timeouts. A timeout preserves
  its transcript and receives one retry in a fresh or clean state before it is
  classified.

### Finding disposition
- **D-05:** Phase 52 is strictly observation-only. During the QA campaign, do
  not modify code, tests, recipes, documentation, or create follow-up tickets.
  The owner will direct every finding's disposition after receiving the
  results.
- **D-06:** The QA report contains factual findings only: severity, scope,
  reproduction, evidence, classification, and residual risk. It does not
  include remediation suggestions or routing proposals.
- **D-07:** When a new reproducible issue is found, capture and classify it,
  continue independent QA ideas, and reset the stop-gate counters.
- **D-08:** Do not deliberately replay known Phase 50/51 issues. If a prior
  issue is encountered naturally while testing, mark it as a regression and
  continue with ordinary counter handling; do not create special replay ideas
  or apply special counter treatment.

### the agent's Discretion
- Select realistic package operations, co-install combinations, and
  installation orders within the fixed ten-package scope, following the
  `qa-testing` skill and the Phase 52 roadmap examples.
- Request only the runtime credential classes required by selected operations;
  keep credentials out of recipes, reports, fixtures, and commits, and record
  blocked paths honestly.
- Derive the exact interactive-interface inventory and select appropriate PTY
  geometries and prompt sentinels for each package.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements
- `.planning/ROADMAP.md` §Phase 52 — fixed ten-package priority scope,
  observation goals, stop rule, and handback criteria.
- `.planning/REQUIREMENTS.md` §Integration QA (TST-08) — reusable QA skill,
  co-install expectations, regression-to-zero gate, and honest coverage.
- `.planning/REQUIREMENTS.md` §Operational verification (OPS-01) — real
  package operations beyond version/help checks.
- `.planning/phases/50-integration-qa/50-CONTEXT.md` — locked QA boundaries,
  credential handling, workflow-combination principles, and Docker limits.
- `.planning/phases/51-fix-all-phase-50-integration-qa-findings-known-issues-and-pr/51-CONTEXT.md` —
  remediated baseline, known package/workflow surfaces, and follow-up QA
  expectations.

### QA workflow and evidence
- `.claude/skills/qa-testing/SKILL.md` — scenario ledger, credential
  checkpoint, PTY requirements, finding schema, productive-time/latest-10
  mechanics, and handback template.
- `.planning/phases/50-integration-qa/50-SCENARIO-LEDGER.md` — prior package
  and workflow scenarios to inform natural coverage without deliberate replay.
- `.planning/phases/50-integration-qa/50-QA-REPORT.md` — prior findings,
  boundaries, and evidence style.
- `.planning/phases/50-integration-qa/50-EVIDENCE.md` — redacted prior
  reproductions and durable evidence conventions.
- `tests/docker/rc-sandbox.sh` — disposable release-candidate environment and
  real curl-installer path for package QA.
- `tests/bats/helpers/tty-driver.py` — bounded real-PTY interaction helper and
  prompt-gated input behavior.
- `docs/HARNESS.md` §4 — project review and harness boundaries.

### Catalog and integration surfaces
- `plugin/catalog/catalog.json` — current catalog inventory, pins, source
  kinds, and package metadata.
- `plugin/catalog/agents/` — package-specific install, operation, and removal
  contracts exercised by the QA campaign.
- `plugin/catalog/lib/mcp-register.sh` — cross-agent MCP registration and
  symmetric removal surface.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `.claude/skills/qa-testing/SKILL.md` supplies the reusable campaign contract,
  scenario-ledger structure, finding schema, credential gate, and handback
  format.
- `tests/docker/rc-sandbox.sh` provisions a disposable release-candidate
  container through the real installer path and supports an interactive shell
  plus agent-user command execution.
- `tests/bats/helpers/tty-driver.py` provides prompt-gated PTY input, bounded
  execution, and captured interactive output.
- Existing Phase 50 scenario and evidence artifacts provide realistic workflow
  shapes and redaction conventions.

### Established Patterns
- QA is black-box and user-oriented: package identity checks are necessary but
  never sufficient without a meaningful primary operation.
- Package lifecycle evidence includes install, operation, removal, residue,
  sibling preservation, and idempotent cleanup where meaningful.
- MCP registration is checked through compatible client configuration and
  symmetric removal; credentials remain runtime-only.
- Docker is the package-QA substrate; QEMU/systemd behavior is not inferred or
  claimed from this phase.
- The QA run is observation-only; implementation and disposition are separate
  owner-directed work after the report.

### Integration Points
- `plugin/catalog/catalog.json` defines the ten package identities and pins.
- Catalog recipes, per-user configuration, PATH wiring, MCP registration, and
  removal-preservation paths are the primary user-visible surfaces.
- The phase scenario ledger and QA report are the durable evidence artifacts.

</code_context>

<specifics>
## Specific Ideas

- The owner explicitly wants every priority package with an interactive
  interface tested through a real PTY this time.
- Ubuntu 22.04 and 26.04 should be left aside for this campaign rather than
  expanding the matrix.
- The owner will decide what to do with all QA findings after reviewing the
  results; the agent should not propose or execute remediation.
- Known prior issues should not receive deliberate replay slots. Organic
  encounters should be documented as regressions without special counter
  handling.

</specifics>

<deferred>
## Deferred Ideas

### Reviewed Todos (not folded)
- `2026-03-09-add-pr-preview-deployments-for-website.md` — unrelated website
  tooling; outside the priority-package QA boundary.

</deferred>

---

*Phase: 52-priority-package-qa-sweep*
*Context gathered: 2026-07-19*
