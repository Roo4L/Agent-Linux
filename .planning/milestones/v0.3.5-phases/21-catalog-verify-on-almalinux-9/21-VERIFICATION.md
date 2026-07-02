# Phase 21 Verification — Catalog Verify on AlmaLinux 9 (REC-01)

**Verified:** 2026-06-29
**Verdict:** PASS (goal achieved)

## Goal-backward check

> The three catalog agents install and pass their health checks on AlmaLinux 9,
> resolving the open Playwright-Chromium question by on-box smoke; per the user
> scope decision, make the browser launchable on both families.

| Sub-goal | Evidence | Verdict |
|---|---|---|
| claude-code + gsd port unchanged to EL9 | Phase 20 `50-agents.bats` 11/11 + `51/52-agt02` real installs on EL9 row | PASS |
| Playwright-Chromium question resolved by on-box smoke | 21-RESEARCH §Finding 1-4: `install --skills` downloads a Chromium binary whose launch closure is unsatisfied symmetrically (EL9 20, Ubuntu 24); no EL9-only path launches it in the health-check contract | PASS |
| Browser launches on both families (user scope decision) | Recipe deps step: Playwright `install-deps` (debian) + verified `dnf` list (rhel). On-box: post-deps `ldd` clean + headless launch exit 0 on both | PASS |
| Locked by a behavior test | **AGT-06** (`tests/bats/50-agents.bats:323`) — ldd-clean + headless `--dump-dom about:blank` exit 0, same observable both families | PASS |
| No regression | Full bats suite **258/258 PASS on both `almalinux-9` and `ubuntu-24.04`** (was 257; +AGT-06) | PASS |

## Authoritative test run (2026-06-29)

```
== PASS: agentlinux-install + bats on almalinux-9 ==   ok 258 / not-ok 0
== PASS: agentlinux-install + bats on ubuntu-24.04 ==   ok 258 / not-ok 0
ok 251 AGT-06: playwright-cli Chromium shared-lib closure is satisfied and it launches headless
```

Both rows ran the full provision + `agentlinux install {claude-code,gsd,playwright-cli}`
in `setup_file`, so the recipe's new browser-launch-deps step executed against a
real install on both families before AGT-06 asserted the launch.

## Review loop

10 reviewers (catalog-auditor, security, bash, ai-deslop, qa, behavior-coverage,
technical-writer, fact-checker, external-audience, dev-docs). One CRITICAL
(qa-engineer: AGT-06 `grep -c` errexit inversion) and one Medium (catalog-auditor:
hoisting-fragile cli.js path) found and fixed; the rest minor doc/comment polish,
all applied. Re-lint clean; resolver + AGT-06 fix re-verified on-box and via the
258/258 green re-run.

## Gates

- shellcheck (recipe) — clean
- distro-leak guard — pass
- catalog schema — unaffected (no schema-governed JSON changed)
- behavior-coverage (TST-07) — REC-01 covered by AGT-06, bidirectional traceability

## Out of scope (Phase 22)

Real enforcing-SELinux EL9 QEMU row; AGT-02 zero-EACCES milestone-close gate;
release-pipeline gate flip. Browser-launch deps on a *real* EL9 guest re-confirm
naturally in the Phase 22 QEMU run.
