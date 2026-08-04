---
phase: 57-provisioner-port-logic-consolidation
plan: 02
subsystem: infra
tags: [rust, provisioner, clap, agent-user, locale, doc-02, require-root, musl]

# Dependency graph
requires:
  - phase: 57-01
    provides: "sysio (ensure_user/ensure_dir/ensure_marker_block), pkg (locale_ensure), distro (detect_distro), recipe_env (resolve_install_user), the AGENTLINUX_PROVISION_RUST=1 run.sh staging seam"
  - phase: 56
    provides: "clap CLI shell (cli.rs Command enum), main.rs dispatch + guard_agent_user, recipe_env typed source"
provides:
  - "The `agentlinux provision` subcommand + orchestrator shell (require_root guard, fixed ordered step vec [agent_user, sudoers, nodejs, path_wiring, registry_cli])"
  - "guard::require_root(euid) — the pre-Node EUID==0 entry guard (Pitfall 7)"
  - "provision/agent_user.rs — the 10-agent-user.sh port (useradd + locale + byte-exact DOC-02 CLAUDE.md)"
  - "provision/mod.rs shared types: Resolution / Resolutions / ProvisionCtx + seed_create()"
affects: [57-03, 57-04, 57-05, 57-06, "Wave 2 sudoers.rs", "Wave 3 nodejs.rs", "Wave 4 path_wiring.rs", "Wave 5 registry_cli + detect-decide wiring"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "require_root vs guard_agent_user split: the provision arm routes through require_root BEFORE the CLI-05 blanket guard; the six user-facing verbs keep guard_agent_user"
    - "Fixed ordered step vec (no filesystem glob) reproducing run_provisioners' numeric order; later steps are LOUD not-yet-wired markers each wave replaces"
    - "DECIDE-THEN-ACT: Resolutions seeded (seed_create) up front; steps dispatch on the token and do ONLY I/O — Wave 5 swaps the seed without restructuring the loop"
    - "DOC02 body as a single &str const round-tripping byte-exact through sysio::ensure_marker_block"

key-files:
  created:
    - rust/crates/agentlinux/src/cmd/provision.rs
    - rust/crates/agentlinux/src/provision/mod.rs
    - rust/crates/agentlinux/src/provision/agent_user.rs
  modified:
    - rust/crates/agentlinux/src/cli.rs
    - rust/crates/agentlinux/src/guard.rs
    - rust/crates/agentlinux/src/main.rs
    - rust/crates/agentlinux/src/cmd/mod.rs

key-decisions:
  - "Both plan tasks landed in ONE commit: provision/mod.rs's `pub mod agent_user` makes the step file a compile-time dependency of the orchestrator, so the entrypoint + first step are one indivisible compilable unit."
  - "--user precedence (--user > $AGENTLINUX_USER > agent) implemented in cmd/provision.rs; recipe_env::resolve_install_user already owns the env>file>agent tail, so cmd/provision only adds the --user head + a ported validate_user_name (charset + reserved denylist)."
  - "20-agent-user.bats cannot be fully GREEN in Wave 1 — its BHV-02 (path-wiring) and BHV-04 (systemd) cases are Wave-4 / Phase-59 scope. The agent-user OBSERVABLE Task 2 delivers (BHV-01 + DOC-02) is green on both distros; DOC-02 byte-fidelity proven by a direct Rust-vs-Bash diff (identical, 2264 bytes)."

patterns-established:
  - "Pattern: require_root(euid: Option<u32>) test seam mirroring guard_agent_user's invoker: None convention"
  - "Pattern: loud not-yet-wired step markers so a premature full provision run cannot silently skip a step (T-57-03 fail-loud)"

requirements-completed: [PROV-01, GATE-01, GATE-05]

coverage:
  - id: D1
    description: "`agentlinux provision` subcommand parses (six-verb surface intact) with --user/--yes/--no-yes/--dry-run/--report-only/--purge/--remove-nodejs/--report-format/--verbose"
    requirement: "PROV-01"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux/src/cli.rs#cli_parse::provision_all_flags, provision_defaults_are_all_false_and_user_none, provision_contradiction_pairs_parse_at_clap_layer"
        status: pass
    human_judgment: false
  - id: D2
    description: "provision dispatches through require_root (EUID==0), NOT guard_agent_user (Pitfall 7 / T-57-04); non-root exits 64"
    requirement: "PROV-01"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux/src/guard.rs#guard_tests::require_root_success_for_euid_zero, require_root_exits_64_for_nonroot"
        status: pass
    human_judgment: false
  - id: D3
    description: "Flag contradictions (--yes×--no-yes, --dry-run×--yes) + bad --report-format + invalid --user map to EX_USAGE(64), matching Bash parse_args"
    requirement: "PROV-01"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux/src/cmd/provision.rs#provision_tests (contradiction_*, report_format_*, validate_user_name_*, explicit_user_flag_*)"
        status: pass
    human_judgment: false
  - id: D4
    description: "provision/agent_user.rs reproduces 10-agent-user.sh: ensure_user + ensure_dir 0755 + locale_ensure C.UTF-8 + byte-exact DOC-02 CLAUDE.md (0644 <user>:<user>), dispatching on RESOLUTIONS[user]"
    requirement: "PROV-01"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux/src/provision/agent_user.rs#agent_user_tests (doc02_body_*, ensure_marker_block_frames_doc02_body_byte_exact, bail_resolution_is_defensive_error)"
        status: pass
      - kind: integration
        ref: "diff <(rust provision CLAUDE.md) <(bash provisioner CLAUDE.md) — byte-identical, 2264 bytes, agent:agent 0644 (Docker ubuntu:24.04)"
        status: pass
      - kind: e2e
        ref: "AGENTLINUX_PROVISION_RUST=1 ./tests/docker/run.sh {ubuntu-24.04,almalinux-9} 20-agent-user — BHV-01 (identity+LANG/LC_ALL+locale-a) GREEN on both"
        status: pass
    human_judgment: false
  - id: D5
    description: "The ordered step vec + loud Wave-2..5 not-yet-wired markers so a premature run fails loud instead of silently skipping a step (GATE-01/GATE-05: master Bash path unchanged, only rust/ touched)"
    requirement: "GATE-01, GATE-05"
    verification:
      - kind: unit
        ref: "grep 'not-yet-wired (Wave [2-5])' rust/crates/agentlinux/src/cmd/provision.rs; git diff --name-only HEAD~1 HEAD shows only rust/"
        status: pass
    human_judgment: false

# Metrics
duration: 12min
completed: 2026-07-28
status: complete
---

# Phase 57 Plan 02: Provisioner Orchestrator Shell + 10-agent-user.sh Port Summary

**The `agentlinux provision` entrypoint (require_root guard + fixed ordered step vec) plus the byte-faithful 10-agent-user.sh port — useradd + per-family locale + a DOC-02 CLAUDE.md that is byte-identical to the Bash-produced file on both apt and dnf distros.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-07-28T20:07:19Z
- **Completed:** 2026-07-28T20:19:23Z
- **Tasks:** 2
- **Files modified:** 7 (3 created, 4 modified)

## Accomplishments
- The `provision` subcommand + orchestrator shell every Wave 2-5 step plugs into: a clap `Provision(ProvisionArgs)` variant dispatched through `require_root` (EUID==0), NOT `guard_agent_user` (Pitfall 7 / T-57-04), with the six-verb surface byte-stable.
- `provision/agent_user.rs` reproduces `10-agent-user.sh` observable state — `ensure_user` + `ensure_dir 0755` + `locale_ensure C.UTF-8` + the DOC-02 CLAUDE.md marker block — dispatching on the `RESOLUTIONS[user]` token, consuming the Wave-0 `sysio`/`pkg` primitives as their first real caller (no hand-rolled marker/atomic logic).
- Proven byte-fidelity: the Rust-produced `/home/agent/CLAUDE.md` is **byte-identical** to the Bash-produced file (both 2264 bytes, `agent:agent` 0644, `diff` empty); the three anti-pattern strings + marker delimiters + `--top` placement all verified.
- `agentlinux-core` untouched (stays pure); master's Bash provisioner path unchanged (GATE-05) — only `rust/` changed.

## Task Commits

Both tasks landed in one atomic commit (the orchestrator's `pub mod agent_user` makes the step file a compile-time dependency — the entrypoint + first step are one indivisible compilable unit):

1. **Task 1 (provision subcommand + orchestrator shell) + Task 2 (agent_user.rs port)** — `26ba65f` (feat)

_No separate plan-metadata commit yet — the docs commit lands with STATE/ROADMAP/REQUIREMENTS updates._

## Files Created/Modified
- `rust/crates/agentlinux/src/cmd/provision.rs` (created) — the orchestrator: flag validation (contradictions + report-format → EX_USAGE 64), `--user` resolution + ported `validate_user_name`, distro detect, `Resolutions::seed_create()`, ordered step vec, loud Wave-2..5 markers, Wave-5 stubs for `--purge`/`--report-only`/`--dry-run`.
- `rust/crates/agentlinux/src/provision/mod.rs` (created) — `Resolution`/`Resolutions`/`ProvisionCtx` shared types + `seed_create()`; `pub mod agent_user`.
- `rust/crates/agentlinux/src/provision/agent_user.rs` (created) — the 10-agent-user.sh port; `DOC02_BODY` byte-exact const; RESOLUTIONS[user] dispatch; re-chmod 0644 + chown after the marker block.
- `rust/crates/agentlinux/src/cli.rs` (modified) — `Provision(ProvisionArgs)` variant + 3 new `cli_parse` rows (provision + both contradiction pairs); six-verb surface unchanged.
- `rust/crates/agentlinux/src/guard.rs` (modified) — `require_root(euid: Option<u32>)` + 2 tests (euid 0 → SUCCESS, 1000 → 64).
- `rust/crates/agentlinux/src/main.rs` (modified) — `mod provision;`; route `Command::Provision` through `require_root` in a dispatch arm before the CLI-05 blanket guard; `verb_name` exhaustiveness.
- `rust/crates/agentlinux/src/cmd/mod.rs` (modified) — `pub mod provision;`.

## Decisions Made
- **One commit for both tasks:** `provision/mod.rs`'s `pub mod agent_user;` makes `agent_user.rs` a compile-time dependency of the orchestrator, so Task 1 cannot compile (and CI cannot accept it) without Task 2's file. The entrypoint + its first step are one indivisible compilable feature.
- **`--user` precedence in cmd/provision.rs:** `recipe_env::resolve_install_user()` already owns `$AGENTLINUX_USER` > env-file > `agent`; cmd/provision.rs adds only the `--user` head and a ported `validate_user_name` (charset `^[a-z][a-z0-9_-]*$` + the reserved/system-account denylist from `remediate.sh:78-107`). The runtime UID<1000 `user_adoptable` gate is deferred to Wave 5's real detect→decide wiring (as the plan scopes it).
- **Loud not-yet-wired markers over silent skips:** the four later steps print explicit `not-yet-wired (Wave N)` lines (T-57-03 fail-loud) so a premature full run cannot silently skip a step.

## Deviations from Plan

### 1. [Rule 1 — Acceptance scope correction] `20-agent-user.bats` is not a Wave-1-completable file

- **Found during:** Task 2 verification (bats on the Rust provisioner).
- **Issue:** The plan's Task-2 acceptance names `20-agent-user.bats` GREEN, but that file's `BHV-02` (non-interactive SSH sees `/home/agent/.local/bin` on PATH) is a **Wave-4 path-wiring** observable, and `BHV-04` is a **systemd** mode (Phase-59 QEMU, explicitly out of Docker scope per the executor brief). Neither can pass while Wave 1 wires only `agent_user` + loud markers.
- **Resolution (not a code change — an acceptance interpretation):** Task 2 delivers the agent-user *observable*: **BHV-01** (user identity `:/home/agent:/bin/bash`, `/etc/default/locale` vs `/etc/locale.conf` LANG/LC_ALL=C.UTF-8, `locale -a` gate) is **GREEN on both ubuntu-24.04 and almalinux-9**, and the DOC-02 CLAUDE.md (whose byte-assertions live in `10-installer.bats`, not `20-agent-user.bats`) is proven byte-identical to the Bash output by a direct diff. The `BHV-02`/`BHV-04` reds are Wave-4 / Phase-59 scope, documented here rather than force-passed.
- **Files modified:** none (interpretation).
- **Verification:** see "Issues Encountered" for the exact bats matrix.

---

**Total deviations:** 1 (acceptance-scope interpretation; no code deviation).
**Impact on plan:** None on scope. The agent-user step is complete and byte-faithful; the un-green bats cases belong to later waves and are called out so the phase-close wave (or Wave 4) picks them up rather than assuming a false-green.

## Issues Encountered

**bats matrix on the Rust provisioner (`AGENTLINUX_PROVISION_RUST=1`):**

| Case | ubuntu-24.04 | almalinux-9 | Owner |
|---|---|---|---|
| BHV-01 user identity (`:/home/agent:/bin/bash`) | PASS | PASS | Task 2 (this plan) |
| BHV-01 locale LANG=C.UTF-8 (family file) | PASS | PASS | Task 2 |
| BHV-01 locale LC_ALL=C.UTF-8 | PASS | PASS | Task 2 |
| BHV-01 `locale -a` has C.UTF-8 | PASS | PASS | Task 2 |
| BHV-02 SSH PATH `/home/agent/.local/bin` | FAIL | PASS* | **Wave 4** (path-wiring) |
| BHV-03 cron PATH | PASS | PASS | (base image) |
| BHV-04 systemd PATH | (skip) | FAIL | **Phase 59** (QEMU systemd) |
| BHV-05/06 sudo/interactive PATH+locale | PASS | PASS | (base image / locale) |

*almalinux base image already seeds `/home/agent/.local/bin` on the SSH PATH, so BHV-02 passes there; ubuntu does not, so it fails until Wave-4 path-wiring lands. BHV-04 requires systemd PID 1 (Phase-59 QEMU per the brief — not claimable from Docker).

**DOC-02 byte-fidelity proof (direct Rust-vs-Bash diff, ubuntu:24.04 Docker):** both files 2264 bytes, `agent:agent` mode 0644, `diff` empty. All three anti-pattern greps (`usr/local/bin`, `sudo npm install -g`, `second Node.js install`) + both marker delimiters present, begin marker first (`--top`).

## Review

The review-loop dispatch table (`.claude/skills/review/`) maps `plugin/`, `tests/`, `docs/`, and config surfaces to reviewer roles; it has **no pattern matching `rust/crates/**/*.rs`** (it predates the v0.4.0 Rust rewrite). With the changed-file set entirely under `rust/`, the intersection with the table is empty, so no project subagent roles were dispatchable (limited pass). I applied the cross-cutting reliability/security/simplicity lenses via self-review: `cargo clippy -p agentlinux --all-targets -- -W clippy::pedantic` produced no provision/guard warnings; no `.unwrap()`/`.expect()`/`panic!` in production paths (all in `#[cfg(test)]`); exit codes (64 usage / 70 software) match the Bash entrypoint. No actionable findings.

## Verification Status
- `cargo test --workspace`: **287 passed, 0 failed** (was 271 at HEAD — +16: cli_parse 12, require_root 2, provision 14 incl. agent_user).
- `cargo clippy -p agentlinux --all-targets -- -D warnings`: **clean**.
- `cargo fmt --all --check`: **clean**.
- `cargo build --release --target x86_64-unknown-linux-musl -p agentlinux`: **builds**.
- Pure core: no runtime `std::process`/`std::fs` (the two grep hits are `#[cfg(test)]` drift-checks); `agentlinux-core` untouched.

## Next Phase Readiness
- The orchestrator shell + `require_root` + the ordered step vec are established once — Wave 2 (`sudoers.rs`), Wave 3 (`nodejs.rs`), Wave 4 (`path_wiring.rs`), Wave 5 (`registry_cli.rs` + the real detect→decide wiring) each register in `provision/mod.rs` and replace their loud marker in the step vec.
- **Wave 4 must land path-wiring** for `20-agent-user.bats` BHV-02 (ubuntu) to go green; **Phase 59 (QEMU)** owns BHV-04 systemd.
- `Resolutions::seed_create()` is the Wave-5 swap point: replace the seed with the ported gate computation without touching the step loop.

## Self-Check: PASSED

- Created files exist: `cmd/provision.rs`, `provision/mod.rs`, `provision/agent_user.rs`, `57-02-SUMMARY.md`.
- Task commit `26ba65f` present in git history.

---
*Phase: 57-provisioner-port-logic-consolidation*
*Completed: 2026-07-28*
