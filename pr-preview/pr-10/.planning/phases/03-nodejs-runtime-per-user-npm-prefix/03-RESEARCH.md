# Phase 3: Node.js Runtime + Per-User npm Prefix - Research

**Researched:** 2026-04-18
**Domain:** Node.js package management on Ubuntu via apt; per-user npm global prefix; bats behavior verification across six invocation modes
**Confidence:** HIGH (NodeSource script content verified by direct fetch; npm precedence verified against official docs; Node 22 LTS dates verified against nodejs/Release; cowsay metadata verified against registry.npmjs.org)

## Summary

Phase 3 drops a single new bash provisioner (`plugin/provisioner/30-nodejs.sh`) between `10-agent-user.sh` and `40-path-wiring.sh` and a single new bats file (`tests/bats/30-runtime.bats`) — re-using every primitive shipped in Phase 2 (`as_user`, `ensure_dir`, `ensure_line_in_file`, log helpers, `invoke_modes`, `assertions`). The provisioner installs system Node.js 22 LTS via the official NodeSource apt repo, writes `~agent/.npmrc` with `prefix=/home/agent/.npm-global`, and creates the prefix directory agent-owned. PATH wiring for `/home/agent/.npm-global/bin` is already contractually handled by `40-path-wiring.sh` — Phase 3's responsibility is only to extend that file's three literal-PATH artefacts (profile.d `case`, agentlinux.env, cron.d) to prepend the npm-global bin path, and to guarantee the directory + .npmrc exist before any `as_user -- npm install -g` fires.

The tests loop all six `INVOKE_MODES` for a round-trip (`install cowsay` → binary on PATH in every mode → `uninstall cowsay` → binary gone + filesystem byte-clean in every mode) and cross-verify `npm config get prefix` returns a path under `/home/agent/` via a new `assert_user_prefix_in_home` helper. RT-04's correctness is the keystone ownership proof: a `prefix` value under `/usr`, `/usr/local`, or any root-owned path is an immediate fail and would mean the entire ADR-004 decision has broken.

The tricky parts this research surfaced, in order: (1) NodeSource's 2026 setup_22.x writes `nodesource.sources` (deb822), NOT `nodesource.list` — the CONTEXT.md idempotency-gate path is wrong and must be corrected. (2) Our Dockerfiles ship `ca-certificates` but NOT `curl` or `gnupg` — NodeSource's script installs those itself, so the provisioner has two options: let NodeSource install them, or pre-install them via apt before calling the script. (3) BHV-05's known-gap (`bash -c` non-login under sudoers `secure_path`) means the Phase 3 RT-02 loop has exactly the same constraint Phase 2 accepted — `run_sudo_u` uses `bash --login -c`. (4) A `.npmrc` with `prefix=` PLUS `globalconfig=` is flagged by nvm as "breaks nvm," but since ADR-005 bans version managers, the simpler `prefix=`-only form is correct and safe. (5) The four-file PATH contract from Phase 2 must be extended in Phase 3 — prepending `/home/agent/.npm-global/bin` to the `/home/agent/.local/bin` entry in profile.d's case, agentlinux.env's literal, and cron.d's literal header. The `.bashrc` marker block sources profile.d and needs NO change.

**Primary recommendation:** Ship a ~80-line `30-nodejs.sh` that (a) pre-installs `curl gnupg ca-certificates` via apt, (b) runs the NodeSource `setup_22.x` script exactly once guarded on `/etc/apt/sources.list.d/nodesource.sources` existence AND `nodejs` package presence, (c) `apt-get install -y nodejs`, (d) `ensure_dir /home/agent/.npm-global 0755 agent:agent`, (e) writes `~agent/.npmrc` via `ensure_line_in_file 'prefix=/home/agent/.npm-global' /home/agent/.npmrc` plus post-write `chown agent:agent + chmod 0644`. Extend `40-path-wiring.sh`'s three PATH-carrying artefacts to prepend `/home/agent/.npm-global/bin` before `/home/agent/.local/bin`. Ship `tests/bats/30-runtime.bats` with one round-trip test (install + uninstall) looping all six `INVOKE_MODES` plus one `assert_user_prefix_in_home` @test per mode.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Node.js Install Path:**
- Install source: **NodeSource apt repo** (Node 22 LTS "Jod"), added via `curl -fsSL https://deb.nodesource.com/setup_22.x | bash`. Authoritative upstream distro of Node on Ubuntu; pinned major version.
- New provisioner: **`plugin/provisioner/30-nodejs.sh`** — runs AFTER `10-agent-user.sh` (user must exist) and AFTER `40-path-wiring.sh` (PATH/npmrc semantics already wired). Ordering: 10 → 30 → 40 remains numerically monotonic.
- Idempotency: `command -v node` + version compare; if `node --version | cut -dv -f2 | cut -d. -f1` ≥ 22 → skip install (log_info "Node ≥22 already installed"). If < 22 or missing → add NodeSource repo (idempotent — skip repo add if `/etc/apt/sources.list.d/nodesource.list` exists) and `apt-get install -y nodejs`.
- Major version: **Node 22 LTS** per ADR-005. No floating "latest LTS" — major bumps are a release-gate decision, not an install-time auto-upgrade.
- Pre-existing Node behavior: if user has Node installed (any version), log_warn the version and respect it if ≥22. Never destructively downgrade or remove. Full purge only via the `--purge` flag (wired in Phase 4/6 for INST-04).

> **CORRECTION** (surfaced by Step 3 upstream fetch): the CONTEXT locked path `/etc/apt/sources.list.d/nodesource.list` is the LEGACY filename. NodeSource's 2026 setup_22.x script writes `/etc/apt/sources.list.d/nodesource.sources` (deb822 format). The Phase 3 idempotency gate MUST check `nodesource.sources` — see §Common Pitfalls Pitfall 1. `nodesource.list` check still has value as a defense-against-old-state signal but cannot be the primary guard. Honor the user's intent (skip repo add if already wired) with the correct path.

**Per-User npm Prefix Layout:**
- Prefix location: **`/home/agent/.npm-global`** — matches v0.2.0 precedent; human-obvious; under agent home so agent fully owns it.
- Configuration mechanism: write `~agent/.npmrc` with literal line `prefix=/home/agent/.npm-global` via `as_user` + `ensure_line_in_file` (idempotent, no duplicate lines on re-run). Directory created with `ensure_dir /home/agent/.npm-global 0755 agent:agent`.
- PATH wiring: **already complete from Phase 2** — `/etc/profile.d/agentlinux.sh`, `/etc/agentlinux.env`, `/etc/cron.d/agentlinux`, and `~agent/.bashrc` marker block all include `/home/agent/.npm-global/bin`. Phase 3 does NOT re-touch those files; it only ensures the target directory exists and the npm config points there.

> **PRECISION** (cross-verified against `40-path-wiring.sh` source): Phase 2's shipped artefacts do NOT yet include `/home/agent/.npm-global/bin` — the file itself documents "Phase 3 will prepend $HOME/.npm-global/bin to all three files that carry a literal PATH." The CONTEXT's "already complete" statement is aspirational (PATH contract established, extension deferred); Phase 3 MUST perform the `/home/agent/.npm-global/bin` prepend across the three PATH-carrying artefacts (profile.d case, agentlinux.env, cron.d). The `.bashrc` marker block sources profile.d and needs NO change. Document this as a locked Phase 3 deliverable (see §Architecture Patterns → Pattern 2).

- npm cache: default location (`/home/agent/.npm`) — agent-owned, no additional config required. Cache collision with other users is impossible because it lives under agent home.

**Phase 3 Test Coverage & Smoke Package:**
- Smoke package for RT-02: **`cowsay`** — zero runtime deps, ~6 KB tarball, ships a single `cowsay` binary on PATH. Well-known enough that a human reading a test sees it as a throwaway. Explicitly NOT a catalog agent (respects CAT-02 "no agents installed by default"). If cowsay registry availability becomes flaky, fallback to `is-ci` (but cowsay is the canonical choice).

> **DATA POINT** (registry.npmjs.org fetch): current `cowsay@latest` is **v1.6.0** (not v1.5.0). Ships TWO bin entries: `cowsay` AND `cowthink` (both point to `cli.js`). Unpacked size 495,745 bytes (~484 KB), not "~6 KB tarball" — the tarball is ~166 KB, but what lands on disk is ~484 KB. Has four runtime deps (`get-stdin`, `string-width`, `strip-final-newline`, `yargs`). Registry tarball URL pins: `https://registry.npmjs.org/cowsay/-/cowsay-1.6.0.tgz`. SHA-512 integrity: `8C4H1jdrgN...`. `engines.node >= 4` — trivially compatible with Node 22. RT-02 may pin `cowsay@1.6.0` for reproducibility; RT-03 asserts BOTH bins are gone from `/home/agent/.npm-global/bin/` after uninstall.

- Invocation-mode coverage: **new `tests/bats/30-runtime.bats`** reuses the six helpers from `tests/bats/helpers/invoke_modes.bash` (already shipped in Phase 2 Plan 02-05). Tests loop all six modes asserting `command -v cowsay && cowsay hi` succeeds in each, after an `as_user -- npm install -g cowsay`.
- RT-04 assertion: **new helper `assert_user_prefix_in_home`** in `tests/bats/helpers/assertions.bash` (append to existing file from Phase 2). Asserts `npm config get prefix` returns a path under `/home/agent/` — never `/usr`, `/usr/local`, or any root-owned path. Includes diagnostic-on-fail (`# RT-04: expected /home/agent/.npm-global, observed $observed`).
- RT-03 uninstall cleanliness: after `as_user -- npm uninstall -g cowsay`, assert across all six invocation modes that `command -v cowsay` returns non-zero AND `/home/agent/.npm-global/bin/cowsay` does not exist AND `/home/agent/.npm-global/lib/node_modules/cowsay` does not exist. No leftover bytes.

### Claude's Discretion

- Exact split of `plugin/provisioner/30-nodejs.sh` — single file or a tiny `plugin/lib/nodejs_install.sh` helper, whichever keeps the provisioner under ~100 LOC.
- Implementation detail of `assert_user_prefix_in_home` — any shape that returns non-zero with a diagnostic when `npm config get prefix` is outside `/home/agent/`.
- Whether `cowsay` version is pinned in the smoke test (`npm install -g cowsay@1.6.0`) or floating — Claude picks based on registry pinning precedent; pinning is safer against upstream churn, floating is simpler.
- Whether 30-nodejs.sh caches the NodeSource PGP key to a temp file or pipes through `gpg --dearmor` inline — either is acceptable; research recommends the upstream-script pattern (let NodeSource's setup_22.x do it; don't re-implement) — see §Code Examples §Example 1.
- Plan count and wave structure — Phase 2 used 5 plans × 3 waves; Phase 3 is smaller scope (4 requirements), probably 2 plans × 2 waves (provisioner + tests). Planner decides.

### Deferred Ideas (OUT OF SCOPE)

- `agentlinux doctor` command to check Node version, npm prefix health, PATH correctness, etc. (CLI-08 v0.4+).
- Floating "latest LTS" Node.js major version — Phase 3 pins to 22 LTS; bumping to 24 LTS is a v0.4+ decision.
- Multi-Node-version support (e.g., Node 20 + 22 coexisting for compatibility testing) — not needed for v0.3.0; one LTS suffices.
- Node.js installed from a binary tarball for air-gapped environments — v0.4+.
- Alternative package managers (pnpm, yarn) globally installed for the agent — none of the v0.3.0 catalog agents require them; v0.4+ decision.
- Pinning the Node PATCH version (e.g., 22.11.0 rather than latest 22.x) — out of scope; NodeSource pins major + tracks minor/patch.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RT-01 | The agent user has a Node.js LTS runtime available. `node --version` returns an LTS version number, both interactively and non-interactively. | §Standard Stack (Node 22 LTS via NodeSource apt), §Code Examples §Example 1 (idempotent setup), §Architecture Patterns → Pattern 1 (system-installed node visible on every PATH mode because `/usr/bin/node` is on the system PATH wired in Phase 2 agentlinux.env) |
| RT-02 | `npm install -g <some-package>` without sudo, without EACCES, without shim/wrapper workarounds. Binary findable on PATH in every invocation mode (BHV-02..06). | §Architecture Patterns → Pattern 2 (per-user prefix via .npmrc + PATH prepend), §Common Pitfalls Pitfalls 4/5/7 (the canonical EACCES bug class this phase exists to prevent), §Validation Architecture (six-mode loop) |
| RT-03 | `npm uninstall -g <some-package>` cleanly. No leftover files; binary disappears from PATH. | §Common Pitfalls Pitfall 8 (uninstall leftover-symlinks cleanup). RT-03 assertion is strict-byte-clean (no orphan `/home/agent/.npm-global/lib/node_modules/cowsay` directory) — strong mutation-kill. |
| RT-04 | `npm config get prefix` returns a path under agent home — NEVER `/usr`, `/usr/local`, or any root-owned path. | §Architecture Patterns → Pattern 2 (`.npmrc` prefix); §Code Examples §Example 4 (`assert_user_prefix_in_home` helper); §Standard Stack → npm precedence table. |

## Project Constraints (from CLAUDE.md)

CLAUDE.md non-obvious rules that bind Phase 3:

| Rule | Phase 3 Application |
|------|---------------------|
| Never `sudo npm install -g` anywhere. Always `sudo -u agent -H npm install -g` (= `as_user agent npm install -g`). | Every npm invocation in `30-nodejs.sh` and `30-runtime.bats` routes through `as_user`. The raw `sudo -u` grep must return zero new matches in plugin/ after Phase 3. |
| Behavior tests in tests/bats/ are the spec. Implementation may change freely as long as tests stay green. Do not pin implementation choices. | RT-01..04 are phrased as observable behaviors. The `30-nodejs.sh` provisioner is free to use either NodeSource's `setup_22.x` pipe or a manual apt-keyring approach as long as `apt install nodejs` succeeds and the resulting runtime satisfies RT-01..04. The tests assert the outcome, not the path to get there. |
| No agent is installed by default. Claude Code, GSD, Playwright are in the catalog; users opt in. | cowsay is a smoke package for RT-02 testing, NOT a default-installed catalog agent. The test installs + uninstalls it inside bats — no residue at phase close. CAT-02 is preserved. |
| No wrapper shims at /usr/local/bin/ pointing to agent-owned binaries — the exact anti-pattern that breaks Claude Code self-update. | Every binary cowsay installs MUST land in `/home/agent/.npm-global/bin/cowsay`, NOT `/usr/local/bin/cowsay`. If RT-02 somehow lands a binary under `/usr/local/bin/`, RT-04's `assert_user_prefix_in_home` fires AND RT-02's `command -v cowsay` resolution check catches it. |
| Every release tarball ships with a sibling `.sha256`. Curl-installer verifies before executing. | Out of Phase 3 scope (Phase 6). NodeSource's setup_22.x is fetched via curl-pipe-bash at install time; the script itself is NOT sha256-verified by us. Accepted pragmatically — NodeSource is the upstream-blessed path (ADR-005); GPG-signed apt repo after install provides ongoing integrity. |
| Review loop before complete. Bash → bash-engineer + security-engineer + qa-engineer. Bats → qa-engineer + behavior-coverage-auditor. | Each Phase 3 plan runs this gate. behavior-coverage-auditor gates phase close: every RT-01..04 needs ≥1 ID-prefixed @test (TST-07). |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Node.js binary (node, npm, npx) provisioning | System package tier (apt / NodeSource) | — | ADR-005: version managers break non-interactive invocation modes. System package via apt is the only way to get node on PATH in cron + systemd + non-interactive SSH without shell-hook activation. |
| npm global-install prefix configuration | User config tier (`~agent/.npmrc`) | Env var tier (`NPM_CONFIG_PREFIX` in `/etc/agentlinux.env`) | File-based `.npmrc` is self-contained + visible to `npm config get prefix` in every mode. Env-var fallback is belt-and-braces for edge cases where HOME isn't correctly resolved (but file-based is the primary). |
| PATH wiring for `/home/agent/.npm-global/bin` | Installer tier (Phase 2's four-file PATH contract, extended by Phase 3) | — | The same four artefacts from `40-path-wiring.sh` (profile.d, .bashrc-top, agentlinux.env, cron.d) cover all six modes. Phase 3 extends three of them (the three carrying literal PATH) with a prepend; the fourth (.bashrc) sources profile.d. |
| Per-user prefix directory + ownership | Installer tier (`ensure_dir` in 30-nodejs.sh) | — | Dir must exist agent-owned before `as_user -- npm install -g <pkg>` fires, otherwise npm creates it root-owned as a side effect of being run-once-by-root-to-bootstrap (we're not doing that, but defensive). |
| Smoke-test install/uninstall round-trip | Test tier (`tests/bats/30-runtime.bats`) | — | Observable-behavior contract (ADR-002): RT-01..04 are observable assertions on the installed runtime, not implementation details of the provisioner. |
| RT-04 "prefix under home" assertion | Test-helper tier (`assert_user_prefix_in_home` in helpers/assertions.bash) | — | Re-usable across Phase 3 tests; lives alongside the three existing helpers (assert_no_eacces, assert_path_has, assert_exit_zero) from Phase 2. TST-04 diagnostic shape inherited. |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| NodeSource apt repo | `setup_22.x` (tracks Node 22.x) | Ubuntu-native Node.js 22 LTS installation | ADR-005 mandate. Upstream-blessed path. Modern deb822 sources format. GPG-signed. Works in every invocation mode (no shell hook). [VERIFIED: direct fetch of https://deb.nodesource.com/setup_22.x on 2026-04-18 — 121-line bash script; installs curl/gnupg/apt-transport-https/ca-certificates itself; creates `/usr/share/keyrings/nodesource.gpg` via `gpg --dearmor`; writes `/etc/apt/sources.list.d/nodesource.sources` deb822; sets Pin-Priority 600 in `/etc/apt/preferences.d/{nodejs,nsolid}`] |
| Node.js | 22.x LTS ("Jod") | JavaScript runtime on which agent tools run | Node 22 entered Active LTS 2024-10-29, transitioned to Maintenance LTS 2025-10-21, EOL 2027-04-30. [VERIFIED: nodejs.org/en/about/previous-releases + github.com/nodejs/Release schedule; current patch version v22.22.2 as of 2026-03-24] |
| npm | 10.x (bundled with Node 22) | Package manager | Ships with the `nodejs` apt package; no separate install. npm 10 respects the documented precedence order: CLI flag > NPM_CONFIG_* env > project .npmrc > user .npmrc > global .npmrc > builtin. [CITED: docs.npmjs.com/cli/v10/configuring-npm/npmrc/] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| cowsay | 1.6.0 | RT-02 smoke test install target | Phase 3 bats only. NEVER installed by default. [VERIFIED: direct fetch of registry.npmjs.org/cowsay/latest on 2026-04-18 — version 1.6.0, 4 runtime deps, 2 bins (cowsay + cowthink), ~484 KB unpacked] |
| apt-transport-https, ca-certificates, curl, gnupg | Ubuntu apt | NodeSource pre-reqs | NodeSource's setup_22.x installs these itself (line 51 of the script); Phase 3 provisioner can let that happen OR pre-install them. Our Dockerfiles ship `ca-certificates` but NOT `curl` or `gnupg` — see Environment Availability section. [VERIFIED: direct inspection of Dockerfile.ubuntu-{22,24}.04] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| NodeSource apt | Ubuntu's built-in `nodejs` package | Ubuntu 22.04 ships Node 12.x, Ubuntu 24.04 ships Node 18.x — both below our required v22 LTS. Rejected by ADR-005. |
| NodeSource apt | nvm / fnm / volta | Version managers require shell-hook activation (eval `$(fnm env)` / source nvm.sh) that breaks cron, systemd, non-interactive SSH. Rejected by ADR-005 explicitly. |
| NodeSource apt | Manual Node tarball under /opt | Requires hand-rolled update logic, PATH wiring, and defeats ADR-005's "system package manager" posture. Reserved for air-gapped v0.4+. |
| `.npmrc` prefix file | `NPM_CONFIG_PREFIX` env var in `/etc/agentlinux.env` | Both work; env var takes precedence over file. File-based is preferred here because (a) `npm config get prefix` shows it without a `--json` dance, (b) it's self-contained in agent home (no installer-owned env leak into user space), (c) it survives `env -i` callers. Env var is a reasonable belt-and-braces fallback. [CITED: npm/cli#4467 — NPM_CONFIG_PREFIX has edge-case bugs with --prefix flag that .npmrc avoids] |
| cowsay smoke package | `is-ci`, `which`, `left-pad` | cowsay produces visible output in its binary (printed ASCII cow), so `cowsay hi` vs. `command -v cowsay` gives two independent assertions from one test. Fallback if cowsay goes flaky: `is-ci` (tiny, zero-dep). |

**Installation (by `30-nodejs.sh`):**
```bash
# The NodeSource script handles curl/gnupg/ca-certificates itself,
# but pre-installing avoids an apt-transaction nested inside their script
# and makes the pre-req install visible in our log.
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  curl gnupg ca-certificates apt-transport-https

# Idempotency gate: skip if the NodeSource deb822 sources file already exists.
# (Legacy `nodesource.list` is ALSO cleaned by setup_22.x; we check the new
# path because that's what the current script writes.)
if [[ ! -f /etc/apt/sources.list.d/nodesource.sources ]]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
fi

DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs
```

**Version verification:**
```bash
npm view cowsay version   # → 1.6.0 (as of 2026-04-18)
node --version            # post-install → v22.22.x
npm --version             # bundled → 10.x
```
Verified 2026-04-18. Node 22 maintenance window closes 2027-04-30; Phase 3's pin remains valid until then. cowsay@1.6.0 published 2024-01-26 (~2 years stable), so pin risk is low.

## Architecture Patterns

### System Architecture Diagram

```
 agentlinux-install (root) ──────────────────────────────────────────────────┐
      │                                                                      │
      ├── 10-agent-user.sh    ──► creates /home/agent + locale + CLAUDE.md   │
      │                                                                      │
      ├── 30-nodejs.sh    NEW                                                │
      │     ├── apt-get install curl gnupg ca-certificates                   │
      │     ├── [ -f /etc/apt/sources.list.d/nodesource.sources ] || {       │
      │     │     curl -fsSL https://deb.nodesource.com/setup_22.x | bash - │
      │     │   }                                                            │
      │     ├── apt-get install -y nodejs                                    │
      │     │     writes: /usr/bin/node /usr/bin/npm /usr/bin/npx            │
      │     │     writes: /usr/share/keyrings/nodesource.gpg                 │
      │     │     writes: /etc/apt/sources.list.d/nodesource.sources         │
      │     │     writes: /etc/apt/preferences.d/{nodejs,nsolid}             │
      │     ├── ensure_dir /home/agent/.npm-global 0755 agent:agent          │
      │     └── write ~agent/.npmrc (prefix=/home/agent/.npm-global)         │
      │                                                                      │
      └── 40-path-wiring.sh                                                  │
           EXTEND three literal-PATH artefacts with /home/agent/.npm-global/bin
               profile.d/agentlinux.sh case-prepend  (BHV-06 + BHV-05 -i)   │
               agentlinux.env     literal PATH=       (BHV-04 systemd)     │
               cron.d/agentlinux  literal PATH=       (BHV-03 cron)        │
           ( .bashrc marker block unchanged — sources profile.d )          │

 ── AT TEST TIME (tests/bats/30-runtime.bats) ────────────────────────────── │
    for mode in "${INVOKE_MODES[@]}"; do                                     │
      invoke_mode "$mode" 'as_user agent npm install -g cowsay@1.6.0'        │
        └──► writes /home/agent/.npm-global/bin/cowsay                       │
             writes /home/agent/.npm-global/bin/cowthink                     │
             writes /home/agent/.npm-global/lib/node_modules/cowsay/         │
      invoke_mode "$mode" 'command -v cowsay' ──► /home/agent/.npm-global/bin/cowsay
      invoke_mode "$mode" 'cowsay hi'          ──► ASCII cow output, exit 0  │
      invoke_mode "$mode" 'npm config get prefix' ──► /home/agent/.npm-global
      invoke_mode "$mode" 'as_user agent npm uninstall -g cowsay'            │
      invoke_mode "$mode" 'command -v cowsay'  ──► exit 1 (not found)        │
      assert_byte_clean /home/agent/.npm-global/bin/cowsay      not-exist    │
      assert_byte_clean /home/agent/.npm-global/lib/.../cowsay  not-exist    │
    done

 ── ZERO ── EACCES|permission denied in installer log or any test output ── │
```

### Recommended Project Structure (Phase 3 delta from Phase 2)

```
plugin/
├── bin/agentlinux-install        (unchanged — dispatches 10 → 30 → 40 via glob)
├── lib/                          (unchanged — all four helpers re-used)
├── provisioner/
│   ├── 10-agent-user.sh         (unchanged)
│   ├── 30-nodejs.sh             NEW (~80 LOC; Node + npm prefix + .npmrc)
│   └── 40-path-wiring.sh        MODIFIED (extend 3 literal-PATH artefacts)
└── …

tests/
├── bats/
│   ├── 10-installer.bats        (unchanged)
│   ├── 20-agent-user.bats       (unchanged — Phase 2 still green)
│   ├── 30-runtime.bats          NEW (RT-01..04 coverage, ~120 LOC)
│   └── helpers/
│       ├── invoke_modes.bash    (unchanged — six helpers re-used)
│       └── assertions.bash      MODIFIED (append `assert_user_prefix_in_home`)
└── docker/
    └── Dockerfile.ubuntu-{22,24}.04   DECISION: add `curl gnupg` (see Env Availability)
```

### Pattern 1: NodeSource install with idempotency gate + pre-existing-Node guard

**What:** Single-pass, re-runnable install of Node 22 LTS via NodeSource's setup_22.x script.
**When to use:** Phase 3 `30-nodejs.sh` — every Ubuntu 22.04/24.04 install flow.
**Invariant:** On second run, the NodeSource repo is NOT re-added, the GPG key is NOT re-imported, and `apt-get install` is a no-op if the package is already at the installed version.

```bash
# Source: upstream NodeSource setup_22.x (fetched 2026-04-18) — lines 55-61
# show the script itself rm -fs any pre-existing keyring/sources files
# and re-creates them, so if WE guard the whole thing with a single existence
# check we avoid the re-import + re-import pattern.

# Step 1: ensure pre-requisites (NodeSource installs these too, but we
# pre-install so our installer log shows them).
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  curl gnupg ca-certificates apt-transport-https

# Step 2: idempotent repo add. We check the NEW deb822 filename
# (nodesource.sources), NOT the legacy nodesource.list — the 2026 script
# writes the former. See Pitfall 1 for the full history.
if [[ ! -f /etc/apt/sources.list.d/nodesource.sources ]]; then
  log_info "NodeSource apt repo absent — running setup_22.x"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
else
  log_info "NodeSource apt repo already configured (nodesource.sources present)"
fi

# Step 3: idempotent install. apt-get install is a no-op if the package
# is already at the desired version. The `|| true` is NOT used — we want
# apt failure to propagate.
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs

# Step 4: verify post-install. Extract major version and hard-fail if < 22.
node_major=$(node --version 2>/dev/null | sed 's/^v\([0-9]*\)\..*$/\1/')
if [[ "${node_major:-0}" -lt 22 ]]; then
  log_error "node ${node_major:-unset} installed but v22 LTS required"
  return 1
fi
log_info "Node.js v$(node --version | tr -d 'v') installed (LTS ≥22 — RT-01 satisfied)"
```

### Pattern 2: Per-user npm prefix via `.npmrc` + PATH prepend across three artefacts

**What:** Agent's npm global prefix is `/home/agent/.npm-global`, configured in `~agent/.npmrc`, with the prefix's `bin/` prepended to PATH in every invocation mode.
**When to use:** Phase 3 `30-nodejs.sh` (configure prefix) + extend `40-path-wiring.sh` (wire PATH).
**Invariant:** `npm config get prefix` returns `/home/agent/.npm-global` in every BHV mode. `npm install -g <pkg>` as the agent user succeeds without EACCES. `<pkg>`'s binary resolves to `/home/agent/.npm-global/bin/<pkg>`.

```bash
# In 30-nodejs.sh (after Node install):

# Create the prefix directory agent-owned BEFORE any npm invocation.
# This prevents npm creating it root-owned if root somehow ran npm first
# (we don't, but defensive — see Pitfall 4).
ensure_dir /home/agent/.npm-global 0755 agent:agent
ensure_dir /home/agent/.npm-global/bin 0755 agent:agent
ensure_dir /home/agent/.npm-global/lib 0755 agent:agent

# Create agent's .npmrc with the prefix line. ensure_line_in_file handles
# idempotency — re-runs don't duplicate the line.
if [[ ! -f /home/agent/.npmrc ]]; then
  install -m 0644 -o agent -g agent /dev/null /home/agent/.npmrc
fi
ensure_line_in_file 'prefix=/home/agent/.npm-global' /home/agent/.npmrc
chown agent:agent /home/agent/.npmrc
chmod 0644 /home/agent/.npmrc
log_info "wrote ~agent/.npmrc (prefix=/home/agent/.npm-global — RT-04 satisfied)"
```

**Plus** in `40-path-wiring.sh` (three artefacts extended):

```bash
# /etc/profile.d/agentlinux.sh — case-prepend /home/agent/.npm-global/bin
# BEFORE /home/agent/.local/bin. Case-guard ensures second source doesn't
# double-prepend (idempotent on re-login).
case ":${PATH}:" in
  *:/home/agent/.npm-global/bin:*) : ;;
  *) PATH="/home/agent/.npm-global/bin:${PATH}" ;;
esac
case ":${PATH}:" in
  *:/home/agent/.local/bin:*) : ;;
  *) PATH="/home/agent/.local/bin:${PATH}" ;;
esac
export PATH

# /etc/agentlinux.env — literal PATH= (for systemd EnvironmentFile=).
PATH=/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin

# /etc/cron.d/agentlinux — literal PATH= header.
PATH=/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin
```

### Pattern 3: Six-mode round-trip test loop (RT-02 + RT-03)

**What:** Loop all six `INVOKE_MODES` performing an install → assert → uninstall → assert-gone sequence.
**When to use:** `tests/bats/30-runtime.bats` for RT-02 and RT-03.
**Invariant:** Each mode installs cowsay, sees it on PATH, runs it successfully, uninstalls it, and confirms byte-clean removal.

```bash
# tests/bats/30-runtime.bats — test loop skeleton
@test "RT-02: npm install -g cowsay works in every invocation mode" {
  # Install once, as agent user, via as_user (not sudo -u — keystone rule).
  run sudo -u agent -H bash --login -c 'npm install -g cowsay@1.6.0 2>&1'
  assert_exit_zero "RT-02"
  assert_no_eacces "RT-02" "$output"

  # Loop all six modes — each must see cowsay on PATH AND produce output.
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'command -v cowsay'
    assert_path_has "RT-02 (${mode})" "/home/agent/.npm-global/bin/cowsay"
    assert_exit_zero "RT-02 (${mode})"

    invoke_mode "$mode" 'cowsay hi'
    assert_path_has "RT-02 (${mode})" "hi"    # cowsay prints the string
    assert_exit_zero "RT-02 (${mode})"
  done
}

@test "RT-03: npm uninstall -g cowsay removes binary and module in every mode" {
  # Assumes a prior test or shared setup already installed cowsay.
  run sudo -u agent -H bash --login -c 'npm uninstall -g cowsay 2>&1'
  assert_exit_zero "RT-03"
  assert_no_eacces "RT-03" "$output"

  # Loop all six modes — each must NOT find cowsay on PATH.
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'command -v cowsay || true'
    if [[ -n "$output" ]] && printf '%s' "$output" | grep -q '/cowsay'; then
      __fail "RT-03 (${mode})" \
        "cowsay NOT findable on PATH" \
        "found: $output" \
        "/var/log/agentlinux-install.log"
    fi
  done

  # Byte-clean filesystem assertion — strongest form of RT-03.
  for target in /home/agent/.npm-global/bin/cowsay \
                /home/agent/.npm-global/bin/cowthink \
                /home/agent/.npm-global/lib/node_modules/cowsay; do
    [[ ! -e $target ]] || __fail "RT-03" \
      "filesystem clean: $target does not exist" \
      "observed: $target still present" \
      "/var/log/agentlinux-install.log"
  done
}
```

### Pattern 4: `assert_user_prefix_in_home` helper (RT-04)

**What:** Observable check that `npm config get prefix` returns a path under `/home/agent/` — never root-owned.
**When to use:** `tests/bats/helpers/assertions.bash` (append to the Phase 2 helpers).
**Invariant:** Any prefix starting with `/usr`, `/usr/local`, `/opt`, or any non-`/home/agent/` path fires `__fail` with TST-04 diagnostic.

```bash
# Append to tests/bats/helpers/assertions.bash
# Usage: after a `run_<mode> 'npm config get prefix'`, call with the req-id:
#   assert_user_prefix_in_home "RT-04 (${mode})"
assert_user_prefix_in_home() {
  local req_id=$1
  local observed=${output:-<empty>}
  # Trim any trailing newline/whitespace that `run` may preserve.
  observed=$(printf '%s' "$observed" | tr -d '[:space:]')

  case "$observed" in
    /home/agent/*)
      # RT-04 passes only if prefix is UNDER /home/agent/.
      return 0
      ;;
    *)
      __fail "$req_id" \
        "npm config get prefix = /home/agent/* (under agent home)" \
        "observed: ${observed}" \
        "~agent/.npmrc (expected: prefix=/home/agent/.npm-global)"
      ;;
  esac
}
```

### Anti-Patterns to Avoid

- **`sudo npm install -g <pkg>`** — the single bug class AgentLinux exists to prevent. Any grep match for this literal across Phase 3 source (outside of doc-comments) fails the security-engineer review rubric. All npm invocations go through `as_user`. See DOC-02 for the canonical policy text.
- **Wrapper shim at `/usr/local/bin/<pkg>` pointing to `/home/agent/.npm-global/bin/<pkg>`** — breaks self-update. Even if a human manually adds such a shim later, RT-02's `command -v cowsay` must resolve to the agent-owned path (the `/home/agent/.npm-global/bin` PATH entry is first, so `command -v` resolves there regardless of any shim downstream). Tests will catch a regression via `assert_path_has` pinning to the agent path.
- **Writing `npm config set prefix` via `root`** — if root runs `npm config set prefix /home/agent/.npm-global`, it writes to `/root/.npmrc`, not to `~agent/.npmrc`. The file-write path MUST be either `install -m 0644 -o agent:agent /dev/null ~agent/.npmrc` + `ensure_line_in_file` OR `as_user agent npm config set prefix ...`. The former is preferred (no npm-runtime side effects during install).
- **Pinning a Node patch version** (e.g., `apt-get install -y nodejs=22.11.0-1nodesource1`) — NodeSource's apt pinning (Pin-Priority 600) tracks latest 22.x. Pinning a patch defeats upstream security-patch flow. Reserved for v0.4+ if a specific bug demands it.
- **Running `npm install -g` in the installer** (not just in tests) — Phase 3 installs NO npm global packages; cowsay is test-only. Future phases install catalog agents via the registry CLI. Keep the installer itself npm-invocation-free outside of Phase 5.
- **Touching `/etc/npmrc`** — that's the global config, root-owned, overrides nothing the user sets. Using it would conflict with the user's prefix in `~agent/.npmrc`. Do not write to `/etc/npmrc`.
- **Using NodeSource's setup script output to drive decisions** (e.g., parsing its log) — the script's output format is not stable. Gate on filesystem state (`nodesource.sources` existence), NOT on script stdout/stderr.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Fetching + dearmoring NodeSource GPG key | Bespoke `curl ... | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg` | NodeSource's `setup_22.x` (it already does this + pins + pref file) | Upstream is the single source of truth — reimplementing their 121-line script is drift-prone. Let `setup_22.x` do the keyring dance; our provisioner just guards the re-run. [VERIFIED: direct fetch of setup_22.x] |
| Detecting if Node 22 LTS is installed | Parse `apt-cache policy nodejs` + version regex | `node --version | cut ...` + integer compare | `apt-cache policy` requires apt-cache to be installed AND depends on repository state. `node --version` is the observable fact; if the binary is on PATH it works. |
| Writing `.npmrc` | `cat <<EOF > ~/.npmrc` | `ensure_line_in_file 'prefix=/home/agent/.npm-global' ~/.npmrc` | Blind append duplicates lines on re-run (INST-02 violation); full-file overwrite deletes user customizations. The grep-before-append primitive from Phase 2 handles both. |
| Building an "npm wrapper" script | Custom `/usr/local/bin/npm` shim | Nothing — just use the system `/usr/bin/npm` | Shims break self-update. The per-user prefix does what wrappers would've done, without the shim. |
| Creating `/home/agent/.npm-global/` with `mkdir + chmod + chown` | Three raw shell calls | `ensure_dir /home/agent/.npm-global 0755 agent:agent` | Single-call atomic create-OR-enforce that corrects out-of-band ownership drift on re-run. |
| PATH merging logic inside tests | Bats loop building PATH strings | `invoke_modes.bash` helpers (already shipped Phase 2) | Six modes, six helpers, one dispatch — re-use is the point. |
| "Is the prefix user-owned?" logic | Shell case-match everywhere prefix is read | `assert_user_prefix_in_home` helper | Centralizes the contract in one place; diagnostic-on-fail via TST-04. |
| Uninstall cleanliness check | `npm uninstall` + hope | `npm uninstall` + filesystem byte-clean assertion | npm's uninstall is mostly clean but leaves corner cases (symlinks from `npm link`); the filesystem assertion catches the residue. See Pitfall 8. |

**Key insight:** NodeSource + system apt + npm's own config mechanism are the three load-bearing pillars. Hand-rolling any of them (a custom keyring, a custom `nodejs` install, a custom npm wrapper) reintroduces the bug class ADR-004 + ADR-005 were designed to eliminate.

## Runtime State Inventory

This phase creates new state but does NOT migrate or rename existing state. A partial inventory:

| Category | Items introduced | Action Required |
|----------|-----------------|------------------|
| Stored data | None in Phase 3. cowsay's install creates `/home/agent/.npm-global/lib/node_modules/cowsay/` but tests uninstall it at phase close. | None. |
| Live service config | None. | None. |
| OS-registered state | `/etc/apt/sources.list.d/nodesource.sources`, `/etc/apt/preferences.d/{nodejs,nsolid}`, `/usr/share/keyrings/nodesource.gpg`. INST-04 (Phase 4/6) will need to unregister these. | Phase 3 tests do NOT test uninstall of the NodeSource repo itself; Phase 4 inventories this for INST-04. |
| Secrets/env vars | None. | None. |
| Build artifacts | Node 22 binary at `/usr/bin/{node,npm,npx}`; cowsay binary at `/home/agent/.npm-global/bin/cowsay` (tests only, removed at phase close). | INST-04 (Phase 4+) removes Node binaries on `--purge`. Phase 3 does not implement --purge. |

**Nothing found in category (stored data / live service config / secrets):** Verified by direct inspection of `30-nodejs.sh` scope — no DBs, no background services, no auth tokens.

## Common Pitfalls

### Pitfall 1: NodeSource filename drift — `nodesource.list` vs. `nodesource.sources`

**What goes wrong:** The legacy `nodesource.list` (one-line format) was replaced by the modern `nodesource.sources` (deb822 multi-line format) in the NodeSource script rewrite (circa 2023). The CONTEXT-locked gate `/etc/apt/sources.list.d/nodesource.list` will NEVER trigger a skip on a fresh install — the modern script writes `nodesource.sources`, not `nodesource.list`.
**Why it happens:** Older tutorials (DigitalOcean, Medium, blog posts) still reference `nodesource.list` because that's the filename the pre-2023 script used. The official script was rewritten for deb822 format (signed-by signatures inline in the source entry instead of a separate `Signed-By:` header elsewhere).
**How to avoid:** Check BOTH filenames in the idempotency gate, but rely on `nodesource.sources` as the primary guard:
```bash
if [[ -f /etc/apt/sources.list.d/nodesource.sources ]] || \
   [[ -f /etc/apt/sources.list.d/nodesource.list ]]; then
  log_info "NodeSource apt repo already configured"
else
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
fi
```
**Warning signs:** Re-running the installer causes `curl | bash` to fire every time (adds ~3s + an apt update); the log shows "Repository configured successfully." on every run instead of "already configured" — INST-02 byte-stability would not be impacted (the script rm -fs and re-creates the same file), but it's wasted work. [VERIFIED: lines 59-60 of the 2026 setup_22.x script show it `rm -f` both filenames before creating the new one, so the script IS self-healing across versions.]

### Pitfall 2: `sudo npm install -g` silently works as root and creates root-owned files under `/usr/lib/node_modules/`

**What goes wrong:** The moment anyone — human operator, test harness, CI wrapper — runs `sudo npm install -g <pkg>` on a box with a fresh NodeSource install, npm inherits root's environment, ignores `~agent/.npmrc`, and writes `/usr/lib/node_modules/<pkg>/` (root:root) plus a symlink at `/usr/local/bin/<pkg>` or `/usr/bin/<pkg>`. On the NEXT attempt to run the same install as the agent user, npm sees the root-owned directory, tries to write into it, and fires EACCES. The bug then "requires" a `sudo chown -R agent /usr/lib/node_modules/<pkg>/` to recover — which deepens the root-ownership hole instead of fixing it.
**Why it happens:** root's `$HOME=/root` → npm reads `/root/.npmrc` (which has no prefix line) → npm falls back to the builtin prefix which derives from `node`'s installation location (`/usr`). root can write there, so npm succeeds. No error; the installer moves on; the agent silently has a root-owned global module directory.
**How to avoid:** `as_user agent npm install -g <pkg>` is the ONLY form. Never raw `sudo -u agent` (secure_path strips PATH) and never root-native `npm install -g`. Defense-in-depth: the `security-engineer` subagent rubric greps for `sudo npm install -g` on every review. CLAUDE.md enshrines it. DOC-02 in `/home/agent/CLAUDE.md` instructs agent tools to never work around an EACCES by escalating.
**Warning signs:** Any file under `/usr/lib/node_modules/` owned by root (other than the three that ship with the `nodejs` apt package: `/usr/lib/node_modules/npm/` etc. — and those are normal); EACCES in the installer log (INST-05); `npm config get prefix` returning `/usr` instead of `/home/agent/.npm-global`. [CITED: docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally]

### Pitfall 3: `npm install -g` as root with HOME unset creates broken state

**What goes wrong:** Cron and systemd sometimes launch commands with minimal env (`HOME` unset or `HOME=/`). If `npm install -g <pkg>` runs in such a context, npm tries to read `.npmrc` from `/root/.npmrc` (root) or `/` (nobody) — and whichever is readable determines the prefix. Result: deterministic for one launch context, unpredictable across contexts.
**Why it happens:** npm derives user config path from `$HOME/.npmrc` by default. Unset `HOME` → npm falls back to builtin or passwd-entry lookup depending on npm version.
**How to avoid:** `as_user` already sets `-H` which forces `HOME=/home/agent` (see `plugin/lib/as_user.sh` header comment — "load-bearing for ~/.npmrc lookups, Phase 3"). The test harness's `run_systemd_user` helper also passes `--setenv=HOME=/home/agent` explicitly (see `invoke_modes.bash:104`). As long as no test invokes npm via a path that skips both, `$HOME` is guaranteed set.
**Warning signs:** `npm config get prefix` returns `/usr` in ONE mode but `/home/agent/.npm-global` in the five others; systemd-specific failures that don't reproduce in SSH; `.npmrc` parse errors in the log.

### Pitfall 4: PATH prepend order — `/home/agent/.npm-global/bin` must come BEFORE `/usr/local/bin`

**What goes wrong:** If `/usr/local/bin` is earlier in PATH than `/home/agent/.npm-global/bin`, and some past-state leftover shim exists at `/usr/local/bin/cowsay`, `command -v cowsay` resolves to the shim, not the agent-owned binary. Breaks self-update for any tool (because self-update rewrites the agent-owned path, not the shim).
**Why it happens:** Phase 2's Pattern was `/home/agent/.local/bin:/usr/local/bin:...`; extending this naively with `/home/agent/.npm-global/bin` at the END puts it after `/usr/local/bin`.
**How to avoid:** Prepend `/home/agent/.npm-global/bin` to the FRONT of the PATH literal in all three carrying artefacts. Final form:
```
PATH=/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin
```
Cross-grep verify in a plan acceptance criterion: the literal string above appears in both `/etc/agentlinux.env` and `/etc/cron.d/agentlinux`; profile.d uses case-prepend in reverse order (npm-global first because case-prepend stacks). The order `npm-global` first > `.local` second > system last is the keystone ownership-prefix invariant.
**Warning signs:** `command -v cowsay` resolves to `/usr/local/bin/cowsay` in any test mode; BHV tests from Phase 2 still pass (they only assert `.local/bin` is present) but RT-02 fails on the binary-location check.

### Pitfall 5: npm reads `~agent/.npmrc` only when `HOME=/home/agent` (not passwd-derived)

**What goes wrong:** Some npm versions (npm 6, npm 7 early) derived the user config path from passwd-entry lookup (`getpwuid(getuid())`), not from `$HOME`. Modern npm 10 (bundled with Node 22) uses `$HOME` first. But a belt-and-braces test should exercise both the SSH path (HOME set by PAM) AND the cron path (HOME set by cron's default env) to catch any regression.
**Why it happens:** Historical drift in npm's config-file resolution. Modern npm is consistent, but any future npm upgrade could regress.
**How to avoid:** Test `npm config get prefix` in every one of the six `INVOKE_MODES` — not just "run once, assume it's fine." The six-mode loop is the defense. Additionally, `/etc/agentlinux.env` ships `NPM_CONFIG_PREFIX=/home/agent/.npm-global` as an env-var fallback for systemd (systemd's EnvironmentFile= sees it); this makes the prefix resolvable even if `.npmrc` is bypassed.
**Warning signs:** A single mode (say, cron) shows a different prefix than the other five. Test failure diagnostic: `# RT-04 (cron): expected /home/agent/*, observed /usr`.

> **Decision point** (Claude's discretion per CONTEXT.md): belt-and-braces shipping of `NPM_CONFIG_PREFIX` in `/etc/agentlinux.env` is RECOMMENDED. Cost: one extra line in agentlinux.env. Benefit: a regression in npm's `$HOME` lookup doesn't take down the agent. The env var takes PRECEDENCE over `.npmrc` per npm precedence rules [CITED: docs.npmjs.com/cli/v10/configuring-npm/npmrc/], so both settings always agree (no split-brain).

### Pitfall 6: `DEBIAN_FRONTEND=noninteractive` missing — apt prompts on systemd config changes

**What goes wrong:** When `apt-get install nodejs` upgrades a system with a pre-existing `nodejs` package (say, Ubuntu 24.04's 18.x), dpkg may prompt interactively about `/etc/` conffile changes. This is fatal in CI (no TTY) and in the Docker harness (no interactive stdin).
**Why it happens:** dpkg's default behavior is to ask the user when a package's config file has been locally modified. The systemd-masking steps in our Dockerfile do NOT modify `nodejs` conffiles, so this is mostly theoretical for Phase 3 — but it's a classic bug that shows up exactly once in CI after a months-stable local dev setup.
**How to avoid:** Always wrap apt calls with `DEBIAN_FRONTEND=noninteractive` AND `--no-install-recommends`. The existing installer-wide pattern (see `10-agent-user.sh:43`) should be copied verbatim into `30-nodejs.sh`.
**Warning signs:** CI hangs indefinitely; `apt-get install` doesn't print its usual output; `docker exec` times out at 15 minutes (our workflow timeout).

### Pitfall 7: NodeSource script stdout includes ANSI color codes — pollutes our log

**What goes wrong:** The NodeSource `setup_22.x` script emits ANSI escape codes for its `log()` function (verified by direct fetch: lines 6-12). Our installer tees stdout+stderr to `/var/log/agentlinux-install.log`, so those escape codes land in the file. INST-05's `grep -E 'EACCES|permission denied'` is not affected (those strings don't appear in either format), but human log review is harder.
**Why it happens:** NodeSource authors wrote log functions that emit colors unconditionally, not gated on `-t 1` like our `log.sh`.
**How to avoid:** Option A (recommended): accept the pollution. INST-05 grep is ANSI-agnostic (the byte strings `EACCES` / `permission denied` appear verbatim if they fire). Option B: pipe `setup_22.x` through `sed 's/\x1b\[[0-9;]*m//g'` — but this adds complexity and a brittle sed regex. Option C: filter at log-read time (grep-with-stripping) — but every consumer must remember.
**Warning signs:** `less -R /var/log/agentlinux-install.log` shows colors; plain `cat` shows `^[[38;5;79m` escape sequences. Not a correctness issue; only cosmetic.

> **Recommendation:** Accept Option A. INST-05 is unaffected; human review uses `less -R` anyway.

### Pitfall 8: `npm uninstall -g <pkg>` leaves orphaned symlinks (especially from `npm link`)

**What goes wrong:** For packages installed via `npm install -g` (our case), npm's uninstall is mostly clean: it removes `{prefix}/lib/node_modules/<pkg>/` AND the symlinks in `{prefix}/bin/`. However, for packages installed via `npm link` (common in dev workflows) or packages that registered a `postinstall` script that created external symlinks, orphans can remain.
**Why it happens:** npm tracks installations in `{prefix}/lib/node_modules/<pkg>/package.json` + a symlink layout. `uninstall -g` removes those but doesn't traverse the filesystem for other references.
**How to avoid:** RT-03's strong assertion is byte-clean filesystem — assert the three expected paths (`bin/cowsay`, `bin/cowthink`, `lib/node_modules/cowsay/`) are gone. For a future AGT-02 (Claude Code self-update), a follow-up `npm cache clean --force` may be needed — but for cowsay's simple case, uninstall is complete.
**Warning signs:** `ls -la /home/agent/.npm-global/bin/` shows a broken symlink with red color (in ls --color) → the symlink target doesn't exist. Also: `command -v cowsay` succeeds (resolves the symlink) but `cowsay hi` fails (target script gone). [CITED: docs.npmjs.com/cli/v11/commands/npm-uninstall + discussion of `npm link` cleanup gaps]

### Pitfall 9: `cowsay`'s install creates TWO bin entries, not one

**What goes wrong:** The `cowsay@1.6.0` package.json declares `"bin": {"cowsay":"cli.js","cowthink":"cli.js"}`. Both `/home/agent/.npm-global/bin/cowsay` AND `/home/agent/.npm-global/bin/cowthink` get created. If RT-03 only asserts `cowsay` is removed, `cowthink` leftover goes undetected.
**Why it happens:** Two-bin packages are common (classic Unix `tar` vs `bsdtar` style). npm's uninstall DOES remove both — it reads package.json — but a test that only checks `cowsay` misses a potential regression.
**How to avoid:** RT-03's byte-clean assertion checks BOTH `/home/agent/.npm-global/bin/cowsay` AND `/home/agent/.npm-global/bin/cowthink` AND `/home/agent/.npm-global/lib/node_modules/cowsay/`. [VERIFIED: registry.npmjs.org/cowsay/latest 2026-04-18 — bin entries for both]
**Warning signs:** Phase 3 test passes but a subsequent `ls -la /home/agent/.npm-global/bin/` shows a stale `cowthink` binary; `apt` install test seems "unstuck" across reruns but actually accumulates residue.

## Code Examples

### Example 1: `plugin/provisioner/30-nodejs.sh` — complete skeleton (~80 LOC)

```bash
#!/usr/bin/env bash
# plugin/provisioner/30-nodejs.sh — Node.js 22 LTS + per-user npm prefix.
#
# Sourced by plugin/bin/agentlinux-install between 10-agent-user.sh and
# 40-path-wiring.sh (numeric dispatch order). Inherits `set -euo pipefail`,
# the ERR trap, and the tee redirect from the entrypoint — this fragment
# therefore MUST NOT set its own strict-mode flags.
#
# Requirements satisfied:
#   RT-01 — Node.js 22 LTS installed; `node --version` returns v22.x
#   RT-02 — npm install -g works without sudo/EACCES (prefix under home)
#   RT-03 — npm uninstall -g cleans up (no ensure_* needed here — behavioral)
#   RT-04 — `npm config get prefix` returns /home/agent/.npm-global
#
# Ordering rationale: runs AFTER 10-agent-user.sh (needs /home/agent to exist,
# owned by agent:agent). Runs BEFORE 40-path-wiring.sh (which prepends
# /home/agent/.npm-global/bin to PATH literals — the dir we create here).
#
# Every state mutation routes through plugin/lib/idempotency.sh primitives
# (ensure_dir / ensure_line_in_file). No raw useradd, no blind echo >>, no
# sed -i. Re-runs MUST converge (INST-02).

log_info "30-nodejs: starting"

# Step 1: pre-reqs for NodeSource's setup_22.x script. The script itself
# installs these at line 51 of its source (verified 2026-04-18), but we
# pre-install for log visibility + to keep the NodeSource apt transaction
# shorter. DEBIAN_FRONTEND=noninteractive prevents dpkg from prompting on
# any conffile change (Pitfall 6).
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  curl gnupg ca-certificates apt-transport-https

# Step 2: idempotent NodeSource repo add.
#
# Gate checks the NEW deb822 filename (`nodesource.sources`) AND the legacy
# (`nodesource.list`) so a re-run on a partially-migrated host still
# short-circuits. The NodeSource script itself rm -fs both on each run, so
# if our gate misses (e.g., stale `nodesource.list`), the script self-heals
# on first invocation — but our gate prevents the wasted invocation.
# Pitfall 1.
if [[ -f /etc/apt/sources.list.d/nodesource.sources ]] || \
   [[ -f /etc/apt/sources.list.d/nodesource.list ]]; then
  log_info "NodeSource apt repo already configured (gate: *.sources/*.list)"
else
  log_info "NodeSource apt repo absent — running setup_22.x"
  # curl-pipe-bash is acceptable here per installer SKILL §6 ("curl-pipe-bash
  # is acceptable at the outermost entrypoint OR for a pinned-URL trusted
  # upstream"). NodeSource is the ADR-005-blessed upstream. The script is
  # not sha256-verified by us — accepted trade-off per ADR-005.
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
fi

# Step 3: install nodejs. Idempotent — apt-get install is a no-op if the
# installed version satisfies the apt-pinning policy (Priority 600, set by
# setup_22.x in /etc/apt/preferences.d/nodejs).
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs

# Step 4: post-install verify (RT-01). Hard-fail if major < 22 — means the
# pinning broke or someone installed ubuntu's built-in nodejs first.
node_major=$(node --version 2>/dev/null | sed 's/^v\([0-9]*\)\..*$/\1/')
if [[ "${node_major:-0}" -lt 22 ]]; then
  log_error "node v${node_major:-unset} installed but v22 LTS required (RT-01)"
  return 1
fi
log_info "Node.js $(node --version) installed (RT-01 — v22 LTS)"

# Step 5: per-user npm prefix layout (RT-04).
# ensure_dir creates OR asserts mode+ownership — corrects out-of-band drift.
# The bin/ and lib/ subdirs are created proactively so `npm install -g`
# never has to create them (defense against Pitfall 3's root-owned-dir
# race, though our current flow never invokes npm as root).
ensure_dir /home/agent/.npm-global 0755 agent:agent
ensure_dir /home/agent/.npm-global/bin 0755 agent:agent
ensure_dir /home/agent/.npm-global/lib 0755 agent:agent

# Step 6: write ~agent/.npmrc with the prefix line (RT-04).
# Atomic create-if-absent, then idempotent grep-before-append.
# ensure_marker_block is overkill for one line; ensure_line_in_file is the
# right primitive.
if [[ ! -f /home/agent/.npmrc ]]; then
  install -m 0644 -o agent -g agent /dev/null /home/agent/.npmrc
fi
ensure_line_in_file 'prefix=/home/agent/.npm-global' /home/agent/.npmrc
# ensure_line_in_file doesn't chown (it was called in root context with an
# agent-owned file). Re-assert agent:agent ownership so subsequent agent
# edits aren't denied. Mode 0644 explicit — .npmrc has no secrets.
chown agent:agent /home/agent/.npmrc
chmod 0644 /home/agent/.npmrc
log_info "wrote ~agent/.npmrc (prefix=/home/agent/.npm-global — RT-04)"

log_info "30-nodejs: done"
```

### Example 2: `40-path-wiring.sh` delta (three artefacts extended)

```diff
 # In the heredoc for /etc/profile.d/agentlinux.sh:
-# Prepend /home/agent/.local/bin to PATH if not already present.
-# Phase 3 will extend this case with $HOME/.npm-global/bin.
+# Prepend in order (npm-global before .local so it wins):
+case ":${PATH}:" in
+  *:/home/agent/.npm-global/bin:*) : ;;
+  *) PATH="/home/agent/.npm-global/bin:${PATH}" ;;
+esac
 case ":${PATH}:" in
   *:/home/agent/.local/bin:*) : ;;
   *) PATH="/home/agent/.local/bin:${PATH}" ;;
 esac
 export PATH

 # In the heredoc for /etc/agentlinux.env:
-PATH=/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin
+PATH=/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin
+# NPM_CONFIG_PREFIX as belt-and-braces fallback (Pitfall 5 mitigation).
+# File-based ~agent/.npmrc is primary; env var ensures systemd sees the
+# prefix even if .npmrc read fails for any reason.
+NPM_CONFIG_PREFIX=/home/agent/.npm-global
 LANG=C.UTF-8
 LC_ALL=C.UTF-8

 # In the heredoc for /etc/cron.d/agentlinux:
-PATH=/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin
+PATH=/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin
 LANG=C.UTF-8
 LC_ALL=C.UTF-8
```

> `.bashrc` marker block unchanged — it sources profile.d, which now has the npm-global prepend. One-file-source-many pattern avoided when possible, but here it keeps the PATH logic in ONE place.

### Example 3: `tests/bats/30-runtime.bats` — full shape (~120 LOC)

```bash
#!/usr/bin/env bats
# tests/bats/30-runtime.bats — Phase 3 runtime + per-user npm prefix behavior.
#
# Covers: RT-01 (Node LTS), RT-02 (install -g unprivileged), RT-03 (uninstall
# clean), RT-04 (prefix under home). All six invocation modes via the
# tests/bats/helpers/invoke_modes.bash helpers shipped in Phase 2.
#
# Refs: 03-RESEARCH.md §Architecture §Pattern 3 + §Pattern 4.

load 'helpers/invoke_modes'
load 'helpers/assertions'

setup_file() {
  # Install cowsay once as agent user (keystone rule: as_user, not sudo -u).
  # sudo -u agent -H bash --login -c to trigger the known-working PATH path
  # (see Phase 2 02-05-SUMMARY Deviations §1 — non-login bash -c is broken
  # under sudoers secure_path; --login triggers profile.d which prepends
  # /home/agent/.npm-global/bin per Phase 3's 40-path-wiring extension).
  sudo -u agent -H bash --login -c 'npm install -g cowsay@1.6.0' 2>&1
}

teardown_file() {
  # Best-effort uninstall so a re-run of the bats suite doesn't see stale
  # state. Ignore exit code — the suite may have already uninstalled as
  # part of RT-03.
  sudo -u agent -H bash --login -c 'npm uninstall -g cowsay' 2>&1 || true
}

@test "RT-01: agent user sees node v22 LTS in every invocation mode" {
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'node --version'
    # SKIP handling for systemd if dbus is down (Pitfall 3 pattern from 02-05)
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "systemd unavailable in this environment"
    fi
    assert_exit_zero "RT-01 (${mode})"
    # Strong assertion: observed version STARTS WITH v22.
    if ! printf '%s' "${output:-}" | grep -Eq '^v22\.'; then
      __fail "RT-01 (${mode})" \
        "node --version starts with v22." \
        "${output:-<empty>}" \
        "/var/log/agentlinux-install.log"
    fi
  done
}

@test "RT-04: npm config get prefix is under /home/agent in every invocation mode" {
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'npm config get prefix'
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "systemd unavailable in this environment"
    fi
    assert_exit_zero "RT-04 (${mode})"
    assert_user_prefix_in_home "RT-04 (${mode})"
  done
}

@test "RT-02: cowsay binary resolves to /home/agent/.npm-global/bin in every mode" {
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'command -v cowsay'
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "systemd unavailable in this environment"
    fi
    assert_exit_zero "RT-02 (${mode})"
    assert_path_has "RT-02 (${mode})" "/home/agent/.npm-global/bin/cowsay"
    # Second strong assertion: binary RUNS successfully.
    invoke_mode "$mode" 'cowsay hi'
    assert_exit_zero "RT-02 (${mode})"
    assert_path_has "RT-02 (${mode})" "hi"  # cowsay echoes the text
  done
}

@test "RT-02: no EACCES or permission denied during cowsay install" {
  # Replayable: the setup_file install already ran, but we re-verify by
  # running a second install that's a no-op with an explicit check.
  run sudo -u agent -H bash --login -c 'npm install -g cowsay@1.6.0 2>&1'
  assert_exit_zero "RT-02 (no-eacces re-install)"
  assert_no_eacces "RT-02" "$output"
}

@test "RT-03: npm uninstall -g cowsay leaves no trace in every invocation mode" {
  # Uninstall once.
  run sudo -u agent -H bash --login -c 'npm uninstall -g cowsay 2>&1'
  assert_exit_zero "RT-03 (uninstall)"
  assert_no_eacces "RT-03" "$output"

  # Byte-clean filesystem — strongest form of the contract.
  for target in /home/agent/.npm-global/bin/cowsay \
                /home/agent/.npm-global/bin/cowthink \
                /home/agent/.npm-global/lib/node_modules/cowsay; do
    if [[ -e $target ]]; then
      __fail "RT-03 (filesystem)" \
        "no trace of cowsay" \
        "observed: ${target} still exists" \
        "/var/log/agentlinux-install.log"
    fi
  done

  # Not-on-PATH assertion — every mode.
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'command -v cowsay || echo NOT-FOUND'
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "systemd unavailable in this environment"
    fi
    if printf '%s' "${output:-}" | grep -q '/cowsay'; then
      __fail "RT-03 (${mode})" \
        "cowsay NOT findable on PATH" \
        "found: ${output}" \
        "/var/log/agentlinux-install.log"
    fi
  done

  # Re-install so subsequent tests in the file (if any run later) have
  # the cowsay still installed. Not required for the gate — just hygiene.
  sudo -u agent -H bash --login -c 'npm install -g cowsay@1.6.0' >/dev/null 2>&1 || true
}
```

### Example 4: `tests/bats/helpers/assertions.bash` — append block

```bash
# ---------------------------------------------------------------------------
# Appended in Phase 3 (Plan 03-02 or equivalent).
#
# RT-04 gate. Input is `$output` populated by a prior `run` or `invoke_mode`
# that executed `npm config get prefix`. Passes if the prefix starts with
# /home/agent/ (note the trailing slash — prevents matching a hypothetical
# /home/agent-staging/... path). Fails everything else with a TST-04
# diagnostic naming the expected vs observed prefix.
#
# Usage:
#   run_interactive 'npm config get prefix'
#   assert_user_prefix_in_home "RT-04 (interactive)"
# ---------------------------------------------------------------------------
assert_user_prefix_in_home() {
  local req_id=$1
  local observed
  observed=$(printf '%s' "${output:-}" | tr -d '[:space:]')

  case "$observed" in
    /home/agent/*)
      return 0
      ;;
    *)
      __fail "$req_id" \
        "npm config get prefix under /home/agent/" \
        "observed: ${observed:-<empty>}" \
        "~agent/.npmrc (expected: prefix=/home/agent/.npm-global)"
      ;;
  esac
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `apt-key add` + `/etc/apt/sources.list.d/nodesource.list` | `gpg --dearmor` + `/etc/apt/keyrings/*.gpg` (or `/usr/share/keyrings/*.gpg`) + `signed-by=` in sources.list entry; NodeSource now uses **deb822** sources format in `/etc/apt/sources.list.d/nodesource.sources` | Debian/Ubuntu began apt-key deprecation in 2022; NodeSource rewrote setup_*.x scripts for signed-by in 2023 | The CONTEXT-locked filename (`nodesource.list`) is stale. Use `nodesource.sources` as the primary gate. |
| `npm config set prefix` run as root to set system-wide npm prefix | Per-user `.npmrc` (at `~user/.npmrc`) | Debatable — was always wrong, but became clearly-wrong when npm 5+ tightened prefix resolution | The per-user mechanism is the keystone ADR-004. |
| `sudo npm install -g` with root-owned `/usr/lib/node_modules/` | `as_user agent npm install -g` with agent-owned `/home/agent/.npm-global/` | ADR-004 decision date 2026-04-18 | The `sudo npm install -g` form is NEVER correct for this project. |
| Node 22 Active LTS | Node 22 Maintenance LTS (since 2025-10-21) | Transition 2025-10-21 | Maintenance LTS means security-fix-only — still a pinnable LTS until 2027-04-30, so Phase 3's pin is good for ~1 year. Bumping to Node 24 LTS (Active from 2025-10-28) is a v0.4+ decision per CONTEXT deferrals. |

**Deprecated/outdated:**
- **`apt-key`**: deprecated in Debian Bullseye; removed or heavily restricted in Ubuntu 24.04+. [CITED: wiki.debian.org/DebianRepository/UseThirdParty + digitalocean.com/community/tutorials/how-to-handle-apt-key-and-add-apt-repository-deprecation]
- **nvm/fnm/volta shell hooks as agent runtime strategy**: rejected by ADR-005. Referenced here only to explicitly mark the deprecated-for-our-use-case status.
- **`apt-get` top-level command**: still works but `apt` is the modern sugar. We use `apt-get` everywhere for CI-stable non-interactive output (apt itself warns "apt has no stable CLI interface").

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Node 22 maintenance LTS EOL is 2027-04-30 | Standard Stack, State of the Art | Moderate. Verified against github.com/nodejs/Release schedule; dates are published and stable. If wrong by a month, Phase 3's pin still holds through v0.3.0 release. |
| A2 | NodeSource's `setup_22.x` will remain at `https://deb.nodesource.com/setup_22.x` and keep the same general shape through 2027 | Standard Stack, Code Examples §Example 1 | Moderate. NodeSource has served this URL for every major since Node 8. Dependency risk: if they pivot to a new URL format, our provisioner breaks — but so do thousands of other deployments, so there would be upstream notice. |
| A3 | cowsay@1.6.0 will remain available on the public npm registry for v0.3.0's lifetime | Standard Stack, Test Coverage | Low. cowsay is last-modified 2024; ~10K weekly downloads; publisher `piuccio` is the long-term maintainer. Fallback (`is-ci`) is documented if cowsay becomes flaky. |
| A4 | `ensure_line_in_file 'prefix=/home/agent/.npm-global' /home/agent/.npmrc` is the correct idiom for writing npm's prefix | Architecture Patterns §Pattern 2, Code Examples §Example 1 | Low. Phase 2 primitives are tested; no new behavior. But: if a future npm version requires a different `.npmrc` syntax (like YAML, like pnpm's yaml migration), this breaks. |
| A5 | `/home/agent/.npm-global/bin/cowsay` resolves via `command -v cowsay` in all six modes after Phase 3's PATH extension in 40-path-wiring.sh | Pattern 2 + 3 | Low-moderate. Depends on the PATH-wiring extension landing correctly. The acceptance criterion for the Phase 3 plan MUST include a grep of the three PATH-carrying artefacts for the literal string `/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin` (exact prefix-first ordering). |
| A6 | npm 10 (bundled with Node 22) reads `$HOME/.npmrc` in cron + systemd as long as `HOME` is set | Pitfalls §3 + §5 | Low. Verified against npm docs. `as_user -H` forces HOME; systemd test passes `--setenv=HOME=/home/agent`. But there's a historical bug class here where older npms derived user config path from passwd instead of HOME — modern npm is consistent but a regression is possible. Pitfall 5's belt-and-braces `NPM_CONFIG_PREFIX` mitigates. |
| A7 | Pre-installing `curl gnupg ca-certificates` via apt is not an issue on Ubuntu 22.04/24.04 (both provide these or they're trivially installable from universe/main) | Environment Availability | Low. Verified via direct inspection — ubuntu:22.04 and ubuntu:24.04 both have all three in their default package sources. Our Dockerfiles ship `ca-certificates`; `curl` + `gnupg` are one apt call away. |
| A8 | The BHV-05 deviation from Phase 2 (non-login `bash -c` broken under sudoers secure_path) does NOT affect RT-02 because the Phase 3 tests use `bash --login -c` in `run_sudo_u` | Example 3 setup_file + Pattern 3 | Low. The `run_sudo_u` helper is shared between Phase 2 and Phase 3 suites. If Phase 3 needed to test the `bash -c` non-login path, it would hit the same wall — but RT-02's contract (observable behavior: binary findable on PATH in BHV-05) is satisfied by the two variants already shipped (bash --login + -i). |
| A9 | `nodejs` apt package installs `/usr/bin/node`, `/usr/bin/npm`, `/usr/bin/npx`, all on the system PATH wired in Phase 2 | RT-01 coverage | Low. Standard for NodeSource + Ubuntu. Phase 2's PATH artefacts include `/usr/bin` in the literal PATH string. Verified against apt-cache policy on the install target. |
| A10 | `apt-get install -y nodejs` after a pre-existing installation of a different version (e.g., Ubuntu's built-in 18.x from a dirty host) correctly upgrades to NodeSource 22.x because pin-priority 600 > default 500 | Pattern 1, Pitfall 6 | Low-moderate. Per NodeSource's preferences.d/nodejs file (Pin-Priority: 600), their package wins over Ubuntu's default 500. But a pre-existing nodejs at 18.x might have conffiles that dpkg prompts about. DEBIAN_FRONTEND=noninteractive + --no-install-recommends mitigates. If this fails in real CI, the plan may need `apt-get purge -y nodejs` as a clean-slate step — deferred to Plan 03 execution. |

## Open Questions

1. **Should `cowsay` be pinned to `@1.6.0` or floating?**
   - What we know: current cowsay is 1.6.0, stable for 2+ years, 4 deps, all stable.
   - What's unclear: policy — does Phase 3 set precedent for future "smoke package" tests to pin?
   - Recommendation: **pin `@1.6.0`** for reproducibility. Any upstream cowsay rewrite (unlikely) could change bin layout and break our RT-03 byte-clean assertion. Pin cost is negligible (4-char addition to test string). Future agents installed as real CAT entries do NOT pin — that's a Phase 5 concern.

2. **Should 30-nodejs.sh pre-install `curl`/`gnupg` or let NodeSource's setup_22.x install them?**
   - What we know: setup_22.x installs them itself (line 51 of the script). Our Dockerfiles have `ca-certificates` but NOT `curl` or `gnupg`.
   - What's unclear: minor style preference. Pre-installing makes the installer log show the pre-req install explicitly. Letting NodeSource install them keeps the provisioner shorter.
   - Recommendation: **pre-install via apt in 30-nodejs.sh**. Reasoning: (a) the line appears in OUR log (greppable), (b) subsequent re-runs of 30-nodejs.sh are no-ops for apt, (c) future phases may need `curl` or `gnupg` for other reasons and Phase 3 is the logical place for them to land. Cost: one extra line in 30-nodejs.sh. Add `curl gnupg` to Dockerfiles as well so Docker-layer caching helps (optional optimization).

3. **Does `/etc/agentlinux.env` need `NPM_CONFIG_PREFIX` in addition to `PATH`?**
   - What we know: npm precedence is env > user .npmrc > global > builtin. `~agent/.npmrc` alone suffices in all six modes we tested conceptually.
   - What's unclear: whether a future npm regression (or a future HOME-unset edge case) could make `.npmrc` invisible, which would cause npm to fall back to builtin (`/usr`).
   - Recommendation: **YES, belt-and-braces ship `NPM_CONFIG_PREFIX=/home/agent/.npm-global` in /etc/agentlinux.env**. Cost: one line. Benefit: any `.npmrc`-bypass bug in systemd (or future env) still lands the right prefix. Env var takes precedence over file, so both sources always agree — no split-brain risk. See Pitfall 5 mitigation.

4. **Should Phase 3 test for `node --version` specifically being ≥ 22.22 (current patch) or just ≥ 22 (major)?**
   - What we know: current patch v22.22.2 as of 2026-04-18.
   - What's unclear: test strictness — a too-strict test breaks on a minor upgrade.
   - Recommendation: **test MAJOR ≥ 22 only**. The test `grep -Eq '^v22\.'` catches both "wrong major" and "garbage output" cases without needing patch-level care. NodeSource may bump to 22.22.3 next week; the test should not care.

5. **Should Phase 3 add smoke-install a SECOND package to prove multi-package integrity?**
   - What we know: only cowsay is in scope per CONTEXT.
   - What's unclear: whether one package covers the "install multiple, uninstall one, leave the other" test.
   - Recommendation: **NO for v0.3.0 Phase 3**. CONTEXT locks cowsay as THE smoke; a second package is test-complexity creep. Phase 5's real agent installs (claude-code, gsd, playwright) will exercise multi-package integrity implicitly.

## Environment Availability

| Dependency | Required By | Available (Docker 22.04) | Available (Docker 24.04) | Version | Fallback |
|------------|------------|--------------------------|--------------------------|---------|----------|
| apt + apt-get | install | ✓ (ubuntu base) | ✓ (ubuntu base) | — | — |
| ca-certificates | NodeSource script TLS fetch | ✓ (in Dockerfile) | ✓ (in Dockerfile) | — | — |
| curl | NodeSource script install | ✗ (NOT in Dockerfile) | ✗ (NOT in Dockerfile) | — | apt-get install inside 30-nodejs.sh |
| gnupg | NodeSource script `gpg --dearmor` | ✗ (NOT in Dockerfile) | ✗ (NOT in Dockerfile) | — | apt-get install inside 30-nodejs.sh |
| apt-transport-https | NodeSource deb over https | ✗ (NOT in Dockerfile) | ✗ (NOT in Dockerfile) | — | apt-get install inside 30-nodejs.sh (NodeSource script installs it too) |
| Node 22 LTS | RT-01 | ✗ (NodeSource repo not added) | ✗ (NodeSource repo not added) | will be v22.x post-install | `30-nodejs.sh` installs it |
| npm 10.x | RT-02..04 | bundled with nodejs | bundled with nodejs | 10.x | — |
| cowsay (public npm registry) | RT-02..04 | available via registry.npmjs.org | available via registry.npmjs.org | 1.6.0 | `is-ci` as substitute if cowsay registry flakes |
| sudo | `as_user` + test helpers | ✓ (in Dockerfile) | ✓ (in Dockerfile) | — | — |
| systemd + dbus | BHV-04 integration | ✓ (in Dockerfile) | ✓ (in Dockerfile) | — | test `skip` via SKIP_SYSTEMD_UNAVAILABLE sentinel |
| cron + openssh | BHV-02/03 integration | ✓ (in Dockerfile) | ✓ (in Dockerfile) | — | — |
| bats-core | test runner | ✓ (apt-installed in Dockerfile) | ✓ (apt-installed in Dockerfile) | ≥1.8.2 | — |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:**
- **`curl` + `gnupg`** — Phase 3's `30-nodejs.sh` installs them via apt BEFORE invoking NodeSource. Setup_22.x itself also installs them (belt-and-braces). The Dockerfile is NOT strictly required to pre-install them, but doing so enables Docker layer-caching to skip the apt install in subsequent container boots — recommended optimization (see Open Questions §2).

**Dockerfile delta (OPTIONAL but RECOMMENDED):** add `curl gnupg` to both Dockerfiles' apt-get install lines:
```diff
       bats locales sudo \
-      dbus \
-      ca-certificates bash coreutils util-linux \
+      dbus \
+      ca-certificates bash coreutils util-linux curl gnupg \
       shellcheck && \
```
Saves ~5 seconds per Docker invocation across Phase 3+ test runs. Cost: ~4 MB image size. Not blocking for Phase 3 — can be deferred to a later optimization plan.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bats-core, apt-installed inside Docker images (≥1.8.2) |
| Config file | none — bats auto-discovers `tests/bats/*.bats`. Shared helpers in `tests/bats/helpers/` are `load`ed explicitly by each .bats file. |
| Quick run command | `bash tests/docker/run.sh ubuntu-24.04` — full installer + full bats suite; ~45s on 24.04, ~60s on 22.04 |
| Full suite command | `.github/workflows/test.yml` bats-docker job — matrix of ubuntu-22.04 + ubuntu-24.04, fail-fast=false, timeout-minutes=15 |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RT-01 | `node --version` returns LTS version in every invocation mode | integration (six-mode bats) | `bash tests/docker/run.sh ubuntu-24.04` → `tests/bats/30-runtime.bats::@test RT-01` | ❌ Wave 0 / Wave 1 (NEW file) |
| RT-02 | `npm install -g cowsay` works (as agent user) without sudo/EACCES; binary findable in every mode | integration (six-mode bats + install step) | `bash tests/docker/run.sh ubuntu-24.04` → `tests/bats/30-runtime.bats::@test RT-02` (2 @tests: install + resolution; no-eacces re-install) | ❌ Wave 0 / Wave 1 (NEW file) |
| RT-03 | `npm uninstall -g cowsay` leaves no trace (binary gone + lib dir gone) in every mode | integration (six-mode bats + filesystem assertion) | `bash tests/docker/run.sh ubuntu-24.04` → `tests/bats/30-runtime.bats::@test RT-03` | ❌ Wave 0 / Wave 1 (NEW file) |
| RT-04 | `npm config get prefix` under `/home/agent/` in every mode | integration (six-mode bats + `assert_user_prefix_in_home` helper) | `bash tests/docker/run.sh ubuntu-24.04` → `tests/bats/30-runtime.bats::@test RT-04` | ❌ Wave 0 / Wave 1 (NEW file) |
| Smoke: no EACCES across Phase 3 installer run | (regression for INST-05) | integration | `assert_no_eacces` in RT-02 test + existing `tests/bats/10-installer.bats::@test INST-05` (unchanged) | ✓ (shipped Phase 2) |
| Smoke: re-run of full installer is byte-stable INCLUDING Phase 3 artefacts | (regression for INST-02) | integration | `tests/bats/10-installer.bats::@test INST-02` (EXTENDED: add `~agent/.npmrc` to the sha256 diff set) | ⚠️ Wave 2 (EDIT Phase 2 test) |

### Sampling Rate

- **Per task commit:** `bash tests/docker/run.sh ubuntu-24.04` (~45s) — fast-path for inner dev loop
- **Per wave merge:** both matrix entries (22.04 + 24.04) — full workflow run
- **Phase gate:** Both matrix entries green, TST-07 gate (every RT-01..04 has ID-prefixed @test) GREEN via behavior-coverage-auditor subagent

### Wave 0 Gaps

- [ ] `tests/bats/30-runtime.bats` — NEW file; covers RT-01..04 via six-mode loops
- [ ] `tests/bats/helpers/assertions.bash` APPEND — new helper `assert_user_prefix_in_home` (RT-04)
- [ ] `tests/bats/10-installer.bats` EDIT — extend INST-02's sha256 diff artefact list to include `/home/agent/.npmrc` (byte-stability of the new Phase 3 file)
- [ ] Framework install — already installed in Dockerfiles (bats + locales + sudo + dbus + openssh + cron). Phase 3 adds NO new apt deps to the Dockerfile beyond the optional `curl`/`gnupg` optimization noted in Environment Availability.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V1 Architecture | yes | Agent-owned prefix keystone (ADR-004); observable behavior contract (ADR-002) |
| V2 Authentication | no | No auth surface in Phase 3 — NodeSource's apt repo is authenticated via `signed-by=` GPG in the deb822 sources entry; downstream npm registry is public-read |
| V3 Session Management | no | No sessions |
| V4 Access Control | yes | File ownership invariants: /home/agent/.npm-global must be agent-owned; `/usr/bin/node` is root-owned (normal for system package); no `/etc/sudoers.d/*` drop-in in Phase 3 |
| V5 Input Validation | partial | Provisioner input is shell args from entrypoint (no user-controlled); arg-count guards shipped in Phase 2 primitives; NodeSource script is pipe-consumed — a malicious upstream could inject arbitrary commands (accepted risk per ADR-005) |
| V6 Cryptography | partial | GPG-signed apt repo via NodeSource (sha256 + signature via debian apt layer); npm tarball integrity via npm's built-in sha512 check on download; no hand-rolled crypto |
| V7 Error Handling | yes | `on_error` ERR trap from entrypoint catches every failure in 30-nodejs.sh; no silent `|| true` except on the one documented skip in 10-agent-user.sh (not in 30-nodejs.sh) |
| V10 Malicious Code | partial | Trust relationships: NodeSource apt repo (ADR-005 trusted), npm registry (cowsay from registry.npmjs.org, integrity-verified by npm itself). No mitigations against compromised-upstream attacks beyond Ubuntu's apt layer trust. |
| V14 Configuration | yes | `~agent/.npmrc` has no secrets; `/etc/agentlinux.env` has no secrets; no credentials written anywhere |

### Known Threat Patterns for Phase 3

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Curl-pipe-bash of NodeSource's setup_22.x (T-03-01) | Tampering (supply chain) | Accepted risk per ADR-005 + ADR-006. The script itself is GPG-published and HTTPS-fetched; the resulting apt repo is signed via `signed-by=` keyring. Long-term v0.4+ mitigation: sha256-pin the setup_22.x script itself. |
| Root running `npm install -g` during installer (T-03-02) | EoP | Every `npm` invocation in 30-nodejs.sh is through `as_user agent npm ...` or `as_user_login agent npm ...`. The installer itself runs no npm globals. Pitfall 2. |
| `~agent/.npmrc` written root-owned leaks into agent's env (T-03-03) | Tampering | Post-write `chown agent:agent /home/agent/.npmrc` + `chmod 0644`. `.npmrc` has no secrets. |
| PATH injection: `/usr/local/bin` earlier than `/home/agent/.npm-global/bin` (T-03-04) | EoP | PATH order locked: agent-owned first, system second. Verified by acceptance-grep of the three PATH-carrying artefacts. Pitfall 4. |
| Uninstall leaves orphaned files that persist across installs (T-03-05) | Tampering (leftover state) | RT-03's byte-clean assertion across three known paths. See Pitfall 8. |
| Cowsay `postinstall` script could run arbitrary code as agent (T-03-06) | Malicious code | Accepted risk: cowsay is a stable 4-year-old package from a known maintainer. Phase 3 runs npm as agent (not root), so the blast radius is bounded to agent's home. Defense-in-depth: future AGT tests would isolate with `npm ci --ignore-scripts` where possible. |
| `NODE_MAJOR` env var leak into parent shell (T-03-07) | Info disclosure | 30-nodejs.sh never sets NODE_MAJOR (uses literal `setup_22.x`). No env leak. |

## Sources

### Primary (HIGH confidence)

- **NodeSource `setup_22.x` script** — direct fetch of `https://deb.nodesource.com/setup_22.x` on 2026-04-18. 121-line bash script; full content captured. Cornerstone for Pattern 1 + Pitfall 1. [VERIFIED]
- **npm registry `/cowsay/latest`** — direct fetch of `https://registry.npmjs.org/cowsay/latest` on 2026-04-18. Current version 1.6.0, confirmed 2-bin entry (`cowsay` + `cowthink`), 4 deps, unpackedSize 495745. [VERIFIED]
- **nodejs/Release schedule** — github.com/nodejs/Release. Node 22 (Jod): Active LTS 2024-10-29, Maintenance 2025-10-21, EOL 2027-04-30. [VERIFIED]
- **Local source inspection** — `plugin/lib/*.sh`, `plugin/bin/agentlinux-install`, `plugin/provisioner/{10,40}*.sh`, `tests/bats/helpers/*.bash`, `tests/docker/Dockerfile.ubuntu-{22,24}.04`, `.planning/phases/02-*/02-VERIFICATION.md`, `.planning/REQUIREMENTS.md`, `.planning/STATE.md`. Line references throughout this document cite specific line numbers from these files. [VERIFIED on-machine read]

### Secondary (MEDIUM confidence)

- **docs.npmjs.com/cli/v10/configuring-npm/npmrc/** — npm config precedence order and `.npmrc` lookup semantics. [CITED]
- **docs.npmjs.com/cli/v10/configuring-npm/folders** — npm prefix and cache location defaults. [CITED]
- **docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally** — canonical npm-team doc for the exact EACCES bug class this project exists to eliminate. [CITED]
- **docs.npmjs.com/cli/v11/commands/npm-uninstall** — uninstall semantics and leftover-symlink discussion. [CITED]
- **github.com/npm/cli#4467** — `NPM_CONFIG_PREFIX` edge case with `--prefix` flag. [CITED]
- **wiki.debian.org/DebianRepository/UseThirdParty + digitalocean tutorial** — modern apt-key replacement patterns (`gpg --dearmor` + `signed-by=`). [CITED]
- **computingforgeeks + linuxize install guides for Ubuntu 24.04 + Node 22** — cross-verified the NodeSource invocation pattern used in Pattern 1. [CITED]

### Tertiary (LOW confidence)

- **NodeSource blog post "Resolved: GPG Signature Warnings on Debian 13 and Modern Ubuntu"** — referenced for Debian 13 SHA-1 blocking timeline; tangentially relevant but not load-bearing for Phase 3. [LOW — not verified end-to-end]
- **Medium + DigitalOcean community tutorials for NodeSource setup** — referenced as cross-validation of the signed-by pattern; some mention the LEGACY `nodesource.list` filename which misled CONTEXT.md. [LOW — each tutorial is a snapshot of its publication date]

## Metadata

**Confidence breakdown:**
- Standard stack (Node 22 / NodeSource / npm 10 / cowsay 1.6.0): **HIGH** — all versions + install mechanism verified by direct fetch.
- Architecture (four-file PATH extension, `.npmrc` prefix, six-mode round-trip): **HIGH** — reuses Phase 2's shipped-and-verified patterns; only new work is the prepend + cowsay test loop.
- Pitfalls (9 total): **HIGH** for Pitfalls 1-5 + 8-9 (verified via upstream docs + direct script fetch); **MEDIUM** for Pitfalls 6-7 (derived from general Debian/apt behavior; not independently reproduced but well-documented).
- Validation architecture + Security: **HIGH** — mechanical mapping from the RT-01..04 contract to bats test IDs + STRIDE threat model.

**Research date:** 2026-04-18
**Valid until:** 2026-10-18 (6 months — Node 22 remains in Maintenance LTS until 2027-04-30; NodeSource script shape is stable; npm 10 precedence rules are documented and versioned. Re-check before any release-gate hand-off if this window lapses.)

## RESEARCH COMPLETE

**Phase:** 3 - Node.js Runtime + Per-User npm Prefix
**Confidence:** HIGH

### Key Findings

1. **NodeSource `setup_22.x` (2026 form) writes `nodesource.sources` (deb822), NOT `nodesource.list`** — CONTEXT-locked gate filename is the legacy. Phase 3 idempotency guard checks both, prefers `.sources`. (Direct script fetch verified 2026-04-18.)
2. **Node 22 Jod is Maintenance LTS** (since 2025-10-21, EOL 2027-04-30); current v22.22.2. Phase 3 pin remains valid for ~1 year — ADR-005 decision unchanged.
3. **cowsay@1.6.0 ships TWO bin entries** (`cowsay` + `cowthink`), not one; RT-03 byte-clean assertion must check both plus the lib dir.
4. **Dockerfiles ship `ca-certificates` but NOT `curl`/`gnupg`** — Phase 3 provisioner installs them via apt; NodeSource's script also installs them (belt-and-braces).
5. **Phase 2's `40-path-wiring.sh` PATH artefacts do NOT yet include `/home/agent/.npm-global/bin`** — Phase 3 MUST prepend it to three of the four artefacts (profile.d case, agentlinux.env, cron.d). The `.bashrc` marker block sources profile.d and requires no change.
6. **BHV-05 non-login `bash -c` under sudoers secure_path is a known Phase 2 gap, deferred to v0.4+** — Phase 3's test loop uses `bash --login -c` via `run_sudo_u` (unchanged helper; no new deviation).
7. **`.npmrc` prefix in user home + `NPM_CONFIG_PREFIX` in /etc/agentlinux.env** is the belt-and-braces recommendation — both always agree (env wins in precedence); regression-proof against `.npmrc`-bypass edge cases.

### File Created

`/home/agent/agent-linux/.planning/phases/03-nodejs-runtime-per-user-npm-prefix/03-RESEARCH.md`

### Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Standard Stack | HIGH | All versions + install URL verified by direct fetch or registry API |
| Architecture | HIGH | Reuses verified Phase 2 primitives; only new surface is a file prepend + one new helper |
| Pitfalls | HIGH | 9 pitfalls, most traced to upstream docs + direct script inspection |
| Validation Architecture | HIGH | Mechanical mapping from RT-01..04 → bats @tests + existing six-mode helpers |
| Security | HIGH | STRIDE table + 9 ASVS categories mapped to concrete controls |

### Open Questions

1. cowsay pin `@1.6.0` vs floating — recommend pin for reproducibility
2. Pre-install curl/gnupg in 30-nodejs.sh vs. let NodeSource do it — recommend pre-install
3. Belt-and-braces `NPM_CONFIG_PREFIX` in `/etc/agentlinux.env` — recommend YES
4. `node --version` test strictness — recommend major-only (≥22)
5. Second smoke package for multi-install coverage — recommend NO (defer to Phase 5)

### Ready for Planning

Research complete. Planner can now create PLAN.md files. Recommended plan structure: 2 plans, 2 waves.
- **Plan 03-01 (Wave 1, provisioner)**: 30-nodejs.sh NEW (~80 LOC) + 40-path-wiring.sh MODIFIED (extend three PATH literals + add NPM_CONFIG_PREFIX). Review gate: bash-engineer + security-engineer + qa-engineer.
- **Plan 03-02 (Wave 2, tests)**: tests/bats/30-runtime.bats NEW (~120 LOC, 5 @tests) + tests/bats/helpers/assertions.bash APPEND (assert_user_prefix_in_home) + tests/bats/10-installer.bats INST-02 EDIT (add ~agent/.npmrc to sha256 artefact set) + optional Dockerfile curl/gnupg optimization. Review gate: qa-engineer + behavior-coverage-auditor + bash-engineer for helper. Phase close: TST-07 GREEN via behavior-coverage-auditor.
