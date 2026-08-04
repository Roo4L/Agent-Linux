---
phase: 05-agent-installability
plan: 02
subsystem: agent-recipe
tags: [gsd, get-shit-done-cc, npm-global, agt-04, banner-grep, version-lock, adr-004]

requires:
  - phase: 04-registry-cli-catalog-uninstall
    provides: runner.ts dispatchRecipe + AGENT_PATH env contract (PATH, NPM_CONFIG_PREFIX=/home/agent/.npm-global, HOME, LANG/LC_ALL) + Phase 4 scaffold install.sh/uninstall.sh files with `:?` guards + catalog.json pinned_version=1.37.1 + npm_package_name=get-shit-done-cc (three CONTEXT corrections verified at catalog-time in Plan 04-02)
  - phase: 03-runtime-wiring
    provides: NPM_CONFIG_PREFIX=/home/agent/.npm-global keystone (ADR-004) so npm install -g lands in agent-owned territory without sudo or EACCES
  - phase: 05-01 (same phase, Wave 1)
    provides: canonical pipe-to-bash recipe pattern (Pattern 1 from 05-01-SUMMARY) + in-recipe version-lock pattern (Pattern 2) — Plan 05-02 adapts these patterns to the npm-kind source
provides:
  - plugin/catalog/agents/gsd/install.sh (real npm-global body with `--omit=dev --no-fund --no-audit`, PATH-resolve check, and banner-grep version-lock against `get-shit-done-cc --help`)
  - plugin/catalog/agents/gsd/uninstall.sh (symmetric inverse: `npm uninstall -g get-shit-done-cc` with idempotent `|| true` + post-uninstall `command -v` absence check)
affects: [phase-05-04 50-agents.bats consolidated plan (exercises AGT-04 against this install.sh body via `agentlinux install gsd`), phase-06 TST-05/TST-07 closure (AGT-04 requirement flip to GREEN), phase-05-03 (playwright recipe — shares npm-kind pattern established here)]

tech-stack:
  added: []
  patterns:
    - "Pattern 6 (npm-kind version-lock via --help banner): when a package has no --version flag, `<bin> --help | head -N | grep -q -F \"v${PINNED}\"` is the version-lock mechanism. Works on pkgs that print a banner before the usage text. More fragile than `--version` output (banner shape can change) but upstream-stable enough for version-pinned installs. Verified live: get-shit-done-cc@1.37.1 prints ASCII-art logo (7 lines) + blank + `  Get Shit Done \\e[2mv1.37.1\\e[0m` at line 9 — `head -20` captures it and `grep -F 'v1.37.1'` matches through the ANSI color codes."
    - "Pattern 7 (npm-kind recipe — agent-owned prefix, zero sudo): `npm install -g <pkg>@<pinned> --omit=dev --no-fund --no-audit` followed by `command -v <bin>` resolve-check. NPM_CONFIG_PREFIX=/home/agent/.npm-global (runner.ts-injected) keeps the install in agent territory (ADR-004 keystone). Zero sudo, zero /usr/local/bin writes. End-to-end wall-time observed: 0.5s (tiny tarball — ~130 KB unpacked)."
    - "Pattern 8 (no-symlink anti-pattern avoidance): when a package's binary name differs from the catalog `id`, DO NOT add a symlink alias. Adding `ln -s ~/.npm-global/bin/get-shit-done-cc ~/.npm-global/bin/gsd` would be a wrapper-shim in the spirit of the /usr/local/bin/<tool> anti-pattern that breaks `claude update` (AGT-02). Catalog `id` is a UI label; tests invoke the package-native binary name directly."

key-files:
  created:
    - .planning/phases/05-agent-installability/05-02-SUMMARY.md
  modified:
    - plugin/catalog/agents/gsd/install.sh (scaffold body → real npm-global body, 51 lines)
    - plugin/catalog/agents/gsd/uninstall.sh (scaffold body → real symmetric inverse, 19 lines)

key-decisions:
  - "RESEARCH Pattern 3 + Pattern 4 transcribed verbatim, modulo two comment rephrasings (L8 `NOT the three-letter slug` replacing `NOT gsd`; L17 `without privilege escalation` replacing `without sudo or EACCES`) — explicitly allowed by plan quality-gate note 'Comments rephrased where they would match catalog-auditor grep -q sweeps' (per Plan 04-02 State note line 154). Rephrasings do not change semantics; they reduce `gsd` word-boundary matches and `sudo` substring matches in catalog-auditor sweeps."
  - "Banner-grep is the version-lock mechanism (AGT-04) — not `--version`. Verified via `npm view get-shit-done-cc bin`: package exposes `get-shit-done-cc` binary only, no `--version` flag. `--help` first-20-lines contain `  Get Shit Done \\e[2mv1.37.1\\e[0m` (ANSI-wrapped); `grep -q -F 'v1.37.1'` matches through the escape codes (substring search ignores non-matching bytes). Pattern survives a future banner-shape change as long as `v<pinned>` remains somewhere in the first 20 lines."
  - "`--omit=dev --no-fund --no-audit` kept as a triple despite none being individually load-bearing for a 130 KB package: `--omit=dev` is belt-and-braces against future devDep bloat (only runtime files ship today per package `files` manifest); `--no-fund` / `--no-audit` silence npm's funding banner and vulnerability summary for cleaner transcripts. Total wall-time savings: negligible (~50ms); readability savings: significant (transcript goes from 8 lines to 2)."
  - "No symlink alias for `gsd` → `get-shit-done-cc`. Catalog `id` is `gsd` (a UI label surfaced by `agentlinux list` and `agentlinux install gsd`); binary invoked by tests and users is `get-shit-done-cc` (package-native). Adding a symlink would be a hidden shim (RESEARCH §Open Question 1 research-locked decision) — exactly the anti-pattern AgentLinux exists to eliminate."
  - "Uninstall uses `|| true` on the npm call with the `command -v` check as the authoritative post-condition (vs. trusting npm's exit code). npm 10.x returns 0 on uninstall-missing (\"up to date\") but this could drift in future npm majors; `command -v` is the observable-behavior assertion that survives npm behavior changes."
  - "`--help` banner captured via `head -20` rather than full output. Banner is at line 9 today (ASCII-art logo lines 1-7 + blank + banner line); `head -20` gives 11 lines of slack against future logo-height changes. Using full `--help` output would pipe the whole usage list (40+ lines of option flags) through grep — wasteful and brittle to usage-text edits."

patterns-established:
  - "npm-kind recipe body: `npm install -g <pkg>@<pinned> --omit=dev --no-fund --no-audit` + `command -v <bin>` PATH-resolve check + banner-grep version-lock (or `--version` grep when the package supports it — choose based on `npm view <pkg> bin` inspection)."
  - "Zero-sudo symmetric uninstall for npm-kind: `npm uninstall -g <pkg> --no-fund --no-audit >/dev/null 2>&1 || true` + `command -v <bin>` absence check. `|| true` is the idempotency primitive (npm uninstall-missing exits 0 today, future-proof guard); `command -v` is the observable-behavior postcondition."
  - "Comment-phrasing discipline to reduce catalog-auditor grep false-positives: `privilege escalation` instead of literal `sudo` in comments; `the three-letter slug` instead of `gsd` when the context is about the binary name (not the catalog id or log-label)."

requirements-completed: [AGT-04]

duration: 45min
completed: 2026-04-19
---

# Phase 05 Plan 02: gsd recipe — npm install -g get-shit-done-cc Summary

**Real npm-global recipe body shipped (51-line install.sh + 19-line uninstall.sh) — `npm install -g get-shit-done-cc@1.37.1` with `--omit=dev --no-fund --no-audit`, PATH-resolve check, and `--help` banner-grep version-lock; symmetric uninstall with idempotent `|| true` + observable-behavior `command -v` absence check. Exercised end-to-end on the host: 0.5s install wall-time, zero sudo, zero EACCES, zero /usr/local writes.**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-04-19T20:22:00Z
- **Completed:** 2026-04-19T21:08:00Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments

- `plugin/catalog/agents/gsd/install.sh` (51 lines) REPLACES Phase 4 scaffold body with real npm-global install body per RESEARCH §Pattern 3. `npm install -g "get-shit-done-cc@${AGENTLINUX_PINNED_VERSION}"` with `--omit=dev --no-fund --no-audit` flags + fail-fast `:?` guard on `AGENTLINUX_PINNED_VERSION` + post-install `command -v get-shit-done-cc` resolve check + `--help` banner-grep against `v${PINNED}` (AGT-04 version-lock, NOT via `--version` because the package has no such flag).
- `plugin/catalog/agents/gsd/uninstall.sh` (19 lines) REPLACES Phase 4 scaffold body with symmetric inverse per RESEARCH §Pattern 4. `npm uninstall -g get-shit-done-cc --no-fund --no-audit` with idempotent `|| true` + post-uninstall `command -v` absence check as the observable-behavior postcondition.
- End-to-end exercised on the agent user's live npm-global prefix: install completes in 0.542s (real-time, `time bash install.sh`) with the exact spec'd log line `gsd: install complete (resolves at /home/agent/.npm-global/bin/get-shit-done-cc; banner matches pin)`. Uninstall is symmetric and idempotent (two consecutive runs both exit 0).
- AGT-04 requirement is now covered at the recipe level; the bats @test for end-to-end `agentlinux install gsd` ships in Plan 05-04.

## Task Commits

1. **Task 1: Replace gsd install.sh + uninstall.sh scaffolds with real npm-global install bodies (AGT-04)** — `a8a9a18` (feat)

_No separate review-fix commits needed — inline review loop clean after first pass._

## Files Created/Modified

- `plugin/catalog/agents/gsd/install.sh` — **modified** (scaffold body 18 lines → real body 51 lines). Real body: `npm install -g get-shit-done-cc@PINNED` + PATH-resolve check + `--help` banner-grep. Rejects missing `AGENTLINUX_PINNED_VERSION` via `:?` guard; rejects missing binary after install; rejects banner mismatch.
- `plugin/catalog/agents/gsd/uninstall.sh` — **modified** (scaffold body 11 lines → real body 19 lines). Real body: `npm uninstall -g get-shit-done-cc` + idempotent `|| true` + post-uninstall `command -v` absence check.
- `.planning/phases/05-agent-installability/05-02-SUMMARY.md` — **created** (this file).

## Live Evidence

### RESEARCH Pattern match count

- **Pattern 3 (gsd install.sh):** transcribed verbatim modulo two comment rephrasings (see Deviations §1).
- **Pattern 4 (gsd uninstall.sh):** transcribed verbatim, zero deviations.
- Total: 2 patterns matched, 0 structural deviations, 2 cosmetic comment rephrasings (explicitly allowed by plan quality-gate note).

### npm install wall-time (host observation, sanity check)

```
$ time bash plugin/catalog/agents/gsd/install.sh
gsd: installing get-shit-done-cc@1.37.1
npm warn EBADENGINE Unsupported engine { ... node '>=22.0.0' ... current v20.20.1 ... }
added 1 package in 424ms
gsd: install complete (resolves at /home/agent/.npm-global/bin/get-shit-done-cc; banner matches pin)

real	0m0.542s
user	0m0.468s
sys	0m0.149s
```

Wall-time 0.5s on the host (Node 20.20.1, tiny 130 KB tarball). Docker matrix baseline is Node 22 LTS — expect similar or faster. EBADENGINE warning is host-local (executor running on Node 20); the installer container ships Node 22 LTS so EBADENGINE never surfaces inside the real runtime.

### `get-shit-done-cc --help` banner output (first 10 lines, ANSI stripped for readability)

```
   ██████╗ ███████╗██████╗
  ██╔════╝ ██╔════╝██╔══██╗
  ██║  ███╗███████╗██║  ██║
  ██║   ██║╚════██║██║  ██║
  ╚██████╔╝███████║██████╔╝
   ╚═════╝ ╚══════╝╚═════╝

  Get Shit Done v1.37.1
  A meta-prompting, context engineering and spec-driven
  development system for Claude Code, OpenCode, Gemini, ...
```

Banner line is line 9: `  Get Shit Done ^[[2mv1.37.1^[[0m` (dim-ANSI wrapped around `v1.37.1`). `head -20 | grep -q -F 'v1.37.1'` matches through the ANSI escapes because the literal `v1.37.1` substring is present byte-for-byte.

### Word-boundary `gsd` hits in install.sh (zero binary invocations)

```
$ grep -En 'gsd' plugin/catalog/agents/gsd/install.sh
3:# gsd install.sh — real body (Phase 5 AGT-04).
22:echo "gsd: installing get-shit-done-cc@${AGENTLINUX_PINNED_VERSION}"
37:  echo "gsd install: get-shit-done-cc not on PATH after install" >&2
45:  printf 'gsd install: pinned=%s but banner: %s\n' \
50:echo "gsd: install complete (resolves at ${bin_path}; banner matches pin)"
```

All 5 hits are in (a) a file-header shell comment or (b) quoted echo/printf log-label strings for transcript parsing (`gsd:` / `gsd install:` prefixes). **Zero hits are binary invocations** — no `command -v gsd`, no `gsd --help`, no `gsd --version`, no `npm install -g gsd`, no `npm install -g get-shit-done` (minus the `-cc` suffix). Intent-level check (documented below in Deviations §1).

## Decisions Made

See frontmatter `key-decisions` for the six structural decisions (verbatim-from-RESEARCH, banner-grep mechanism, triple-flag npm rationale, no-symlink anti-pattern, uninstall idempotency-via-`|| true`, `head -20` slack).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — spec-grep contradiction] `! grep -Ewq 'gsd' install.sh` AC line is self-contradictory with the RESEARCH-mandated verbatim body**

- **Found during:** Task 1 (acceptance-criteria gate execution)
- **Issue:** The plan's AC line reads `! grep -Ewq 'gsd' plugin/catalog/agents/gsd/install.sh` (grep rejects any whole-word `gsd` token), with parenthetical `(word-boundary match rejects 'gsd' as a whole word; 'gsd:' echo prefix and '# gsd' comments are allowed)`. BUT `grep -Ew` uses regex word boundaries `\b`, and `:` is a non-word character — so `gsd:` DOES match `-w 'gsd'` (the `:` IS a word boundary). Similarly `# gsd install.sh` matches because space→`gsd`→space satisfies `\b..\b`. The grep as written cannot pass while keeping the RESEARCH-verbatim body, which has 5 such hits (1 header comment + 4 `gsd:` / `gsd install:` log labels).
- **Fix:** Applied the AC's *intent* instead of its *literal grep* (the plan action block itself says "MUST use `get-shit-done-cc` as the binary name everywhere; DO NOT reference `gsd` ... (those binaries do NOT exist)" — a binary-invocation restriction). Verified via five separate intent-level negative greps: no `command -v gsd\b`, no `\bgsd --`, no `which gsd\b`, no `npm install -g gsd\b`, no `npm install -g get-shit-done\b`. All five PASS. Also preemptively rephrased two comments (L8 `NOT the three-letter slug` vs RESEARCH's `NOT gsd`; L17 `without privilege escalation` vs RESEARCH's `without sudo or EACCES`) — plan quality-gate note explicitly allows comment rephrasings to reduce catalog-auditor grep false-positives.
- **Files modified:** plugin/catalog/agents/gsd/install.sh (2 comment lines rephrased; rest of file verbatim-RESEARCH).
- **Verification:** All other AC greps pass byte-for-byte; live end-to-end install+uninstall smoke passes; intent-level binary-invocation negative greps all pass.
- **Committed in:** `a8a9a18` (Task 1 commit).

**2. [Rule 1 — transient flake] AGT-02 release-gate test flaked once on Docker ubuntu-24.04**

- **Found during:** Verification — first Docker ubuntu-24.04 run
- **Issue:** Test 57 (AGT-02 release-gate, the canonical `claude update` test shipped in Plan 05-01) failed with exit code 124 and empty output — classic `timeout 120s` SIGTERM on the real `claude update` call against the live Anthropic CDN (downloads ~8 MB binary). The test's own docstring acknowledges: "120s gives a safety margin against slow CI network + installer-side checksum verify."
- **Fix:** Not a code bug — flake. Confirmed by:
  - Exit code 124 = `timeout` command's SIGTERM exit
  - Output empty (connection cut before any line printed)
  - Test is entirely unrelated to gsd recipe (tests `claude-code` update path)
  - Retry in the same git state: 57/57 green on ubuntu-24.04
  - ubuntu-22.04 first-run: 57/57 green (same code, different container — confirms not a Docker-image issue)
- **Files modified:** None (flake, not code).
- **Verification:** Docker ubuntu-24.04 retry 57/57 green; Docker ubuntu-22.04 first-run 57/57 green; harness meta-tests 104/104 green.
- **Committed in:** N/A — no fix needed.

---

**Total deviations:** 2 auto-fixed (1 spec-grep contradiction resolved by intent-level interpretation, 1 pre-existing network flake in unrelated test).
**Impact on plan:** Zero scope creep. Deviation §1 is a documentation issue in the AC wording (grep `-w` vs `\b` semantics) — intent preserved, verbatim-RESEARCH body kept. Deviation §2 is external flakiness in a test owned by Plan 05-01 and has nothing to do with this plan's scope.

## Issues Encountered

### gsd-sdk CLI unavailable in execution environment

- **Symptom:** `gsd-sdk: command not found` when attempting `gsd-sdk query init.execute-phase` or `gsd-sdk query state.*` handlers.
- **Root cause:** The executor host has `$HOME/.claude/get-shit-done/` installed (v1.37.1, confirmed via `cat VERSION`) but the `gsd-sdk` CLI binary is not on PATH. The `bin/` directory contains `gsd-tools.cjs` and `lib/*.cjs` but no `gsd-sdk` entrypoint.
- **Resolution:** Executed plan directly from the PLAN.md file (all required context accessible via `Read`). State updates will be performed manually below (STATE.md / ROADMAP.md / REQUIREMENTS.md) using the same Edit/Write primitives. This is the same path Plan 05-01 followed for its atomic manual updates.
- **Impact:** None on the shipped recipe; purely a workflow-tooling issue. Bears mentioning in case the executor host needs a `gsd-sdk` CLI install before later phases.

## Review Loop

- **Reviewers dispatched (inline, via rubric):** catalog-auditor, bash-engineer, security-engineer, qa-engineer (plan matches `^plugin/catalog/agents/.+/.+\.sh$` dispatch rule).
- **Iterations:** 1 (no fixes needed after first pass).
- **Findings:**
  - **bash-engineer:** shellcheck --severity=warning clean, shfmt `-i 2 -ci -bn` clean, `set -euo pipefail` at top of both files, all variables quoted, no `|` without pipefail inheritance. No findings.
  - **security-engineer:** no `eval`, no `xargs -I {}`, no word-splitting in command substitutions, no secrets echoed, no `/etc/sudoers.d` writes, no sudo calls, no curl fetches (only input is `${AGENTLINUX_PINNED_VERSION}` which is schema-validated semver). No findings.
  - **catalog-auditor:** `validate-catalog.mjs` exit 0 (4 entries OK), symmetric uninstall present, no `/usr/local/` writes, no wrapper shims, no unsanitized input into shell commands. As with claude-code install.sh in Plan 05-01: catalog recipe does NOT source `plugin/lib/as_user.sh` (privilege drop happens upstream in `plugin/cli/src/runner.ts` via `asUser("agent", ["bash", recipePath], { env })`); this matches the post-Phase-4 dispatch architecture. No findings.
  - **qa-engineer:** negative-env smoke passes (unset `AGENTLINUX_PINNED_VERSION` → exit 1 with `AGENTLINUX_PINNED_VERSION not set` on stderr), bash -n passes on both files, end-to-end host smoke passes (install+uninstall+re-uninstall all exit 0), AGT-04 bats @test not in scope (lands in Plan 05-04). No findings.
- **Triage verdict:** STOP — remaining comments would be out-of-scope stylistic preferences.

## User Setup Required

None — no external service configuration required. Recipe consumes only `AGENTLINUX_PINNED_VERSION` (from catalog.json at dispatch time) and writes only under the agent user's `$HOME/.npm-global/`.

## Next Phase Readiness

- **Plan 05-03 (playwright recipe):** Can now follow the npm-kind Pattern 6 + 7 + 8 established here. Playwright differs (needs `npx playwright install chromium` AND `sudo playwright install-deps` per ADR-012 — more involved) but the `npm install -g` skeleton is identical.
- **Plan 05-04 (50-agents.bats consolidated bats):** AGT-04 bats @test will now exercise this recipe via `agentlinux install --force gsd` + `command -v get-shit-done-cc` + `get-shit-done-cc --help | grep -q v1.37.1` against a provisioned Docker container.
- **Blockers:** None.

## Self-Check: PASSED

**Files claimed created/modified (all verified present):**
- [x] `plugin/catalog/agents/gsd/install.sh` — FOUND (51 lines, `-rwxr-xr-x agent:agent`, bash -n OK, shellcheck OK, shfmt OK).
- [x] `plugin/catalog/agents/gsd/uninstall.sh` — FOUND (19 lines, `-rwxr-xr-x agent:agent`, bash -n OK, shellcheck OK, shfmt OK).
- [x] `.planning/phases/05-agent-installability/05-02-SUMMARY.md` — FOUND (this file).

**Commits claimed exist (verified in `git log --oneline`):**
- [x] `a8a9a18` — `feat(05-02): real gsd install.sh + uninstall.sh (AGT-04)` — FOUND.

**Gates executed and passed:**
- [x] shellcheck --severity=warning — exit 0
- [x] shfmt -i 2 -ci -bn -d — exit 0 (no diff)
- [x] bash -n both files — exit 0
- [x] Negative-env smoke (`unset AGENTLINUX_PINNED_VERSION`) — exit 1 with correct stderr
- [x] validate-catalog.mjs — exit 0 (4 entries OK)
- [x] Docker matrix ubuntu-22.04 — 57/57 green
- [x] Docker matrix ubuntu-24.04 — 57/57 green (on retry after AGT-02 network flake — Deviation §2)
- [x] Harness meta-tests (`bash tests/harness/run.sh`) — 104/104 green
- [x] End-to-end host smoke (install + uninstall + re-uninstall idempotency) — all exit 0
- [x] Banner-grep mechanism verified against live `get-shit-done-cc@1.37.1 --help` output — `v1.37.1` substring present at line 9 (through ANSI color codes).

---
*Phase: 05-agent-installability*
*Completed: 2026-04-19*
