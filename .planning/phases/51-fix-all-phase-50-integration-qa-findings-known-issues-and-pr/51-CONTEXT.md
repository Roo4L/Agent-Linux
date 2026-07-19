# Phase 51: unified integration-QA remediation - Context

**Gathered:** 2026-07-19
**Status:** Ready for planning
**Mode:** Interactive discuss

<domain>
## Phase Boundary

Remediate every actionable Phase 50 integration-QA finding, known issue, and
prerequisite boundary: Firecrawl authentication, OpenCode GitHub MCP OAuth,
Playwright failure status and browser runtime dependencies, GSD/Codex
compatibility, and the Spec Kit/Chrome/system dependency paths. Add regression
coverage, revalidate the affected workflows, and repeat the reusable
`qa-testing` sweep across the Phase 50 in-scope packages and representative
co-installed workflows. Record resolved issues, remaining blockers, and any
new findings. `openclaw` and `hermes-agent` remain outside the Docker follow-up
unless a systemd-capable environment becomes available.

This phase does not absorb unrelated catalog growth or website tooling work.

</domain>

<decisions>
## Implementation Decisions

### Firecrawl authentication contract
- **D-01:** Reproduce Firecrawl's documented API-key URL path using a runtime-only credential during investigation. The API key must not be committed, written into planning evidence, or baked into a catalog recipe or release artifact.
- **D-02:** Also test the bare `https://mcp.firecrawl.dev/v2/mcp` endpoint through the documented MCP OAuth flow. Prefer the credential-safe OAuth path for clients that support it; if API-key authentication is the only working path for a client, define a truthful and explicit user-facing fallback rather than silently claiming keyless operation.
- **D-03:** The final catalog description, install guidance, metadata, and regression tests must match the authentication behavior that is actually reproducible. The current false promise of unrestricted keyless scraping must not remain.

### Hosted MCP and OpenCode compatibility
- **D-04:** Do not skip OpenCode or reduce the five-client MCP fan-out merely because the Phase 50 OAuth attempt failed. Investigate the root cause against the current OpenCode implementation and the GitHub MCP authorization/discovery responses.
- **D-05:** Use OpenCode's documented OAuth diagnostics and compare client version, remote-resource metadata, authorization-server discovery, dynamic client registration, redirect URI handling, stored auth state, and the actual browser authorization flow. Repair the recipe, client configuration, or compatible package version as evidence requires.
- **D-06:** Add a regression that covers OpenCode registration, OAuth authorization, and a GitHub MCP read-only operation, while preserving sibling-agent registrations and symmetric removal. The ADR-017 no-baked-credential rule remains in force.

### Playwright action failures
- **D-07:** Any unresolved action target or other failed action resolution must return a nonzero process status, including the observed `click` and `fill` cases. Human-readable diagnostics should remain available.
- **D-08:** Treat this as a general action-command contract, not a narrow test-only correction for the two observed commands. Cover representative action families in regression tests and verify that successful actions continue to return zero.

### System prerequisites and runtime dependencies
- **D-09:** Make the required `git`, Chrome, and Playwright browser-library dependencies available automatically as part of the AgentLinux package workflow where possible. First attempt installation through the agent user's available `apt`/`dnf` access.
- **D-10:** If an operating-system dependency cannot be installed with the agent user's privileges, stop with an explicit, actionable explanation and request sudo/root permission rather than silently downgrading the workflow to help/version checks or leaving a misleading partial install.
- **D-11:** Revalidate fresh-image behavior on the relevant Ubuntu versions and retain the project's agent-owned install, no `/usr/local` shim, idempotent uninstall, and no-credential guarantees.

### GSD and Codex integration
- **D-12:** Replace the current `get-shit-done-cc` package behind the existing `gsd` catalog entry with the current official Open GSD distribution (`@opengsd/gsd-core`), selecting and pinning an exact stable release during research/planning rather than shipping an unbounded `latest` dependency.
- **D-13:** Codex integration is mandatory. Do not preserve the current GSD recipe behavior that skips Codex. Verify the upgraded Open GSD package's Codex support end-to-end; if the generated Codex configuration remains incompatible, fix the integration/configuration path or find a compatible upstream/package approach.
- **D-14:** Preserve the existing `agentlinux install gsd` user-facing catalog identity unless research shows that Open GSD's official installer requires a transparent, documented catalog metadata change.

### Gemini observation closure
- **D-15:** Close the Phase 50 Gemini stream symptom as an unconfirmed/environmental observation after regression verification of the corrected invocation. Do not add speculative retry or stream-recovery behavior without a reproducible AgentLinux-owned defect.

### Follow-up QA and completion
- **D-16:** After remediation and targeted regressions, rerun the `qa-testing` workflow across the Phase 50 in-scope package set and representative workflows, not only the fixed paths. Record each known issue's disposition, remaining credential/prerequisite/systemd boundaries, and every newly discovered problem before declaring the phase complete.

### the agent's Discretion
- Exact Firecrawl API-key runtime injection and OAuth client mechanics, provided secrets remain runtime-only and the final contract is truthful.
- The smallest compatible OpenCode/GitHub MCP repair after discovery of the actual OAuth failure.
- Exact package-manager commands, dependency package names, preflight checks, and whether a dependency belongs in the catalog recipe or shared AgentLinux provisioning, subject to the explicit escalation rule above.
- The exact Open GSD stable release selected after checking the upstream package, release, and compatibility requirements.
- Regression fixture contents, QA scenario ordering, and the minimum safe duration/coverage needed to satisfy the Phase 51 exit gate.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and Phase 50 handback
- `.planning/ROADMAP.md` §Phase 51 — remediation goal, exclusions, and mandatory follow-up QA exit gate.
- `.planning/phases/50-integration-qa/50-QA-REPORT.md` — confirmed findings F-004/F-005/F-006, unconfirmed F-007, known K-001/K-002, and expected boundaries B-001/B-002.
- `.planning/phases/50-integration-qa/50-EVIDENCE.md` — durable redacted reproduction evidence for each finding and boundary.
- `.planning/phases/50-integration-qa/50-SCENARIO-LEDGER.md` — package/workflow coverage and follow-up scenarios.
- `.planning/phases/50-integration-qa/50-CONTEXT.md` — locked QA boundaries, credential rules, observation-only discovery posture, and Docker/QEMU limits.
- `.claude/skills/qa-testing/SKILL.md` — reusable QA workflow, credential checkpoint, finding schema, productive-time/latest-10 stop rule, and honest handback requirements.

### Requirements and MCP policy
- `.planning/REQUIREMENTS.md` §Operational verification (OPS-01) — real package operations beyond version/help checks.
- `.planning/REQUIREMENTS.md` §Integration QA (TST-08) — co-install, install-order, residue, and honest coverage requirements.
- `docs/decisions/017-mcp-thin-installer-in-client-auth.md` — bare hosted MCP registration, in-client authentication, and no credential stored by AgentLinux.
- `plugin/catalog/lib/mcp-register.sh` — shared five-client remote-MCP registration and deregistration behavior.
- `plugin/catalog/catalog.json` — catalog schema data and current package pins/metadata.

### Firecrawl and hosted OAuth
- `plugin/catalog/agents/firecrawl-mcp/install.sh` — current keyless endpoint contract and user guidance to reassess.
- `plugin/catalog/agents/firecrawl-mcp/uninstall.sh` — symmetric remote registration removal.
- `tests/bats/62-catalog-firecrawl-mcp.bats` — current Firecrawl entry-shape, no-credential, fan-out, and removal contract.
- `https://docs.firecrawl.dev/developer-guides/mcp-setup-guides/oauth` — Firecrawl's documented API-key URL and keyless OAuth flows, dynamic client registration, redirect requirements, and client fallback guidance.
- `plugin/catalog/agents/github-mcp/install.sh` — current GitHub hosted-MCP fan-out contract.
- `tests/bats/60-catalog-github-mcp.bats` — GitHub MCP fan-out and symmetric removal coverage.
- `https://opencode.ai/docs/mcp-servers/#oauth` — OpenCode remote MCP OAuth behavior, dynamic registration, authentication commands, stored auth state, and `mcp debug` diagnostics.

### Package recipes and runtime dependencies
- `plugin/catalog/agents/playwright-cli/install.sh` — current Playwright package installation path.
- `plugin/catalog/agents/playwright-cli/uninstall.sh` — current Playwright removal/preservation behavior.
- `plugin/catalog/agents/spec-kit/install.sh` — git-tag uv installation and current git prerequisite behavior.
- `plugin/catalog/agents/spec-kit/uninstall.sh` — managed uv removal and project preservation contract.
- `plugin/catalog/agents/chrome-devtools-mcp/install.sh` — current Chrome prerequisite and MCP registration behavior.
- `plugin/catalog/agents/chrome-devtools-mcp/uninstall.sh` — symmetric registration removal.
- `tests/docker/rc-sandbox.sh` — fresh release-candidate environment used for package QA and dependency validation.
- `tests/bats/66-catalog-spec-kit.bats` — Spec Kit/uv lifecycle and real-operation coverage.

### GSD and Codex
- `plugin/catalog/agents/gsd/install.sh` — current GSD install and Codex fan-out skip behavior to replace.
- `plugin/catalog/agents/gsd/uninstall.sh` — current GSD cleanup contract.
- `plugin/catalog/agents/codex/install.sh` — Codex package/config preservation contract.
- `tests/bats/70-catalog-cross-wire.bats` — cross-agent wiring, order-independence, and sibling-preserving removal patterns.
- `https://github.com/open-gsd/gsd-core` — official Open GSD distribution, supported runtimes, installation model, and release history.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `.claude/skills/qa-testing/SKILL.md` plus the Phase 50 scenario ledger and report provide the follow-up campaign structure and redacted evidence format.
- `plugin/catalog/lib/mcp-register.sh` already centralizes remote HTTP fan-out to Claude Code, Codex, Gemini CLI, OpenCode, and Qwen Code, with idempotent registration and removal.
- Catalog recipe pairs under `plugin/catalog/agents/` provide the install/remove seams; the existing Firecrawl, GitHub MCP, Spec Kit, Chrome DevTools MCP, GSD, and Codex recipes are the direct remediation surfaces.
- `tests/bats/60-catalog-github-mcp.bats`, `tests/bats/62-catalog-firecrawl-mcp.bats`, `tests/bats/66-catalog-spec-kit.bats`, and `tests/bats/70-catalog-cross-wire.bats` provide established lifecycle, fan-out, credential, prerequisite, and order-independence assertion patterns.
- `tests/docker/rc-sandbox.sh` provides disposable fresh-image validation without contaminating the host.

### Established Patterns
- MCP entries follow ADR-017: register a bare hosted endpoint, let the client authenticate, store no AgentLinux credential, and remove registrations symmetrically.
- Catalog installs must be agent-owned, must not use `sudo npm install -g`, must not create `/usr/local/bin` shims, and must preserve user-owned configuration/data according to each recipe's contract.
- Behavior tests are the product specification; implementation may change as long as install → real operation → remove → residue checks remain green.
- Docker validates package lifecycle and foreground operations; systemd-user daemon behavior remains QEMU/VM-gated and is not silently claimed by this phase.
- The Phase 50 QA campaign deliberately observed and documented findings without fixing them; Phase 51 is the remediation boundary.

### Integration Points
- `plugin/catalog/catalog.json` controls package identity, pins, dependency metadata, and recipe dispatch.
- `plugin/catalog/lib/mcp-register.sh` and per-agent configuration files are the shared hosted-MCP compatibility surface.
- `plugin/cli/src/runner.ts`, the catalog recipes, and the installed agent user's PATH/environment determine how dependencies and package operations execute.
- `tests/bats/` and `tests/docker/` provide regression and fresh-image validation; the final `qa-testing` rerun is the phase exit evidence.

</code_context>

<specifics>
## Specific Ideas

- The owner explicitly requires Codex integration to remain enabled; skipping Codex is unacceptable.
- Firecrawl should be tested through both documented API-key and OAuth paths before changing the catalog contract. Firecrawl's documentation states that the keyless endpoint uses OAuth with dynamic client registration, while clients without OAuth can use an API-key URL.
- OpenCode's documentation claims dynamic client registration and provides `opencode mcp debug`; the Phase 50 failure should be diagnosed rather than accepted as a permanent incompatibility.
- Dependency installation should feel automatic on a fresh AgentLinux environment. The agent user's package-manager access should be tried first, with explicit privilege escalation only when required.
- The Open GSD upstream repository currently advertises v1.7.0 as its latest release as of context gathering; planning must verify the exact release and pin before implementation.

</specifics>

<deferred>
## Deferred Ideas

- Website PR preview deployments from the unrelated pending todo `2026-03-09-add-pr-preview-deployments-for-website.md` — outside Phase 51's package-remediation boundary.
- `openclaw` and `hermes-agent` daemon operation — remains excluded until a systemd-capable Docker/VM environment is available.
- Unrelated catalog additions, package upgrades, or repository/harness refactors not required to resolve the Phase 50 handback.

</deferred>

---

*Phase: 51-fix-all-phase-50-integration-qa-findings-known-issues-and-pr*
*Context gathered: 2026-07-19*
