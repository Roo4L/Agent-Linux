# Phase 15: Pre-flight UX — Context

**Gathered:** 2026-05-25
**Status:** Ready for planning
**Mode:** Smart-discuss (autonomous batch-table, accept-all)

<domain>
## Phase Boundary

A user invoking `agentlinux install` on a brownfield host gets the right experience for their context:

- **`--dry-run`** (UX-01): runs the full Phase 12-14 detection → decision pipeline, prints the Reuse/Create/Remediate/Bail report, exits 0 without writing any state. Re-running `agentlinux install` immediately after produces identical detection output (dry-run is observably non-mutating).
- **TTY per-action prompts** (UX-02): when stdin is a TTY, after the pre-flight report each state-overwriting Remediate action (REMEDIATE-01 chown, REMEDIATE-03 sudoers drift overwrite, REMEDIATE-04 reinstall-broken) issues `Proceed with this remediation? [Y/n]`. Decline = skip that one remediation, log a warning, continue with the rest. Additive actions (PATH wiring, missing-file sudoers install, fresh-component Create) run unconfirmed. `--yes` auto-approves every prompt in TTY mode too.
- **Alt-user flow** (UX-04): when DET-01 surfaces an incompatible existing install user (wrong shell, no writable home, conflicting UID, or `--user=` mismatch), interactive mode prompts for an alternate name with a numerically-suffixed default offer (`agent2`); non-interactive mode bails with exit code 65 (`EX_DATAERR`) and a remediation hint that names the conflicting attribute and suggests `--user=NAME`.
- **JSON report shape**: keep the Phase 12 `jq -n` dump as-is. **No schema file, no version field, no ADR.** Consumers (bats tests + Phase 16 docs) ARE the spec.

**Greenfield invariant:** a fresh container's `agentlinux install --dry-run` reports every component as `absent → Create`; running `agentlinux install` after the dry-run produces a v0.3.0-identical greenfield install (66/66 bats green).

</domain>

<decisions>
## Implementation Decisions

### Locked (user-confirmed via smart-discuss batch table 2026-05-25)

**D-15-01 — `--dry-run` exit code: always 0**
- `--dry-run` is a pure preview. It exits 0 regardless of what the report contains (including Bail components). The bails surface IN the report, not as an exit code.
- Rationale: matches spec literal ("exits 0 without writing any state"); aligns with Unix preview-flag convention (`apt --simulate`, `terraform plan` exit 0 even when changes are pending).
- Mirror in non-dry-run: bails STILL exit 65 in real-install mode per UX-03/UX-05.

**D-15-02 — TTY decline-and-continue sentinel: `status: "reused-with-warning"`**
- When a TTY user declines a per-action prompt, AgentLinux skips THAT remediation, writes a sentinel with `status: "reused-with-warning"` and `decline_reason: "<short reason>"` (one of `chown-declined`, `sudoers-drift-declined`, `reinstall-broken-declined`), and continues with the rest of the install.
- `agentlinux list` renders this as: `claude-code (reused — declined remediation: chown-declined; manual fix needed)`.
- Rationale: consistent with `feedback_aggressive_ownership.md` (AgentLinux adopts and manages reused user-installed binaries — same applies when user explicitly declines our fix). Decline ≠ unmanaged; it just means user opted to keep current state.
- Widens the Sentinel status union to: `"installed" | "reused" | "broken-after-remediate" | "reused-with-warning"`.
- TS type lives in `plugin/cli/src/types.ts` (extends Phase 14's union).

**D-15-03 — JSON report finalization: MINIMUM-VIABLE (drop ceremony from spec)**
- **Keep:** Phase 12's `jq -n` dump format unchanged. Bats grep-on-fields is the de-facto contract.
- **Drop:** schema file at versioned path, schema-version field, ADR for breaking changes, `jq`-parses-every-documented-field CI smoke.
- **Add (Phase 16):** README "Brownfield install" section lists the top-level keys with a one-line gloss each (this is the human-readable spec).
- Rationale: matches user's repeated avoid-ceremony pushback (DET-06 amendment, `feedback_avoid_ceremony.md`). The original success criterion #4 was bundled from boilerplate roadmap text without re-checking against the user's stated preference. Phase 16 README docs cover discoverability without the schema-+-ADR overhead.
- **Success-criteria amendment**: replace original SC#4 ("schema is published at a stable, versioned path; jq CI smoke; ADR for breaking changes") with "JSON report shape is stable AND grep-tested by bats; README documents the top-level keys; no schema file or version field required."

**D-15-04 — `--dry-run --yes` combo: reject as contradictory (exit 64 EX_USAGE)**
- Pattern: argv parser at first occurrence emits `agentlinux-install: contradictory flags — --dry-run forbids --yes (dry-run never mutates; --yes is a mutation gate)` to stderr and exits 64.
- Symmetric: `--yes --dry-run` also rejected.
- Rationale: Unix convention rejects contradictory flags upfront (matches existing T-14-02 `--yes`/`--no-yes` rejection pattern). Avoids ambiguity about which flag wins.

### Implicit from spec text (no discussion needed — already locked by phase goal + success criteria)

- **D-15-05 — TTY detection mechanism**: `[[ -t 0 ]]` on bash entrypoint stdin. Single source of truth; no per-call probing.
- **D-15-06 — Per-action prompt format**: `Proceed with this remediation? [Y/n] ` (capital Y = default-yes). Skipping flushed pending bails first, then runs prompts in component-order (user, nodejs, sudoers, agents).
- **D-15-07 — Alt-user numeric suffix**: scan `/etc/passwd` for the first free `agent<N>` starting at N=2. Offer it as the prompt default; accept Enter = use suggested name; accept typed name = use that name (subject to standard validation — `[a-z][a-z0-9_-]*`).
- **D-15-08 — Non-interactive alt-user bail message**: `agentlinux: existing user "agent" is incompatible (<reason>). Re-run with --user=<suggested_name> or fix the existing user manually.` Exit code 65.
- **D-15-09 — Additive actions never prompt**: PATH wiring, missing-file sudoers install, and fresh-component Create paths run without TTY confirmation (matches spec text).
- **D-15-10 — `--yes` in TTY mode auto-approves**: same flag, same semantics across TTY and non-TTY (spec text explicitly extends `--yes` to TTY mode).
- **D-15-11 — Skipped-remediation log format**: `[REMEDIATE-NN] DECLINED by user — skipping <component>; install continues (state will be marked reused-with-warning)` to install log; matches existing `[REMEDIATE-NN]` grep-stable marker convention from Phase 14.

### Claude's Discretion

- Exact prompt-rendering library/helper (bash `read -r -p` vs a tiny wrapper; both acceptable)
- TUI-loop pacing — whether the prompt loop runs inside `remediate.sh` or inside a new `prompt.sh` helper module
- Exact bash variable names for prompt state
- Test fixture mechanics for TTY simulation (`script(1)`, `unbuffer`, or PTY via expect — whichever the test author finds simplest within bats)
- Whether `--dry-run` output suppresses the trailing summary table vs always emits it (style choice; default to "always emit" for consistency)
- Color/no-color handling for prompts (likely re-use existing log_warn coloring)

</decisions>

<code_context>
## Existing Code Insights

**Phase 14 contract that Phase 15 builds on:**
- `plugin/lib/remediate.sh::remediate::collect_all_decisions` already populates RESOLUTIONS map + BAILED_COMPONENTS array BEFORE any mutation
- `remediate::flush_bails_or_continue` runs at main() level before provisioners — this is the natural injection point for per-action TTY prompts (between flush_bails and run_provisioners)
- DECIDE-THEN-ACT pattern is the load-bearing architecture; Phase 15 leverages it for `--dry-run` (collect decisions, skip flush_bails+provisioners entirely)
- `plugin/bin/agentlinux-install` already parses `--yes`, `--no-yes`, `--report-format=text|json`, `--report-only`, with T-14-02 contradiction handling
- Exit codes 64/65/1/0 already declared `readonly` near top of entrypoint
- `plugin/cli/src/state/sentinel.ts` Sentinel status union already widened in Phase 14 to include `"broken-after-remediate"` — Phase 15 adds `"reused-with-warning"` to the same union

**Reusable assets:**
- `plugin/lib/log.sh::log_warn` for skipped-remediation warnings
- `plugin/lib/detect/*.sh` for the dry-run discovery pass (already pure-read, no changes needed)
- `tests/bats/helpers/brownfield.bash` for TTY-fixture brownfield setups (will need a new `setup_tty_brownfield_<scenario>` per UX-02 prompt test)

**Patterns to match:**
- Phase 14 `tryRemediate` in `plugin/cli/src/commands/install.ts` for the CLI path (Phase 15 may extend it for the TTY prompt loop, OR keep all TTY interactivity in the bash entrypoint and have the CLI inherit via subprocess)
- `[REMEDIATE-NN]`, `[DET-NN]`, `[REUSE-NN]`, `[BAIL]` grep-stable log markers — Phase 15 adds `[PROMPT-NN]` markers for the prompt-loop events (presented, accepted, declined)

**Integration points:**
- Bash entrypoint: argv parser (new `--dry-run`), main() (new dry-run branch that exits after report)
- TS CLI: `index.ts` Commander option `--dry-run`, `install.ts` early-return path
- Sentinel writer: new status case for `reused-with-warning`
- List renderer: new suffix for `reused-with-warning` entries

</code_context>

<specifics>
## Specific Ideas

**TTY decline behavior — concrete walkthrough**

1. Detection finds: REMEDIATE-01 (npm prefix wrong-owner) + REMEDIATE-03 (sudoers drifted) + REUSE-02 (Node 22 healthy) + Create user
2. After report prints, prompt loop runs:
   - `Proceed with REMEDIATE-01 (chown ~agent/.npm-global to agent:agent)? [Y/n] ` → user types `n`
   - `Proceed with REMEDIATE-03 (overwrite /etc/sudoers.d/agentlinux with catalog version)? [Y/n] ` → user types `<Enter>` (default Y)
3. Install continues:
   - Create user runs (additive, no prompt)
   - REMEDIATE-03 sudoers overwrite runs
   - REMEDIATE-01 SKIPPED → `[REMEDIATE-01] DECLINED by user — skipping ownership chown; install continues`
   - Sentinel written for npm-prefix component: `{ "status": "reused-with-warning", "decline_reason": "chown-declined", ... }`
4. `agentlinux list` later shows: `nodejs-runtime (reused — declined remediation: chown-declined; manual fix needed)`

**`--dry-run` concrete walkthrough**

1. `agentlinux install --dry-run` on brownfield (pre-populated)
2. Detection runs (read-only) → report printed:
   ```
   pre-flight report:
     user        agent      Reuse (exists, bash, writable home, NOPASSWD-apt)
     nodejs      v22.x      Remediate (REMEDIATE-01: chown ~agent/.npm-global)
     sudoers     drifted    Remediate (REMEDIATE-03: overwrite /etc/sudoers.d/agentlinux)
     claude-code v2.0.7     Reuse (path-canonical, in compatibility window)
   exit code: 0 (dry-run)
   ```
3. No mutations; `stat /etc/sudoers.d/agentlinux` returns the pre-existing inode unchanged.
4. Immediately running `agentlinux install --yes` produces a report with byte-identical first 4 lines (the dry-run is observably non-mutating).

**Alt-user prompt concrete walkthrough**

1. Pre-existing user `agent` has shell `/bin/sh` (incompatible — DET-01 requires bash)
2. Interactive TTY:
   ```
   pre-flight: existing user "agent" has shell /bin/sh (DET-01 requires bash)
   AgentLinux can create a new install user instead.
   Suggested alternate name: agent2
   Press Enter to use "agent2", or type another name: <user types Enter>
   Proceeding with --user=agent2 ...
   ```
3. Non-interactive (cron, CI):
   ```
   agentlinux: existing user "agent" is incompatible (shell /bin/sh, required bash).
   Re-run with --user=agent2 or fix the existing user manually.
   (exit 65)
   ```

**Test coverage expectations**

Bats:
- UX-01: 3 @tests (dry-run greenfield, dry-run brownfield-bail-detected, dry-run idempotency-with-real-install)
- UX-02: 4 @tests (per-action prompt accept-all, decline-one-continue-others, --yes auto-approves all, no-TTY-no-prompts-at-all)
- UX-04: 3 @tests (interactive alt-user-prompt, non-interactive bail-65-with-hint, --user= name validation)
- Total: ~10 new bats @tests on top of Phase 14's 184 baseline → ~194

Node:test:
- ~5 new TS unit tests (CLI --dry-run option, list-suffix for reused-with-warning, sentinel widening, install.ts dry-run early-return)

JSON-report:
- ZERO new tests beyond existing grep-stable bats coverage (per D-15-03 minimum-viable choice)

</specifics>

<deferred>
## Deferred Ideas

- **TUI bulk-accept ("Yes to all" in first prompt)**: not in spec, adds branching. Defer to v0.3.5+ if real users complain about prompt fatigue.
- **`--auto-approve=PATTERN` per-action allowlist**: not in spec; `--yes` is the documented single-shot approve, no per-action flags by design (UX-03 lock).
- **`--report-format=yaml`**: out of scope; JSON + text are the only documented formats.
- **JSON schema file at `docs/schemas/report-v1.json`**: dropped per D-15-03. Reconsider if/when an external automation consumer materializes (today no consumer exists; bats greps are the de-facto spec).
- **Prompt timeout / Ctrl+C handling**: out of scope; SIGINT terminates the installer as per shell default (no special handling). Can be addressed in a future "robust UX" phase if needed.
- **Multi-host alt-user-suffix random scheme**: rejected; spec text mandates numeric suffix.
- **Per-action JSON status in sentinel beyond `decline_reason`**: today we record just the reason; a richer audit trail (timestamp, prompt-text-version) is a future iteration if needed.

</deferred>
