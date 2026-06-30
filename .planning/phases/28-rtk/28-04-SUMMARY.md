---
phase: 28-rtk
plan: 04
subsystem: testing
tags: [bats, catalog, prebuilt-binary, rtk, verify-before-extract, ops-smoke, dev-docs]

# Dependency graph
requires:
  - phase: 28-02
    provides: "plugin/catalog/lib/prebuilt-binary.sh + al_pb_fetch_and_verify (the verify-before-extract gate the negative test drives)"
  - phase: 28-03
    provides: "rtk catalog entry + install.sh/uninstall.sh (the lifecycle + opt-in hook the bats file exercises)"
provides:
  - "tests/bats/57-catalog-binary.bats — the TST-07/OPS-01 gate for Phase 28 (4 @tests, green on Docker Ubuntu 24.04)"
  - "ENABLE-01 proof: checksum-verified fetch → ~/.local/bin (no root/shim/EACCES) → symmetric residue-free remove → idempotent re-remove → verify-before-extract abort"
  - "WORK-02 proof: pin from catalog, opt-in ~/.claude hook wired by `rtk init -g` and reverted by remove (no orphan)"
  - "OPS-01 smoke: a real offline rtk op (token-optimized ls) as the agent user, no credential"
  - "docs/internals/catalog.md — the prebuilt-binary source_kind section (product voice)"
affects: [29-gh, 30-glab, 31-trivy, 32-gitleaks, 33-sentry-cli]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Offline negative-checksum fixture: drive al_pb_fetch_and_verify via file:// against a locally-corrupt asset + wrong-hash checksums.txt (one real network download = the happy path only)"
    - "Absolute /home/agent/... paths in every bats command string (SC2088: ~ does not expand in a quoted bash -c argument)"
    - "jq-derived pin from the provisioned /opt/agentlinux/catalog/<ver>/catalog.json, guarded non-empty/non-null (never hardcoded)"
    - "Binary-lifecycle driver: command -v resolves under ~/.local/bin (not /usr/local), residue checks on ~/.config + ~/.local/share, idempotent re-remove"

key-files:
  created:
    - tests/bats/57-catalog-binary.bats
  modified:
    - docs/internals/catalog.md

key-decisions:
  - "Negative test asserts a non-zero exit AND a 'verification failed' message AND no binary written — distinguishes a real rejection from any other non-zero path"
  - "Opt-in test asserts on rtk's own ~/.claude/RTK.md artifact (pre-absent → present after `rtk init -g` → absent after remove) and never touches the user-owned settings.json (threat T-28-14)"
  - "OPS-01 op is `rtk ls <tmpdir>` listing a uniquely-named seeded marker — deterministic and credential-free (Appendix C: rtk needs none)"

patterns-established:
  - "Binary source_kind bats lifecycle template reusable by phases 29-33 (gh/glab/trivy/gitleaks/sentry-cli)"

requirements-completed: [ENABLE-01, WORK-02, OPS-01]

# Metrics
duration: 3min
completed: 2026-06-30
---

# Phase 28 Plan 04: rtk prebuilt-binary lifecycle gate Summary

**`tests/bats/57-catalog-binary.bats` (4 @tests, green on Docker Ubuntu 24.04) is the executable proof of Phase 28: it drives rtk's full prebuilt-binary lifecycle (checksum-verified fetch → `~/.local/bin` with no root / no `/usr/local` shim / no EACCES → version-lock against the jq-derived catalog pin → symmetric residue-free remove → idempotent re-remove), proves the WORK-02 opt-in contract (a bare install never mutates `~/.claude`; `rtk init -g` wires the hook; remove reverts it with no orphan), proves verify-before-extract with an OFFLINE negative-checksum fixture, and runs a real OPS-01 offline rtk op as the agent user — plus a product-voice `binary` source_kind section in `docs/internals/catalog.md`.**

## Performance

- **Duration:** ~3 min (authoring) + one full Docker validation run
- **Started:** 2026-06-30T19:05:49Z
- **Completed:** 2026-06-30T19:12Z
- **Tasks:** 2
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments

- `tests/bats/57-catalog-binary.bats` (229 lines, 4 @tests) — shellcheck-clean (`--severity=warning --shell=bash --external-sources`), shfmt-clean (`-i 2 -ci -bn`), pre-commit clean. Models `53-catalog-npm-cluster.bats` for the jq-pin + `__fail` + login-shell discipline and `56-catalog-skill-wiring.bats` for absolute-path discipline.
  1. **ENABLE-01 lifecycle** — install (exit 0, no EACCES) → `command -v rtk` resolves exactly at `/home/agent/.local/bin/rtk` (not `/usr/local`) → `rtk --version` contains the catalog pin (jq-derived) → `agentlinux remove --force rtk` drops the binary AND `~/.config/rtk` AND `~/.local/share/rtk` (no residue) → second remove exits 0 (idempotent).
  2. **WORK-02 opt-in** — a bare install leaves `~/.claude/RTK.md` absent; `rtk init -g --auto-patch` creates it; remove reverts it and drops `~/.claude/settings.json.bak` (no orphan hook). Never touches the user-owned `settings.json` (threat T-28-14).
  3. **ENABLE-01 negative-checksum** — the one OFFLINE test: stage a real-gzip-but-wrong-checksum asset + a bad `checksums.txt` in a tmpdir, drive `al_pb_fetch_and_verify` via `file://`, and assert a non-zero exit + a "verification failed"-class message + NO binary written. The real-gzip body makes the rejection the SHA-256 gate specifically, not the magic-byte guard.
  4. **OPS-01 smoke** — install rtk, seed a uniquely-named marker file in a tmpdir, run `rtk ls <tmpdir>` as the agent user, assert the marker appears. Credential-free (Appendix C).
- `docs/internals/catalog.md` — new "Source kinds: npm, script, and prebuilt binary" section documenting the `binary` kind (pinned release → verify-before-extract checksum → agent-owned `~/.local/bin`, no root/shim), the shared `plugin/catalog/lib/prebuilt-binary.sh` helper, and rtk as the first consumer. Product voice; zero internal requirement IDs (external-audience / dev-docs scope).

## OPS-01 Phase-Close Gate — RUN AND PASSED

Per the REQUIREMENTS.md OPS-01 contract ("a phase is done only once its OPS-01 smoke has been run + passed at least once"), the rtk OPS-01 smoke was executed on the Docker Ubuntu 24.04 harness and **passed**:

```
ok 234 ENABLE-01: rtk install fetches+checksum-verifies a binary into ~/.local/bin (no root/shim/EACCES) and removes symmetrically
ok 235 WORK-02: rtk install does NOT mutate ~/.claude; opt-in rtk init -g wires the hook; remove reverts it (no orphan)
ok 236 ENABLE-01: a mismatched checksum aborts BEFORE extract (binary not installed/replaced)
ok 237 OPS-01: rtk performs a real offline operation as the agent user
```

Full suite: `== PASS: agentlinux-install + bats on ubuntu-24.04 ==` (241 ok, 0 failures). rtk needs no credential, so the OPS-01 op runs unconditionally (unlike the cluster's model-call smokes that `skip` without API keys).

## Task Commits

Each task committed atomically (hooks ON — shellcheck, shfmt, secret-scan all green):

1. **Task 1: 57-catalog-binary.bats (lifecycle + opt-in + negative + OPS-01)** — `72056d2` (test)
2. **Task 2: docs/internals/catalog.md prebuilt-binary section** — `d0dd7ef` (docs)

**Plan metadata:** (final commit — SUMMARY + STATE + ROADMAP + REQUIREMENTS)

## Files Created/Modified

- `tests/bats/57-catalog-binary.bats` — the Phase 28 TST-07/OPS-01 gate (4 @tests).
- `docs/internals/catalog.md` — appended the prebuilt-binary source_kind section between the auto-update-freeze paragraph and the worked example.

## Decisions Made

- **The OPS-01 op is `rtk ls <tmpdir>`** (token-optimized listing of a seeded marker file) rather than `rtk gain`. It is deterministic — a uniquely-named marker either appears in the output or it does not — and credential-free. Validated green in Docker; satisfies the `rtk (ls|gain|proxy)` "real subcommand, not just --version" requirement.
- **The negative test stays offline via `file://`.** The plan/research mandate keeping the one real network download to the happy path. Driving `al_pb_fetch_and_verify` against a locally-staged corrupt asset proves the verify-before-extract gate deterministically in Docker without a second download.
- **The opt-in test asserts on `~/.claude/RTK.md`**, rtk's own artifact, for the pre-absent → present → absent cycle, and never deletes the shared user-owned `settings.json` — only rtk-owned `RTK.md` / `settings.json.bak` (threat T-28-14 / V4 boundary).

## Deviations from Plan

None — plan executed exactly as written. Both tasks' acceptance greps pass; the full Docker Ubuntu 24.04 suite is green (241 ok, 0 failures) including all four new @tests. No Rules 1-4 deviations.

## Issues Encountered

- **Pre-existing CLI unit-test failure (out of scope, unchanged).** `cd plugin/cli && pnpm test` still reports one failing file (`install.test.js`, the REUSE-03 pre-runner suite) carried over from 28-03's `deferred-items.md`. This plan touches no CLI source and does not affect it; left as logged.

## Next Phase Readiness

- `57-catalog-binary.bats` is the worked bats template for phases 29-33: each new binary tool (gh, glab, trivy, gitleaks, sentry-cli) reuses the lifecycle + negative-checksum + OPS-01 shape against the same `al_pb_install` / `al_pb_fetch_and_verify` helper, swapping only the catalog id and the OPS-01 op.
- Phase 28 (rtk 🔧 / ENABLE-01 prebuilt-binary) requirements ENABLE-01 + WORK-02 are now bats-proven end-to-end with the OPS-01 smoke passed — the phase is ready for its close-out.

---
*Phase: 28-rtk*
*Completed: 2026-06-30*

## Self-Check: PASSED

- tests/bats/57-catalog-binary.bats: FOUND
- docs/internals/catalog.md (prebuilt-binary section): FOUND
- .planning/phases/28-rtk/28-04-SUMMARY.md: FOUND
- Commit 72056d2 (test): FOUND
- Commit d0dd7ef (docs): FOUND
- Docker Ubuntu 24.04: 57-catalog-binary.bats 4/4 green (tests 234-237); full suite 241 ok / 0 failures
