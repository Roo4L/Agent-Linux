# Phase 12: Detection Layer - Context

**Gathered:** 2026-05-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the read-only discovery layer that pre-flight `agentlinux install` invocations call to enumerate every component AgentLinux owns on the host. Phase 12 ships:

1. A bash detection module under `plugin/lib/detect/` that probes: install user (default `agent`), Node.js installations across 8 covered sources, npm global prefix, catalog agents (claude-code, gsd, playwright), `/etc/sudoers.d/agentlinux` drop-in.
2. Two output paths: a default human-readable text report (TTY-aware ANSI coloring, `[DET-NN] key=value` markers for grep stability) and an undocumented `--report-format=json` mode for test consumption only (`jq -n` dump of the same data, no schema doc, no version field).
3. Two invocation surfaces on the bash entrypoint: `agentlinux-install --report-only` (run detection + render text + exit 0) and `--report-format=json` (orthogonal flag).
4. Bash readers (`detect::user_uid`, `detect::nodejs_count`, etc.) sourced by Phase 13 provisioners for in-process REUSE decisions.
5. A targeted "no-op" bats @test (Docker matrix only) that snapshots the documented host paths before+after a detection pass and asserts byte-equality.

Requirements in scope: DET-01..06.

Out of scope:
- `--dry-run` flag (Phase 15 / UX-01).
- Reuse short-circuit logic in provisioners (Phase 13).
- Remediate decisions / `--yes` flag / exit codes (Phase 14).
- Interactive prompts (Phase 15).
- README brownfield section (Phase 16).

</domain>

<decisions>
## Implementation Decisions

### Area 1: Detection Code Surface & Implementation Language (accepted as recommended)

- **Module location:** New `plugin/lib/detect/` directory with one file per detector (`user.sh`, `nodejs.sh`, `npm_prefix.sh`, `agents.sh`, `sudoers.sh`) plus a `detect.sh` orchestrator. Sits alongside existing `plugin/lib/{as_user,idempotency,distro_detect,log}.sh`.
- **Invocation:** Two surfaces on the bash entrypoint — `agentlinux-install --report-only` runs the orchestrator and exits 0; `--report-format=text|json` (default `text`) is an orthogonal flag honored by both `--report-only` and (later, Phase 15) `--dry-run`. The TS CLI's `agentlinux install <name>` is unchanged.
- **Renderer language:** Pure bash for text rendering (`plugin/lib/log.sh` style); JSON via `jq -n --arg ... '{...}'` (jq is already a transitive dep on Ubuntu via apt-utils; will hard-add as a pre-req in `30-nodejs.sh`'s prerequisite block if not already present).
- **Phase 13 handoff:** Detection writes to `/run/agentlinux-detect.json` (tmpfs, no persistence across reboot) AND exposes bash reader functions (`detect::user_uid`, `detect::nodejs_count`, `detect::agents_status_for <name>`) sourced via `plugin/lib/detect.sh`. Phase 13 provisioners source the lib and call readers — no JSON parse in bash.

### Area 2: JSON Output Shape (amended after discuss — option B chosen)

**DET-06 amended.** The original DET-06 mandated "stable JSON via `--report-format=json`; the JSON schema is documented and versioned, and a smoke test parses it via `jq` to extract every captured field." The user pushed back: humans don't read JSON; the only real consumer of JSON in v0.3.4 is bats tests that want structural assertions instead of regex against colored text. Schema docs / ADR / `schema_version` field were rejected as ceremony for hypothetical future consumers.

**Amended DET-06 (binding for this phase):**
> The detection report renders in a human-readable text format (default, TTY-aware color, `[DET-NN] key=value` markers for grep stability). An undocumented `--report-format=json` flag emits the same captured data as a `jq -n`-built object for test-only consumption. No JSON Schema document. No `schema_version` field. No ADR. Bats @tests parse via `jq` for structural assertions.

REQUIREMENTS.md will be updated in this phase's first plan to reflect the amendment with a strikeout on the original DET-06 wording and a 1-line "amended in Phase 12 discuss" footnote.

### Area 3: Text Format Design (accepted as recommended)

- **Color:** TTY-detect via `[ -t 1 ]`; ANSI escape literals (`\033[32m✓\033[0m` style); honor `NO_COLOR` env var (de-facto standard, https://no-color.org). No `tput`, no extra deps.
- **Section ordering:** ROADMAP success-criteria order — User → Node.js → npm prefix → Catalog agents → Sudoers. Matches the order users will read in REQUIREMENTS.md.
- **Field markers:** Per-field `[DET-NN] key=value` line prefix for grep stability. Example: `[DET-01] user.uid=1001 user.shell=/bin/bash user.home_writable=true`. One DET-NN section per detector, multiple lines if needed.
- **Verbosity:** Single output level. No `--verbose`/`--brief` flags. Add later if a real use case emerges.

### Area 4: Read-Only Verification Strategy (3 of 4 accepted; Q3 changed)

- **Q1 (enforcement):** Convention + dedicated bats @test that snapshots target paths before/after a detection pass and asserts byte-equality. No runtime FS-write guard (would add complexity).
- **Q2 (snapshot scope):** Targeted — `/etc`, `/home`, `/usr/local/bin`, `/opt`, `/home/agent` — captured via `find ... -printf '%p %T@ %s\n' | sort -u` (mtime + size + path). Direct from REQUIREMENTS criterion 8.
- **Q3 (where the @test runs) — CHANGED:** Docker matrix only (Ubuntu 22.04 + 24.04). User explicitly opted out of QEMU run for this @test — read-only-ness does not depend on systemd / locale / cloud-init paths, so QEMU buys nothing here. Project-level rule (CLAUDE.md "Docker-only test runs are insufficient ... QEMU suite must be green before any release") is unchanged; this specific @test is one of the cases where Docker is sufficient because the contract under test is FS-write-count, not init-system behavior.
- **Q4 (allowed probes):** Detection uses only non-mutating probes — `dpkg-query` (read-only) instead of `dpkg`, `apt list --installed` (read-only), `id`, `getent`, `stat`, `node --version`, `npm config get prefix`, `<agent> --version`. NEVER `apt-get update`, `apt install`, `npm install`, etc. The allowed-probe list is documented in `plugin/lib/detect/README.md` (one paragraph, no ADR ceremony) so reviewers know the rule.

### Phase 12 → Phase 13 contract

Phase 13's REUSE provisioners depend on:
1. `plugin/lib/detect.sh` exists and is sourceable.
2. Reader functions named `detect::user_present`, `detect::user_uid`, `detect::user_shell`, `detect::user_home_writable`, `detect::nodejs_satisfies_pin`, `detect::nodejs_prefix_writable`, `detect::npm_prefix_path`, `detect::npm_prefix_writable_by_install_user`, `detect::agent_status <name>` (returns `healthy`/`broken`/`absent`).
3. Detection has been run before any reader is called — provisioners call `detect::run_once` (memoized; first call probes, subsequent calls return cached results from `/run/agentlinux-detect.json`).

This contract belongs to Phase 12 and will be enforced by a Phase 12 bats test that sources the lib, runs `detect::run_once`, and asserts each reader returns parseable output.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- `plugin/lib/log.sh` — `log_info`, `log_warn`, `log_error` already TTY-aware. Read it before writing the detect renderer; reuse the color macros.
- `plugin/lib/distro_detect.sh` — existing pattern for read-only OS probe (cat /etc/os-release). Mirror its return-codes / function-naming style.
- `plugin/lib/as_user.sh` — `as_user` helper. Detection probes that need to run AS the install user (e.g., `npm config get prefix --location=user`) call `as_user agent npm config get prefix --location=user`.
- `plugin/lib/idempotency.sh` — has `ensure_marker_block` / `ensure_dir` patterns. Detection itself is read-only so won't use these, but the caller (post-Phase-13 provisioner) will.
- `plugin/cli/src/state/sentinel.ts` (TS, not bash) — pattern for detecting "is an agent installed" by sentinel file. Not directly reusable in bash but informs how `agents.sh` classifies `healthy`/`broken`/`absent`.
- `plugin/provisioner/{10-agent-user,30-nodejs,20-sudoers}.sh` — these contain the existing CREATE-path logic. Phase 13 will modify them to short-circuit when reuse is possible. Phase 12 only READS what they would have created.

### Established Patterns

- **Strict mode + ERR trap inheritance:** Provisioners and lib files are SOURCED from `plugin/bin/agentlinux-install` and inherit `set -euo pipefail` + ERR trap. Detection module follows the same pattern — no per-file `set` directives.
- **Logging convention:** All output via `log_info` / `log_warn` / `log_error` (ANSI-aware, TTY-detected). Detection renderer extends this with explicit `[DET-NN]` markers.
- **`return 1` vs `exit 1`:** Sourced files use `return 1` so the entrypoint's ERR trap captures src:line correctly (pattern from `30-nodejs.sh:71`).
- **Idempotency rule:** Re-running the entire entrypoint must converge (INST-02). Detection is naturally idempotent (read-only); the @test in Q3 enforces it.
- **Test convention:** Bats files numbered to match the provisioner they cover (`22-agent-sudo.bats` covers `20-sudoers.sh` etc.). Phase 12 adds `tests/bats/15-detection.bats` (slot 15 = before installer-foundation tests).

### Integration Points

- **Bash entrypoint:** `plugin/bin/agentlinux-install` parses argv. Phase 12 adds `--report-only` and `--report-format=text|json` flag handling. Existing dispatch loop (provisioners 10/20/30/40/50) is gated behind "not --report-only".
- **Provisioner consumers (Phase 13):** Provisioners 10/20/30 will source `plugin/lib/detect.sh` and short-circuit on `detect::*` returns. Phase 12 ships the lib + readers; Phase 13 wires the short-circuits.
- **CLI catalog (no integration this phase):** The TS CLI `agentlinux install <name>` is unchanged. Catalog-agent detection probes the same paths the recipes write to (`/usr/local/bin/<binary>` symlinks etc.) but the CLI itself doesn't change.

</code_context>

<specifics>
## Specific Ideas

- **DET-06 amendment must land before plan-phase finalizes:** First plan in Phase 12 includes a small REQUIREMENTS.md edit applying the amended DET-06 wording with a "Discuss-phase amendment 2026-05-10: dropped JSON schema doc + version field per smart-discuss; JSON is now test-only" footnote.
- **README for allowed probes:** `plugin/lib/detect/README.md` is one paragraph naming `dpkg-query`, `apt list --installed`, `id`, `getent`, `stat`, `node --version`, `npm config get prefix`, `<agent> --version`, with one sentence "if you add a probe, verify it doesn't write to /etc /home /usr/local/bin /opt /home/agent — the bats no-op test will catch you if it does."
- **Health-probe details for DET-04:** `claude --version` (check exit 0 + parseable semver), `get-shit-done-cc --help | head -1` (banner-grep for "GSD"), `playwright --version` (check exit 0 + parseable semver). Source: REQUIREMENTS.md DET-04 verbatim.

</specifics>

<deferred>
## Deferred Ideas

- **Schema doc + version field for the JSON output.** Rejected as ceremony — no real consumer beyond tests in v0.3.4. Re-open if a real external consumer emerges.
- **`--verbose` / `--brief` flags.** Not in scope; add only if a real use case appears.
- **Runtime FS-write guard (LD_PRELOAD or strace wrapper).** Considered, rejected for complexity; bats snapshot @test is sufficient.
- **Detection of arbitrary npm globals beyond catalog agents** (`npx`, `tsx`, `vercel`, `pnpm`). Out of scope per REQUIREMENTS.md "Future Requirements" — AgentLinux only owns its catalog.
- **QEMU run for the read-only @test.** User explicitly opted out; Docker is sufficient because the contract is FS-write-count, not init-system behavior.

</deferred>
