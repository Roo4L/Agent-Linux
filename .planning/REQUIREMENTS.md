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

- [x] **INST-01**: Running the installer on a clean Ubuntu 22.04 or 24.04 system produces a working AgentLinux environment with one command, no interactive prompts, non-zero exit on failure. (Verified 02-05 bats: `INST-01: installer log file exists after initial run` + `INST-01: installer log contains success banner` — green on both Ubuntu 22.04 + 24.04 inside systemd-capable Docker images.)
- [x] **INST-02**: The installer is idempotent — re-running it converges; does not duplicate PATH lines, sudoers entries, or skel files; does not error on pre-existing agent user, pre-existing Node.js, or partial prior install. (Verified 02-05 bats: `INST-02: re-running the installer is byte-stable (idempotency)` — sha256 diff across 5 artefacts (profile.d/agentlinux.sh, agentlinux.env, cron.d/agentlinux, /home/agent/.bashrc, /home/agent/CLAUDE.md) before + after re-run produces empty diff.)
- [ ] **INST-03**: The installer is distributable via curl-pipe-bash (primary) and verifies release tarball integrity via SHA256 before execution.
- [x] **INST-04**: The installer supports uninstall that removes the agent user, home, Node.js binaries owned by the install, and any files the installer placed on the system (with a `--purge` flag for destructive home-dir removal). (Verified 04-06 Docker smoke: agentlinux-install --purge replaces Phase 2 stub with 7-step ordered idempotent teardown: per-agent uninstall.sh via as_user; rm -rf /opt/agentlinux; /etc/profile.d/agentlinux.sh + /etc/agentlinux.env + /etc/cron.d/agentlinux; NodeSource apt files; optional apt-purge nodejs gated on --remove-nodejs (default: leave Node); pkill + userdel -r agent with -rf fallback; log-file removal LAST (Pitfall 7 tee-EOF sequencing). All rm targets literal absolute paths — security-engineer T-04-16 mitigation. Bats enforcement lands Plan 04-07.)
- [x] **INST-05**: No invocation of the installer produces a line containing `EACCES` or `permission denied` on stdout or stderr. (Verified 02-05 bats: `INST-05: installer log contains no EACCES or 'permission denied' lines` — grep against /var/log/agentlinux-install.log returns 0 matches on a green run; installer entrypoint tees stdout+stderr merged to the log via `exec > >(tee -a $LOG) 2>&1` per Pitfall 6 mitigation.)
- [x] **INST-06**: After install, `sudo -u agent sudo -n true` returns exit 0 — the agent user has passwordless sudo via `/etc/sudoers.d/agentlinux` (scope: ALL commands, per ADR-012). Enables agent workflows requiring `apt install`, `systemctl restart`, etc. ✓ Plan 05.1-01 (plugin/provisioner/20-sudoers.sh installs the drop-in; verified 05.1-01 bats: 2 @tests in tests/bats/22-agent-sudo.bats — `INST-06: agent user can run 'sudo -n true' without prompt or error` via run_sudo_u, `INST-06: agent user's sudo -l lists NOPASSWD for ALL commands` asserts `(ALL) NOPASSWD: ALL` in policy output; 56/56 bats green on Ubuntu 22.04 + 24.04.)

### Agent User Behavior (BHV)

Observable behaviors of the provisioned agent user. These are the contract — tests must cover every bullet.

- [x] **BHV-01**: The agent user exists after install, has a bash shell, a real home directory, and a UTF-8 locale configured (`LANG`, `LC_ALL`). (Provisioner landed 02-03; verified end-to-end 02-05 bats: 4 @tests covering getent-passwd shell/home, /etc/default/locale LANG + LC_ALL lines, `locale -a` presence of C.utf8.)
- [x] **BHV-02**: The agent user can run commands over **non-interactive SSH** (`ssh agent@host '<cmd>'`) and all installed agent binaries (`claude`, `gsd`, etc.) are findable on PATH. (PATH contract landed 02-04 via `/home/agent/.bashrc` `agentlinux-path` marker block at TOP — precedes skel `case $- in *i*) ;; *) return;;` early-return so non-interactive bash sees PATH + locale; verified 02-05 bats: 2 @tests via `run_ssh` helper with per-container lazy-generated ed25519 keypair.)
- [x] **BHV-03**: The agent user can run commands via **cron** and all installed agent binaries are findable on PATH. (PATH contract landed 02-04 via `/etc/cron.d/agentlinux` literal `PATH=...` header; Pitfall 4 mitigation — no `$PATH` expansion; verified 02-05 bats: 1 @test via `run_cron` helper that writes a one-shot /etc/cron.d/agentlinux-test-<stamp> job, polls 70s for output.)
- [x] **BHV-04**: The agent user can run commands via **systemd `User=agent`** and all installed agent binaries are findable on PATH. (PATH contract landed 02-04 via `/etc/agentlinux.env` literal KEY=VALUE file; future units reference via `EnvironmentFile=/etc/agentlinux.env`; verified 02-05 bats: 2 @tests via `run_systemd_user` helper using `systemd-run --wait --pipe --uid=agent --property=EnvironmentFile=/etc/agentlinux.env`. Requires dbus in the image — added to both Dockerfiles in commit badd877.)
- [x] **BHV-05**: Another user can run commands as the agent user via `sudo -u agent <cmd>` (or `sudo -u agent -i <cmd>`) and all installed agent binaries are findable on PATH. (PATH contract landed 02-04; verified 02-05 bats: 3 @tests via `run_sudo_u` [bash --login -c] and `run_sudo_u_i` [sudo -u agent -H -i bash -c]. NOTE: plan-spec'd `sudo -u agent -H bash -c` [no login] does NOT work under Ubuntu's default `Defaults secure_path=...` because sudo env_reset strips PATH before bash runs AND `bash -c` non-interactive non-login does not source .bashrc; fixing this requires a sudoers drop-in which Phase 2 CONTEXT explicitly locks — DEFERRED to v0.4+ as a PAM/sudoers architectural enhancement. The login variants exercised by the two helpers cover BHV-05's observable behavior contract.)
- [x] **BHV-06**: The agent user can run commands in an interactive bash login shell and all installed agent binaries are findable on PATH. (PATH contract landed 02-04 via `/etc/profile.d/agentlinux.sh` sourced by `/etc/profile`; re-source guard `AGENTLINUX_PROFILE_SOURCED` prevents double-prepend; verified 02-05 bats: 2 @tests via `run_interactive` helper using `su - agent -c`.)
- [x] **BHV-07**: `/etc/sudoers.d/agentlinux` exists after install with mode `0440`, owner `root:root`, passes `visudo -cf` validation, and contains exactly the line `agent ALL=(ALL) NOPASSWD: ALL`. File is idempotent across installer re-runs (byte-stable). Per ADR-012. ✓ Plan 05.1-01 (plugin/provisioner/20-sudoers.sh: visudo -cf gate on tmpfile → atomic `install -m "0440" -o root -g root` → post-install visudo -cf re-verify; verified 05.1-01 bats: 5 @tests in tests/bats/22-agent-sudo.bats — existence, stat `440 root:root`, grep -Fx exact NOPASSWD line, visudo -cf clean, AND sha256 byte-stable across `bash /opt/agentlinux-src/plugin/bin/agentlinux-install` re-run — T-05.1-01..04 all mitigated.)

### Runtime + Global-Install Behavior (RT)

- [x] **RT-01**: The agent user has a Node.js LTS runtime available. Running `node --version` returns an LTS version number, both interactively and non-interactively. ✓ Plan 03-01 (Node v22.22.2 installed via NodeSource on Ubuntu 22.04 + 24.04; version gate enforces major ≥22) + ✓ Plan 03-02 (observable six-mode proof: `@test "RT-01: agent user sees node v22 LTS in every invocation mode"` in tests/bats/30-runtime.bats loops all six INVOKE_MODES asserting `node --version` starts with `v22.`; Docker 22.04 + 24.04 both pass 27/27)
- [x] **RT-02**: The agent user can run `npm install -g <some-package>` without sudo, without `EACCES`, without creating any shim/wrapper workarounds. The resulting binary is findable on PATH in every invocation mode from BHV-02..06. ✓ Plan 03-02 (two @tests in tests/bats/30-runtime.bats: `@test "RT-02: cowsay binary resolves to /home/agent/.npm-global/bin in every mode"` loops six modes asserting `command -v cowsay` resolves under the agent-owned prefix AND `cowsay hi` runs + echoes "hi"; `@test "RT-02: no EACCES during cowsay re-install (INST-05 under npm pressure)"` re-installs and asserts assert_no_eacces — VALIDATION task 03-02-05 satisfied. cowsay pinned @1.6.0 for reproducibility. setup_file install via `sudo -u agent -H bash --login -c 'npm install -g cowsay@1.6.0'` — agent-user invocation, never bare sudo npm. Docker 22.04 + 24.04 both pass.)
- [x] **RT-03**: The agent user can run `npm uninstall -g <some-package>` cleanly (no leftover files, binary disappears from PATH). ✓ Plan 03-02 (`@test "RT-03: npm uninstall -g cowsay leaves no trace"` in tests/bats/30-runtime.bats asserts BOTH `/home/agent/.npm-global/bin/cowsay` AND `/home/agent/.npm-global/bin/cowthink` absent — Pitfall 9: cowsay@1.6.0 ships TWO bin entries — AND `/home/agent/.npm-global/lib/node_modules/cowsay` directory absent; then loops six modes asserting `command -v cowsay` resolves to NOT-FOUND. Strongest form of cleanliness contract. Docker 22.04 + 24.04 both pass.)
- [x] **RT-04**: `npm config get prefix` for the agent user returns a path under the agent user's home directory (or equivalent user-writable path) — never `/usr`, `/usr/local`, or any root-owned path. ✓ Plan 03-01 (~agent/.npmrc written with `prefix=/home/agent/.npm-global`; NPM_CONFIG_PREFIX=/home/agent/.npm-global belt-and-braces in /etc/agentlinux.env; /home/agent/.npm-global{,/bin,/lib} agent-owned 0755) + ✓ Plan 03-02 (observable six-mode proof: `@test "RT-04: npm config get prefix is under /home/agent in every invocation mode"` loops six modes with new `assert_user_prefix_in_home` helper — case-matches `/home/agent/*` with trailing slash to prevent /home/agent-staging false positive; TST-04 4-line diagnostic on fail. T-03-07 mitigation. Docker 22.04 + 24.04 both pass.)

### Agent-Tool Behavior (AGT)

Behaviors of installed agent tools. Each behavior is tested once with Claude Code as the canonical example; equivalent tests apply to any catalog tool.

- [x] **AGT-01**: After `agentlinux install claude-code`, the agent user can run `claude --version` successfully (from interactive shell, non-interactive SSH, cron, systemd, and `sudo -u agent`). (Verified 05-04 Docker smoke on Ubuntu 22.04 + 24.04: 3 @tests in tests/bats/50-agents.bats loop `${INVOKE_MODES[@]}` (interactive, ssh, cron, systemd_user, sudo_u, sudo_u_i) for each of `claude --version`, `get-shit-done-cc --help`, `npx playwright --version` — exit 0 + semver regex `[0-9]+\.[0-9]+\.[0-9]+` check. `SKIP_SYSTEMD_UNAVAILABLE` sentinel honored but never triggered on the systemd-capable Docker images. First Phase 5 @tests to exercise the Phase 2 six-mode matrix against REAL agent binaries, not node/npm.)
- [x] **AGT-02**: After `agentlinux install claude-code`, the agent user can self-update Claude Code to a newer version without sudo, without `EACCES`, and without manual intervention (this is the **canonical acceptance test** for v0.3.0). AGT-02 is a permission invariant: the self-update path succeeds regardless of the version produced. (Verified 05-01 Docker smoke on Ubuntu 22.04 + 24.04: 1 @test in tests/bats/51-agt02-release-gate.bats runs REAL `timeout 120s sudo -u agent -H bash --login -c 'claude update'` against live Anthropic CDN; transcript captured to dedicated mktemp file (Pitfall 4 binary-stderr-interleave mitigation); assert_exit_zero + assert_no_eacces + sort -V monotonicity all green; observed post-update 2.1.114 ≥ pinned 2.1.98. File prefix 51-*.bats lets Phase 6 TST-05 select the release-gate subset separately.)
- [x] **AGT-02b**: Installing Claude Code via `agentlinux install claude-code` produces exactly `pinned_version` on disk — `claude --version` matches the catalog's `pinned_version` field — verifying the version-lock mechanism from ADR-011 works end-to-end. Companion test to AGT-02 (which is version-agnostic). (Verified 05-01 in-recipe + 05-04 bats: plugin/catalog/agents/claude-code/install.sh in-recipe `grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"` fails fast on upstream drift; `tests/bats/50-agents.bats` 1 @test `AGT-02b: claude --version returns exactly pinned_version from catalog.json` reads pinned via `jq -r '.agents[] | select(.id=="claude-code") | .pinned_version' /opt/agentlinux/catalog/0.3.0/catalog.json` and substring-matches `claude --version` output — Docker smoke on Ubuntu 22.04 + 24.04 both 66/66 green.)
- [x] **AGT-03**: `claude doctor` (or equivalent diagnostic) reports a clean state for the agent user after install. (Verified 05-04 Docker smoke on Ubuntu 22.04 + 24.04: 1 @test in tests/bats/50-agents.bats `AGT-03: claude --help exits 0 and prints no error strings` — `claude doctor` waits for stdin per GH issue claude-code#26487 (unusable in bats), so `claude --help` is the scriptable substitute: exits 0 + no failure-prefix tokens in output (regex `error:|Error:|ERROR:|Traceback|traceback \(` + case-insensitive `permission denied|EACCES`). Case-insensitive bare-word `error` excluded to avoid false positive on upstream `--mcp-debug` noun "errors" in option description.)
- [x] **AGT-04**: After `agentlinux install gsd`, the agent user can run `gsd --version` (or equivalent) successfully. (Verified 05-02 recipe + 05-04 bats: plugin/catalog/agents/gsd/install.sh `npm install -g get-shit-done-cc@${PINNED}` + banner-grep version-lock; `tests/bats/50-agents.bats` 1 @test `AGT-04: get-shit-done-cc --help banner reports pinned version` reads pinned via jq and substring-matches `v${pinned}` in `get-shit-done-cc --help` output (no `--version` flag exists — banner grep IS the version lock). AGT-01 also covers `get-shit-done-cc --help` six-mode exit-0 under all INVOKE_MODES. Docker 66/66 green on both Ubuntu versions.)
- [x] **AGT-05**: After `agentlinux install playwright`, the agent user can run `npx playwright --version` and `npx playwright install` (downloads browsers into the agent user's cache, no sudo, no EACCES). Playwright is the canonical browser-access tool for agents (replaces v0.2.0's chrome-devtools-mcp). (Verified 05-03 recipe + 05-04 bats: plugin/catalog/agents/playwright/install.sh 3-part body + ADR-012 sudo auto-prepend for apt install-deps; `tests/bats/50-agents.bats` 3 @tests — (1) `AGT-05: npx playwright --version exits 0 with pinned version string` catalog-driven pin substring-match; (2) `AGT-05: chromium cached under ~agent/.cache/ms-playwright (no sudo/EACCES)` finds chromium-* dir + asserts `stat -c '%U'` owner == `agent` (ADR-004 keystone); (3) `AGT-05: re-install playwright is idempotent (CLI-03 invariant on real agent)` second `agentlinux install playwright` exits 0 + prints `already installed`. AGT-01 also covers `npx playwright --version` six-mode. Docker 66/66 green on Ubuntu 22.04 + 24.04; chromium-1217 owned agent:agent; zero "password is required" lines — ADR-012 sentinel green.)

### Registry CLI (CLI)

- [x] **CLI-01**: The `agentlinux` command is available on PATH for the agent user after install. (Verified 04-06 Docker smoke end-to-end on Ubuntu 22.04 + 24.04: plugin/provisioner/50-registry-cli.sh stages CLI bundle trio (dist + node_modules + package.json) under /opt/agentlinux/cli/0.3.0/; symlinks /home/agent/.npm-global/bin/agentlinux -> /opt/agentlinux/cli/0.3.0/dist/index.js via ln -sfn + chown -h; `sudo -u agent -H bash --login -c 'agentlinux --version'` returns `0.3.0`; `agentlinux list` prints 3-agent table. Bats enforcement lands Plan 04-07.)
- [x] **CLI-02**: `agentlinux list` shows all agents in the catalog with an installed/not-installed indicator.
- [x] **CLI-03**: `agentlinux install <name>` installs a catalog agent as the agent user, non-interactively, idempotently.
- [x] **CLI-04**: `agentlinux remove <name>` cleanly uninstalls a catalog agent (binary gone, config restored/removed).
- [x] **CLI-05**: `agentlinux` commands fail fast with a clear error when run as a non-agent user who lacks permission, and succeed without sudo when run as the agent user.
- [x] **CLI-06**: `agentlinux upgrade` detects per-agent divergence (`synced`, `override-ahead`, `override-behind`) between the installed version, the release's curated pin, and upstream latest; offers per-agent 3-way reconcile ([keep override] / [accept curated] / [accept upstream latest]) or bulk flags (`--reset-all-curated`, `--respect-overrides`, `--all-latest`). Drives the stability-first model per ADR-011. ✓ 2026-04-19 (Plan 04-04 TypeScript-side; bats enforcement Plan 04-07)
- [x] **CLI-07**: `agentlinux pin <name>=<curated|latest|x.y.z>` sets sticky override semantics — power-users who ran ahead of the curated set are not re-nagged on subsequent releases; `pin <name>=curated` clears the override. Precedent: Homebrew `brew pin`. ✓ 2026-04-19 (Plan 04-05 TypeScript-side: plugin/cli/src/commands/pin.ts ships pinCmd + parsePinSpec + PinTarget discriminated union; three target shapes via `semver.valid()`-gated parsing (T-04-14 mitigation); partial sentinel update preserves id+installed_at; exit 64 for bad spec/unknown agent, exit 1 for missing install; 20 unit tests including 3 integration-sanity end-to-end with upgrade.ts confirming pin=latest→upgrade --all-latest SKIPS and pin=<semver>→upgrade --reset-all-curated CLEARS. Test total 92→112. Bats enforcement lands Plan 04-07.)

### Catalog (CAT)

- [x] **CAT-01**: The v0.3.0 catalog contains at least three available agents: `claude-code`, `gsd`, `playwright`. (Playwright replaces v0.2.0's chrome-devtools-mcp as the canonical browser-access tool.) ✓ Plan 04-02 (plugin/catalog/catalog.json ships exactly 4 entries: claude-code 2.1.98 script, gsd 1.37.1 npm→get-shit-done-cc, playwright 1.59.1 npm, test-dummy 0.0.1 script/test_only; ajv-validated: `node plugin/cli/scripts/validate-catalog.mjs` → "4 entries OK"; `jq '.agents | length'` → 4).
- [x] **CAT-02**: **None of the catalog agents is installed by default.** Fresh install produces an empty-install state; every agent is opt-in via `agentlinux install`. ✓ Plan 04-02 catalog-side (no provisioner references any recipe; zero `installed_by_default` fields in catalog.json; test-dummy carries `test_only: true` filtering it from default `agentlinux list`. Runtime-side bats assertion — empty installed.d/ after fresh install + test-dummy hidden unless `--include-test` — lands Plan 04-07 per phase TST-07 gate.)
- [x] **CAT-03**: The catalog has a documented, machine-readable schema (JSON) so new agents can be added by submitting a catalog entry + install recipe without code changes to the CLI. (Verified Plan 04-01: plugin/catalog/schema.json is JSON Schema 2020-12 per ADR-011; ajv validator at plugin/cli/src/catalog/schema.ts + pre-commit wrapper at plugin/cli/scripts/validate-catalog.mjs both enforce it; 6/6 unit tests exercise positive + negative + boundary cases.)
- [x] **CAT-04**: Every catalog entry declares a `pinned_version` (required, semver) validated by JSON Schema. `agentlinux install <name>` installs exactly that version via `sudo -u agent -H npm install -g <pkg>@<pinned_version>` (or equivalent native-installer pin for agents with their own installer, e.g. Claude Code). Per ADR-011. (Verified Plan 04-01 schema-side: `required: [..., pinned_version, ...]`; pattern `^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$` accepts pre-release + build-metadata, rejects non-semver. Runtime-side install happens in Plan 04-03.)
- [ ] **CAT-05**: Each release artifact includes a catalog snapshot at `/opt/agentlinux/catalog/<version>/catalog.json` as a sibling of the release tarball + `.sha256`. The installer stages this snapshot; `agentlinux upgrade` reads it to compute the 3-way divergence. The snapshot is what CI validates end-to-end before the release tag is published (per TST-08).

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

- [x] **TST-01**: A black-box behavior-test suite exists that covers every `BHV-XX`, `RT-XX`, `AGT-XX`, `CLI-XX`, `CAT-XX`, and `INST-XX` requirement with at least one automated test. (Phase 2 portion: 22 @tests in tests/bats/10-installer.bats + tests/bats/20-agent-user.bats covering INST-01/02/05 + BHV-01..06 + DOC-02. Phase 3: +5 @tests in tests/bats/30-runtime.bats covering RT-01..04. Phase 4: +22 @tests in tests/bats/40-registry-cli.bats covering CLI-01..07 + CAT-01..04 + INST-04. Phase 5.1: +7 @tests in tests/bats/22-agent-sudo.bats covering INST-06 + BHV-07. Phase 5: +9 @tests in tests/bats/50-agents.bats covering AGT-01 × 3 + AGT-02b + AGT-03 + AGT-04 + AGT-05 × 3, plus +1 @test in tests/bats/51-agt02-release-gate.bats covering AGT-02 — Plan 05-04 closes TST-01. Total: 66 @tests green on Ubuntu 22.04 + 24.04 Docker matrix. Every v0.3.0 observable-behavior requirement has ≥1 bats @test citing it; TST-07 gate GREEN at every phase close.)
- [x] **TST-02**: Tests run inside a Docker-based harness on Ubuntu 22.04 and 24.04 images. Every PR runs the full suite. (Landed 02-05: `tests/docker/Dockerfile.ubuntu-22.04` + `Dockerfile.ubuntu-24.04` + `tests/docker/run.sh` + `.github/workflows/test.yml` `bats-docker` matrix job with `fail-fast: false` and `timeout-minutes: 15`. End-to-end green on both Ubuntu versions locally; matrix runs on every PR.)
- [~] **TST-03**: Tests also run inside a QEMU-based harness against a fresh Ubuntu cloud image (nightly and release-gate). Docker-only testing is insufficient per known false-positive categories (root-by-default, no systemd, locale). (Plan 06-03 landed the harness structure: `tests/qemu/boot.sh` 14-step cloud-init + QEMU-with-KVM + ssh + installer + bats orchestrator; `tests/qemu/cloud-init/user-data` + `meta-data` templates with per-run pubkey placeholder; `tests/qemu/cloud-images.txt` URL+SHA256 manifest driving actions/cache key; `.github/workflows/nightly-qemu.yml` matrix 22.04+24.04 with KVM udev rule + cache + artifact-on-failure upload. All static gates green: shellcheck --severity=warning + shfmt -i 2 -ci -bn + bash -n + actionlint all clean. Runtime gate — green workflow_dispatch run on both Ubuntu versions with AGT-02 passing in-guest — deferred to first CI run per 06-VALIDATION.md §Manual-Only Verifications. Pitfall 4 (KVM fail-fast) + Pitfall 10 (SHA256 cache-hit verify) + T-06-06 (per-run keypair hygiene) code paths present and exercised locally where possible.)
- [x] **TST-04**: Test failures produce a clear diagnostic: which BHV/RT/AGT/CLI/CAT/INST requirement failed, what was expected, what was observed, where the logs live. (Landed 02-05: `tests/bats/helpers/assertions.bash` __fail emits four-line diagnostic `# FAIL: <req-id>` / `#   expected: ...` / `#   observed: ...` / `#   log: ...` on stderr for every assertion failure; bats TAP surfaces as test-attached comments.)
- [ ] **TST-05**: The acceptance test `AGT-02` (agent user self-updates Claude Code without sudo/EACCES) is a blocking gate for any release.
- [x] **TST-06**: Mutation testing runs nightly. The Node.js registry CLI uses `stryker-mutator` (target ≥ 75% mutation score, advisory in v0.3.0). Bash sources use a custom `tests/mutation/bash-mutator.sh` (target ≥ 60% mutation score, advisory in v0.3.0). Score regressions open a follow-up issue but do not block release in v0.3.0; promotion to a release gate is a v0.4 decision. ✓ Plan 01-02 (scaffolded: `plugin/cli/stryker.config.json` with `thresholds.break: 0`; `tests/mutation/bash-mutator.sh` executable, exits 0 on empty plugin; `nightly-mutation.yml` uses `continue-on-error: true`; `tests/mutation/README.md` documents advisory status. Full mutant-scoring bodies land in Phase 2+.) + Plan 01-05 (9 @tests in `tests/harness/60-mutation-scaffolding.bats` assert the scaffolding stays runnable and advisory).
- [x] **TST-07**: A `behavior-coverage-auditor` review subagent (per HRN-06) runs at the end of every phase to assert that every newly-added BHV/RT/AGT/CLI/CAT/INST requirement has at least one bats test. ✓ Plan 01-03 (`.claude/agents/behavior-coverage-auditor.md` defines the subagent; `.claude/skills/review/SKILL.md` §"Relation to TST-07" names it as the "always spawn at phase close regardless of what changed" gate; emits `TST-07 gate: RED|GREEN` summary line for the main agent to decide phase close.)
- [ ] **TST-08**: CI installs the pinned catalog combo (every agent at its `pinned_version` per CAT-04) and runs the full bats suite against it before the release tag is published (Phase 6 release-gate). Ensures we never ship a curated combo that was not end-to-end validated together. A red run of this gate blocks the release workflow. Per ADR-011.

### Documentation (DOC)

- [ ] **DOC-01**: A README ships with the installer describing: how to install, how to verify (`agentlinux list` + one test command), how to uninstall.
- [x] **DOC-02**: A `CLAUDE.md` is placed in the agent user's home with guidance that the environment is correctly owned and agent tools must NOT create shim/wrapper workarounds. Prevents LLM agents from pattern-matching on past permission bugs and introducing the exact class of shim AgentLinux exists to prevent. (Landed 02-03 via ensure_marker_block with tag `agentlinux-doc-02`; verified 02-05 bats: 4 @tests for file existence, agent:agent owner via stat, and three anti-pattern greps [`usr/local/bin`, `sudo npm install -g`, `second Node install`].)

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
- **CAT-06**: Remote-fetch catalog with embedded fallback (renumbered from CAT-04; v0.3.0 now uses CAT-04 for per-entry `pinned_version` per ADR-011)
- **CAT-07**: Multiple install backends per catalog entry (npm / apt / binary download / pipx) (renumbered from CAT-05)
- **CLI-08**: `agentlinux info <name>` — detailed info per agent (renumbered from CLI-06)
- **CLI-09**: `agentlinux update <name>` — delegates to the agent's own self-update (distinct from CLI-06 `agentlinux upgrade`, which reconciles against the curated catalog pin; CLI-09 would invoke the agent's native updater, e.g. `claude update`) (renumbered from CLI-07)
- **CLI-10**: `agentlinux doctor` — system-wide health check (renumbered from CLI-08)

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
| INST-01 | Phase 2 | ✓ Complete (02-02 entrypoint; verified 02-05 bats: 2 @tests on log existence + success banner) |
| INST-02 | Phase 2 | ✓ Complete (02-04 idempotent heredocs + ensure_marker_block; verified 02-05 bats: 1 @test on sha256 byte-stable re-run across 5 artefacts) |
| INST-05 | Phase 2 | ✓ Complete (02-02 tee-to-log + stderr merge; verified 02-05 bats: 1 @test — 0 EACCES matches in /var/log/agentlinux-install.log) |
| BHV-01 | Phase 2 | ✓ Complete (02-03 provisioner; verified 02-05 bats: 4 @tests on getent passwd shell/home + LANG/LC_ALL + locale -a) |
| BHV-02 | Phase 2 | ✓ Complete (02-04 .bashrc --top marker block; verified 02-05 bats: 2 @tests via run_ssh helper + lazy ed25519 keypair) |
| BHV-03 | Phase 2 | ✓ Complete (02-04 /etc/cron.d/agentlinux literal PATH header; verified 02-05 bats: 1 @test via run_cron helper polling 70s) |
| BHV-04 | Phase 2 | ✓ Complete (02-04 /etc/agentlinux.env + dbus in Dockerfile; verified 02-05 bats: 2 @tests via run_systemd_user helper with SKIP_SYSTEMD_UNAVAILABLE sentinel) |
| BHV-05 | Phase 2 | ✓ Complete (02-04 profile.d for -i login path; verified 02-05 bats: 3 @tests via run_sudo_u [bash --login -c] + run_sudo_u_i [sudo -u -H -i bash -c]. Note: plain `sudo -u agent bash -c` path needs PAM/sudoers work deferred to v0.4+) |
| BHV-06 | Phase 2 | ✓ Complete (02-04 /etc/profile.d/agentlinux.sh; verified 02-05 bats: 2 @tests via run_interactive helper [su - agent -c]) |
| DOC-02 | Phase 2 | ✓ Complete (02-03 CLAUDE.md + ensure_marker_block --top; verified 02-05 bats: 4 @tests on file+owner+three anti-pattern greps) |
| TST-01 | Phase 2+ | ✓ Partial (Phase 2 portion: 22 bats @tests in 10-installer.bats + 20-agent-user.bats; grows each phase until Phase 5 closes) |
| TST-02 | Phase 2 | ✓ Complete (02-05 bats-docker matrix on Ubuntu 22.04 + 24.04; end-to-end green; fail-fast=false; timeout-minutes=15) |
| TST-04 | Phase 2 | ✓ Complete (02-05 tests/bats/helpers/assertions.bash __fail emits four-line req-id/expected/observed/log diagnostic via stderr on every failure) |
| RT-01 | Phase 3 | ✓ Complete installer-side (03-01: NodeSource Node 22 LTS + version gate in 30-nodejs.sh; Node v22.22.2 verified end-to-end on Ubuntu 22.04 + 24.04; observable six-mode bats proof lands in Plan 03-02) |
| RT-02 | Phase 3 | Pending (Plan 03-02 bats — PATH wiring installer-side ready via 40-path-wiring.sh extension in 03-01) |
| RT-03 | Phase 3 | Pending (Plan 03-02 bats) |
| RT-04 | Phase 3 | ✓ Complete installer-side (03-01: ~agent/.npmrc `prefix=/home/agent/.npm-global` + NPM_CONFIG_PREFIX belt-and-braces in /etc/agentlinux.env; /home/agent/.npm-global agent-owned 0755; T-03-03 byte-identical split-brain avoidance; observable six-mode bats proof lands in Plan 03-02 via assert_user_prefix_in_home) |
| CLI-01 | Phase 4 | ✓ Complete (04-06 installer-side + 04-07 bats: 2 @tests in tests/bats/40-registry-cli.bats loop all six INVOKE_MODES asserting `command -v agentlinux` resolves under /home/agent/.npm-global/bin AND `agentlinux --version` prints `0.3.0`; 49/49 green on Ubuntu 22.04 + 24.04) |
| CLI-02 | Phase 4 | ✓ Complete (04-03 TS + 04-07 bats: 3 @tests in 40-registry-cli.bats — default list shows 3 real agents with test-dummy hidden, --include-test shows test-dummy, --json emits machine-readable array) |
| CLI-03 | Phase 4 | ✓ Complete (04-03 TS + 04-07 bats: 4 @tests in 40-registry-cli.bats — install creates marker+sentinel with pinned_version=0.0.1 + source=curated; second install idempotent ("already installed"); --force re-runs recipe (installed_at advances); --version 9.9.9 overrides catalog pin (sentinel.source=override)) |
| CLI-04 | Phase 4 | ✓ Complete (04-03 TS + 04-07 bats: 2 @tests in 40-registry-cli.bats — remove clears marker+sentinel; remove-when-not-installed exits 1 w/o --force and 0 with --force) |
| CLI-05 | Phase 4 | ✓ Complete (04-01 preAction + 04-03 TS + 04-07 bats: 2 @tests in 40-registry-cli.bats — as root exits 64 with "must run as user 'agent'"; as agent succeeds without sudo) |
| CLI-06 | Phase 4 | ✓ Complete (04-04 TS + 04-07 bats: 1 @test in 40-registry-cli.bats — `agentlinux upgrade` with no flags prints divergence report including real agents + leaves sentinel byte-identical (report-only default, offline-default honored)) |
| CLI-07 | Phase 4 | ✓ Complete (04-05 TS + 04-07 bats: 2 @tests in 40-registry-cli.bats — pin=latest sets sticky=true + source=latest; pin=curated clears sticky and sets source=curated) |
| CAT-01 | Phase 4 | ✓ Complete (04-02 catalog + 04-07 bats: 1 @test in 40-registry-cli.bats asserts JSON list contains claude-code, gsd, playwright via jq) |
| CAT-02 | Phase 4 | ✓ Complete (04-02 catalog + 04-07 bats: 1 @test in 40-registry-cli.bats asserts `/opt/agentlinux/state/installed.d/` has zero *.json files after force-remove of test-dummy) |
| CAT-03 | Phase 4 | ✓ Complete (04-01 schema + 04-02 recipes + 04-07 bats: 1 @test in 40-registry-cli.bats builds a tmp catalog with a fresh `fake-42` entry, points the CLI at it via AGENTLINUX_CATALOG_DIR env override + schema.json copy from production, and asserts the agent appears in `agentlinux list --json` — no TypeScript source change required) |
| CAT-04 | Phase 4 | ✓ Complete (04-01 schema + 04-07 bats: 1 @test in 40-registry-cli.bats asserts every list row has a non-empty pinned_version AND spot-checks claude-code=2.1.98, gsd=1.37.1, playwright=1.59.1, test-dummy=0.0.1) |
| CAT-05 | Phase 6 | Pending (release-time catalog snapshot sibling per ADR-011) |
| INST-04 | Phase 4 | ✓ Complete (04-06 installer + 04-07 bats: 2 @tests in tests/bats/40-registry-cli.bats — (1) `--purge` removes /opt/agentlinux + agent user + PATH artefacts + NodeSource apt files + install log (step 7, LAST) while keeping Node (no --remove-nodejs default); uninstall.sh ran before /opt removal (marker cleared); (2) second `--purge` run is idempotent (exit 0 with nothing to clean). T-04-16 + T-04-17 mitigations enforced.) |
| INST-06 | Phase 5.1 (INSERTED) | ✓ Complete (05.1-01 installer + bats: plugin/provisioner/20-sudoers.sh atomic 0440 drop-in with visudo -cf gate; 2 @tests in tests/bats/22-agent-sudo.bats cover `sudo -n true` exit 0 and `(ALL) NOPASSWD: ALL` in sudo -l) |
| BHV-07 | Phase 5.1 (INSERTED) | ✓ Complete (05.1-01 installer + bats: `/etc/sudoers.d/agentlinux` 0440 root:root `agent ALL=(ALL) NOPASSWD: ALL` via visudo-gated atomic install; 5 @tests cover existence + mode/owner + exact-line grep -Fx + visudo -cf + sha256 byte-stable across re-run) |
| AGT-01 | Phase 5 | ✓ Complete (05-04 bats: 3 @tests in tests/bats/50-agents.bats loop `${INVOKE_MODES[@]}` six modes for each of `claude --version`, `get-shit-done-cc --help`, `npx playwright --version` — first AGT-XX @tests to exercise the Phase 2 six-mode matrix against real agent binaries; Docker 66/66 green on both Ubuntu versions) |
| AGT-02 | Phase 5 | ✓ Complete (05-01 recipe + bats: tests/bats/51-agt02-release-gate.bats 1 @test captures `claude update` transcript via mktemp/timeout 120s + assert_no_eacces + sort -V monotonicity; Docker 22.04 + 24.04 green end-to-end, observed 2.1.114 ≥ pinned 2.1.98) |
| AGT-02b | Phase 5 | ✓ Complete (05-01 recipe + 05-04 bats: plugin/catalog/agents/claude-code/install.sh `grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"` in-recipe fail-fast + 1 @test in tests/bats/50-agents.bats AGT-02b reads catalog pin via jq and substring-matches `claude --version` output) |
| AGT-03 | Phase 5 | ✓ Complete (05-04 bats: 1 @test in tests/bats/50-agents.bats asserts `claude --help` exits 0 + no failure-prefix tokens (error:/Error:/ERROR:/Traceback/permission denied/EACCES); `claude doctor` substitute per GH issue claude-code#26487 — doctor waits for stdin) |
| AGT-04 | Phase 5 | ✓ Complete (05-02 recipe + 05-04 bats: plugin/catalog/agents/gsd/install.sh npm-global body with `--help` banner-grep in-recipe + 1 @test in tests/bats/50-agents.bats reads catalog pin via jq and substring-matches `v${pinned}` in `get-shit-done-cc --help` output; AGT-01 also covers six-mode exit-0 for get-shit-done-cc) |
| AGT-05 | Phase 5 | ✓ Complete (05-03 recipe + 05-04 bats: plugin/catalog/agents/playwright/install.sh 3-part body + ADR-012 sudo auto-prepend; 3 @tests in tests/bats/50-agents.bats — catalog-driven pin version substring-match + chromium cache exists with `stat -c '%U'` owner `agent` + CLI-03 idempotent re-install — plus AGT-01 six-mode for `npx playwright --version`. Zero "password is required" lines in transcripts; ADR-012 sentinel green.) |
| INST-03 | Phase 6 | Pending |
| TST-03 | Phase 6 | ~ In progress (06-03 harness structure complete: tests/qemu/boot.sh + cloud-init/ + cloud-images.txt + nightly-qemu.yml populated; static gates all green; runtime verification — exit-0 boot on 22.04 + 24.04 + AGT-02 in-guest — deferred to first CI run per 06-VALIDATION Manual-Only Verifications) |
| TST-05 | Phase 6 | Pending |
| TST-08 | Phase 6 | Pending (release-gate pinned-combo CI per ADR-011) |
| DOC-01 | Phase 6 | Pending |

**Coverage:**
- v0.3.0 requirements: 54 total (9 HRN + 6 INST + 7 BHV + 4 RT + 6 AGT + 7 CLI + 5 CAT + 8 TST + 2 DOC) — grew from 52 with ADR-012 additions (INST-06, BHV-07) on 2026-04-19
- Mapped to phases: 54 (100%)
- Unmapped: 0

**Per-phase counts:**
- Phase 1 (Harness Setup): 11 — HRN-01..HRN-09, TST-06, TST-07
- Phase 2 (Installer Foundation + Agent User): 13 — INST-01, INST-02, INST-05, BHV-01..BHV-06, DOC-02, TST-01, TST-02, TST-04
- Phase 3 (Node.js Runtime + Per-User npm Prefix): 4 — RT-01..RT-04
- Phase 4 (Registry CLI + Catalog + Uninstall): 12 — CLI-01..CLI-07, CAT-01..CAT-04, INST-04 (grew from 9 with CLI-06, CLI-07, CAT-04 added per ADR-011)
- Phase 5 (Agent Installability): 6 — AGT-01, AGT-02, AGT-02b, AGT-03..AGT-05 (grew from 5 with AGT-02b added per ADR-011)
- Phase 6 (Distribution + Release Pipeline): 6 — INST-03, TST-03, TST-05, TST-08, CAT-05, DOC-01 (grew from 4 with TST-08 + CAT-05 added per ADR-011)

---
*Requirements defined: 2026-04-18 — behavior-contract framing per user direction; implementation left intentionally open.*
*Traceability mapped: 2026-04-18 — 46/46 requirements mapped across 6 phases, 0 orphans.*
*ADR-011 update: 2026-04-19 — 6 new requirements added for stability-first version pinning (CAT-04, CAT-05, CLI-06, CLI-07, TST-08, AGT-02b); v0.4+ placeholder IDs renumbered (CAT-04→06, CAT-05→07, CLI-06→08, CLI-07→09, CLI-08→10). Now 52/52 mapped across 6 phases.*
