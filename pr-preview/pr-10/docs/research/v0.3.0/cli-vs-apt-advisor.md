# Advisor Research: Custom `agentlinux` CLI vs Distro-Native Package Managers

**Date:** 2026-04-19
**Context:** User-raised grey area during Phase 4 smart-discuss — "why build a custom CLI when Ubuntu already has apt?"
**Scope:** The command users run to install/remove catalog agents (Claude Code, GSD, Playwright). NOT the installer itself (ADR-006 locked).
**Outcome:** Option A (custom CLI) recommended; decision preserved in Phase 4 scope.

---

## Question

Should AgentLinux use a custom `agentlinux install <name>` CLI (Commander.js/TS per ADR-008), or should it leverage the target distro's native package manager (apt/dnf/pacman) to install/remove the catalog agents?

## Options Considered

- **A.** Custom `agentlinux` CLI (current Plan 4)
- **B.** Distro-native apt/dnf with one `.deb` per catalog agent
- **C.** Hybrid: `agentlinux` CLI ships as a `.deb`; agent installs go through the CLI via npm (agent-user)
- **D.** Pure apt repo, no CLI at all

## Comparison Table

| Option | Pros | Cons | Complexity | Recommendation |
|---|---|---|---|---|
| **A. Custom `agentlinux` CLI** | Uniform UX across Ubuntu/Fedora/Arch (v0.4+ DST-01..03); reads per-agent `install.sh` as agent user so ADR-004 prefix is honored by construction; CAT-03 submitter ships JSON entry + small shell recipe; symmetric `install`/`remove` with sentinel-tracked state; no middleman between npm publish and user; `claude update` runs in the exact environment we provisioned so AGT-02 is straightforward | New artifact to design/test (Commander.js + schema + dispatcher); "why not just apt?" requires explanation; CLI must itself be bootstrapped onto PATH (already handled by Phase 3 `.npm-global/bin`) | 4-6 files (`plugin/cli/src/commands/{list,install,remove,info}.ts`, `plugin/cli/src/catalog/validate.ts`, `plugin/cli/src/runner.ts`) + per-agent `plugin/catalog/agents/<name>/install.sh` recipes. Risk: schema drift between CLI + catalog; AGT-02 subtly if `install.sh` uses the wrong path. Fully in scope of Phase 4 as planned. | **Recommended for v0.3.0.** |
| **B. Per-agent `.deb`s via apt** | Leverages apt's dependency graph, rollback, and `apt remove` symmetry; familiar `apt install agentlinux-claude-code` UX; `postinst`/`prerm` hooks are well-worn | `postinst` runs as **root** so must `sudo -u agent -H npm install -g` anyway — defeats half the benefit; per-agent `.deb`s must be **rebuilt on every upstream npm publish** (Claude Code publishes weekly+); **breaks AGT-02**: apt considers itself the install owner, but `claude update` detects npm-global and reinstalls to `/home/agent/.npm-global`, clobbering apt's view → split-brain state → next `apt upgrade` reverses it; requires public apt repo + signing key (INF-01, deferred to v0.4+); `.deb` not portable to Fedora/Arch (v0.4+ needs `.rpm` track doubled); CAT-03 submitter must author `debian/{control,rules,changelog,postinst,prerm}` instead of 20-line shell recipe — major friction | Touches 4+ files per agent, plus infra: public apt repo, package-signing GPG key, `fpm` build matrix, per-agent release workflows. Risk: **AGT-02 regression**, ownership ambiguity, stale-repo hazard, rpm fork maintenance from v0.4. | **Not recommended.** |
| **C. Hybrid (CLI-as-.deb)** | Bootstrapping the CLI itself via apt is a small, low-risk concession (single `.deb`, not per-agent); keeps single uniform UX for agent install/remove; no AGT-02 regression because agent installs go through agent-user npm path | Extra packaging path for v0.3.0 (CLI already ships via `.npm-global` from Phase 2-3); requires public apt repo (INF-01 deferred); two CLI install paths to keep in sync | 1-2 additional artifacts; infra still needs apt repo or GitHub-Releases `.deb`. Same per-agent recipe structure as Option A. | **Revisit in v0.4+** once INF-01 (public PPA) is in scope. |
| **D. Pure apt, no CLI** | Maximum "why roll our own?" answer — zero new UX; `apt search agentlinux-*` is a discovery primitive for free | All of B's drawbacks plus: no `agentlinux list` with installed-state UX; no `agentlinux doctor`; "install recipe runs as agent user" is an invariant of each `postinst`, which any submitter could break; non-portable to non-Debian distros; CAT-03 submitter friction extreme; same AGT-02 regression; no API for future v0.4 features | Highest infra burden, lowest code surface, highest maintenance surface | **Not recommended.** |

## Recommendation

**Option A** is the correct answer for v0.3.0. The user's "why roll our own?" intuition — valid for a generic installer — is defeated here by three load-bearing specifics:

1. **All three catalog agents (Claude Code, GSD, Playwright) are npm packages whose publish cadence is daily-to-weekly.** Shipping them as `.deb` makes AgentLinux a middleman that lags upstream; users would be stuck on our `.deb` version, not the latest npm publish. Adds per-agent release pipelines and requires rebuilding every time upstream ships.

2. **Claude Code's `claude update` detects install type by resolving `which claude` against `~/.local/bin` vs `~/.npm-global/bin`** (per [anthropics/claude-code#22415](https://github.com/anthropics/claude-code/issues/22415) and [#28625](https://github.com/anthropics/claude-code/issues/28625)) and then runs either the native self-updater or `npm install -g` directly. An apt-installed Claude Code would be invisible to this detection — the first `claude update` would spawn `npm install -g` into `/home/agent/.npm-global` and shadow the apt version, recreating the exact ownership ambiguity AgentLinux exists to eliminate (AGT-02 regression).

3. **CAT-03 explicitly requires that adding a new agent be "submit only a catalog entry + install recipe, no CLI source edit."** Option A honors this with a 20-line `install.sh` + JSON entry. Options B/D force the submitter to author full Debian packaging (`debian/control`, `debian/rules`, `debian/changelog`, `postinst`, `prerm`) — an order-of-magnitude higher friction that chills ecosystem adoption.

## Real-World Precedent

The industry consensus for this exact class of problem ("meta-installer for fast-moving developer tools") is unambiguous:

- **[rustup](https://rust-lang.github.io/rustup/installation/package-managers.html):** Documents that apt versions "lag several major versions" and cannot provide toolchain management. Chose custom meta-installer.
- **[pipx](https://pipx.pypa.io/stable/) + [PEP 668](https://peps.python.org/pep-0668/):** Chose isolated per-user envs over apt for Python CLIs because "package managers need someone else to package things for you" and "step on each other's toes."
- **[Homebrew](https://docs.brew.sh/Installation):** Coexists with apt rather than replacing it for precisely the "developer-tools evolve faster than distro release cycles" reason.

AgentLinux's catalog agents live in the same regime.

## AGT-02 Litmus Test (End-to-End Walkthrough)

The canonical acceptance test: user opens Claude Code and types `/update`. What happens?

- **Option A:** `agentlinux install claude-code` ran `sudo -u agent -H curl ... | bash` (native) or `sudo -u agent -H npm install -g @anthropic-ai/claude-code`. Binary lives under `/home/agent/.local/bin/claude` or `/home/agent/.npm-global/bin/claude`. `claude update` resolves `which claude` → agent-owned path → updater writes to same agent-owned path → works, no EACCES. ✓

- **Option B/D:** `apt install agentlinux-claude-code` ran `postinst` as root, which ran `sudo -u agent -H npm install -g ...` into `/home/agent/.npm-global`. User runs `claude update`. `which claude` → `/home/agent/.npm-global/bin/claude` → updater detects "npm-global" → runs `npm install -g` as agent user → **works from Claude Code's side**, but apt's dpkg database now lists a version that's been clobbered by npm; next `apt upgrade` brings the apt-tracked version back and fights the self-update. ⚠ AGT-02 technically green on first test, but the install is in a split-brain state where apt and Claude Code's self-updater each think they own the binary. Regression risk: HIGH.

- **Option C:** Same as Option A for AGT-02 path. ✓

## CAT-03 Submitter Experience

| Option | What the submitter produces |
|--------|----------------------------|
| **A / C** | `plugin/catalog/agents/<name>/agent.json` (10-20 lines) + `install.sh` (20-40 lines) + `uninstall.sh` (symmetric) + PR. JSON Schema validates entry. CI runs bats install+run+uninstall. |
| **B / D** | Full `debian/` directory (`control`, `rules`, `changelog`, `postinst`, `prerm`) + `build.sh` (fpm) + release-pipeline entry + signing-key config + PR. Debian-build CI runs. Infrastructure lint validates apt metadata. |

## Phase 4 Scope Adjustment

**Not applicable:** Option A wins and Phase 4's current scope (registry CLI + JSON-schema catalog + per-agent recipes + symmetric uninstall) stands unchanged.

## What to Do Next

1. **Keep Phase 4 scope as specified in ROADMAP.md.**
2. **Leave ADR-008 (Commander.js for CLI) accepted as-is.** This research reinforces rather than challenges it.
3. **(Optional) Author ADR-011 "custom CLI over distro package manager for catalog agents"** capturing this decision so the "why not apt?" question isn't re-litigated.
4. **(Optional, v0.4+)** Revisit Option C (ship the CLI itself as a `.deb` in a public PPA) once INF-01 is in scope. Agent-level installs should remain npm-driven regardless.
5. **Validate in Phase 5's AGT-02 test** that the `install.sh` recipe for Claude Code uses `sudo -u agent -H` exclusively — this is the single load-bearing implementation detail across every option.

## Sources

- [Claude Code: Advanced setup](https://code.claude.com/docs/en/setup) — canonical npm/native install paths, auto-update mechanics
- [anthropics/claude-code #22415](https://github.com/anthropics/claude-code/issues/22415) — auto-updater install-type detection on split installs
- [anthropics/claude-code #28625](https://github.com/anthropics/claude-code/issues/28625) — `claude update` misdetects native install as npm-global
- [@anthropic-ai/claude-code on npm](https://www.npmjs.com/package/@anthropic-ai/claude-code) — npm publish cadence
- [rustup: Package managers](https://rust-lang.github.io/rustup/installation/package-managers.html)
- [rustup: Issue #800](https://github.com/rust-lang/rustup/issues/800) — design rationale against apt
- [pipx docs](https://pipx.pypa.io/stable/), [PEP 668](https://peps.python.org/pep-0668/)
- [Homebrew: Installation](https://docs.brew.sh/Installation)
- [Debian Policy Manual §6](https://www.debian.org/doc/debian-policy/ch-maintainerscripts.html) — package maintainer scripts
