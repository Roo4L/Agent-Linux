# Phase 47: openclaw — Summary

**Status:** ✓ COMPLETE (Docker 4/4 green, ubuntu-24.04; systemd-user lifecycle QEMU-gated) — 2026-07-14
**Requirements:** ASST-01, ENABLE-04, ENABLE-05 (+ OPS-01 real-op gate)
**Jira:** AL-94

## What shipped

- **ENABLE-04 AI-assistant daemon lifecycle** — `plugin/catalog/lib/daemon-lifecycle.sh`:
  a shared, sourced helper owning the per-user-daemon bookkeeping every daemon-class tool
  needs — `XDG_RUNTIME_DIR` export, a `systemctl --user` availability probe
  (`al_daemon_user_systemd_available`), ownership-aware linger enable/revert
  (`al_daemon_enable_linger` / `al_daemon_revert_linger_if_unused`), and per-tool markers.
  Linger is enabled only if it was off, and reverted only if AgentLinux enabled it AND no
  other daemon tool's marker remains — so removing one daemon never cuts linger from under
  another. The named second consumer is hermes-agent (Phase 48).
- **openclaw catalog entry** (`source_kind: script`, pin `2026.6.10`, MIT, `requires_secret:
  true`, `preserve_paths_file`) + recipe pair. `script` (not `npm`) because the recipe owns
  a full lifecycle — npm install → non-interactive no-secret onboard → self-updater freeze →
  daemon setup — the same modeling as spec-kit.
- `tests/bats/67-catalog-openclaw.bats` — 4 @tests (Docker process-level lifecycle + OPS-01
  gateway-serves + a self-gating QEMU systemd-user daemon test + offline helper trust-
  boundary + entry shape).
- `docs/internals/catalog.md` "Per-user daemons: a background service with no root" section;
  `script` source-kind bullet + roster line updated.

## Ground truth established before building (verify-before-build)

Three container probes mapped openclaw's real command surface before any recipe was written:
- Install is a clean agent-user npm global (`openclaw@2026.6.10`, Node 22 OK); state dir is
  `~/.openclaw` (0700, holds the gateway token + workspace/persona + SQLite sessions).
- Non-interactive no-secret setup = `openclaw onboard --non-interactive --accept-risk
  --auth-choice skip --skip-health` (RC 0; writes config, bakes no key).
- **ENABLE-05**: the self-updater config key is `update.auto.enabled` (NOT `autoUpdate`),
  written via `openclaw config patch --stdin` (a validated write — `config set` on a wrong
  key is schema-rejected). openclaw defaults background auto-update OFF and is notify-only,
  so the pin is authoritative out of the box; the patch makes the freeze explicit.
- **The daemon is systemd `--user`** — `openclaw daemon install` fails in Docker ("systemctl
  --user unavailable: No medium found", masked logind), so it is **QEMU-gated (ADR-007)**.
- Docker-testable liveness = the process-level Gateway: `openclaw gateway run --port N`
  reaches `[gateway] ready`; a **credential-free** `curl http://127.0.0.1:N/` → **HTTP 200**
  and (with loopback `gateway.auth.mode=none`) `openclaw health --json` → `{"ok":true}`.

## Decision: CAT-04 preserve vs "symmetric state teardown" (reconciliation)

The ROADMAP success criterion said remove "tears down the daemon + state symmetrically." In
practice `~/.openclaw` holds the user's gateway token, assistant persona/workspace,
conversation history, and any provider key added in-tool — highly personal data. The repo-
wide **CAT-04** invariant (every authenticated agent — codex, gh, glab, claude-code —
preserves its config/auth dir on `remove`, only `--purge` wipes it) governs here. So Phase 47
splits cleanly: the **daemon/service artifacts** (systemd `--user` unit, `/tmp/openclaw`
logs, the daemon marker) are torn down completely; the **user state** `~/.openclaw` is
preserved via `preserve_paths.json` + the `_should_remove` gate. The bats test asserts both
(CLI + marker gone; `~/.openclaw` kept). This is the honest, consistent behavior.

## The Docker-vs-real split (why one bats file covers both gates)

`agentlinux install openclaw` must succeed in a container (no user bus) AND on a real host.
The recipe probes `al_daemon_user_systemd_available`: where present it installs+starts the
per-user daemon; where absent it installs + configures and prints how to run the Gateway.
The QEMU harness re-runs the full bats suite in-guest, so @test 2 (systemd-user daemon
install → `daemon status loaded:true` → linger on → remove tears down + reverts linger)
`skip`s in Docker and executes on the real cloud image — no separate QEMU artifact needed.

## OPS-01 real-operation smoke (phase-close gate)

The Gateway actually serves: @test 1 starts `openclaw gateway run` and asserts a credential-
free HTTP 200 from the dashboard plus `openclaw health` reporting `ok:true`. **Passed**
(Docker 4/4, no credential — offline op per Appendix C). Recorded per the OPS-01 requirement.

## Review loop

10 reviewers (catalog-auditor, security-engineer, bash-engineer, qa-engineer,
behavior-coverage-auditor, ai-deslop, dev-docs-auditor, technical-writer, fact-checker,
external-audience-auditor). No CRITICAL/HIGH. catalog-auditor / security / dev-docs /
fact-checker / external-audience / behavior-coverage all clean/GREEN (4/4). Actionable
findings fixed:
- **qa MED** — `openclaw health` grep was whitespace-fragile → switched to `jq -r .ok`.
- **qa MED** — gateway process could survive the test → PID + `pkill -P $gwpid` reap plus a
  port-free wait. **Caught in re-verify:** the first fix used `pkill -f "openclaw gateway
  run"`, which self-matched the test's own login shell (its argv contains that literal) and
  killed the block — replaced with PID/parent-PID reap + `fuser -k <port>/tcp` in scrub.
- **bash MED** — the ENABLE-05 config-patch failure was swallowed to `/dev/null` →
  captured and surfaced (the "honest freeze" claim now matches the code).
- **bash/qa LOW** — marker count simplified to `find -printf '.' | wc -c` (newline-immune);
  dropped the dead `assert_exit_zero` on the best-effort block; capture the auth-mode set RC.
- **technical-writer / ai-deslop** — cut the double BYOK mention + logout redundancy,
  moved to third-person voice, re-wrapped the roster line, trimmed the over-commented
  warm-up ping.
Final: Docker 4/4 green on the fixed code.
