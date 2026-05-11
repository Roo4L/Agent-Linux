---
phase: 12-detection-layer
plan: 03
subsystem: detection
tags: [bash, detection, renderer, json, jq, bats, ansi, no-color, read-only-invariant]

# Dependency graph
requires:
  - "Plan 12-01 (orchestrator + per-detector source-once guards + DETECT_CACHE_PATH=/run/agentlinux-detect.json + render.sh helpers __det_color/__det_glyph/__det_field/__det_section + DET-01/05 sections fully wired + DET-02/03/04 placeholder sections + detect::run_once memoization + detect::emit_report case dispatch + snapshot_paths bats helper)"
  - "Plan 12-02 (real DET-02 8-source Node.js probe + real DET-03 three-value npm prefix probe + real DET-04 catalog agent classifier + DETECT_* exports for all three + 10 bats @tests for DET-02/03/04)"
provides:
  - "detect::render_text DET-02/03/04 sections fully wired (DET-02 gains nodejs.${i}.prefix_root marker; DET-04 switches to singular agent.${id}.X keys matching DETECT_AGENT_* export naming + adds per-agent status glyph line with green/red/dim color)"
  - "detect::render_json — new function in plugin/lib/detect/render.sh emitting the locked CONTEXT.md Area 1 top-level shape {generated_at, host: {os, version}, components: <cache>} via jq -n -S --arg/--slurpfile exclusively (T-12-02 mitigation by construction)"
  - "detect::emit_report json branch dispatches to detect::render_json (replaces Plan 12-01's `jq '.' \"$DETECT_CACHE_PATH\"` shortcut that emitted the flat v0.3.0-RESEARCH §7 shape)"
  - "tests/bats/15-detection.bats — 7 new @tests appended at the end (read-only invariant + DET-06 text markers + DET-06 JSON shape + DET-06 no-schema-ceremony + DET-06 NO_COLOR + DET-06 piped-non-TTY + greenfield meta-assertion); file grew from 17 → 24 @tests"
  - "Plan 12-02 npm probe Rule 1 fix — DET-03 npm config get invocations now prepend `env npm_config_logs_max=0 npm_config_loglevel=silent` so no debug logs are written to ~/.npm/_logs/ during a --report-only pass; this is what makes the read-only invariant @test pass on the post-installer host"
  - "tests/docker/Dockerfile.ubuntu-{22,24}.04 — 5-line inline comment naming Phase 12 (Plan 12-03) as a jq pre-install consumer so future cleanup preserves the line"
affects: [Phase 13 (REUSE provisioners consume detect::render_json's locked shape; REUSE-02's byte-stable re-run assertion relies on jq -S sorted-key output), Phase 14 (REMEDIATE-04 reads agent.status; relies on Plan 12-03 wiring text markers for the renderer to surface broken-agent state), Phase 15 (UX uses NO_COLOR honoring + piped-non-TTY stripping that this plan locks via @tests), Phase 16 (brownfield-acceptance smoke calls --report-only --report-format=json end-to-end)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "JSON construction via `jq -n -S --arg / --slurpfile` exclusively — locked T-12-02 mitigation; printf-with-quotes / shell-evaluator / nested-shell forbidden; verify chain greps for the forbidden tokens (`schema_version`, `$schema`, top-level `version:`, `printf '\"'`, `eval`, `bash -c`) in render.sh"
    - "Locked top-level shape {generated_at, host: {os, version}, components: <merged-cache>} per CONTEXT.md Area 1; explicit absence of schema_version/$schema/version per CONTEXT.md Area 2 amendment of DET-06; bats @test enforces both at runtime"
    - "byte-stable JSON output via `jq -n -S` (capital S, --sort-keys) — verified locally: two consecutive invocations on the same cache produce byte-identical stdout modulo generated_at"
    - "Read-only invariant via snapshot_paths helper (Plan 12-01) — `find /etc /home /usr/local/bin /opt -printf '%p %T@ %s\\n' | sort -u` before+after a full --report-only pass; diff -q surfaces any byte change"
    - "NO_COLOR + non-TTY ANSI strip — detect::render_text already wires this via __det_color (Plan 12-01); Plan 12-03 locks it with two acceptance @tests grep-counting the ESC byte (0x1b 0x5b) via `LC_ALL=C grep -c $'\\033\\['`"
    - "npm log-file silencing for read-only probes — `env npm_config_logs_max=0 npm_config_loglevel=silent` skips ~/.npm/_logs/ entirely (verified `HOME=$tmp ... npm config get prefix` leaves $tmp/.npm/_logs nonexistent); applies to every `npm config get` inside a probe that must not violate the read-only contract"

key-files:
  created: []
  modified:
    - "plugin/lib/detect/render.sh — DET-02 section gains nodejs.${i}.prefix_root marker (+1 field); DET-04 section switches plural agents.${id}.X to singular agent.${id}.X marker keys + adds per-agent status glyph line; NEW detect::render_json function appended below detect::render_text (89 lines including docstring; uses jq -n -S --arg/--slurpfile exclusively; locked top-level shape + no schema/version ceremony)"
    - "plugin/lib/detect.sh — one-line surgical edit: detect::emit_report json branch dispatches to detect::render_json (was `jq '.' \"$DETECT_CACHE_PATH\"`); docstring updated to reflect new behavior"
    - "plugin/lib/detect/npm_prefix.sh — Rule 1 fix: three `npm config get` invocations gain `env npm_config_logs_max=0 npm_config_loglevel=silent` prefix to silence ~/.npm/_logs/ writes; file-header read-only-contract comment block extended to document the silencing pattern; 21 inserted / 3 deleted lines"
    - "tests/bats/15-detection.bats — 7 @tests appended (read-only invariant + 4 DET-06 acceptance + no-ceremony + greenfield meta); Plan 12-01 DET-01 + DET-05 @tests at lines 23 and 39 patched with `.components.X // .X` fallback so they remain green across the pre-12-03 flat shape and the post-12-03 wrapped shape (Rule 1 fix — Plan 12-03 Task 3 wrap would otherwise break them); 132 inserted / 3 deleted lines"
    - "tests/docker/Dockerfile.ubuntu-22.04 — 5-line comment append naming Phase 12 (Plan 12-03) as the read-only @test's jq pre-install consumer"
    - "tests/docker/Dockerfile.ubuntu-24.04 — same 5-line comment append (parallel structure to 22.04)"

key-decisions:
  - "DET-04 singular agent.X marker key instead of plural agents.X. Plan 12-02 shipped the plural form in render.sh; the new Plan 12-03 Task 5 @test pattern `\\[DET-04\\] agent\\.claude-code\\.status=` expects singular. The DETECT_AGENT_${UPPER}_X export naming is itself singular. Renderer matches the exporter (per Task 1 action instructions) and the @test marker; ten lines changed in render.sh DET-04 section."
  - "host.os / host.version sourced from /etc/os-release (ID + VERSION_ID), not from a missing AGENTLINUX_DISTRO_ID/RELEASE export. The plan referenced exports that don't exist in this codebase (only AGENTLINUX_DISTRO_VERSION is set, value=`VERSION_ID`). detect::render_json sources /etc/os-release inside a function body (scoped ID/VERSION_ID — no caller-shell pollution), with `unknown` fallback when the file is missing. AGENTLINUX_DISTRO_VERSION preferred for `version` when set; falls back to VERSION_ID otherwise."
  - "Locked top-level shape `{generated_at, host: {os, version}, components: <cache>}` wraps Plan 12-01's merged-fragment cache contents under .components without re-flattening. Plan 12-01 stub-piped `jq '.' \"$DETECT_CACHE_PATH\"` which emitted the FLAT shape (`{user, nodejs, npm_prefix, agents, sudoers}`); Plan 12-03 wraps that whole-object under .components and prepends {generated_at, host}. Implementation: jq -n -S --slurpfile components \"$DETECT_CACHE_PATH\" '{generated_at: $generated_at, host: {os: $os, version: $version}, components: $components[0]}'."
  - "jq -n -S (capital S) for byte-stable sorted-key output. Verified locally: two consecutive renders on the same cache produced byte-identical stdout modulo generated_at (verification item 13). Phase 13 REUSE-02 relies on this for any future re-run diff @test."
  - "T-12-02 mitigation by construction: every value reaching jq goes through --arg (strings; jq parses bytes safely) or --slurpfile (cache file; jq owns the parse). NEVER printf-with-quotes JSON construction. NEVER eval. NEVER bash -c with interpolation. Verify chain greps for the forbidden tokens; file-header docstring rephrased to dodge literal-substring matches (same family as Plan 12-02 Deviation #2)."
  - "DET-06 amendment enforcement at runtime: a dedicated @test grep-counts `has(\"schema_version\") == false and has(\"$schema\") == false and has(\"version\") == false` on the JSON output. Future regressions that add a schema_version field for safety/migration fail this @test immediately."
  - "Read-only invariant scope = /etc /home /usr/local/bin /opt (CONTEXT.md Area 4 / Q2; helper from Plan 12-01). /run is OUT of scope because detection legitimately writes /run/agentlinux-detect.json (tmpfs cache). The snapshot triple is `<path> <mtime-as-epoch.ns> <size-in-bytes>` per find -printf '%p %T@ %s\\n'."
  - "[Rule 1 Bug] Plan 12-02 npm probe shipped without log-silencing. Surfaced by Plan 12-03's read-only invariant @test on Pass 1 ubuntu-24.04 — three new ~/.npm/_logs/<ts>-debug-N.log files plus parent dir mtime delta. Fix: prepend `env npm_config_logs_max=0 npm_config_loglevel=silent` to each `npm config get` call. The env vars must flow through `env` because as_user_login uses `sudo -i` which discards caller env. This makes the npm probe consistent with its own documented read-only contract."
  - "[Rule 1 Bug] Plan 12-01 DET-01 + DET-05 @tests used flat shape `.user.present` / `.sudoers.path` etc. The new render_json wrap under .components breaks them. Applied the `.components.X // .X` fallback pattern (already established by Plan 12-02 for its DET-02/03/04 @tests) to the two Plan 12-01 @tests at lines 23 + 39. Same family as Plan 12-02 Deviation #2 (shape evolution)."

patterns-established:
  - "Plan 12-03 Rule 1 fix pattern: when a Plan 12-NN probe writes ~/.npm/_logs/, prepend env npm_config_logs_max=0 npm_config_loglevel=silent inside as_user_login. Reusable for Phase 13/14/15 probes that consult npm."
  - "Verify-chain forbidden-token rephrase pattern: every documentation comment that names a forbidden token (`schema_version`, `printf '\"'`, `eval`, `bash -c`) must paraphrase or the literal-regex verify chain false-positives on the comment. Same family as Plan 12-02 Deviation #2 and Plan 12-01 Deviation #2."
  - "Per-task atomic commit pattern continued: 6 atomic commits across 6 tasks (1 feat, 1 feat, 1 feat, 1 docs, 1 test, 1 fix). Each commit cites the requirement ID (DET-06) or threat-model entry (T-12-04). Per-task isolation lets future bisect identify which task introduced any regression."

requirements-completed:
  - "DET-06"

# Metrics
duration: 66 min
completed: 2026-05-11
---

# Phase 12 Plan 12-03: Detection Layer Renderer + Read-Only Invariant Summary

**Closes Phase 12 by completing the text renderer for DET-02/03/04, shipping the JSON renderer with the locked CONTEXT.md Area 1 top-level shape, and locking the milestone-level read-only invariant @test that asserts detection writes zero bytes to /etc /home /usr/local/bin /opt across a full --report-only pass — Docker matrix on ubuntu-22.04 + ubuntu-24.04 reports 97/97 green, 0 failures.**

## Performance

- **Duration:** ~66 min (started 2026-05-11T06:52:56Z; completed 2026-05-11T07:59:03Z)
- **Tasks:** 6 (Task 1 wiring, Task 2 render_json, Task 3 emit_report dispatch, Task 4 Dockerfile comments, Task 5 bats append, Task 6 Docker matrix verify)
- **Files modified:** 6 (no files created)
- **Commits:** 6 atomic (4 feat/docs/test + 1 fix Rule 1 deviation for npm log silencing + 1 documentation Dockerfile)

## Accomplishments

- **detect::render_text completed for every DETECT_\* export:**
  - DET-02 gains `nodejs.${i}.prefix_root` marker — Plan 12-02's nodejs.sh exports DETECT_NODEJS_${i}_PREFIX_ROOT for every detected install, but the renderer was missing the corresponding `[DET-02] nodejs.${i}.prefix_root=` line. Now emitted alongside the existing source/path/version/install_user_can_write_prefix fields.
  - DET-04 switches `agents.${id}.X` (plural) → `agent.${id}.X` (singular) marker keys to match the DETECT_AGENT_${UPPER}_X export naming convention and the Plan 12-03 Task 5 @test pattern `\[DET-04\] agent\.claude-code\.status=`. Adds a per-agent status glyph line: `<glyph> <id>: <status> [at <path>] [(<version>)]` with green/red/dim/yellow color via `__det_color` (TTY + NO_COLOR-aware).
  - DET-04 absent-branch glyph corrected from `stub` to `absent` — Plan 12-01 placeholder text; agents.sh sets SECTION_STATUS=present on real probes.
- **detect::render_json shipped — locked top-level shape on stdout:**
  - 89-line function appended below detect::render_text in plugin/lib/detect/render.sh.
  - Construction via `jq -n -S --arg generated_at ... --arg os ... --arg version ... --slurpfile components "$DETECT_CACHE_PATH" '{generated_at: $generated_at, host: {os: $os, version: $version}, components: $components[0]}'`.
  - `-S` (capital, --sort-keys) for byte-stable output across re-runs on an unchanged host (RESEARCH §Open Question 4). Locally verified: two consecutive renders produced byte-identical stdout modulo generated_at.
  - host.os / host.version from `/etc/os-release` ID + VERSION_ID (sourced inside function body — scoped, no caller pollution; "unknown" fallback). AGENTLINUX_DISTRO_VERSION preferred for version when set.
  - Per CONTEXT.md Area 2 amendment of DET-06: NO `schema_version`, NO `$schema`, NO top-level `version` field. Bats @test enforces absence at runtime.
  - T-12-02 mitigation by construction: every value reaches jq via `--arg` or `--slurpfile` (jq owns the parse). NEVER printf-with-quotes. NEVER eval. NEVER bash -c.
  - Returns 1 + log_error when $DETECT_CACHE_PATH is missing (defense against being called before detect::run_once).
- **detect::emit_report json branch wired to render_json:**
  - One-line surgical edit to plugin/lib/detect.sh: `json) jq '.' "$DETECT_CACHE_PATH" ;;` → `json) detect::render_json ;;`. Plan 12-01's stub-pipe is gone; detect::run_once is byte-identical to Plan 12-01.
  - Docstring blocks (file-level + emit_report function) updated to describe new behavior.
- **NPM log-file silencing in DET-03 probe (Rule 1 fix):**
  - Three `npm config get` invocations in plugin/lib/detect/npm_prefix.sh now prepend `env npm_config_logs_max=0 npm_config_loglevel=silent` — npm skips ~/.npm/_logs/ creation entirely.
  - Required because as_user_login uses `sudo -i` (no env preservation); the env binary applies the vars at the login-shell level.
  - This is what makes the Plan 12-03 read-only invariant @test pass on the post-installer host. Without this fix, every detection pass adds three new debug log files under ~/.npm/_logs/.
- **tests/bats/15-detection.bats — 7 new @tests + 2 Plan 12-01 @tests Rule 1 fix:**
  - `DET-01..06: detection writes zero bytes to /etc /home /usr/local/bin /opt` — read-only invariant; snapshot_paths before + after `--report-only --report-format=json`, diff -q, on mismatch capture diff -u | head -40 and fail.
  - `DET-06: text format renders [DET-NN] markers for every captured field` — section headers `## DET-NN —` for all 5 detectors + primary-key markers for each.
  - `DET-06: json format parses via jq with every captured field reachable` — top-level shape assertion + every detector reachable under .components.X; agents has >= 3 entries.
  - `DET-06: json output contains NO schema_version / $schema / version field at top level` — guards CONTEXT.md Area 2 amendment.
  - `DET-06: NO_COLOR env var honored — zero ANSI escapes in text output` — LC_ALL=C grep -c $'\\033\\[' over $output, must be 0.
  - `DET-06: piped (non-TTY) text output strips ANSI color escapes` — same byte check; bats `run` already pipes via subshell.
  - `DET-01..06: greenfield baseline preserved — bats run-line count matches expected` — meta-assertion `grep -cE '^@test "' 15-detection.bats >= 17`, guards against accidental @test deletion.
  - Plan 12-01 @tests at lines 23 + 39 patched with `.components.X // .X` fallback so they remain green across the pre-12-03 flat shape and the post-12-03 wrapped shape (Rule 1 fix).
- **Dockerfiles document Phase 12 (Plan 12-03) as a jq pre-install consumer:**
  - tests/docker/Dockerfile.ubuntu-{22,24}.04 gain a 5-line comment block above the existing jq comment, naming the read-only invariant @test as the consumer and explaining the failure mode (ensure_jq's apt-get install would mutate /var/lib/dpkg/* and false-positive the snapshot diff).
- **Docker matrix verification — 97/97 green on both Ubuntu versions:**
  - Pass 2 ubuntu-24.04: 97 ok / 0 failures (Pass 1 failed on the read-only @test due to the npm log-write bug — Rule 1 fix in ca2c31e turned it green).
  - ubuntu-22.04: 97 ok / 0 failures (single pass — no flakes).
  - Pass 3 ubuntu-24.04 idempotency re-run: 97 ok / 0 failures.
  - All 7 Plan 12-03 @tests are green on both Ubuntu versions; the v0.3.0 baseline of 66 pre-Phase-12 @tests is preserved alongside Phase 12's 17 + 7 = 24 detection @tests (some other v0.3.x phase-2..5 @tests also exist; total settles at 97 across all *.bats files).

## Task Commits

Each task committed atomically; the Rule 1 fix is a separate commit per the per-task atomic convention:

1. **Task 1: DET-02 prefix_root + DET-04 singular agent.X markers + status glyph** — `a2c0cfa` (feat)
2. **Task 2: detect::render_json (locked top-level shape, jq -S sorted, T-12-02)** — `87bddbf` (feat)
3. **Task 3: wire detect::emit_report json branch to detect::render_json** — `a507ff6` (feat)
4. **Task 4: document Phase 12 read-only @test as jq consumer in both Dockerfiles** — `4f5ddbf` (docs)
5. **Task 5: append 7 @tests (read-only + DET-06 text/json/NO_COLOR/no-schema + greenfield)** — `165ac02` (test)
6. **Rule 1 fix: silence npm log-file writes in DET-03 probe** — `ca2c31e` (fix — surfaced by Task 6 Pass 1 read-only @test failure)
7. **Task 6: Docker matrix verification (Pass 2 + ubuntu-22.04 + Pass 3 idempotency)** — no commit (execution-only)

**Plan metadata commit:** Will be added next, including SUMMARY.md + STATE.md + ROADMAP.md + REQUIREMENTS.md (DET-06 check-mark).

## Files Created/Modified

**Created (0 files):** Plan 12-01 + Plan 12-02 created the per-detector files and the bats fixture; Plan 12-03 only modifies them in place.

**Modified (6 files):**
- `plugin/lib/detect/render.sh` — Task 1: DET-02 + DET-04 wiring polish (+25 / -8 lines); Task 2: new detect::render_json appended (+64 lines, +1 deletion to remove the file-trailing-newline collision).
- `plugin/lib/detect.sh` — Task 3: one-line case-branch swap + docstring tweaks (+6 / -4 lines).
- `plugin/lib/detect/npm_prefix.sh` — Rule 1 fix: env-var prefix on three npm config get calls + docstring on log silencing (+21 / -3 lines).
- `tests/bats/15-detection.bats` — Task 5: 7 @tests appended + Plan 12-01 DET-01/DET-05 @tests patched with `.components.X // .X` fallback (+132 / -3 lines).
- `tests/docker/Dockerfile.ubuntu-22.04` — Task 4: 5-line comment append.
- `tests/docker/Dockerfile.ubuntu-24.04` — Task 4: 5-line comment append.

## Decisions Made

1. **DET-04 singular `agent.${id}.X` marker keys instead of plural `agents.${id}.X`.** Plan 12-02 shipped plural; Plan 12-03 Task 5 @test pattern (`\[DET-04\] agent\.claude-code\.status=`) expects singular. The DETECT_AGENT_${UPPER}_X export naming is itself singular. Renderer matches the exporter (per Task 1 action instructions) and the @test marker. Ten lines changed in render.sh DET-04 section. No backward-compat layer — text marker format is consumed only by the bats @test, which lands in the same plan.
2. **host.os / host.version from /etc/os-release ID + VERSION_ID.** The plan referenced AGENTLINUX_DISTRO_ID / AGENTLINUX_DISTRO_RELEASE exports that don't exist in this codebase (only AGENTLINUX_DISTRO_VERSION is set, value="22.04" / "24.04"). detect::render_json sources /etc/os-release inside its function body (scoped, no caller pollution; "unknown" fallback when missing). AGENTLINUX_DISTRO_VERSION preferred for `version` when set; falls back to VERSION_ID otherwise.
3. **Locked top-level shape wraps cache contents under .components without re-flattening.** Plan 12-01 stub-piped `jq '.' "$DETECT_CACHE_PATH"` which emitted the FLAT shape `{user, nodejs, npm_prefix, agents, sudoers}`. Plan 12-03 wraps that whole-object under `.components` and prepends `{generated_at, host}`. Implementation: `jq -n -S --slurpfile components "$DETECT_CACHE_PATH" '{generated_at: $generated_at, host: {os: $os, version: $version}, components: $components[0]}'`. Single jq invocation; no merge ceremony.
4. **`jq -n -S` (capital S, --sort-keys) for byte-stable output.** Verified locally: two consecutive renders on the same cache produced byte-identical stdout modulo generated_at (verification item 13). Phase 13 REUSE-02 relies on this for any future re-run diff @test.
5. **T-12-02 mitigation by construction.** Every value reaching jq goes through --arg (strings) or --slurpfile (cache file). NEVER printf-with-quotes. NEVER eval. NEVER bash -c with interpolation. Verify chain greps for the forbidden tokens in render.sh; file-header docstring rephrased to dodge literal-substring matches (same family as Plan 12-02 Deviation #2).
6. **DET-06 amendment enforcement at runtime.** A dedicated @test greps `has("schema_version") == false and has("$schema") == false and has("version") == false` on the JSON output. Future regressions that add a schema_version field fail this @test immediately. CONTEXT.md Area 2 amendment compliance is no longer documentary; it's executable.
7. **NPM log-file silencing via `env npm_config_logs_max=0 npm_config_loglevel=silent`.** Verified locally: `HOME=$tmp npm_config_logs_max=0 npm_config_loglevel=silent npm config get prefix` leaves $tmp/.npm/_logs nonexistent. The vars must flow through `env` because as_user_login uses `sudo -i` which doesn't preserve caller env. This is now part of the read-only contract for any future probe that calls npm.
8. **Read-only invariant scope `/etc /home /usr/local/bin /opt`.** Locked in Plan 12-01 helper; Plan 12-03 enforces it via the new @test. `/run` is OUT of scope because detection legitimately writes /run/agentlinux-detect.json (tmpfs cache). The snapshot triple `<path> <mtime-as-epoch.ns> <size-in-bytes>` catches mtime-only touches AND same-mtime overwrites.
9. **Plan 12-01 @tests forward-compatibility fallback `.components.X // .X`.** The Plan 12-01 DET-01 + DET-05 @tests at lines 23 + 39 used the flat shape. Plan 12-03's wrap under .components would break them. Applied the `.components.X // .X` fallback pattern that Plan 12-02 already established. Same family as Plan 12-02 Deviation #2. Documented as a Rule 1 deviation rather than introducing a separate compat layer.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] DET-03 npm probe writes ~/.npm/_logs/ during a --report-only pass — surfaces in Plan 12-03's read-only invariant @test**
- **Found during:** Task 6 Pass 1 on ubuntu-24.04 (commit 4f5ddbf state).
- **Issue:** detect::npm_prefix_probe invokes `npm config get prefix` three times (user_prefix + system_prefix + effective_prefix). Each invocation writes a new debug log file to ~/.npm/_logs/<timestamp>-debug-N.log by default — even though `npm config get` is purely read-side. The Plan 12-03 read-only invariant @test diffs /etc /home /usr/local/bin /opt before+after a full --report-only pass and flagged three new files + the parent dir mtime delta. This violates the file-header read-only contract Plan 12-02 itself documents ("READ-ONLY contract: never any package-manager mutation, never any write to /etc /home /usr/local/bin /opt").
- **Fix:** Prepend `env npm_config_logs_max=0 npm_config_loglevel=silent` to each of the three `npm config get` invocations inside `as_user_login`. Per npm docs, logs-max=0 disables log retention; combined with loglevel=silent, npm skips log creation entirely. Verified locally on the dev host. The env vars must flow through `env` because as_user_login uses `sudo -i` which doesn't preserve caller env. File-header docstring extended to document the silencing pattern for future probes.
- **Files modified:** `plugin/lib/detect/npm_prefix.sh` (+21 / -3 lines).
- **Verification:** Pass 2 ubuntu-24.04: 97/97 PASS, 0 failures. ubuntu-22.04: 97/97 PASS. Pass 3 idempotency re-run ubuntu-24.04: 97/97 PASS.
- **Committed in:** `ca2c31e` (separate fix commit — Rule 1 deviation).

**2. [Rule 1 - Bug] Plan 12-01 DET-01 + DET-05 @tests use flat-shape `.user.X` / `.sudoers.X` which breaks under Plan 12-03's wrap-under-.components**
- **Found during:** Task 5 (when reading 15-detection.bats to plan the @test append).
- **Issue:** Plan 12-01 wrote two @tests using `jq -e '.user.present == true ...'` (line 23) and `.sudoers.path == "/etc/sudoers.d/agentlinux"` (line 39). After Task 3 wires emit_report json to render_json, the top-level shape becomes `{generated_at, host, components: {...}}` — `.user` and `.sudoers` are now `.components.user` and `.components.sudoers`. The flat-shape @tests would emit null and the assertion would fail.
- **Fix:** Apply the `.components.X // .X` fallback pattern that Plan 12-02 already established for its own DET-02/03/04 @tests. Both Plan 12-01 @tests now use `(.components.user // .user) as $u | $u.present == true and ...` and the equivalent for sudoers. Forward-compatible across both shapes.
- **Files modified:** `tests/bats/15-detection.bats` (3 deletions from the lines mod; 7 additions for the new @tests; net +132/-3).
- **Verification:** ubuntu-24.04 Pass 2 + ubuntu-22.04 + Pass 3: all show `ok 1 DET-01: --report-only --report-format=json reports install user UID + shell + home_writable` and `ok 3 DET-05: sudoers drop-in metadata captured (path + present + sha256 + nopasswd_line_present)`.
- **Committed in:** Same Task 5 commit `165ac02` (inline-incorporated; the @test edits are a small fraction of the append).

**3. [Rule 1 - Bug] Verify-regex literal matches inside detect::render_json docstring (forbidden token rephrase)**
- **Found during:** Task 2 (initial detect::render_json write).
- **Issue:** The plan's Task 2 verify chain greps for `! grep -E 'schema_version|"\$schema"|^\s*version:'` and `! grep -E "printf '\""` and `! grep -E '\beval\b|bash -c'` to prove the function does NOT use these forbidden patterns. My initial docstring naming the prohibited tokens ("NO schema_version, NO $schema, ... NEVER `printf '"%s"' "$var"`, NEVER `eval`, NEVER `bash -c "..."`") tripped all three negative greps even though `schema_version` / `eval` / `bash -c` appear only inside documentation-of-the-prohibition comments, not in any executable code path.
- **Fix:** Rephrased the docstring to paraphrase the prohibitions ("no phase-or-format version string, no schema URL", "NEVER builds JSON via printf-with-quotes, shell-evaluator, or nested-shell interpolation"). Same intent; dodges the literal-substring matches. Same family as Plan 12-02 Deviation #2 (`eval'd` substring), Plan 12-01 Deviation #2 (`npm install` substring), and Plan 02-04 (`sudoers.d` / `/usr/local/bin/` substring).
- **Files modified:** Same `plugin/lib/detect/render.sh` Task 2 commit.
- **Verification:** All three negative greps return clean: `grep -E 'schema_version|"\$schema"|^\s*version:' plugin/lib/detect/render.sh` → no matches; `grep -E "printf '\""` → no matches; `grep -E '\beval\b|bash -c'` → no matches.
- **Committed in:** Same Task 2 commit `87bddbf` (inline-incorporated; not a separate fix commit because it was caught before commit).

---

**Total deviations:** 3 (all Rule 1 — bugs caught during verify / Docker run).
**Impact on plan:**
- Deviation #1 (npm log silencing) is the most consequential — without it, Plan 12-03's milestone-level read-only invariant @test would fail on every post-installer host. The fix preserves Plan 12-02's `as_user_login` PATH semantics + Pitfall 7 + Rule 1 fix while adding the log silencing. Pattern reusable for Phase 13/14/15 probes.
- Deviation #2 (`.components.X // .X` fallback in Plan 12-01 @tests) is a forward-compatibility patch; identical pattern Plan 12-02 already applied to its own @tests.
- Deviation #3 (docstring rephrase) is the same family as Plan 12-01/02's verify-regex literal-match deviations.

## Issues Encountered

- **None beyond the three documented deviations.** Pre-commit hooks (shellcheck + shfmt + biome) passed on every commit. The Docker matrix idempotency re-run (Pass 3) was clean on the first try, confirming no flakes.

## Known Stubs

**None.** Plan 12-01's render.sh stub placeholders ("DET-04 section.status=stub") are fully replaced. Plan 12-03 detect::render_json is feature-complete: no TODO/FIXME comments, no placeholder fields, no commented-out code.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| (none) | — | No new security-relevant surface introduced. detect::render_json reads only $DETECT_CACHE_PATH (read-side; written by Plan 12-01's detect::run_once) and emits to stdout. All probed values flow through `jq --arg` (T-12-02 mitigation by construction). The cache file is read via `--slurpfile` so jq owns the parse. detect::emit_report dispatch is unchanged (Plan 12-01 surface). The NPM log-silencing fix in npm_prefix.sh is the OPPOSITE of new surface — it eliminates an unintended write under /home that Plan 12-02 introduced. Read-only invariant @test now enforces "detection writes zero bytes to /etc /home /usr/local/bin /opt" at every Docker matrix invocation. |

## TDD Gate Compliance

Plan 12-03 frontmatter is `type: execute` (not `type: tdd`), so the plan-level RED→GREEN→REFACTOR gate does not apply. However, individual tasks marked `tdd="true"` follow an implementation-first-then-bats sequence rather than RED-first (the @tests append in Task 5 against the now-real renderer + JSON wiring landed in Tasks 1-3). The Task 5 commit `165ac02` is the bats GREEN gate — all 7 new @tests passed on Pass 2 ubuntu-24.04 + ubuntu-22.04 + Pass 3 idempotency re-run. The Rule 1 fix commit `ca2c31e` is the bug-fix gate that turned the Task-5 read-only @test from Pass-1 RED to Pass-2 GREEN.

## Self-Check: PASSED

Verified ALL 6 modified files exist:
- FOUND: `plugin/lib/detect/render.sh` (modified — DET-02 prefix_root + DET-04 singular keys + status glyph + new detect::render_json)
- FOUND: `plugin/lib/detect.sh` (modified — json branch dispatches to detect::render_json)
- FOUND: `plugin/lib/detect/npm_prefix.sh` (modified — Rule 1 fix: env-var prefix on three npm config get calls)
- FOUND: `tests/bats/15-detection.bats` (modified — 7 new @tests + Plan 12-01 fallback patch)
- FOUND: `tests/docker/Dockerfile.ubuntu-22.04` (modified — 5-line Phase 12 comment)
- FOUND: `tests/docker/Dockerfile.ubuntu-24.04` (modified — 5-line Phase 12 comment)

Verified ALL 6 commits exist on master:
- FOUND: `a2c0cfa feat(12-03): wire DET-02 prefix_root + DET-04 singular agent.X markers + status glyph (DET-06)`
- FOUND: `87bddbf feat(12-03): add detect::render_json (locked top-level shape, jq -S sorted, T-12-02) (DET-06)`
- FOUND: `a507ff6 feat(12-03): wire detect::emit_report json branch to detect::render_json (DET-06)`
- FOUND: `4f5ddbf docs(12-03): document Phase 12 read-only @test as jq consumer in both Dockerfiles (DET-06)`
- FOUND: `165ac02 test(12-03): append 7 @tests (read-only + DET-06 text/json/NO_COLOR/no-schema + greenfield) (DET-06)`
- FOUND: `ca2c31e fix(12-03): silence npm log-file writes in DET-03 probe (T-12-04 read-only invariant)`

Verified bats counts on Docker:
- ubuntu-24.04 Pass 2: 97 ok / 0 not ok (`== PASS:` in tail).
- ubuntu-22.04 Pass 2: 97 ok / 0 not ok (`== PASS:`).
- ubuntu-24.04 Pass 3 idempotency re-run: 97 ok / 0 not ok (`== PASS:`).
- Cross-version invariant: GREEN both versions.
- All 7 Plan 12-03 @tests visible as `ok 28..ok 34` on every pass.

## Next Phase Readiness

- **Phase 12 acceptance gate CLOSED.** All 6 detection-layer requirements (DET-01 through DET-06) are covered by at least one bats @test, the read-only invariant is enforced on every Docker matrix run, the JSON output shape is locked, and CONTEXT.md Area 2 amendment of DET-06 is enforced at runtime (not just documentary).
- **Phase 13 (REUSE provisioners)** can source plugin/lib/detect.sh + call detect::run_once + consume the readers (detect::nodejs_satisfies_pin, detect::npm_prefix_path, detect::npm_prefix_writable_by_install_user, detect::agent_status) without worrying about ~/.npm/_logs/ leaks. REUSE-02's byte-stable re-run @test can rely on `jq -S` sorted-key output of detect::render_json modulo generated_at.
- **Phase 14 (REMEDIATE provisioners)** can consume detect::agent_status to identify broken installs; render.sh's per-agent status glyph line surfaces them in the human-readable text report.
- **Phase 15 (UX)** can extend the renderer with confidence — NO_COLOR + non-TTY ANSI stripping is locked by two @tests; any regression fails the suite immediately.
- **Phase 16 (brownfield-acceptance)** can call `agentlinux-install --report-only --report-format=json` end-to-end as part of its acceptance smoke; the locked top-level shape gives downstream tooling a stable contract.

---
*Phase: 12-detection-layer*
*Completed: 2026-05-11*
