# Phase 57 — Plan Check (Pre-Execution Verification)

**Checked:** 2026-07-28
**Plans:** 57-01 … 57-06 (6 plans, waves 0→5, 10 tasks)
**Verdict:** **GO-WITH-FIXES** — one BLOCKER in the Wave-5 PROV-02 deletion scope, plus targeted warnings. The port architecture, byte-fidelity front-loading, pre-Node crux, and staging seam are sound; the phase should NOT execute until the `13-reuse`/`73` orphan is resolved in plan 57-06.

---

## Verdict rationale (goal-backward)

The phase goal — a Rust `provision` entrypoint that leaves identical observable system state PRE-Node across six modes on Ubuntu 22/24/26 + AlmaLinux 9, consolidating the Bash canonical-path duplication — is **coverable by these plans**. Requirement→plan mapping is complete (PROV-01/02/03 + GATE-01/05 all present in ROADMAP and in plan frontmatter; every step has a byte-fidelity acceptance criterion and a bats file on the apt/dnf pair). Wave 0 correctly front-loads `sysio.rs` (the 6 primitives) with a byte-diff corpus, the `require_root`-not-`guard_agent_user` crux (Pitfall 7) is explicit in 57-02, the NodeSource pre-Node bootstrap (57-04) shells curl/apt/dnf via the base image, and the six-mode PATH matrix (57-05) enforces an artefact-3==artefact-4==`recipe_env` PATH invariant. The dependency chain 01→02→03→04→05→06 is linear/acyclic; core purity holds (verified: `agentlinux-core` has no live `std::process/fs/env`). Systemd/cron modes are honestly deferred to Phase 59 QEMU, not claimed from Docker.

The single blocker is a real, code-verified orphaning of existing @tests by the PROV-02 deletion — it would turn `13-reuse.bats` (20 @tests) and `73-phase51-gsd-codex.bats` (1 @test) RED, violating the plan's own GATE-01 acceptance. It is fixable inside 57-06 without re-architecting.

---

## BLOCKER (must fix before execution)

### B-1 — [context/oracle: PROV-02 deletion orphans 13-reuse.bats + 73-phase51] plan 57-06, Task 1 move D
Plan 57-06 deletes, from `plugin/lib/reuse/agents.sh`, **all** of: the `REUSE_AGENT_CANONICAL_PATHS` map, `REUSE_GSD_SYSTEM_PATH`, the `reuse::agent_decision` shim, AND `reuse::_agent_decision_bash`. It asserts (acceptance) that `13-reuse.bats` stays GREEN "driven by the in-process gate not the shim."

**This is false as written and verified against the code:**
- `tests/bats/13-reuse.bats` has **20 `@test`s** that call `run reuse::agent_decision <id>` **directly as a sourced Bash function** (via `__source_lib_chain_with_reuse` → `reuse.sh` → `reuse/agents.sh`). They do NOT invoke the `provision` entrypoint. `AGENTLINUX_RUST_BIN` is unset in these tests, so they currently exercise the `_agent_decision_bash` fallback — which reads the very map being deleted.
- Deleting the function + fallback ⇒ `reuse::agent_decision: command not found` in all 20 @tests ⇒ RED ⇒ GATE-01 violation (a newly-red file, contradicting 57-06's own acceptance).
- `tests/bats/73-phase51-gsd-codex.bats:34` (AGT-04) `grep`s `plugin/lib/reuse/agents.sh` for `gsd-core`; the `[gsd]="…/gsd-core"` map entry is exactly what the deletion removes ⇒ that @test also goes RED.

RESEARCH.md A2 only checked "no bats greps `REUSE_AGENT_CANONICAL_PATHS` (the map NAME)" — technically true, but it missed (a) tests calling the `reuse::agent_decision` FUNCTION and (b) the `gsd-core` string-grep. RESEARCH Pitfall 8 flags this exact class ("bats unit-source the Bash libs directly") but 57-06 never reconciles it for 13-reuse/73.

**Fix (pick one, keep it in 57-06):**
1. **Retain `reuse::agent_decision` + `_agent_decision_bash` + the map in `reuse/agents.sh`** (do NOT delete them) and scope PROV-02 to deleting only the *external duplicate iterators* in `remediate.sh:286-296` and `prompt.sh:110-114` — i.e. the entrypoint owns enumeration, but the unit-source oracle keeps its function. Then re-scope the `check-no-bash-canonical-map.sh` gate to assert only that no *iterator* consumes the map outside `reuse/agents.sh` (not that the map definition is gone). This is the lowest-risk path and still satisfies "single source of truth for enumeration."
2. **OR** rewrite the 20 `13-reuse.bats` @tests to drive `agentlinux reuse-decision`/the bin — but this edits the spec (the plan forbids editing bats) and is a much larger, riskier change; not recommended in a like-for-like port phase.

Until B-1 is resolved, 57-06's `check-no-bash-canonical-map.sh` "must exit ZERO" target and its "13-reuse green" acceptance are mutually inconsistent.

---

## WARNINGS (fix recommended)

- **W-1 — [key-link: recipe_env::canonical_path is private + hardcodes /home/agent]** plan 57-05. `recipe_env.rs::canonical_path(home)` is `fn` (private, not `pub`) and its test pins `/home/agent`. Plan 57-05 says "REUSE the `recipe_env` canonical PATH literal … do NOT hand-roll a second PATH string" and asserts a cross-module equality test in `path_wiring.rs`. As written, `path_wiring.rs` cannot call a private fn in another module. Fix: 57-05 must either make `canonical_path` `pub(crate)` (a one-line change it does not currently call out) or state that the invariant test lives in `recipe_env.rs`. Flag it so the executor promotes visibility rather than duplicating the literal.

- **W-2 — [scope: `provision --purge` parity is Q3-LOCKED in-phase but folded into one already-heavy task]** plan 57-06 Task 1 bundles FOUR interdependent moves (registry_cli port + full detect→decide→act wiring + `--purge`/`--dry-run`/`--report-only` parity + the Bash deletion). That is the largest single task in the phase and touches 7 files including 3 Bash deletions. It stays under the 5-task/plan cap (2 tasks) but the *single task* is dense. Consider splitting move C (`--purge`/preview parity) into its own task so a purge-teardown regression surfaces independently of the map-deletion. Not a blocker (Q3 is locked in-phase per CONTEXT deferred list; keeping it in-phase is correct), but the executor should watch context budget here.

- **W-3 — [oracle: 14-remediate.bats unit-source exposure not explicitly triaged]** plan 57-06 Task 2 lists `14-remediate` (56 @tests) as "Docker subset" but does not enumerate which of its unit-sourced functions (it sources `remediate.sh`, whose `:286-296` iterator is being deleted) might break. The deletion of the `remediate.sh` iterator is inside a `declare -p …` guard, so a sourced call likely no-ops safely — but 57-06 should add an explicit "confirm no 14-remediate @test asserts the deleted iterator's output" check alongside the 13-reuse fix, since both files source the mutated libs.

- **W-4 — [numbering: plan file N vs wave N off-by-one]** plans are numbered 57-01…57-06 for waves 0…5 (57-01 = wave 0). VALIDATION.md's skeleton called the wave-0 plan "00". Harmless (frontmatter `wave:` is authoritative and internally consistent) but worth noting so the executor doesn't mis-map a plan to a wave.

---

## Dimension summary

| Dimension | Result |
|-----------|--------|
| Requirement coverage (PROV-01/02/03, GATE-01/05) | PASS — all mapped to concrete deliverables; no assert-only requirement |
| Pre-Node crux (require_root, NodeSource bootstrap) | PASS — 57-02 Pitfall 7 explicit; 57-04 shells curl/apt/dnf pre-Node |
| Byte-fidelity (sysio Wave 0, content+mode+owner, PATH matrix) | PASS — front-loaded corpus; artefact-3==4==recipe_env invariant |
| Acceptance-oracle wiring (bats on Rust, fail-loud seam) | PASS — `AGENTLINUX_PROVISION_RUST=1`, `RUST_BIN_STAGED` fail-loud verified in run.sh |
| PROV-02 consolidation (safe deletion sequencing) | **FAIL → B-1** — deletion orphans 13-reuse (20) + 73 (1) |
| Systemd/cron honesty (defer to Phase 59) | PASS — explicitly deferred, not claimed from Docker |
| Purity + dependency soundness | PASS — core stays pure; 01→…→06 acyclic; no same-wave file collision |
| Locked-decision compliance (Q1 TS-bundle, Q3 --purge in-phase) | PASS — both honored, neither re-opened |

---

## Required fixes checklist (before GO)

- [ ] **B-1**: Re-scope 57-06 PROV-02 deletion so `13-reuse.bats` (reuse::agent_decision function) and `73-phase51` (gsd-core grep) stay green — retain the function/map, delete only the external iterators; adjust `check-no-bash-canonical-map.sh` accordingly.
- [ ] **W-1**: 57-05 — make `recipe_env::canonical_path` `pub(crate)` (or relocate the invariant test) so the PATH-equality test compiles.
- [ ] **W-3**: 57-06 — add an explicit triage line for `14-remediate.bats` against the deleted `remediate.sh` iterator.
- [ ] (optional) **W-2**: split 57-06 move C (`--purge`/preview) into its own task; **W-4**: note plan#↔wave off-by-one for the executor.

After B-1 (and ideally W-1/W-3) are addressed, this phase is **GO**.
