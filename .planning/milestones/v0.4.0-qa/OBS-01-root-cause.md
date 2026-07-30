# OBS-01 — root-cause + fix (RC-QA finding, v0.4.0 Rust build)

**Severity:** low (provision succeeds; message says "continuing") — but user-visible on EVERY greenfield provision, so an RC-polish blocker.
**Classification:** NEW reproducible — a Rust-cutover regression (upgrade from `observation` to `finding` after root-cause).

## Symptom
Greenfield `agentlinux provision` ends with:
`agentlinux provision: agentlinux adopt --all reported a problem (continuing; run it manually to retry)`
(`.planning/qa/prov-ubuntu2404.log` L281-282).

## Root cause (confirmed, not the adopt logic)
`rust/crates/agentlinux/src/cmd/adopt.rs` returns `ExitCode::SUCCESS` on a greenfield `adopt --all` (the `from(1)` paths are only name-not-found `:160` and JSON-serialize failure `:198`; the non-json `--all` loop falls to `SUCCESS` `:228`). TS parity confirms: `adopt.ts` `--all` falls off the end → exit 0. So adopt is NOT the problem.

The non-zero comes from the **provisioner dispatch** — `rust/crates/agentlinux/src/cmd/provision.rs:201-215` `run_agent_adoption`:
```rust
let r = crate::dispatcher::as_user(user, &argv, &[], false, None);  // env = &[]  <-- BUG
if r.exit_code != 0 { log::line("...adopt --all reported a problem..."); }
```
It dispatches `["agentlinux","adopt","--all"]` with an **empty env (`&[]`)**. Under `sudo -u <agent>` (invoker=root during provision), the agent's non-login PATH does NOT include `~/.npm-global/bin` (where the provisioner symlinked `agentlinux`), so the bin isn't found → dispatcher ENOENT → `exit_code 1` → the warning fires. The Bash provisioner (`agentlinux-install` `run_agent_adoption`) invoked adopt with the agent PATH established, so it did not warn on greenfield.

## Recommended fix
Give the dispatched `adopt --all` a PATH that resolves `agentlinux`. Two clean options:
1. **Pass the canonical recipe env** (preferred, parity with how recipes are dispatched): build the env via `recipe_env::full_child_env(...)` (or at least `recipe_env::canonical_path(home)` as `PATH`) and pass it as the `env` arg instead of `&[]`. This mirrors the Bash-parity PATH the recipes already get.
2. **Invoke the absolute staged path**: dispatch the symlink/target absolute path (`<home>/.npm-global/bin/agentlinux` or `/opt/agentlinux/cli/<ver>/bin/agentlinux`) instead of the bare `agentlinux`, so PATH resolution isn't needed.
Option 1 is the more faithful port. Add a unit/integration check that a greenfield `run_agent_adoption` does NOT emit the "reported a problem" line (e.g. assert the dispatched adopt exits 0 when `agentlinux` is on the provided PATH).

## Verify after fix
- Re-run a greenfield `AGENTLINUX_PROVISION_RUST` provision on ubuntu-24.04 + almalinux-9; confirm the L282 "reported a problem" line is GONE and adopt runs clean (prints per-agent "nothing to adopt — <reason>" then the provision completes without the warning).
- `cargo test --workspace` stays green; `10-installer`/`23-install-user` still green on both distros.

## Status
NOT yet fixed (checkpointed at context limit). This is the one actionable RC finding; the rest of the RC-QA campaign (almalinux-9 provision + keyless per-package lifecycles + PTY + workflow combos → the 10-latest-clean gate) is still INCOMPLETE and must be completed before RC sign-off.
