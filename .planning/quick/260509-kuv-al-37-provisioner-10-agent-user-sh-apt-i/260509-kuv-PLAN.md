---
phase: quick-260509-kuv
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - plugin/provisioner/10-agent-user.sh
  - plugin/provisioner/20-sudoers.sh
  - tests/docker/Dockerfile.dogfood
autonomous: true
requirements:
  - AL-37
quick_id: 260509-kuv

must_haves:
  truths:
    - "plugin/provisioner/10-agent-user.sh runs `DEBIAN_FRONTEND=noninteractive apt-get update` inside the `if ! command -v locale-gen` auto-install branch, BEFORE `apt-get install -y locales`"
    - "plugin/provisioner/20-sudoers.sh runs `DEBIAN_FRONTEND=noninteractive apt-get update` inside the `if ! command -v visudo` auto-install branch, BEFORE `apt-get install -y sudo`"
    - "Both apt-get update calls live INSIDE the existing `if ! command -v ...; then` gate — they do NOT run unconditionally on every installer invocation (preserves the gate's no-op-when-already-installed property)"
    - "tests/docker/Dockerfile.dogfood adds `&& rm -rf /var/lib/apt/lists/*` to the apt-get install RUN so the dogfood image starts with an empty apt cache — turning the AL-37 regression scenario into a permanent CI assertion"
    - "Dockerfile.dogfood comment block (lines 51-60) is rewritten to drop the AL-37 tactical-workaround language and instead document why we INTENTIONALLY clean lists (regression coverage for AL-37)"
    - "After fix: `bash tests/docker/dogfood.sh ubuntu-24.04` completes through 10-agent-user.sh AND 20-sudoers.sh on a fresh image with empty apt cache — no `Package locales has no installation candidate` and no `Package sudo has no installation candidate` errors in installer log"
    - "Existing strict-mode contract preserved: each new `apt-get update` line is a single statement with no trailing `|| true`, so a real apt failure (e.g. network outage, broken sources) trips the entrypoint's ERR trap instead of being silently masked"
    - "Sourced-fragment contract preserved: no `set -e`/`set -u`/`set -o pipefail` lines added (these provisioners inherit strict mode from the entrypoint, per the file headers)"
  artifacts:
    - path: "plugin/provisioner/10-agent-user.sh"
      provides: "Fixed locales auto-install — runs apt-get update first when locale-gen is missing"
      contains: "apt-get update"
    - path: "plugin/provisioner/20-sudoers.sh"
      provides: "Fixed sudo auto-install — runs apt-get update first when visudo is missing"
      contains: "apt-get update"
    - path: "tests/docker/Dockerfile.dogfood"
      provides: "Dogfood image now starts with empty apt cache; permanent regression coverage for AL-37"
      contains: "rm -rf /var/lib/apt/lists"
  key_links:
    - from: "plugin/provisioner/10-agent-user.sh"
      to: "plugin/provisioner/30-nodejs.sh"
      via: "shared apt-update-before-install pattern (30-nodejs.sh:33 is canonical)"
      pattern: "apt-get update"
    - from: "plugin/provisioner/20-sudoers.sh"
      to: "plugin/provisioner/30-nodejs.sh"
      via: "shared apt-update-before-install pattern (30-nodejs.sh:33 is canonical)"
      pattern: "apt-get update"
    - from: "tests/docker/Dockerfile.dogfood"
      to: "plugin/provisioner/10-agent-user.sh + 20-sudoers.sh"
      via: "empty-cache start state exercises the fixed auto-install branches"
      pattern: "rm -rf /var/lib/apt/lists"
---

<objective>
Fix AL-37: AgentLinux installer fails on Ubuntu hosts with empty apt cache
because two provisioner steps auto-install missing prerequisite packages
(`locales` in 10-agent-user.sh, `sudo` in 20-sudoers.sh) without first running
`apt-get update`. On a freshly pulled Ubuntu container or a long-idle real
host, `/var/lib/apt/lists/` is empty and `apt-get install` fails with
`Package <name> has no installation candidate`.

Root cause: AL-30 introduced the auto-install pattern but did not include the
matching `apt-get update` that 30-nodejs.sh:33 already runs. Earlier dogfood
retests masked it because the manual eight-line setup recipe ran `apt update`
before installing curl, side-effecting a populated cache.

Fix: mirror the canonical 30-nodejs.sh pattern by running
`DEBIAN_FRONTEND=noninteractive apt-get update` inside each gated auto-install
branch, immediately before `apt-get install`. Two single-line edits.

Additionally, strengthen the dogfood image (tests/docker/Dockerfile.dogfood)
so its apt cache is empty at runtime — the file already documents this as the
desired strategic end-state once AL-37 is fixed. This converts AL-37's
regression scenario into a permanent test: any future provisioner that adds
an auto-install gate without an apt-get update will fail dogfood retests
immediately.

Acceptance per AL-37: launch a fresh ubuntu:24.04 container with no apt-get
update done inside, run the curl-pipe-bash AgentLinux installer; install
completes through 10-agent-user.sh and 20-sudoers.sh without "no installation
candidate" errors. Locally reproducible via:
  bash tests/docker/dogfood.sh ubuntu-24.04
</objective>

<context>
**Files to read first:**
- plugin/provisioner/10-agent-user.sh (lines 39-45 — the locale-gen auto-install gate)
- plugin/provisioner/20-sudoers.sh (lines 40-48 — the visudo auto-install gate)
- plugin/provisioner/30-nodejs.sh (lines 26-35 — the canonical apt-update-then-install pattern to mirror)
- tests/docker/Dockerfile.dogfood (whole file — the workaround comment block at lines 51-60 is what gets rewritten)
- tests/docker/dogfood.sh (entrypoint for the local end-to-end test that asserts the fix)

**Related Jira:**
- AL-30 — introduced the auto-install pattern this exposes (4-bug fix bundle)
- AL-36 — added the minimal-prereqs Dockerfile.dogfood that surfaced AL-37

**Constraint — sourced-fragment shape:** Both provisioner fragments are
sourced by plugin/bin/agentlinux-install. They inherit `set -euo pipefail`
and the ERR trap from the entrypoint (file headers say so explicitly). The
new apt-get update line MUST NOT add `|| true` — strict-mode propagation is
the only way real apt failures surface in the installer log.

**Constraint — gate placement:** The apt-get update goes INSIDE the
`if ! command -v <X>` block, not before it. The whole point of the gate is
that on hosts where the prereq is already installed (which is the steady-
state for repeat installs and for non-slim images), we skip the install AND
the update — both are wasted work. 30-nodejs.sh runs apt-get update
unconditionally because nodejs is ALWAYS installed by the AgentLinux
installer; locales/sudo are only installed when missing.
</context>

<tasks>

## Task 1: 10-agent-user.sh — apt-get update before locales install

**File:** plugin/provisioner/10-agent-user.sh

**Action:** Inside the existing `if ! command -v locale-gen >/dev/null 2>&1; then`
block (currently lines 42-45), add a single `DEBIAN_FRONTEND=noninteractive
apt-get update` line BEFORE the existing `apt-get install -y
--no-install-recommends locales` line.

Resulting block shape:

```bash
if ! command -v locale-gen >/dev/null 2>&1; then
  log_warn "locale-gen not found; installing 'locales' package"
  DEBIAN_FRONTEND=noninteractive apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends locales
fi
```

The comment block above (lines 39-41) explaining "Docker slim images strip
the locales package entirely" should gain ONE additional sentence noting that
apt-get update precedes the install because the cache may be empty on slim
images and freshly pulled containers (cite AL-37 as the discovery context).
Keep it brief — one or two sentences.

**Verify:**
- shellcheck plugin/provisioner/10-agent-user.sh exits 0 (no new warnings)
- The new line is INSIDE the `if ! command -v locale-gen ...` block, not
  before it, so installs that already have locale-gen are unaffected
- pre-commit run --files plugin/provisioner/10-agent-user.sh passes

**Done:**
- File compiles via `bash -n plugin/provisioner/10-agent-user.sh`
- shellcheck clean
- pre-commit clean
- Diff is +2 lines (apt-get update + the comment-block addendum)

## Task 2: 20-sudoers.sh — apt-get update before sudo install

**File:** plugin/provisioner/20-sudoers.sh

**Action:** Same fix shape as Task 1, applied to the visudo auto-install gate
at lines 45-48. Insert `DEBIAN_FRONTEND=noninteractive apt-get update` BEFORE
the `apt-get install -y --no-install-recommends sudo` line. The existing
comment block at lines 40-44 already says "Mirror the pattern used by
10-agent-user.sh's locales install" — once Task 1 lands the pattern includes
the apt-get update, so this fragment stays in lockstep.

Optionally (and cheaply): update that comment to read "Mirror the pattern
used by 10-agent-user.sh's locales install (apt-get update + apt-get install,
gated on prereq absence)" for clarity. Keep it tight.

Resulting block shape:

```bash
if ! command -v visudo >/dev/null 2>&1; then
  log_warn "visudo not found; installing 'sudo' package"
  DEBIAN_FRONTEND=noninteractive apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends sudo
fi
```

**Verify:**
- shellcheck plugin/provisioner/20-sudoers.sh exits 0
- The new line is INSIDE the `if ! command -v visudo ...` block
- pre-commit run --files plugin/provisioner/20-sudoers.sh passes

**Done:**
- File compiles via `bash -n plugin/provisioner/20-sudoers.sh`
- shellcheck clean
- pre-commit clean
- Diff is +1 line (the apt-get update; comment update optional)

## Task 3: Dockerfile.dogfood — drop tactical workaround, clean apt lists

**File:** tests/docker/Dockerfile.dogfood

**Action:** Two edits in the same file:

1. In the apt-get install RUN (currently lines 46-50), append `&& rm -rf
   /var/lib/apt/lists/*` so the resulting image ships with an empty apt
   cache. This is the steady state described in the file's own comment
   block ("Until that lands, keeping /var/lib/apt/lists/ populated here is
   the tactical fix"); after AL-37 lands, the strategic fix is in the
   installer and the dogfood image gets stricter.

2. Replace the explanatory comment block (currently lines 51-60, the
   ">>> DO NOT add `rm -rf /var/lib/apt/lists/*` to the RUN above. <<<"
   block) with a positive-framing block explaining why we DO clean lists
   here: AL-37 ensures the installer runs `apt-get update` before any
   gated auto-install, so the dogfood image starting with an empty cache
   is the canonical regression test for that fix. Cite AL-37 as the
   landed fix that made this safe.

   Suggested replacement comment (adapt as you see fit):

   ```
   # /var/lib/apt/lists/ is intentionally cleaned. AL-37 fixed the installer
   # so plugin/provisioner/10-agent-user.sh AND 20-sudoers.sh both run
   # `apt-get update` before any gated auto-install — that means the
   # AgentLinux installer is now correct on hosts with empty apt cache.
   # We start the dogfood image with an empty cache so any future
   # provisioner that re-introduces an "auto-install missing package
   # without apt-get update" pattern fails dogfood retests immediately.
   # This is regression coverage for AL-37 baked into the test substrate.
   ```

**Verify:**
- `docker build -t agentlinux-dogfood-al37 -f tests/docker/Dockerfile.dogfood
  --build-arg UBUNTU_VERSION=24.04 tests/docker/` succeeds
- The resulting image has an empty `/var/lib/apt/lists/` (verify with
  `docker run --rm --entrypoint=/bin/sh agentlinux-dogfood-al37 -c 'ls
  /var/lib/apt/lists/'` — should show nothing or only `partial/`/`lock`)
- hadolint or whatever Dockerfile linter the project uses (if any) stays
  clean — likely none gates this file today; skip unless pre-commit fails

**Done:**
- Diff: +1 line (`&& rm -rf /var/lib/apt/lists/*` appended), comment block
  rewritten in place (no net line-count growth required)
- pre-commit clean
- Docker build succeeds locally

## Task 4: End-to-end validation via dogfood.sh

**Files touched:** none (validation-only)

**Action:** Run the existing one-command dogfood retest end-to-end:

```bash
bash tests/docker/dogfood.sh ubuntu-24.04
```

Capture installer log output. Both 10-agent-user.sh and 20-sudoers.sh must
complete without "no installation candidate" errors. Compare to a pre-fix
baseline if useful (the workaround comment in Dockerfile.dogfood describes
the failure shape).

**Verify:**
- dogfood.sh exits 0
- Installer log shows successful "wrote /etc/sudoers.d/agentlinux" and
  successful "locale C.UTF-8 enforced" messages from both provisioners
- The new sentinel checks in tests/dogfood/ (added under AL-36, see commit
  77043fa) still pass — agent ownership + no-EACCES + ERR-trap diagnostics
- No new shellcheck/pre-commit warnings introduced anywhere

**Done:**
- Single-shot `bash tests/docker/dogfood.sh ubuntu-24.04` is green
- Captured output (or relevant snippet) in the SUMMARY.md

</tasks>

<commit_plan>

Three atomic commits, one per file edit. Validation (Task 4) is a no-commit
gate; if it passes, write SUMMARY.md and let the orchestrator do the docs
commit.

1. `fix(provisioner): apt-get update before locales install (AL-37)`
   — plugin/provisioner/10-agent-user.sh

2. `fix(provisioner): apt-get update before sudo install (AL-37)`
   — plugin/provisioner/20-sudoers.sh

3. `test(docker): empty apt cache in Dockerfile.dogfood — AL-37 regression coverage`
   — tests/docker/Dockerfile.dogfood

</commit_plan>

<pitfalls>

- **Do NOT add `apt-get update` UNGATED at the top of either file.** It must
  stay inside the `if ! command -v ...; then` block. Running apt-get update
  on every installer re-run when the prereq is already installed is wasted
  network + log noise; the existing gate skips both lines today and must
  keep that property.

- **Do NOT add `|| true` to the new apt-get update.** Strict mode is the
  whole point — a real apt failure (broken sources, network outage, GPG
  expiry) MUST surface as an installer-level ERR-trap with src:line
  attribution. Silencing it would mask exactly the class of bug AL-37 is
  fixing.

- **Do NOT add `set -e`/`set -u`/`set -o pipefail` to either provisioner.**
  Both file headers state explicitly: "Sourced by plugin/bin/agentlinux-
  install. Inherits `set -euo pipefail`, the ERR trap, and the tee redirect
  ... ; this fragment therefore MUST NOT set its own strict-mode flags."

- **Do NOT consolidate the two `DEBIAN_FRONTEND=noninteractive apt-get`
  calls** into a single combined `apt-get update && apt-get install` (e.g.,
  via a helper). The existing 30-nodejs.sh idiom keeps them as two adjacent
  statements; idiom consistency matters more than line-count optimization.

- **Do NOT touch the `30-nodejs.sh` apt-get update.** It is unconditional
  (correct, because nodejs is always installed) and is the canonical
  reference pattern. Editing it would broaden scope.

- **Do NOT change the auto-install gate's `command -v` predicate** to a
  `dpkg -l` or `apt-cache policy` check. The existing predicate is the
  right shape (presence of the binary on PATH); switching it would change
  semantics for hosts that have the package but a corrupted install.

- **Do NOT clean `/var/lib/apt/lists/` in Dockerfile.ubuntu-22.04 /
  Dockerfile.ubuntu-24.04 / Dockerfile.ubuntu-26.04.** Those are the heavier
  bats CI images, not the dogfood image. They populate the cache for
  reasons unrelated to AL-37 (the installer + bats setup steps both rely on
  apt). Scope is dogfood-only.

</pitfalls>
