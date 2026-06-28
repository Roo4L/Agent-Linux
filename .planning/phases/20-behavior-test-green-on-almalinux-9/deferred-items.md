# Phase 20 — Deferred Items (out-of-scope discoveries)

Logged per the executor scope boundary. The two items below were surfaced by the
first complete in-order EL9 run (Plan 20-05, `bash tests/docker/run.sh
almalinux-9`, 251/257) but lived in files OUTSIDE the 20-05 plan scope. Both were
CLOSED by Plan 20-06 (the gap-closure plan) — the EL9 suite now runs 257/257
GREEN. They are retained here as provenance, marked CLOSED; nothing in this file
is still outstanding.

## Discovered by Plan 20-05 (authoritative EL9 full-suite run, 2026-06-28)

### 1. UX-04 alt-user TTY flow — 5 reds in `tests/bats/15-preflight-ux.bats` — CLOSED (Plan 20-06)
- Tests 137–141 (UX-04 accept-suggested / accept-typed / decline-and-bail /
  non-TTY bail-with-hint / input-validation).
- Root cause: the wrong-shell fixture hardcoded `/bin/sh` as "the wrong shell".
  That is a Debian-only assumption — on Debian `/bin/sh → dash` (a non-bash but
  functional login shell), but on RHEL/EL9 `/bin/sh → bash`, so the product's
  `reuse::user_decision` (`readlink -f` against {/bin/bash,/usr/bin/bash})
  correctly deemed the agent bash-compatible, the wrong-shell bail never fired,
  and the UX-04 alt-user gate never triggered (the run drifted into an
  npm-prefix remediation prompt instead). This is a TEST/FIXTURE generalization
  gap, NOT a product defect (the product behaves correctly per family).
- Fix (Plan 20-06): family-dispatch the wrong shell via a new
  `distro_wrong_shell` verb — `/bin/sh` on Debian (verbatim, byte-identical
  Ubuntu rows) and `/usr/bin/tcsh` on RHEL/EL9 (a real, non-bash login shell;
  `/sbin/nologin` is non-bash but breaks the `as_user_login` detection probes,
  so tcsh is provisioned idempotently from AppStream). Test 13's `/bin/sh`
  assertion was generalized through the same verb. EL9 137–141 now GREEN; Ubuntu
  unchanged. No `plugin/` edit.

### 2. BHV-52b inline `dpkg-query` — 1 red in `tests/bats/52-agt02-brownfield-gate.bats` — CLOSED (Plan 20-06)
- Test 253 (BHV-52b setup_brownfield_host_full helper validation), line 122:
  `dpkg-query -W -f='${Status}' nodejs | grep -q "install ok installed"` →
  `dpkg-query: command not found` on EL9.
- Root cause: an un-generalized Debian-hardcoded package query INLINE in the
  `.bats` file (the Plan 20-02 grep guard only covered
  `tests/bats/helpers/brownfield.bash`, not this `.bats` file).
- Fix (Plan 20-06): routed through `distro_pkg_is_installed nodejs`
  (`rpm -q` on rhel, `dpkg-query` on debian). Test 253 now GREEN on EL9.
- Regression prevention: Plan 20-06 also broadened the guard into an enforced
  pre-commit + CI hook (`scripts/check-distro-leak.sh`) that scans the WHOLE
  bats tree (every `tests/bats/*.bats` + `helpers/*.bash`), not just
  brownfield.bash, so this class cannot regress silently.
