---
phase: quick-260630-gn4
plan: 01
subsystem: installer
tags: [AL-50, AL-59, INST-07, installer, registry-cli, sudoers, security]
requires:
  - plugin/bin/agentlinux-install (INSTALL_USER resolution)
  - plugin/lib/remediate.sh (validate_user_name)
  - /etc/agentlinux.env (AGENTLINUX_USER runtime source-of-truth)
provides:
  - configurable target install username (--user / AGENTLINUX_USER / prompt)
  - hardened username validation (reserved/system-account rejection)
  - fully threaded resolved-user across provisioners + sudoers + catalog CLI
affects:
  - plugin/provisioner/*
  - plugin/cli/src/runner.ts (dispatch user)
  - plugin/cli/src/guard/user.ts (guard user)
tech-stack:
  added: []
  patterns:
    - "_AL_USER/_AL_HOME derivation mirrored across every provisioner"
    - "resolveInstallUser() in CLI reads AGENTLINUX_USER env / /etc/agentlinux.env"
    - "username spliced into sudoers via printf (no unquoted heredoc / no eval)"
key-files:
  created:
    - tests/bats/23-install-user.bats
  modified:
    - plugin/bin/agentlinux-install
    - plugin/lib/remediate.sh
    - plugin/lib/prompt.sh
    - plugin/provisioner/30-nodejs.sh
    - plugin/provisioner/40-path-wiring.sh
    - plugin/provisioner/50-registry-cli.sh
    - plugin/provisioner/20-sudoers.sh
    - plugin/lib/remediate/sudoers.sh
    - plugin/lib/detect/sudoers.sh
    - plugin/cli/src/runner.ts
    - plugin/cli/src/guard/user.ts
    - plugin/cli/test/runner.test.ts
    - plugin/cli/test/guard-user.test.ts
    - docs/internals/installer.md
    - docs/internals/agent-user.md
    - docs/internals/registry-cli.md
decisions:
  - "Resolution precedence: --user flag > AGENTLINUX_USER env > interactive prompt > agent"
  - "validate_user_name stays PURE (no getent); a separate user_adoptable runtime gate refuses existing UID<1000 system accounts"
  - "CLI resolveInstallUser re-validates POSIX charset and falls back to agent on a malformed read (defense-in-depth)"
  - "teardown_file restores the agent baseline via purge+reinstall so 23-install-user does not poison downstream bats files"
metrics:
  duration: ~75m
  completed: 2026-06-30
  tasks: 7
  files: 16
requirements: [AL-50, INST-07]
---

# Phase quick-260630-gn4 Plan 01: Configurable Target Username at Install Time Summary

Make the AgentLinux installer provision under an operator-chosen target user
(`--user=NAME`, `AGENTLINUX_USER` env, or an interactive prompt) instead of the
hardcoded `agent`, with hardened username validation and the resolved user
threaded through every provisioner, the sudoers drop-in, and the catalog CLI —
closing the AL-59 alt-user hollow-install bug.

## What shipped

- **Task 1 — resolve + harden-validate (f029fed).** `remediate::validate_user_name`
  now rejects `root` + a reserved/system denylist (`daemon`, `www-data`, `nobody`,
  any `systemd-*`, …) case-insensitively, on top of the POSIX charset. A new
  `remediate::user_adoptable` runtime gate refuses to adopt an existing system
  account (UID < 1000). The entrypoint resolves `--user > AGENTLINUX_USER > agent`,
  validates at parse time (exit 64 before any mutation), and runs the adoption
  gate after `require_root`.
- **Task 2 — interactive prompt (1fbc192).** `prompt::choose_install_user` renders
  `Install AgentLinux under which user? [agent]` on stderr, returns the chosen
  name on stdout (no export-across-pipe), validates + re-prompts 3× then falls
  back to default. Wired into `main()` only on a TTY with no explicit flag/env.
- **Task 3 — thread nodejs/registry-cli/adoption/purge (bda95c1).** 30-nodejs,
  50-registry-cli, and the entrypoint `run_agent_adoption`/`run_purge` derive all
  per-user paths/ownership/sudo-targets from `_AL_USER`/`_AL_HOME`.
- **Task 4 — thread 40-path-wiring (1ebc11d).** All four artefacts + `.local`/
  `.bashrc` derive from the resolved user; heredocs switched to unquoted with
  escaped runtime-shell vars; `/etc/agentlinux.env` now carries `AGENTLINUX_USER`
  + `AGENTLINUX_AGENT_HOME`. Byte-identical PATH/NPM_CONFIG_PREFIX for `agent`.
- **Task 5 — parameterize sudoers (dc5cb36).** The NOPASSWD line's username column
  is built from the validated user via `printf` (no unquoted heredoc, no eval);
  detection's canonical/drift line is parameterized; visudo gate + 0440 root:root
  preserved.
- **Task 6 — catalog CLI guard + dispatch (f64550c RED → 9e143a7 GREEN).**
  `resolveInstallUser()` (env > `/etc/agentlinux.env` > `agent`, POSIX re-validated)
  drives both `guardAgentUser` and `dispatchRecipe`; recipes now dispatch as
  `dispatcher(user, …)` with HOME/PATH/NPM_CONFIG_PREFIX from `/home/<user>`.
  Byte-identical for `agent`.
- **Task 7 — behavior suite + docs (9501601).** `tests/bats/23-install-user.bats`
  (8 INST-07 @tests: AC1–AC5 + no-leftover-agent grep + dispatch-as-configured-user
  via a test-dummy recipe marker owned by the alt user). Three `docs/internals`
  pages updated.

## Verification

- `shellcheck -x --severity=warning` (the CI severity) clean on every modified
  bash file; `bash -n` clean on the heredoc-heavy 40-path-wiring.
- `cd plugin/cli && pnpm test`: the new `guard-user.test.ts` (4) and the added
  `runner.test.ts` alt-user cases (8 total) pass, including
  `AGENTLINUX_USER=claude → dispatcher("claude", …)` and the malformed→agent
  fallback. Default-`agent` output stays byte-identical (existing cross-asserts
  green).
- Render-harness proof: for `agent` the emitted profile.d/env/cron/sudoers bytes
  match the pre-change form (only a cosmetic "agent-owned"→"user-owned" comment
  and the additive `AGENTLINUX_USER`/`AGENTLINUX_AGENT_HOME` env lines differ);
  for `claude` every artefact is parameterized with **zero** `\bagent\b` /
  `/home/agent` leftovers. `visudo -cf` validates the generated `claude` sudoers.
- `bats --count tests/bats/23-install-user.bats` → 8 (TST-07 INST-07 gate).
- Docker bats suite (`./tests/docker/run.sh ubuntu-24.04`): the suite passed
  tests 1–131 (10-installer, 13-reuse, 14-remediate, 15-detection,
  15-preflight-ux — all exercising the modified 20/30/40/50 provisioners +
  sudoers) before an environment OOM (see Deviations). A clean re-run was
  launched to capture 23-install-user end-to-end.

## Deviations from Plan

### Auto-fixed / adjusted

**1. [Rule 3 - Blocking] Plan verify command `bash -n` is invalid for bats DSL.**
- **Found during:** Task 7.
- **Issue:** The Task 7 `<automated>` block runs `bash -n tests/bats/23-install-user.bats`,
  but bats's `@test "…" { … }` syntax is not valid bash — `bash -n` errors on
  *every* bats file in the repo (confirmed against 10-installer.bats).
- **Fix:** Used the correct parser gate `bats --count tests/bats/23-install-user.bats`
  → 8. No file change needed.

**2. [Rule 3 - Blocking] Plan verify paths point at a sibling worktree.**
- **Found during:** all tasks.
- **Issue:** The PLAN.md `<automated>` commands hardcode
  `/home/agent/agent-linux/.claude/worktrees/user-configuration` (the worktree
  the plan was authored in). Execution happened in
  `…/worktrees/agent-ac777d1a60d04f0ec`.
- **Fix:** Ran each verify against the execution worktree. Logic unchanged.

**3. [biome] noDelete lint on test env cleanup.**
- **Found during:** Task 6 RED commit.
- **Issue:** pre-commit's biome blocked `delete process.env.AGENTLINUX_USER`.
- **Fix:** Added the codebase's standard `// biome-ignore lint/performance/noDelete`
  comment (same pattern already used in adopt/list tests).

### Cron comment reworded (AC4 enablement)

The 40-path-wiring cron artefact's comment "Any agent cron job…" contained a
bare lowercase `agent` that would trip the AC4 no-leftover grep on an alt-user
install. Reworded to "Any cron job…" — cosmetic, byte-stable on re-run.

## Deferred Issues

**Pre-existing `plugin/cli/test/install.test.js` file-level failure (OUT OF SCOPE).**
On both the pre-change baseline and after this work, `install.test.js` reports
all 14 subtests passing but exits the test *file* with code 1 (no `not ok`
subtest, empty stderr) — a node:test harness artifact (a leaked `process.exit`
override after tests complete), unrelated to the username feature. Left as-is per
the scope boundary; `runner.test.ts` + `guard-user.test.ts` (the files this plan
owns) are fully green.

## Threat Flags

None — the changes stay inside the plan's `<threat_model>` surface
(username → useradd/chown/sudoers/paths; `/etc/agentlinux.env` → CLI). All
`mitigate` dispositions (T-AL50-01..04, T-AL50-06) are implemented.

## Self-Check: PASSED

All 5 sampled key files exist on disk; all 8 per-task commits are present in
`git log`.

## Review Follow-up (post-execution)

The `--validate` review loop (security/bash/node/qa/coverage/ai-deslop/dev-docs/
fact-check/external-audience + gsd-verifier) ran clean on the core change but
surfaced one real code gap and confirmed the new bats file had never executed
end-to-end (the executor's Docker run OOMed at test ~131, before reaching it).
Three follow-up commits (2807b18, cfad7a2, d29ae60):

- **`fix`: npm_ls.ts (AL-59 gap).** `agentlinux upgrade`'s npm probe
  (`queryGlobalNpm` / `queryNpmViewLatest`) still hardcoded `dispatcher("agent",
  …)` + `/home/agent` — a sibling the plan never enumerated. Now resolves via
  `resolveInstallUser()`; new `npm_ls.test.ts`. Independently flagged by
  ai-deslop and gsd-verifier (Truth 6 / AC4).
- **`test`: 23-install-user.bats.** First true E2E Docker run (Ubuntu 24.04)
  failed: the brownfield-aware installer needs `--yes` to switch the shared
  artefacts to an alt user (added to 4 invocations), and the AC4 no-leftover
  grep tripped on the sudoers ADR citation `012-agent-user-full-sudo.md`
  (whitelisted). Added a uid<1000 `user_adoptable` adoption-refusal @test
  (qa-engineer). **All 9 INST-07 @tests now green E2E.**
- **`docs`: registry-cli.md / installer.md / prompt.sh.** Synced stale "agent
  user" claims to "configured install user"; scoped the exit-64 guarantee to
  flag/env paths; trimmed an internal `INST-06` ID from a public-facing example;
  dropped a now-false "KNOWN LIMITATION (AL-59)" source comment.
