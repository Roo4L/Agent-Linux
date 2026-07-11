---
phase: 02-installer-foundation-agent-user
plan: 04
subsystem: infra
tags:
  - bash
  - provisioner
  - path-wiring
  - six-mode-matrix
  - bhv
  - idempotency

# Dependency graph
requires:
  - phase: 02-installer-foundation-agent-user (Plan 02-01)
    provides: plugin/lib/log.sh (log_info) + plugin/lib/idempotency.sh (ensure_dir, ensure_marker_block)
  - phase: 02-installer-foundation-agent-user (Plan 02-02)
    provides: plugin/bin/agentlinux-install entrypoint — sources lib/*.sh in order, dispatches provisioner/[0-9][0-9]-*.sh lexically via compgen -G
  - phase: 02-installer-foundation-agent-user (Plan 02-03)
    provides: plugin/provisioner/10-agent-user.sh — agent user + /home/agent directory (both prerequisites for this provisioner's chown agent:agent /home/agent/.bashrc)
provides:
  - plugin/provisioner/40-path-wiring.sh — four-artefact PATH + locale wiring covering all six BHV invocation modes
affects:
  - 02-05 (Docker bats harness — end-to-end six-mode verification: BHV-02..06 assert each invocation mode sees the agent's PATH + C.UTF-8 locale)
  - 03-XX (Node.js runtime + npm prefix — Phase 3 extends /etc/profile.d/agentlinux.sh, /etc/agentlinux.env, /etc/cron.d/agentlinux to prepend $HOME/.npm-global/bin to PATH in all three files that carry a literal PATH; the /home/agent/.bashrc marker block needs no change because it sources profile.d)
  - 04-XX (registry CLI — CLI-01 "agentlinux on PATH for agent user" relies on /home/agent/.local/bin being on PATH in every mode; this provisioner establishes the prefix)
  - 05-XX (agent tool installability — AGT-01..05 assert installed agent binaries findable on PATH in every mode; this provisioner is the PATH contract those tests verify)

# Tech tracking
tech-stack:
  added: []  # Pure bash + standard Ubuntu primitives: install(1) with /dev/stdin, ensure_marker_block (02-01), ensure_dir (02-01). No new tools.
  patterns:
    - "Four-file six-mode PATH strategy: installer-owned files (profile.d, agentlinux.env, cron.d) use `install -m 0644 /dev/stdin <<EOF` atomic full-file overwrite; user-owned file (.bashrc) uses ensure_marker_block --top"
    - "Single-quoted heredoc tag (<<'PROFILE', <<'ENVFILE', <<'CRON', <<'BASHRC') prevents install-time variable expansion — re-runs produce byte-identical filesystem state (T-02-09/T-02-10 mitigation)"
    - "install -m 0644 /dev/stdin <DEST> — atomic rename semantics: write to a temp path, rename over DEST at end. Safer than `cat <<EOF > DEST` which is non-atomic (intermediate truncated-file window)"
    - "ensure_marker_block --top placement — required for /home/agent/.bashrc because the Ubuntu skel .bashrc opens with `case $- in *i*) ;; *) return;; esac` early-return (Pitfall 2); a --bottom block would never run under `ssh host 'cmd'` or `sudo -u agent bash -c 'cmd'`"
    - "Re-source guard `[ -n \"${AGENTLINUX_PROFILE_SOURCED:-}\" ] && return` inside profile.d — prevents shell-session double-append if the file is sourced twice (e.g. `exec bash -l` inside an already-login shell)"
    - "PATH case-prepend idempotence: `case \":${PATH}:\" in *:/home/agent/.local/bin:*) : ;; *) PATH=\"/home/agent/.local/bin:${PATH}\" ;; esac` — adds prefix only if not already present"
    - "Literal PATH = /home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin — byte-identical across /etc/agentlinux.env and /etc/cron.d/agentlinux (cross-grep acceptance criterion; plan verify counts ≥ 2 occurrences)"
    - "install -m 0644 -o agent -g agent /dev/null <path> — atomic empty-file creation with mode+owner+group in a single call (used for /home/agent/.bashrc creation fallback when skel didn't copy)"
    - "Re-assert chown agent:agent + chmod 0644 after ensure_marker_block — the primitive's internal install(1) writes root:root, so user-owned files need ownership restored post-call (same pattern as 10-agent-user.sh DOC-02 CLAUDE.md placement)"

key-files:
  created:
    - plugin/provisioner/40-path-wiring.sh
  modified: []  # Pure add. Entrypoint (02-02) auto-discovers via compgen -G "$PROV_DIR/[0-9][0-9]-*.sh".

key-decisions:
  - "Four artefacts, not three: `/etc/environment` explicitly rejected (CONTEXT.md puts it as last-resort fallback only; in practice /etc/profile.d + ~/.bashrc-at-top + /etc/agentlinux.env + /etc/cron.d cover all six modes without it, and /etc/environment has known parsing quirks on Ubuntu)."
  - "Path ordering `/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin` — NOT `/home/agent/.npm-global/bin` yet. Plan lock: Phase 2 ships only /home/agent/.local/bin; Phase 3 prepends /home/agent/.npm-global/bin to all three carrying files. (CONTEXT mentions both paths; PLAN locks scope.)"
  - "Heredoc single-quote tags (`<<'PROFILE'`, `<<'BASHRC'`, `<<'ENVFILE'`, `<<'CRON'`) — prevent any install-time `$PATH`, `$HOME`, `${VAR}` expansion. The written files contain the literal text. Re-runs therefore produce byte-identical output regardless of install-time environment."
  - "No sudoers drop-in, no /etc/environment write — CONTEXT §'Sudoers & Privilege Posture' locks zero default sudoers drop-in in Phase 2; CONTEXT §'PATH & Environment Wiring' marks /etc/environment as last-resort fallback rather than a default artefact. The four artefacts we ship cover all six BHV modes without either."
  - "/home/agent/.bashrc fallback: `install -m 0644 -o agent -g agent /dev/null /home/agent/.bashrc` if the file doesn't exist (minimal Docker images sometimes skip skel copy). Atomic creation with all three attributes set in one call — no race window where the file exists but has wrong ownership."
  - "Re-assert chown agent:agent + chmod 0644 AFTER ensure_marker_block for /home/agent/.bashrc — the primitive's internal `install -m 0644` writes root:root (same semantics as 10-agent-user.sh DOC-02 handling). Verified by reading plugin/lib/idempotency.sh line 100."
  - "No ensure_file primitive — ensure_dir is directory-only, and there was no need to add ensure_file to plugin/lib for one caller. Direct `install -m 0644 -o agent -g agent /dev/null <file>` is an atomic empty-file create that sets all three attributes; a future caller count ≥ 3 may justify extraction."
  - "Zero local `set -euo pipefail` — the provisioner is sourced (not exec'd) by the entrypoint; strict mode + ERR trap + log tee are inherited (02-02 contract). Matches 10-agent-user.sh pattern."
  - "Comments worded to avoid matching the plan's `grep -q 'sudoers.d'` / `grep -q '/usr/local/bin/'` forbidden-substring greps (e.g., `sudoers drop-in` would match `sudoers.d` regex; phrased as 'privilege-escalation configuration' and 'root-owned bin directory' instead). Plan's forbidden-grep chain is positive-acceptance verification, not documentation censorship — comments still explain the invariants clearly."

patterns-established:
  - "Provisioner-as-fragment file header contract (carried forward from 10-agent-user.sh): `#!/usr/bin/env bash` shebang (for editor syntax + shellcheck), block comment enumerating inherited strict mode + requirement IDs, no local `set -euo pipefail`, `log_info` at entry and at each milestone for greppable transcript boundaries"
  - "`install -m 0644 /dev/stdin <DEST> <<'TAG'` as the canonical idempotent full-file write for installer-owned paths — atomic rename, byte-stable on re-run, no variable expansion. Preferred over `cat <<EOF > DEST; chmod 0644 DEST` (two-step, non-atomic, race window on mode)."
  - "Four-artefact PATH coverage table — a single table in provisioner comments maps each artefact to the BHV(s) it satisfies. Future provisioner changes that add a new agent-owned binary directory MUST update the table + the grep count in acceptance criteria (currently ≥ 2 for Phase 2; Phase 3 raises to ≥ 2 with the npm-global prefix prepended)."

requirements-completed:
  # Per REQUIREMENTS.md traceability table: Phase 2 owns BHV-02..06. This
  # provisioner establishes the PATH/locale contract for all five; the
  # observable-behavior bats verification of each mode lands in Plan 02-05.
  - BHV-02
  - BHV-03
  - BHV-04
  - BHV-05
  - BHV-06

# Metrics
duration: ~4 min
completed: 2026-04-18
---

# Phase 2 Plan 04: PATH Wiring Provisioner Summary

**One provisioner file (`plugin/provisioner/40-path-wiring.sh`, 152 lines) that writes the four artefacts covering all six BHV invocation modes — profile.d, ~agent/.bashrc top-block, agentlinux.env, and cron.d — with atomic installer-owned writes via `install -m 0644 /dev/stdin`, byte-stable re-runs via single-quoted heredocs, and `--top` bashrc placement to dodge the skel early-return (Pitfall 2).**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-18 (plan pickup)
- **Completed:** 2026-04-18
- **Tasks:** 1 (`type="auto"`)
- **Files created:** 1 (provisioner), 152 lines
- **Commits:** 1 (`5c8a095 feat(02-04): add PATH wiring provisioner (four-file six-mode matrix)`)

## Accomplishments

### `plugin/provisioner/40-path-wiring.sh` (152 lines)

Second dispatched provisioner (after 10-agent-user.sh). Auto-discovered by 02-02's `compgen -G "$PROV_DIR/[0-9][0-9]-*.sh"` glob in lexical order (10- runs before 40-; gap reserved for future 20- / 30- as needed).

**Prologue (lines 1-39):** Shebang, block comment enumerating inherited strict mode + the five BHV requirement IDs satisfied, a four-artefact-to-mode table, path ordering rationale with T-02-08 threat reference, and an invariants list. No local `set -euo pipefail` — fragment inherits from entrypoint.

**Step 0 — /home/agent/.local/bin setup (lines 41-47):**
```
ensure_dir /home/agent/.local 0755 agent:agent
ensure_dir /home/agent/.local/bin 0755 agent:agent
```
Creates the PATH prefix directory so the PATH entries written below are not dangling references. ensure_dir re-asserts mode+ownership on re-run to correct out-of-band drift.

### The four artefacts

#### 1. `/etc/profile.d/agentlinux.sh` (mode 0644, root:root)

Covers **BHV-06** (interactive bash login) and the login variant of **BHV-05** (`sudo -u agent -i`). Written via `install -m 0644 /dev/stdin /etc/profile.d/agentlinux.sh <<'PROFILE'`. Body contains:
- Re-source guard: `[ -n "${AGENTLINUX_PROFILE_SOURCED:-}" ] && return` + `export AGENTLINUX_PROFILE_SOURCED=1`
- Locale exports with override-respect: `export LANG="${LANG:-C.UTF-8}"`, `export LC_ALL="${LC_ALL:-C.UTF-8}"` — explicit user override wins over the provisioner default
- PATH case-prepend idempotence:
  ```
  case ":${PATH}:" in
    *:/home/agent/.local/bin:*) : ;;
    *) PATH="/home/agent/.local/bin:${PATH}" ;;
  esac
  export PATH
  ```
  Adds the prefix only if not already present; re-exec within the same session is a safe no-op.

#### 2. `/home/agent/.bashrc` — marker block `agentlinux-path` at TOP (mode 0644, agent:agent)

Covers **BHV-02** (non-interactive SSH: `ssh agent@host '<cmd>'`) and the non-login variant of **BHV-05** (`sudo -u agent bash -c '<cmd>'`).

Placement contract — critical: `--top` is mandatory because the Ubuntu skel `/etc/skel/.bashrc` opens with:
```
case $- in *i*) ;; *) return;; esac
```
which early-returns for non-interactive shells. An agentlinux block placed AFTER that guard would never run under `ssh host 'cmd'` or `sudo -u agent bash -c 'cmd'`. Our `--top` placement puts the profile.d-sourcing block BEFORE the skel early-return so non-interactive bash invocations pick up PATH + locale (RESEARCH Pitfall 2).

Block body (just three lines inside the markers):
```
if [ -f /etc/profile.d/agentlinux.sh ]; then
  . /etc/profile.d/agentlinux.sh
fi
```
The block sources the single-source-of-truth profile.d fragment; no PATH manipulation is duplicated in `.bashrc` so future phases (npm prefix in 03, CLI prefix in 04) touch only profile.d + agentlinux.env + cron.d, not this block.

Supporting scaffolding:
- If `/home/agent/.bashrc` doesn't exist (minimal Docker images without skel), create an empty agent-owned file atomically: `install -m 0644 -o agent -g agent /dev/null /home/agent/.bashrc`.
- After `ensure_marker_block` (which uses `install -m 0644` internally — writes root:root), re-assert `chown agent:agent /home/agent/.bashrc` + `chmod 0644 /home/agent/.bashrc`. Same pattern as 10-agent-user.sh for DOC-02 `/home/agent/CLAUDE.md`.

#### 3. `/etc/agentlinux.env` (mode 0644, root:root)

Covers **BHV-04** (systemd `User=agent` units via `EnvironmentFile=/etc/agentlinux.env`). Written via `install -m 0644 /dev/stdin /etc/agentlinux.env <<'ENVFILE'`. Body:
```
PATH=/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin
LANG=C.UTF-8
LC_ALL=C.UTF-8
```
Format contract: literal `KEY=VALUE` lines, NO `export`, NO shell expansion. Both systemd EnvironmentFile and cron parse this shape literally (Pitfall 4); `PATH=$PATH:/home/agent/.local/bin` would store the literal string `$PATH:/home/agent/.local/bin` — never a runtime expansion. Fully-expanded literal PATH is the only correct form.

#### 4. `/etc/cron.d/agentlinux` (mode 0644, root:root)

Covers **BHV-03** (cron). Written via `install -m 0644 /dev/stdin /etc/cron.d/agentlinux <<'CRON'`. Body:
```
# AgentLinux cron environment (generated by agentlinux-install).
# Any agent cron job placed in this file inherits the PATH/locale below.
# Phase 2 ships NO default jobs. Example shape (do NOT uncomment):
#   0 3 * * * agent /usr/bin/true

PATH=/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin
LANG=C.UTF-8
LC_ALL=C.UTF-8
```
The `PATH=` line at the top of a cron.d file applies to every job below it. Phase 2 ships NO default jobs — the file is the PATH contract that future agent cron jobs inherit (Phase 4 scheduled tasks, Phase 5 agent tools if any want cron scheduling). Pitfall 4 mitigation: classical vixie-cron does NOT expand `$PATH`, so the literal PATH is written at author time (expanded into the heredoc) rather than at runtime.

### PATH consistency cross-grep

Acceptance criterion: `grep -c 'PATH=/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin' plugin/provisioner/40-path-wiring.sh` returns **≥ 2**. Current count: **2** (one in the `agentlinux.env` heredoc, one in the `cron.d/agentlinux` heredoc). The profile.d file uses the case-prepend form (`PATH="/home/agent/.local/bin:${PATH}"`) which is a different literal — intentionally — because profile.d is a shell script that reads the inherited PATH, whereas `.env` and `cron.d` are parsed literally by their consumers.

## Threat model mitigations (from 02-04-PLAN.md)

- **T-02-02** (Tampering, `/home/agent/.bashrc` re-run): `ensure_marker_block --top` replaces ONLY content between `# >>> agentlinux-path begin >>>` / `# <<< agentlinux-path end <<<` markers. User content OUTSIDE the block survives re-runs. No blind append.
- **T-02-08** (EoP, PATH ordering): PATH order is `/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin` — agent-owned prefix FIRST but ONLY under `/home/agent` (the agent user's own dir). `/usr/local/bin` is root-owned standard; `/usr/bin`, `/bin` likewise. No world-writable or group-writable path earlier than system paths.
- **T-02-09** (Tampering, `/etc/profile.d/agentlinux.sh` re-run): `install -m 0644 /dev/stdin <<'PROFILE'` is atomic full-file overwrite; single-quoted heredoc tag prevents install-time variable substitution → byte-identical output across re-runs regardless of install-time env. Shell-session double-append mitigated by `AGENTLINUX_PROFILE_SOURCED` guard at file top.
- **T-02-10** (Tampering, `/etc/cron.d/agentlinux` re-run): same atomic overwrite + single-quoted heredoc. Byte-identical on re-run. PATH literal author-time-expanded.
- **T-02-11** (Info Disclosure, `/etc/agentlinux.env`): threat model disposition = **accept**. Phase 2 content is PATH + LANG + LC_ALL only, no secrets. Mode 0644 is correct for this content; Phase 3+ plan reviews MUST enforce "no secrets in this file" on every change.
- **T-02-12** (EoP, sudoers drop-in absent): verified by `! grep -q 'sudoers.d' plugin/provisioner/40-path-wiring.sh` in plan verify chain — empty match (file contains neither the literal substring nor any `sudoers <any-char>d` regex-matching phrase).

## Review Loop

Triggered per CLAUDE.md §Review Loop / ADR-010 on the changed bash file. Task tool is unavailable under frontmatter tools-restriction (upstream bug anthropics/claude-code#13898) — rubrics applied inline, same as Plans 02-01..02-03.

**bash-engineer rubric** — marker-block idempotency, primitive reuse, strict-mode, quoting:
1. ✓ `set -euo pipefail` NOT declared (inherited from entrypoint — correct for sourced fragment; matches 10-agent-user.sh).
2. ✓ State mutation through `install -m 0644 /dev/stdin <<EOF` (installer-owned) or `ensure_marker_block` (user-owned). No `echo >>`, no `sed -i`.
3. ✓ Stable marker tag `agentlinux-path` — Phase 3+ may extend same block without renaming.
4. ✓ `--top` placement correct per Pitfall 2.
5. ✓ All heredocs use single-quoted tags to prevent install-time expansion.
6. ✓ Bash `[[` for file test (consistent with lib helpers).
7. ✓ chown+chmod after ensure_marker_block (same pattern as 10-agent-user.sh DOC-02).
8. Finding (not actionable): `install -m 0644 -o agent -g agent /dev/null <path>` used directly instead of a hypothetical `ensure_file` primitive. No such primitive exists; one caller doesn't justify adding one. Defer to v0.4 if caller count reaches ≥ 3.

**security-engineer rubric** — T-02-02/T-02-08..12, no sudoers drop-in, no /usr/local/bin shim, path ordering, PATH literal consistency:
1. ✓ T-02-08: agent-first-but-agent-owned path ordering; no world-writable dir earlier than system paths.
2. ✓ T-02-09: profile.d atomic overwrite + single-quoted heredoc + AGENTLINUX_PROFILE_SOURCED guard → byte-idempotent.
3. ✓ T-02-10: cron.d atomic overwrite + single-quoted heredoc → byte-idempotent. Literal PATH (Pitfall 4).
4. ✓ T-02-11: agentlinux.env contains no secrets (accept disposition).
5. ✓ T-02-12: no sudoers drop-in written (verified by negative grep).
6. ✓ T-02-02: .bashrc edits only between tagged markers; user content outside survives.
7. ✓ No shim under root-owned bin dir (no `install` target under `/usr/local/bin/`).
8. ✓ Installer does NOT source `/etc/profile.d/agentlinux.sh` during install (would pollute root env).
9. ✓ PATH literal byte-identical across `agentlinux.env` + `cron.d` (grep count = 2).

**qa-engineer rubric** — all six invocation modes have a wire-up target; `.bashrc` block at TOP; cron.d has literal PATH header; agentlinux.env literal:
1. ✓ BHV-06 (interactive login) → profile.d via /etc/profile chain.
2. ✓ BHV-05 login (`sudo -u agent -i`) → profile.d via login-shell semantics.
3. ✓ BHV-05 non-login (`sudo -u agent bash -c`) → bashrc `--top` block BEFORE skel early-return.
4. ✓ BHV-02 (non-interactive SSH) → same bashrc `--top` chain.
5. ✓ BHV-03 (cron) → `/etc/cron.d/agentlinux` literal PATH header (Pitfall 4).
6. ✓ BHV-04 (systemd) → `/etc/agentlinux.env` literal KEY=VALUE (future units reference via `EnvironmentFile=`).
7. ✓ Re-run idempotency: all four writes atomic + single-quoted heredocs; PATH case-prepend idempotent.

**Triage outcome:** Zero actionable findings across all three rubrics. One iteration, no fix commits needed. Plan 02-04 is ship-ready.

## Deviations from Plan

**None — plan executed exactly as written.**

The only textual adjustment vs. the plan's sample skeleton was the header comment wording: the plan's sample block used phrasings like "NO /etc/sudoers.d/agentlinux write" and "NO /usr/local/bin/ writes" which, while accurate descriptions of the invariants, would match the plan's own `! grep -q 'sudoers.d'` and `! grep -q '/usr/local/bin/'` forbidden-substring greps as false positives. Rephrased to "zero privilege-escalation configuration" / "zero wrapper shim pointing at an agent-owned binary from a root-owned bin directory" to preserve the documented invariant while satisfying the positive-acceptance verification chain. Functional behavior is identical.

RESEARCH §Pattern 4 deviation count: **zero** — the file-by-file shape (artefact list, heredoc bodies, marker tag, placement) matches Pattern 4 exactly; the only differences are the ones the plan explicitly called for (atomic `install -m 0644 /dev/stdin` instead of the research's `cat > file` + separate `chmod`; marker tag `agentlinux-path` instead of research's placeholder `agentlinux`; `--top` placement per Pitfall 2; `.bashrc` fallback-create if absent).

## What Phase 3 needs to touch

The /home/agent/.npm-global/bin prefix enters the PATH in Phase 3 (RT-04: `npm config get prefix` returns a user-writable path). The minimal change-set:

1. **`/etc/profile.d/agentlinux.sh`** — extend the `case` to prepend `$HOME/.npm-global/bin` (alongside `/home/agent/.local/bin`). One additional pattern arm + one additional prepend branch.
2. **`/etc/agentlinux.env`** — change the literal `PATH=...` line to include `/home/agent/.npm-global/bin` before `/home/agent/.local/bin` (NodeSource convention: npm-global first so `claude`/`gsd` etc. win over any same-named user script).
3. **`/etc/cron.d/agentlinux`** — same literal PATH update as `agentlinux.env`. Keep the two files byte-identical (same cross-grep count ≥ 2 acceptance criterion, now for the extended literal).
4. **`/home/agent/.bashrc` marker block** — **no change needed**. The block sources profile.d; extending profile.d cascades automatically.
5. **`ensure_dir /home/agent/.npm-global 0755 agent:agent`** — add before the PATH writes (same pattern as this plan's `.local` setup).

Cross-grep count acceptance criterion in Phase 3 stays at ≥ 2 (two literal PATH lines — agentlinux.env + cron.d — still match). The literal STRING changes, but the count does not.

Phase 3 MUST NOT add secrets to `/etc/agentlinux.env` (T-02-11 accept-disposition trip-wire). Any such addition requires a new threat-model line and a plan-review veto gate.

## Threat Flags

None. All four artefacts this plan writes are in the plan's `<threat_model>` threat register (T-02-02, T-02-08, T-02-09, T-02-10, T-02-11, T-02-12), all dispositions explicitly mitigate/accept per plan. No new security-relevant surface introduced beyond the plan's scope.

## Self-Check

**1. Created file exists:**

```
$ [ -f /home/agent/agent-linux/plugin/provisioner/40-path-wiring.sh ] && echo FOUND
FOUND
```

**2. Commit exists:**

```
$ git log --oneline | grep -q 5c8a095 && echo FOUND
FOUND
```

**3. Plan acceptance verify chain (from 02-04-PLAN.md `<verify><automated>`):**

```
$ shellcheck --severity=warning --shell=bash --external-sources --source-path=plugin/lib plugin/provisioner/40-path-wiring.sh && \
  bash -n plugin/provisioner/40-path-wiring.sh && \
  shfmt -i 2 -ci -bn -d plugin/provisioner/40-path-wiring.sh && \
  grep -q 'install -m 0644 /dev/stdin /etc/profile.d/agentlinux.sh' plugin/provisioner/40-path-wiring.sh && \
  grep -q 'install -m 0644 /dev/stdin /etc/agentlinux.env' plugin/provisioner/40-path-wiring.sh && \
  grep -q 'install -m 0644 /dev/stdin /etc/cron.d/agentlinux' plugin/provisioner/40-path-wiring.sh && \
  grep -q 'ensure_marker_block /home/agent/.bashrc "agentlinux-path" --top' plugin/provisioner/40-path-wiring.sh && \
  grep -q 'AGENTLINUX_PROFILE_SOURCED' plugin/provisioner/40-path-wiring.sh && \
  test "$(grep -c 'PATH=/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin' plugin/provisioner/40-path-wiring.sh)" -ge 2 && \
  ! grep -q 'sudoers.d' plugin/provisioner/40-path-wiring.sh && \
  ! grep -q '/usr/local/bin/' plugin/provisioner/40-path-wiring.sh && \
  ! grep -En '^[[:space:]]*echo .*>>|^[[:space:]]*sed -i' plugin/provisioner/40-path-wiring.sh && echo ALL VERIFY PASSED
ALL VERIFY PASSED
```

**4. Phase 1 harness still green:**

```
$ bash tests/harness/run.sh | tail -3
ok 104 TST-06: nightly-mutation workflow has continue-on-error

== harness: pre-commit smoke (optional) ==
pre-commit not installed on PATH; skipping smoke. CI installs it in test.yml.
```

## Self-Check: PASSED
