# Requirements: AgentLinux v0.3.0

**Defined:** 2026-04-18
**Milestone:** v0.3.0 AgentLinux Plugin (Ubuntu)
**Core Value:** An agent can be dropped into any supported Linux system and just work — a dedicated agent user with correctly-owned runtime, so self-updates, global npm installs, and tool provisioning happen without permission fights, sudo prompts, or recursive-shim workarounds.

## Design Philosophy (read first)

**Requirements are expressed as observable behaviors, not implementation choices.**

The user's explicit direction for v0.3.0: stop trying to pick the "right" install mechanism, sudo configuration, or package layout upfront. Instead, define what the agent user must be *able to do*, write automated tests that verify it, and let the implementation vary as long as the tests pass.

Consequences:
- A behavior-test suite is a **primary v0.3.0 deliverable**, not a verification-only step.
- Implementation-level requirements (npm vs native installer; sudo vs no-sudo; profile.d wiring pattern) are intentionally absent or framed as "one of several acceptable implementations that pass the behavior tests."
- **No agents installed by default.** The catalog ships Claude Code, GSD, and Chrome DevTools MCP as *available* for installation via the registry CLI. Users opt in with `agentlinux install <name>`.

## v0.3.0 Requirements

Grouped by behavior area. Each `BHV-XX` is a testable, observable behavior — the automated test suite must verify it.

### Installer (INST)

- [ ] **INST-01**: Running the installer on a clean Ubuntu 22.04 or 24.04 system produces a working AgentLinux environment with one command, no interactive prompts, non-zero exit on failure.
- [ ] **INST-02**: The installer is idempotent — re-running it converges; does not duplicate PATH lines, sudoers entries, or skel files; does not error on pre-existing agent user, pre-existing Node.js, or partial prior install.
- [ ] **INST-03**: The installer is distributable via curl-pipe-bash (primary) and verifies release tarball integrity via SHA256 before execution.
- [ ] **INST-04**: The installer supports uninstall that removes the agent user, home, Node.js binaries owned by the install, and any files the installer placed on the system (with a `--purge` flag for destructive home-dir removal).
- [ ] **INST-05**: No invocation of the installer produces a line containing `EACCES` or `permission denied` on stdout or stderr.

### Agent User Behavior (BHV)

Observable behaviors of the provisioned agent user. These are the contract — tests must cover every bullet.

- [x] **BHV-01**: The agent user exists after install, has a bash shell, a real home directory, and a UTF-8 locale configured (`LANG`, `LC_ALL`). (Provisioner landed 02-03; end-to-end bats verification in 02-05.)
- [x] **BHV-02**: The agent user can run commands over **non-interactive SSH** (`ssh agent@host '<cmd>'`) and all installed agent binaries (`claude`, `gsd`, etc.) are findable on PATH. (PATH contract landed 02-04 via `/home/agent/.bashrc` `agentlinux-path` marker block at TOP — precedes skel `case $- in *i*) ;; *) return;;` early-return so non-interactive bash sees PATH + locale; end-to-end bats verification in 02-05.)
- [x] **BHV-03**: The agent user can run commands via **cron** and all installed agent binaries are findable on PATH. (PATH contract landed 02-04 via `/etc/cron.d/agentlinux` literal `PATH=...` header; Pitfall 4 mitigation — no `$PATH` expansion; end-to-end bats verification in 02-05.)
- [x] **BHV-04**: The agent user can run commands via **systemd `User=agent`** and all installed agent binaries are findable on PATH. (PATH contract landed 02-04 via `/etc/agentlinux.env` literal KEY=VALUE file; future units reference via `EnvironmentFile=/etc/agentlinux.env`; end-to-end bats verification in 02-05.)
- [x] **BHV-05**: Another user can run commands as the agent user via `sudo -u agent <cmd>` (or `sudo -u agent -i <cmd>`) and all installed agent binaries are findable on PATH. (PATH contract landed 02-04: `sudo -u agent -i` → `/etc/profile.d/agentlinux.sh` via login shell; `sudo -u agent bash -c` → `.bashrc` TOP marker block; end-to-end bats verification in 02-05.)
- [x] **BHV-06**: The agent user can run commands in an interactive bash login shell and all installed agent binaries are findable on PATH. (PATH contract landed 02-04 via `/etc/profile.d/agentlinux.sh` sourced by `/etc/profile`; re-source guard `AGENTLINUX_PROFILE_SOURCED` prevents double-prepend; end-to-end bats verification in 02-05.)

### Runtime + Global-Install Behavior (RT)

- [ ] **RT-01**: The agent user has a Node.js LTS runtime available. Running `node --version` returns an LTS version number, both interactively and non-interactively.
- [ ] **RT-02**: The agent user can run `npm install -g <some-package>` without sudo, without `EACCES`, without creating any shim/wrapper workarounds. The resulting binary is findable on PATH in every invocation mode from BHV-02..06.
- [ ] **RT-03**: The agent user can run `npm uninstall -g <some-package>` cleanly (no leftover files, binary disappears from PATH).
- [ ] **RT-04**: `npm config get prefix` for the agent user returns a path under the agent user's home directory (or equivalent user-writable path) — never `/usr`, `/usr/local`, or any root-owned path.

### Agent-Tool Behavior (AGT)

Behaviors of installed agent tools. Each behavior is tested once with Claude Code as the canonical example; equivalent tests apply to any catalog tool.

- [ ] **AGT-01**: After `agentlinux install claude-code`, the agent user can run `claude --version` successfully (from interactive shell, non-interactive SSH, cron, systemd, and `sudo -u agent`).
- [ ] **AGT-02**: After `agentlinux install claude-code`, the agent user can self-update Claude Code to a newer version without sudo, without `EACCES`, and without manual intervention (this is the **canonical acceptance test** for v0.3.0).
- [ ] **AGT-03**: `claude doctor` (or equivalent diagnostic) reports a clean state for the agent user after install.
- [ ] **AGT-04**: After `agentlinux install gsd`, the agent user can run `gsd --version` (or equivalent) successfully.
- [ ] **AGT-05**: After `agentlinux install playwright`, the agent user can run `npx playwright --version` and `npx playwright install` (downloads browsers into the agent user's cache, no sudo, no EACCES). Playwright is the canonical browser-access tool for agents (replaces v0.2.0's chrome-devtools-mcp).

### Registry CLI (CLI)

- [ ] **CLI-01**: The `agentlinux` command is available on PATH for the agent user after install.
- [ ] **CLI-02**: `agentlinux list` shows all agents in the catalog with an installed/not-installed indicator.
- [ ] **CLI-03**: `agentlinux install <name>` installs a catalog agent as the agent user, non-interactively, idempotently.
- [ ] **CLI-04**: `agentlinux remove <name>` cleanly uninstalls a catalog agent (binary gone, config restored/removed).
- [ ] **CLI-05**: `agentlinux` commands fail fast with a clear error when run as a non-agent user who lacks permission, and succeed without sudo when run as the agent user.

### Catalog (CAT)

- [ ] **CAT-01**: The v0.3.0 catalog contains at least three available agents: `claude-code`, `gsd`, `playwright`. (Playwright replaces v0.2.0's chrome-devtools-mcp as the canonical browser-access tool.)
- [ ] **CAT-02**: **None of the catalog agents is installed by default.** Fresh install produces an empty-install state; every agent is opt-in via `agentlinux install`.
- [ ] **CAT-03**: The catalog has a documented, machine-readable schema (JSON) so new agents can be added by submitting a catalog entry + install recipe without code changes to the CLI.

### Agent Harness (HRN)

Per `docs/HARNESS.md`. The agent harness is a foundation deliverable shipped as Phase 1 of v0.3.0 — everything else depends on it being in place.

- [x] **HRN-01**: Project layout matches `docs/HARNESS.md` §1 — `plugin/`, `tests/`, `packaging/`, `docs/`, `.claude/agents/`, `.claude/skills/` all created with their documented sub-structure. ✓ Plan 01-01 (17 directories from HARNESS.md §1 created and persisted via `.gitkeep` sentinels) + Plan 01-05 (20 @tests in `tests/harness/00-layout.bats` assert every directory / file still exists and JSON files parse).
- [x] **HRN-02**: A pre-commit configuration is installed and green on every commit, covering shellcheck (bash), shfmt (bash format), biome (TS lint+format), and JSON Schema validation of catalog entries. ✓ Plan 01-02 (`.pre-commit-config.yaml` verbatim from HARNESS.md §1.2; local `catalog-schema-validate` hook wires `plugin/cli/scripts/validate-catalog.mjs`) + Plan 01-05 (8 @tests in `tests/harness/20-precommit.bats` assert the config + each hook; `run.sh` runs `pre-commit run --all-files` as an optional smoke when installed).
- [x] **HRN-03**: A `CLAUDE.md` exists at the repo root, under 150 lines, containing the project identity, critical rules, review-loop instruction, command reference, and pointers per `docs/HARNESS.md` §6. ✓ Plan 01-01 (82 lines)
- [x] **HRN-04**: A `docs/decisions/` ADR directory exists, seeded with ADR-001..ADR-010 from `docs/HARNESS.md` §2.3. ✓ Plan 01-01
- [x] **HRN-05**: All `docs/research/v0.2.0/` and `docs/research/v0.3.0/` subdirectories exist with the appropriate research files migrated out of `.planning/`. ✓ Plan 01-01
- [x] **HRN-06**: Project-scoped review subagents exist in `.claude/agents/`: bash-engineer, node-engineer, security-engineer, qa-engineer, behavior-coverage-auditor, catalog-auditor. ✓ Plan 01-03 (all six `.md` files under `.claude/agents/` with valid Claude Code subagent frontmatter; read-only tool set `Read, Grep, Glob, Bash` per HARNESS.md §4.2 T-03-01 mitigation; rubrics copy-of-truthed from HARNESS.md §4.2.)
- [x] **HRN-07**: A `/review` skill exists in `.claude/skills/` documenting the review-feedback-loop convention from `docs/HARNESS.md` §4. ✓ Plan 01-03 (`.claude/skills/review/SKILL.md` with dispatch rules table, triage rules, ADR-010 trigger citation, and TST-07 end-of-phase gate; CLAUDE.md line 46 already points at it.)
- [x] **HRN-08**: GitHub Actions workflows are configured: `test.yml` (pre-commit + CLI unit tests + Docker bats matrix on every PR), `nightly-qemu.yml` (QEMU release-gate suite), `nightly-mutation.yml` (stryker + bash mutator), `release.yml` (tag → tarball + .deb + sha256 → GitHub Release). ✓ Plan 01-02 (all four YAML files parse; all authored with empty-plugin guards so Phase 1 skeleton commit green-bars; legacy `deploy.yml` untouched.)
- [x] **HRN-09**: Project-scoped skill skeletons exist in `.claude/skills/`: agentlinux-installer, behavior-test-contract, catalog-schema, qemu-harness. ✓ Plan 01-04 (all four `SKILL.md` files under `.claude/skills/<name>/` with valid Claude Code skill frontmatter — `name` matching directory slug + `description` engineered for auto-delegation; bodies 93-116 lines each; non-negotiable rules codified — `set -euo pipefail`, idempotency primitives, `as_user` keystone, sudoers mode 0440, no-EACCES contract, six-invocation-mode matrix, CAT-02 no-default-agents invariant, ADR-007 Docker-only-disqualified rationale; every skill has an explicit growth-plan section naming the phase that absorbs it.)

### Test Harness (TST)

The test harness is a **primary deliverable** of v0.3.0, not a supporting concern. It encodes the entire behavior contract. Mutation testing keeps the suite honest.

- [ ] **TST-01**: A black-box behavior-test suite exists that covers every `BHV-XX`, `RT-XX`, `AGT-XX`, `CLI-XX`, `CAT-XX`, and `INST-XX` requirement with at least one automated test.
- [ ] **TST-02**: Tests run inside a Docker-based harness on Ubuntu 22.04 and 24.04 images. Every PR runs the full suite.
- [ ] **TST-03**: Tests also run inside a QEMU-based harness against a fresh Ubuntu cloud image (nightly and release-gate). Docker-only testing is insufficient per known false-positive categories (root-by-default, no systemd, locale).
- [ ] **TST-04**: Test failures produce a clear diagnostic: which BHV/RT/AGT/CLI/CAT/INST requirement failed, what was expected, what was observed, where the logs live.
- [ ] **TST-05**: The acceptance test `AGT-02` (agent user self-updates Claude Code without sudo/EACCES) is a blocking gate for any release.
- [x] **TST-06**: Mutation testing runs nightly. The Node.js registry CLI uses `stryker-mutator` (target ≥ 75% mutation score, advisory in v0.3.0). Bash sources use a custom `tests/mutation/bash-mutator.sh` (target ≥ 60% mutation score, advisory in v0.3.0). Score regressions open a follow-up issue but do not block release in v0.3.0; promotion to a release gate is a v0.4 decision. ✓ Plan 01-02 (scaffolded: `plugin/cli/stryker.config.json` with `thresholds.break: 0`; `tests/mutation/bash-mutator.sh` executable, exits 0 on empty plugin; `nightly-mutation.yml` uses `continue-on-error: true`; `tests/mutation/README.md` documents advisory status. Full mutant-scoring bodies land in Phase 2+.) + Plan 01-05 (9 @tests in `tests/harness/60-mutation-scaffolding.bats` assert the scaffolding stays runnable and advisory).
- [x] **TST-07**: A `behavior-coverage-auditor` review subagent (per HRN-06) runs at the end of every phase to assert that every newly-added BHV/RT/AGT/CLI/CAT/INST requirement has at least one bats test. ✓ Plan 01-03 (`.claude/agents/behavior-coverage-auditor.md` defines the subagent; `.claude/skills/review/SKILL.md` §"Relation to TST-07" names it as the "always spawn at phase close regardless of what changed" gate; emits `TST-07 gate: RED|GREEN` summary line for the main agent to decide phase close.)

### Documentation (DOC)

- [ ] **DOC-01**: A README ships with the installer describing: how to install, how to verify (`agentlinux list` + one test command), how to uninstall.
- [x] **DOC-02**: A `CLAUDE.md` is placed in the agent user's home with guidance that the environment is correctly owned and agent tools must NOT create shim/wrapper workarounds. Prevents LLM agents from pattern-matching on past permission bugs and introducing the exact class of shim AgentLinux exists to prevent. (Landed 02-03 via ensure_marker_block with tag `agentlinux-doc-02`; bats grep-verification in 02-05.)

## Future Requirements (deferred to v0.4+)

Tracked but not in v0.3.0 scope.

### Cross-Distro
- **DST-01**: Fedora/Alma/CentOS support
- **DST-02**: Arch/openSUSE support
- **DST-03**: Automatic distro detection at install time

### Distribution / Update Infrastructure
- **INF-01**: Public PPA or hosted apt repository with package signing
- **INF-02**: `.deb` distribution as a first-class path (not optional)
- **INF-03**: `agentlinux self-update` command (fetches newer installer and re-runs)
- **INF-04**: Auto-update daemon (opt-in)

### Registry Power-Ups
- **CAT-04**: Remote-fetch catalog with embedded fallback
- **CAT-05**: Multiple install backends per catalog entry (npm / apt / binary download / pipx)
- **CLI-06**: `agentlinux info <name>` — detailed info per agent
- **CLI-07**: `agentlinux update <name>` — delegates to the agent's own self-update
- **CLI-08**: `agentlinux doctor` — system-wide health check

### Advanced Agent User
- **USR-04**: Multiple agent users per host (multi-tenant provisioning)
- **USR-05**: Sandboxing / rootless-container mode

## Out of Scope (permanently or near-permanently)

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Custom distro / ISO / QCOW2 image | Retired with v0.2.0 → v0.3.0 pivot |
| OpenNebula deploy & test pipeline | Retired with v0.2.0 → v0.3.0 pivot |
| `.deb` packages for Claude Code / GSD / MCP as standalone distro artifacts | Superseded by in-installer install via the registry CLI |
| Default agents installed automatically | Explicit v0.3.0 design: zero defaults, everything opt-in |
| GUI or TUI installer | CLI-only — matches product aesthetic and minimizes dependencies |
| Docker-in-Docker inside the agent environment | High complexity, niche use case |
| Agent sandboxing per individual task | Claude Code's own concern, not the installer's |
| Telemetry / phone-home | Privacy stance; not our data to collect |
| Multi-arch (ARM) | x86_64-only for v0.3.0; ARM considered later |
| Fleet / config-management integration (Ansible/Chef/Puppet) | Single-host installer; fleet tooling is downstream users' problem |
| Snap as distribution mechanism | AppArmor confinement incompatible with agent filesystem access |
| nvm/fnm/volta for agent Node.js | Shell-hook activation breaks cron, systemd, non-interactive SSH |

## Traceability

Mapped by roadmapper on 2026-04-18. See `.planning/ROADMAP.md` for phase details.

| Requirement | Phase | Status |
|-------------|-------|--------|
| HRN-01 | Phase 1 | ✓ Complete (01-01 + 01-05 verified) |
| HRN-02 | Phase 1 | ✓ Complete (01-02 + 01-05 verified) |
| HRN-03 | Phase 1 | ✓ Complete (01-01 + 01-05 verified) |
| HRN-04 | Phase 1 | ✓ Complete (01-01 + 01-05 verified) |
| HRN-05 | Phase 1 | ✓ Complete (01-01 + 01-05 verified) |
| HRN-06 | Phase 1 | ✓ Complete (01-03 + 01-05 verified) |
| HRN-07 | Phase 1 | ✓ Complete (01-03 + 01-05 verified) |
| HRN-08 | Phase 1 | ✓ Complete (01-02 + 01-05 verified) |
| HRN-09 | Phase 1 | ✓ Complete (01-04 + 01-05 verified) |
| TST-06 | Phase 1 | ✓ Complete (01-02 scaffolded + 01-05 verified) |
| TST-07 | Phase 1 | ✓ Complete (01-03 + 01-05 scaffold-verified) |
| INST-01 | Phase 2 | Pending |
| INST-02 | Phase 2 | Pending |
| INST-05 | Phase 2 | Pending |
| BHV-01 | Phase 2 | ✓ Satisfied (02-03 provisioner; bats verification in 02-05) |
| BHV-02 | Phase 2 | ✓ Satisfied (02-04 .bashrc --top marker block sources profile.d before skel early-return; bats verification in 02-05) |
| BHV-03 | Phase 2 | ✓ Satisfied (02-04 /etc/cron.d/agentlinux literal PATH header; bats verification in 02-05) |
| BHV-04 | Phase 2 | ✓ Satisfied (02-04 /etc/agentlinux.env for systemd EnvironmentFile=; bats verification in 02-05) |
| BHV-05 | Phase 2 | ✓ Satisfied (02-04 profile.d for sudo -u agent -i + .bashrc --top for sudo -u agent bash -c; bats verification in 02-05) |
| BHV-06 | Phase 2 | ✓ Satisfied (02-04 /etc/profile.d/agentlinux.sh sourced by /etc/profile on login; bats verification in 02-05) |
| DOC-02 | Phase 2 | ✓ Satisfied (02-03 CLAUDE.md placement; bats grep-verification in 02-05) |
| TST-01 | Phase 2 | Pending |
| TST-02 | Phase 2 | Pending |
| TST-04 | Phase 2 | Pending |
| RT-01 | Phase 3 | Pending |
| RT-02 | Phase 3 | Pending |
| RT-03 | Phase 3 | Pending |
| RT-04 | Phase 3 | Pending |
| CLI-01 | Phase 4 | Pending |
| CLI-02 | Phase 4 | Pending |
| CLI-03 | Phase 4 | Pending |
| CLI-04 | Phase 4 | Pending |
| CLI-05 | Phase 4 | Pending |
| CAT-01 | Phase 4 | Pending |
| CAT-02 | Phase 4 | Pending |
| CAT-03 | Phase 4 | Pending |
| INST-04 | Phase 4 | Pending |
| AGT-01 | Phase 5 | Pending |
| AGT-02 | Phase 5 | Pending |
| AGT-03 | Phase 5 | Pending |
| AGT-04 | Phase 5 | Pending |
| AGT-05 | Phase 5 | Pending |
| INST-03 | Phase 6 | Pending |
| TST-03 | Phase 6 | Pending |
| TST-05 | Phase 6 | Pending |
| DOC-01 | Phase 6 | Pending |

**Coverage:**
- v0.3.0 requirements: 46 total (9 HRN + 5 INST + 6 BHV + 4 RT + 5 AGT + 5 CLI + 3 CAT + 7 TST + 2 DOC)
- Mapped to phases: 46 (100%)
- Unmapped: 0

**Per-phase counts:**
- Phase 1 (Harness Setup): 11 — HRN-01..HRN-09, TST-06, TST-07
- Phase 2 (Installer Foundation + Agent User): 13 — INST-01, INST-02, INST-05, BHV-01..BHV-06, DOC-02, TST-01, TST-02, TST-04
- Phase 3 (Node.js Runtime + Per-User npm Prefix): 4 — RT-01..RT-04
- Phase 4 (Registry CLI + Catalog + Uninstall): 9 — CLI-01..CLI-05, CAT-01..CAT-03, INST-04
- Phase 5 (Agent Installability): 5 — AGT-01..AGT-05
- Phase 6 (Distribution + Release Pipeline): 4 — INST-03, TST-03, TST-05, DOC-01

---
*Requirements defined: 2026-04-18 — behavior-contract framing per user direction; implementation left intentionally open.*
*Traceability mapped: 2026-04-18 — 46/46 requirements mapped across 6 phases, 0 orphans.*
