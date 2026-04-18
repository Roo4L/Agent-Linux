# Roadmap: AgentLinux v0.3.0 — Installable Ubuntu Plugin

**Milestone:** v0.3.0 AgentLinux Plugin (Ubuntu)
**Started:** 2026-04-18
**Phase numbering:** Restart at Phase 1 (clean break from retired v0.2.0 distro-era phases; user approved `--reset-phase-numbers`).

## Overview

v0.3.0 replaces the retired v0.2.0 custom-distro approach with an **installable extension** for existing Ubuntu systems. A user runs one command; the installer provisions a dedicated `agent` user with a correctly-owned Node.js runtime and a CLI registry for opting into agent tools. Requirements are expressed as observable behaviors — the bats test suite is the spec, implementation is free to vary as long as the suite stays green.

The critical path is: **harness first** (Phase 1), then **build the installable base in layers** (Phases 2–5, each shipping implementation *with* its behavior-contract tests), then **ship it** (Phase 6 — distribution, release pipeline, QEMU release gate, and the AGT-02 self-update gate enforced in CI). No phase ships implementation without the tests that prove it.

Key locked decisions honored by this roadmap:
- Phase 1 is Harness Setup — project skeleton, review infra, skills, ADRs, GH Actions scaffolding. No installer code in Phase 1.
- No agent is installed by default. Catalog (claude-code, gsd, playwright) ships as available; users opt in via `agentlinux install <name>`.
- AGT-02 (Claude Code self-update without sudo/EACCES) is the canonical acceptance test and is wired as a release gate in Phase 6.
- QEMU testing is mandatory, not optional; Docker alone is insufficient.
- Mutation testing is advisory in v0.3.0; promotion to release gate is a v0.4 decision.
- Playwright replaces Chrome DevTools MCP as the canonical browser-access tool in the catalog.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [ ] **Phase 1: Harness Setup** - Project skeleton, pre-commit, CLAUDE.md, ADRs, review subagents, skills, GH Actions scaffolding — green harness before any installer code lands.
- [ ] **Phase 2: Installer Foundation + Agent User** - One-command installer creates a correctly-provisioned `agent` user with belt-and-braces PATH for every invocation mode (interactive shell, non-interactive SSH, cron, systemd, sudo -u); Docker bats matrix green on PR.
- [ ] **Phase 3: Node.js Runtime + Per-User npm Prefix** - NodeSource Node.js 22 LTS + agent's npm global prefix under home; `npm install -g` works without sudo from the agent user in every invocation mode (smoke-tested with a throwaway package).
- [ ] **Phase 4: Registry CLI + Catalog + Uninstall** - `agentlinux list/install/remove` ships; catalog with claude-code, gsd, playwright entries is *available* (none installed by default); JSON Schema validates entries; clean uninstall path.
- [ ] **Phase 5: Agent Installability** - Each of claude-code, gsd, playwright is installable via `agentlinux install <name>` and runs correctly for the agent user across all invocation modes. AGT-02 (Claude Code self-updates without sudo/EACCES) is the canonical acceptance test.
- [ ] **Phase 6: Distribution + Release Pipeline** - SHA256-verified curl-pipe-bash installer, optional `.deb` via fpm, GitHub Releases workflow, QEMU nightly + release-gate suite wired as mandatory, AGT-02 release gate enforced. Ship v0.3.0.

## Phase Details

### Phase 1: Harness Setup
**Goal**: A green development harness is in place so every subsequent phase can ship implementation with its behavior-contract tests enforced by CI and review automation.
**Depends on**: Nothing (first phase)
**Requirements**: HRN-01, HRN-02, HRN-03, HRN-04, HRN-05, HRN-06, HRN-07, HRN-08, HRN-09, TST-06, TST-07
**Success Criteria** (what must be TRUE):
  1. A contributor cloning the repo can run `pre-commit run --all-files` and it passes (shellcheck, shfmt, biome, catalog-schema validation) — HRN-01, HRN-02.
  2. A contributor opening any Claude Code session sees the project-scoped CLAUDE.md under 150 lines at the repo root and can navigate to ADR-001..ADR-010 in `docs/decisions/` — HRN-03, HRN-04.
  3. Research outputs and review skill files are findable under `docs/research/v0.2.0/`, `docs/research/v0.3.0/`, and `.claude/skills/review/` — HRN-05, HRN-07.
  4. Running `/review` on a throwaway change spawns the six project-scoped review subagents (bash-engineer, node-engineer, security-engineer, qa-engineer, behavior-coverage-auditor, catalog-auditor) and returns feedback — HRN-06, HRN-07, TST-07.
  5. The four GitHub Actions workflows (`test.yml`, `nightly-qemu.yml`, `nightly-mutation.yml`, `release.yml`) exist and pass on an empty-plugin commit; mutation harness scaffolding (stryker for Node, bash-mutator.sh for bash) runs nightly and reports scores without blocking merge — HRN-08, TST-06.
  6. The four project-scoped skill skeletons (`agentlinux-installer`, `behavior-test-contract`, `catalog-schema`, `qemu-harness`) exist and are loadable — HRN-09.
**Plans**: 5 plans
- [ ] 01-01-PLAN.md — Project skeleton + CLAUDE.md + ADRs + research migration (HRN-01, HRN-03, HRN-04, HRN-05)
- [ ] 01-02-PLAN.md — Pre-commit + four GH Actions workflows + mutation scaffolding (HRN-02, HRN-08, TST-06)
- [ ] 01-03-PLAN.md — Six review subagents + /review skill (HRN-06, HRN-07, TST-07)
- [ ] 01-04-PLAN.md — Four project-scoped skill skeletons (HRN-09)
- [ ] 01-05-PLAN.md — Harness meta-test suite (closes Phase 1 acceptance gate)

### Phase 2: Installer Foundation + Agent User
**Goal**: Running the installer on a clean Ubuntu 22.04 or 24.04 produces an `agent` user who can run commands — with all six BHV invocation modes working and zero EACCES / permission-denied output — even though no agents are installed yet.
**Depends on**: Phase 1
**Requirements**: INST-01, INST-02, INST-05, BHV-01, BHV-02, BHV-03, BHV-04, BHV-05, BHV-06, DOC-02, TST-01, TST-02, TST-04
**Success Criteria** (what must be TRUE):
  1. Running the installer on a fresh Ubuntu 22.04 or 24.04 Docker image completes with a single command, no interactive prompts, exit 0 — INST-01.
  2. Re-running the installer on the same system converges (no duplicate PATH lines, no sudoers breakage, no error on pre-existing `agent` user) — INST-02.
  3. An observer who `grep -E 'EACCES|permission denied'` on the entire installer transcript finds zero hits — INST-05.
  4. The `agent` user can run a trivial command (e.g. `echo ok`) across all six invocation modes — interactive bash login shell, non-interactive SSH, cron, systemd `User=agent`, `sudo -u agent`, and `sudo -u agent -i` — with the correct PATH, UTF-8 locale, and bash shell each time — BHV-01..BHV-06.
  5. `/home/agent/CLAUDE.md` exists after install and instructs agent tooling against creating shim/wrapper workarounds — DOC-02.
  6. The Docker bats matrix (Ubuntu 22.04 + 24.04) runs on every PR, covers every INST-XX and BHV-XX requirement with at least one test, and failure output identifies which requirement failed, what was expected, what was observed, and where the logs live — TST-01 (partial), TST-02, TST-04.
**Plans**: TBD

### Phase 3: Node.js Runtime + Per-User npm Prefix
**Goal**: After this phase the agent user has a working Node.js LTS and a writable `npm install -g` path under their own home — proving the keystone ownership decision before any agent is installed on top.
**Depends on**: Phase 2
**Requirements**: RT-01, RT-02, RT-03, RT-04
**Success Criteria** (what must be TRUE):
  1. Running `node --version` as the agent user returns an LTS version number both in an interactive shell and in every non-interactive invocation mode (cron, systemd, sudo -u, non-interactive SSH) — RT-01.
  2. The agent user can `npm install -g cowsay` (or any throwaway npm package — *not* a catalog agent, since the "agents opt in only" rule still applies), have the resulting binary on PATH in every invocation mode, without sudo, without EACCES, and without any shim/wrapper workaround — RT-02.
  3. The agent user can `npm uninstall -g cowsay` and the binary disappears from PATH with no leftover files — RT-03.
  4. `npm config get prefix` for the agent user returns a path under the agent user's home — never `/usr`, `/usr/local`, or any root-owned path — RT-04.
  5. The Docker bats matrix from Phase 2 is extended to cover RT-01..RT-04 (one test per requirement minimum) and stays green on PR.
**Plans**: TBD

### Phase 4: Registry CLI + Catalog + Uninstall
**Goal**: The `agentlinux` CLI is on the agent's PATH and can list / install / remove entries from a JSON-Schema-validated catalog that contains claude-code, gsd, and playwright *as available* (none installed). A symmetric uninstall path removes what the installer placed.
**Depends on**: Phase 3
**Requirements**: CLI-01, CLI-02, CLI-03, CLI-04, CLI-05, CAT-01, CAT-02, CAT-03, INST-04
**Success Criteria** (what must be TRUE):
  1. `agentlinux --version` works as the agent user with no sudo and no path fiddling, in every invocation mode — CLI-01, CLI-05.
  2. `agentlinux list` shows claude-code, gsd, and playwright with a "not installed" indicator on a fresh system — CLI-02, CAT-01, CAT-02.
  3. A new catalog entry can be added by submitting only a JSON catalog entry plus a per-agent install recipe (no edits to the CLI source); `agentlinux list` validates every entry against the published JSON Schema and refuses malformed entries — CAT-03.
  4. Running `agentlinux remove` on an entry that was installed cleans up the binary and any config additions the install placed; running the installer's `--purge` uninstall path removes the agent user's home, Node.js binaries owned by the install, sudoers drop-ins, and all installer-placed files — CLI-04, INST-04.
  5. The Docker bats matrix is extended to cover CLI-01..CLI-05, CAT-01..CAT-03, and INST-04 end-to-end (including "install + remove + install again is idempotent") and stays green on PR.
**Plans**: TBD

### Phase 5: Agent Installability
**Goal**: Each of the three catalog agents can be installed via `agentlinux install <name>` and runs correctly for the agent user across all six BHV invocation modes — and AGT-02 (Claude Code self-updates without sudo/EACCES) passes as the canonical acceptance test.
**Depends on**: Phase 4
**Requirements**: AGT-01, AGT-02, AGT-03, AGT-04, AGT-05
**Success Criteria** (what must be TRUE):
  1. After `agentlinux install claude-code`, the agent user can run `claude --version` successfully from an interactive shell, non-interactive SSH, cron, systemd `User=agent`, and `sudo -u agent` — AGT-01.
  2. **Canonical acceptance test (release gate):** After `agentlinux install claude-code`, the agent user can self-update Claude Code to a newer version (or dry-run-equivalent) without sudo, without any line containing `EACCES` or `permission denied` on stdout or stderr, and without manual intervention — AGT-02.
  3. `claude doctor` (or equivalent diagnostic) reports a clean state for the agent user after install — AGT-03.
  4. After `agentlinux install gsd`, the agent user can run `gsd --version` (or equivalent) successfully — AGT-04.
  5. After `agentlinux install playwright`, the agent user can run `npx playwright --version` and `npx playwright install` downloads browsers into the agent user's cache with no sudo and no EACCES — AGT-05.
  6. The Docker bats matrix is extended with AGT-01..AGT-05 tests; the AGT-02 test is explicitly tagged as the release-gate acceptance test so Phase 6 can enforce it in CI.
**Plans**: TBD

### Phase 6: Distribution + Release Pipeline
**Goal**: A tagged release produces a SHA256-verified curl-pipe-bash installer (and optional `.deb`), the QEMU release-gate suite must be green before the release workflow publishes, AGT-02 is a hard blocker for any release, and a user-facing README tells people how to install, verify, and uninstall.
**Depends on**: Phase 5
**Requirements**: INST-03, TST-03, TST-05, DOC-01
**Success Criteria** (what must be TRUE):
  1. A user on a fresh Ubuntu 22.04 or 24.04 cloud image can run a single `curl -fsSL ... | bash` command published on agentlinux.org, and the installer verifies the release tarball's SHA256 before executing it — INST-03.
  2. Every tagged release is gated on a green QEMU suite against a fresh Ubuntu cloud image; a red QEMU run blocks the release workflow — TST-03.
  3. The release workflow refuses to publish a tag if the AGT-02 acceptance test (agent user self-updates Claude Code without sudo/EACCES) is not green in both the Docker matrix and the QEMU release-gate run — TST-05.
  4. A user can find a README shipping with the installer that tells them exactly how to install (one command), how to verify the install (`agentlinux list` + one agent-invocation command), and how to uninstall (`agentlinux` uninstall entrypoint + `--purge` semantics) — DOC-01.
  5. Tagging `v0.3.0` produces a GitHub Release with the release tarball, its `.sha256` sibling, and (optionally) a `.deb` built via fpm, with the curl-installer pointing at that release.
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Harness Setup | 0/5 | Not started | - |
| 2. Installer Foundation + Agent User | 0/TBD | Not started | - |
| 3. Node.js Runtime + Per-User npm Prefix | 0/TBD | Not started | - |
| 4. Registry CLI + Catalog + Uninstall | 0/TBD | Not started | - |
| 5. Agent Installability | 0/TBD | Not started | - |
| 6. Distribution + Release Pipeline | 0/TBD | Not started | - |

## Coverage Summary

**Total v0.3.0 requirements:** 46 (9 HRN + 5 INST + 6 BHV + 4 RT + 5 AGT + 5 CLI + 3 CAT + 7 TST + 2 DOC)
**Mapped:** 46 / 46
**Orphaned:** 0

Requirement allocation per phase:

| Phase | Requirements | Count |
|-------|--------------|-------|
| 1 Harness Setup | HRN-01..HRN-09, TST-06, TST-07 | 11 |
| 2 Installer Foundation + Agent User | INST-01, INST-02, INST-05, BHV-01..BHV-06, DOC-02, TST-01, TST-02, TST-04 | 13 |
| 3 Node.js Runtime + Per-User npm Prefix | RT-01..RT-04 | 4 |
| 4 Registry CLI + Catalog + Uninstall | CLI-01..CLI-05, CAT-01..CAT-03, INST-04 | 9 |
| 5 Agent Installability | AGT-01..AGT-05 | 5 |
| 6 Distribution + Release Pipeline | INST-03, TST-03, TST-05, DOC-01 | 4 |
| **Total** | | **46** |

**Notes on TST-XX placement:**
- TST-01 (full behavior-test suite coverage) is introduced in Phase 2 and *grows with each phase* — every phase from 2 onward must add its own bats coverage before the phase closes (enforced by the behavior-coverage-auditor from HRN-06, running at end of every phase per TST-07).
- TST-02 (Docker matrix on every PR) lands in Phase 2 when the first bats tests ship.
- TST-03 (QEMU nightly + release-gate) lands in Phase 6 where the release pipeline wires it in.
- TST-04 (clear diagnostic output) is a helper-library / bats-convention requirement satisfied in Phase 2 and reused by later phases.
- TST-05 (AGT-02 as blocking release gate) is enforced in Phase 6's release workflow; the test itself is authored in Phase 5 (where AGT-02 lives).
- TST-06 (nightly mutation testing, advisory) is scaffolded in Phase 1 via HRN-08's `nightly-mutation.yml` workflow. Promotion to release gate is a v0.4 decision — explicitly not a v0.3.0 release blocker.
- TST-07 (behavior-coverage-auditor runs at end of every phase) is operationalized in Phase 1 when the auditor subagent is created (HRN-06); it becomes the gating check at every subsequent phase transition.
