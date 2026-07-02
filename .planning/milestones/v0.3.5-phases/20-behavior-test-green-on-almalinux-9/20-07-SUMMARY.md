---
phase: 20
plan: 20-07
subsystem: test-harness
tags: [review-fix, distro-dispatch, leak-guard, ci-gate]
provides: [el9-parity-helper-fidelity, hard-pr-gate-almalinux-9]
key-files:
  modified:
    - tests/bats/helpers/distro.bash
    - tests/bats/helpers/tty-driver.py
    - tests/bats/15-preflight-ux.bats
    - tests/bats/10-installer.bats
    - scripts/check-distro-leak.sh
    - .github/workflows/test.yml
metrics:
  completed: 2026-06-28
---

# Phase 20 Plan 20-07: Review-Fix Pass Summary

Applied seven code-review findings against the Phase 20 EL9 test-harness/helpers/CI
(no plugin/ product code touched): restored helper↔product fidelity for the
NodeSource repo snapshot, hardened two RHEL helper arms to fail loudly instead of
silently, broadened the distro-leak guard, trimmed rotting plan-archaeology
comments, and flipped almalinux-9 to a hard PR gate now that EL9 is green.

## Changes

- **F1 (helper false-green fix):** `distro_nodesource_repo_paths` rhel arm now
  emits BOTH `nodesource-nodejs.repo` AND `nodesource-nsolid.repo`, mirroring the
  product source-of-truth `nodesource_repo_paths` in `plugin/lib/pkg.sh`. The
  INST-02 byte-stability snapshot (`10-installer.bats`) now snapshots the nsolid
  repo too, so a mutation to it can no longer pass undetected on EL9.
- **F2 (test-fidelity):** `distro_restore_ssh_context` rhel arm restructured to
  `if command -v restorecon …; then restorecon -R -F "$dir"; fi` — absence stays a
  no-op (Docker) but a genuine restorecon failure now propagates (Phase 22 QEMU
  enforcing). Dropped the `|| true` that masked real failures.
- **F3 (fail-loud fixture):** `distro_wrong_shell` rhel arm re-checks
  `command -v tcsh` after the install attempt and `return 1` + stderr diagnostic if
  still absent, so a failed `dnf install tcsh` fast-fails instead of producing a
  `useradd -s /usr/bin/tcsh` against a missing shell.
- **F4 (stale comment):** `15-preflight-ux.bats` ~line 339 corrected from
  "/sbin/nologin on RHEL/EL9" to "/usr/bin/tcsh on RHEL/EL9" to match
  `distro_wrong_shell`. Comment-only; assertion was already sound.
- **F5 (leak-guard regex):** broadened `leak_re` to catch flag-first
  `apt-get -y install`, bare `dpkg`/`dpkg -l`, `apt install|update|cache`, and
  `add-apt-repository` — dropping the narrow trailing `[a-z]` anchor. Allowlist
  (18-pkg-dispatch, 18-detect-el9, distro.bash) and full-line-comment stripping
  preserved.
- **F6 (comment trims):** removed rotting line-number / plan-archaeology
  references in `distro.bash`, `check-distro-leak.sh`, and `tty-driver.py` while
  keeping the durable rationale.
- **F7 (CI hard gate):** `test.yml` `bats-docker` — removed the `almalinux-9`
  experimental include entry; the arm is now a hard PR gate. `continue-on-error`
  line left as a harmless no-op (re-introducing an experimental arm needs no
  plumbing change). Comment updated to note Phase 20 made it hard and Phase 22
  owns the release gate. `release.yml` gate-2-docker left UNCHANGED (Phase 22
  REL-01 owns that flip).
- **Forward note (bash-engineer):** added a comment on `distro_family`'s
  `*)→debian` catch-all noting a 3rd EL distro must add an explicit rhel match.

## Verification

- `shellcheck --severity=warning` clean: distro.bash, brownfield.bash,
  check-distro-leak.sh.
- `scripts/check-distro-leak.sh` passes clean on the tree AND fires on injected
  flag-first `apt-get -y install nodejs`, bare `dpkg -l`, `apt install`, and
  `add-apt-repository` leaks.
- Both `.github/workflows/test.yml` and `release.yml` parse as valid YAML;
  test.yml almalinux-9 is no longer experimental; release.yml unchanged.
- EL9 Docker targeted re-run (real almalinux-9 container, full installer + bats):
  - First pass `10-installer / 15-preflight-ux / 20-agent-user / 50-agents`:
    53 ok / 1 not ok — the single failure was INST-02 (see Deviation below).
  - After the consumer fix: `10-installer.bats` = 11/11 green (INST-02 included).
    Confirmed on-disk that the EL9 installer drops BOTH
    `/etc/yum.repos.d/nodesource-nodejs.repo` AND `…/nodesource-nsolid.repo`
    (262 bytes each), so the broadened snapshot is meaningful (the nsolid file
    is now hashed; a mutation to it can no longer pass undetected).
  - The other three files (15-preflight-ux UX-04 tcsh fixture F3/F4;
    20-agent-user / 50-agents restorecon path F2) were green in the first pass;
    none touch the INST-02 file-list, so they were unaffected by the fix.
  - Ubuntu rows untouched: distro.bash debian arms and the leak guard do not
    change any Debian-side behavior (debian arms byte-identical).

## Deviations from Plan

**[Rule 3 — blocking] INST-02 consumer needed array expansion for the two-path
rhel output.** `10-installer.bats` fed the helper output through a DOUBLE-QUOTED
`"$(distro_nodesource_repo_paths)"` into two `find` invocations. With the F1
change the rhel arm now emits two newline-separated paths; double-quoting
collapsed them into a single bogus argument with an embedded newline, so `find`
failed and INST-02 went red on the first EL9 pass. Fixed (test-harness only, no
product code) by reading the helper output into a `mapfile -t ns_repos` array and
expanding `"${ns_repos[@]}"` as separate `find` operands — shellcheck-safe and
correct for both families (debian still emits exactly one path). Re-verified
INST-02 green on EL9. This is the consumer half of F1; the plan flagged "re-verify
INST-02 stays green," which required this adjustment. No architectural conflict —
the helper was strictly behind pkg.sh and bringing it to parity is purely additive.
