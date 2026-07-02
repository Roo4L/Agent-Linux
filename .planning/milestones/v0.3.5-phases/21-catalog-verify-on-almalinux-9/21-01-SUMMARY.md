# Phase 21 Plan 01 — Summary

**Completed:** 2026-06-29
**Requirement:** REC-01 (Done)

## What shipped

The playwright-cli catalog recipe now makes Chromium genuinely launchable on
AlmaLinux 9 **and** Ubuntu, closing a pre-existing symmetric gap surfaced by the
Phase 21 on-box smoke. claude-code and gsd needed no EL9 changes (Phase 20 already
proved them green).

### Changes
- `plugin/catalog/agents/playwright-cli/install.sh` — new family-dispatched
  browser-launch-deps step after `install --skills`: inline `/etc/os-release`
  family detection; **debian** → bundled Playwright `install-deps chromium`
  (located via a hoisting/exports-tolerant `require.resolve('playwright/package.json')`
  lookup); **rhel** → explicit on-box-verified `dnf install` list. Fail-closed.
- `plugin/catalog/agents/playwright-cli/uninstall.sh` — documented the deliberate
  asymmetry (shared OS browser-deps are not removed).
- `tests/bats/50-agents.bats` — AGT-06 locks the launch capability (ldd-clean +
  headless launch) on both Docker rows.
- `docs/internals/playwright.md` — corrected a factual inaccuracy (the old text
  claimed `--skills` auto-installs apt deps; no such logic existed) and rewrote to
  the real family-dispatched flow.
- `docs/internals/README.md` — TOC blurb synced.
- `.planning/REQUIREMENTS.md` — REC-01 → Done.

## Key decisions / discoveries
- The Chromium launch gap is **symmetric** across families (EL9 20 missing libs,
  Ubuntu 24) — not an EL9 regression. Resolved by the user choosing to fix launch
  on **both** families rather than leave the gap.
- `@playwright/cli` bundles classic `playwright`, so `install-deps` (apt) is
  reachable on debian; it has **no dnf path**, so EL9 needs the explicit list.
- Verified EL9 dnf list: `nss nspr atk at-spi2-atk at-spi2-core cups-libs libdrm
  mesa-libgbm pango cairo alsa-lib libxkbcommon libX11 libXcomposite libXdamage
  libXext libXfixes libXrandr libxcb libxshmfence`.

## Verification
Full bats suite **258/258 PASS on almalinux-9 and ubuntu-24.04**. Review loop
(10 reviewers) clean after fixing one CRITICAL test bug (AGT-06 `grep -c` errexit
inversion) and one Medium (hoisting-fragile cli.js path).

## Deviations
Phase 21 grew from "verify + resolve question" to "verify + close the launch gap
on both families" per the user's explicit scope decision (2026-06-29). The Ubuntu
recipe changed (relaxing the byte-for-byte-preserve guideline) — sanctioned by
that decision, and it fixes a real Ubuntu bug, not just an EL9 one.
