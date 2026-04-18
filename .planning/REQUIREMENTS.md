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

- [ ] **BHV-01**: The agent user exists after install, has a bash shell, a real home directory, and a UTF-8 locale configured (`LANG`, `LC_ALL`).
- [ ] **BHV-02**: The agent user can run commands over **non-interactive SSH** (`ssh agent@host '<cmd>'`) and all installed agent binaries (`claude`, `gsd`, etc.) are findable on PATH.
- [ ] **BHV-03**: The agent user can run commands via **cron** and all installed agent binaries are findable on PATH.
- [ ] **BHV-04**: The agent user can run commands via **systemd `User=agent`** and all installed agent binaries are findable on PATH.
- [ ] **BHV-05**: Another user can run commands as the agent user via `sudo -u agent <cmd>` (or `sudo -u agent -i <cmd>`) and all installed agent binaries are findable on PATH.
- [ ] **BHV-06**: The agent user can run commands in an interactive bash login shell and all installed agent binaries are findable on PATH.

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

- [ ] **HRN-01**: Project layout matches `docs/HARNESS.md` §1 — `plugin/`, `tests/`, `packaging/`, `docs/`, `.claude/agents/`, `.claude/skills/` all created with their documented sub-structure.
- [ ] **HRN-02**: A pre-commit configuration is installed and green on every commit, covering shellcheck (bash), shfmt (bash format), biome (TS lint+format), and JSON Schema validation of catalog entries.
- [ ] **HRN-03**: A `CLAUDE.md` exists at the repo root, under 150 lines, containing the project identity, critical rules, review-loop instruction, command reference, and pointers per `docs/HARNESS.md` §6.
- [ ] **HRN-04**: A `docs/decisions/` ADR directory exists, seeded with ADR-001..ADR-010 from `docs/HARNESS.md` §2.3.
- [ ] **HRN-05**: All `docs/research/v0.2.0/` and `docs/research/v0.3.0/` subdirectories exist with the appropriate research files migrated out of `.planning/`.
- [ ] **HRN-06**: Project-scoped review subagents exist in `.claude/agents/`: bash-engineer, node-engineer, security-engineer, qa-engineer, behavior-coverage-auditor, catalog-auditor.
- [ ] **HRN-07**: A `/review` skill exists in `.claude/skills/` documenting the review-feedback-loop convention from `docs/HARNESS.md` §4.
- [ ] **HRN-08**: GitHub Actions workflows are configured: `test.yml` (pre-commit + CLI unit tests + Docker bats matrix on every PR), `nightly-qemu.yml` (QEMU release-gate suite), `nightly-mutation.yml` (stryker + bash mutator), `release.yml` (tag → tarball + .deb + sha256 → GitHub Release).
- [ ] **HRN-09**: Project-scoped skill skeletons exist in `.claude/skills/`: agentlinux-installer, behavior-test-contract, catalog-schema, qemu-harness.

### Test Harness (TST)

The test harness is a **primary deliverable** of v0.3.0, not a supporting concern. It encodes the entire behavior contract. Mutation testing keeps the suite honest.

- [ ] **TST-01**: A black-box behavior-test suite exists that covers every `BHV-XX`, `RT-XX`, `AGT-XX`, `CLI-XX`, `CAT-XX`, and `INST-XX` requirement with at least one automated test.
- [ ] **TST-02**: Tests run inside a Docker-based harness on Ubuntu 22.04 and 24.04 images. Every PR runs the full suite.
- [ ] **TST-03**: Tests also run inside a QEMU-based harness against a fresh Ubuntu cloud image (nightly and release-gate). Docker-only testing is insufficient per known false-positive categories (root-by-default, no systemd, locale).
- [ ] **TST-04**: Test failures produce a clear diagnostic: which BHV/RT/AGT/CLI/CAT/INST requirement failed, what was expected, what was observed, where the logs live.
- [ ] **TST-05**: The acceptance test `AGT-02` (agent user self-updates Claude Code without sudo/EACCES) is a blocking gate for any release.
- [ ] **TST-06**: Mutation testing runs nightly. The Node.js registry CLI uses `stryker-mutator` (target ≥ 75% mutation score, advisory in v0.3.0). Bash sources use a custom `tests/mutation/bash-mutator.sh` (target ≥ 60% mutation score, advisory in v0.3.0). Score regressions open a follow-up issue but do not block release in v0.3.0; promotion to a release gate is a v0.4 decision.
- [ ] **TST-07**: A `behavior-coverage-auditor` review subagent (per HRN-06) runs at the end of every phase to assert that every newly-added BHV/RT/AGT/CLI/CAT/INST requirement has at least one bats test.

### Documentation (DOC)

- [ ] **DOC-01**: A README ships with the installer describing: how to install, how to verify (`agentlinux list` + one test command), how to uninstall.
- [ ] **DOC-02**: A `CLAUDE.md` is placed in the agent user's home with guidance that the environment is correctly owned and agent tools must NOT create shim/wrapper workarounds. Prevents LLM agents from pattern-matching on past permission bugs and introducing the exact class of shim AgentLinux exists to prevent.

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

Populated by the roadmapper during phase creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| INST-01 | TBD | Pending |
| INST-02 | TBD | Pending |
| INST-03 | TBD | Pending |
| INST-04 | TBD | Pending |
| INST-05 | TBD | Pending |
| BHV-01 | TBD | Pending |
| BHV-02 | TBD | Pending |
| BHV-03 | TBD | Pending |
| BHV-04 | TBD | Pending |
| BHV-05 | TBD | Pending |
| BHV-06 | TBD | Pending |
| RT-01 | TBD | Pending |
| RT-02 | TBD | Pending |
| RT-03 | TBD | Pending |
| RT-04 | TBD | Pending |
| AGT-01 | TBD | Pending |
| AGT-02 | TBD | Pending |
| AGT-03 | TBD | Pending |
| AGT-04 | TBD | Pending |
| AGT-05 | TBD | Pending |
| CLI-01 | TBD | Pending |
| CLI-02 | TBD | Pending |
| CLI-03 | TBD | Pending |
| CLI-04 | TBD | Pending |
| CLI-05 | TBD | Pending |
| CAT-01 | TBD | Pending |
| CAT-02 | TBD | Pending |
| CAT-03 | TBD | Pending |
| HRN-01 | TBD | Pending |
| HRN-02 | TBD | Pending |
| HRN-03 | TBD | Pending |
| HRN-04 | TBD | Pending |
| HRN-05 | TBD | Pending |
| HRN-06 | TBD | Pending |
| HRN-07 | TBD | Pending |
| HRN-08 | TBD | Pending |
| HRN-09 | TBD | Pending |
| TST-01 | TBD | Pending |
| TST-02 | TBD | Pending |
| TST-03 | TBD | Pending |
| TST-04 | TBD | Pending |
| TST-05 | TBD | Pending |
| TST-06 | TBD | Pending |
| TST-07 | TBD | Pending |
| DOC-01 | TBD | Pending |
| DOC-02 | TBD | Pending |

**Coverage:**
- v0.3.0 requirements: 46 total (9 HRN + 5 INST + 6 BHV + 4 RT + 5 AGT + 5 CLI + 3 CAT + 7 TST + 2 DOC)
- Mapped to phases: 0 (roadmapper pending)
- Unmapped: 46

---
*Requirements defined: 2026-04-18 — behavior-contract framing per user direction; implementation left intentionally open.*
