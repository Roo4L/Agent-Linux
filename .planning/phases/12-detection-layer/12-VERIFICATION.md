---
phase: 12
slug: detection-layer
verified: 2026-05-10
status: passed
score: 10/10
---

# Phase 12 — Detection Layer: Verification Report

## Summary

Phase 12 ships a fully-working, read-only host discovery layer. Empirical verification on Ubuntu 22.04 + 24.04 Docker matrix confirms 97/97 bats tests pass on both images, including all 24 Phase-12 `DET-*` tests (DET-01..06 plus the Plan 12-03 read-only invariant + greenfield meta-assertion). Goal-backward analysis verifies every observable truth in the phase goal: enumeration of install user, 8 Node.js sources, 3-value npm prefix, 3 catalog agents (claude-code → claude, gsd → get-shit-done-cc, playwright-cli → playwright-cli), sudoers drop-in metadata + drift, and dual text/JSON output with `[DET-NN] key=value` markers and locked top-level JSON shape `{generated_at, host, components}` — emitted without writing any byte to `/etc /home /usr/local/bin /opt`.

All 6 must-have REQ-IDs (DET-01..06) are marked `Complete` in REQUIREMENTS.md. The DET-04 binary-name amendment (`playwright-cli`, not `playwright`) and DET-06 ceremony-strikeout amendment (no `schema_version`, no `$schema`, no committed JSON Schema doc, no ADR-013) are present in REQUIREMENTS.md with the "Phase 12 discuss (2026-05-10)" footnote and are enforced at runtime by a dedicated bats `@test` that asserts the JSON top-level object lacks all three forbidden fields. No `sudo npm install -g` anywhere in `plugin/lib/detect/`. No `/usr/local/bin/` wrapper shims to agent-owned binaries are created (only read-only `/usr/local/bin/node` probe via `readlink -f`). The phase delivers the locked Phase 12 → Phase 13 contract (`detect::user_*`, `detect::nodejs_*`, `detect::npm_prefix_*`, `detect::agent_status`, `detect::run_once`) ready for Phase 13 REUSE consumption.

## Goal-Backward Analysis

Each must-have empirically verified against the codebase, not against SUMMARY claims.

| # | Must-have | Status | Evidence |
|---|-----------|--------|----------|
| 1 | DET-01: user probe captures UID/GID/shell/home/groups/home_writable | VERIFIED | `plugin/lib/detect/user.sh:35-86` — `detect::user_probe` uses `getent passwd`, `id -nG`, `as_user $user test -w "$home"` (Pitfall 4 — root sees every dir writable). JSON fragment emitted via `jq -n --arg/--argjson` (T-12-02 safe). Bats tests #11, #12 (json + text) pass on both matrices. |
| 2 | DET-02: nodejs probe enumerates 8+ sources without sourcing manager init | VERIFIED | `plugin/lib/detect/nodejs.sh:88-155` — NodeSource (dual-gate Pitfall 10), distro APT, manual `/usr/local/bin/node` with `readlink -f` self-equality dedup (Pitfall 5), per-user managers nvm/fnm/volta/mise/asdf/pnpm via `find -maxdepth N -name node -type f` — never sources `nvm.sh` / `fnm env` / `mise activate`. Bats tests #18, #19, #20 (NodeSource present, nvm fixture present, symlink-no-double-count) pass. |
| 3 | DET-03: npm prefix surfaces user/system/effective 3-value via as_user_login | VERIFIED | `plugin/lib/detect/npm_prefix.sh:53-162` — three values via `npm config get prefix --location=user`, `env NPM_CONFIG_PREFIX= npm config get prefix --no-userconfig`, and `npm config get prefix`. All three invocations gated through `as_user_login` (sudo -i, login shell — Pitfall 7) so user-shell `NPM_CONFIG_PREFIX` exports propagate. `prefix_declarations` counter disambiguates `/usr-because-empty` from `/usr-explicitly-set` (Pitfall 6). npm log-file silencing via `env npm_config_logs_max=0 npm_config_loglevel=silent` (Plan 12-03 Rule 1 fix). Bats tests #21, #22 (sentinel via NPM_CONFIG_PREFIX user-shell export), #23 pass. |
| 4 | DET-04: catalog classifier maps id→binary verbatim, uses as_user_login PATH probe | VERIFIED | `plugin/lib/detect/agents.sh:51-55` — `DETECT_AGENT_BINARIES=([claude-code]=claude [gsd]=get-shit-done-cc [playwright-cli]=playwright-cli)` matches `plugin/catalog/catalog.json` verbatim. PATH probe via `as_user_login "$user" command -v "$binary"` (Plan 12-02 Rule 1 fix — bare `as_user` uses sudo's secure_path which omits `/home/agent/.local/bin` + `/home/agent/.npm-global/bin`). Three-state classifier {healthy, broken, absent}. `test-dummy` explicitly excluded (`test_only: true`). Bats tests #24, #25, #26, #27 (healthy / banner-grep / absent / broken-when-help-non-zero) pass. |
| 5 | DET-05: sudoers drop-in metadata + drift, never writes | VERIFIED | `plugin/lib/detect/sudoers.sh:31-90` — `DETECT_SUDOERS_PATH=/etc/sudoers.d/agentlinux` and `DETECT_SUDOERS_EXPECTED_LINE='agent ALL=(ALL) NOPASSWD: ALL'` are LOCKED `readonly` constants mirroring ADR-012. Probe uses only `stat -c '%a' / '%U:%G'`, `sha256sum`, `grep -Fxq -- "$LINE"` — never `visudo`, `install`, `chmod`, `>` redirect. Bats tests #13, #14 (metadata + sudoers SHA256 byte-stable across pass) pass. |
| 6a | DET-06: text format with `[DET-NN] key=value` markers, TTY/NO_COLOR aware | VERIFIED | `plugin/lib/detect/render.sh:36-189` — `__det_color` checks `[[ -t $fd ]]` and `${NO_COLOR:-}`. `__det_field` emits `[DET-NN] key=value` lines. Section headers `## DET-NN — Title` per detector. Bats #29 grep-asserts `\[DET-01\] user\.uid=`, `\[DET-02\] nodejs\.`, `\[DET-03\] npm\.`, `\[DET-04\] agent\.claude-code\.status=`, `\[DET-05\] sudoers\.path=`. NO_COLOR + non-TTY ANSI strip enforced by #32 + #33 (zero ESC bytes counted via `LC_ALL=C grep -c $'\033\['`). |
| 6b | DET-06: JSON format via `--report-format=json`, parseable by jq, locked shape | VERIFIED | `plugin/lib/detect/render.sh:213-253` — `detect::render_json` builds `{generated_at, host: {os, version}, components: <cache>[0]}` via `jq -n -S --arg/--slurpfile` exclusively (T-12-02 mitigation by construction). `jq -S` sorts keys for byte-stability. Bats #15, #30 verify top-level object + every captured field reachable + `components.{user,npm_prefix,sudoers,nodejs[],agents[]}` reachable + agents has all 3 catalog ids. |
| 6c | DET-06 amendment: NO `schema_version` / `$schema` / `version` / committed Schema / ADR-013 | VERIFIED | grep `schema_version` across `plugin/` finds zero matches. `find -name "*.schema.json"` finds zero files. `docs/decisions/013-license-mit.md` is unrelated to JSON schema. Bats #31 grep-asserts `has("schema_version") == false and has("$schema") == false and has("version") == false` on JSON output. REQUIREMENTS.md DET-06 has `<del>` strikeout on old wording + amendment with "Phase 12 discuss (2026-05-10)" footnote. |
| 7 | Read-only invariant: detection writes zero bytes to /etc /home /usr/local/bin /opt | VERIFIED | `tests/bats/helpers/detection.bash:17-19` — `snapshot_paths()` uses `find -printf '%p %T@ %s\n' | sort -u`. Bats #28 snapshots before/after a full `--report-only` pass and asserts `diff -q` empty. Plan 12-03 Rule 1 fix silences npm `~/.npm/_logs/*-debug-N.log` writes. `plugin/lib/detect/README.md` documents the allowed-probe contract. Docker-only enforcement per CONTEXT.md Area 4 Q3. |
| 8 | Greenfield invariant: v0.3.0 baseline preserved + bats matrix green | VERIFIED | Empirical run: `./tests/docker/run.sh ubuntu-24.04` → 97/97 PASS, exit 0. `./tests/docker/run.sh ubuntu-22.04` → 97/97 PASS, exit 0. Bats #34 meta-assertion: `15-detection.bats` has ≥17 @tests (actual: 24). No pre-Phase-12 test regressed. |
| 9 | CLAUDE.md compliance | VERIFIED | No `sudo npm install -g` in `plugin/lib/detect/*` (grep zero matches). No `/usr/local/bin/` shim writes in detect — only `readlink -f` self-equality READ probe at `nodejs.sh:113-116`. All bats `@test` names reference REQ-IDs (`@test "DET-NN: ..."`). Read-only enforcement via convention + bats snapshot @test (CONTEXT.md Q1). |
| 10 | Phase 12 → Phase 13 reader contract | VERIFIED | `detect::user_present`, `detect::user_uid`, `detect::user_shell`, `detect::user_home_writable` (user.sh:92-95); `detect::nodejs_satisfies_pin`, `detect::nodejs_prefix_writable` (nodejs.sh:162-189); `detect::npm_prefix_path`, `detect::npm_prefix_writable_by_install_user` (npm_prefix.sh:168-171); `detect::agent_status` (agents.sh:185-191); `detect::run_once` memoized via `DETECT_RAN=1` + `/run/agentlinux-detect.json` (detect.sh:71-109). All readers consume exported `DETECT_*` variables — no JSON parse in bash readers. |

**Score: 10/10 must-haves verified.**

## Test Results

### Ubuntu 24.04 — `./tests/docker/run.sh ubuntu-24.04`

```
1..97
ok 1..97 (all 97 tests pass)
EXITCODE=0
```

### Ubuntu 22.04 — `./tests/docker/run.sh ubuntu-22.04`

```
1..97
ok 1..97 (all 97 tests pass)
EXITCODE=0
```

### Phase 12 DET-* tests (identical results on both matrices)

```
ok 11 DET-01: --report-only --report-format=json reports install user UID + shell + home_writable
ok 12 DET-01: text format includes [DET-01] markers for user.uid + user.shell + user.home
ok 13 DET-05: sudoers drop-in metadata captured (path + present + sha256 + nopasswd_line_present)
ok 14 DET-05: sudoers file SHA256 unchanged across detection pass (read-only invariant on sudoers)
ok 15 DET-06: --report-format=json emits valid JSON parseable by jq (object at top level)
ok 16 DET-06: text format contains [DET-NN] markers for grep stability (DET-01 + DET-05 wired in this plan)
ok 17 DET-06: --report-only exits 0 and skips run_provisioners (no /opt/agentlinux/cli/<v>/dist edits during report)
ok 18 DET-02: nodejs probe enumerates NodeSource install on post-installer host
ok 19 DET-02: nodejs probe enumerates nvm install when fixture sets ~/.nvm
ok 20 DET-02: a /usr/local/bin/node symlinked to nvm does not double-count
ok 21 DET-03: npm prefix surfaces user / system / effective values as separate JSON fields
ok 22 DET-03: npm prefix probe runs via as_user_login (NPM_CONFIG_PREFIX user-shell export observed)
ok 23 DET-03: effective prefix ownership + writability captured for the install user
ok 24 DET-04: claude classified healthy when present and --version exits 0
ok 25 DET-04: get-shit-done-cc classified healthy when --help banner parseable
ok 26 DET-04: playwright-cli classified absent when binary missing from install user PATH
ok 27 DET-04: classifier returns broken when binary present but --help non-zero
ok 28 DET-01..06: detection writes zero bytes to /etc /home /usr/local/bin /opt
ok 29 DET-06: text format renders [DET-NN] markers for every captured field
ok 30 DET-06: json format parses via jq with every captured field reachable
ok 31 DET-06: json output contains NO schema_version / $schema / version field at top level
ok 32 DET-06: NO_COLOR env var honored — zero ANSI escapes in text output
ok 33 DET-06: piped (non-TTY) text output strips ANSI color escapes
ok 34 DET-01..06: greenfield baseline preserved — bats run-line count matches expected
```

24/24 Phase-12 tests pass on Ubuntu 22.04 + 24.04 (48 total Phase-12 test invocations).

### Flake note

A prior test run intermittently failed test #93 (`AGT-02 (release-gate): claude update`) with exit 124 (timeout). That test exercises the live Anthropic CDN with a 120s timeout, is unrelated to Phase 12, and recovered on retry — both clean 97/97 runs above were observed on the same codebase without any modifications. No Phase 12 code path is reached by the AGT-02 test.

## Requirements Coverage

| Requirement | Plan Source | Status | Evidence |
|-------------|-------------|--------|----------|
| DET-01 | 12-01 | SATISFIED | `plugin/lib/detect/user.sh` + bats #11, #12 |
| DET-02 | 12-02 | SATISFIED | `plugin/lib/detect/nodejs.sh` + bats #18, #19, #20 |
| DET-03 | 12-02 | SATISFIED | `plugin/lib/detect/npm_prefix.sh` + bats #21, #22, #23 |
| DET-04 | 12-02 (amended 12-01) | SATISFIED | `plugin/lib/detect/agents.sh` + bats #24..#27; binary-name amendment in REQUIREMENTS.md:38-40 |
| DET-05 | 12-01 | SATISFIED | `plugin/lib/detect/sudoers.sh` + bats #13, #14 |
| DET-06 | 12-03 (amended 12-01) | SATISFIED | `plugin/lib/detect/render.sh` (text + JSON) + bats #15..#17, #29..#33; ceremony-strikeout amendment in REQUIREMENTS.md:42-44 |

All 6 declared Phase-12 requirements are `Complete` in REQUIREMENTS.md traceability table (lines 105-110) and have empirical bats coverage on both Ubuntu matrices.

## Data-Flow Trace (Level 4)

Each rendered field traces back to a real probe (not hardcoded / not stub):

| Component | Render source variable | Populated by | Probe primitive | Real data? |
|-----------|----------------------|--------------|----------------|------------|
| user.uid | `DETECT_USER_UID` | `detect::user_probe` | `getent passwd $user` → field 3 | YES |
| user.home_writable | `DETECT_USER_HOME_WRITABLE` | `detect::user_probe` | `as_user $user test -w "$home"` | YES |
| nodejs[].path | `DETECT_NODEJS_${i}_PATH` | `__det_nodejs_manager` | `find $root -maxdepth N -name node -type f` | YES |
| nodejs[].version | `DETECT_NODEJS_${i}_VERSION` | `__det_nodejs_manager` | `as_user $user $bin --version` | YES |
| npm_prefix.effective_prefix | `DETECT_NPM_PREFIX_PATH` | `detect::npm_prefix_probe` | `as_user_login $user npm config get prefix` | YES |
| npm_prefix.effective_owner | `DETECT_NPM_PREFIX_EFFECTIVE_OWNER` | `detect::npm_prefix_probe` | `stat -c '%U:%G' "$effective_prefix"` | YES |
| agents[].path | `DETECT_AGENT_*_PATH` | `detect::agents_probe` | `as_user_login $user command -v $binary` | YES |
| agents[].status | `DETECT_AGENT_*_STATUS` | `detect::agents_probe` | classification: command -v + version regex + `--help` exit | YES |
| sudoers.sha256 | `DETECT_SUDOERS_SHA256` | `detect::sudoers_probe` | `sha256sum $path \| cut -d' ' -f1` | YES |
| sudoers.nopasswd_line_present | `DETECT_SUDOERS_NOPASSWD_OK` | `detect::sudoers_probe` | `grep -Fxq -- "$EXPECTED_LINE" $path` | YES |

No HOLLOW (wired-but-disconnected) artifacts. Bats #22 specifically proves the npm probe is wired all the way through `as_user_login` by writing a sentinel `NPM_CONFIG_PREFIX` export to `~/.profile` and observing it in the rendered `effective_prefix`.

## Anti-Patterns Scanned

| Scan | Result | Severity |
|------|--------|----------|
| `sudo npm install -g` in `plugin/lib/detect/` | 0 matches | — |
| `/usr/local/bin/<binary>` shim WRITES in `plugin/lib/detect/` | 0 (only `readlink -f` read probe) | — |
| `schema_version` in `plugin/` | 0 matches | — |
| `$schema` in `plugin/` | 0 matches | — |
| Committed `*.schema.json` files | 0 found | — |
| ADR-013 for JSON Schema | Does not exist (013 is unrelated MIT license ADR) | — |
| TODO/FIXME/XXX/HACK in `plugin/lib/detect/` | 0 functional TODOs | — |
| `return null \| return [] \| return {}` placeholder bodies in detect/* | 0 matches | — |
| `console.log`-only handlers | 0 (bash module, N/A) | — |
| ROADMAP.md DET-06 SC mentions "JSON schema documented and versioned" but REQUIREMENTS.md is the contract source-of-truth and has the strikeout + amendment | Documented in CONTEXT.md Area 2 + Plan 12-01 Task 1 commit `a59d3d0` | INFO (intentional design choice, not a gap) |

## ROADMAP-vs-REQUIREMENTS Discrepancy (Documented, Not a Gap)

`.planning/ROADMAP.md:48` (Phase 12 Success Criterion 6) still reads "the JSON schema is documented and versioned". This pre-dates the 2026-05-10 discuss-phase amendment captured in `12-CONTEXT.md` Area 2 ("Option B chosen — schema docs / ADR / `schema_version` field were rejected as ceremony for hypothetical future consumers"). The amendment was applied to REQUIREMENTS.md DET-06 (the single source of truth for behavior contracts) with a `<del>` strikeout on the original wording and an amendment paragraph carrying the "Phase 12 discuss (2026-05-10)" footnote. The ROADMAP.md text was not back-edited because ROADMAP.md is a high-level phase plan, not the behavior contract.

This is consistent with the planning documents' explicit framing: CONTEXT.md Area 2 closes with "REQUIREMENTS.md will be updated in this phase's first plan to reflect the amendment with a strikeout on the original DET-06 wording" — which Plan 12-01 Task 1 did (commit `a59d3d0`). The bats test #31 (`DET-06: json output contains NO schema_version / $schema / version field at top level`) enforces the amendment at runtime on every harness run.

No code or behavior change is required to align ROADMAP.md with REQUIREMENTS.md; the amendment is binding via the REQUIREMENTS.md strikeout. Phase 15 (Pre-flight UX) may revisit ROADMAP wording when it finalizes the UX surface, but that is out of scope for Phase 12 verification.

## Human Verification Needed

None. Every dimension is empirically verified by bats `@test` on the Docker matrix:
- DET-01..06 functional behavior: 17 @tests (#11-#27)
- Read-only invariant: 1 @test (#28) + sub-invariant for sudoers (#14)
- DET-06 amendment (no schema/version): 1 @test (#31)
- NO_COLOR / TTY-stripping: 2 @tests (#32, #33)
- Greenfield + meta: 1 @test (#34)

The CONTEXT.md Q3 decision to scope this @test to Docker-only (no QEMU) is explicit and well-reasoned — read-only-ness does not depend on systemd / locale / cloud-init paths. QEMU pre-existing-systems coverage remains a milestone-close gate owned by Phase 16, not Phase 12.

## Gaps

None.

## Recommendation

**PROCEED.** Phase 12 (Detection Layer) achieves its goal. The phase ships:
- A read-only host discovery library at `plugin/lib/detect/` with 6 files (orchestrator + 5 probes + renderer) totaling ~700 LOC of production code
- Two new entrypoint flags (`--report-only`, `--report-format=text|json`, plus `--user=NAME`)
- A locked Phase 12 → Phase 13 reader contract (`detect::*` accessors backed by exported `DETECT_*` variables)
- Comprehensive bats coverage: 24 `@tests` in `tests/bats/15-detection.bats`, all green on Ubuntu 22.04 + 24.04
- DET-04 + DET-06 amendments captured in REQUIREMENTS.md with the discuss-phase footnote and enforced at runtime by bats

Phase 13 (Reuse Wiring) can begin without prerequisites — the detection layer is ready to be consumed by short-circuit provisioners. The CONTEXT.md "Phase 12 → Phase 13 contract" (reader function symbols + memoization semantics + `/run/agentlinux-detect.json` cache location) is implemented and tested.

---

*Verified: 2026-05-10*
*Verifier: Claude (gsd-verifier)*
