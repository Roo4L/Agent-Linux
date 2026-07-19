# Phase 51: Existing Patterns

**Created:** 2026-07-19
**Purpose:** Pattern map for planning Phase 51 remediation work.

## Catalog recipes and shared helpers

| Phase 51 seam | Closest analog | Pattern to preserve |
|---|---|---|
| Firecrawl/GitHub hosted MCP | `plugin/catalog/agents/firecrawl-mcp/install.sh`, `plugin/catalog/agents/github-mcp/install.sh` | Thin recipe sources `plugin/catalog/lib/mcp-register.sh`, registers a bare URL into present clients, prints an actionable note, and uninstall calls `al_mcp_deregister` plus `al_mcp_assert_absent`. |
| MCP metadata/regression | `tests/bats/60-catalog-github-mcp.bats`, `tests/bats/62-catalog-firecrawl-mcp.bats` | Assert catalog shape, fan-out into conditionally present clients, no credential-shaped strings, symmetric removal, idempotent re-remove, and no Docker recipe. |
| GSD cross-agent wiring | `plugin/catalog/agents/gsd/install.sh`, `tests/bats/70-catalog-cross-wire.bats` | Provider install wires supported agents, later consumer install triggers reconciliation, removal is sibling-preserving and residue-free. |
| Spec Kit/uv prerequisite | `plugin/catalog/agents/spec-kit/install.sh`, `plugin/catalog/lib/uv-bootstrap.sh`, `tests/bats/66-catalog-spec-kit.bats` | Use `set -euo pipefail`, agent-owned paths, managed-resource markers, explicit prerequisite errors, and preserve project `.specify/` data. |

## Dependency and privilege patterns

- `plugin/lib/detect/user.sh` is the existing distro-aware probe for whether the install user can run `/usr/bin/apt-get` or `/usr/bin/dnf` through non-interactive sudo. Reuse its absolute-path and no-hang behavior rather than inventing a second privilege detector.
- `plugin/provisioner/` owns root-level host setup and should be considered if browser/git dependencies cannot safely be installed by an agent-user catalog recipe. Any recipe-level escalation must be explicit and must not use a hidden password prompt.
- `tests/bats/helpers/invoke_modes.bash` and the Docker harness encode the six invocation modes and no-EACCES contract. Any new PATH or environment variable must be mirrored in the invocation helpers.

## CLI/package patterns

- `plugin/cli/src/runner.ts` dispatches catalog recipes as the configured install user and supplies `AGENTLINUX_AGENT_HOME`, `AGENTLINUX_CATALOG_DIR`, PATH, and preserve-path state.
- `plugin/cli/src/rewire.ts` is the post-install reconcile seam for provider/consumer order independence. Hosted MCP registration uses the shared helper; GSD skill wiring uses its own recipe behavior.
- Existing npm catalog recipes install globally only through the runner's agent-owned npm prefix. Never add root npm installation or `/usr/local/bin` wrappers.
- Catalog entries are pinned in `plugin/catalog/catalog.json`; an upstream upgrade must update the pin, compatibility metadata, tests, and any detection mapping together.

## Test and QA patterns

- Behavior tests use `@test` requirement IDs and shared assertion helpers. New tests should be black-box: invoke `agentlinux install`, perform a real minimal operation, remove, then assert ownership, path, sibling preservation, and residue.
- `tests/docker/rc-sandbox.sh` creates disposable release-candidate environments. Use temporary HOME/config roots and runtime-only credentials for OAuth/API-key diagnostics; durable output is redacted.
- `tests/harness/run.sh` and `pre-commit` checks are the phase-level static gates. `./tests/docker/run.sh ubuntu-24.04` is the full Docker validation command; Ubuntu 22.04 and 26.04 are targeted for distro-sensitive dependency behavior.
- `.claude/skills/qa-testing/SKILL.md` plus Phase 50's `50-SCENARIO-LEDGER.md` and `50-QA-REPORT.md` define the final follow-up sweep, including the productive-time/latest-10 clean stop rule and honest blocked/excluded coverage.

## Likely file/data-flow map

1. `plugin/catalog/catalog.json` → catalog schema/runner → per-user recipe → installed agent/client config.
2. `plugin/catalog/lib/mcp-register.sh` → client-specific config files → OAuth/API-key client behavior → symmetric `uninstall.sh`.
3. Dependency resolver/provisioner → apt/dnf/Chrome/browser libraries → Playwright or Chrome DevTools MCP real operation.
4. GSD recipe/package installer → per-agent skill/command config → Codex TOML/config → cross-wire Bats and `codex exec`.
5. Targeted Bats/Docker checks → redacted Phase 51 QA evidence → final `qa-testing` follow-up report.
