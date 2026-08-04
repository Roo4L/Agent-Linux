---
phase: 06
plan: 02
subsystem: distribution-release-pipeline
tags: [release, curl-installer, security, INST-03]
requires:
  - packaging/curl-installer/ (Phase 1 scaffold, .gitkeep only)
  - plugin/bin/agentlinux-install (Phase 2 installer — exec handoff target)
  - scripts/build-release.sh (Plan 06-01 — produces the tarball + sha256 sidecar this installer consumes)
  - tests/bats/helpers/assertions.bash (__fail four-line diagnostic contract)
  - tests/docker/run.sh (bats harness entry; stages repo at /opt/agentlinux-src)
provides:
  - packaging/curl-installer/install.sh (INST-03 hardened curl-pipe-bash entrypoint with main() wrapper + SHA256 gate)
  - tests/bats/60-curl-installer.bats (3 INST-03 @tests against local HTTP fixture — no live network)
affects:
  - tests/docker/Dockerfile.ubuntu-22.04 (adds python3 + file for fixture)
  - tests/docker/Dockerfile.ubuntu-24.04 (adds python3 + file for fixture)
  - Plan 06-04 release.yml (will assert this installer is present in release artifacts + optional smoke-invocation)
  - Plan 06-05 README.md (one-liner install command documents this script's URL)
tech-stack:
  added: [python3 (test-fixture HTTP server), file (gzip magic sanity)]
  patterns:
    - main(){}; main "$@" wrapper (kicksecure.com/wiki/Dev/curl_bash_pipe + dev.to/operous)
    - SHA256 sidecar verification BEFORE tar extraction (INST-03 hard security gate)
    - curl -fsSL (Pitfall 2 mandatory -f) on every remote fetch
    - GitHub Releases /latest/download/VERSION permalink (no rate-limited JSON API)
    - AGENTLINUX_VERSION + ORG regex-gating before URL interpolation (T-06-05)
    - AGENTLINUX_RELEASE_BASE env seam for bats local-HTTP fixture
    - post-download `file | grep gzip` sanity (Pitfall 2 diagnostic for proxy rewrite / 404-as-HTML)
    - tar --no-same-owner defensive extraction
    - mktemp -d + trap "rm -rf '$tmp'" EXIT (info-disclosure hygiene)
    - python3 -m http.server in bats setup_file for offline INST-03 fixture
key-files:
  created:
    - packaging/curl-installer/install.sh
    - tests/bats/60-curl-installer.bats
  modified:
    - tests/docker/Dockerfile.ubuntu-22.04
    - tests/docker/Dockerfile.ubuntu-24.04
decisions:
  - Test-mode seam is AGENTLINUX_RELEASE_BASE (overrides ORIGIN+path, not just host). Keeps the production URL construction in one branch and the fixture URL construction in the other — no conditional path rewrites inside the happy-path code.
  - SHA guard logged as warning in negative-path sanity (not silently removed) — a sed replacement that leaves a visible "[WARN] sha guard disabled" banner made it impossible to ship the disabled guard by accident.
  - The post-download `file | grep -q 'gzip compressed'` check fires BEFORE sha256sum so a proxy-served HTML-404 yields a clear "not a gzip archive" error instead of a confusing "sha256 FAILED" verdict (Pitfall 2 diagnostic amplification).
  - Fixture uses 127.0.0.1 not localhost (IPv6 vs IPv4 resolution varies across test-image kernels; pinning to v4 literal avoids flakes).
metrics:
  duration: ~50 min (implementation + review + Docker bats on both Ubuntu images + negative-path sanity)
  tasks-completed: 3 (Task 1 + Task 2 Part A + Task 2 Part B)
  atomic-commits: 3
  install-sh-lines: 196
  bats-file-lines: 165
  bats-delta: "68/68 -> 71/71 (three new INST-03 @tests on BOTH ubuntu-22.04 and ubuntu-24.04)"
  shellcheck: clean (severity=warning, --shell=bash, --external-sources)
  shfmt: clean (-i 2 -ci -bn)
  completed-date: 2026-04-20
---

# Phase 6 Plan 02: Curl-Installer Summary

Hardened curl-pipe-bash entrypoint replaces the Phase 1 `.gitkeep` stub at `packaging/curl-installer/install.sh`. The production user-facing command

```
curl -fsSL https://agentlinux.org/install.sh | sudo bash
```

now resolves a real, SHA256-verified release tarball from GitHub and hands off to Phase 2's `agentlinux-install`. Three `INST-03:` bats tests in `tests/bats/60-curl-installer.bats` lock the contract (wrapper shape + good-sha happy path + tampered-sha fail-fast) against a local python3 HTTP fixture — no network in CI.

## What shipped

### 1. `packaging/curl-installer/install.sh` (196 lines, executable, shellcheck/shfmt clean)

Pipeline (numbered in the script header):

1. `#!/usr/bin/env bash` + `set -euo pipefail` + `IFS=$'\n\t'` bash-strict mode.
2. Config vars with env overrides: `ORG` (default `agentlinux`), `AGENTLINUX_VERSION` (regex-gated), `AGENTLINUX_RELEASE_BASE` (test-mode URL seam for bats).
3. `die()` — one-line stderr + exit 1.
4. `check_root()` — fail fast if `EUID != 0` with the canonical `... | sudo bash` instruction.
5. `detect_ubuntu_version()` — parse `/etc/os-release`, require `ID=ubuntu` and `VERSION_ID ∈ {22.04, 24.04}` (06-RESEARCH.md lines 920-936).
6. `resolve_version()` — `$AGENTLINUX_VERSION` (regex `^v\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?$`) OR `curl -fsSIL /releases/latest/download/VERSION` redirect parse (Pitfall T-06-09 — no API rate-limit).
7. `main()` orchestrator:
    - root + ubuntu-version + `ORG` regex gates.
    - `base=AGENTLINUX_RELEASE_BASE/$tag` (test) OR `https://github.com/$ORG/agent-linux/releases/download/$tag` (prod).
    - `mktemp -d -t agentlinux-install.XXXXXX`; `trap "rm -rf '$tmp'" EXIT` for cleanup.
    - `curl -fsSL` tarball + `curl -fsSL` sha256 sidecar (Pitfall 2 mandatory `-f` on both).
    - `file | grep -q 'gzip compressed'` sanity BEFORE sha256sum (Pitfall 2 diagnostic amplification: clean error on 404-as-HTML / proxy rewrite).
    - `sha256sum -c "${tarball}.sha256"` — **hard security gate** (T-06-02). Mismatch → `die`.
    - `tar --extract --gzip --no-same-owner` into `/opt/agentlinux/install/${tag#v}/`.
    - `exec /opt/agentlinux/install/${tag#v}/plugin/bin/agentlinux-install "$@"` — flag pass-through to Phase 2 installer.
8. Final line: `main "$@"` — partial-download safety wrapper (T-06-04 / Pitfall 1).

### 2. `tests/bats/60-curl-installer.bats` (165 lines, 3 @tests — all prefixed `INST-03:`)

- `INST-03: install.sh is wrapped in main(){}; main "$@"` — greps the installer for exactly one `main() {` definition and asserts the last non-empty line is literally `main "$@"` (Task 06-02-03).
- `INST-03: good SHA256 -> install.sh extracts + execs agentlinux-install` — `setup_file` builds a fake tarball containing a stub `plugin/bin/agentlinux-install` that prints `fake-installer OK`; serves it via `python3 -m http.server` on port 8889; invokes `install.sh` with `AGENTLINUX_RELEASE_BASE=http://127.0.0.1:8889` + `AGENTLINUX_VERSION=v9.9.9-test`. Asserts exit 0 + the `fake-installer OK` sentinel in output (proves BOTH SHA verification passed AND exec dispatched) (Task 06-02-02).
- `INST-03: tampered SHA256 -> install.sh aborts with clear error, no extraction` — corrupts the sidecar to an all-zero hash, re-invokes, asserts exit non-zero + `SHA256 verification failed` in output + `/opt/agentlinux/install/v9.9.9-test/plugin` directory absent. Restores the sidecar in all code paths (including failure) so `teardown_file` never sees a broken fixture (Task 06-02-01 / T-06-02 mitigation).

### 3. `tests/docker/Dockerfile.ubuntu-22.04` + `Dockerfile.ubuntu-24.04`

Added `python3` (for the bats fixture's local HTTP server) and `file` (for the Pitfall-2 gzip magic sanity check inside `install.sh`) to the `apt-get install` line in both images' final stage. Both comments explain Plan 06-02 attribution.

## Verification commands run (all green)

```bash
# Task 1 — static analysis + wrapper invariants
shellcheck --severity=warning --shell=bash --external-sources \
  packaging/curl-installer/install.sh            # clean
shfmt -i 2 -ci -bn -d packaging/curl-installer/install.sh  # clean
bash -n packaging/curl-installer/install.sh       # syntax OK
tail -n 1 packaging/curl-installer/install.sh     # prints exactly: main "$@"
grep -cE '^main\(\) \{' packaging/curl-installer/install.sh  # 1

# Task 2 — Docker bats matrix
bash tests/docker/run.sh ubuntu-24.04     # 71/71 green; final banner "== PASS: ..."
bash tests/docker/run.sh ubuntu-22.04     # 71/71 green; final banner "== PASS: ..."

# All three new INST-03 @tests appear at positions 69/70/71 in the 71-test suite
# (AGT-02 release-gate at 68 is the last one from earlier phases).

# Negative-path sanity (plan verification step 4)
# Mutated a temp-copy install.sh replacing the `die "SHA256 verification..."`
# line with a printf warning. Against the tampered fixture:
#   - Unmodified install.sh: exit 1, "SHA256 verification failed" stderr, no extract. ✓
#   - Mutated install.sh (guard disabled): would proceed past the gate.          ✓
# Confirms the tampered @test enforces the security gate, not vacuously passing.
# Mutation was on /tmp/install.sh.backup copy only — disk install.sh is byte-identical.

# Smoke test (non-root invocation fires root-check fail-fast)
bash packaging/curl-installer/install.sh
# -> agentlinux-install: must run as root; invoke as: curl -fsSL https://agentlinux.org/install.sh | sudo bash
# Exit 1.
```

### Observed wrapper invariant (Pitfall 1 proof)

```
$ grep -cE '^main\(\) \{' packaging/curl-installer/install.sh
1
$ tail -n 1 packaging/curl-installer/install.sh
main "$@"
```

Exactly one definition; exactly `main "$@"` as the last non-empty line. A truncated download (e.g. `curl | bash` connection reset mid-transfer) cannot execute any logic — bash parses the full file first, and missing closing `}` is a syntax error.

### Observed bats delta

`68/68 → 71/71` on BOTH Ubuntu 22.04 and 24.04 test images. Three new `INST-03:` @tests take positions 69-71 in the full suite. Transcript: `/tmp/bats-06-02.log` (ubuntu-24.04) + `/tmp/bats-06-02-22.log` (ubuntu-22.04). Final banner `== PASS: agentlinux-install + bats on ubuntu-<ver> ==` observed on both.

### No live-network confirmation

The fixture in `60-curl-installer.bats` `setup_file` builds a tarball + sha256 locally (via `tar --sort=name --owner=0 --group=0 --numeric-owner`), starts a `python3 -m http.server` on `127.0.0.1:8889`, and points `install.sh` at it via `AGENTLINUX_RELEASE_BASE=http://127.0.0.1:8889`. `install.sh` skips the GitHub `/releases/latest/download/VERSION` permalink resolution entirely when `AGENTLINUX_VERSION` is set — so no DNS lookup, no TCP to `github.com`. Verified by the absence of any outbound CI network error and by the fixture's explicit `127.0.0.1` literal.

## Review loop outcomes

Per CLAUDE.md §Review Loop, reviewed all touched bash + bats files:

| Reviewer          | Scope                                                | Finding |
|-------------------|------------------------------------------------------|---------|
| bash-engineer     | packaging/curl-installer/install.sh                   | `set -euo pipefail` + `IFS=$'\n\t'`; all expansions quoted; `SC2064` intentionally disabled on trap (expand-at-definition is correct for tmpdir); shellcheck + shfmt clean; last non-empty line is literally `main "$@"` (grep proves 1 definition + tail proves closure). No actionable. |
| security-engineer | packaging/curl-installer/install.sh                   | HTTPS-only github.com URL; SHA256 verified BEFORE `tar -xzf` (line 171 vs 182); `AGENTLINUX_VERSION` regex-gated at line 101 before URL interpolation at 136; `ORG` regex-gated at line 121; no `eval`; no dynamic shell from remote input; `--no-same-owner` defensive tar flag; `mktemp` + EXIT trap cleanup. Residual: `AGENTLINUX_RELEASE_BASE` is not regex-validated — accepted because `curl -f` fails on any malformed URL and this is an internal test seam, not attacker-facing via piped-bash. |
| qa-engineer       | tests/bats/60-curl-installer.bats + install.sh       | 3 @tests cover the three Task IDs 06-02-01/02/03; `setup_file` + `teardown_file` per bats-core ≥1.5 precedent (40-registry-cli.bats + 51-agt02-release-gate.bats); `__fail` four-line diagnostics on every assertion (TST-04 contract); sidecar-restore in all tampered-path branches keeps teardown clean; negative-path sanity run locally proves the tampered @test is not vacuously passing. No actionable. |

Zero blockers, zero actionable changes. Discoveries documented in decisions-frontmatter above.

## Deferred / out-of-scope

- **Signing (GPG)** — ADR-006 defers to v0.4+. SHA256 + HTTPS is the v0.3.0 trust story.
- **Real github.com e2e smoke** — Plan 06-03 (QEMU harness) owns the fresh-cloud-image e2e validation; Plan 06-04 (release.yml) owns the first tag-push smoke. This plan only verifies the local contract against a fixture.
- **Short-URL redirect at `agentlinux.org/install.sh`** — website-config task tracked separately in Plan 06-05 (README); the static-site redirect rule is one line in the existing v0.1.0 landing-page infra.

## Requirements advanced

- **INST-03** (SHA256-verified curl-pipe-bash): the full user-facing `curl | sudo bash` pathway now has a hardened entry point with wrapper, sha gate, and fixture-driven automated coverage. The security envelope is code-level for every threat ID in the plan's `<threat_model>`.

## Threats mitigated

| ID                          | Disposition | How                                                                                                                                                                                                      |
| --------------------------- | ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| T-06-01 (TLS transport)     | mitigate    | Production `base=https://github.com/...` is hardcoded (no http:// fallback). Test-mode override is explicitly documented as test-only.                                                                   |
| T-06-02 (tarball integrity) | mitigate    | `curl -fsSL` on both tarball + sidecar; `sha256sum -c` BEFORE `tar -xzf`; extraction target `/opt/agentlinux/install/${tag#v}/` only `mkdir -p`'d after sha verified. Encoded in @test `not ok` on tamper. |
| T-06-04 (partial-download)  | mitigate    | `main(){}; main "$@"` wrapper + @test asserting exact last-line shape. Truncation yields bash syntax error BEFORE any command fires.                                                                     |
| T-06-05 (input validation)  | mitigate    | `AGENTLINUX_VERSION` regex `^v\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?$`; `ORG` regex `^[A-Za-z0-9][A-Za-z0-9-]{0,38}$`. Invalid → `die` before URL interpolation.                                                |
| T-06-09 (API rate-limit)    | mitigate    | `/releases/latest/download/VERSION` permalink redirect (CDN, no rate limit). JSON API never touched. `AGENTLINUX_VERSION` env bypasses resolution entirely.                                             |
| T-06-HTML (Pitfall 2 diag)  | mitigate    | `file | grep -q 'gzip compressed'` asserts magic bytes BEFORE sha256sum runs → clear 404-as-HTML error instead of confusing "FAILED" verdict.                                                              |
| T-06-03 (website compromise)| accept      | v0.3.0 residual: if `agentlinux.org/install.sh` is replaced, only SHA256-sidecar verification on the GitHub-hosted tarball remains as defense. GPG → v0.4+ (ADR-006). Maintainer 2FA + branch protection is the operational mitigation. |

## Self-Check: PASSED

- [x] `packaging/curl-installer/install.sh` — committed in 211caf5 (feat(06-02): add install.sh)
- [x] `tests/docker/Dockerfile.ubuntu-22.04` + `Dockerfile.ubuntu-24.04` — committed in 5390ba0 (test(06-02): add python3 + file)
- [x] `tests/bats/60-curl-installer.bats` — committed in 2a8c660 (test(06-02): add INST-03 @tests)
- [x] Commit hashes reachable via `git log --oneline | grep 06-02`
- [x] Docker bats 71/71 green on BOTH ubuntu-22.04 AND ubuntu-24.04 with all 3 new `INST-03:` @tests passing
- [x] `shellcheck --severity=warning packaging/curl-installer/install.sh` clean
- [x] `shfmt -i 2 -ci -bn -d packaging/curl-installer/install.sh` clean
- [x] `tail -n 1 install.sh` prints exactly `main "$@"` (Pitfall 1 wrapper)
- [x] `grep -cE '^main\(\) \{' install.sh` returns `1`
- [x] Good-SHA @test exits 0, `fake-installer OK` sentinel in output (proves exec dispatched)
- [x] Tampered-SHA @test exits non-zero, `SHA256 verification failed` in output, no extraction under `/opt/agentlinux/install/v9.9.9-test/`
- [x] Negative-path sanity (plan verify step 4): guard disabled on temp-copy → would bypass; tampered @test therefore enforces the gate, not vacuously passing
- [x] No live-network fetch during Docker bats: fixture is local `python3 -m http.server` on `127.0.0.1:8889` only
