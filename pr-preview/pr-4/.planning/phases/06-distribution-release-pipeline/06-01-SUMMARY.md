---
phase: 06
plan: 01
subsystem: distribution-release-pipeline
tags: [release, build, reproducibility, catalog, fpm, deb]
requires:
  - plugin/cli/package.json (version source-of-truth, via jq -r .version)
  - plugin/catalog/catalog.json (CAT-05 source for snapshot cp)
  - plugin/provisioner/50-registry-cli.sh (CAT-01 staging target the new @test locks)
provides:
  - scripts/build-release.sh (reproducible tarball + sha256 + catalog snapshot + optional .deb)
  - packaging/deb/postinst.sh (fpm --after-install dpkg bridge)
  - tests/bats/10-installer.bats CAT-05 @tests (byte-stable anti-drift contract)
affects:
  - .github/workflows/release.yml (Plan 06-04 will invoke scripts/build-release.sh in its build step)
  - packaging/curl-installer/install.sh (Plan 06-02 will consume the .sha256 sidecar over HTTPS)
tech-stack:
  added: [fpm (optional .deb), pnpm@frozen-lockfile (CLI bundle)]
  patterns:
    - reproducible-builds.org tar recipe (--sort=name, --owner=0, --numeric-owner, --mtime=@SOURCE_DATE_EPOCH)
    - gzip -n (no mtime in gzip frame) for cross-run byte stability
    - "cp (not jq .) for byte-for-byte catalog snapshot (Pitfall 8 mitigation)"
    - three-way version lock (tag + package.json + catalog.json) before expensive build steps
    - "--dry-run short-circuit (validate without producing artifacts)"
key-files:
  created:
    - scripts/build-release.sh
    - packaging/deb/postinst.sh
  modified:
    - .gitignore (adds dist/)
    - tests/bats/10-installer.bats (adds 2 CAT-05 @tests)
decisions:
  - Skip .deb in default local runs (fpm not present in dev env; SKIP_DEB path verified)
  - Use pnpm --frozen-lockfile (mirrors Docker cli-builder; refuses lockfile drift)
  - Strip plugin/cli/node_modules/.modules.yaml + .pnpm-workspace-state-v1.json from tarball (pnpm bookkeeping with wall-clock timestamps that break reproducibility)
  - --dry-run added even though plan task 1 did not require it — VALIDATION.md row 06-01-01 mentions dry-run and it makes release.yml workflow_dispatch smoke tests cheap (<1s)
metrics:
  duration: ~7 min (implementation + verification + Docker bats suite)
  tasks-completed: 3
  atomic-commits: 3
  tarball-sha256: 6c2c35146bb472c1205aede62dbb458b436093f36e055cf91abc5ebebe08380c
  tarball-bytes: 30332112
  catalog-snapshot-sha256: 81cdf0405018c7150de69c48c3a310577b70f2b9ca466a12efb9338d8ffac4cf
  bats-delta: "66/66 -> 68/68 (two new CAT-05 @tests)"
  completed-date: 2026-04-20
---

# Phase 6 Plan 01: Build-Release Script Summary

Reproducible AgentLinux release-artifact assembly: a single `scripts/build-release.sh vX.Y.Z` produces the byte-identical tarball + SHA256 sidecar + byte-stable catalog snapshot the curl-installer (Plan 06-02) and release.yml (Plan 06-04) consume. All three Phase 6 Plan 01 tasks landed with per-task atomic commits and full verification green.

## What shipped

### 1. `scripts/build-release.sh` (300 lines, executable, shellcheck/shfmt clean)

Pipeline (steps numbered in the script header):
1. Arg parse + tag-shape regex gate (`^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$`; malformed → exit 64).
2. Repo-root resolution via `git rev-parse --show-toplevel` (invocable from any cwd).
3. Three-way version-consistency gate: tag vs `plugin/cli/package.json .version` vs `plugin/catalog/catalog.json .version` (drift → exit 1 with precise mismatch message).
3b. **`--dry-run` short-circuit**: prints the planned artifact set to stdout and exits 0 without pnpm/tar/writes. Intended for `release.yml` `workflow_dispatch` smoke tests (<1s).
4. CLI build via pnpm `--frozen-lockfile` then `prune --prod` (mirrors the Docker cli-builder stage; ADR-011 bundle pattern).
5. `mkdir -p dist`.
6. `SOURCE_DATE_EPOCH` pinned to `git log -1 --pretty=%ct HEAD` (overridable via env).
7. Reproducible tar: `--sort=name --owner=0 --group=0 --numeric-owner --mtime=@$EPOCH --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime`, then `gzip -n` for a timestamp-free gzip frame. Excludes pnpm bookkeeping files (`.modules.yaml`, `.pnpm-workspace-state-v1.json`) that embed wall-clock timestamps.
8. SHA256 sidecar (`sha256sum <basename> > <basename>.sha256` from inside `dist/` so the filename column is unqualified — `sha256sum -c` round-trips cleanly).
9. Catalog snapshot: `cp plugin/catalog/catalog.json dist/catalog-<tag>.json` — NOT `jq .` (Pitfall 8).
10. Build-time self-verify: sha256(source) == sha256(snapshot) → exit 1 if a rogue `cp` alias corrupted bytes.
11. Optional `fpm -s dir -t deb ...` — skipped with a clear one-line stdout notice if `SKIP_DEB=1`, `--no-deb`, or fpm absent.
12. Final summary line (stdout; no emojis).

### 2. `packaging/deb/postinst.sh` (37 lines, executable, shellcheck clean)

Minimal fpm `--after-install` hook. Uses `exec /opt/agentlinux/bin/agentlinux-install "$@"` so dpkg observes the installer's real exit code (not a wrapper's always-0). Propagates dpkg's lifecycle args for forward-compat with ADR-011 reconcile semantics. Guards against missing installer with an explicit existence + executability check. Minimal by design — ADR-006 scopes `.deb` as OPTIONAL for v0.3.0.

### 3. `tests/bats/10-installer.bats` — two new CAT-05 @tests

Appended at the end of the file; positions 9 and 10 in the 68-test suite:

- `CAT-05: catalog snapshot staged at /opt/agentlinux/catalog/<version>/catalog.json` — resolves version from `plugin/cli/package.json` (tracks v0.3.x bumps automatically). Asserts non-empty regular file at the canonical staging path.
- `CAT-05: staged catalog is byte-stable against tarball source (Pitfall 8 anti-drift)` — asserts `sha256(source) == sha256(staged)`. Locks the contract between `cp` in `scripts/build-release.sh §9` and `cp -R` in `plugin/provisioner/50-registry-cli.sh`.

Both @tests cite the CAT-05 requirement ID in the `@test` title (TST-07 gate passes) and use the project-standard `__fail <req> <expected> <observed> <log>` diagnostic (TST-04).

### 4. `.gitignore`

Appended `dist/` so CI-ephemeral build output never commits.

## Verification commands run (all green)

```bash
shellcheck --severity=warning --shell=bash --external-sources \
  scripts/build-release.sh packaging/deb/postinst.sh           # clean
shfmt -i 2 -ci -bn -d \
  scripts/build-release.sh packaging/deb/postinst.sh           # clean

bash scripts/build-release.sh v0.3.0 --dry-run                 # exit 0, no dist/
bash scripts/build-release.sh v0.3.0                           # exit 0, 3 artifacts
(cd dist && sha256sum -c agentlinux-v0.3.0.tar.gz.sha256)      # OK (exit 0)
sha256sum plugin/catalog/catalog.json dist/catalog-v0.3.0.json  # identical hash

# Reproducibility
cp dist/agentlinux-v0.3.0.tar.gz /tmp/first.tar.gz
rm -rf dist/
bash scripts/build-release.sh v0.3.0
sha256sum /tmp/first.tar.gz dist/agentlinux-v0.3.0.tar.gz       # identical (6c2c351...)

# Error-path gates
bash scripts/build-release.sh 0.3.0                            # exit 64, clear msg
jq '.version="9.9.9"' plugin/cli/package.json > tmp && mv tmp plugin/cli/package.json
bash scripts/build-release.sh v0.3.0                           # exit 1, precise drift msg
# (package.json restored)

# Docker bats (AGT-02 release gate + CAT-05 @tests)
bash tests/docker/run.sh ubuntu-24.04
# 1..68  all green, both CAT-05 @tests at positions 9+10
```

### Observed tarball SHA256

```
6c2c35146bb472c1205aede62dbb458b436093f36e055cf91abc5ebebe08380c  dist/agentlinux-v0.3.0.tar.gz
```

Byte-identical across two back-to-back builds on the same HEAD — confirms Pitfall 5 mitigation (SOURCE_DATE_EPOCH + `--sort=name` + numeric-owner=0 + `gzip -n` + pnpm-bookkeeping exclusions).

### Observed catalog-snapshot SHA256

```
81cdf0405018c7150de69c48c3a310577b70f2b9ca466a12efb9338d8ffac4cf  plugin/catalog/catalog.json
81cdf0405018c7150de69c48c3a310577b70f2b9ca466a12efb9338d8ffac4cf  dist/catalog-v0.3.0.json
```

Byte-identical — confirms Pitfall 8 mitigation (`cp` not `jq .`).

### .deb decision (SKIP_DEB behavior exercised)

- fpm not installed in this dev environment → the script's guard (`command -v fpm`) triggers and prints `skipping .deb (fpm not installed; install via 'gem install fpm' to enable)`. Build continues; tarball + sha256 + catalog snapshot produced.
- `--no-deb` and `SKIP_DEB=1` paths exercise the explicit-skip branch (`skipping .deb (SKIP_DEB=1 or --no-deb)`). Both verified during iterative testing.
- .deb payload itself is deferred to Plan 06-04 CI (fpm pre-installed in the release runner) or v0.4+ per ADR-006 if fpm integration proves fragile. `packaging/deb/postinst.sh` is in place regardless.

## Bats delta

`66/66 → 68/68` (Docker ubuntu-24.04). The two additions both verify CAT-05. No prior @tests flake or shift. Full transcript in `/tmp/bats-06-01.log` (not committed; CI equivalent is captured in `.github/workflows/test.yml` job output).

## Review loop outcomes

Per CLAUDE.md §Review Loop, reviewed all touched bash files (`scripts/build-release.sh`, `packaging/deb/postinst.sh`) and the bats addition:

| Reviewer | Scope | Finding |
|----------|-------|---------|
| bash-engineer | scripts/build-release.sh, packaging/deb/postinst.sh | `set -euo pipefail` present in both; all variables quoted; tar-into-gzip pipe + pipefail correctly propagates; shellcheck+shfmt clean with project flags. No actionable comments. |
| security-engineer | scripts/build-release.sh | TAG re-validated at entry (not trusted from caller); three-way version lock prevents shipping drifted tag; `--numeric-owner --owner=0` erases builder uid/gid; no `sudo`, no `npm install -g`; no secret surface (SHA256 verification is the only trust boundary and is downstream in 06-02). No actionable comments. |
| qa-engineer | all three | Reproducibility verified (two runs, same sha256); error paths verified (bad tag → 64; version drift → 1); edge case `SOURCE_DATE_EPOCH` env override preserved for CI pinning; fpm-absent path exercised. `--dry-run` adds validation smoke test without real-build cost. No actionable comments. |
| catalog-auditor | scripts/build-release.sh §9, tests/bats/10-installer.bats CAT-05 | `cp` used (not `jq .`), byte-stability self-verified at build time AND install time (two @tests). Pitfall 8 anti-drift contract locked end-to-end. No actionable comments. |

Zero blockers, zero actionable changes. Non-actionable discovery: fpm integration testing deferred to Plan 06-04 CI where fpm is pre-installed.

## Deferred / out-of-scope

- **Actual fpm .deb build exercise**: fpm not installed in dev env. SKIP path fully exercised locally; CI runner (release.yml Plan 06-04) provisions fpm and will exercise the build path on the first tag push.
- **GPG-signed tarball**: ADR-006 defers to v0.4+. SHA256 + HTTPS is the v0.3.0 trust story.
- **QEMU verification of the curl-installer consuming the sha256 sidecar**: owned by Plan 06-02 (curl-installer) and Plan 06-03 (QEMU harness). This plan produced the artifacts they consume.

## Requirements advanced

- **INST-03** (SHA256-verified curl-pipe-bash): tarball + `.sha256` sidecar in GNU default format, round-trips via `sha256sum -c`. Reproducible across reruns on same HEAD — downstream curl-installer can now rely on a stable contract.
- **CAT-05** (catalog snapshot as release sibling): `dist/catalog-v<X.Y.Z>.json` written, byte-stable vs source. Install-time staged copy contract locked by the two new @tests.

## Threats mitigated

| ID | Disposition | How |
|----|-------------|-----|
| T-06-01 (tamper / integrity) | mitigate | SOURCE_DATE_EPOCH + reproducible tar flags + gzip -n → two CI runs of the same commit MUST produce identical sha256. |
| T-06-08 (release-publish integrity) | mitigate | `sha256sum` sidecar written in GNU default format before the build can claim success; release.yml's artifact glob will fail if sidecar is missing (Plan 06-04). |
| T-06-08b (local catalog drift) | mitigate | `cp` not `jq .` + build-time sha256 self-verify + install-time @test byte-stability gate. |
| T-06-V (input-validation) | mitigate | Tag regex gate + three-way version lock. |
| T-06-deb (postinst surface) | accept for v0.3.0 | ADR-006 scoping; minimal postinst; fpm path optional. |

## Self-Check: PASSED

- [x] `scripts/build-release.sh` — committed in 315f47b (feat(06-01): add scripts/build-release.sh)
- [x] `packaging/deb/postinst.sh` — committed in a910720 (feat(06-01): add packaging/deb/postinst.sh)
- [x] `tests/bats/10-installer.bats` CAT-05 @tests — committed in 7fa9531 (test(06-01): add CAT-05 @tests)
- [x] `.gitignore` `dist/` entry — committed in 315f47b (alongside script)
- [x] Commit hashes reachable via `git log --oneline | grep 06-01`
- [x] Docker bats 68/68 green with both CAT-05 @tests passing
- [x] Reproducibility verified (two runs produce identical tarball sha256)
- [x] `sha256sum -c` round-trip exits 0
- [x] Bad tag exits 64; version drift exits 1 with precise message
- [x] SKIP_DEB and --no-deb and fpm-absent paths all exercise the graceful-skip branch
