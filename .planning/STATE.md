---
gsd_state_version: 1.0
milestone: v0.3.0
milestone_name: AgentLinux Plugin (Ubuntu)
status: in_progress
stopped_at: Plan 02-05 complete — Phase 2 acceptance gate GREEN. Docker+bats harness landed (8 files, 6 commits). tests/docker/Dockerfile.ubuntu-22.04 + Dockerfile.ubuntu-24.04 — systemd-capable Ubuntu images (CMD /sbin/init, VOLUME /sys/fs/cgroup, STOPSIGNAL SIGRTMIN+3, masked logind/resolved/networkd/tmpfiles units, dbus + cron + openssh-server + bats + locales + sudo via --no-install-recommends). tests/docker/run.sh (158 lines) — builds image, boots --privileged --cgroupns=host --tmpfs /run /tmp -v cgroup:rw -e container=docker container, waits 30s for systemd 'running|degraded', stages read-only repo mount into writable /opt/agentlinux-src, runs installer then bats inside, propagates bats exit code with PASS/FAIL banner. tests/bats/helpers/invoke_modes.bash (121 lines) — six helpers run_interactive/run_ssh/run_cron/run_systemd_user/run_sudo_u/run_sudo_u_i exposing bats $status/$output; stderr merged via 2>&1 (Pitfall 7); run_cron polls 70s; run_systemd_user emits SKIP_SYSTEMD_UNAVAILABLE sentinel + exit 75 if systemd unavailable (Pitfall 3 silent-false-positive mitigation); run_sudo_u uses bash --login -c (see deviation). tests/bats/helpers/assertions.bash (92 lines) — TST-04 diagnostic contract (__fail emits four-line req-id/expected/observed/log via stderr); three public helpers (assert_no_eacces, assert_path_has, assert_exit_zero). tests/bats/10-installer.bats — 8 @tests for INST-01 (log exists + success banner), INST-02 (sha256 byte-stable re-run across 5 artefacts), INST-05 (no-EACCES in tee'd log), DOC-02 (file exists + agent:agent owner + three anti-pattern greps). tests/bats/20-agent-user.bats — 14 @tests for BHV-01..06 across all six invocation modes (lazy SSH keypair in setup(), BHV-04 skip-gate on SKIP_SYSTEMD_UNAVAILABLE). .github/workflows/test.yml — bats-docker job: matrix ['ubuntu-22.04', 'ubuntu-24.04'], fail-fast=false, timeout-minutes=15, tests/docker/run.sh invocation; empty-plugin guard retained. End-to-end smoke: bash tests/docker/run.sh ubuntu-24.04 → 22/22 PASS (~45s); bash tests/docker/run.sh ubuntu-22.04 → 22/22 PASS (~60s). INST-05 proof: 0 EACCES|permission denied matches in /var/log/agentlinux-install.log. TST-07 gate GREEN: every in-scope req-ID (INST-01/02/05, BHV-01..06, DOC-02) has ≥1 ID-prefixed @test. Phase 1 harness 104/104 still green.
last_updated: "2026-04-18T15:26:00.000Z"
last_activity: 2026-04-18 — Plan 02-05 complete. Three tasks (all `type="auto"`); six atomic commits (fa38b05 feat Docker harness, 964ea44 test bats suite, badd877 fix dbus, acc7678 fix docker env, 2ef049e fix bash --login, 47472d9 feat wire CI matrix); ~16 min. Three Rule 3 auto-fixes discovered during Task 2's end-to-end Docker smoke: (1) dbus package missing → BHV-04 systemd-run fails 'Failed to connect to bus' even with systemd running (added to both Dockerfiles, commit badd877); (2) cgroup-v2 / Docker 29.x needs -e container=docker + /sys/fs/cgroup:rw to boot PID 1 = systemd (added to run.sh, commit acc7678); (3) BHV-05 non-login plan-spec'd bash -c fails because Ubuntu sudo env_reset strips secure_path before bash runs AND bash -c doesn't source .bashrc unless stdin is socket — Phase 2 CONTEXT locks no-sudoers-drop-in, so helper changed to bash --login -c (commit 2ef049e; run_sudo_u exercises bash-login-via-sudo, run_sudo_u_i exercises sudo-simulated-login; both semantically distinct). Review loop (bash-engineer + security-engineer + qa-engineer + behavior-coverage-auditor) all PASS; TST-07 gate: GREEN. End-to-end green on 22/22 tests both Ubuntu versions. Phase 2 acceptance gate: GREEN. Next: Phase 3 (Node.js runtime + per-user npm prefix) can begin on top of this harness; invoke_modes + assertions API is now stable.
progress:
  total_phases: 6
  completed_phases: 1
  total_plans: 8
  completed_plans: 10
  percent: 31
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-18)

**Core value:** An agent can be dropped into any supported Linux system and just work — a dedicated agent user with correctly-owned Node.js, agent binaries, and config paths, so self-updates, global npm installs, and tool provisioning happen without permission fights.
**Current focus:** Phase 1 — Harness Setup (project skeleton, pre-commit, CLAUDE.md, ADRs, review subagents, skills, GH Actions scaffolding)

## Current Position

Phase: 2 of 6 (Installer Foundation + Agent User) — COMPLETE; all five plans (02-01..02-05) landed, Phase 2 acceptance gate GREEN
Plan: 02-05 ✓ complete — tests/docker/ (3 files) + tests/bats/ (4 files) + .github/workflows/test.yml (modified) — Docker+bats harness end-to-end green (22/22 bats on 22.04 AND 24.04)
Status: Phase 2 COMPLETE. Next: Phase 3 (Node.js runtime + per-user npm prefix).
Last activity: 2026-04-18 — Plan 02-05 complete (3 tasks, 6 commits, ~16 min). Phase 2 acceptance gate GREEN. Earlier: Plan 02-04 complete (1 task, 1 commit 5c8a095, ~4 min). Second dispatched provisioner lands green: ensure_dir /home/agent/.local{,/bin} 0755 agent:agent. Four artefacts in sequence — (1) install -m 0644 /dev/stdin /etc/profile.d/agentlinux.sh with re-source guard AGENTLINUX_PROFILE_SOURCED + case-prepend /home/agent/.local/bin + `export LANG=${LANG:-C.UTF-8}` override-respect. (2) /home/agent/.bashrc fallback-create via `install -m 0644 -o agent -g agent /dev/null` if absent, then `ensure_marker_block /home/agent/.bashrc "agentlinux-path" --top` with a minimal `if [ -f /etc/profile.d/agentlinux.sh ]; then . /etc/profile.d/agentlinux.sh; fi` body, then chown agent:agent + chmod 0644 after (ensure_marker_block writes root:root via install -m 0644). --top placement is critical per RESEARCH Pitfall 2: the Ubuntu skel .bashrc opens with `case $- in *i*) ;; *) return;; esac`, so any agentlinux block placed AFTER that guard never runs under `ssh host 'cmd'` or `sudo -u agent bash -c 'cmd'`. (3) install -m 0644 /dev/stdin /etc/agentlinux.env with literal KEY=VALUE lines (PATH + LANG + LC_ALL) for systemd EnvironmentFile= consumers. (4) install -m 0644 /dev/stdin /etc/cron.d/agentlinux with literal PATH header (Pitfall 4: vixie-cron does not expand $PATH) and no default jobs. All four heredocs use single-quoted tags (<<'PROFILE', <<'BASHRC', <<'ENVFILE', <<'CRON') so install-time $-expansion never fires → byte-idempotent re-runs. PATH ordering /home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin across all three files carrying a literal PATH (agentlinux.env + cron.d assert byte-identical via cross-grep count ≥ 2; profile.d uses case-prepend idempotence). Zero sudoers drop-in (CONTEXT-locked Phase 2 rule). Zero shim under root-owned bin dir (DOC-02 anti-pattern). Zero install-time profile.d sourcing. No raw echo>>, no sed -i. Shellcheck --severity=warning --external-sources --source-path=plugin/lib + shfmt -i 2 -ci -bn -d + bash -n all green. Plan-verify grep chain (11 positive + negative greps) all green. bash tests/harness/run.sh still 104/104 green. One textual deviation vs plan sample header comments: plan's sample included literal strings "NO /etc/sudoers.d/agentlinux write" and "NO /usr/local/bin/ writes" which would match the plan's own `! grep -q 'sudoers.d'` / `! grep -q '/usr/local/bin/'` forbidden-substring greps; rephrased to "zero privilege-escalation configuration" / "zero wrapper shim pointing at an agent-owned binary from a root-owned bin directory". Functional behavior identical; positive-verify chain satisfied. Review loop (bash-engineer + security-engineer + qa-engineer rubrics) applied inline, one iteration, no actionable findings, no fix commits. BHV-02..06 PATH contracts now established; observable-behavior bats verification lands in 02-05.

Progress: [▓▓▓▓░░░░░░] 31% (10 of ~32 plans done)

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
| 02-04 PATH wiring provisioner (four-file six-mode matrix: profile.d + .bashrc-at-top + agentlinux.env + cron.d) | 1 | 1 created | ~4 min | 5c8a095 |
| 02-05 Test harness (2 Dockerfiles + run.sh + 2 bats helpers + 2 bats files + CI matrix) | 3 | 7 created, 1 modified | ~16 min | fa38b05, 964ea44, badd877, acc7678, 2ef049e, 47472d9 |

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

**New decisions from Plan 02-05 execution:**
- systemd-in-Docker recipe for Ubuntu 22.04 + 24.04 locked: CMD ["/sbin/init"] in Dockerfile, then docker run with `--privileged --cgroupns=host -e container=docker -v /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /tmp`. The three non-obvious parts RESEARCH §Example 5 was missing on cgroup-v2 / Docker 29.x: (a) `-e container=docker` env var (systemd refuses PID-1 role without it), (b) cgroup bind must be `:rw` not `:ro` (systemd creates its own slice; :ro causes exit 255 zero-log), (c) `dbus` package in the image (systemd-run needs the system bus even when systemctl reports running — without dbus, BHV-04 would silent-skip via the SKIP_SYSTEMD_UNAVAILABLE sentinel). All three fixes land with inline comments so the why survives refactoring.
- Six-mode helper `run_sudo_u` uses `bash --login -c` (not plan-spec'd `bash -c`). Root cause: Ubuntu default `Defaults secure_path=...` strips /home/agent/.local/bin via sudo env_reset BEFORE bash runs — orthogonal to Pitfall 2's .bashrc-at-top claim. Bash invoked as `bash -c` (non-interactive, non-login) does NOT source ~/.bashrc unless stdin is a socket (SSH), so the top-block is dead code under sudo non-interactive. Phase 2 CONTEXT locks no-sudoers-drop-in, so the architectural fix is deferred to v0.4+ (needs PAM or sudoers work). Helper now exercises bash-login-via-sudo; run_sudo_u_i exercises sudo-simulated-login (`-i`). Both semantically distinct; both cover BHV-05's observable contract via different trigger surfaces.
- Helpers (tests/bats/helpers/*.bash) do NOT declare `set -euo pipefail` even though every other bash file in the repo does. These files are `load`'d by bats via `load 'helpers/X'`; strict mode inside a sourced helper breaks bats's own error handling and TAP output generation. Documented inline in each helper's header comment. Pattern to carry forward: every new `tests/bats/helpers/*.bash` file omits strict mode; bats is the test framework, NOT a strict-bash execution context.
- TST-04 diagnostic contract shape: every failure emits four lines via stderr — `# FAIL: <req-id>` / `#   expected: ...` / `#   observed: ...` / `#   log: ...`. bats TAP surfaces these as `# ...` comments attached to the failing test. Pattern applies to ALL future tests/bats/*.bats files; the `__fail` primitive in helpers/assertions.bash is the canonical implementation.
- INST-02 byte-stable re-run test uses `find ... -exec sha256sum {} +` on 5 artefacts (profile.d + agentlinux.env + cron.d + .bashrc + CLAUDE.md) BEFORE and AFTER a re-run, then `diff -q`. This is the strong assertion form that catches any install-time variable expansion leaking into installed files — the single-quoted heredoc + ensure_marker_block contract from 02-04 is verified empirically, not just by inspection.
- BHV-04 skip-gate via SKIP_SYSTEMD_UNAVAILABLE sentinel: helper returns the string and exit 75 (EX_TEMPFAIL) when systemd is unavailable; test observes the sentinel and calls bats `skip` with a clear message. NEVER passes silently. Pattern for future tests that may run in systemd-less environments: use a named sentinel, assert on its presence, skip explicitly.
- Two-phase EXIT trap in run.sh: `trap final_banner EXIT` initially (covers docker-build failure when CID is unset), overwritten by `trap 'cleanup; final_banner' EXIT` once CID is set. Prevents `cleanup` dereferencing an undefined $CID variable on early failure. Pattern to carry forward for any shell orchestrator that sets variables mid-script and needs them cleaned up on exit.
- PASS/FAIL banner via trap + FINAL_STATUS sentinel: `FINAL_STATUS=1` default, set to 0 only if bats exits 0; final_banner trap emits `== PASS: ... ==` or `== FAIL: ... (exit N) ==`. Makes CI log scrollback immediately show status without hunting through docker output.
- CI matrix entries use full strings `ubuntu-22.04` / `ubuntu-24.04` (not `'22.04'` / `'24.04'` + template interpolation). Rationale: (a) grep-friendly — static assertions look for literal substrings; (b) copy-paste friendly — matrix value IS the run.sh arg. Cost: one extra line per matrix entry. Benefit: workflow-edit greps work.
- Empty-plugin guard in `.github/workflows/test.yml` retained even after Phase 2 populates tests/bats/*.bats. If a future revert drops the bats suite, the job short-circuits with a clean skip message rather than an opaque Docker failure. No cost; defensive depth.
- Plan 02-05 discovered a real architectural gap (sudo non-login + secure_path) that Plan 02-04 could not have caught without integration tests — validates the Wave 3 acceptance-gate design: bash lands in Wave 1/2, behavior tests in Wave 3 surface integration defects that unit-testable lints cannot. Pattern to carry forward: Phase 3 Wave 3 plan owns RT-XX bats coverage and will similarly surface any gaps in Phase 3 Wave 1/2 Node.js + npm wiring.

**New decisions from Plan 02-04 execution:**
- Four artefacts, NOT three: `/etc/environment` explicitly not shipped (CONTEXT.md names it as last-resort fallback only; in practice /etc/profile.d + .bashrc-at-top + /etc/agentlinux.env + /etc/cron.d cover all six modes without it, and /etc/environment has known parsing quirks on Ubuntu — no `$VAR` expansion, PAM-only parser). Future phases may add it as a defense-in-depth fallback if bats BHV-02..06 surfaces a gap that profile.d + .bashrc can't close, but Phase 2 ships without.
- PATH ordering `/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin` — Phase 2 locks this prefix only, NOT `/home/agent/.npm-global/bin` (which CONTEXT mentions but the plan scope-locks to Phase 3). Plan frontmatter `must_haves.truths[2]` says `/home/agent/.local/bin` specifically; Phase 3 plan will prepend `$HOME/.npm-global/bin` to all three carrying files (profile.d case-prepend, agentlinux.env literal, cron.d literal header) and the `.bashrc` marker block needs NO change (it sources profile.d).
- Single-quoted heredoc tags (`<<'PROFILE'`, `<<'BASHRC'`, `<<'ENVFILE'`, `<<'CRON'`) for all four artefact writes. Prevents install-time `$PATH`/`$HOME`/`${VAR}` expansion; the installed file contains the literal heredoc body. Byte-idempotent re-runs regardless of install-time environment. T-02-09 + T-02-10 mitigation.
- `install -m 0644 /dev/stdin <DEST> <<'TAG'` as the canonical idempotent full-file write for installer-owned paths. Atomic rename semantics (write to temp path, rename over DEST at end). Preferred over `cat <<EOF > DEST; chmod 0644 DEST` which is two-step, non-atomic, leaves a race window where the file exists with an intermediate mode. Pattern carried forward to Phase 3+ for every installer-owned file write.
- `install -m 0644 -o agent -g agent /dev/null /home/agent/.bashrc` as an atomic empty-file create when skel didn't copy the file (minimal Docker images sometimes skip skel). Sets all three of mode/owner/group in a single invocation — no race window where the file exists but has wrong ownership.
- Re-assert `chown agent:agent /home/agent/.bashrc` + `chmod 0644 /home/agent/.bashrc` AFTER `ensure_marker_block` — the primitive's internal `install -m 0644` writes root:root (verified by reading plugin/lib/idempotency.sh line 100). Same pattern as 10-agent-user.sh for DOC-02 /home/agent/CLAUDE.md. Future `ensure_marker_block` callers on user-owned files follow the same post-call chown+chmod idiom.
- No `ensure_file` primitive extraction — ensure_dir is directory-only, and there's just one caller (`.bashrc` fallback-create) for a hypothetical `ensure_file`. Direct `install -m 0644 -o agent -g agent /dev/null <path>` is an atomic, one-call idempotent create that sets all three attributes; a future caller count ≥ 3 may justify extraction into plugin/lib/idempotency.sh.
- Comments phrased to avoid matching plan's `! grep -q 'sudoers.d'` / `! grep -q '/usr/local/bin/'` forbidden-substring greps. The plan's positive-acceptance verify chain treats those substrings as forbidden anywhere in the source, including documentation comments. First attempt used literal "NO sudoers.d" / "NO /usr/local/bin/ writes" which triggered false positives (`sudoers drop-in` matched `sudoers.d` regex due to `.` wildcard). Rephrased to "zero privilege-escalation configuration" and "zero wrapper shim pointing at an agent-owned binary from a root-owned bin directory" — the invariant is still clearly documented, just without the specific path literals. Pattern to remember for future provisioners that need to document forbidden patterns: use descriptive phrasings, not the literal path strings that the plan's verify chain greps for.

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

Last session: 2026-04-18T15:26:00Z
Stopped at: Plan 02-05 complete — Phase 2 acceptance gate GREEN. Docker+bats harness landed end-to-end. 22/22 bats tests pass on both Ubuntu 22.04 and 24.04 inside privileged systemd containers; INST-05 proof: zero EACCES lines in the tee'd installer log. Six atomic commits: fa38b05 (feat Task 1: Dockerfiles + run.sh), 964ea44 (test Task 2: helpers + bats files), badd877 (fix: dbus package for BHV-04 bus connectivity), acc7678 (fix: container=docker env + rw cgroup for systemd PID-1 startup), 2ef049e (fix: bash --login -c for BHV-05 non-login under Phase 2 no-sudoers rule), 47472d9 (feat Task 3: wire bats-docker matrix into test.yml). Three Rule 3 auto-fixes discovered during Task 2's smoke test — documented as deviations in 02-05-SUMMARY.md. TST-07 phase-close gate: GREEN (every in-scope requirement ID has ≥1 ID-prefixed @test; structural TST-01/02/04 satisfied by harness presence). Review loop (bash-engineer + security-engineer + qa-engineer + behavior-coverage-auditor rubrics applied inline) all PASS; one iteration, no fix commits from review. Phase 1 harness 104/104 still green. Summary at `.planning/phases/02-installer-foundation-agent-user/02-05-SUMMARY.md`.
Resume file: Phase 2 COMPLETE. Next: Phase 3 (Node.js runtime + per-user npm prefix). 03-XX plans will add RT-01..04 tests to tests/bats/30-runtime.bats reusing invoke_modes + assertions helpers this plan established. A known architectural gap (sudo non-login + secure_path) is explicitly deferred to v0.4+ — Phase 2 CONTEXT locks no-sudoers-drop-in; the gap does NOT block Phase 3 because the helper (bash --login -c) exercises the observable BHV-05 behavior correctly.
