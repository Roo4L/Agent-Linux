---
gsd_state_version: 1.0
milestone: v0.3.0
milestone_name: AgentLinux Plugin (Ubuntu)
status: in_progress
stopped_at: Plan 02-03 complete — plugin/provisioner/10-agent-user.sh landed (136 lines). First dispatched provisioner: ensure_user agent + ensure_dir /home/agent 0755 + locale-gen/update-locale C.UTF-8 (with locale -a verify per RESEARCH Pitfall 5) + ensure_marker_block /home/agent/CLAUDE.md "agentlinux-doc-02" --top with all three DOC-02 anti-pattern strings. No raw state mutation. Shellcheck + shfmt + bash -n green. Marker-block round-trip byte-stable (tmp-dir smoke test). Phase 1 harness still 104/104. Wave 2 continues with 02-04 (PATH wiring, running in parallel) then 02-05 (Docker bats harness) to close Phase 2.
last_updated: "2026-04-18T14:49:00.000Z"
last_activity: 2026-04-18 — Plan 02-03 complete. One task (`type="auto"`), one commit (7bfa20d feat); ~3 min. Clean landing — no auto-fixes, no deviations, plan executed exactly as written. Locale folded into 10- (per RESEARCH latitude `20-locale.sh OR folded into 10-`). Review loop (bash-engineer + security-engineer + qa-engineer) applied inline (Task tool unavailable under frontmatter restriction); all three rubrics PASS, one iteration, no fix commits needed.
progress:
  total_phases: 6
  completed_phases: 1
  total_plans: 8
  completed_plans: 8
  percent: 25
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-18)

**Core value:** An agent can be dropped into any supported Linux system and just work — a dedicated agent user with correctly-owned Node.js, agent binaries, and config paths, so self-updates, global npm installs, and tool provisioning happen without permission fights.
**Current focus:** Phase 1 — Harness Setup (project skeleton, pre-commit, CLAUDE.md, ADRs, review subagents, skills, GH Actions scaffolding)

## Current Position

Phase: 2 of 6 (Installer Foundation + Agent User) — IN PROGRESS; Wave 1 done, Wave 2 entrypoint + first provisioner done
Plan: 02-03 ✓ complete — plugin/provisioner/10-agent-user.sh (136 lines; agent user + C.UTF-8 locale + DOC-02 CLAUDE.md)
Status: Phase 2 in progress; Wave 2 continues — 02-04 (PATH wiring, running in parallel in a separate session on plugin/provisioner/40-path-wiring.sh); 02-05 closes Phase 2 with Docker bats harness.
Last activity: 2026-04-18 — Plan 02-03 complete (1 task, 1 commit 7bfa20d, ~3 min). First dispatched provisioner lands green: ensure_user agent (no-op on re-run), ensure_dir /home/agent 0755 agent:agent (chmod+chown unconditional on existing path to correct out-of-band drift), locale step (command -v locale-gen guard + apt install locales fallback for Docker slim, `locale-gen C.UTF-8 ... || true` documented skip-path, update-locale LANG=C.UTF-8 LC_ALL=C.UTF-8, `locale -a | grep -Eiq '^c\.utf-?8$'` verify per RESEARCH Pitfall 5, `return 1` not `exit 1` so entrypoint ERR trap fires with src:line attribution), ensure_marker_block /home/agent/CLAUDE.md "agentlinux-doc-02" --top with heredoc containing all three canonical anti-pattern strings (`usr/local/bin`, `sudo npm install -g`, `second Node.js install`), chmod 0644 + chown agent:agent after ensure_marker_block (since install -m 0644 writes root-owned). Zero raw state mutation (every change routes through ensure_* primitives; chmod/chown are metadata-only idempotent). Marker-block round-trip byte-stable verified via tmp-dir smoke test: two ensure_marker_block calls with identical body around user-added preamble + appendix → diff empty, preamble + appendix preserved, block at top. Shellcheck --severity=warning --external-sources --source-path=plugin/lib + shfmt -i 2 -ci -bn -d + bash -n all green. Plan executed exactly as written — zero deviations, zero auto-fixes. Review loop (bash-engineer + security-engineer + qa-engineer rubrics applied inline under frontmatter tools-restriction) one iteration, no actionable findings. bash tests/harness/run.sh still 104/104 green.

Progress: [▓▓▓░░░░░░░] 25% (8 of ~32 plans done)

## Performance Metrics

**Velocity:**
- Total plans completed: 10 (5 v0.1.0, 5 v0.2.0)
- Average duration: ~3 min per plan

**By Phase (historical):**

| Phase | Milestone | Plans | Total | Avg/Plan |
|-------|-----------|-------|-------|----------|
| 1. Complete Website | v0.1.0 | 3 | ~6min | ~2min |
| 2. Deploy to Public | v0.1.0 | 2 | ~3min | ~1.5min |
| 3. Bootable Image | v0.2.0 | 3 | ~14min | ~4.7min |
| 4. Agent Tool Packages | v0.2.0 | 2 | ~5min | ~2.5min |
| 1. Harness Setup | v0.3.0 | 5/5 | ~49min | ~9.8min |

**v0.3.0 plan metrics:**

| Plan | Tasks | Files | Duration | Commit |
|------|-------|-------|----------|--------|
| 01-01 Skeleton + CLAUDE.md + ADRs + research | 3 | 47 created | ~4 min | 3d65cb2, fa49675, d2ca481 |
| 01-02 Pre-commit + GH workflows + mutation scaffolding | 3 | 9 created | ~3 min | d428627, 6997474, 82abda0 |
| 01-03 Review subagents + /review skill | 2 | 7 created | ~34 min | 0da6082, f1595f8 |
| 01-04 Four project-scoped skill skeletons | 2 | 4 created | ~4 min | d46f2dd, 53db3ec |
| 01-05 Harness meta-test suite (Phase 1 acceptance gate) | 3 | 9 created | ~4 min | 62a1257, c0ae0b2, f59ba60 |
| 02-01 Bash library primitives (log, distro_detect, as_user, idempotency) | 2 | 4 created | ~11 min | 1b26d6a, 0b103f1, 69bd859 |
| 02-02 Installer entrypoint rewrite (pre-parse flags + log tee + ERR/EXIT traps + provisioner dispatch) | 1 | 1 modified | ~18 min | 44208a3 |
| 02-03 Agent-user provisioner (ensure_user + C.UTF-8 locale + DOC-02 CLAUDE.md via ensure_marker_block --top) | 1 | 1 created | ~3 min | 7bfa20d |

## Accumulated Context

### Decisions

Full decision log in PROJECT.md Key Decisions table. ADR-001..ADR-010 ✓ seeded in `docs/decisions/` during Plan 01-01 (2026-04-18), each Accepted:
- ADR-001: Pivot from custom distro to installable Ubuntu plugin (v0.2.0 → v0.3.0) ✓
- ADR-002: Behavior-contract framing — requirements are BHV-XX, not INST-XX; tests are the spec ✓
- ADR-003: No default agents installed in v0.3.0 ✓
- ADR-004: Per-user npm prefix as the keystone ownership decision ✓
- ADR-005: System Node.js (NodeSource) over version managers (nvm/fnm/volta) ✓
- ADR-006: curl-pipe-bash primary + optional .deb distribution ✓
- ADR-007: Docker (fast) + QEMU (release gate) test harness; Docker-only is disqualified ✓
- ADR-008: Commander.js for the registry CLI ✓
- ADR-009: Snap is structurally disqualified as a distribution mechanism ✓
- ADR-010: Review loop triggered by CLAUDE.md instruction, not a Stop hook ✓

**New decisions from Plan 01-01 execution:**
- Copy research rather than move: `.planning/research/` and `.planning/milestones/v0.2.0-research/` kept intact; `docs/research/vX.Y.Z/` copies are byte-exact (`diff -q` verified). Archive sweep deferred to Phase 6.
- Per-task atomic commits via raw `git add <files> && git commit --no-gpg-sign`, not `gsd-tools.cjs commit` (which auto-stages all working-tree changes and breaks atomic per-task commits in sequential mode).
- CLAUDE.md deliberately references skills that arrive later in the phase (`.claude/skills/review/` in Plan 01-03, four more in Plan 01-04); flagged with "arrives in Plan 01-0X" to set reader expectations.

**New decisions from Plan 01-02 execution:**
- `.pre-commit-config.yaml` is a **verbatim copy** of `docs/HARNESS.md` §1.2; drift is detectable by a single `diff` command, making HARNESS.md the authoritative spec.
- `validate-catalog.mjs` is kept strictly zero-dep (Node built-in `fs` + `JSON.parse`); ajv swap-in deferred to Phase 4 via inline `// TODO Phase 4:` comment in the script header.
- Mutation scaffolding is non-blocking at **three independent layers**: `stryker.config.json` `thresholds.break: 0`, `nightly-mutation.yml` job-level `continue-on-error: true`, `bash-mutator.sh` always exits 0 on the current skeleton. No single layer can drag the release pipeline red.
- Every CI workflow is authored with a `compgen -G` / `[[ -x ... ]]` empty-plugin guard so skeleton-phase commits green-bar without fake test files. Guards skip jobs whose sources (tests/, bats/, CLI source) do not yet exist.
- Legacy `.github/workflows/deploy.yml` (v0.1.0 website) left completely untouched; the new `test.yml` uses `paths-ignore` for website files so the two workflows do not double-fire.

**New decisions from Plan 01-05 execution:**
- Shipped the pre-commit smoke block inside `tests/harness/run.sh` in Task 1 instead of waiting for Task 3's run.sh rewrite. Three atomic commits (62a1257 / c0ae0b2 / f59ba60) instead of two touching run.sh. Every Task 3 acceptance-criterion grep still passes because Task 1 wrote the final shape.
- Multi-path bats discovery in run.sh (PATH → ./node_modules/.bin/bats → ./tests/bats/bin/bats). PATH still wins when present; fallbacks only activate when PATH is empty. Supports three install paths: apt/brew/global-npm (PATH), `npm install --no-save bats` from repo root (node_modules), and vendored clone (tests/bats/).
- Did NOT commit bats or node_modules/ to the repo. No root package.json exists — HARNESS.md §1 doesn't declare one, and adding one for a test-time dependency would force an unrelated packaging decision. Bats install guidance lives in run.sh's error message and tests/harness/README.md (5 paths: apt, brew, npm local, npm global, docker, vendored).
- Enriched failure diagnostics: multi-item loop @tests emit `# HRN-XX: missing X` diagnostic lines on failure via `|| { echo ...; return 1; }` so TAP output identifies the exact regressed artifact. CLAUDE.md line-count test prints actual count when over budget.
- Byte-match research-migration check uses `diff -q` (matching Plan 01-01's original verification command), not md5/sha256 — same tool, greppable pairing.

**New decisions from Plan 01-04 execution:**
- CLAUDE.md left untouched (same posture as Plan 01-03): Plan 01-01's Pointers section at lines 77-79 already lists all four skill directories; grep over each slug confirmed references resolve. Success-criterion "No overlap with /review skill from 01-03" honored — all four new skills live in their own subdirectories alongside `.claude/skills/review/`.
- Skeleton body size 93-116 lines each (plan body suggested 30-80 per section / 40-80 per body; prompt's success-criterion said 50-120). Landed in the 93-116 band because every skeleton has three uncompressible parts: (1) frontmatter description naming every trigger for Claude Code's skill auto-delegation, (2) the non-negotiable rules that will not drift as later phases fill in detail (strict mode, `as_user`, mode 0440, six-mode PATH matrix, no-EACCES contract, CAT-02 invariant, SHA-verified cloud images), (3) the growth-plan section naming which artifacts absorb in which phase. Trimming any of these would either weaken the "locked rules before code exists" property or break future agents' ability to find what they need without a separate Read.
- Growth phases named in BOTH description and body (`## Growth plan` section). A future agent opening the skill knows immediately whether each section is a locked contract or placeholder awaiting Phase N.
- Requirement-ID linkage in each skill's opening paragraph — the linkage the `behavior-coverage-auditor` needs at phase-close to trace "skill X → requirement Y → test Z".
- Per-task atomic commits via raw `git add <files> && git commit --no-gpg-sign` (continuing Plans 01-01, 01-02, 01-03 pattern).

**New decisions from Plan 02-03 execution:**
- Locale folded into 10-agent-user.sh rather than split into a sibling 20-locale.sh. RESEARCH offered the split-vs-fold choice (`20-locale.sh OR folded into 10-`); folded because locale is ~10 lines, tied to user identity, and folding keeps the Phase 2 provisioner count minimal (10/40 instead of 10/20/40). Decision documented in the provisioner's header comment so it's visible at the file.
- `return 1` (not `exit 1`) on locale-verify failure. The provisioner is sourced (`. "$step"`) by the entrypoint's run_provisioners; `return 1` trips the parent's `set -euo pipefail` which fires the on_error ERR trap with proper `src:line` attribution. `exit 1` would kill the entrypoint immediately and bypass the structured-logging failure banner.
- Locale outcome regex `^c\.utf-?8$` with `-i`. Accepts both `C.UTF-8` (documentation canonical) AND `C.utf8` (the form Ubuntu 24.04 reports via `locale -a`). Matches RESEARCH Pitfall 5 verification pattern verbatim.
- `ensure_marker_block --top` placement for DOC-02 (not default `--bottom`). Anti-pattern DO-NOT guidance MUST appear before any user-added sections so agent tooling reading the CLAUDE.md encounters the DO-NOT list before making install decisions. Round-trip verified: two calls with identical body around user preamble + appendix produce a byte-stable diff, preamble + appendix both preserved.
- Stable marker tag `agentlinux-doc-02` — Phase 4/5 may extend this block with new anti-patterns but MUST reuse this exact tag. Renaming would cause the new phase's block to co-exist with the orphaned old one, breaking idempotency across versions.
- `chmod 0644 + chown agent:agent` AFTER `ensure_marker_block`. The helper uses `install -m 0644` which leaves the file root-owned; re-asserting agent:agent ownership ensures the agent user can read + edit outside the marker block on subsequent runs.
- Zero raw state mutation convention enforced: every filesystem / user change routes through `plugin/lib/idempotency.sh` primitives (`ensure_user`, `ensure_dir`, `ensure_marker_block`). `chmod` and `chown` appear only for post-helper ownership re-assertion (metadata-only, idempotent). Verified via `grep -En 'useradd|install -d|echo .*>>|sed -i' | grep -v '^[0-9]*:[[:space:]]*#'` returning empty.
- Provisioner file header contract established: `#!/usr/bin/env bash` shebang (editor syntax + shellcheck), block comment naming sourced-by parent + inherited strict mode + requirement IDs satisfied, bookend `log_info "NN-name: starting/done"` calls for greppable transcript boundaries. Future provisioners (02-04, Phase 3+) follow this shape.

**New decisions from Plan 02-02 execution:**
- Pre-parse fast-exit for --help/--version/--purge added BEFORE log-file init. Plan skeleton ordered `install -m 0644 /dev/null $LOG_FILE` before `parse_args`, which meant non-root `agentlinux-install --help` hit the root-required log-init fallback and exited 64 instead of printing usage and exiting 0 — violating the CONTEXT UX lock and the plan's own acceptance criterion (line 311). Fix: `pre_parse_args` walks argv BEFORE log-init and fast-exits for -h/--help/-V/--version/--purge (all three are print-and-exit; no state mutation). --verbose and unknown-flag diagnostics still route through the post-log-init `parse_args` so they hit the tee transcript. Committed in 44208a3.
- `trap 'wait' EXIT` (Pitfall 6 mitigation from RESEARCH.md line 699) replaced with `trap 'exec >&- 2>&-; wait "$TEE_PID" 2>/dev/null || true' EXIT`. Discovered by reproducing locally: bare `trap wait EXIT` deadlocks because the EXIT trap runs BEFORE bash drops FD 1/2 for the caller, so the tee subshell never sees EOF on its stdin and `wait` blocks forever. Correct idiom: close FD 1+2 (delivering EOF to tee), then `wait` on the saved TEE_PID (avoids accidentally waiting on unrelated background children). RESEARCH.md gets a correction during Phase 3 — for now the fix lives in the installer plus an inline comment block (lines 86-91 of `plugin/bin/agentlinux-install`).
- Provisioner glob uses `mapfile -t steps < <(compgen -G "$PROV_DIR/[0-9][0-9]-*.sh" || true)` instead of `steps=("$PROV_DIR"/[0-9][0-9]-*.sh)`. shfmt 3.8.0's lexer misparses `[0-9][0-9]` immediately after a word as an array subscript (`"[x]" must be followed by =`) and fails `shfmt -d`. `compgen -G` is a bash builtin that takes the pattern as a string — no lexer trip, same lexical ordering, `|| true` handles empty-match. Documented in-source at lines 167-172.
- SC2155 split: `readonly X="$(cmdsub)"` decomposed into `X="$(cmdsub)"; readonly X` so cmdsub failures propagate to `set -e` instead of being masked by the `readonly` wrapper. Applied to BIN_DIR / LIB_DIR / PROV_DIR.
- Function surface is a superset of plan: `pre_parse_args + parse_args + require_root + run_provisioners + main + usage + on_error`. Plan had only `parse_args + require_root + main + usage + on_error`; `pre_parse_args` is the correctness fix documented above; `run_provisioners` was pulled out of main for clarity.

**New decisions from Plan 02-01 execution:**
- Arg-count guards added to every library primitive (review-loop finding). Review loop caught that the plan's exact-shape skeletons dereference `$1`/`$2`/`$3` before checking `$#` — under the entrypoint's mandated `set -euo pipefail` (02-02), zero-arg misuse crashes with a raw `$1: unbound variable` bash diagnostic instead of routing through `log_error`. Fix: `[[ $# -lt N ]] && { log_error "usage: ..."; return 64; }` prepended to every primitive (`as_user`, `as_user_login`, `ensure_line_in_file`, `ensure_marker_block`, `ensure_user`, `ensure_dir`, `visudo_validate`). Committed in 69bd859. EX_USAGE=64 matches sysexits.h and the pre-existing `as_user foo` (no-command) branch.
- Source order locked: `log.sh → distro_detect.sh → idempotency.sh → as_user.sh`. All three downstream libs check `command -v log_error` at top and hard-fail (return 1 2>/dev/null || exit 1) if log.sh has not been sourced first. Entrypoint in 02-02 enforces the order.
- `ensure_marker_block` hardcodes mode 0644 via `install -m 0644`. Deferred for Phase 3 — no 0600 callers in Phase 2. Phase 3 will either extend signature with a 4th mode arg or carve out `ensure_marker_block_with_mode` when `~/.npmrc` (likely 0600) gets marker-block treatment.
- `AGENTLINUX_SKIP_DISTRO_CHECK=1` escape hatch ships in distro_detect.sh. Intended for bats unit sourcing on non-Ubuntu dev hosts; exports `AGENTLINUX_DISTRO_VERSION=unchecked` and logs a WARN. Documented as bats-only in file header.
- pre-commit itself not installed on executor host (expected: dev workstation, not CI image). Mitigation: ran shellcheck 0.9.0 + shfmt 3.8.0 via apt with the exact args from `.pre-commit-config.yaml` (`shellcheck --severity=warning --shell=bash --external-sources` + `shfmt -i 2 -ci -bn`). Both green on all 4 files. CI will re-run the full pre-commit stack on push.

**New decisions from Plan 01-03 execution:**
- CLAUDE.md left untouched: line 46 already pointed at `.claude/skills/review/SKILL.md` (Plan 01-01's doing). Success-criterion was to verify the pointer resolves — it does, so no silent edit was made.
- All six subagents ship with read-only tool sets (`tools: Read, Grep, Glob, Bash` — no Write/Edit) per HARNESS.md §4.2 threat-register T-03-01 mitigation. Write access can be granted when spawned outside the review loop, but the file-level restriction is the belt-and-braces layer.
- Subagent rubrics are copy-of-truth for `docs/HARNESS.md` §4.2: every rubric bullet expands a HARNESS.md §4.2 one-liner. Same pattern Plan 01-02 used for `.pre-commit-config.yaml`. Future HARNESS.md §4.2 edits require a sweep across the six subagent files — drift is detectable via diff.
- Subagent files omit `model:` frontmatter (let Claude Code infer from parent session); the plan's `<interfaces>` example only declared `name`, `description`, `tools`. Pinning `sonnet` is a trivial one-line edit if future tuning wants it.
- `/review` skill explicitly names `behavior-coverage-auditor` as the "always spawn at phase close regardless of what changed" TST-07 gate — the rule is in the dispatch-rules table (last row) and in a dedicated "Relation to TST-07" section, so no phase can close without the report.

**Carried forward from v0.2.0 (still relevant for plugin installer):**
- Node.js 22 LTS from NodeSource as the runtime baseline (install path proven)
- npm install -g for Claude Code / GSD packages (but now as the agent user, not root)
- MCP config merged into ~/.claude.json via jq (works for default-agent setup)
- Chrome install pattern for browser-access tool (now under Playwright in the v0.3.0 catalog)
- Provisioner script chain pattern (ordered numbered scripts) translates to installer phases

**Retired with pivot:**
- Debian 12 Bookworm base — superseded by "target user's existing Ubuntu"
- Packer + QEMU image build — replaced by Docker (fast) + QEMU (release gate) test harnesses
- fpm-built `.deb`s as distribution artifacts — superseded by in-installer npm install (fpm may return as the plugin's own optional .deb packaging)
- Local apt repo in image — N/A
- OpenNebula contextualization — N/A
- one-context-based agent user creation — replaced by direct useradd in installer
- chrome-devtools-mcp as the canonical browser tool — replaced by Playwright per locked decision

**New for v0.3.0:**
- Ubuntu as initial target distro (22.04 + 24.04)
- Canonical acceptance test: agent user can self-update Claude Code without sudo/EACCES (AGT-02)
- Behavior-contract framing: bats test suite is the spec
- No default agents — catalog ships claude-code, gsd, playwright as *available*; users opt in
- Phase 1 is Harness Setup (non-negotiable); restart phase numbering at 1
- Mutation testing is advisory in v0.3.0; promotion to release gate is a v0.4 decision

### Key Infrastructure Details

OpenNebula API and target VM details from v0.2.0 are no longer load-bearing. Test infrastructure for v0.3.0:
- Docker matrix (ubuntu:22.04, ubuntu:24.04) — fast, every PR (lands in Phase 2)
- QEMU with fresh Ubuntu cloud images — nightly + release gate (lands in Phase 6)

### Pending Todos

- [ ] Add PR preview deployments for website (tooling)
- [ ] Convert OG image from SVG to PNG for broader social platform support

### Blockers/Concerns

None. Roadmap created; all 46 requirements mapped; Phase 1 is ready to plan.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-04-18T14:49:00Z
Stopped at: Plan 02-03 complete — `plugin/provisioner/10-agent-user.sh` (136 lines) lands as the first dispatched provisioner. Three imperative steps (sourced-fragment; strict mode inherited from entrypoint): (1) `ensure_user agent` + `ensure_dir /home/agent 0755 agent:agent` for BHV-01 user-identity; (2) locale step — `command -v locale-gen` guard with `apt-get install -y --no-install-recommends locales` fallback for Docker slim, `locale-gen C.UTF-8 >/dev/null 2>&1 || true` (documented skip-path; glibc built-in makes this a no-op on 22.04+), `update-locale LANG=C.UTF-8 LC_ALL=C.UTF-8`, and outcome verify via `locale -a 2>/dev/null | grep -Eiq '^c\.utf-?8$'` with `return 1` on failure (trips entrypoint ERR trap); (3) DOC-02 CLAUDE.md placement via `ensure_marker_block /home/agent/CLAUDE.md "agentlinux-doc-02" --top` with heredoc body containing all three canonical anti-pattern strings (`usr/local/bin`, `sudo npm install -g`, `second Node.js install`), followed by `chmod 0644 + chown agent:agent` to re-assert agent ownership (ensure_marker_block's `install -m 0644` writes root-owned). Zero raw state mutation verified via `grep -En 'useradd|install -d|echo .*>>|sed -i' | grep -v '^[0-9]*:[[:space:]]*#'` returning empty. Marker-block round-trip byte-stable: tmp-dir smoke test ran ensure_marker_block twice with identical body around user-added preamble + appendix → diff run1 run2 empty, preamble + appendix preserved, block placed at top. Shellcheck --severity=warning --external-sources --source-path=plugin/lib + shfmt -i 2 -ci -bn -d + bash -n all green. Plan executed exactly as written (zero deviations, zero auto-fixes, one iteration of the review loop with bash-engineer + security-engineer + qa-engineer rubrics applied inline under the frontmatter tools-restriction). bash tests/harness/run.sh still 104/104 green. Summary at `.planning/phases/02-installer-foundation-agent-user/02-03-SUMMARY.md`. One commit: `7bfa20d` (feat) + plan-metadata commit after this STATE update.
Resume file: Phase 2 in progress; 02-04 (PATH wiring, parallel in a separate session on `plugin/provisioner/40-path-wiring.sh`) is the only remaining Wave 2 plan before 02-05 (Docker bats harness + CI matrix) closes Phase 2. 02-04 can assume the agent user exists, /home/agent is 0755 agent:agent, and C.UTF-8 is enforced system-wide.
