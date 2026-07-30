# QA Scenario Ledger — v0.4.0 Rust build (2026-07-29)

Subject: musl `agentlinux` static bin (default provisioner + CLI, Phase 58).
Catalog reconciled from `plugin/catalog/catalog.json` (v0.3.6, 25 real IDs +
`test-dummy` fixture). No credentials pre-authorized: all credentialed
coding-agent/MCP operations are `blocked`, keyless/local surface only.
Thresholds: 30 min productive + latest 10 distinct clean ideas since last new issue.

Distros: ubuntu-24.04 (apt) + almalinux-9 (dnf), Docker.

Binary identity (host): `ELF 64-bit LSB pie, x86-64, static-pie linked, stripped`
— confirmed static-musl, matches the "sole shipped artifact" contract.

| # | Idea | Packages | Distro | Order | Operation | Cred | Interval | Novelty | Finding | Cleanup | Evidence |
|---|------|----------|--------|-------|-----------|------|----------|---------|---------|---------|----------|
| 1 | musl bin identity + version | (bin) | host | n/a | `file` + `--version` + `--help` verb enum | none | ~4m | clean | — | n/a | static-pie stripped; v0.3.6; 6 verbs + provision |
| 2 | `list` default byte-render | (bin) | host | n/a | `agentlinux list` | none | ~3m | clean | — | n/a | aligned cols; status vocab (synced/pinned-override/drift-undeclared/present/not-installed); reuse + non-managed-path hints render |
| 3 | `list --json` validity + fields | (bin) | host | n/a | `list --json` \| json.load | none | ~3m | clean | — | n/a | 25 entries, valid JSON; machine fields (status/curated/installed/sentinel_version/drifted/category*) present |
| 4 | `list --by-category` grouping | (bin) | host | n/a | `list --by-category` (+`--json`) | none | ~3m | clean | — | n/a | 6 category headers, per-category sub-tables; `--by-category --json` returns 25-elem list w/ category_order |
| 5 | verb exit-code surface (Rust regression class) | (bin) | host | n/a | frobnicate/install(no-arg)/install-missing/pin-bad/remove-not-installed | none | ~5m | clean | — | n/a | 64=EX_USAGE (clap usage+catalog-miss), 1=operational (remove not-installed), 0=success — differentiated, matches bats-asserted EX_USAGE parity |
| 6 | recipe env-var contract (Rust dispatcher → Bash recipes) | (dispatcher) | static | n/a | grep produced vs consumed | none | ~4m | clean | — | n/a | 5 consumed vars (AGENT_HOME/CATALOG_DIR/PINNED_VERSION/PRESERVE_PATHS/SOURCE_KIND) all exported by Rust; OPENCODE_CONFIG/QWEN_SETTINGS are recipe-local, not contract |
| 7 | dispatcher subprocess parity (sudo -u/tee/timeout) | (dispatcher) | static | n/a | read dispatcher.rs | none | ~4m | clean(static-only) | — | n/a | sudo -u/-H/-E/-- hop; thread-per-pipe tee; SIGTERM→2000ms→SIGKILL; stream timeout→124, buffered→1 — coded to TS `asUser` parity. LIVE proof pending idea 8 |
| 8 | fresh-container Rust provision — PROVISION PHASE (ubuntu-24.04) | (provisioner) | ubuntu-24.04 | fresh | `tests/docker/run.sh ubuntu-24.04` (Rust default) | none | ~8m (bg) | clean | — | container-scoped | PROVISION COMPLETED clean (log L82-283): 10-agent-user→20-sudoers(ADR-012 NOPASSWD)→30-nodejs(Node 22.23.1, npm prefix `/home/agent/.npm-global`, RT-04 .npmrc)→40-path-wiring(4 artefacts)→50-registry-cli(symlink `/home/agent/.npm-global/bin/agentlinux`→`/opt/agentlinux/cli/0.3.6/bin/agentlinux`, NO `/usr/local/bin` shim). `agentlinux-install complete`. bats INST-05 asserts no-EACCES/no-perm-denied (ok 6). Dispatcher→Bash recipes ran under musl bin. NOTE: `adopt --all` reported a problem (continuing) — see obs |
| 8b | bats full-suite verification under Rust default (ubuntu-24.04) | (bats 369) | ubuntu-24.04 | — | `bats tests/bats/` w/ AGENTLINUX_RUST_BIN | none | in-flight | INCOMPLETE | — | container-scoped | LIVE at handback: reached ~test 132/369, all green so far (ok 1-79 captured incl brownfield E2E ok43-44, remediate ok45-79); real PTY test running via tty-driver.py. Not complete — no pass claimed on full suite |
| 9 | fresh-container Rust provision (almalinux-9 / dnf) | (provisioner+bats) | almalinux-9 | fresh | `tests/docker/run.sh almalinux-9` | none | not-started | INCOMPLETE | — | pending | not reached under context budget this resume |
| 10+ | keyless per-package lifecycles (trivy/gitleaks/gsd/spec-kit/ccusage/playwright/rtk) | various | both | fresh | install→op→remove | none | not-started | INCOMPLETE | — | pending | require a green provisioned container first (idea 8/9) |
| — | credentialed coding-agent + MCP ops | claude-code/codex/etc + MCP | both | — | authed prompt / tool call | BLOCKED | — | blocked | — | — | no credentials pre-authorized per checkpoint |

> Idea 8 RESOLVED (provision phase): the ubuntu-24.04 Rust provision COMPLETED cleanly end-to-end — install→identity→ownership(`agent:agent` npm prefix under `$HOME`)→no `/usr/local/bin` shim (CLI symlinked into `.npm-global/bin` instead)→dispatcher→Bash recipes confirmed executing under the musl bin. This satisfies the idea-8 install→identity→ownership→no-shim lifecycle at the PROVISIONER level and is folded in as CLEAN.
>
> Idea 8b IN-FLIGHT: the same `run.sh` invocation then launched the full 369-test bats suite (separate verification). At this resume's handback it had reached ~test 132/369 with every executed assertion green (ok 1-79 captured in log incl brownfield REUSE-03 E2E and full REMEDIATE foundation; PTY-driven UX-02 test running via `tty-driver.py`). Left running in background; NOT counted as complete — no full-suite pass claimed.
>
> OBSERVATION (retained, not a confirmed finding): line 282 `agentlinux provision: agentlinux adopt --all reported a problem (continuing; run it manually to retry)`. In a from-scratch greenfield provision there are no reuse-eligible agents to adopt, so a non-fatal `adopt --all` complaint may be benign/expected — but the message is user-visible and was NOT reproduced/root-caused this session. Classified `observation` (neither new nor clean); needs a clean re-run to decide benign-vs-defect. Does NOT reset the gate.
>
> COVERAGE NOTE: the runner container's per-test state is non-deterministic while bats runs (it purges/re-stages `/opt/agentlinux` for brownfield/remediate cases), so it is NOT usable as a stable target for independent keyless per-package lifecycles. Those (ideas 10+) still require a dedicated fresh container and were NOT reached this resume under the context budget.
