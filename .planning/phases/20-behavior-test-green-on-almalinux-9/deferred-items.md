# Phase 20 — Deferred Items (out-of-scope discoveries)

Logged per the executor scope boundary: these RED tests were surfaced by the
first complete in-order EL9 run (Plan 20-05, `bash tests/docker/run.sh
almalinux-9`, 251/257) but live in files OUTSIDE the 20-05 plan scope
(`tests/bats/15-detection.bats`, `tests/bats/helpers/tty-driver.py`). They are
NOT DET-03 (which is now green) and NOT regressions — before the Plan 20-05
tty-driver timeout the suite hung at test ~138 and never reached them. The
bounded timeout converts the UX-04 hang into a fast, diagnosable failure so the
suite now completes and these became observable.

## Discovered by Plan 20-05 (authoritative EL9 full-suite run, 2026-06-28)

### 1. UX-04 alt-user TTY flow — 5 reds in `tests/bats/15-preflight-ux.bats`
- Tests 137–141 (UX-04 accept-suggested / accept-typed / decline-and-bail /
  non-TTY bail-with-hint / input-validation).
- Root cause (observed in the run log): on the EL9 wrong-shell brownfield
  fixture the installer enters a `npm-prefix` remediation prompt
  (`Proceed with this remediation? [Y/n] (npm-prefix — chown ~agent/.npm-global
  to agent:agent)`) BEFORE/instead of the expected alt-user prompt, so the
  test's typed input (`mybot`, Enter, EOF, metachar-injection) lands on the
  wrong prompt. This is an EL9 brownfield-baseline state / installer-branch
  difference, i.e. a `15-preflight-ux` + brownfield-fixture generalization gap.
- Disposition: a follow-up `15-preflight-ux` / brownfield item. Out of 20-05
  scope (20-05 only added the defensive timeout, which now makes these
  fast-fail at exit 124 instead of hanging ~13 min).

### 2. BHV-52b inline `dpkg-query` — 1 red in `tests/bats/52-agt02-brownfield-gate.bats`
- Test 253 (BHV-52b setup_brownfield_host_full helper validation), line 122:
  `dpkg-query -W -f='${Status}' nodejs | grep -q "install ok installed"` →
  `dpkg-query: command not found` on EL9.
- Root cause: an un-generalized Debian-hardcoded package query INLINE in the
  test file (the Plan 20-02 CI grep guard only covered
  `tests/bats/helpers/brownfield.bash`, not this `.bats` file). Route it through
  `distro_pkg_is_installed` (already in `distro.bash`).
- Disposition: a follow-up brownfield-family generalization item. Out of 20-05
  scope.
