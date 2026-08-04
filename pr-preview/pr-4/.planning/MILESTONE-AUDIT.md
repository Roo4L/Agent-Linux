---
audit: v0.3.0 cross-phase integration
audit_date: 2026-04-20
auditor: Claude (integration-checker)
phases_in_scope: [02, 03, 04, 05, 05.1, 06]
phase_status_input: all marked complete
verdict: shippable (with explicit deferrals to first-CI-run / first-tag-push)
---

# v0.3.0 Milestone Integration Audit (Phases 2–6)

**Question this audit answers:** Do Phases 2 through 6, each verified individually as passing, actually compose into a working v0.3.0 system end-to-end? Specifically, can a user `curl | sudo bash` and end up with the agent user, Node, the registry CLI, and three installable agents — wired together correctly — with no break in any cross-phase handoff?

**Method:** read-only inspection of `plugin/`, `packaging/`, `scripts/`, `tests/bats/`, `.github/workflows/`, plus the six per-phase VERIFICATION.md reports. No code touched.

## 1. Integration Map (Phase X output → Phase Y input, per handoff)

End-to-end install path traced through every handoff:

| # | Producer (Phase) | Output / Contract | Consumer (Phase) | Wiring evidence | Status |
|---|------------------|-------------------|------------------|-----------------|--------|
| 1 | curl-installer (P6) `packaging/curl-installer/install.sh:182-193` | extracts release tarball under `/opt/agentlinux/install/<ver>/`; `exec`s `plugin/bin/agentlinux-install` | agentlinux-install entrypoint (P2) | `install.sh:188` `exe="${inst}/plugin/bin/agentlinux-install"` + `[[ -x "$exe" ]]` + `exec "$exe" "$@"` | ✓ WIRED |
| 2 | release tarball (P6) `scripts/build-release.sh:262-272` `tar … plugin/` | ships `plugin/{bin,lib,provisioner,catalog,cli}` byte-for-byte | curl-installer (P6) tar extract | `build-release.sh:271` archives `plugin/` only; `50-registry-cli.sh:55-66` asserts `dist/index.js`, `node_modules`, `package.json`, `catalog.json` are all present in the staged tree (fail-fast if release tarball malformed) | ✓ WIRED |
| 3 | `plugin/cli/` build step (P6) `scripts/build-release.sh:201-219` (pnpm install --frozen-lockfile + build + prune --prod) | populates `plugin/cli/{dist,node_modules,package.json}` | 50-registry-cli provisioner (P4) | `50-registry-cli.sh:46-66` resolves `CLI_BUNDLE_SRC=$BIN_DIR/../cli` then explicitly tests for `dist/index.js`, `node_modules`, `package.json` and exits with `log_error … release tarball malformed?` if any missing | ✓ WIRED |
| 4 | agentlinux-install entrypoint (P2) `plugin/bin/agentlinux-install:185-194` (`run_provisioners`) | `compgen -G "$PROV_DIR/[0-9][0-9]-*.sh" \| sort` then sources each in numeric order | provisioner chain 10 → 20 → 30 → 40 → 50 | numeric sort enforced after Plan 03-01 Rule 3 fix; provisioners present on disk: `10-agent-user.sh`, `20-sudoers.sh`, `30-nodejs.sh`, `40-path-wiring.sh`, `50-registry-cli.sh` | ✓ WIRED |
| 5 | 10-agent-user (P2) | creates agent user, /home/agent (0755 agent:agent), /etc/default/locale, /home/agent/CLAUDE.md (DOC-02) | 30-nodejs (P3) writes `~agent/.npmrc`; 40-path-wiring (P2/P3 ext) writes `/home/agent/.bashrc`; 50-registry-cli (P4) symlinks into `~agent/.npm-global/bin` | every downstream step assumes `/home/agent` + `agent:agent` group exist; ordered before all of them by `[0-9][0-9]` filename prefix | ✓ WIRED |
| 6 | 20-sudoers (P5.1) `plugin/provisioner/20-sudoers.sh` | installs `/etc/sudoers.d/agentlinux 0440 root:root` with `agent ALL=(ALL) NOPASSWD: ALL` per ADR-012 | playwright recipe (P5) `install.sh:63` `npx … playwright install --with-deps chromium` (internal `playwright-core` auto-prepends `sudo`) + future agent recipes needing apt | playwright/install.sh:55-56 comment explicitly cites ADR-012; the `--with-deps` path requires non-interactive sudo, which Phase 5.1 provides; 22-agent-sudo.bats covers BHV-07 + INST-06 | ✓ WIRED |
| 7 | 30-nodejs (P3) | NodeSource Node 22 LTS apt install + `/home/agent/.npm-global` (0755 agent:agent) + `~agent/.npmrc` `prefix=/home/agent/.npm-global` | 40-path-wiring (P3 ext) prepends `/home/agent/.npm-global/bin`; 50-registry-cli symlinks `agentlinux` into it; CLI runner.ts hard-codes the same prefix | byte-identical literals across `~agent/.npmrc`, `/etc/agentlinux.env`, `/etc/cron.d/agentlinux`, `runner.ts:30 AGENT_PATH` (T-03-03 byte-identity verified by Phase 3 acceptance grep) | ✓ WIRED |
| 8 | 40-path-wiring (P2 + P3 ext) `plugin/provisioner/40-path-wiring.sh` | writes `/etc/profile.d/agentlinux.sh` + `~agent/.bashrc` top-marker + `/etc/agentlinux.env` + `/etc/cron.d/agentlinux` (six-mode PATH/locale) | every `BHV-02..06` test, every `RT-XX` test, every `AGT-XX` test, every CLI-XX test (CLI on agent's PATH = CLI-01) | bats helpers `tests/bats/helpers/invoke_modes.bash` `INVOKE_MODES=(interactive ssh cron systemd_user sudo_u sudo_u_i)` exercise all four artefacts in cross-phase loops (used by 20/30/40/50 bats files) | ✓ WIRED |
| 9 | 50-registry-cli (P4) `plugin/provisioner/50-registry-cli.sh` | stages `/opt/agentlinux/cli/0.3.0/{dist,node_modules,package.json}`; stages `/opt/agentlinux/catalog/0.3.0/`; symlinks `/home/agent/.npm-global/bin/agentlinux → dist/index.js` (chown -h agent:agent); creates empty `/opt/agentlinux/state/installed.d/` | agent user runs `agentlinux <subcommand>` from any of the six invocation modes | symlink target verified at provisioner end via `as_user agent test -x "$SYMLINK"` (T-04-15 mitigation); CLI-01 bats @tests in `40-registry-cli.bats:62,77` loop INVOKE_MODES | ✓ WIRED |
| 10 | catalog.json (P4) `plugin/catalog/catalog.json` | declares 4 entries with `pinned_version`, `install_recipe_path`, `source_kind`; ajv-validated per `schema.json` | `plugin/cli/src/catalog/loader.ts:19` reads via `AGENTLINUX_CATALOG_DIR` or default `/opt/agentlinux/catalog/<ver>` | loader.ts default → 50-registry-cli stage path; verified runtime via `AGENTLINUX_CATALOG_DIR` env override in 40-registry-cli.bats CAT-03 fixture; `pinned_version` flows: catalog.json → loader → install.ts:75 (recipePath) → runner.ts:60 (env injection) → recipe install.sh `${AGENTLINUX_PINNED_VERSION:?…}` | ✓ WIRED |
| 11 | runner.ts dispatcher (P4) `plugin/cli/src/runner.ts` | injects `AGENTLINUX_PINNED_VERSION`, `AGENTLINUX_CATALOG_DIR`, `AGENTLINUX_AGENT_HOME`, `AGENTLINUX_SOURCE_KIND`, `AGENTLINUX_INSTALL_LOG`, `PATH`, `HOME`, `NPM_CONFIG_PREFIX`, `LANG`, `LC_ALL` | every install.sh / uninstall.sh recipe in `plugin/catalog/agents/*/` | grep confirms all 4 install.sh recipes consume `${AGENTLINUX_PINNED_VERSION:?…}` (claude-code, gsd, playwright, test-dummy); `AGENT_PATH` literal in runner.ts:31 byte-identical to `/etc/agentlinux.env` PATH= line (40-path-wiring.sh:146) | ✓ WIRED |
| 12 | dispatcher.ts asUser() (P4) `plugin/cli/src/state/dispatcher.ts:48-88` | `sudo -u <user> -H -E -- <argv…>` (mirrors `plugin/lib/as_user.sh`); short-circuits to direct `execFile` when `userInfo().username === user` | install.ts/remove.ts → recipe install.sh / uninstall.sh runs as agent | invoker===target short-circuit (Plan 04-07 Rule 1 auto-fix) prevents agent→agent sudo failure on default Ubuntu (sudoers drop-in only present from Phase 5.1 onward); CLI-05 `guard/user.ts` enforces invoker is agent at preAction hook | ✓ WIRED |
| 13 | claude-code recipe (P5) `plugin/catalog/agents/claude-code/install.sh:30` `curl -fsSL https://claude.ai/install.sh \| bash -s "${PINNED}"` | installs `~agent/.local/bin/claude` | AGT-02 bats (P5) tests `claude update` runs as agent without EACCES | release.yml `gate-2-docker` + `gate-3-qemu` both run `tests/bats/51-agt02-release-gate.bats` which invokes the live self-update path; AGT-02b in-recipe `grep -q -F -- "${PINNED}"` blocks success-sentinel write on version drift | ✓ WIRED |
| 14 | gsd recipe (P5) `plugin/catalog/agents/gsd/install.sh:30` `npm install -g get-shit-done-cc@${PINNED}` | installs `~agent/.npm-global/bin/get-shit-done-cc` | AGT-04 bats verifies `--help` banner contains `v${pinned}` | catalog jq lookup at runtime; AGT-01 bats also exercises `get-shit-done-cc --help` across all six INVOKE_MODES — touches Phase 2 PATH wiring, Phase 3 npm prefix, Phase 4 CLI install path | ✓ WIRED |
| 15 | playwright recipe (P5) `plugin/catalog/agents/playwright/install.sh` | `npm install -g playwright@${PINNED}` + `npx … install --with-deps chromium`; chromium under `~agent/.cache/ms-playwright/chromium-*` (agent:agent) | AGT-05 bats: version pin, cache owner=agent, idempotent re-install | depends on Phase 5.1 NOPASSWD sudo for `--with-deps` apt step; bats verifies via `stat -c '%U'` ownership (ADR-004 keystone) | ✓ WIRED |
| 16 | bats matrix (P2..P5) `tests/docker/run.sh ubuntu-{22.04,24.04}` | runs `tests/bats/*.bats` glob (8 files, 71 @tests on disk) inside a real systemd-capable Docker container that ran `agentlinux-install` end-to-end | release.yml gate-2-docker + gate-4-pinned-combo (P6) | release.yml:113 `bash tests/docker/run.sh ${{ matrix.ubuntu }}`; gate-4-pinned-combo:199 re-runs against `ubuntu-24.04` as the named TST-08 observable | ✓ WIRED |
| 17 | release pipeline (P6) `.github/workflows/release.yml` | resolve → gate-1-precommit → gate-2-docker × 2 → gate-3-qemu × 2 → gate-4-pinned-combo → build → publish; explicit `needs:` chain | `softprops/action-gh-release@v2.6.2` publishes tarball + .sha256 + catalog-<tag>.json on `v*` tag push | every gate cites the phase it enforces; build step runs `scripts/build-release.sh "$TAG"` then `sha256sum -c` round-trip; publish glob covers all required release sibling assets per CAT-05 + INST-03 | ✓ WIRED |
| 18 | --purge teardown (P4) `plugin/bin/agentlinux-install:223-296` (`run_purge`) | 7-step ordered teardown: per-agent uninstall.sh → /opt/agentlinux/ rm → PATH artefacts rm → NodeSource apt files rm → optional `apt purge nodejs` → userdel -r agent → log file rm LAST | symmetric inverse of Phases 2–5 install steps | T-04-16 mitigation: every rm target is a literal absolute path; recipe paths derived from `AGENTLINUX_VERSION` (entrypoint-controlled), not sentinel JSON contents; INST-04 bats covers 22.04 + 24.04 with second-purge idempotency assertion | ✓ WIRED |

**Wiring summary:** 18 / 18 cross-phase handoffs WIRED. Zero orphaned exports, zero missing connections, zero broken flows.

## 2. Cross-Phase Invariants Check Matrix (CLAUDE.md hard rules)

| # | Invariant | Check | Status | Evidence |
|---|-----------|-------|--------|----------|
| 1 | No `sudo npm install -g` anywhere in `plugin/` | grep `sudo\s+npm\s+install\s+-g` `plugin/` | ✓ GREEN | 3 matches all in DOC-02 anti-pattern warnings + `as_user.sh` docstring (`plugin/lib/as_user.sh:3`, `plugin/provisioner/10-agent-user.sh:77,100`); zero executable instances; recipes use bare `npm install -g <pkg>@<ver>` (gsd, playwright) under sudo-to-agent dispatch from runner.ts |
| 2 | No `/usr/local/bin/` shims pointing at agent-owned binaries | grep `/usr/local/bin/` `plugin/` | ✓ GREEN | 1 match in `10-agent-user.sh:94` DOC-02 anti-pattern body (the FORBIDDEN-list text); `/usr/local/bin` only otherwise appears in PATH literals as a *trailing* fall-through after `/home/agent/.npm-global/bin` and `/home/agent/.local/bin` |
| 3 | Per-user npm prefix `/home/agent/.npm-global` consistent across Phase 3 + Phase 4 + Phase 5 recipes | grep `/home/agent/.npm-global` across all 11 hits | ✓ GREEN | Phase 3: `30-nodejs.sh` writes `~agent/.npmrc prefix=/home/agent/.npm-global` + creates dir 0755 agent:agent. Phase 3 ext (40-path-wiring): `/etc/agentlinux.env` `NPM_CONFIG_PREFIX=/home/agent/.npm-global` + literal `PATH=/home/agent/.npm-global/bin:…` (×2: env + cron). Phase 4: `runner.ts:67 NPM_CONFIG_PREFIX: "/home/agent/.npm-global"` + `AGENT_PATH = "/home/agent/.npm-global/bin:…"`. Phase 4: `50-registry-cli.sh` symlinks into `/home/agent/.npm-global/bin/agentlinux`. All values byte-identical. T-03-03 split-brain avoidance enforced. |
| 4 | `pinned_version` flows: catalog.json → loader → install.ts → runner.ts → recipe `${AGENTLINUX_PINNED_VERSION}` | grep + path trace | ✓ GREEN | catalog.json declares pin; schema.json requires `pinned_version` semver pattern; loader.ts validates via ajv; install.ts:75 `decideVersion(entry, opts.version, existing)` produces `decision.version`; install.ts:80 passes `version: decision.version` to dispatchRecipe; runner.ts:60 `AGENTLINUX_PINNED_VERSION: args.version` injected into env; all 4 recipes consume `${AGENTLINUX_PINNED_VERSION:?…}` as fail-fast guard. `claude-code/install.sh:47` adds AGT-02b in-recipe assertion `grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"` against `claude --version` output. |
| 5 | No raw `sudo -u` outside `plugin/lib/as_user.sh` (and its TS mirror `dispatcher.ts`) | grep `sudo -u` plugin/ | ✓ GREEN | `as_user.sh:38,52` and `dispatcher.ts:60` are the only executable sites; other matches are doc comments and uninstall.sh scaffolds within recipes. ADR-012 sudoers drop-in keeps the agent→agent sudo path viable when invoker != agent. |
| 6 | All 4 catalog recipes have install.sh + uninstall.sh siblings | ls per-agent dir | ✓ GREEN | claude-code, gsd, playwright, test-dummy all have install.sh + uninstall.sh. |
| 7 | INST-02 byte-stability sha256 set covers Phase 2..5 artefacts | `tests/bats/10-installer.bats:35` INST-02 @test | ✓ GREEN (per VERIFICATION reports) | Plan 02-05 baseline: 5 artefacts. Plan 03-02: +`~agent/.npmrc` + NodeSource sources. Plan 04-07: +4 Phase-4 LOCKED artefacts. Plan 05.1-01: re-run sha256 covers `/etc/sudoers.d/agentlinux`. |
| 8 | TST-07 phase-close gate GREEN at every phase boundary | per-phase VERIFICATION.md frontmatter `tst07_gate` | ✓ GREEN at all 6 phases (2, 3, 4, 5, 5.1, 6) |
| 9 | Phase 1 harness still green after every phase merge | `bash tests/harness/run.sh` 104/104 | ✓ GREEN per all six VERIFICATION reports |

**Invariant summary:** 9 / 9 GREEN.

## 3. Bats Coverage Roll-up (per requirement ID)

Total @tests on disk: **71** across 8 files (10-installer × 10, 20-agent-user × 14, 22-agent-sudo × 7, 30-runtime × 5, 40-registry-cli × 22, 50-agents × 9, 51-agt02-release-gate × 1, 60-curl-installer × 3).

Per-requirement @test count from grep `^@test` cross-referenced against requirement IDs in test names:

| Req | @tests | File(s) | Status |
|-----|--------|---------|--------|
| INST-01 | 2 | 10-installer.bats | ✓ |
| INST-02 | 1 | 10-installer.bats | ✓ |
| INST-03 | 3 | 60-curl-installer.bats | ✓ |
| INST-04 | 2 | 40-registry-cli.bats | ✓ |
| INST-05 | 1 | 10-installer.bats | ✓ |
| INST-06 | 2 | 22-agent-sudo.bats | ✓ |
| BHV-01 | 4 | 20-agent-user.bats | ✓ |
| BHV-02 | 2 | 20-agent-user.bats | ✓ |
| BHV-03 | 1 | 20-agent-user.bats | ✓ |
| BHV-04 | 2 | 20-agent-user.bats | ✓ |
| BHV-05 | 3 | 20-agent-user.bats | ✓ (with documented override for plain `bash -c` deferred to v0.4) |
| BHV-06 | 2 | 20-agent-user.bats | ✓ |
| BHV-07 | 5 | 22-agent-sudo.bats | ✓ |
| RT-01 | 1 | 30-runtime.bats (six-mode loop) | ✓ |
| RT-02 | 2 | 30-runtime.bats | ✓ |
| RT-03 | 1 | 30-runtime.bats | ✓ |
| RT-04 | 1 | 30-runtime.bats (six-mode loop) | ✓ |
| AGT-01 | 3 | 50-agents.bats (six-mode × 3 binaries) | ✓ |
| AGT-02 | 1 | 51-agt02-release-gate.bats (live `claude update`) | ✓ |
| AGT-02b | 1 | 50-agents.bats | ✓ |
| AGT-03 | 1 | 50-agents.bats | ✓ |
| AGT-04 | 1 | 50-agents.bats | ✓ |
| AGT-05 | 3 | 50-agents.bats | ✓ |
| CLI-01 | 2 | 40-registry-cli.bats | ✓ |
| CLI-02 | 3 | 40-registry-cli.bats | ✓ |
| CLI-03 | 4 | 40-registry-cli.bats | ✓ |
| CLI-04 | 2 | 40-registry-cli.bats | ✓ |
| CLI-05 | 2 | 40-registry-cli.bats | ✓ |
| CLI-06 | 1 | 40-registry-cli.bats | ✓ |
| CLI-07 | 2 | 40-registry-cli.bats | ✓ |
| CAT-01 | 1 | 40-registry-cli.bats | ✓ |
| CAT-02 | 1 | 40-registry-cli.bats | ✓ |
| CAT-03 | 1 | 40-registry-cli.bats | ✓ |
| CAT-04 | 1 | 40-registry-cli.bats | ✓ |
| CAT-05 | 2 | 10-installer.bats (staging presence + byte-stability) | ✓ |
| DOC-02 | 4 | 10-installer.bats | ✓ |

**CI-gate-only (no bats — wired through release.yml `needs:` chain):**

| Req | Gate | Status |
|-----|------|--------|
| TST-01 | aggregate of all bats files (TST-07 audit cites every BHV/RT/AGT/CLI/CAT/INST as covered) | ✓ |
| TST-02 | `.github/workflows/test.yml` bats-docker matrix on every PR | ✓ |
| TST-03 | `.github/workflows/nightly-qemu.yml` + release.yml gate-3-qemu | ⏸ structural-green; runtime exit-0 deferred to first CI run |
| TST-04 | `tests/bats/helpers/assertions.bash::__fail` four-line diagnostic | ✓ |
| TST-05 | release.yml gate-2-docker + gate-3-qemu both run 51-*.bats; AGT-02 red blocks publish via `needs:` chain | ⏸ structural-green; tag-push exercise deferred |
| TST-06 | `.github/workflows/nightly-mutation.yml` (advisory in v0.3.0; `continue-on-error: true`) | ✓ scaffolded |
| TST-07 | per-phase behavior-coverage-auditor GREEN at every close | ✓ |
| TST-08 | release.yml gate-4-pinned-combo runs 50-agents.bats + 51-*.bats against pinned catalog | ⏸ structural-green; tag-push exercise deferred |
| HRN-01..09 | `tests/harness/run.sh` 104/104 | ✓ |
| DOC-01 | `README.md` + `docs/STABILITY-MODEL.md` (presence + version stamp + ADR-011 cross-link) | ✓ |

**Coverage roll-up:** 54 / 54 v0.3.0 requirements have either a bats @test or a CI-gate citation. Zero orphans.

## 4. Cross-Phase Contradictions or Gaps

### Documented supersession (NOT a contradiction)

- **Phase 2 CONTEXT lock: "no default sudoers drop-in" → Phase 5.1 supersedes with `agent ALL=(ALL) NOPASSWD: ALL`.** This is documented in ADR-012 (`docs/decisions/012-…`). The rationale: Phase 5 catalog recipes (notably playwright `npx playwright install --with-deps chromium`) require non-interactive `apt install`. Phase 2's lock was a deliberately conservative starting point; Phase 5.1 was inserted (decimal phase numbering preserves provenance) once the requirement became concrete. ROADMAP.md §Phase 5.1 ("Supersedes the Phase 2 'zero sudo for agent user' CONTEXT lock"), 02-VERIFICATION.md §Invariants ("zero sudoers drop-in confirmed; revisited Phase 5.1+"), and REQUIREMENTS.md INST-06 + BHV-07 all reference ADR-012. The phases compose: Phase 2 ships green without the drop-in; Phase 5.1 introduces it before Phase 5 needs it. No contradiction.

### Documented overrides (one)

- **Phase 2 BHV-05 plain `sudo -u agent bash -c` (no `--login`).** Accepted override per 02-VERIFICATION.md frontmatter: Ubuntu's default `Defaults secure_path` strips PATH before bash runs, and `bash -c` non-interactive non-login does not source `.bashrc`. Login variants `run_sudo_u` (`bash --login -c`) + `run_sudo_u_i` (`sudo -u -H -i`) cover the BHV-05 observable contract. With Phase 5.1's NOPASSWD drop-in NOW in place, this would be revisitable in v0.4+ via a `Defaults!secure_path` + `env_keep` adjustment, but is explicitly deferred. Not a v0.3.0 blocker.

### Latent hygiene gap (non-blocking, fix is one command)

- **Plan 04-07 Rule 1 auto-fix in `plugin/cli/src/state/dispatcher.ts:59` exceeded biome `lineWidth=100`** — flagged by Phase 4 verification as PARTIAL. The verification frontmatter says it was resolved in commit `664fa82` ("biome format dispatcher.ts; pnpm run format auto-applied"). Spot-check of the current file shows the line is now properly broken (line 59 is now a destructured assignment split over the standard column width). Verified resolved.

### Other gaps

**None found.** No phase contradicts another. Provisioner numeric ordering (10/20/30/40/50) maps cleanly to phase ordering (P2 → P5.1 → P3 → P3-ext / P2-ext → P4). The decimal phase number for 5.1 is metadata only — it slots into provisioner order at `20-` (between agent-user creation and Node install) where it is correctly needed before any sudo-requiring step but after the agent user exists.

## 5. Items Explicitly Deferred to First-CI-Run / First-Tag-Push

These are **not gaps** — they are the shipping event itself. All are documented in `06-VALIDATION.md §Manual-Only Verifications` and re-listed in 06-VERIFICATION.md `deferred_manual_only`:

1. **Runtime exit-0 of `tests/qemu/boot.sh` on Ubuntu 22.04 + 24.04 GH Actions runners** — first execution of `nightly-qemu.yml` (or `release.yml` gate-3-qemu). The harness scaffolding (boot.sh + cloud-init templates + workflow YAML + KVM udev rule + actions/cache key) is all in place; only the live KVM-on-runner exercise is deferred. (TST-03)
2. **End-to-end release-gate run on real `v0.3.0-rc1` tag push** — first `softprops/action-gh-release@v2.6.2` publish to GitHub Releases via the 4-gate `needs:` chain. Validates that gates 1–4 are observable and that the publish glob captures all 4 asset types (tarball / .sha256 / catalog-<tag>.json / optional .deb). (TST-05, TST-08, INST-03, CAT-05)
3. **Real `curl -fsSL https://agentlinux.org/install.sh | sudo bash`** — only executable once a real GH Release asset exists at the canonical URL. Validates the production path of the curl-installer fixture-tested in 60-curl-installer.bats. (INST-03)
4. **Cold-cache vs warm-cache QEMU runtime measurement** — second nightly QEMU run (after first). Validates `actions/cache@v4` keyed on `tests/qemu/cloud-images.txt` actually saves the ~1 GB Ubuntu cloud image fetch on subsequent runs. (TST-03 telemetry, not a correctness gate.)
5. **Pinned-combo CI gate live exercise** — gate-4-pinned-combo first execution. (TST-08)
6. **Live network smoke for `agentlinux upgrade --check-upstream`** — Phase 4 VERIFICATION human-verification row 3. Unit tests use DI stubs; first real-registry exercise lands when an end-user actually upgrades.

**Risk profile of deferrals:** all six deferrals are runtime-only verifications of CI infrastructure that has been shellcheck/actionlint/yaml-parsed/grep-asserted statically green. The probability that a structural break exists is low but non-zero — historical precedent (Plan 02-05's `dbus` Rule 3, Plan 04-07's `jq` Rule 3, Plan 05-01's `curl` Rule 3) shows minor environmental gaps are caught and fixed inline within a single retry on first CI run. The shipping event itself is the test.

## 6. Final Verdict

**`shippable`** — the v0.3.0 milestone composes correctly end-to-end. All 18 cross-phase handoffs are wired, all 9 cross-phase invariants hold, all 54 requirement IDs have either ≥1 bats @test or a CI-gate citation, the one prior PARTIAL hygiene gap (dispatcher.ts line 59) is resolved, no phase contradicts another, the one supersession (Phase 5.1 vs Phase 2's no-sudoers lock) is documented in ADR-012, and the six runtime-only deferrals are explicitly the shipping event (first CI run + first tag push) — they are not blocking gaps.

The system is shippable in the sense that it cannot be more thoroughly validated without firing the shipping event itself.

## 7. Recommended Next Step

**Cut the `v0.3.0-rc1` tag.** The rc1 push exercises six deferred items in one shot (release pipeline gates 1–4 + build + softprops publish + downstream `curl | bash` smoke against the real GH Release asset). If rc1 surfaces an environmental gap (probable shape: a missing apt package on a GH runner, a KVM permission edge case, an action version drift), fix inline on master, push `v0.3.0-rc2`, repeat. When rc2 (or rcN) runs end-to-end green:

1. Push `v0.3.0` final.
2. Update `.planning/STATE.md` `status: in_progress` → `status: complete` and `stopped_at` to "v0.3.0 shipped".
3. Add a row to `.planning/MILESTONES.md` for v0.3.0 with the release date.
4. Move ROADMAP focus to v0.4.0 (deferred items: BHV-05 plain `bash -c` PAM/sudoers fix, mutation testing → release gate, fpm `.deb` first-class, multi-distro DST-01..03, etc.).

If rc1 is green on first try, the project ships v0.3.0 final immediately.

---

_Audit performed: 2026-04-20 by Claude (integration-checker subagent), read-only on code; only `.planning/MILESTONE-AUDIT.md` written._
