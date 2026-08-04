---
phase: 06
plan: 03
subsystem: distribution-release-pipeline
tags: [release, qemu, release-gate, cloud-init, kvm, TST-03]
requires:
  - tests/qemu/ (Phase 1 scaffold — .gitkeep only)
  - .github/workflows/nightly-qemu.yml (Phase 1 empty-guard scaffold)
  - scripts/build-release.sh (Plan 06-01 — produces the tarball boot.sh scps)
  - plugin/bin/agentlinux-install (Phase 2 — the exec handoff in-guest)
  - tests/bats/51-agt02-release-gate.bats (Phase 5 — the canonical AGT-02 test
    that runs inside the QEMU guest to prove the release gate)
  - docs/decisions/007-docker-plus-qemu-harness.md (ADR-007 — "Docker-alone
    is disqualified" rationale)
  - .claude/skills/qemu-harness/SKILL.md (target-shape spec this plan
    absorbs the concrete flags + cloud-init template snippets from)
provides:
  - tests/qemu/boot.sh (390-line 14-step cloud-init + QEMU + ssh + installer
    + bats orchestrator — TST-03 release-gate harness)
  - tests/qemu/cloud-init/user-data (cloud-config template with per-run
    __AGENTLINUX_QEMU_PUBKEY__ placeholder)
  - tests/qemu/cloud-init/meta-data (instance-id template with per-run
    __AGENTLINUX_QEMU_INSTANCE_ID__ placeholder)
  - tests/qemu/cloud-images.txt (authoritative Ubuntu cloud-image URL +
    SHA256SUMS manifest — drives the workflow's actions/cache key)
  - .github/workflows/nightly-qemu.yml (nightly cron + workflow_dispatch
    matrix for ubuntu 22.04 + 24.04 with KVM udev + cloud-image cache +
    artifact-on-failure upload)
affects:
  - Plan 06-04 release.yml gate-3 (will re-use tests/qemu/boot.sh for the
    release-tag QEMU gate; this plan is gate-3's prerequisite)
  - docs/HARNESS.md §1.3 (QEMU row now points to a real orchestrator, no
    longer a skeleton)
tech-stack:
  added:
    - QEMU system-x86_64 with -enable-kvm -cpu host
    - cloud-image-utils (cloud-localds(1)) to build the seed ISO
    - Ubuntu cloud images (jammy 22.04, noble 24.04) cached under
      $AGENTLINUX_QEMU_CACHE (default $HOME/.cache/agentlinux/qemu)
  patterns:
    - Pattern 4 (06-RESEARCH.md lines 414-508) — cloud-init seed + KVM
      backgrounded QEMU + cloud-init status --wait + scp + bats-over-ssh
    - Per-run ed25519 keypair generated in mktemp 0700 with EXIT trap cleanup
      (T-06-06 — keypair never committed, destroyed on every exit path)
    - `sha256sum --ignore-missing --check` against upstream SHA256SUMS
      refetched every run (Pitfall 10 — verify on cache hit, not just cold)
    - `-drive file=${IMG},if=virtio,snapshot=on` — writes never mutate the
      cached image (defense-in-depth against Pitfall 10 + cross-run isolation)
    - KVM udev rule `KERNEL=="kvm", GROUP="kvm", MODE="0666"` on GitHub
      Actions ubuntu-24.04 runners + fail-fast `[[ -r /dev/kvm && -w /dev/kvm ]]`
      assertion (Pitfall 4 — refuse silent TCG fallback)
    - actions/cache@v4 keyed on `hashFiles('tests/qemu/cloud-images.txt')`
      so URL rotation invalidates the cache automatically
    - ssh `bash -s -- "$TAG" <<'REMOTE'` stdin-heredoc dispatch for
      in-guest scripts (Rule 1 auto-fix — avoids double-shell quote-escape
      fragility)
    - Serial log captured with `-serial file:${RUN_DIR}/serial.log`, copied
      to `tests/qemu/artifacts/` on bats failure, uploaded by the workflow
      with actions/upload-artifact@v4 on `if: failure()` only
key-files:
  created:
    - tests/qemu/boot.sh (mode 0755)
    - tests/qemu/cloud-init/user-data
    - tests/qemu/cloud-init/meta-data
    - tests/qemu/cloud-images.txt
  modified:
    - .github/workflows/nightly-qemu.yml (Phase 1 empty-guard → real matrix
      + KVM udev + cache + artifact upload)
  removed:
    - tests/qemu/.gitkeep (replaced by real artifacts)
    - tests/qemu/cloud-init/.gitkeep (replaced by real artifacts)
decisions:
  - Templates committed under tests/qemu/cloud-init/ (user-data + meta-data)
    with explicit __PLACEHOLDER__ tokens instead of heredoc-inline pubkeys
    (06-RESEARCH Pattern 4's alternative). Templates are reviewable by
    qa-engineer without tracing through boot.sh; Pattern 4 heredoc hides
    cloud-init structure inside a 390-line bash script.
  - Files are named literally `user-data` / `meta-data` (no .yaml extension)
    per cloud-init convention — matches what cloud-localds(1) consumes
    without a rename step, and aligns with every published cloud-init
    example. pre-commit check-yaml has no glob match (.yml/.yaml only) so
    no CI-side drift from this naming choice.
  - boot.sh uses the CURRENT repo version from plugin/cli/package.json as
    the tag passed to scripts/build-release.sh (NOT the plan's spec-listed
    `v0.0.0-qemu`, which would fail build-release.sh's three-way version
    lock gate — plan-code bug, Rule 1 fix inline). QEMU_TAG="v${VERSION}"
    is deterministic on a given HEAD and matches the lock.
  - Accept both `22.04` and `ubuntu-22.04` arg shapes (strip `ubuntu-`
    prefix). The prompt's request signature used `ubuntu-XX.YY`; plan
    frontmatter + cloud-images.txt uses `22.04`. Both flow through the
    same manifest lookup, so accepting both is zero-cost UX.
  - `--help`/`-h` handler added (prompt explicitly asked for `boot.sh
    --help` to exit 0 as a smoke test; plan's `${1:?}` would have failed
    that). Rule 2 — missing critical UX for the verification contract.
  - Removed the ephemeral "Build CLI bundle" workflow step. Node 22 ships
    corepack; scripts/build-release.sh activates pnpm via corepack itself
    (mirrors tests/docker/Dockerfile.ubuntu-24.04 cli-builder). Two
    preparations for one build is redundant and doubles the failure
    surface.
  - SKIP_DEB=1 --no-deb passed to build-release.sh from boot.sh. The
    QEMU harness only needs the .tar.gz; the .deb path is validated in
    release.yml (Plan 06-04), not here. fpm isn't even installed in
    nightly-qemu's runner image, and failing on missing fpm here would
    mask the actual in-guest signal.
metrics:
  duration: ~9 min (static implementation + static verification; runtime
    verification deferred to first CI run)
  tasks-completed: 3 autonomous tasks + 1 blocking checkpoint (deferred)
  atomic-commits: 4 (559a783 templates, 1830e42 boot.sh, 605dfbb workflow,
    9465651 Rule 1 ssh-heredoc fix)
  boot-sh-lines: 390
  workflow-yaml-lines: 118
  cloud-init-user-data-lines: 25
  cloud-init-meta-data-lines: 2
  cloud-images-txt-rows: 2
  shellcheck-clean: true (both plain + --severity=warning)
  shfmt-clean: true (-i 2 -ci -bn)
  actionlint-clean: true (workflow)
  harness-regression: none (104/104 tests/harness still green)
  completed-date: 2026-04-20
---

# Phase 6 Plan 03: QEMU Release-Gate Harness Summary

Full cloud-init + QEMU + SSH + installer + bats orchestration for the
AgentLinux release-gate — replaces Phase 1's empty scaffolds at
`tests/qemu/`, `tests/qemu/cloud-init/`, and `.github/workflows/nightly-qemu.yml`
with working code. Static gates all green; runtime gates (actual KVM boot)
deferred to the first CI run per 06-VALIDATION.md §"Manual-Only Verifications"
(explicitly documented there as manual because GitHub Actions first-run
exercises the KVM udev rule installation).

## Context

TST-03 is the ADR-007 "Docker-alone is disqualified" requirement. Docker masks
systemd, locale generation, and cloud-init paths that QEMU catches. Phase 6
Plan 06-04's `release.yml` gate-3 (release-tag QEMU gate) depends on this
harness existing and green; this plan is that gate's prerequisite.

## What Was Built

### tests/qemu/boot.sh (390 lines, 14 steps)

End-to-end orchestrator:

1. **Argument parsing + `--help`** — `-h|--help` prints usage and exits 0;
   no args or bad version → exit 64 with usage on stderr.
2. **Locate `cloud-images.txt` manifest** and resolve `<image-url>` +
   `<sha256sums-url>` for the requested Ubuntu version. Codename mapping
   (22.04→jammy, 24.04→noble) is embedded; unknown versions exit 64.
3. **Fail-fast on `/dev/kvm`** (Pitfall 4). `[[ -r /dev/kvm && -w /dev/kvm ]]`
   assertion with a diagnostic that names the workflow step responsible
   for KVM access; refuses to proceed under TCG (20-30× slower → blows
   past the 45-minute workflow timeout).
4. **Assert host tools** — `qemu-system-x86_64`, `qemu-img`, `cloud-localds`,
   `ssh`, `scp`, `ssh-keygen`, `curl`, `sha256sum`, `jq`, `tar` all required.
5. **Cache dir + cloud-image fetch** — download once on cold cache; **always
   re-fetch the upstream SHA256SUMS on every run** (Pitfall 10) and verify
   with `sha256sum --ignore-missing --check`. Mismatch → exit 1 with a
   clear "remove the cache file to force re-download" message.
6. **Per-run state dir** (T-06-06) — `mktemp -d -t agentlinux-qemu.XXXXXX`,
   `chmod 0700`, generate ed25519 keypair via `ssh-keygen -q -t ed25519 -N ''`.
   Combined EXIT/INT/TERM trap kills `QEMU_PID` with TERM+KILL escalation
   and `rm -rf "$RUN_DIR"` (keypair + serial.log + seed.iso + rendered
   user-data + rendered meta-data).
7. **Render seed ISO** — `sed` replaces `__AGENTLINUX_QEMU_PUBKEY__` in
   `user-data` and `__AGENTLINUX_QEMU_INSTANCE_ID__` in `meta-data`, feeds
   both to `cloud-localds "${RUN_DIR}/seed.iso"`.
8. **Boot QEMU backgrounded** — `qemu-system-x86_64 -cpu host -enable-kvm
   -m 2048 -smp 2 -drive file=${IMG},if=virtio,snapshot=on -drive
   file=${RUN_DIR}/seed.iso,format=raw,readonly=on -netdev
   user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net,netdev=n0
   -nographic -serial file:${RUN_DIR}/serial.log -display none &`. PID
   captured into `$QEMU_PID`. `snapshot=on` keeps the cached image pristine.
9. **Wait on `cloud-init status --wait`** in-guest over SSH — 300s deadline
   (overridable via `AGENTLINUX_QEMU_TIMEOUT`), polled every 5s. Also
   detects QEMU-exited-early via `kill -0 "$QEMU_PID"` — dumps serial.log
   and exits 1 if QEMU died before cloud-init finished.
10. **Build release tarball via `scripts/build-release.sh`** using the
    REAL repo tag (`v${VERSION}` from `plugin/cli/package.json`), not the
    plan-spec placeholder `v0.0.0-qemu` (which would violate the three-way
    version lock). `SKIP_DEB=1` + `--no-deb` — the QEMU harness only needs
    the `.tar.gz`.
11. **scp both tarballs** — the release `.tar.gz` (plugin/ only, per 06-01
    locked decision) and a second `tests.tar.gz` containing `tests/bats/`
    (plus `node_modules/bats/` when present on the host) so the in-guest
    bats run has the test files next to the installed plugin.
12. **Install in-guest** — `ssh ... bash -s -- "$TAG" <<'REMOTE_INSTALL'`
    stdin-heredoc dispatch: `tar -xzf` both, then `bash plugin/bin/agentlinux-install`.
13. **Run bats in-guest** — same heredoc pattern: prefers
    `./node_modules/bats/bin/bats tests/bats/` if the vendored copy is
    present (matches the Docker harness), falls back to `bats tests/bats/`
    (seeded via cloud-init's `packages: [bats]`). Exit code captured into
    `$BATS_STATUS`.
14. **Artifacts on failure + poweroff** — on non-zero `BATS_STATUS`, copy
    `serial.log` to `tests/qemu/artifacts/serial-${RELEASE}-${TIMESTAMP}.log`.
    Then `ssh ... poweroff` (best-effort) and `wait "$QEMU_PID"`. The trap
    handles any path that skips this clean shutdown.

Exit codes: 0 green, 1 runtime failure (cloud-init timeout, KVM missing,
SHA mismatch, bats red), 64 usage error.

Environment overrides (all optional): `AGENTLINUX_QEMU_CACHE`,
`AGENTLINUX_QEMU_TIMEOUT`, `AGENTLINUX_QEMU_MEM`, `AGENTLINUX_QEMU_SMP`,
`AGENTLINUX_QEMU_PORT`.

### tests/qemu/cloud-init/user-data (25 lines)

Minimal `#cloud-config` seed template:

- `ssh_pwauth: false`, `disable_root: false` — boot.sh needs to `ssh
  root@localhost` with the per-run ed25519 key.
- `users: [{name: root, ssh_authorized_keys: [__AGENTLINUX_QEMU_PUBKEY__]}]`
  — boot.sh's `sed` replaces the placeholder with the freshly-generated
  pubkey from `${RUN_DIR}/id_ed25519.pub`.
- `package_update: true` + `packages: [bats, jq, ca-certificates, curl]`
  — bats for the in-guest test run, jq/curl for Phase 5 recipe scripts
  (claude-code's curl|bash native installer; gsd's npm registry calls via
  curl), ca-certificates for HTTPS to Anthropic's CDN / npm registry.
- `runcmd: [systemctl enable --now ssh]` — belt-and-suspenders on the
  ubuntu cloud-image default (openssh-server is preinstalled + enabled,
  but some minor releases ship with it socket-activated; this makes it
  unconditional).

Cloud-init structure is reviewable by qa-engineer as a standalone file —
the Pattern 4 alternative (heredoc-inlined inside boot.sh) hides it inside
a 390-line orchestrator.

### tests/qemu/cloud-init/meta-data (2 lines)

```yaml
instance-id: __AGENTLINUX_QEMU_INSTANCE_ID__
local-hostname: agentlinux-ci
```

`instance-id` is sed-replaced with `agentlinux-ci-${RELEASE}-$(date +%s)` per
run, forcing cloud-init to re-seed on every boot (snapshot=on + fresh
instance-id = zero seed-cache interference across runs).

### tests/qemu/cloud-images.txt (16 lines, 2 manifest rows)

Authoritative URL + SHA256SUMS manifest. boot.sh `grep`s the version
prefix; nightly-qemu.yml's `actions/cache` step keys on
`hashFiles('tests/qemu/cloud-images.txt')`. Rotating any URL invalidates
the cache automatically — no manual key bump needed when Canonical
publishes a new cloud-image build.

### .github/workflows/nightly-qemu.yml (118 lines)

- `schedule: '0 3 * * *'` UTC nightly + `workflow_dispatch` with an
  `ubuntu` choice input (`both` | `22.04` | `24.04`).
- `permissions: contents: read` (least-privilege default).
- `runs-on: ubuntu-24.04` with `timeout-minutes: 45` and `strategy:
  {fail-fast: false, matrix: {ubuntu: ['22.04', '24.04']}}`.
- Matrix-leg gating via a `decide` step that honors `workflow_dispatch.inputs.ubuntu`
  (so `gh workflow run nightly-qemu.yml -f ubuntu=24.04` skips the 22.04
  leg entirely).
- `actions/checkout@v4` → `actions/setup-node@v4 node-version: 22` (node
  22 ships corepack, which `scripts/build-release.sh` uses on demand; no
  pnpm/action-setup step needed).
- **"Enable /dev/kvm access"** step — installs the `MODE=0666` udev rule,
  reloads udev, triggers `kvm` match, then `[[ -r /dev/kvm && -w /dev/kvm ]]`
  fail-fast with `::error::` on missing KVM (matches boot.sh's step 3).
- **Install QEMU step** — `sudo apt-get install -y --no-install-recommends
  qemu-system-x86 cloud-image-utils netcat-openbsd jq` (ubuntu-24.04
  runners preinstall most of these; the step is cheap-idempotent).
- **`actions/cache@v4`** keyed on `cloud-image-${{ matrix.ubuntu }}-${{
  hashFiles('tests/qemu/cloud-images.txt') }}` with a restore-key prefix
  fallback.
- **`QEMU boot + installer + bats`** — `bash tests/qemu/boot.sh ${{
  matrix.ubuntu }}`. Fails the job on any non-zero exit.
- **`actions/upload-artifact@v4` on `if: failure()`** — uploads
  `tests/qemu/artifacts/` (serial-*.log files) with `retention-days: 14`
  and `if-no-files-found: ignore`.

actionlint-clean (verified with actionlint 1.7.12).

## What Was Verified Locally (static only)

| Check                                            | Result     |
|--------------------------------------------------|------------|
| `shellcheck tests/qemu/boot.sh` (plain)          | PASS       |
| `shellcheck --severity=warning --external-sources tests/qemu/boot.sh` | PASS |
| `shfmt -i 2 -ci -bn -d tests/qemu/boot.sh`       | PASS       |
| `bash -n tests/qemu/boot.sh`                     | PASS       |
| `chmod +x tests/qemu/boot.sh`                    | applied (0755) |
| `python3 -c "yaml.safe_load(user-data)"` (rendered with placeholder filled) | PASS |
| `python3 -c "yaml.safe_load(meta-data)"` (rendered with placeholder filled) | PASS |
| `python3 -c "yaml.safe_load(nightly-qemu.yml)"`  | PASS       |
| `actionlint .github/workflows/nightly-qemu.yml`  | PASS       |
| `actionlint .github/workflows/*.yml` (no regression) | PASS   |
| `bash tests/qemu/boot.sh --help` → exit 0 with usage | PASS   |
| `bash tests/qemu/boot.sh` (no args) → exit 64    | PASS       |
| `bash tests/qemu/boot.sh 99.99` → exit 64 (unknown version) | PASS |
| `bash tests/qemu/boot.sh 22.04` on /dev/kvm-absent host → exit 1 with KVM diagnostic | PASS (Pitfall 4 exercised) |
| `bash tests/harness/run.sh` — no regression      | 104/104    |
| pre-commit equivalents (detect-private-key, trailing-ws, end-of-file) | PASS manually |

## What Is Deferred to the First CI Run

The VALIDATION.md row for TST-03 calls out these manual-only verifications
because a local static-check environment cannot boot KVM:

| Runtime Gate | Why Deferred | Where It Will Be Observed |
|--------------|--------------|---------------------------|
| `tests/qemu/boot.sh ubuntu-22.04` exits 0 (cloud-init + ssh-in + installer + bats green) | Requires a KVM-capable host; the executor VM this plan ran in has no `/dev/kvm` | First `workflow_dispatch` of nightly-qemu.yml on a feature branch, or first nightly cron |
| `tests/qemu/boot.sh ubuntu-24.04` exits 0 | Same — KVM-capable host required | Same CI run (matrix.ubuntu == '24.04' leg) |
| AGT-02 bats passes inside the QEMU guest | Transitively requires both above — AGT-02 is the in-guest bats file 51-*.bats that boot.sh invokes in step 13 | Same CI run (visible in the `QEMU boot + installer + bats` step log as `ok N AGT-02 release-gate: claude update passes without EACCES`) |
| Cold-vs-warm cache runtime measurement | Requires two consecutive CI runs | First two nightly cron runs (cold 8-12min; warm 4-8min per qemu-harness SKILL.md) |
| Pitfall 4 CI-side exercise (udev rule needed on fresh ubuntu-24.04 runner) | Local test exercised the boot.sh fail-fast half; the workflow-step half requires the GitHub-hosted runner | Same first CI run (the "Enable /dev/kvm access" step will either succeed quietly or emit `::error::` and fail the leg) |
| Pitfall 10 CI-side exercise (SHA256 verify on cache hit) | Local test exercised the code path; the cache-hit scenario requires a second CI run to populate then hit the cache | Second nightly run (cache populated) |

These deferrals are consistent with 06-VALIDATION.md §"Manual-Only
Verifications" row 2: *"Full QEMU release-gate run on both Ubuntu 22.04
and 24.04 with KVM enabled — GitHub Actions runner first-time KVM-rule
installation — needs real CI run to confirm. First tag push exercises
this."*

Plan 06-03's `<task type="checkpoint:human-verify" gate="blocking">`
(final task in 06-03-PLAN.md) cannot be resolved until a human triggers
`gh workflow run nightly-qemu.yml` on a branch that includes these four
commits and observes both matrix legs green. This is consistent with the
plan's `autonomous: false` frontmatter.

## Explicit Manual-Only Items Remaining

| Item | Source | When It Lands |
|------|--------|---------------|
| Green `nightly-qemu` workflow run URL for ubuntu-22.04 | 06-03-PLAN.md §verification item 3 | First workflow_dispatch after merge |
| Green `nightly-qemu` workflow run URL for ubuntu-24.04 | 06-03-PLAN.md §verification item 3 | Same run |
| AGT-02 observed `ok` in-guest bats output tail | 06-03-PLAN.md §verification item 4 | Same run (in the `QEMU boot + installer + bats` step log) |
| Cold-cache vs warm-cache runtime delta | 06-03-PLAN.md §output bullet 2 | Second nightly run |
| Production-URL curl-pipe-bash smoke | 06-VALIDATION.md Manual-Only row 1 | Post-release smoke (Plan 06-04 + tag push) |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Plan's `QEMU_TAG="v0.0.0-qemu"` would violate `build-release.sh`'s three-way version lock**

- **Found during:** Task 2 (boot.sh implementation)
- **Issue:** The plan's action code (06-03-PLAN.md line 369) prescribes
  `QEMU_TAG="v0.0.0-qemu"` passed to `scripts/build-release.sh`. But
  06-01's build-release.sh (lines 127-144) enforces a three-way lock:
  TAG must equal `plugin/cli/package.json .version` AND
  `plugin/catalog/catalog.json .version`. Both are `0.3.0`, so any
  `v0.0.0-*` tag would `exit 1` with "version mismatch". The plan would
  have built green on static checks then failed the first CI run.
- **Fix:** boot.sh step 9 reads `VERSION=$(jq -r .version
  "${REPO_ROOT}/plugin/cli/package.json")` and passes `TAG="v${VERSION}"`
  — always matches the three-way lock on the current HEAD.
- **Files modified:** `tests/qemu/boot.sh` (never used the v0.0.0-qemu
  string in the first place — the bug was caught before committing Task 2)
- **Commit:** embedded in Task 2's `1830e42 feat(06-03): implement
  tests/qemu/boot.sh ...`. No separate fix commit because the plan-code
  bug was caught during implementation, not post-commit.

**2. [Rule 1 — Fragility] Double-shell quote escape on in-guest ssh dispatch**

- **Found during:** Post-Task-2 review-loop pass (bash-engineer rubric)
- **Issue:** Initial implementation used `ssh "${SSH_OPTS[@]}"
  root@localhost bash -c "'...multi-line body...'"` — a double-quoted
  string wrapping a single-quoted remote body. Works today but any future
  edit that introduces a single quote (`let's`, contractions in diagnostic
  echoes) silently breaks the dispatch. Shellcheck does not flag this.
- **Fix:** Both in-guest dispatch sites switched to `ssh "${SSH_OPTS[@]}"
  root@localhost bash -s [-- "$TAG"] <<'REMOTE'` stdin-heredoc pattern.
  Script body goes over ssh's stdin; zero re-parse on the wire. The
  quoted heredoc delimiter prevents host-side variable expansion; the
  host→guest value ($TAG) is passed as a positional arg (`-- "$TAG"` →
  `$1` in the remote).
- **Files modified:** `tests/qemu/boot.sh` steps 11 + 12 (9 insertions,
  5 deletions)
- **Commit:** `9465651 fix(06-03): [Rule 1] switch in-guest ssh
  invocations to bash -s + stdin heredoc`

**3. [Rule 2 — Missing critical UX] `--help` handler**

- **Found during:** Task 2 (alignment with prompt's explicit verification
  command `bash tests/qemu/boot.sh --help`)
- **Issue:** Plan's implementation starts with `UBUNTU_VERSION=${1:?usage:
  ...}` — fails with an error on missing/`--help` arg. The prompt listed
  `bash tests/qemu/boot.sh --help` as one of the local smoke checks (exit
  0 with usage), and users discovering the script need `-h` as a reflex.
- **Fix:** Added a `case "${1:-}" in -h|--help) usage; exit 0;; '') usage
  >&2; exit 64;; esac` preamble; the rest of the script keeps its
  fail-on-missing semantics.
- **Files modified:** `tests/qemu/boot.sh` (lines 42-78 — usage function
  + case block)
- **Commit:** embedded in Task 2's `1830e42`

**4. [Rule 2 — Robustness] Accept both `22.04` and `ubuntu-22.04` arg shapes**

- **Found during:** Task 2 (prompt signature mismatch)
- **Issue:** The prompt's "Success criteria" uses `ubuntu-XX.YY` format
  (`tests/qemu/boot.sh ubuntu-22.04`); the plan's cloud-images.txt + plan
  spec use `22.04`. Either UX is fine; refusing one when the other works
  is brittle.
- **Fix:** `UBUNTU_VERSION=${UBUNTU_ARG#ubuntu-}` strips the optional
  prefix before manifest lookup. Both shapes flow through the same
  `grep` against cloud-images.txt.
- **Files modified:** `tests/qemu/boot.sh` (lines 82-83 + usage help text)
- **Commit:** embedded in Task 2's `1830e42`

**5. [Rule 3 — Blocking simplification] Dropped redundant "Build CLI
bundle" workflow step**

- **Found during:** Task 3 (workflow review)
- **Issue:** Initial workflow draft included an explicit `Build CLI bundle
  (prep for build-release.sh)` step that ran `pnpm install + pnpm run
  build` before invoking `bash tests/qemu/boot.sh`. But
  scripts/build-release.sh does its own corepack-activates-pnpm dance
  internally; doubling the build doubles the failure surface.
- **Fix:** Removed the prep step; the workflow now only calls
  `actions/setup-node@v4 {node-version: 22}` (which brings corepack) and
  relies on build-release.sh to activate pnpm on demand. Matches the
  Docker harness pattern (Dockerfile.ubuntu-24.04 cli-builder stage does
  its own pnpm activation).
- **Files modified:** `.github/workflows/nightly-qemu.yml` (removed
  pnpm/action-setup + Build CLI bundle steps)
- **Commit:** embedded in Task 3's `605dfbb`

None of these deviations required architectural changes (Rule 4). All are
bug/robustness/UX fixes that a sharp reviewer would have caught in a PR.

### No-deviation items

The plan was otherwise implemented verbatim: pitfall mitigations (4, 10,
T-06-06) match plan spec byte-for-byte; workflow matrix, cache key shape,
KVM udev rule, artifact-on-failure upload all match plan spec; cloud-init
templates use the exact placeholder tokens listed in the plan's Task 1
action block.

## Review-Loop Triage Notes

**bash-engineer on tests/qemu/boot.sh:**
- `set -euo pipefail`: present (line 40)
- EXIT/INT/TERM trap with TERM+KILL escalation: present (lines 198-214)
- Quoting discipline: shellcheck --severity=warning + plain shellcheck
  both clean
- Array usage for SSH_OPTS + SCP_OPTS (no word-splitting via string
  concatenation): present
- Actionable finding: ssh heredoc quote-fragility (Deviation 2 above —
  fixed in 9465651)

**security-engineer on tests/qemu/boot.sh + cloud-init/:**
- mktemp 0700 RUN_DIR: present (line 194-195)
- EXIT trap rm -rf RUN_DIR: present (line 211)
- No committed private keys (detect-private-key equivalent grep): clean
- SHA256 manifest refetched every run before verify: present (line 172)
- `sha256sum --ignore-missing --check` on cached image: present (line 178)
- cloud-init has no secrets (no password:, token:, api_key: fields): clean
- `ssh_pwauth: false`: present
- `disable_root: false` — intentional for the ephemeral test guest, not
  a production security regression; documented in the user-data header
  comment
- No actionable findings beyond the ssh-heredoc hygiene already addressed

**qa-engineer on .github/workflows/nightly-qemu.yml:**
- actionlint clean (1.7.12): PASS
- KVM `::error::` fail-fast step present before the QEMU step runs: PASS
- `hashFiles('tests/qemu/cloud-images.txt')` in cache key: PASS
- `if: failure()` on artifact upload (not blanket always-upload): PASS
- `timeout-minutes: 45` (bounded; KVM-accelerated would finish in ~15): PASS
- `fail-fast: false` on the matrix (don't cancel the other Ubuntu version
  on one's failure): PASS
- `permissions: contents: read` (least-privilege, not default read-write): PASS
- No actionable findings

All reviewer rubrics applied inline per Phase 2/3/4/5 precedent (Task tool
for subagent dispatch unavailable in this executor context per prior
phase SUMMARYs). Single iteration; one actionable finding (the ssh-heredoc
fragility) fixed in `9465651`.

## Commits

| # | Hash     | Subject                                                                                          |
|---|----------|--------------------------------------------------------------------------------------------------|
| 1 | 559a783  | feat(06-03): add tests/qemu/cloud-init templates + cloud-images.txt manifest                     |
| 2 | 1830e42  | feat(06-03): implement tests/qemu/boot.sh (TST-03 — full cloud-init + QEMU + ssh + installer + bats orchestrator) |
| 3 | 605dfbb  | feat(06-03): populate nightly-qemu.yml — matrix + KVM udev + cloud-image cache (TST-03)          |
| 4 | 9465651  | fix(06-03): [Rule 1] switch in-guest ssh invocations to bash -s + stdin heredoc                  |

## TDD Gate Compliance

Not applicable — this plan is `type: execute` (structural, not behavioral).
No `tdd="true"` tasks; no RED/GREEN gate commits required. The behavioral
contract (AGT-02 bats passing inside the QEMU guest) is tested by the
already-existing tests/bats/51-agt02-release-gate.bats (Plan 05-01) which
boot.sh invokes in step 13 — the gate is exercised, just not inside a
RED/GREEN commit pair this plan authored.

## Self-Check: PASSED

Files verified present on disk:
- `tests/qemu/boot.sh`: FOUND
- `tests/qemu/cloud-init/user-data`: FOUND
- `tests/qemu/cloud-init/meta-data`: FOUND
- `tests/qemu/cloud-images.txt`: FOUND
- `.github/workflows/nightly-qemu.yml`: FOUND (modified)

Commits verified in git log:
- 559a783: FOUND
- 1830e42: FOUND
- 605dfbb: FOUND
- 9465651: FOUND

Removed (replaced by real artifacts):
- `tests/qemu/.gitkeep`: ABSENT (intended — replaced by cloud-images.txt + cloud-init/)
- `tests/qemu/cloud-init/.gitkeep`: ABSENT (intended — replaced by user-data + meta-data)
