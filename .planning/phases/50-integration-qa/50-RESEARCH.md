# Phase 50: Integration QA — Research

**Researched:** 2026-07-18
**Question:** What must be known to plan a reusable QA-testing skill and run a credible co-installed catalog sweep?

## Findings

### Existing project contracts

- `AGENTS.md` defines the catalog behavior-test suite as the specification, requires QEMU for release-gate systemd/cloud-init paths, prohibits `sudo npm install -g`, and requires a review pass before completion.
- `CLAUDE.md` currently describes the project-scoped skill list and Claude-specific reviewer dispatch. The new skill must be added there without leaking internal planning vocabulary into user-facing docs.
- `docs/HARNESS.md` §5.2 treats project skills as the canonical home for AgentLinux-specific workflows. `.codex/skills/` symlinks to `.claude/skills/`, so a new skill should have one canonical copy under `.claude/skills/` and a symlink for Codex discovery if the project convention applies.
- The existing `.claude/skills/review/SKILL.md` requires an end-of-phase behavior-coverage audit even when the phase does not add bats tests. Phase 50's own self-check should be deterministic and separate from the reviewer loop.

### Reusable harnesses and seams

- `tests/docker/rc-sandbox.sh` creates a persistent systemd-in-Docker Ubuntu environment, installs a locally built release through the real curl-installer path, and offers interactive `shell` and agent-user `run` commands. It explicitly documents that per-user systemd/logind is not faithfully available there.
- `tests/docker/run-smoke.sh` builds a provisioned container, stages the source and CLI, and runs operational smokes with credentials forwarded by environment name. It is a useful pattern for disposable, credential-free-by-default QA.
- `tests/bats/helpers/tty-driver.py` allocates a real PTY with `pty.fork()`, gates input on observed prompt sentinels, has a bounded timeout, and captures output. It is the closest existing primitive for the required representative TUI session.
- `tests/bats/helpers/interactive.bash` and the prompt sentinel fixtures provide established interactive assertions; they should be reused rather than building a pipe-based prompt driver.
- `tests/docker/Dockerfile.ubuntu-22.04`, `Dockerfile.ubuntu-24.04`, and `Dockerfile.ubuntu-26.04` are the available Ubuntu matrix. Docker is suitable for catalog co-install and CLI/wiring checks; systemd-user daemon behavior remains QEMU-only per ADR-007.

### Integration surfaces to probe

- `plugin/cli/src/commands/{list,install,remove}.ts` and `plugin/cli/src/runner.ts` cover user-facing command output, recipe dispatch, environment/PATH handoff, and failure propagation.
- `plugin/cli/src/rewire.ts` plus `plugin/catalog/lib/mcp-register.sh` cover cross-agent fan-out and reverse-trigger reconciliation when a coding agent is installed after an MCP provider.
- `plugin/catalog/catalog.json`, `plugin/catalog/schema.json`, and the recipes under `plugin/catalog/agents/` define the co-installable entries and install/remove residue boundaries.
- Phase 47/48 daemon recipes and `plugin/catalog/lib/daemon-lifecycle.sh` are representative of the paths that must be called out as unavailable or QEMU-gated in an honest local handback.

## Planning implications

1. The skill must be procedural and self-sufficient: scope derivation, disposable setup, exact PTY geometry/env, high-traffic combinations, bug log schema, quiet-round stop rule, and handback template all belong in `SKILL.md`.
2. The implementation should add a deterministic discoverability/load check (for example, required headings and `bash`/Markdown checks) rather than pretend a Markdown skill can be unit-tested like TypeScript.
3. The integration report must distinguish direct vs adjacent findings, Docker vs QEMU reachability, credentialed vs skipped smokes, and tested vs untested invocation modes.
4. No new catalog recipe is required. Any code defect found during the sweep should be fixed only when small and safe; deeper work must be recorded for a decimal phase or Jira ticket.

## Validation Architecture

### Observable truths

- The skill directory exists, is listed in `CLAUDE.md`, has the required three-pillar headings, names the PTY/harness setup, defines the quiet-round stop condition, and includes a report template.
- A self-check command can discover and load the skill without a Claude session.
- The QA report records executed combinations, findings/dispositions, quiet rounds, and explicit Docker/QEMU and invocation-mode limits.
- The phase verification records either a passed sweep or a maintainer hand-off with the exact remaining coverage gap.

### Verification levels

| Level | Method | What it proves |
|---|---|---|
| Static | `test`, `grep`, `awk`, Markdown structure checks | Skill discoverability and required contract text |
| CLI unit | `cd plugin/cli && pnpm test` | Existing CLI command behavior remains green after integration work |
| Disposable integration | `tests/docker/rc-sandbox.sh` / targeted Docker runs | Co-install, order-independence, UX, and residue behavior in a real AgentLinux environment |
| PTY | `tests/bats/helpers/tty-driver.py` or equivalent session | Interactive prompts and live output are observed through a genuine terminal |
| Release gate | QEMU workflow or explicit handback | systemd-user daemon and other VM-only reachability is not silently conflated with Docker |

### Risks and mitigations

- **False confidence from Docker:** mark openclaw/hermes systemd-user paths QEMU-gated; do not report the Docker result as full coverage.
- **Frozen prompt transcripts:** require a PTY and record `TERM`, width, and color settings; reject captured-pipe-only evidence.
- **State contamination:** use a disposable fresh container for each order-sensitive scenario and assert sibling survival plus residue after remove.
- **Credential leakage:** use environment-only credentials and report skipped credentialed paths without recording values.
- **Checklist theater:** require a bug-arrival-rate stop record and a direct/adjacent finding table; a green fixed checklist alone is insufficient.

## Sources

- `AGENTS.md` — project contracts and review/session rules
- `CLAUDE.md` — Claude skill registration and reviewer routing
- `docs/HARNESS.md` §4–§5 — review loop and project skill conventions
- `tests/docker/rc-sandbox.sh` — persistent interactive Docker harness
- `tests/docker/run-smoke.sh` — disposable smoke/credential forwarding pattern
- `tests/bats/helpers/tty-driver.py` — real PTY interaction primitive
- `plugin/cli/src/commands/`, `plugin/cli/src/runner.ts`, `plugin/cli/src/rewire.ts` — integration surfaces
- `plugin/catalog/catalog.json`, `plugin/catalog/schema.json`, `plugin/catalog/agents/` — catalog and recipe contracts
