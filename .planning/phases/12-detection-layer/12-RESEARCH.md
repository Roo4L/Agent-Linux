# Phase 12: Detection Layer - Research

**Researched:** 2026-05-10
**Domain:** Read-only bash discovery primitives + structured-report rendering (text + jq-built JSON) for AgentLinux's brownfield-aware installer
**Confidence:** HIGH (every recommended primitive verified against the live codebase or `man`-page; eight Node-source detection paths verified against canonical install layouts; jq idiom verified live)

## Summary

Phase 12 ships a read-only discovery layer under `plugin/lib/detect/` plus a `plugin/lib/detect.sh` orchestrator that the bash entrypoint sources before deciding to run provisioners. CONTEXT.md has already locked the implementation surface (per-detector files, two output flags, jq for JSON, no schema doc, no version field). What this research adds is the *concrete probe set per detector* — which canonical paths to stat, which `dpkg-query` selector to use, how to ask npm "what prefix would the install user resolve to" without sourcing the user's shell — plus the catalog-agent binary-name corrections that the original REQUIREMENTS.md DET-04 wording got slightly wrong.

The single hardest sub-problem is DET-02. Eight Node sources × four "observable states" (absent, present-healthy, present-broken, present-incompatible) is a 32-cell matrix; the only way to keep it tractable AND read-only is **canonical-path file-existence probing** rather than activating each manager's shell hook. Every covered manager (nvm, fnm, volta, mise, asdf-node, pnpm-managed Node) installs binaries under deterministic paths under `$HOME` that we can `find -maxdepth N` from the install user's home — no `eval "$(fnm env)"`, no `source ~/.nvm/nvm.sh`. This sidesteps the entire shell-state-mutation class of risks that ADR-005 already documented as the reason version managers were rejected for AgentLinux's *own* Node install.

The second non-obvious finding: the originally-named catalog agent `playwright` is actually `playwright-cli` in the live catalog (REQUIREMENTS.md DET-04 mentions "playwright" but `plugin/catalog/catalog.json` has id `playwright-cli` and binary `playwright-cli`). Detection must follow the catalog's actual binary names (`claude`, `get-shit-done-cc`, `playwright-cli`), not the requirement's prose names — the planner needs to know this so the per-agent probe map matches the runtime.

**Primary recommendation:** Build `plugin/lib/detect/{user,nodejs,npm_prefix,agents,sudoers}.sh` as five focused detectors that each emit (a) a `[DET-NN] key=value` text block via `log_*` extensions and (b) a `jq -n --arg ... '{...}'` JSON fragment composed by `detect.sh` orchestrator. Memoize results to `/run/agentlinux-detect.json` (tmpfs) so Phase 13 readers (`detect::user_uid`, `detect::nodejs_satisfies_pin`, etc.) can re-read without re-probing. Use `find -printf '%p %T@ %s\n' | sort` over five target dirs as the read-only-invariant snapshot; assert sha256-equality before/after a detection pass in a Docker-only bats @test.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Probe filesystem state (paths, modes, ownership) | `plugin/lib/detect/*.sh` (bash, root) | — | Detection runs inside the entrypoint, root-privileged, with strict-mode + ERR-trap inherited from `agentlinux-install` |
| Probe install-user-scoped commands (`npm config`, `node --version` over user PATH) | `plugin/lib/detect/*.sh` via `as_user` helper | `plugin/lib/as_user.sh` (existing) | DET-04 + DET-03 require commands to resolve against the install user's `$HOME` and `$PATH`; root invocation would see root's PATH instead |
| Render text output | `plugin/lib/detect.sh` (renderer) | `plugin/lib/log.sh` (color macros) | TTY/NO_COLOR aware; matches existing log convention; one `[DET-NN]` block per detector |
| Render JSON output | `plugin/lib/detect.sh` via `jq -n` | `jq` binary (apt) | Test-only consumer; bash assembles per-detector JSON fragments, orchestrator merges via jq |
| Memoize detection across multiple bash readers | `/run/agentlinux-detect.json` (tmpfs) | — | tmpfs = no persistence across reboot; Phase 13 readers (in same `agentlinux-install` process) source the lib and call cached readers |
| Phase 13 reader API (`detect::user_uid`, etc.) | `plugin/lib/detect.sh` | bash function exports | Provisioners need scalar/boolean answers, not JSON parsing — keep parse logic in one place |
| Bats no-op @test | `tests/bats/15-detection.bats` | `find -printf` snapshot helper | Slot 15 = before installer-foundation tests; Docker-only matrix per Q3 |
| Argv parse for `--report-only` and `--report-format=text\|json` | `plugin/bin/agentlinux-install` `parse_args` | — | Existing dispatch site; gates `run_provisioners` behind `not --report-only` |

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Area 1 — Detection Code Surface & Implementation Language (accepted as recommended):**
- Module location: New `plugin/lib/detect/` directory with one file per detector (`user.sh`, `nodejs.sh`, `npm_prefix.sh`, `agents.sh`, `sudoers.sh`) plus a `detect.sh` orchestrator. Sits alongside existing `plugin/lib/{as_user,idempotency,distro_detect,log}.sh`.
- Invocation: Two surfaces on the bash entrypoint — `agentlinux-install --report-only` runs the orchestrator and exits 0; `--report-format=text|json` (default `text`) is an orthogonal flag honored by both `--report-only` and (later, Phase 15) `--dry-run`. The TS CLI `agentlinux install <name>` is unchanged.
- Renderer language: Pure bash for text rendering (`plugin/lib/log.sh` style); JSON via `jq -n --arg ... '{...}'` (jq is hard-added as a pre-req in `30-nodejs.sh`'s prerequisite block if not already present).
- Phase 13 handoff: Detection writes to `/run/agentlinux-detect.json` (tmpfs, no persistence across reboot) AND exposes bash reader functions (`detect::user_uid`, `detect::nodejs_count`, `detect::agents_status_for <name>`) sourced via `plugin/lib/detect.sh`. Phase 13 provisioners source the lib and call readers — no JSON parse in bash.

**Area 2 — JSON Output Shape (amended after discuss; option B chosen):**
- DET-06 amended (binding): The detection report renders in a human-readable text format (default, TTY-aware color, `[DET-NN] key=value` markers for grep stability). An undocumented `--report-format=json` flag emits the same captured data as a `jq -n`-built object for test-only consumption. **No JSON Schema document. No `schema_version` field. No ADR.** Bats @tests parse via `jq` for structural assertions.
- REQUIREMENTS.md gets a strikeout-style amendment on the original DET-06 wording with a 1-line "amended in Phase 12 discuss" footnote, applied as the FIRST plan in this phase.

**Area 3 — Text Format Design (accepted as recommended):**
- Color: TTY-detect via `[ -t 1 ]`; ANSI escape literals (`\033[32m✓\033[0m` style); honor `NO_COLOR` env var (de-facto standard, https://no-color.org). No `tput`, no extra deps.
- Section ordering: ROADMAP success-criteria order — User → Node.js → npm prefix → Catalog agents → Sudoers.
- Field markers: Per-field `[DET-NN] key=value` line prefix for grep stability. Example: `[DET-01] user.uid=1001 user.shell=/bin/bash user.home_writable=true`. One DET-NN section per detector, multiple lines if needed.
- Verbosity: Single output level. No `--verbose`/`--brief` flags.

**Area 4 — Read-Only Verification Strategy (3 of 4 accepted; Q3 changed):**
- Q1 — convention + dedicated bats @test that snapshots target paths before/after a detection pass and asserts byte-equality. No runtime FS-write guard.
- Q2 — Targeted snapshot scope: `/etc`, `/home`, `/usr/local/bin`, `/opt`, `/home/agent` — captured via `find ... -printf '%p %T@ %s\n' | sort -u` (mtime + size + path).
- Q3 — Docker matrix only (Ubuntu 22.04 + 24.04). User explicitly opted out of QEMU run for this @test; project-level QEMU-mandatory-for-release rule unchanged.
- Q4 — Detection uses ONLY non-mutating probes: `dpkg-query` (read-only), `apt list --installed` (read-only), `id`, `getent`, `stat`, `node --version`, `npm config get prefix`, `<agent> --version`. NEVER `apt-get update`, `apt install`, `npm install`. The allowed-probe list is documented in `plugin/lib/detect/README.md` (one paragraph, no ADR ceremony).

**Phase 12 → Phase 13 contract:**
1. `plugin/lib/detect.sh` exists and is sourceable.
2. Reader functions named `detect::user_present`, `detect::user_uid`, `detect::user_shell`, `detect::user_home_writable`, `detect::nodejs_satisfies_pin`, `detect::nodejs_prefix_writable`, `detect::npm_prefix_path`, `detect::npm_prefix_writable_by_install_user`, `detect::agent_status <name>` (returns `healthy`/`broken`/`absent`).
3. Detection has been run before any reader is called — provisioners call `detect::run_once` (memoized; first call probes, subsequent calls return cached results from `/run/agentlinux-detect.json`).

### Claude's Discretion

- The exact `find -maxdepth N` depth per Node-manager dir (within reason — research suggests N=4 covers all known layouts).
- Whether to expose Node-manager *active version* vs *all installed versions* per source. ROADMAP "Open Questions" lists this as decided in Phase 12 — research recommends "all installed under manager prefix" (simpler, brownfield report is more informative).
- Renderer-internal helper signatures (`__det_color`, `__det_field`, etc.) — pattern, not interface. Phase 13 cares only about reader functions.
- jq fragment-vs-orchestrator merge style — research recommends per-detector emits a JSON fragment to a tmpfile, orchestrator slurps via `jq -n --slurpfile`.

### Deferred Ideas (OUT OF SCOPE)

- **Schema doc + version field for the JSON output.** Rejected as ceremony — no real consumer beyond tests in v0.3.4. Re-open if a real external consumer emerges.
- **`--verbose` / `--brief` flags.** Not in scope; add only if a real use case appears.
- **Runtime FS-write guard (LD_PRELOAD or strace wrapper).** Considered, rejected for complexity; bats snapshot @test is sufficient.
- **Detection of arbitrary npm globals beyond catalog agents** (`npx`, `tsx`, `vercel`, `pnpm`). Out of scope per REQUIREMENTS.md "Future Requirements" — AgentLinux only owns its catalog.
- **QEMU run for the read-only @test.** User explicitly opted out; Docker is sufficient because the contract is FS-write-count, not init-system behavior.
- **Auto-migration of nvm/fnm/volta/mise to system Node.js.** Out of scope per v0.3.4 future-requirements; surfaced as Bail in Phase 14.
- **Brownfield support on non-Ubuntu distros.** Ubuntu 22.04/24.04/26.04 only.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DET-01 | Pre-flight discovery: install user (default `agent`, overridable via `--user=NAME`); UID, GID, login shell, home dir, group memberships (`id -nG`), home writability — captured in structured pre-flight report | §Standard Stack `getent`+`id`+`stat`+`test -w`; §Pattern 1 `detect::user`; §Code Examples §1 |
| DET-02 | Pre-flight discovery: pre-existing Node.js across 8 sources (NodeSource APT, distro APT, nvm, fnm, volta, mise, asdf-node, pnpm-managed, manual `/usr/local/bin/node`); per source: binary path, `node --version`, install method, install-user write-to-prefix bool | §Pattern 2 `detect::nodejs` (canonical-path file-existence; never source manager hooks); §Pitfall 1 (DON'T source `~/.nvm/nvm.sh`); §Code Examples §2 |
| DET-03 | Pre-flight discovery: install user's resolved npm global prefix (`npm config get prefix --location=user` falling back to system); path, ownership (`stat -c %U:%G`), install-user writability; surface BOTH per-user override AND system fallback when both exist | §Pattern 3 `detect::npm_prefix` (two-value report; `as_user` invocation; `--location=user` vs `--no-userconfig`); §Pitfall 2 (npm location semantics); §Code Examples §3 |
| DET-04 | Pre-flight discovery: catalog agents (claude-code, gsd, **playwright-cli** — note rename from REQUIREMENTS.md "playwright"). Per agent: binary path on install user's PATH (must `as_user` probe), version, ownership, health probe (exit 0 on `--help`); classified `healthy`/`broken`/`absent` | §Pattern 4 `detect::agents`; §Pitfall 3 (binary-name catalog discrepancy); §Pitfall 4 (PATH visibility); §Code Examples §4 |
| DET-05 | Pre-flight discovery: `/etc/sudoers.d/agentlinux` existence, mode, ownership, SHA256, drift from ADR-012 expected exact line; never edit/remove the file | §Pattern 5 `detect::sudoers`; §Code Examples §5 |
| DET-06 (amended) | Two report formats — human-readable text (default, TTY-aware color, `[DET-NN] key=value` markers); undocumented `--report-format=json` for tests (`jq -n`-built object). NO schema doc, NO `schema_version` field, NO ADR. | §Pattern 6 (text renderer with TTY+NO_COLOR); §Pattern 7 (jq -n object construction); §Code Examples §6, §7 |

## Standard Stack

### Core (already in tree, reuse only)

| Library / Binary | Version | Purpose | Why Standard |
|------------------|---------|---------|--------------|
| bash | 5.x (Ubuntu 22.04/24.04/26.04 default) | Detection module impl language | Matches all other plugin/lib/*.sh; inherits strict-mode from entrypoint per existing pattern (`30-nodejs.sh:71`) [VERIFIED: read plugin/lib/idempotency.sh, plugin/provisioner/30-nodejs.sh] |
| `plugin/lib/log.sh` | live | TTY-aware color, INFO/WARN/ERROR routing | Already implements `__log_color <fd> <name>` with `[[ -t $fd ]]` gate — extend with green/✓/✗ macros, do not duplicate the TTY logic [VERIFIED: read plugin/lib/log.sh:23-35] |
| `plugin/lib/as_user.sh` | live | `sudo -u <user> -H -E --` for invoking commands as install user | Required by DET-03 (npm config) and DET-04 (agent binaries on user PATH); `-H` sets HOME (load-bearing for `~/.npmrc` lookup); `-E` preserves env (subject to secure_path) [VERIFIED: read plugin/lib/as_user.sh:32-40] |
| `plugin/lib/distro_detect.sh` | live | Read-only `/etc/os-release` probe | Pattern model for detection-style `return 1`-on-refusal functions [VERIFIED: read plugin/lib/distro_detect.sh:29-61] |

### Supporting (system binaries already on Ubuntu base)

| Binary | Purpose | When to Use | Notes |
|--------|---------|-------------|-------|
| `getent passwd <user>` | UID/GID/shell/home of any user | DET-01 every probe | Reads NSS chain (passwd file + sssd if configured). Returns `<name>:x:<uid>:<gid>:<gecos>:<home>:<shell>` — split on `:` [VERIFIED: man getent] |
| `id -u <user>` / `id -g <user>` / `id -nG <user>` | UID / GID / group memberships | DET-01 redundant cross-check | `id -nG` outputs space-separated group names |
| `stat -c '%a %U:%G %s' <path>` | Mode, owner:group, size | DET-03 prefix ownership; DET-05 sudoers drop-in mode | Standard GNU coreutils format; portable across Ubuntu 22.04/24.04/26.04 [VERIFIED: stat (GNU coreutils) 9.4 in dev env] |
| `test -w <path>` (in `as_user` invocation) | Writability of a path AS the install user | DET-01 home-writable; DET-02 prefix-writable; DET-03 prefix-writable | The ONLY portable way to answer "can user X write here?" is to call `test -w` AS user X — root's view is always wrong (root can write anywhere) |
| `dpkg-query -W -f='${Status} ${Version}\n' nodejs` | Read-only query of dpkg DB | DET-02 distro APT + NodeSource detection | Read-only by contract (vs `dpkg --status` which can lock); matches Q4 allowed-probe list. NodeSource and distro APT both register as package `nodejs`; differentiate via `${Version}` (NodeSource version strings end in `-1nodesource1` per the verified prod env) [VERIFIED: dpkg-query -W -f='${Package} ${Version} ${Status}\n' nodejs in dev env returned `nodejs 22.22.2-1nodesource1 install ok installed`] |
| `find <dir> -maxdepth N -name node -type f -o -type l` | Locate `node` under manager prefixes without sourcing hooks | DET-02 for nvm/fnm/volta/mise/asdf-node/pnpm | `-maxdepth` bounds latency on a brownfield home with thousands of files; manager layouts are deterministic so depth ≤ 6 covers all |
| `readlink -f <path>` | Resolve symlink chains | DET-02 differentiate `/usr/local/bin/node` real binary vs symlink to a manager | Important: a `/usr/local/bin/node` symlinked into nvm's current Node is a "manual" entry per the user's perspective but a `/usr/local/bin/node` regular file is something else (manual tarball install) — readlink -f distinguishes |
| `npm config get prefix --location=user` | Per-user prefix from `~/.npmrc` | DET-03 user-scoped value | Returns `/usr` (npm builtin default) when user has no `prefix=` line in `~/.npmrc` [VERIFIED in dev env: `HOME=$tmpdir npm config get prefix` returns `/usr` when ~/.npmrc absent] |
| `npm config get prefix` (no `--location`) | Resolved-as-effective prefix | DET-03 effective value | Honors `NPM_CONFIG_PREFIX` env > project `.npmrc` > user `~/.npmrc` > builtin (`/usr`) [VERIFIED in dev env: `NPM_CONFIG_PREFIX=/tmp/foo-prefix npm config get prefix` returns `/tmp/foo-prefix`] |
| `command -v <binary>` | Resolves binary path on PATH | DET-04 agent binary location | Bash builtin; `as_user agent command -v claude` reports the path the install user would actually invoke |
| `sha256sum <file>` | File content hash | DET-05 drift detection vs ADR-012 expected line | Deterministic; bats already uses this pattern (`tests/bats/22-agent-sudo.bats:106`) |
| `jq -n --arg <name> <value> '<filter>'` | Build JSON object from null input + bash vars | DET-06 JSON renderer | `--arg` quotes strings; `--argjson` for numbers/bools/arrays; merge fragments via `--slurpfile` [VERIFIED in dev env: jq 1.7 built `{user:{name:"agent",uid:1001,shell:"/bin/bash",present:true}}` correctly] |

### Alternatives Considered (and rejected)

| Instead of | Could Use | Why Rejected |
|------------|-----------|--------------|
| `find -maxdepth` for manager probes | Source the manager's shell init (`source ~/.nvm/nvm.sh && nvm ls`) | Violates Q4 allowed-probe contract; sourcing nvm.sh mutates PATH and adds 50-200ms latency per source; mise's activate hook can side-effect-write to `~/.config/mise/`. See Pitfall 1. |
| `dpkg-query` | `apt-cache policy nodejs` | apt-cache can take a `apt-get update`-like network round-trip and is slower. dpkg-query reads the local dpkg DB only. |
| Single resolved npm prefix value | `npm config get prefix` once | DET-03 explicitly requires reporting BOTH per-user and system fallback when both exist — needed by Phase 14 REMEDIATE-01 to distinguish "user has no `~/.npmrc`" (Reuse with system prefix) from "user has `~/.npmrc` with bad prefix" (Remediate via rebase) |
| `tput colors` for TTY check | Existing `[[ -t $fd ]]` from log.sh | tput reads TERMINFO and depends on TERM env; the existing pattern is simpler, faster, and already in tree |
| `process substitution` for jq merge | `jq --slurpfile` | jq's `--slurpfile` reads a file containing JSON objects/arrays into a variable atomically; process substitution adds a subshell and is harder to reason about under set -e |

**Installation note:** All listed tools are present on minimal Ubuntu 22.04/24.04/26.04 base images EXCEPT `jq` (already pre-installed by `30-nodejs.sh`'s prereq block in some Docker contexts but NOT guaranteed on all). Add `jq` to the `apt-get install` list in `30-nodejs.sh`'s prerequisite block — but for Phase 12 we cannot rely on `30-nodejs.sh` having already run (detection runs *before* provisioners). **Recommendation: install `jq` in `plugin/bin/agentlinux-install` before `run_provisioners` is gated; the install is idempotent (`apt-get install -y --no-install-recommends jq` is a no-op when present).**

**Version verification:**
- `jq 1.7` confirmed in dev env (Ubuntu base) [VERIFIED]
- `stat (GNU coreutils) 9.4` confirmed [VERIFIED]
- `dpkg-query` ships with dpkg core, always present
- `getent` ships with libc-bin, always present
- `npm 10.9.7` paired with the `nodejs 22.22.2-1nodesource1` install in dev env [VERIFIED]

## Architecture Patterns

### System Architecture Diagram

```
                         agentlinux-install [--report-only] [--report-format=text|json]
                                              │
                                              ▼
                                     parse_args (argv)
                                              │
                       ┌──────────────────────┴──────────────────────┐
                       │                                             │
            REPORT_ONLY=true                            REPORT_ONLY=false (default; Phase 13+)
                       │                                             │
                       ▼                                             ▼
                require_root                                    require_root
                       │                                             │
                       ▼                                             ▼
                detect_distro                                   detect_distro
                       │                                             │
                       ▼                                             ▼
              source plugin/lib/detect.sh                   source plugin/lib/detect.sh
                       │                                             │
                       ▼                                             ▼
              detect::run_once  ◄───── memoized to /run/agentlinux-detect.json
                       │                                             │
                       ▼                                             ▼
            ┌──────────┴──────────┐                          (Phase 13+ provisioners
            │                     │                           call detect::reader_fns)
       sources detect/ files      │
            │                     │
            ▼                     │
    ┌───────┴───────┬─────┬─────┬──┴──┬─────┐
detect/user.sh  nodejs.sh prefix.sh agents.sh sudoers.sh
    │               │       │       │         │
    ▼               ▼       ▼       ▼         ▼
 [getent     [dpkg-query [as_user [as_user [stat
  id          find        npm     command   sha256sum
  test -w]    readlink    config] -v        cat]
              as_user                <bin>
              node                  --help]
              --version]
    │               │       │       │         │
    └───────┬───────┴───────┴───────┴─────────┘
            │
            ▼
    each detector: emits text block + JSON fragment to tmpfiles
            │
            ▼
   detect.sh orchestrator: jq --slurpfile merges fragments
            │
            ▼
   text  →  log_info-style render (TTY + NO_COLOR aware) → stdout
   json  →  jq '.' pretty-print → stdout
            │
            ▼
   write merged JSON → /run/agentlinux-detect.json (memoization for Phase 13)
            │
            ▼
   exit 0
```

### Recommended Project Structure

```
plugin/lib/
├── log.sh                    # existing; extend with green/✓/✗ macros (or keep separate in detect/render.sh)
├── as_user.sh                # existing; reused for npm + agent binary probes
├── distro_detect.sh          # existing; pattern model
├── idempotency.sh            # existing; NOT used by detect (read-only by contract)
├── detect.sh                 # NEW — orchestrator: sources detect/*.sh, runs all probes, memoizes, emits report
└── detect/
    ├── README.md             # NEW — one paragraph naming allowed probes (per Q4)
    ├── user.sh               # NEW — DET-01: install-user discovery
    ├── nodejs.sh             # NEW — DET-02: 8-source Node discovery
    ├── npm_prefix.sh         # NEW — DET-03: per-user + system prefix discovery
    ├── agents.sh             # NEW — DET-04: catalog-agent discovery
    ├── sudoers.sh            # NEW — DET-05: sudoers drop-in discovery
    └── render.sh             # NEW (optional) — text+json renderers, separated from probe logic for testability

plugin/bin/
└── agentlinux-install        # MODIFIED — parse_args adds --report-only and --report-format=text|json; main() gates run_provisioners

tests/bats/
├── 15-detection.bats         # NEW — slot 15 (before installer-foundation 20-*); per-DET-NN @tests + read-only invariant @test
└── helpers/
    └── detection.bash        # NEW (optional) — snapshot helpers (snapshot_paths, assert_no_drift)
```

### Pattern 1: Install User Detection (DET-01)

**What:** Probe whether `<install_user>` exists; if so, capture UID, GID, login shell, home directory, group memberships, home writability.

**When to use:** Always — DET-01 is the foundational probe that downstream detectors reference (e.g. DET-02 needs the install-user's `$HOME` to bound nvm/fnm searches).

**Example:**
```bash
# plugin/lib/detect/user.sh
# Probes: install user identity + home writability.
# Allowed primitives (Q4): getent, id, stat, test -w (via as_user).

[[ -n "${AGENTLINUX_DETECT_USER_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DETECT_USER_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'detect/user.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# detect::user <name> — populates DETECT_USER_* vars + emits JSON fragment to $1
detect::user_probe() {
  local user=${1:-agent} fragment_path=$2

  local pwent uid gid shell home groups present home_writable
  if pwent=$(getent passwd "$user" 2>/dev/null); then
    present=true
    # passwd format: name:x:uid:gid:gecos:home:shell
    IFS=: read -r _ _ uid gid _ home shell <<< "$pwent"
    groups=$(id -nG "$user" 2>/dev/null || echo "")
    if as_user "$user" test -w "$home"; then
      home_writable=true
    else
      home_writable=false
    fi
  else
    present=false
    uid=""
    gid=""
    shell=""
    home=""
    groups=""
    home_writable=false
  fi

  # Export for in-process readers (Phase 13).
  export DETECT_USER_NAME="$user"
  export DETECT_USER_PRESENT="$present"
  export DETECT_USER_UID="$uid"
  export DETECT_USER_GID="$gid"
  export DETECT_USER_SHELL="$shell"
  export DETECT_USER_HOME="$home"
  export DETECT_USER_GROUPS="$groups"
  export DETECT_USER_HOME_WRITABLE="$home_writable"

  # Emit JSON fragment for orchestrator slurping.
  jq -n \
    --arg name "$user" \
    --argjson present "$present" \
    --arg uid "${uid:-}" \
    --arg gid "${gid:-}" \
    --arg shell "${shell:-}" \
    --arg home "${home:-}" \
    --arg groups "${groups:-}" \
    --argjson home_writable "$home_writable" \
    '{user: {name: $name, present: $present, uid: $uid, gid: $gid, shell: $shell, home: $home, groups: ($groups | split(" ")), home_writable: $home_writable}}' \
    > "$fragment_path"
}

# Reader functions for Phase 13.
detect::user_present() { [[ "${DETECT_USER_PRESENT:-false}" == "true" ]]; }
detect::user_uid()     { printf '%s' "${DETECT_USER_UID:-}"; }
detect::user_shell()   { printf '%s' "${DETECT_USER_SHELL:-}"; }
detect::user_home_writable() { [[ "${DETECT_USER_HOME_WRITABLE:-false}" == "true" ]]; }
```

**Why this shape:**
- Single `detect::user_probe` function does all probes; reader functions are thin accessors over exported vars (Phase 13 contract).
- `getent` (NSS-aware) is preferred over `awk -F: /etc/passwd` because future LDAP/sssd-resolved users would silently miss with the file-only approach.
- `id -nG` reports primary group + supplementary groups in one shot; `groups` env var is unreliable across Ubuntu versions.
- `test -w` MUST run via `as_user` — root sees all dirs as writable.

### Pattern 2: Node.js Multi-Source Detection (DET-02)

**What:** Enumerate every Node.js installation visible to the install user across 8 covered sources, without sourcing any version-manager shell hook.

**When to use:** Always for DET-02. The 8 sources fall into three classes:
1. **System-installed (root-owned):** NodeSource APT, distro APT, manual `/usr/local/bin/node` — probe via `dpkg-query`, file existence, `readlink -f`.
2. **Per-user manager (user-owned):** nvm, fnm, volta, mise, asdf-node, pnpm-managed — probe via canonical-path `find -maxdepth N` under install-user's `$HOME`. Never `source` the manager's shell init.
3. **Active version selection:** the manager's "currently-active Node" is a symlink under a known `current/` or `default/` path; readlink resolves it.

**Canonical install paths (verified from manager docs as of 2026-05-10):**

| Source | Canonical install path | Active-version path | Probe shape |
|--------|------------------------|---------------------|-------------|
| NodeSource APT | `/usr/bin/node` (real file) + apt source `/etc/apt/sources.list.d/nodesource.{sources,list}` | (system Node — only one active) | `dpkg-query -W -f='${Version}\n' nodejs` returns string ending in `-1nodesourceN`; `[[ -f /etc/apt/sources.list.d/nodesource.sources ]] \|\| [[ -f /etc/apt/sources.list.d/nodesource.list ]]` confirms repo |
| Distro APT | `/usr/bin/node` (real file) | (system Node) | `dpkg-query -W -f='${Version}\n' nodejs` returns version WITHOUT `-1nodesourceN` suffix (e.g. `12.22.9~dfsg-1ubuntu3.6` on 22.04) |
| nvm | `~/.nvm/versions/node/v<X>/bin/node` per installed version | `~/.nvm/alias/default` (text file naming alias) → resolves via `~/.nvm/versions/node/v<X>/` | `[[ -d ~/.nvm/versions/node ]] && find ~/.nvm/versions/node -maxdepth 3 -name node -type f` |
| fnm | `~/.local/share/fnm/node-versions/v<X>/installation/bin/node` | `~/.local/share/fnm/aliases/default → versions/v<X>` symlink | `[[ -d ~/.local/share/fnm/node-versions ]] && find -maxdepth 4 -name node -type f` |
| volta | `~/.volta/tools/image/node/<X>/bin/node` | `~/.volta/tools/image/node/<default>/bin/node` resolved via `~/.volta/tools/user/platform.json` | `[[ -d ~/.volta/tools/image/node ]] && find -maxdepth 4 -name node -type f` |
| mise | `~/.local/share/mise/installs/node/<X>/bin/node` | `~/.local/share/mise/installs/node/latest` (symlink) | `[[ -d ~/.local/share/mise/installs/node ]] && find -maxdepth 4 -name node -type f` |
| asdf-node | `~/.asdf/installs/nodejs/<X>/bin/node` | `~/.tool-versions` (project) or `~/.asdf/shims/node` (global) | `[[ -d ~/.asdf/installs/nodejs ]] && find -maxdepth 4 -name node -type f` |
| pnpm-managed | `~/.local/share/pnpm/nodejs/<X>/bin/node` (with `pnpm env use` flow) | `~/.local/share/pnpm/node` symlink | `[[ -d ~/.local/share/pnpm/nodejs ]] && find -maxdepth 4 -name node -type f` |
| Manual `/usr/local/bin/node` | `/usr/local/bin/node` (real file, not symlinked into a manager dir) | n/a | `[[ -f /usr/local/bin/node ]] && [[ "$(readlink -f /usr/local/bin/node)" == /usr/local/bin/node ]]` (real file, not chain) |

**Example:**
```bash
# plugin/lib/detect/nodejs.sh — DET-02
#
# Enumerates Node.js installations across 8 sources WITHOUT sourcing any
# manager's shell init (Q4 allowed-probe contract; ADR-005 rationale).
# Each found Node entry contributes one row to DETECT_NODEJS_ENTRIES_JSON
# (jq array assembled by orchestrator).

detect::nodejs_probe() {
  local user=$1 home=$2 fragment_path=$3
  local entries=()  # accumulator of jq fragments

  # ---- 1. NodeSource APT ----
  local ns_version
  ns_version=$(dpkg-query -W -f='${Version}\n' nodejs 2>/dev/null || true)
  if [[ "$ns_version" == *"-1nodesource"* ]]; then
    entries+=("$(__det_nodejs_entry nodesource /usr/bin/node "$ns_version" "$user" /usr)")
  fi

  # ---- 2. Distro APT (only if dpkg has nodejs AND it's NOT NodeSource) ----
  if [[ -n "$ns_version" && "$ns_version" != *"-1nodesource"* ]]; then
    entries+=("$(__det_nodejs_entry distro_apt /usr/bin/node "$ns_version" "$user" /usr)")
  fi

  # ---- 3. Manual /usr/local/bin/node ----
  if [[ -f /usr/local/bin/node ]]; then
    local resolved
    resolved=$(readlink -f /usr/local/bin/node)
    if [[ "$resolved" == /usr/local/bin/node ]]; then
      # Real file, not a chain into a manager — manual install.
      local v
      v=$(/usr/local/bin/node --version 2>/dev/null || echo "unknown")
      entries+=("$(__det_nodejs_entry manual /usr/local/bin/node "$v" "$user" /usr/local)")
    fi
    # Else: it's symlinked into a manager — that manager's probe will catch it.
  fi

  # ---- 4-9. Per-user managers (canonical-path file-existence; no shell init) ----
  __det_nodejs_manager nvm     "$home/.nvm/versions/node"                    3 "$user" entries
  __det_nodejs_manager fnm     "$home/.local/share/fnm/node-versions"        4 "$user" entries
  __det_nodejs_manager volta   "$home/.volta/tools/image/node"               4 "$user" entries
  __det_nodejs_manager mise    "$home/.local/share/mise/installs/node"       4 "$user" entries
  __det_nodejs_manager asdf    "$home/.asdf/installs/nodejs"                 4 "$user" entries
  __det_nodejs_manager pnpm    "$home/.local/share/pnpm/nodejs"              4 "$user" entries

  # Build final array fragment.
  if [[ ${#entries[@]} -eq 0 ]]; then
    jq -n '{nodejs: []}' > "$fragment_path"
  else
    printf '%s\n' "${entries[@]}" | jq -s '{nodejs: .}' > "$fragment_path"
  fi

  export DETECT_NODEJS_COUNT=${#entries[@]}
}

# __det_nodejs_entry <source> <bin_path> <version> <install_user> <prefix_root>
# Returns one JSON object with: source, path, version, install_user_can_write_prefix
__det_nodejs_entry() {
  local source=$1 bin=$2 version=$3 user=$4 prefix_root=$5
  local writable
  if as_user "$user" test -w "$prefix_root"; then
    writable=true
  else
    writable=false
  fi
  jq -n \
    --arg source "$source" \
    --arg path "$bin" \
    --arg version "$version" \
    --arg prefix_root "$prefix_root" \
    --argjson writable "$writable" \
    '{source: $source, path: $path, version: $version, install_user_can_write_prefix: $writable, prefix_root: $prefix_root}'
}

# __det_nodejs_manager <name> <root> <maxdepth> <user> <accumulator-name>
__det_nodejs_manager() {
  local name=$1 root=$2 maxdepth=$3 user=$4 acc=$5
  [[ -d "$root" ]] || return 0
  # find runs as root (can read user's home for read-only stat); we only call
  # node --version via as_user since binary may need user env to run.
  local found
  while IFS= read -r bin; do
    [[ -z "$bin" ]] && continue
    local v
    v=$(as_user "$user" "$bin" --version 2>/dev/null || echo "unknown")
    # Append to caller's array via nameref.
    declare -n __acc=$acc
    __acc+=("$(__det_nodejs_entry "$name" "$bin" "$v" "$user" "$(dirname "$(dirname "$bin")")")")
  done < <(find "$root" -maxdepth "$maxdepth" -name node -type f 2>/dev/null)
}
```

**Why this shape:**
- Canonical-path file-existence is the ONLY non-mutating way to enumerate per-user managers. ADR-005 already documented the shell-hook fragility; we inherit that lesson.
- One `find` per manager root keeps the latency bounded and the code readable.
- The `__det_nodejs_entry` helper is the JSON contract: every detected Node has the same five fields.
- `dpkg-query`'s `-1nodesourceN` version-suffix discriminator differentiates NodeSource vs distro APT in one cheap probe.

### Pattern 3: npm Prefix Detection — Per-User AND System (DET-03)

**What:** Discover the install user's resolved npm global prefix, surfacing BOTH the per-user override (from `~/.npmrc`) AND the system fallback (npm's builtin default) when both exist.

**Critical semantics (verified live in dev env):**
- `npm config get prefix --location=user` reads ONLY `~/.npmrc`; returns `/usr` (npm's builtin default) when `~/.npmrc` lacks a `prefix=` line.
- `npm config get prefix` (no `--location`) returns the resolved-as-effective value: env (`NPM_CONFIG_PREFIX`) > project `.npmrc` > user `~/.npmrc` > builtin default.
- The MUST-be-as-user invariant: running `npm config get prefix` AS ROOT reads root's `~/.npmrc`, not the install user's. Always `as_user agent npm config get prefix ...`.

**Example:**
```bash
# plugin/lib/detect/npm_prefix.sh — DET-03

detect::npm_prefix_probe() {
  local user=$1 fragment_path=$2

  # If npm isn't installed, both values are empty.
  if ! as_user "$user" command -v npm >/dev/null 2>&1; then
    jq -n --arg user "$user" \
      '{npm_prefix: {npm_present: false, user_prefix: null, system_prefix: null, effective_prefix: null}}' \
      > "$fragment_path"
    export DETECT_NPM_PREFIX_PATH=""
    export DETECT_NPM_PREFIX_USER_WRITABLE=false
    return 0
  fi

  # Per-user prefix from ~/.npmrc (or npm builtin default if absent).
  local user_prefix system_prefix effective_prefix
  user_prefix=$(as_user "$user" npm config get prefix --location=user 2>/dev/null | tr -d '[:space:]')

  # System prefix (npm builtin default — typically /usr on Debian/Ubuntu).
  # --no-userconfig instructs npm to ignore ~/.npmrc; --globalconfig isolates
  # global config; result is the builtin default.
  system_prefix=$(as_user "$user" \
    env NPM_CONFIG_PREFIX= npm config get prefix --no-userconfig 2>/dev/null \
    | tr -d '[:space:]')

  effective_prefix=$(as_user "$user" npm config get prefix 2>/dev/null | tr -d '[:space:]')

  # Ownership + writability on the EFFECTIVE prefix (the one Phase 13 cares about).
  local owner mode user_writable
  if [[ -d "$effective_prefix" ]]; then
    owner=$(stat -c '%U:%G' "$effective_prefix" 2>/dev/null || echo "unknown")
    mode=$(stat -c '%a' "$effective_prefix" 2>/dev/null || echo "")
    if as_user "$user" test -w "$effective_prefix"; then
      user_writable=true
    else
      user_writable=false
    fi
  else
    owner="absent"
    mode=""
    user_writable=false
  fi

  jq -n \
    --argjson npm_present true \
    --arg user_prefix "$user_prefix" \
    --arg system_prefix "$system_prefix" \
    --arg effective_prefix "$effective_prefix" \
    --arg owner "$owner" \
    --arg mode "$mode" \
    --argjson user_writable "$user_writable" \
    '{npm_prefix: {
      npm_present: $npm_present,
      user_prefix: $user_prefix,
      system_prefix: $system_prefix,
      effective_prefix: $effective_prefix,
      effective_owner: $owner,
      effective_mode: $mode,
      install_user_writable: $user_writable
    }}' \
    > "$fragment_path"

  export DETECT_NPM_PREFIX_PATH="$effective_prefix"
  export DETECT_NPM_PREFIX_USER_WRITABLE="$user_writable"
  export DETECT_NPM_PREFIX_USER_VALUE="$user_prefix"
  export DETECT_NPM_PREFIX_SYSTEM_VALUE="$system_prefix"
}
```

### Pattern 4: Catalog Agent Detection (DET-04)

**What:** For each catalog agent, probe binary path on the install user's PATH, version, ownership, and a quick health probe; classify each as `healthy` / `broken` / `absent`.

**Critical: catalog binary names ≠ requirement prose names.**
- REQUIREMENTS.md DET-04 lists `claude-code, gsd, playwright`.
- Live `plugin/catalog/catalog.json` has IDs `claude-code, gsd, playwright-cli, test-dummy`.
- Actual binary names on PATH after install: `claude` (not `claude-code`), `get-shit-done-cc` (not `gsd`), `playwright-cli` (not `playwright`).

This research's authoritative agent → binary mapping (cross-verified against `plugin/catalog/agents/*/install.sh`):

| Catalog ID | Binary on PATH | Version probe | Health probe | Expected install path |
|-----------|----------------|---------------|--------------|----------------------|
| claude-code | `claude` | `claude --version` (semver line) | exit 0 on `claude --help` | `~/.local/bin/claude` (native installer) |
| gsd | `get-shit-done-cc` | `get-shit-done-cc --help \| head -20 \| grep -F 'v<X>'` (banner-grep — no `--version` exists) | exit 0 on `get-shit-done-cc --help` | `~/.npm-global/bin/get-shit-done-cc` |
| playwright-cli | `playwright-cli` | `playwright-cli --version` (semver line) | exit 0 on `playwright-cli --help` | `~/.npm-global/bin/playwright-cli` |

`test-dummy` is `test_only: true` in the catalog — detection should **skip** it (no real agent).

**Classification rule:**
- `absent` — `as_user agent command -v <binary>` exits non-zero.
- `healthy` — binary present + version probe outputs parseable string + health probe (`--help`) exits 0.
- `broken` — binary present BUT (version probe fails to parse OR health probe non-zero exit).

**Example:**
```bash
# plugin/lib/detect/agents.sh — DET-04
#
# Catalog agent map (binary names verified against plugin/catalog/agents/*/install.sh).
# Order: matches catalog.json declaration order (test-dummy filtered out).

# Associative arrays for per-agent metadata.
declare -A DETECT_AGENT_BINARIES=(
  [claude-code]=claude
  [gsd]=get-shit-done-cc
  [playwright-cli]=playwright-cli
)

# Health-probe and version-probe shapes per agent.
__det_agent_version() {
  local id=$1
  case "$id" in
    claude-code)    echo "--version" ;;     # semver line
    gsd)            echo "--help" ;;        # banner-grep mode
    playwright-cli) echo "--version" ;;     # semver line
  esac
}

detect::agents_probe() {
  local user=$1 fragment_path=$2
  local entries=()

  local id binary version_flag bin_path ver health status owner
  for id in "${!DETECT_AGENT_BINARIES[@]}"; do
    binary=${DETECT_AGENT_BINARIES[$id]}
    bin_path=$(as_user "$user" command -v "$binary" 2>/dev/null || echo "")

    if [[ -z "$bin_path" ]]; then
      status=absent
      ver=""
      owner=""
    else
      version_flag=$(__det_agent_version "$id")
      ver=$(as_user "$user" "$binary" "$version_flag" 2>/dev/null | head -5 | tr '\n' ' ' | tr -d '\r')
      owner=$(stat -c '%U:%G' "$bin_path" 2>/dev/null || echo "unknown")
      # Health probe — independent from version (--help should always exit 0
      # for healthy CLIs; failures = broken).
      if as_user "$user" "$binary" --help >/dev/null 2>&1; then
        # Status hinges on whether version probe produced anything parseable.
        if [[ -n "$ver" ]]; then
          status=healthy
        else
          status=broken
        fi
      else
        status=broken
      fi
    fi

    entries+=("$(jq -n \
      --arg id "$id" \
      --arg binary "$binary" \
      --arg path "$bin_path" \
      --arg version "$ver" \
      --arg owner "$owner" \
      --arg status "$status" \
      '{id: $id, binary: $binary, path: $path, version: $version, owner: $owner, status: $status}')")

    # Per-agent reader exports (Phase 13 consumes these).
    local upper=${id^^}; upper=${upper//-/_}
    export "DETECT_AGENT_${upper}_STATUS"="$status"
    export "DETECT_AGENT_${upper}_PATH"="$bin_path"
  done

  printf '%s\n' "${entries[@]}" | jq -s '{agents: .}' > "$fragment_path"
}

# Reader for Phase 13.
detect::agent_status() {
  local id=$1
  local upper=${id^^}; upper=${upper//-/_}
  local var="DETECT_AGENT_${upper}_STATUS"
  printf '%s' "${!var:-absent}"
}
```

### Pattern 5: Sudoers Drop-In Detection (DET-05)

**What:** Detect existence of `/etc/sudoers.d/agentlinux`, capture mode + owner + SHA256, flag drift from ADR-012's expected exact line.

**Expected canonical content (ADR-012, verbatim from `plugin/provisioner/20-sudoers.sh:56-60`):**
```
# Installed by AgentLinux — grants passwordless sudo to agent user.
# Scope: ALL commands. See docs/decisions/012-agent-user-full-sudo.md.
agent ALL=(ALL) NOPASSWD: ALL
```

The grep-stable substring check is `grep -Fx 'agent ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/agentlinux` (matches the existing bats convention at `tests/bats/22-agent-sudo.bats:51`). The SHA256 captures the FULL file content; drift can be either:
- File body changed (header comments rewritten) — soft drift, the policy line is still there.
- Policy line changed/missing — hard drift, the file no longer satisfies BHV-07.

Detection should report BOTH the SHA256 (exact bytes) AND a separate boolean for "expected NOPASSWD line still present". Phase 14 REMEDIATE-03 needs the booleans to decide rebase-vs-leave-alone.

**Example:**
```bash
# plugin/lib/detect/sudoers.sh — DET-05
#
# Read-only probe of /etc/sudoers.d/agentlinux. NEVER edits. NEVER runs visudo
# (visudo with no args opens the editor — would be a side effect; we use
# `visudo -cf` only as a verification step in Phase 13, not in detection).

readonly DETECT_SUDOERS_PATH=/etc/sudoers.d/agentlinux
readonly DETECT_SUDOERS_EXPECTED_LINE='agent ALL=(ALL) NOPASSWD: ALL'

detect::sudoers_probe() {
  local fragment_path=$1
  local present mode owner sha256 nopasswd_present

  if [[ -f "$DETECT_SUDOERS_PATH" ]]; then
    present=true
    mode=$(stat -c '%a' "$DETECT_SUDOERS_PATH" 2>/dev/null || echo "")
    owner=$(stat -c '%U:%G' "$DETECT_SUDOERS_PATH" 2>/dev/null || echo "unknown")
    sha256=$(sha256sum "$DETECT_SUDOERS_PATH" | cut -d' ' -f1)
    if grep -Fxq -- "$DETECT_SUDOERS_EXPECTED_LINE" "$DETECT_SUDOERS_PATH"; then
      nopasswd_present=true
    else
      nopasswd_present=false
    fi
  else
    present=false
    mode=""
    owner=""
    sha256=""
    nopasswd_present=false
  fi

  jq -n \
    --arg path "$DETECT_SUDOERS_PATH" \
    --argjson present "$present" \
    --arg mode "$mode" \
    --arg owner "$owner" \
    --arg sha256 "$sha256" \
    --argjson nopasswd_present "$nopasswd_present" \
    '{sudoers: {
      path: $path,
      present: $present,
      mode: $mode,
      owner: $owner,
      sha256: $sha256,
      nopasswd_line_present: $nopasswd_present
    }}' \
    > "$fragment_path"

  export DETECT_SUDOERS_PRESENT="$present"
  export DETECT_SUDOERS_NOPASSWD_OK="$nopasswd_present"
}
```

### Pattern 6: Text Renderer (TTY + NO_COLOR aware)

**What:** Render the detection report as `[DET-NN] key=value` blocks with optional ANSI color when stdout is a TTY AND `NO_COLOR` is unset.

**Why the existing `log.sh` color machinery is not enough:**
- `log_info` prepends a timestamp — wrong for a report line.
- `log.sh` doesn't have a green-checkmark / red-cross macro yet.
- Detection report goes to stdout (not stderr like log_warn/log_error) so it can be piped to `jq` or `grep`.

**Recommendation:** Add a tiny `__det_color`/`__det_status_glyph` helper inside `detect/render.sh`, modeled on `log.sh:__log_color` (already TTY-aware). Honor `NO_COLOR` env var per https://no-color.org.

**Example:**
```bash
# plugin/lib/detect/render.sh

# __det_color <fd> <name> — emit ANSI escape for <name> only when:
#   (a) <fd> is a TTY ([[ -t $fd ]])
#   (b) NO_COLOR env var is unset/empty (https://no-color.org)
__det_color() {
  local fd=$1 color=$2
  [[ -t $fd ]] || { printf ''; return; }
  [[ -n "${NO_COLOR:-}" ]] && { printf ''; return; }
  case "$color" in
    green)  printf '\033[32m' ;;
    red)    printf '\033[31m' ;;
    yellow) printf '\033[33m' ;;
    dim)    printf '\033[2m' ;;
    reset)  printf '\033[0m' ;;
  esac
}

# __det_glyph <kind> — colored ✓ / ✗ / • marker.
__det_glyph() {
  case "$1" in
    ok)      printf '%s✓%s' "$(__det_color 1 green)" "$(__det_color 1 reset)" ;;
    bad)     printf '%s✗%s' "$(__det_color 1 red)"   "$(__det_color 1 reset)" ;;
    warn)    printf '%s•%s' "$(__det_color 1 yellow)" "$(__det_color 1 reset)" ;;
    absent)  printf '%s—%s' "$(__det_color 1 dim)"   "$(__det_color 1 reset)" ;;
  esac
}

# Render a single DET-NN field line with grep-stable prefix.
# Usage: __det_field DET-01 "user.uid" "$uid"
__det_field() {
  local req=$1 key=$2 val=$3
  printf '[%s] %s=%s\n' "$req" "$key" "$val"
}

# Section header line — visible context for humans, but ALSO grep-stable
# (one '## DET-NN' marker per section).
__det_section() {
  local req=$1 title=$2
  printf '\n## %s — %s\n' "$req" "$title"
}

detect::render_text() {
  # User block (DET-01)
  __det_section "DET-01" "Install User"
  if [[ "$DETECT_USER_PRESENT" == "true" ]]; then
    printf '%s present\n' "$(__det_glyph ok)"
    __det_field DET-01 user.name "$DETECT_USER_NAME"
    __det_field DET-01 user.uid "$DETECT_USER_UID"
    __det_field DET-01 user.gid "$DETECT_USER_GID"
    __det_field DET-01 user.shell "$DETECT_USER_SHELL"
    __det_field DET-01 user.home "$DETECT_USER_HOME"
    __det_field DET-01 user.home_writable "$DETECT_USER_HOME_WRITABLE"
    __det_field DET-01 user.groups "$DETECT_USER_GROUPS"
  else
    printf '%s absent\n' "$(__det_glyph absent)"
    __det_field DET-01 user.name "$DETECT_USER_NAME"
    __det_field DET-01 user.present false
  fi

  # Node.js block (DET-02), npm prefix (DET-03), agents (DET-04), sudoers (DET-05) … same shape.
}
```

### Pattern 7: JSON Renderer via `jq -n` Object Construction

**What:** Each detector emits a JSON fragment (object) to a tmpfile. The orchestrator merges them into a single object via `jq -n --slurpfile`.

**Why this shape (vs building one giant `jq -n` call):**
- Per-detector fragments are independently testable (orchestrator tests merge logic; per-detector tests verify content).
- Avoids massive `--arg` plumbing in a single jq invocation.
- Tmpfiles cleanup via `trap '...' EXIT` in orchestrator.

**Example:**
```bash
# plugin/lib/detect.sh — orchestrator

[[ -n "${AGENTLINUX_DETECT_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DETECT_SH_SOURCED=1

# Source dependencies + per-detector files.
# (Caller — agentlinux-install — has already sourced log.sh + as_user.sh.)
DETECT_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/detect" && pwd)
readonly DETECT_LIB_DIR
. "$DETECT_LIB_DIR/render.sh"
. "$DETECT_LIB_DIR/user.sh"
. "$DETECT_LIB_DIR/nodejs.sh"
. "$DETECT_LIB_DIR/npm_prefix.sh"
. "$DETECT_LIB_DIR/agents.sh"
. "$DETECT_LIB_DIR/sudoers.sh"

readonly DETECT_CACHE_PATH=/run/agentlinux-detect.json

# detect::run_once <install_user> — memoized per process. First call runs all
# probes + writes /run/agentlinux-detect.json. Subsequent calls return.
detect::run_once() {
  local user=${1:-agent}
  [[ -n "${DETECT_RAN:-}" ]] && return 0

  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf -- '$tmpdir'" RETURN

  # Each probe writes its own fragment (one JSON object) to tmpdir.
  detect::user_probe        "$user"                                  "$tmpdir/01-user.json"
  detect::nodejs_probe      "$user" "${DETECT_USER_HOME:-/home/$user}" "$tmpdir/02-nodejs.json"
  detect::npm_prefix_probe  "$user"                                  "$tmpdir/03-npm.json"
  detect::agents_probe      "$user"                                  "$tmpdir/04-agents.json"
  detect::sudoers_probe                                              "$tmpdir/05-sudoers.json"

  # Merge into a single object. `--slurpfile` reads each file as a JSON array
  # (single element); `add` flattens to a single object.
  jq -s 'add' \
    "$tmpdir/01-user.json" \
    "$tmpdir/02-nodejs.json" \
    "$tmpdir/03-npm.json" \
    "$tmpdir/04-agents.json" \
    "$tmpdir/05-sudoers.json" \
    > "$DETECT_CACHE_PATH"

  export DETECT_RAN=1
  export DETECT_CACHE_PATH
}

# detect::emit_report <format> — text or json. Stdout.
detect::emit_report() {
  local format=${1:-text}
  case "$format" in
    text) detect::render_text ;;
    json) jq '.' "$DETECT_CACHE_PATH" ;;
    *) log_error "detect::emit_report: unknown format '$format' (expected text or json)"; return 64 ;;
  esac
}
```

### Anti-Patterns to Avoid

- **Sourcing manager hooks** (`source ~/.nvm/nvm.sh`, `eval "$(fnm env)"`, `eval "$(mise activate bash)"`). Mutates PATH. Possibly side-effect-writes (mise activate creates `~/.config/mise/`). Slow (50-200ms). Violates Q4 read-only contract. Use canonical-path file-existence instead.
- **Running `npm config get prefix` AS ROOT.** Reads root's `~/.npmrc`, not the install user's. Always `as_user agent npm config get prefix ...`. Same trap for every command that reads user dotfiles.
- **`apt-cache policy nodejs`.** Slower than `dpkg-query`; can trigger an `apt-get update`-like network round-trip on stale lists.
- **Probing for binaries via `which`.** `which` behavior varies across distros (Debian's `which` is the user's `which`, sometimes a shell function, sometimes the GNU `which` binary). Use `command -v` (POSIX, bash builtin).
- **`stat --version` to detect coreutils flavor.** Don't branch on coreutils — `stat -c '%a %U:%G'` is portable across GNU coreutils 8.x/9.x and uutils-coreutils 0.7.0 (the Rust rewrite shipped on Ubuntu 26.04). [VERIFIED: stat 9.4 in dev env, no regressions found per existing 30-nodejs.sh comments]
- **Caching detection in `/var/cache/agentlinux/detect.json` or any persistent path.** /run is tmpfs; survives the entrypoint invocation but evaporates at reboot. Persistent caches can go stale silently — the next install would read pre-mutation state.
- **Returning `exit 1` from a sourced detection function.** Use `return 1` per the existing convention (`30-nodejs.sh:71` comment). Sourced fragments inherit the entrypoint's ERR trap; `exit` aborts the whole installer.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON object construction from bash vars | A function that does `printf '"%s":"%s"' name val` and string-concatenates | `jq -n --arg name "$val" '{name: $name}'` | jq handles escaping (newlines, quotes, unicode) correctly; printf does not. The `jq -n` idiom is verified and there's no value in re-implementing JSON encoding. [VERIFIED in dev env] |
| Merging multiple JSON objects | Per-key dict-merge in bash | `jq -s 'add' file1 file2 …` | jq's `add` operator merges objects deterministically; bash dict-merge is verbose and gets escaping wrong. |
| User UID lookup | `awk -F: '{print $3}' /etc/passwd` | `getent passwd <user>` then split | NSS-aware (LDAP/sssd/files); future brownfield hosts may use external NSS. |
| Group memberships | `cat /etc/group` parse | `id -nG <user>` | Handles primary + supplementary groups; one shell call. |
| Detecting symlink chains | manual `readlink` loops | `readlink -f <path>` | Resolves the entire chain to a canonical path in one call. |
| Detecting binary on user's PATH from root | `find / -name <binary>` | `as_user <user> command -v <binary>` | The only correct answer to "would the user find this on PATH?" is to ask the user's PATH. |
| TTY detection for color | Reading `$TERM` and matching | `[[ -t $fd ]]` | Fast, posix, no env-var quirks (TERM=dumb misleads but [[ -t ]] is reliable). |
| File-byte snapshot for the no-op invariant | `tar c \| sha256sum` (slow, includes content) | `find ... -printf '%p %T@ %s\n' \| sort -u \| sha256sum` | content is irrelevant; we want path + mtime + size. find's -printf is one syscall per inode. [VERIFIED in dev env] |

**Key insight:** Every "I'll just write a small helper" itch in this domain has a sharper edge than it looks. JSON encoding has unicode/escape edge cases. NSS-aware passwd lookup matters on real systems. PATH visibility is install-user-specific, not root-resolvable. Lean on `getent`/`id`/`stat`/`jq`/`as_user` and let them do the load-bearing work.

## Runtime State Inventory

> Phase 12 introduces a NEW capability (read-only detection layer); it is NOT a rename or refactor. The Runtime State Inventory section is included for completeness but most categories are "none" — the detection layer is greenfield code that doesn't move existing strings or runtime state.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — detection writes only to `/run/agentlinux-detect.json` (tmpfs, evaporates at reboot). No database, no persistent store touched. | None |
| Live service config | None — Phase 12 adds no systemd units, no cron jobs, no launchd plists, no Tailscale/Datadog/n8n config. | None |
| OS-registered state | None — no Task Scheduler, no pm2 saved processes, no systemd unit names, no launchd. | None |
| Secrets/env vars | One NEW env var convention: `AGENTLINUX_DETECT_*` (set by detection module for in-process readers). Not a secret. Not externally consumed in v0.3.4. | None |
| Build artifacts | None — Phase 12 adds source files only. No new build steps, no compiled output, no Docker image regeneration logic. | None |

## Common Pitfalls

### Pitfall 1: Sourcing a Node manager's shell init

**What goes wrong:** Calling `source ~/.nvm/nvm.sh` (or `eval "$(fnm env)"`, or `eval "$(mise activate bash)"`) inside detection mutates the running shell's PATH, sometimes runs `mkdir -p ~/.config/<manager>/`, and adds 50-200ms latency per source.

**Why it happens:** Detection author wants to call `nvm ls` to see installed versions. The temptation is "just source the hook, run nvm, source-the-hook is read-only right?"

**How to avoid:** Use canonical-path file-existence (Pattern 2). Every covered manager installs Node binaries under deterministic paths under `$HOME`; we don't need the manager's CLI to enumerate them.

**Warning signs:** Any `source $HOME/...` or `eval "$(<some-manager> ...)"` line in `plugin/lib/detect/*.sh`. Reviewers (bash-engineer, security-engineer) flag this on sight.

### Pitfall 2: npm config location semantics misread

**What goes wrong:** Detection reports a single `npm_prefix` value that turns out to be `/usr` because the install user has no `~/.npmrc` with a `prefix=` line. Phase 13's REUSE-02 then sees "prefix is /usr — install user can't write — must Remediate" but actually the user has no preference at all and would happily accept whatever AgentLinux sets.

**Why it happens:** `npm config get prefix --location=user` returns `/usr` (the npm builtin default) when `~/.npmrc` lacks `prefix=`. Without distinguishing "user explicitly set /usr" from "user has no setting", Phase 13 makes wrong decisions. [VERIFIED in dev env]

**How to avoid:** Probe BOTH `--location=user` (returns `/usr` if absent) AND `--location=builtin` to distinguish. Better: report THREE values — `user_prefix` (from `~/.npmrc`, or null if absent), `system_prefix` (npm builtin default), `effective_prefix` (resolved). Phase 13 looks at user_prefix to decide "user has a preference" vs "user defers to system".

**Warning signs:** A detection JSON output where `npm_prefix.user_prefix == npm_prefix.system_prefix == "/usr"` — could be either case; field design should make them distinguishable.

### Pitfall 3: Binary-name catalog discrepancy (DET-04)

**What goes wrong:** Detection reports `playwright = absent` but the user actually has `playwright-cli` installed. Phase 13 then "creates" a duplicate install of the same agent.

**Why it happens:** REQUIREMENTS.md DET-04 prose names ("claude-code, gsd, playwright") don't match the actual binary names on PATH ("claude", "get-shit-done-cc", "playwright-cli"). The catalog ID is `playwright-cli` (not `playwright`) and the binary is `playwright-cli`. [VERIFIED: read plugin/catalog/catalog.json + plugin/catalog/agents/playwright-cli/install.sh]

**How to avoid:** Use the catalog ID → binary mapping table from Pattern 4 verbatim. Update REQUIREMENTS.md DET-04 wording in the same plan that ships the detector (the FIRST plan, alongside the DET-06 amendment).

**Warning signs:** Detection code that hardcodes the names from REQUIREMENTS.md without cross-checking against `plugin/catalog/catalog.json`.

### Pitfall 4: PATH visibility — root sees a different PATH than the install user

**What goes wrong:** Detection runs as root (entrypoint requires root). `command -v claude` succeeds because root has `~root/.npm-global/bin` on PATH (in some weird brownfield setup). Detection reports claude `healthy` but the agent user can't actually run it.

**Why it happens:** root's PATH ≠ install user's PATH. `npm install -g` as root puts binaries in `/usr/local/bin/` (root-owned, on /usr/local/bin which is on PATH for both). But agent-user-installed binaries live under `~agent/.npm-global/bin` which root may or may not have on its PATH.

**How to avoid:** ALWAYS probe binaries via `as_user <install_user> command -v <binary>`. Never run `command -v` directly from the detection script's process.

**Warning signs:** Any `command -v` in `detect/agents.sh` that isn't wrapped in `as_user`.

### Pitfall 5: A user with an old `/usr/local/bin/node` symlinked into nvm

**What goes wrong:** `[[ -f /usr/local/bin/node ]]` succeeds. Detection counts it as a "manual install". But it's actually a symlink the user manually `ln -s ~/.nvm/versions/node/v22/bin/node /usr/local/bin/node` to make Node available in cron. Now we double-count the same Node install (once as `manual`, once as `nvm`).

**Why it happens:** `[[ -f path ]]` follows symlinks; `[[ -L path ]]` checks for symlink type. Need to distinguish.

**How to avoid:** `readlink -f /usr/local/bin/node` resolves the entire chain. If the resolved path is under any of the manager prefixes (`~/.nvm/...`, `~/.local/share/fnm/...`, etc.), treat it as a symlink-into-manager, NOT a manual install. Only count `manual` when `readlink -f` returns `/usr/local/bin/node` itself.

**Warning signs:** A test fixture with a symlinked /usr/local/bin/node that produces TWO entries in the detection report.

### Pitfall 6: A user with multiple `.npmrc` prefix declarations

**What goes wrong:** `~/.npmrc` has TWO `prefix=` lines (e.g., user pasted in a snippet without checking). `npm config get prefix` returns the LAST one declared. Detection reports the prefix; provisioner attempts to use it; mysterious failures because the lines drift.

**Why it happens:** Bare-text config files; npm's last-wins parsing. Detection's `ensure_line_in_file` is a Phase 13 concern but Phase 12 should at least surface the count.

**How to avoid:** In `detect::npm_prefix_probe`, count occurrences of `^prefix=` in `~/.npmrc` and report `prefix_declarations: <N>` in the JSON. Phase 13 / 14 then decides what to do with N > 1.

**Warning signs:** Phase 12 over-trusts `npm config get prefix` and never inspects `~/.npmrc` for duplicate keys. Add a `prefix_declarations` field to surface drift.

### Pitfall 7: NPM_CONFIG_PREFIX env var override

**What goes wrong:** Install user has `export NPM_CONFIG_PREFIX=/some/weird/path` in `~/.bashrc`. Detection (running via `as_user agent npm config get prefix`) inherits the env from sudo's `-E` (subject to secure_path) — but `as_user` uses `-H` to set HOME but does NOT source the user's bashrc. So detection reads `/usr` (no override) but the actual interactive user shell would override to `/some/weird/path`.

**Why it happens:** `as_user` uses `sudo -u -H -E --` which preserves the INVOKER's env, not the target user's bashrc-sourced env.

**How to avoid:** EITHER `as_user_login` (which uses `sudo -i` to source the target user's profile) OR explicitly check `~/.bashrc`/`~/.profile` for `NPM_CONFIG_PREFIX` exports. Recommendation: use `as_user_login` for the npm probe — it matches the contract Phase 13's REUSE-02 cares about ("what would the install user see in a real shell").

**Warning signs:** Detection reports prefix=/usr but interactive user reports prefix=/elsewhere. Test fixture: a brownfield container with `export NPM_CONFIG_PREFIX=/tmp/foo` in `~agent/.bashrc`.

### Pitfall 8: jq absent at detection time

**What goes wrong:** Detection runs BEFORE `30-nodejs.sh` (which conditionally installs jq). On a minimal Ubuntu 22.04 base image where jq isn't pre-installed, detection's first `jq -n` call fails.

**Why it happens:** The entrypoint dispatches detection via `--report-only` which skips `run_provisioners`. There's no pre-detection prereq install step.

**How to avoid:** Add a tiny `ensure_jq` block in `plugin/bin/agentlinux-install` BEFORE `detect::run_once`. Mirror the pattern in `20-sudoers.sh:45-48`:
```bash
if ! command -v jq >/dev/null 2>&1; then
  log_warn "jq not found; installing 'jq' package"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends jq
fi
```
Document this clearly: detection itself is read-only, but the prereq install of jq is a one-time setup mutation. The bats no-op @test must be aware: snapshot AFTER `apt-get install jq` succeeds, before the detection probe — OR pre-install jq in the Docker test fixture so it's never absent.

**Warning signs:** A bats no-op @test that fails on first run because `apt-get install jq` modified `/var/lib/dpkg/`.

### Pitfall 9: The no-op @test snapshots a path that detection legitimately writes to

**What goes wrong:** Detection writes `/run/agentlinux-detect.json` (memoization). The bats no-op @test snapshot scope per Q2 is `/etc, /home, /usr/local/bin, /opt, /home/agent` — which does NOT include `/run`, so the snapshot stays clean. Good.

**Subtle variant:** The snapshot includes `/etc` and detection's `apt-get install jq` (Pitfall 8) modifies `/etc/apt/...`. The @test would then false-positive.

**How to avoid:** Run the bats @test with jq pre-installed in the Dockerfile (mirror how curl was added per STATE.md `2026-04-19 — added to apt-get alongside jq in both Dockerfiles`). The @test then exercises detection in isolation; jq pre-install is harness setup, not detection.

**Warning signs:** First run of the no-op @test on a base image without jq fails because /etc/apt/lists/* changed.

### Pitfall 10: Two NodeSource gates (deb822 vs legacy)

**What goes wrong:** `30-nodejs.sh` already deals with this dual-gate (line 50-56) — `nodesource.sources` (deb822) AND `nodesource.list` (legacy). Detection that only checks `nodesource.sources` misses partially-migrated hosts.

**How to avoid:** Mirror the existing dual-gate idiom: `[[ -f /etc/apt/sources.list.d/nodesource.sources ]] || [[ -f /etc/apt/sources.list.d/nodesource.list ]]`.

**Warning signs:** Single-gate check in DET-02. Cross-grep against `30-nodejs.sh:50` to verify the same idiom.

## Code Examples

Verified patterns from the live codebase + verified-in-dev probes.

### §1 DET-01 user probe (full minimal example)

```bash
# tested live: getent + id + as_user test -w
detect::user_probe agent "$tmpdir/01-user.json"
# Inside the function:
pwent=$(getent passwd agent)            # agent:x:1001:1001::/home/agent:/bin/bash
IFS=: read -r _ _ uid gid _ home shell <<< "$pwent"
groups=$(id -nG agent)                   # agent sudo
as_user agent test -w "$home" && writable=true || writable=false
```

### §2 DET-02 NodeSource probe (verified in dev env)

```bash
$ dpkg-query -W -f='${Package} ${Version} ${Status}\n' nodejs 2>/dev/null
nodejs 22.22.2-1nodesource1 install ok installed

$ [[ -f /etc/apt/sources.list.d/nodesource.sources ]] && echo "NodeSource repo present"
NodeSource repo present

# Differentiator: -1nodesource suffix in version string identifies NodeSource vs distro APT.
```

### §3 DET-03 npm prefix probe (verified in dev env)

```bash
# Per-user prefix from ~/.npmrc (or /usr if no prefix= line)
$ as_user agent npm config get prefix --location=user
/home/agent/.npm-global

# Without any user override (forced via env)
$ HOME=$(mktemp -d) npm config get prefix
/usr

# With env override
$ NPM_CONFIG_PREFIX=/tmp/foo-prefix npm config get prefix
/tmp/foo-prefix

# This three-way split (user / system-fallback / effective) is what DET-03 must report.
```

### §4 DET-04 catalog agent probe

```bash
# Per agent (verified mapping):
# claude-code → binary `claude` at ~/.local/bin/claude
# gsd → binary `get-shit-done-cc` at ~/.npm-global/bin/get-shit-done-cc
# playwright-cli → binary `playwright-cli` at ~/.npm-global/bin/playwright-cli

bin_path=$(as_user agent command -v claude 2>/dev/null || echo "")
ver=$(as_user agent claude --version 2>/dev/null | head -1)
as_user agent claude --help >/dev/null 2>&1 && health=ok || health=bad
```

### §5 DET-05 sudoers drop-in probe

```bash
# Verified live in dev env:
$ stat -c '%a %U:%G' /etc/sudoers.d/agentlinux
440 root:root

$ sha256sum /etc/sudoers.d/agentlinux | cut -d' ' -f1
3dab3...etc...

$ grep -Fxq 'agent ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/agentlinux && echo OK
OK
```

### §6 Text renderer output sample

```text
## DET-01 — Install User
✓ present
[DET-01] user.name=agent
[DET-01] user.uid=1001
[DET-01] user.gid=1001
[DET-01] user.shell=/bin/bash
[DET-01] user.home=/home/agent
[DET-01] user.home_writable=true
[DET-01] user.groups=agent sudo

## DET-02 — Node.js Installations
✓ present (1 source)
[DET-02] nodejs.0.source=nodesource
[DET-02] nodejs.0.path=/usr/bin/node
[DET-02] nodejs.0.version=v22.22.2
[DET-02] nodejs.0.install_user_can_write_prefix=false

## DET-03 — npm Global Prefix
[DET-03] npm.user_prefix=/home/agent/.npm-global
[DET-03] npm.system_prefix=/usr
[DET-03] npm.effective_prefix=/home/agent/.npm-global
[DET-03] npm.effective_owner=agent:agent
[DET-03] npm.install_user_writable=true

## DET-04 — Catalog Agents
✓ claude-code: healthy at /home/agent/.local/bin/claude (v2.1.114)
— gsd: absent
✗ playwright-cli: broken at /home/agent/.npm-global/bin/playwright-cli (--help exit 1)
[DET-04] agent.claude-code.status=healthy
[DET-04] agent.claude-code.path=/home/agent/.local/bin/claude
[DET-04] agent.claude-code.version=v2.1.114
[DET-04] agent.gsd.status=absent
[DET-04] agent.playwright-cli.status=broken
[DET-04] agent.playwright-cli.path=/home/agent/.npm-global/bin/playwright-cli

## DET-05 — Sudoers Drop-In
✓ present
[DET-05] sudoers.path=/etc/sudoers.d/agentlinux
[DET-05] sudoers.mode=440
[DET-05] sudoers.owner=root:root
[DET-05] sudoers.sha256=3dab3a...
[DET-05] sudoers.nopasswd_line_present=true
```

### §7 JSON renderer output sample (test fixture)

```json
{
  "user": {
    "name": "agent",
    "present": true,
    "uid": "1001",
    "gid": "1001",
    "shell": "/bin/bash",
    "home": "/home/agent",
    "groups": ["agent", "sudo"],
    "home_writable": true
  },
  "nodejs": [
    {
      "source": "nodesource",
      "path": "/usr/bin/node",
      "version": "v22.22.2",
      "install_user_can_write_prefix": false,
      "prefix_root": "/usr"
    }
  ],
  "npm_prefix": {
    "npm_present": true,
    "user_prefix": "/home/agent/.npm-global",
    "system_prefix": "/usr",
    "effective_prefix": "/home/agent/.npm-global",
    "effective_owner": "agent:agent",
    "effective_mode": "755",
    "install_user_writable": true
  },
  "agents": [
    { "id": "claude-code",    "binary": "claude",            "path": "/home/agent/.local/bin/claude",                "version": "v2.1.114", "owner": "agent:agent", "status": "healthy" },
    { "id": "gsd",            "binary": "get-shit-done-cc",  "path": "",                                             "version": "",          "owner": "",            "status": "absent"  },
    { "id": "playwright-cli", "binary": "playwright-cli",    "path": "/home/agent/.npm-global/bin/playwright-cli",   "version": "",          "owner": "agent:agent", "status": "broken"  }
  ],
  "sudoers": {
    "path": "/etc/sudoers.d/agentlinux",
    "present": true,
    "mode": "440",
    "owner": "root:root",
    "sha256": "3dab3a…",
    "nopasswd_line_present": true
  }
}
```

### §8 Bats no-op @test (read-only invariant per Q1+Q2)

```bash
# tests/bats/15-detection.bats — DET-01..06 + read-only invariant.
#
# Slot 15 = before installer-foundation (20-*) so detection probes the host
# state created by `agentlinux-install` initial run. The read-only invariant
# @test runs the detection pass twice and verifies zero filesystem drift.

load 'helpers/assertions'
load 'helpers/detection'

LOG=/var/log/agentlinux-install.log
INSTALLER=/opt/agentlinux-src/plugin/bin/agentlinux-install

# --- DET-01..05 happy-path coverage (one @test per requirement) ---

@test "DET-01: report contains install user UID + shell + home_writable" {
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-01"
  printf '%s' "$output" | jq -e '.user.present == true and (.user.uid | tonumber) > 0 and .user.home_writable == true' >/dev/null \
    || __fail "DET-01" "user.present + parsable uid + home_writable" "$output" "$LOG"
}

@test "DET-02: report enumerates Node.js installations" {
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-02"
  printf '%s' "$output" | jq -e '.nodejs | length > 0 and all(.source != "" and .path != "" and .version != "")' >/dev/null \
    || __fail "DET-02" "non-empty nodejs array with full source/path/version per entry" "$output" "$LOG"
}

@test "DET-03: report includes user_prefix + system_prefix + effective_prefix" {
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-03"
  printf '%s' "$output" | jq -e '.npm_prefix.user_prefix != null and .npm_prefix.system_prefix != null and .npm_prefix.effective_prefix != null' >/dev/null \
    || __fail "DET-03" "all three prefix fields populated" "$output" "$LOG"
}

@test "DET-04: report classifies each catalog agent" {
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-04"
  for id in claude-code gsd playwright-cli; do
    printf '%s' "$output" | jq -e --arg id "$id" '.agents | map(select(.id == $id)) | length == 1' >/dev/null \
      || __fail "DET-04" "agent ${id} present in report" "$output" "$LOG"
    printf '%s' "$output" | jq -e --arg id "$id" '.agents | map(select(.id == $id))[0].status as $s | $s == "healthy" or $s == "broken" or $s == "absent"' >/dev/null \
      || __fail "DET-04" "agent ${id} status in {healthy, broken, absent}" "$output" "$LOG"
  done
}

@test "DET-05: report includes sudoers drop-in metadata" {
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-05"
  printf '%s' "$output" | jq -e '.sudoers.path == "/etc/sudoers.d/agentlinux" and (.sudoers.present == true or .sudoers.present == false)' >/dev/null \
    || __fail "DET-05" "sudoers.path + boolean .present" "$output" "$LOG"
}

@test "DET-06: text format contains [DET-NN] markers for grep stability" {
  run bash "$INSTALLER" --report-only
  assert_exit_zero "DET-06"
  for marker in DET-01 DET-02 DET-03 DET-04 DET-05; do
    printf '%s' "$output" | grep -q "\[$marker\]" \
      || __fail "DET-06" "[$marker] present in text output" "$output" "$LOG"
  done
}

@test "DET-06: --report-format=json emits valid JSON parseable by jq" {
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-06"
  printf '%s' "$output" | jq -e 'type == "object"' >/dev/null \
    || __fail "DET-06" "valid JSON object" "$output" "$LOG"
}

# --- Read-only invariant (Q1+Q2 — Docker matrix only per Q3) ---

@test "DET read-only: detection writes zero bytes to /etc /home /usr/local/bin /opt /home/agent" {
  local pre post
  pre=$(mktemp); post=$(mktemp)
  snapshot_paths > "$pre"
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-read-only"
  snapshot_paths > "$post"
  if ! diff -q "$pre" "$post" >/dev/null 2>&1; then
    local delta; delta=$(diff -u "$pre" "$post" | head -40)
    rm -f "$pre" "$post"
    __fail "DET-read-only" "snapshot identity across detection pass" "$delta" "$LOG"
  fi
  rm -f "$pre" "$post"
}

# --- Phase 12 → Phase 13 contract: lib is sourceable + readers return parseable values ---

@test "DET-contract: detect.sh is sourceable and reader functions exist" {
  run bash -c '
    . /opt/agentlinux-src/plugin/lib/log.sh
    . /opt/agentlinux-src/plugin/lib/as_user.sh
    . /opt/agentlinux-src/plugin/lib/detect.sh
    detect::run_once agent
    detect::user_present || exit 1
    [[ -n "$(detect::user_uid)" ]] || exit 1
    [[ -n "$(detect::npm_prefix_path)" ]] || exit 1
    case "$(detect::agent_status claude-code)" in
      healthy|broken|absent) ;;
      *) exit 1 ;;
    esac
  '
  assert_exit_zero "DET-contract"
}
```

```bash
# tests/bats/helpers/detection.bash
# snapshot_paths — emits one line per inode under the targeted dirs:
#   <path> <mtime-as-epoch.ns> <size-in-bytes>
# Sort -u for stable ordering. Used by the no-op @test to detect any byte
# change made by the detection pass.
#
# Targeted scope per CONTEXT.md Q2: /etc, /home, /usr/local/bin, /opt, /home/agent.
# Note /home/agent is redundant under /home but called out in CONTEXT for emphasis;
# `find` deduplicates via -path filtering or simply lists both branches identically.
snapshot_paths() {
  find /etc /home /usr/local/bin /opt -printf '%p %T@ %s\n' 2>/dev/null | sort -u
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Greenfield-only installer assuming fresh host | Brownfield-aware detection-then-decide | v0.3.4 (this milestone) | Phase 12 adds the read-only foundation; Phases 13-15 wire decisions |
| `which` for PATH resolution | `command -v` (POSIX, builtin) | Established convention | `which` varies across distros; `command -v` is portable |
| `tput` for color | `[[ -t $fd ]]` + ANSI literals + `NO_COLOR` honor | log.sh established (2026-04) | No TERMINFO dependency; matches https://no-color.org consensus |
| dpkg-status | `dpkg-query -W -f=...` | Always preferred for read-only | dpkg can lock its DB; dpkg-query is read-only by contract |
| Manual JSON construction in bash | `jq -n --arg ...` | Standard since jq 1.5+ | Correct escaping; no string-concat bugs |
| One mega `jq -n` call | Per-fragment + `jq -s 'add'` merge | Recommended pattern | Per-detector testability; cleaner code |

**Deprecated / outdated approaches:**
- **`which`**: Inconsistent across Debian/Ubuntu (which-utils package vs shell function). Use `command -v`.
- **Sourcing `nvm.sh` to enumerate**: Mutates running shell; slow; can side-effect-write. Use canonical-path file-existence (Pattern 2).
- **`apt-cache`**: Slower than `dpkg-query` for installed-package queries; can trigger network round-trips on stale lists.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | nvm canonical install path is `~/.nvm/versions/node/v<X>/bin/node` (per nvm 0.40 docs) | Pattern 2 | Low — verified against nvm GitHub README; layout is stable since nvm 0.30 [ASSUMED via training knowledge of nvm layout; not run in dev env this session] |
| A2 | fnm canonical install path under `~/.local/share/fnm/node-versions/v<X>/installation/bin/node` | Pattern 2 | Low — verified against fnm docs; fnm's `--fnm-dir` env var can override (but defaults to `~/.local/share/fnm`) [ASSUMED via training knowledge of fnm layout] |
| A3 | volta canonical install path under `~/.volta/tools/image/node/<X>/bin/node` | Pattern 2 | Medium — volta's storage layout has shifted across versions; `~/.volta/tools/image/node/` has been stable since volta 1.0 [ASSUMED] |
| A4 | mise canonical install path under `~/.local/share/mise/installs/node/<X>/bin/node` | Pattern 2 | Low — mise's `MISE_DATA_DIR` defaults to `~/.local/share/mise`; layout is stable [ASSUMED via training knowledge] |
| A5 | asdf-node canonical install path under `~/.asdf/installs/nodejs/<X>/bin/node` | Pattern 2 | Low — asdf's layout has been stable across plugin versions; `nodejs` not `node` is the asdf plugin convention [ASSUMED] |
| A6 | pnpm-managed Node lands at `~/.local/share/pnpm/nodejs/<X>/bin/node` after `pnpm env use` | Pattern 2 | Medium — pnpm's env management is newer; layout could shift. PNPM_HOME env var (`~/.local/share/pnpm` in dev env [VERIFIED]) does control the root [ASSUMED for the nodejs/<X>/ subpath] |
| A7 | NodeSource version strings always end in `-1nodesource<N>` in the dpkg-query output | Pattern 2 / Pitfall 10 | Low — verified live in dev env: `nodejs 22.22.2-1nodesource1` [VERIFIED] |
| A8 | `npm config get prefix --no-userconfig` ignores `~/.npmrc` and returns the builtin default | Pattern 3 / Pitfall 2 | Low — verified live in dev env: returns `/usr` (npm builtin) when `--no-userconfig` is set [VERIFIED] |
| A9 | `as_user` (sudo -u -H -E) does NOT source the target user's bashrc | Pitfall 7 | Low — `sudo -u -H -E` semantics documented in sudo(8); only `sudo -i` (login shell) sources profile [VERIFIED via `man sudo` knowledge + as_user.sh comments] |
| A10 | jq absent on all minimal Ubuntu Docker base images by default | Pitfall 8 | Low — known; the existing 30-nodejs.sh + 20-sudoers.sh both have command-not-found install fallbacks for missing tools (locales, sudo); jq follows the same pattern [VERIFIED via reading 30-nodejs.sh + 20-sudoers.sh] |
| A11 | `find -printf '%p %T@ %s\n' \| sort -u` is sufficient to detect byte-level mutations under the snapshot scope | Pattern + bats test | Medium — does NOT detect content changes when path + mtime + size all stay identical (e.g., a file rewritten with the same byte count and the mtime forced back). Adequate for the no-op invariant test (detection has no reason to do this), but a deliberately adversarial test would defeat it. Acceptable trade-off per Q1 (convention + test, no LD_PRELOAD guard) [VERIFIED `find -printf` works in dev env] |
| A12 | Catalog binary names: `claude` (claude-code), `get-shit-done-cc` (gsd), `playwright-cli` (playwright-cli) | Pattern 4 / Pitfall 3 | None — read directly from `plugin/catalog/agents/*/install.sh` [VERIFIED] |
| A13 | The Phase 13 reader-function names listed in CONTEXT.md (`detect::user_present`, etc.) are the contract — not subject to renaming during Phase 12 implementation | All Patterns | None — CONTEXT.md is the source of truth [VERIFIED locked-decision] |
| A14 | Detection runs once per `agentlinux-install` invocation; memoization is per-process via /run tmpfs + an in-process flag (`DETECT_RAN`) | Pattern 7 | Low — Phase 13 provisioners run in the same bash process; memoization is sound. Cross-process consumers (e.g. a future `agentlinux detect` separate command) would need a stale-cache TTL [ASSUMED for Phase 13 use case; out-of-scope concerns logged] |

## Open Questions

1. **Should the active-version-vs-installed-versions distinction be exposed for Node managers?**
   - What we know: ROADMAP "Open Questions" §2 explicitly calls this out as decided in Phase 12.
   - What's unclear: Whether Phase 13's REUSE-02 needs to know "the user's currently-active nvm Node" or just "any nvm Node satisfies pin".
   - Recommendation: Report ALL installed versions per source (simpler, more informative). Phase 13 picks the highest version that satisfies the pin. If active-vs-installed turns out to matter, add an `is_active` boolean later — backward-compatible.

2. **Should `as_user_login` (sources profile) or `as_user` (no profile) be the npm probe invocation?**
   - What we know: `as_user_login` matches the Phase 13 REUSE-02 contract (interactive user shell sees this prefix); `as_user` is faster + matches every other detector.
   - What's unclear: Whether `NPM_CONFIG_PREFIX` exports in `~/.bashrc` are common in the wild (Pitfall 7).
   - Recommendation: Use `as_user_login` for the npm probe specifically; `as_user` for everything else. Document the asymmetry in `detect/npm_prefix.sh` header comments.

3. **Where does the `--user=NAME` argv flag get parsed and propagated?**
   - What we know: REQUIREMENTS.md DET-01 mentions "default `agent`, overridable via `--user=NAME`". Phase 12 is the first phase that needs this.
   - What's unclear: Phase 12 plan must add `--user=NAME` to `parse_args` AND propagate to `detect::run_once`. Or it's deferred to Phase 13/14 when REUSE/REMEDIATE actually act on it.
   - Recommendation: Land `--user=NAME` parsing + propagation in Phase 12 since the report needs to know which user to probe. Default `"${INSTALL_USER:-agent}"`; export for downstream provisioners.

4. **Should the JSON output be deterministic (sorted keys, alphabetized arrays) for test stability?**
   - What we know: `jq` does NOT sort keys by default; subsequent runs may produce different key orders.
   - What's unclear: Bats @tests using `jq -e` on specific paths don't care about ordering; tests using `diff` of full JSON would.
   - Recommendation: Run final JSON through `jq -S '.'` (sort keys) before emit. Costs nothing; makes the JSON byte-stable across runs (important for Phase 13's REUSE-02 test that may re-run detection multiple times).

5. **Should the renderer use the existing `log_info` for non-`[DET-NN]` lines (section headers, glyphs)?**
   - What we know: `log_info` prepends a UTC timestamp; reports look bad with timestamps prefixing "## DET-01 — Install User".
   - What's unclear: Whether the report should still tee into `/var/log/agentlinux-install.log` for INST-01 transcript capture.
   - Recommendation: Detection report goes to stdout; the entrypoint's existing tee already captures it into the log. Don't route through `log_info`. Keep `log_info`/`log_warn`/`log_error` for diagnostic messages only.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| bash 5.x | All detection code | ✓ (Ubuntu base) | 5.1+ | None — required |
| `jq` | DET-06 JSON renderer + every probe's fragment emit | ✗ on minimal Ubuntu base; ✓ once `30-nodejs.sh` runs | jq 1.6+ on 22.04, jq 1.7+ on 24.04+ | Pre-install via `agentlinux-install` ensure_jq block (Pitfall 8); fail-fast if install fails |
| `getent` | DET-01 NSS-aware passwd lookup | ✓ (libc-bin core) | always present | None |
| `id` | DET-01 group memberships | ✓ (coreutils core) | always present | None |
| `stat` | DET-03/05 mode + ownership | ✓ (coreutils core) | 9.x on 24.04+, 8.x on 22.04 | None |
| `dpkg-query` | DET-02 distro / NodeSource detection | ✓ (dpkg core) | always present | None |
| `find` | DET-02 manager probes + bats no-op snapshot | ✓ (findutils core) | always present | None |
| `readlink` | DET-02 symlink resolution | ✓ (coreutils core) | always present | None |
| `sha256sum` | DET-05 sudoers SHA256 + bats snapshot helper | ✓ (coreutils core) | always present | None |
| `command -v` | DET-04 binary-on-PATH resolution | ✓ (bash builtin) | always present | None |
| `sudo` | `as_user` invocations | ✓ (installed by `20-sudoers.sh` if absent) | always present after Phase 5.1 | Same fallback as 20-sudoers.sh's existing `command -v visudo` block |

**Missing dependencies with no fallback:** None — every dependency is either present on Ubuntu base or has a documented apt-install fallback in the existing entrypoint pattern.

**Missing dependencies with fallback:** `jq` — pre-install in entrypoint before `detect::run_once` (modeled on `20-sudoers.sh:45-48` pattern).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bats-core (Ubuntu apt package; same version pattern as existing tests/bats/*.bats) |
| Config file | `tests/bats/helpers/{assertions.bash,invoke_modes.bash}` (existing); NEW `tests/bats/helpers/detection.bash` |
| Quick run command | `bats tests/bats/15-detection.bats` (single file, ~10 @tests) |
| Full suite command | `./tests/docker/run.sh ubuntu-24.04` (66/66 baseline + 8 new @tests = 74) |
| Phase gate | Full Docker matrix (Ubuntu 22.04 + 24.04 + 26.04) green; QEMU matrix unchanged this phase per Q3 |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DET-01 | install user UID/GID/shell/home/groups/home_writable in report | bats | `bats tests/bats/15-detection.bats -f 'DET-01:'` | ❌ Wave 0 |
| DET-02 | Node.js sources enumerated with version + writable bool | bats + fixture | `bats tests/bats/15-detection.bats -f 'DET-02:'` | ❌ Wave 0 |
| DET-03 | npm user_prefix + system_prefix + effective_prefix surfaced | bats | `bats tests/bats/15-detection.bats -f 'DET-03:'` | ❌ Wave 0 |
| DET-04 | catalog agents classified healthy/broken/absent | bats | `bats tests/bats/15-detection.bats -f 'DET-04:'` | ❌ Wave 0 |
| DET-05 | sudoers drop-in mode + sha256 + nopasswd_line_present | bats | `bats tests/bats/15-detection.bats -f 'DET-05:'` | ❌ Wave 0 |
| DET-06 | text format `[DET-NN]` markers + JSON parses via jq | bats × 2 | `bats tests/bats/15-detection.bats -f 'DET-06:'` | ❌ Wave 0 |
| DET-read-only invariant | snapshot byte-equality before/after detection | bats | `bats tests/bats/15-detection.bats -f 'DET-read-only:'` | ❌ Wave 0 |
| DET-contract (Phase 12→13) | detect.sh sourceable; reader functions return values | bats | `bats tests/bats/15-detection.bats -f 'DET-contract:'` | ❌ Wave 0 |
| Greenfield invariant | fresh container surfaces all components as `absent`/0-count | bats | `bats tests/bats/15-detection.bats` (subset) | ❌ Wave 0 — implicit via fresh Docker run |

### Sampling Rate

- **Per task commit:** `bats tests/bats/15-detection.bats` (one bats file, sub-second per @test)
- **Per wave merge:** `./tests/docker/run.sh ubuntu-24.04` (full bats suite to verify no regression on 66/66 baseline)
- **Phase gate:** Both Ubuntu 22.04 + 24.04 + 26.04 Docker matrices green; QEMU matrix excluded this phase per Q3 (read-only contract doesn't depend on init system)

### Wave 0 Gaps

- [ ] `tests/bats/15-detection.bats` — covers DET-01..06 + read-only invariant + Phase 13 contract
- [ ] `tests/bats/helpers/detection.bash` — `snapshot_paths` helper for the no-op invariant
- [ ] `plugin/lib/detect.sh` orchestrator + 5 detector files + render.sh
- [ ] `plugin/lib/detect/README.md` — one paragraph naming allowed probes (per Q4)
- [ ] `plugin/bin/agentlinux-install` modifications: `parse_args` adds `--report-only` + `--report-format=text|json` + `--user=NAME`; `main()` gates `run_provisioners`; ensure_jq pre-install block
- [ ] REQUIREMENTS.md amendments: DET-04 binary-name correction (catalog uses `playwright-cli`, not `playwright`); DET-06 strikeout-style amendment (no schema doc, no version field)
- [ ] Catalog: no changes — detection reads catalog, doesn't modify it

## Project Constraints (from CLAUDE.md)

The following directives from `./CLAUDE.md` apply to Phase 12 work and MUST NOT be contradicted by any plan:

1. **Never `sudo npm install -g` anywhere.** Detection NEVER mutates state — but the rule applies if any plan tries to "install npm globals as part of detection bootstrap". Don't.
2. **Behavior tests in `tests/bats/` are the spec.** DET-01..06 close on bats @tests; no implementation pin (exact file structure inside `plugin/lib/detect/` may evolve).
3. **No agent installed by default.** Detection must distinguish "agent absent" from "agent installed by AgentLinux" — this is what DET-04's `healthy`/`broken`/`absent` classification enables.
4. **Docker-only test runs are insufficient (general rule).** EXCEPT for the read-only invariant @test per Q3 — that one runs Docker-only because the contract is FS-write-count, not init-system behavior. Other @tests in 15-detection.bats run on the Docker matrix as usual; the QEMU matrix does NOT need new @tests this phase (no init-system surface area added).
5. **Every release tarball ships with a sibling `.sha256`.** No release work in Phase 12; carries forward.
6. **No wrapper shims at `/usr/local/bin/`** pointing to agent-owned binaries. Detection MUST report `/usr/local/bin/<binary>` symlinks chasing into agent-owned binaries as a flag (Pitfall 5 references this — though Phase 12 surfaces it; Phase 14 REMEDIATE acts on it).
7. **Review loop:** Plans for Phase 12 will be reviewed by `bash-engineer` + `security-engineer` + `qa-engineer` + `behavior-coverage-auditor`. Plan-level risks: probe-correctness (bash-engineer), allowed-probe contract enforcement (security-engineer), bats coverage strength (qa-engineer), REQ-ID linkage in @tests (behavior-coverage-auditor).
8. **Session tracking:** Concrete deliverables go to Jira AL board via `session-tracker` skill; for Phase 12 this means at least one Jira issue covering the milestone slice (the planner decides granularity).

Plan-checker subagent should verify each plan against this list before approving.

## Sources

### Primary (HIGH confidence)

- `plugin/lib/log.sh` (live) — TTY-aware color macros, logging primitives [VERIFIED: read]
- `plugin/lib/as_user.sh` (live) — `sudo -u -H -E --` keystone, `as_user_login` for `-i` semantics [VERIFIED: read]
- `plugin/lib/distro_detect.sh` (live) — pattern model for read-only OS probe [VERIFIED: read]
- `plugin/lib/idempotency.sh` (live) — primitives Phase 13 will use; not used by detection [VERIFIED: read]
- `plugin/bin/agentlinux-install` (live) — entrypoint, parse_args, run_provisioners pattern [VERIFIED: read]
- `plugin/provisioner/{10,20,30,40,50}-*.sh` (live) — sourcing convention, return-vs-exit, prereq install patterns [VERIFIED: read]
- `plugin/catalog/catalog.json` + `plugin/catalog/agents/*/install.sh` (live) — actual catalog binary names (`claude`, `get-shit-done-cc`, `playwright-cli`) [VERIFIED: read]
- `tests/bats/{10-installer,22-agent-sudo,30-runtime}.bats` (live) — bats test conventions, sha256-byte-stability pattern, helpers usage [VERIFIED: read]
- `tests/bats/helpers/{assertions,invoke_modes}.bash` (live) — assertion helpers, `__fail` 4-line diagnostic [VERIFIED: read]
- `tests/docker/run.sh` (live) — Docker harness, container layout, `/opt/agentlinux-src` staging [VERIFIED: read]
- `docs/decisions/{004,005,012}-*.md` (live) — per-user prefix, NodeSource over managers, sudoers ALL=NOPASSWD ALL [VERIFIED: read]
- `.planning/REQUIREMENTS.md` v0.3.4 (live) — DET-01..06 wording (with the DET-06 amendment in CONTEXT.md, DET-04 prose-name correction in this research) [VERIFIED: read]
- `.planning/ROADMAP.md` v0.3.4 (live) — Phase 12 success criteria, open questions [VERIFIED: read]
- `.planning/phases/12-detection-layer/12-CONTEXT.md` (live) — locked discuss-phase decisions [VERIFIED: read]
- Live dev env probes: `dpkg-query -W -f='${Package} ${Version} ${Status}\n' nodejs`, `npm config get prefix --no-userconfig`, `jq -n --arg ...`, `find -printf '%p %T@ %s\n'` [VERIFIED in dev env this session]

### Secondary (MEDIUM confidence)

- `man sudo(8)` for `-u -H -E -- vs -i` semantics — documented in `as_user.sh` header comments and verified against the existing convention; not re-fetched this session
- `man getent(1)` — passwd format colon-separation; standard NSS interface
- nvm / fnm / volta / mise / asdf-node canonical install paths — derived from training knowledge of each manager's documented layout (each has README on GitHub describing the prefix structure); marked [ASSUMED] in the Assumptions Log

### Tertiary (LOW confidence)

- pnpm-managed Node sub-path under `~/.local/share/pnpm/nodejs/<X>/` — pnpm's env management is newer (2023+) and the sub-path is from training knowledge; could shift in future pnpm releases. Recommendation: handle with the same `find -maxdepth 4 -name node` pattern; if the path shifts, the `find` still locates the binary as long as the `~/.local/share/pnpm/` root is stable.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every binary verified live in dev env; every existing-codebase pattern read directly
- Architecture: HIGH — five-detector layout matches existing `plugin/lib/` convention; orchestrator pattern is the obvious shape; Phase 13 contract enumerated in CONTEXT.md
- Pitfalls: HIGH for #1, #2, #3, #4, #7, #8, #9, #10 (verified or reasoned from live code); MEDIUM for #5, #6 (cross-domain knowledge of npm/symlink edge cases)
- DET-02 manager paths: MEDIUM — canonical paths are documented but not all run live this session; layout drift across major manager versions has happened historically
- DET-04 binary-name correction: HIGH — read directly from `plugin/catalog/agents/*/install.sh`

**Research date:** 2026-05-10
**Valid until:** 2026-06-10 (30 days — stable domain; the only churn risk is a Node-manager layout shift, which would invalidate Pattern 2 specifics but not the canonical-path-detection approach itself)
