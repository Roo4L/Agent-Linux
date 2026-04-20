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

- [x] **Phase 1: Harness Setup** - Project skeleton, pre-commit, CLAUDE.md, ADRs, review subagents, skills, GH Actions scaffolding — green harness before any installer code lands. ✓ 2026-04-18 (5 plans; `bash tests/harness/run.sh` green: 104/104 @tests pass)
- [x] **Phase 2: Installer Foundation + Agent User** - One-command installer creates a correctly-provisioned `agent` user with belt-and-braces PATH for every invocation mode (interactive shell, non-interactive SSH, cron, systemd, sudo -u); Docker bats matrix green on PR. ✓ 2026-04-18 (5 plans; 22/22 bats green on both Ubuntu 22.04 + 24.04; TST-07 gate: GREEN; one known architectural gap deferred to v0.4+ — sudo non-login + secure_path needs PAM/sudoers work out of Phase 2 scope)
- [x] **Phase 3: Node.js Runtime + Per-User npm Prefix** - NodeSource Node.js 22 LTS + agent's npm global prefix under home; `npm install -g` works without sudo from the agent user in every invocation mode (smoke-tested with cowsay@1.6.0). ✓ 2026-04-18 (2 plans; 27/27 bats green on both Ubuntu 22.04 + 24.04; RT-01..04 all satisfied with observable six-mode proof; TST-07 gate: GREEN; INST-02 idempotency extended to cover Phase 3 artefacts)
- [x] **Phase 4: Registry CLI + Catalog + Uninstall** - `agentlinux list/install/remove/upgrade/pin` ships; catalog with claude-code, gsd, playwright entries is *available* (none installed by default); JSON Schema validates entries; clean uninstall path. ✓ 2026-04-19 (7 plans; 49/49 bats green on Ubuntu 22.04 + 24.04; TST-07 gate: GREEN; all 12 Phase 4 requirements — CLI-01..07, CAT-01..04, INST-04 — have ≥1 bats @test each; INST-02 extended with 4 Phase-4 artefacts via LOCKED deterministic strategy)
- [x] **Phase 5.1 (INSERTED): Agent User Sudo Drop-In** - `/etc/sudoers.d/agentlinux` grants passwordless sudo to agent user (scope: ALL per ADR-012, overriding Phase 2's zero-sudo lock). Prerequisite for Phase 5 agent recipes needing apt/systemctl/etc. ✓ 2026-04-19 (1 plan; 56/56 bats green on Ubuntu 22.04 + 24.04, +7 sudo @tests vs. Phase 4 baseline; TST-07 gate: GREEN — INST-06 + BHV-07 both have ≥1 bats @test citing the ID; visudo-gated atomic 0440 drop-in with sha256 byte-stable re-run verified)
- [x] **Phase 5: Agent Installability** - Each of claude-code, gsd, playwright is installable via `agentlinux install <name>` and runs correctly for the agent user across all invocation modes. AGT-02 (Claude Code self-updates without sudo/EACCES) is the canonical acceptance test. ✓ 2026-04-19 (4 plans; 66/66 bats green on Ubuntu 22.04 + 24.04, +10 AGT-XX @tests vs. Phase 5.1 baseline; TST-07 gate: GREEN — all 6 Phase 5 requirements (AGT-01, AGT-02, AGT-02b, AGT-03, AGT-04, AGT-05) have ≥1 bats @test citing the ID; three real agent recipes (claude-code native installer, get-shit-done-cc via npm, playwright + chromium via ADR-012 sudo) all ship; AGT-02 canonical acceptance test runs live `claude update` against Anthropic CDN with zero EACCES)
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
- [x] 01-01-PLAN.md — Project skeleton + CLAUDE.md + ADRs + research migration (HRN-01 partial, HRN-03, HRN-04, HRN-05) ✓ 2026-04-18
- [x] 01-02-PLAN.md — Pre-commit + four GH Actions workflows + mutation scaffolding (HRN-02, HRN-08, TST-06) ✓ 2026-04-18
- [x] 01-03-PLAN.md — Six review subagents + /review skill (HRN-06, HRN-07, TST-07) ✓ 2026-04-18
- [x] 01-04-PLAN.md — Four project-scoped skill skeletons (HRN-09) ✓ 2026-04-18
- [x] 01-05-PLAN.md — Harness meta-test suite (closes Phase 1 acceptance gate) (HRN-01 verified, HRN-02..09 verified, TST-06 verified, TST-07 scaffold-verified) ✓ 2026-04-18

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
**Plans**: 5 plans
- [x] 02-01-PLAN.md — Bash library primitives: log.sh, idempotency.sh, as_user.sh, distro_detect.sh (INST-01, INST-02, INST-05) ✓ 2026-04-18
- [x] 02-02-PLAN.md — Installer entrypoint rewrite: root check, log tee, ERR trap, arg parsing, provisioner dispatch (INST-01, INST-02, INST-05) ✓ 2026-04-18
- [x] 02-03-PLAN.md — Agent-user provisioner: ensure_user agent, locale enforcement, DOC-02 CLAUDE.md placement (BHV-01, DOC-02) ✓ 2026-04-18
- [x] 02-04-PLAN.md — PATH wiring provisioner: four-file six-mode matrix (profile.d, ~agent/.bashrc, agentlinux.env, cron.d) (BHV-02, BHV-03, BHV-04, BHV-05, BHV-06) ✓ 2026-04-18
- [x] 02-05-PLAN.md — Docker bats harness + bats helpers + INST/BHV/DOC test suite + CI matrix wire-up (INST-01, INST-02, INST-05, BHV-01..06, DOC-02, TST-01 partial, TST-02, TST-04) ✓ 2026-04-18

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
**Plans**: 2 plans
- [x] 03-01-PLAN.md — Provisioner: 30-nodejs.sh (NodeSource Node 22 LTS + per-user npm prefix) + 40-path-wiring.sh extension (.npm-global/bin prepend + NPM_CONFIG_PREFIX) (RT-01, RT-04) ✓ 2026-04-18 (4 commits: 74366a0, 1fe6a75, c6d9b41, 3dbfcff; 22/22 bats green on Ubuntu 22.04 + 24.04; Node v22.22.2 installed end-to-end)
- [x] 03-02-PLAN.md — Behavior tests: tests/bats/30-runtime.bats (RT-01..04 across six INVOKE_MODES) + assert_user_prefix_in_home helper + INST-02 sha256 set extension (RT-01, RT-02, RT-03, RT-04) ✓ 2026-04-18 (4 commits: 03fda88, c4c9fbf, fc78911, 2d6fdb9; 27/27 bats green on Ubuntu 22.04 + 24.04 — +5 vs Phase 2 baseline; TST-07 phase-close gate GREEN)

### Phase 4: Registry CLI + Catalog + Uninstall
**Goal**: The `agentlinux` CLI is on the agent's PATH and can list / install / remove entries from a JSON-Schema-validated catalog that contains claude-code, gsd, and playwright *as available* (none installed), at specific `pinned_version` values curated and CI-tested by AgentLinux. Users can `agentlinux upgrade` to reconcile installed versions against the release's curated set (per-agent 3-way diff: keep-override / accept-curated / accept-upstream-latest) and `agentlinux pin` to set sticky overrides. A symmetric uninstall path removes what the installer placed. Stability-first per ADR-011.
**Depends on**: Phase 3
**Requirements**: CLI-01, CLI-02, CLI-03, CLI-04, CLI-05, CLI-06, CLI-07, CAT-01, CAT-02, CAT-03, CAT-04, INST-04
**Success Criteria** (what must be TRUE):
  1. `agentlinux --version` works as the agent user with no sudo and no path fiddling, in every invocation mode — CLI-01, CLI-05.
  2. `agentlinux list` shows claude-code, gsd, and playwright with a "not installed" indicator on a fresh system, and shows `pinned_version` per entry — CLI-02, CAT-01, CAT-02, CAT-04.
  3. A new catalog entry can be added by submitting only a JSON catalog entry (with `pinned_version`) plus a per-agent install recipe (no edits to the CLI source); `agentlinux list` validates every entry against the published JSON Schema and refuses malformed entries — CAT-03, CAT-04.
  4. `agentlinux install <name>` installs exactly `pinned_version` (e.g. `sudo -u agent -H npm install -g <pkg>@<pinned_version>`), writes a sentinel at `/opt/agentlinux/state/installed.json` recording `{version, source}`, and is idempotent — CLI-03, CAT-04.
  5. `agentlinux upgrade` detects per-agent divergence (`synced` / `override-ahead` / `override-behind`) between the installed version, the current release's curated pin, and upstream latest; offers 3-way reconcile per agent or bulk flags (`--reset-all-curated` / `--respect-overrides` / `--all-latest`) — CLI-06.
  6. `agentlinux pin <name>=<curated|latest|x.y.z>` sets sticky-override semantics; a user who ran ahead via `claude update` is not re-nagged every release until `pin <name>=curated` clears the flag — CLI-07.
  7. Running `agentlinux remove` on an entry that was installed cleans up the binary, sentinel, and any config additions the install placed; running the installer's `--purge` uninstall path removes the agent user's home, Node.js binaries owned by the install, sudoers drop-ins, and all installer-placed files — CLI-04, INST-04.
  8. The Docker bats matrix is extended to cover CLI-01..CLI-07, CAT-01..CAT-04, and INST-04 end-to-end (including "install + remove + install again is idempotent" and "upgrade detects divergence correctly") and stays green on PR.
**Plans**: 7 plans (grew from 5 with ADR-011 additions: `upgrade` verb + `pin` verb)
- [x] 04-01-PLAN.md — CLI scaffold + ajv catalog validator + interface surface + Commander bootstrap (CLI-01 scaffold, CAT-03, CAT-04) ✓ 2026-04-19
- [x] 04-02-PLAN.md — catalog.json (4 entries) + install.sh/uninstall.sh recipes (CAT-01, CAT-02, CAT-03) ✓ 2026-04-19
- [x] 04-03-PLAN.md — list/install/remove commands + shared runner.ts dispatcher (CLI-02, CLI-03, CLI-04, CLI-05) ✓ 2026-04-19
- [x] 04-04-PLAN.md — upgrade verb with divergence classifier + npm ls/view (CLI-06) ✓ 2026-04-19 (2 commits: 01cbfff divergence+npm_ls+types+26 tests, 897c4e3 upgrade orchestrator+12 tests; 92/92 tests green; CLI-06 TypeScript-side complete; bats enforcement lands Plan 04-07)
- [x] 04-05-PLAN.md — pin verb with sticky-override semantics (CLI-07) ✓ 2026-04-19 (2 commits: b6b8932 RED test — parsePinSpec + pinCmd + integration sanity, 55c55dc GREEN feat — pin.ts stub replaced with full impl; 112/112 tests green up from 92, +20 new pin tests; CLI-07 TypeScript-side complete; bats enforcement lands Plan 04-07)
- [x] 04-06-PLAN.md — 50-registry-cli.sh provisioner + --purge 7-step teardown + Docker builder stage (CLI-01 PATH, INST-04) ✓ 2026-04-19 (4 commits: 34dc39a feat provisioner, b6a6be9 feat --purge teardown, f4d76bb fix as_user caller shape + CLI bundle trio staging (Rule 1 + Rule 2 auto-fixes), 5fd4677 feat Dockerfiles multi-stage node:22-slim builder + run.sh splice; Docker smoke green on Ubuntu 22.04 + 24.04: 27/27 bats per image + agentlinux --version=0.3.0 as agent user + agentlinux list prints 3-agent table; CLI-01 + INST-04 ✓ COMPLETE installer-side; bats enforcement lands Plan 04-07)
- [x] 04-07-PLAN.md — bats integration tests + INST-02 extension + TST-07 phase-close audit (CLI-01..07, CAT-01..04, INST-04) ✓ 2026-04-19 (4 commits: 2e7dcc1 Rule-3 jq in Docker images, aec64ac Rule-1 trio — schema.ts resolver default candidate + dispatcher.ts invoker-equals-target short-circuit + index.ts enablePositionalOptions; f64f3c4 Task 1 tests/bats/40-registry-cli.bats 22 @tests, 1a538f0 Task 2 INST-02 extension with 4 LOCKED Phase-4 artefacts; 49/49 bats green on both Ubuntu 22.04 + 24.04; harness 104/104; unit tests 112/112; TST-07 gate: GREEN — every Phase 4 req ID has ≥1 @test citing it; Phase 4 acceptance gate closed)

### Phase 5.1 (INSERTED): Agent User Sudo Drop-In
**Goal**: The agent user has passwordless sudo via `/etc/sudoers.d/agentlinux` (scope: ALL commands, per ADR-012). Prerequisite for Phase 5 agent recipes (Playwright's `install-deps` calls `apt install`; real coding agents frequently need package-management and service-management root privileges). Supersedes the Phase 2 "zero sudo for agent user" CONTEXT lock.
**Inserted**: 2026-04-19 (during Phase 5 smart-discuss; user chose scope "C — full sudo" over narrower allowlists).
**Depends on**: Phase 4
**Requirements**: INST-06, BHV-07
**Success Criteria** (what must be TRUE):
  1. After a fresh install, `/etc/sudoers.d/agentlinux` exists with mode `0440`, owner `root:root`, and contains exactly `agent ALL=(ALL) NOPASSWD: ALL` — BHV-07.
  2. `sudo -u agent sudo -n true` exit 0 — the agent user has passwordless sudo — INST-06.
  3. `visudo -cf /etc/sudoers.d/agentlinux` exit 0 — the drop-in passes syntax validation.
  4. Re-running the installer produces a byte-identical drop-in (idempotent) — INST-02 extended.
  5. `agentlinux-install --purge` removes the drop-in symmetrically (INST-04 extended verification).
**Plans**: 1 plan
- [x] 05.1-01-PLAN.md — Sudoers drop-in provisioner (`plugin/provisioner/20-sudoers.sh`) + bats coverage (`tests/bats/22-agent-sudo.bats`) closing INST-06 + BHV-07 per ADR-012 ✓ 2026-04-19 (2 commits: 9d4ea32 feat provisioner, edae58a test bats; ~12 min; visudo -cf gated + atomic 0440 install + RETURN-trap tmpfile cleanup; 7 @tests — 4 BHV-07 file-integrity, 2 INST-06 functional, 1 BHV-07 idempotency; TST-07 gate: GREEN)

### Phase 5: Agent Installability
**Goal**: Each of the three catalog agents can be installed via `agentlinux install <name>` and runs correctly for the agent user across all six BHV invocation modes — and AGT-02 (Claude Code self-updates without sudo/EACCES) passes as the canonical acceptance test. AGT-02b verifies the stability-first pin mechanism produces exactly `pinned_version` on disk.
**Depends on**: Phase 5.1 (agent user has sudo for Playwright install-deps + future agent workflows)
**Requirements**: AGT-01, AGT-02, AGT-02b, AGT-03, AGT-04, AGT-05
**Success Criteria** (what must be TRUE):
  1. After `agentlinux install claude-code`, the agent user can run `claude --version` successfully from an interactive shell, non-interactive SSH, cron, systemd `User=agent`, and `sudo -u agent` — AGT-01.
  2. **Canonical acceptance test (release gate):** After `agentlinux install claude-code`, the agent user can self-update Claude Code to a newer version (or dry-run-equivalent) without sudo, without any line containing `EACCES` or `permission denied` on stdout or stderr, and without manual intervention — AGT-02. (Permission invariant, version-agnostic.)
  3. **Version-lock acceptance test:** After `agentlinux install claude-code`, `claude --version` returns exactly the catalog's `pinned_version` — verifying the stability-first mechanism from ADR-011 works end-to-end — AGT-02b.
  4. `claude doctor` (or equivalent diagnostic) reports a clean state for the agent user after install — AGT-03.
  5. After `agentlinux install gsd`, the agent user can run `gsd --version` (or equivalent) successfully — AGT-04.
  6. After `agentlinux install playwright`, the agent user can run `npx playwright --version` and `npx playwright install` downloads browsers into the agent user's cache with no sudo and no EACCES — AGT-05.
  7. The Docker bats matrix is extended with AGT-01..AGT-05 + AGT-02b tests; the AGT-02 test is explicitly tagged as the release-gate acceptance test so Phase 6 can enforce it in CI.
**Plans**: 4 plans
- [x] 05-01-PLAN.md — Real claude-code install.sh + uninstall.sh (native installer + PIPESTATUS + AGT-02b in-recipe assert) + tests/bats/51-agt02-release-gate.bats (AGT-02 release-gate) (AGT-02, AGT-02b ✓; AGT-01 + AGT-03 bats enforcement lands in 05-04) — ✓ Complete 2026-04-19
- [x] 05-02-PLAN.md — Real gsd install.sh + uninstall.sh (npm install -g get-shit-done-cc@$PINNED + banner-grep version-lock) (AGT-04 recipe body ✓; AGT-04 bats enforcement lands in 05-04) — ✓ Complete 2026-04-19
- [x] 05-03-PLAN.md — Real playwright install.sh + uninstall.sh (npm install -g playwright + npx playwright install --with-deps chromium via ADR-012 NOPASSWD sudo + chromium cache verify) (AGT-05 recipe body ✓; AGT-05 bats enforcement lands in 05-04) — ✓ Complete 2026-04-19
- [x] 05-04-PLAN.md — tests/bats/50-agents.bats (AGT-01 × 3 six-mode + AGT-02b + AGT-03 + AGT-04 + AGT-05 × 3) + TST-07 phase-close behavior-coverage-auditor gate (AGT-01..05, AGT-02b ✓; Docker 66/66 on both Ubuntu versions; TST-07 gate GREEN) — ✓ Complete 2026-04-19

### Phase 6: Distribution + Release Pipeline
**Goal**: A tagged release produces a SHA256-verified curl-pipe-bash installer (and optional `.deb`), the QEMU release-gate suite must be green before the release workflow publishes, AGT-02 is a hard blocker for any release, a user-facing README tells people how to install, verify, and uninstall, and the release artifact includes a catalog snapshot that CI validates end-to-end (pinned combo test per TST-08) before tagging — per ADR-011.
**Depends on**: Phase 5
**Requirements**: INST-03, TST-03, TST-05, TST-08, CAT-05, DOC-01
**Success Criteria** (what must be TRUE):
  1. A user on a fresh Ubuntu 22.04 or 24.04 cloud image can run a single `curl -fsSL ... | bash` command published on agentlinux.org, and the installer verifies the release tarball's SHA256 before executing it — INST-03.
  2. Every tagged release is gated on a green QEMU suite against a fresh Ubuntu cloud image; a red QEMU run blocks the release workflow — TST-03.
  3. The release workflow refuses to publish a tag if the AGT-02 acceptance test (agent user self-updates Claude Code without sudo/EACCES) is not green in both the Docker matrix and the QEMU release-gate run — TST-05.
  4. **Pinned-combo gate:** The release workflow installs the pinned catalog combo (every catalog agent at its `pinned_version`) and runs the full bats suite against it before tagging; a red run blocks the release — TST-08. The workflow also publishes `catalog-<version>.json` as a sibling of the release tarball + `.sha256` — CAT-05.
  5. A user can find a README shipping with the installer that tells them exactly how to install (one command), how to verify the install (`agentlinux list` + one agent-invocation command), and how to uninstall (`agentlinux` uninstall entrypoint + `--purge` semantics) — DOC-01.
  6. Tagging `v0.3.0` produces a GitHub Release with the release tarball, its `.sha256` sibling, the catalog snapshot `catalog-v0.3.0.json` (per CAT-05), and (optionally) a `.deb` built via fpm, with the curl-installer pointing at that release.
**Plans**: 5 plans
- [x] 06-01-PLAN.md — scripts/build-release.sh reproducible tarball + SHA256 + catalog snapshot + optional .deb (INST-03, CAT-05)
- [x] 06-02-PLAN.md — packaging/curl-installer/install.sh hardened curl-pipe-bash + tests/bats/60-curl-installer.bats (INST-03)
- [x] 06-03-PLAN.md — tests/qemu/boot.sh + cloud-init templates + nightly-qemu.yml matrix (TST-03)
- [x] 06-04-PLAN.md — release.yml 4-gate pipeline + deploy.yml install.sh staging (TST-05, TST-08, INST-03, CAT-05)
- [ ] 06-05-PLAN.md — README.md + docs/STABILITY-MODEL.md + TST-07 phase-close behavior-coverage-auditor (DOC-01)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Harness Setup | 5/5 | ✓ Complete | 2026-04-18 |
| 2. Installer Foundation + Agent User | 5/5 | ✓ Complete | 2026-04-18 |
| 3. Node.js Runtime + Per-User npm Prefix | 2/2 | ✓ Complete | 2026-04-18 |
| 4. Registry CLI + Catalog + Uninstall | 7/7 | ✓ Complete | 2026-04-19 |
| 5.1 (INSERTED). Agent User Sudo Drop-In | 1/1 | ✓ Complete | 2026-04-19 |
| 5. Agent Installability | 4/4 | ✓ Complete | 2026-04-19 (all 4 plans complete; TST-07 gate: GREEN; 66/66 bats green on Ubuntu 22.04 + 24.04) |
| 6. Distribution + Release Pipeline | 4/5 | In progress | - |

## Coverage Summary

**Total v0.3.0 requirements:** 54 (9 HRN + 6 INST + 7 BHV + 4 RT + 6 AGT + 7 CLI + 5 CAT + 8 TST + 2 DOC) — grew from 52 with ADR-012 additions (INST-06, BHV-07) on 2026-04-19
**Mapped:** 54 / 54
**Orphaned:** 0

Requirement allocation per phase:

| Phase | Requirements | Count |
|-------|--------------|-------|
| 1 Harness Setup | HRN-01..HRN-09, TST-06, TST-07 | 11 |
| 2 Installer Foundation + Agent User | INST-01, INST-02, INST-05, BHV-01..BHV-06, DOC-02, TST-01, TST-02, TST-04 | 13 |
| 3 Node.js Runtime + Per-User npm Prefix | RT-01..RT-04 | 4 |
| 4 Registry CLI + Catalog + Uninstall | CLI-01..CLI-07, CAT-01..CAT-04, INST-04 | 12 |
| 5.1 (INSERTED) Agent User Sudo Drop-In | INST-06, BHV-07 | 2 |
| 5 Agent Installability | AGT-01, AGT-02, AGT-02b, AGT-03..AGT-05 | 6 |
| 6 Distribution + Release Pipeline | INST-03, TST-03, TST-05, TST-08, CAT-05, DOC-01 | 6 |
| **Total** | | **54** |

**Notes on TST-XX placement:**
- TST-01 (full behavior-test suite coverage) is introduced in Phase 2 and *grows with each phase* — every phase from 2 onward must add its own bats coverage before the phase closes (enforced by the behavior-coverage-auditor from HRN-06, running at end of every phase per TST-07).
- TST-02 (Docker matrix on every PR) lands in Phase 2 when the first bats tests ship.
- TST-03 (QEMU nightly + release-gate) lands in Phase 6 where the release pipeline wires it in.
- TST-04 (clear diagnostic output) is a helper-library / bats-convention requirement satisfied in Phase 2 and reused by later phases.
- TST-05 (AGT-02 as blocking release gate) is enforced in Phase 6's release workflow; the test itself is authored in Phase 5 (where AGT-02 lives).
- TST-06 (nightly mutation testing, advisory) is scaffolded in Phase 1 via HRN-08's `nightly-mutation.yml` workflow. Promotion to release gate is a v0.4 decision — explicitly not a v0.3.0 release blocker.
- TST-07 (behavior-coverage-auditor runs at end of every phase) is operationalized in Phase 1 when the auditor subagent is created (HRN-06); it becomes the gating check at every subsequent phase transition.
- TST-08 (pinned-combo release gate per ADR-011) is enforced by Phase 6's release workflow, which installs the catalog's `pinned_version` for every entry and runs the full bats suite before tagging. Red run blocks release.
