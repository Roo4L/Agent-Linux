---
name: behavior-test-contract
description: Use when authoring or modifying bats tests under tests/bats/. Documents how to write BHV/RT/AGT/CLI/CAT/INST tests, shared assertion helpers, the six invocation modes (interactive bash login, non-interactive SSH, cron, systemd User=agent, sudo -u agent, sudo -u agent -i), and the no-EACCES contract. Every @test references its requirement ID so behavior-coverage-auditor can trace coverage. Grows as the first bats suite ships in Phase 2.
---

# behavior-test-contract — Bats test authoring

**Status:** Skeleton. Grows with Phase 2's first bats suite, when the concrete assertion-helper signatures and the first idiomatic BHV test land. The core contract below is already fixed.

Authoritative spec: `docs/HARNESS.md` §1.3 (testing) and §5.2 (skill table). Decisions: ADR-002 (behavior-contract framing — tests are the spec). Requirements this skill helps enforce: BHV-01..BHV-06, RT-01..RT-04, AGT-01..AGT-05, CLI-01..CLI-05, CAT-01..CAT-03, INST-01..INST-05, plus TST-01..TST-07.

## When to use this skill

Use when the task touches any file under:

- `tests/bats/*.bats` — the behavior suite.
- `tests/bats/helpers/*.bash` — shared assertion helpers.
- `tests/docker/run.sh` or `tests/qemu/boot.sh` — the harness that *executes* the bats suite.

Skip for unit tests in `plugin/cli/test/` — those are Node `node:test` and follow the `node-engineer` rubric, not this one.

## Core contract

Behavior tests in `tests/bats/` **are the spec** (ADR-002). Implementation may change freely as long as the suite stays green. Requirements (BHV-XX, RT-XX, AGT-XX, CLI-XX, CAT-XX, INST-XX) are what tests assert — not implementation details. A requirement that is not covered by a `@test` does not exist in the release-gate sense.

## File layout (from HARNESS.md §1.1)

| File | Covers |
|---|---|
| `tests/bats/10-installer.bats` | INST-01..INST-05 (installer idempotency, exit codes, no EACCES) |
| `tests/bats/20-agent-user.bats` | BHV-01..BHV-06 (agent user, six invocation modes, UTF-8 locale, bash shell) |
| `tests/bats/30-runtime.bats` | RT-01..RT-04 (Node.js LTS, per-user npm prefix, install/uninstall round-trip) |
| `tests/bats/40-agent-tools.bats` | AGT-01..AGT-05 (including the canonical AGT-02 Claude Code self-update test) |
| `tests/bats/50-registry-cli.bats` | CLI-01..CLI-05 + CAT-01..CAT-03 (catalog list/install/remove, schema validation) |
| `tests/bats/helpers/*.bash` | Shared assertion helpers, sourced via `load 'helpers/<file>'` |

## The six invocation modes

Every BHV/RT/AGT test that asserts "agent binary X works" MUST cover all six invocation modes. The matrix is fixed and audited by the `qa-engineer` subagent rubric. Missing one is a deviation, not a style choice.

| Mode | Invocation | Why it's different |
|---|---|---|
| Interactive bash login (BHV-06) | `su - agent -c '<cmd>'` | Reads `/etc/profile.d/*.sh` + `~/.bash_profile` |
| Non-interactive SSH (BHV-02) | `ssh agent@host '<cmd>'` | Reads `~/.bashrc` only (no login shell) |
| Cron (BHV-03) | Crontab entry executing the command | Reads `/etc/environment`; minimal PATH |
| systemd `User=agent` (BHV-04) | Transient unit via `systemd-run --user=agent` | Reads unit `Environment=PATH=...`; no user profile files |
| `sudo -u agent` (BHV-05) | `sudo -u agent <cmd>` | Inherits invoker's env minus `env_reset`; needs `env_keep+=PATH` |
| `sudo -u agent -i` (BHV-05) | `sudo -u agent -i <cmd>` | Login shell for agent user; reads `~/.profile` |

Each must see: the correct PATH (agent's npm prefix + agentlinux CLI), a UTF-8 locale (`LANG`/`LC_ALL`), and `bash` as the shell.

## The no-EACCES contract (INST-05, AGT-02)

Zero occurrences of `EACCES` or `permission denied` on stdout or stderr during the entire installer run, during every BHV/RT test, and especially during AGT-02 (Claude Code self-update). This is the single hardest acceptance criterion. The helper `assert_no_eacces_in_log` is the gate.

## Assertion helpers (land in Phase 2 under `tests/bats/helpers/`)

- `assert_agent_can_run <mode> <cmd>` — dispatches on the six invocation modes; asserts exit 0 AND no EACCES in combined output.
- `assert_no_eacces_in_log <logfile>` — `! grep -E 'EACCES|permission denied' <logfile>` (case-sensitive on `EACCES`, case-insensitive on the second form).
- `assert_self_update_succeeds` — the canonical AGT-02 test body; wraps Claude Code self-update.
- `assert_binary_on_path <binary>` — `command -v <binary>` resolves to a path under the agent user's home or `/usr/local/bin/agentlinux` — never a wrapper shim.
- `assert_no_shim <binary>` — follows `readlink -f` to confirm the binary is not a wrapper pointing at a different agent-owned binary.
- `assert_npm_prefix_is_user_writable` — `npm config get prefix` returns a path the agent user can write to without sudo.

## Test-ID linkage (required)

Every `@test` line in a `.bats` file MUST reference its requirement ID in the test name. The `behavior-coverage-auditor` subagent greps for this linkage at every phase close (TST-07 gate).

Good:
```bash
@test "BHV-02: agent user runs command over non-interactive SSH with PATH" { ... }
@test "AGT-02: agent user self-updates Claude Code without EACCES" { ... }
```

Bad (no ID — auditor flags this):
```bash
@test "agent can SSH" { ... }
```

## Assertion strength (qa-engineer rubric)

- **Weak (mutation-kill weak):** exit-code-only assertions. A test that only checks `run <cmd>; [ "$status" -eq 0 ]` kills almost no mutants.
- **Strong:** assert stdout contents, stderr absence of EACCES, filesystem state (file exists, owner, mode), and PATH resolution. Strong tests are what keep mutation score ≥ 60% for bash and ≥ 75% for the Node CLI.

## Common pitfalls (Phase 1 advance-notice)

- **Docker-only for BHV-04.** Docker has no systemd by default. A BHV-04 test that passes only in Docker is a false positive. systemd tests MUST run in QEMU (or a systemd-enabled Docker image).
- **`assert_success` on a pipeline without `set -o pipefail`.** A pipeline exit status is the last command's; upstream failures are hidden.
- **Silent `skip` without a tracking reference.** `skip` is allowed but MUST reference an issue or a requirement ID (`skip "SKIPPED: AGT-02 pending Phase 5"`). Unconditional `skip` is flagged.

## Growth plan

- **Phase 2:** First `10-installer.bats` and `20-agent-user.bats` ship. This skill absorbs concrete helper signatures and one idiomatic BHV test example.
- **Phase 3:** `30-runtime.bats` for Node/npm. Skill gains the `assert_npm_prefix_is_user_writable` example.
- **Phase 4:** `50-registry-cli.bats` for CLI + CAT. Skill links to `catalog-schema` skill for recipe-validation tests.
- **Phase 5:** `40-agent-tools.bats` with AGT-02 — the canonical release-gate test. Skill gains the `assert_self_update_succeeds` body.
- **Phase 6:** QEMU harness wraps the same bats suite. Skill adds the "Docker false positives to watch for" list.

## Related

- `docs/HARNESS.md` §1.3 (testing layers), §5.2 (skill table), §4.2 (qa-engineer + behavior-coverage-auditor rubrics).
- ADRs: 002 (behavior-contract framing), 007 (Docker + QEMU two-layer harness).
- Subagents: `qa-engineer` (test authoring review), `behavior-coverage-auditor` (end-of-phase TST-07 gate).
- Sibling skills: `agentlinux-installer` (the installer these tests exercise), `catalog-schema` (catalog recipes tested by `50-registry-cli.bats`), `qemu-harness` (the release-gate environment these tests run in).
