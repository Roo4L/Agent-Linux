# Feature Research — v0.3.5 AlmaLinux 9 Parity Surface

**Domain:** Distro port (Ubuntu → AlmaLinux 9) of an installable agent-provisioning plugin
**Researched:** 2026-06-27
**Confidence:** HIGH (behavior contract + implementation read directly from the repo; EL9 shell-init / cronie / NodeSource / locale facts verified against current docs — see Sources)

> **Framing note.** This is a port milestone, so "features" = the **observable behavior parity surface** the bats contract (BHV / RT / AGT / CLI / CAT / INST + the v0.3.4 DET / REUSE / REMEDIATE / UX) must hold on AlmaLinux 9. The template's "table stakes / differentiators / anti-features" buckets are re-cast as:
>
> - **Parity — unchanged** (same artefact, same code path, same assertion — already distro-neutral)
> - **Parity — needs EL9 implementation** (observable behavior identical; implementation must branch apt→dnf / dpkg→rpm / locale tooling)
> - **Genuinely different on EL9** (the expected observable expectation itself changes — e.g. the login-shell user init file)
> - **Anti-features / out-of-scope** (explicitly NOT in v0.3.5)
>
> The downstream consumer is the v0.3.5 requirements author + roadmapper. Every row traces to a bats file or a requirement ID.

---

## 0. What a CORRECT AlmaLinux 9 install behaves like

Indistinguishable, at the observable layer, from a correct Ubuntu install:

- An `agent` user exists with `/bin/bash`, a real home, and a UTF-8 locale (`LANG`/`LC_ALL`) — **BHV-01**.
- All six invocation modes resolve the agent's `node`/`npm`/`agentlinux`/agent-tool binaries on PATH — **BHV-02..06**, looped by `INVOKE_MODES` in `tests/bats/helpers/invoke_modes.bash`.
- `npm install -g` works with no sudo, no `EACCES`, no shim; prefix under `~agent` — **RT-02 / RT-04**.
- `claude update` self-updates with **zero `EACCES`** against the live Anthropic CDN — **AGT-02**, the canonical gate (`tests/bats/51-agt02-release-gate.bats`).
- The brownfield detection→Reuse/Create/Remediate/Bail flow produces the same four-state decisions from EL9 evidence sources — **DET/REUSE/REMEDIATE-\*** (v0.3.4-REQUIREMENTS).
- `agentlinux list/install/remove/upgrade/pin` behave identically; the catalog ships the same three agents — **CLI-\* / CAT-\***.
- Zero `EACCES` / `permission denied` anywhere in the install transcript — **INST-05**.

The contract does not change. Only the *implementation under the contract* branches.

---

## A. The six invocation modes — EL9 shell-init analysis

The current matrix (`tests/bats/helpers/invoke_modes.bash`, line 27: `INVOKE_MODES=(interactive ssh cron systemd_user sudo_u sudo_u_i)`) and the four PATH-wiring artefacts (`plugin/provisioner/40-path-wiring.sh`) map onto EL9 as follows.

### A.1 Per-mode init-file resolution: Ubuntu vs AlmaLinux 9

| Mode | bats helper (`invoke_modes.bash`) | Ubuntu init path | **AlmaLinux 9 init path** | AgentLinux artefact that lands PATH | Carries over? |
|------|-----------------------------------|------------------|---------------------------|-------------------------------------|---------------|
| **interactive login** (BHV-06) | `run_interactive` → `su - agent -c` | `/etc/profile` → `/etc/profile.d/*.sh`, then `~/.profile` | `/etc/profile` → `/etc/profile.d/*.sh`, then **`~/.bash_profile`** (skel sources `~/.bashrc` → `/etc/bashrc`) | **Artefact 1** `/etc/profile.d/agentlinux.sh` | ✅ unchanged target |
| **non-interactive SSH** (BHV-02) | `run_ssh` → `ssh agent@host 'cmd'` | sshd-launched bash sources `~/.bashrc` (stdin = socket) | **Same** — sshd-launched bash sources `~/.bashrc` | **Artefact 2** `~agent/.bashrc` marker block (`--top`) | ✅ unchanged target |
| **cron** (BHV-03) | `run_cron` → `/etc/cron.d/...` job | vixie-cron reads `/etc/cron.d/*` PATH header | **cronie** reads `/etc/cron.d/*` PATH header (same format, honors `PATH=`) | **Artefact 4** `/etc/cron.d/agentlinux` | ✅ unchanged target (pkg differs) |
| **systemd `User=agent`** (BHV-04) | `run_systemd_user` → `systemd-run --uid=agent --property=EnvironmentFile=/etc/agentlinux.env` | systemd EnvironmentFile | **Same** — systemd is systemd | **Artefact 3** `/etc/agentlinux.env` | ✅ unchanged target |
| **`sudo -u agent`** (BHV-05) | `run_sudo_u` → `sudo -u agent -H bash --login -c` | `bash --login` → `/etc/profile` → profile.d | **Same** | **Artefact 1** `/etc/profile.d/agentlinux.sh` | ✅ unchanged target |
| **`sudo -u agent -i`** (BHV-05) | `run_sudo_u_i` → `sudo -u agent -H -i bash -c` | sudo `-i` login → `/etc/profile` → profile.d | **Same** | **Artefact 1** `/etc/profile.d/agentlinux.sh` | ✅ unchanged target |

### A.2 The headline answer: which files must the marker-block target on EL9?

**The same four files, in the same locations, written by `40-path-wiring.sh` unchanged:**

1. `/etc/profile.d/agentlinux.sh` (0644 root:root) — login + `sudo -u -i` (sourced by `/etc/profile` on EL9 via the identical `for i in /etc/profile.d/*.sh` loop; the `.sh` suffix is required on EL9 too).
2. `~agent/.bashrc` marker block at `--top` (0644 agent:agent) — non-interactive SSH + `sudo -u bash -c`.
3. `/etc/agentlinux.env` (0644 root:root) — systemd `EnvironmentFile=`.
4. `/etc/cron.d/agentlinux` (0644 root:root) — cron PATH/locale header.

**`40-path-wiring.sh` needs NO file re-targeting on EL9.** All four target files exist and are sourced identically on AlmaLinux 9. The re-source guard `AGENTLINUX_PROFILE_SOURCED` (lines 53–54) already prevents the double-prepend that EL9's login chain would otherwise cause (on EL9 a login shell sources **both** `/etc/profile.d/agentlinux.sh` via `/etc/profile` **and** the `~/.bashrc` marker via `~/.bash_profile`→`~/.bashrc`; the guard collapses them).

### A.3 The one genuinely-different shell-init fact

The login-shell **user** init file differs:

- **Ubuntu:** skel ships `~/.profile` (no `~/.bash_profile`); `~/.profile` sources `~/.bashrc` when interactive.
- **AlmaLinux 9:** skel ships `~/.bash_profile`, which sources `~/.bashrc`, which sources `/etc/bashrc`. There is **no `~/.profile`** in the EL skel, and **the EL skel `~/.bashrc` has no `case $- in *i*) ;; *) return;; esac` non-interactive early-return guard** (the Ubuntu guard that `40-path-wiring.sh` line 80–82 places the marker `--top` to beat).

**Consequence for the port:** AgentLinux writes to **neither** `~/.profile` nor `~/.bash_profile`, so this difference requires **no marker re-targeting** — it is absorbed by the existing `/etc/profile.d` + `~/.bashrc`-marker design. BUT the `--top` *rationale comment* in `40-path-wiring.sh` (lines 76–89, "precedes skel `case … return` early-return") is **Ubuntu-specific and factually false on EL9**. On EL9 there is no early-return to beat; `--top` remains correct (deterministic placement, runs before any user content) but the comment must be re-expressed distro-neutrally so a future maintainer doesn't "simplify" the `--top` away. **This is the only behavior-rationale that genuinely changes.** No assertion in `invoke_modes.bash` changes.

### A.4 cron nuance (BHV-03)

cronie (EL9) and vixie-cron (Ubuntu) both: read `/etc/cron.d/*` files with a username field, and honor a top-of-file `PATH=` literal assignment. The `run_cron` helper writes its own `/etc/cron.d/agentlinux-test-<stamp>` with a `PATH=` header (lines 69–73) — works under cronie unchanged. **EL9 harness must ensure the `cronie` package is installed and `crond` is running** (Ubuntu installs `cron`; the daemon/package name differs). This is a harness/packaging concern, not a path-wiring or assertion change.

---

## B. Parity surface — three buckets

### B.1 Parity — UNCHANGED (distro-neutral; carries over as-is)

| Behavior / req ID | Evidence (file) | Why unchanged on EL9 |
|-------------------|-----------------|----------------------|
| Six-mode PATH wiring, all four artefacts | `plugin/provisioner/40-path-wiring.sh`; `tests/bats/helpers/invoke_modes.bash` | profile.d, `~/.bashrc`, systemd EnvironmentFile, cron.d all behave identically (§A) |
| **BHV-02..06** (six modes resolve agent binaries) | `tests/bats/20-agent-user.bats`, `30-runtime.bats`, `50-agents.bats` looping `INVOKE_MODES` | Same init-file resolution (§A.1) |
| **RT-02 / RT-03** (npm `-g` install/uninstall, no EACCES, no shim) | `tests/bats/30-runtime.bats` (cowsay round-trip) | npm + per-user prefix is OS-neutral once Node is present |
| **RT-04** (`npm config get prefix` under `~agent`) | `tests/bats/30-runtime.bats` (`assert_user_prefix_in_home`) | `~agent/.npmrc` + `NPM_CONFIG_PREFIX` are filesystem-level |
| **INST-05** (zero `EACCES`/`permission denied` in transcript) | `tests/bats/10-installer.bats` | Permission invariant is the product's whole point — must hold identically |
| **INST-02** (idempotent re-run, byte-stable artefacts) | `tests/bats/10-installer.bats` (sha256 diff) | `ensure_marker_block` / `write_file_atomic` are OS-neutral |
| **BHV-07 / INST-06** (sudoers drop-in 0440, `sudo -n true`) | `tests/bats/22-agent-sudo.bats` | `/etc/sudoers.d/` + `visudo` + `#includedir` present on EL9; mode/owner/line identical |
| **CLI-01..07** (registry CLI surface) | `tests/bats/40-registry-cli.bats` | Node/TS CLI; OS-neutral once Node + symlink land |
| **CAT-01..04** (3 agents, no defaults, pinned_version) | `tests/bats/40-registry-cli.bats` | Catalog JSON is OS-neutral |
| **AGT-01 / AGT-02 / AGT-02b / AGT-03 / AGT-04** | `tests/bats/50-agents.bats`, `51-agt02-release-gate.bats` | claude-code native installer + gsd npm are OS-neutral (§E) |
| **DET-01 / DET-03 / DET-04 / DET-05** (user, npm-prefix, agent, sudoers probes) | `plugin/lib/detect/{user,npm_prefix,agents,sudoers}.sh`; `tests/bats/15-detection.bats` | `getent`/`id`/`stat`/`npm config`/`sha256sum`/PATH probes are coreutils — distro-neutral |
| **REUSE-01 / REUSE-03** (reuse user, reuse healthy agent) | `tests/bats/13-reuse.bats` | Decision logic OS-neutral |
| **REMEDIATE-01 / -02 / -03 / -04** (chown/rebase, PATH re-wire, sudoers, reinstall) | `tests/bats/14-remediate.bats` | `chown`/`ensure_marker_block`/`visudo`/recipe re-run are OS-neutral |
| **UX-01..05** (`--dry-run`, prompts, `--yes`, exit codes 64/65/1/0) | `tests/bats/15-preflight-ux.bats` | CLI-level behavior, no OS branch |
| **DOC-02** (`~agent/CLAUDE.md` anti-pattern block) | `plugin/provisioner/10-agent-user.sh` Step 3 | `ensure_marker_block` OS-neutral |

### B.2 Parity — NEEDS EL9 IMPLEMENTATION (same observable behavior, branched impl)

| Behavior / req ID | Ubuntu impl (file) | **EL9 impl required** | Observable assertion preserved |
|-------------------|--------------------|------------------------|-------------------------------|
| **Distro gate** | `plugin/lib/distro_detect.sh` rejects non-Ubuntu, accepts `22.04/24.04/26.04` | Accept `ID=almalinux` + `VERSION_ID=9.*`; export distro **family** (debian/rhel) so provisioners branch | Installer runs on AlmaLinux 9, refuses unsupported |
| **RT-01** (Node 22 LTS present) | `30-nodejs.sh`: `deb.nodesource.com/setup_22.x` + `apt-get install nodejs` | `rpm.nodesource.com/setup_22.x` + `dnf install -y nodejs` (creates `/etc/yum.repos.d/nodesource-nodejs.repo`) | `node --version` ≥ v22 in all six modes |
| **BHV-01 locale** | `10-agent-user.sh`: `locale-gen` + `update-locale` → `/etc/default/locale` | **No `locale-gen`/`update-locale`/`/etc/default/locale` on EL9.** Use `localectl set-locale LANG=C.UTF-8` → `/etc/locale.conf` (C.UTF-8 is a glibc built-in / `glibc-minimal-langpack` provides it; verify via `locale -a \| grep -i c.utf-\?8`) | `LANG`/`LC_ALL`=C.UTF-8; `locale -a` shows `C.utf8` |
| **Pkg auto-install fallbacks** | `20-sudoers.sh` (`apt-get install sudo`), `10-agent-user.sh` (`apt-get install locales`), `30-nodejs.sh` (`apt-get install curl gnupg ca-certificates`) | `dnf install -y sudo` (EL9 ships sudo by default), `dnf install -y glibc-langpack-en`/`glibc-minimal-langpack` if needed, `dnf install -y curl gnupg2 ca-certificates` | Same artefacts present; `visudo`/`curl`/locale available |
| **DET-02** NodeSource/distro arms | `detect/nodejs.sh`: `dpkg-query -W nodejs` + `*-1nodesource*` + `nodesource.{sources,list}` | `rpm -q --qf nodejs` + release-string `nodesource` match + `/etc/yum.repos.d/nodesource-nodejs.repo`; distro arm = AppStream `nodejs` module (`dnf module`) instead of distro APT | Same `{nodejs:[...]}` JSON shape; `nodesource`/`distro`/manager sources classified |
| **REUSE-02** (reuse existing Node) | reads DET-02 outputs | reads EL9 DET-02 outputs (rpm-sourced); decision (`^v?22\.` + writable prefix) unchanged | `30-nodejs.sh` skips install when EL9 Node 22 + writable prefix |
| **INST-04 uninstall** (`--purge`) | removes NodeSource **apt** files | remove `/etc/yum.repos.d/nodesource-nodejs.repo`; optional `dnf remove nodejs` gated by flag; `userdel -r` identical | Purge removes installer-placed files + user |
| **Harness: Docker matrix row** | `tests/docker/Dockerfile.ubuntu-*` (systemd-in-docker, cron, openssh, locales, sudo, bats) | `almalinux:9` systemd image: `cronie`, `openssh-server`, `glibc-langpack-en`, `sudo`, `jq`, `curl`, `python3`; `bats` likely via EPEL or vendored | Full bats suite green on EL9 in CI |
| **Harness: QEMU row** | `tests/qemu/` Ubuntu cloud image + cloud-init | AlmaLinux 9 GenericCloud qcow2 + cloud-init (cloud-init present on Alma cloud images) | Release-gate suite green on EL9 |

### B.3 Genuinely DIFFERENT on EL9 (the expected expectation itself changes)

| Item | Ubuntu expectation | **EL9 expectation** | Action |
|------|--------------------|---------------------|--------|
| Login-shell user init file (§A.3) | `~/.profile` (sources `~/.bashrc`) | `~/.bash_profile` (sources `~/.bashrc` → `/etc/bashrc`); no `~/.profile`; **no non-interactive early-return in skel `~/.bashrc`** | None to code — absorbed by profile.d + `~/.bashrc` marker. **Re-word the `--top` rationale comment** in `40-path-wiring.sh` to be distro-neutral (Ubuntu-only "beat the early-return" claim is false on EL9) |
| Locale tooling (BHV-01) | `locale-gen`/`update-locale`/`/etc/default/locale` exist | None of those exist; `localectl`/`/etc/locale.conf`/`localedef` instead | EL9 impl branch in `10-agent-user.sh` (also listed B.2 — the *tooling* is genuinely different even though the *observable* is identical) |
| Playwright system browser deps (AGT-05, **if** the recipe downloads/runs a browser) | `playwright install-deps` uses apt; ADR-012 sudo auto-prepend | No apt `install-deps` path; browser shared libs come from `dnf install` (nss, atk, at-spi2-atk, cups-libs, libdrm, libXcomposite, libXdamage, libXrandr, mesa-libgbm, alsa-lib, libxshmfence, pango, cairo, …) | EL9 dnf dep list in `playwright-cli/install.sh` system-deps step — **see §E.3 flag** |

---

## C. AGT-02 on EL9 — the canonical gate

`tests/bats/51-agt02-release-gate.bats` runs a real `timeout 120s sudo -u agent -H bash --login -c 'claude update'`, captures the transcript, and asserts `assert_exit_zero` + `assert_no_eacces` + `sort -V` monotonicity. `tests/bats/52-agt02-brownfield-gate.bats` does the same on a pre-populated host after `agentlinux install --yes`.

**What must hold on EL9 for AGT-02 to stay green:**

1. **claude-code native installer is OS-neutral** — `curl -fsSL https://claude.ai/install.sh | bash -s $PINNED` drops a static binary at `~agent/.local/bin/claude` (`plugin/catalog/agents/claude-code/install.sh` line 30, 36). No apt/dpkg dependency. `claude update` rewrites that agent-owned binary in place — the EACCES-free path is purely about *ownership*, which AgentLinux guarantees identically on EL9. **Carries over unchanged.**
2. **`curl` must be present** — EL9 minimal/cloud images may not ship `curl`; the recipe and/or harness must `dnf install -y curl` (the Ubuntu Docker image already special-cases this — `Dockerfile.ubuntu-24.04` lines 78–82).
3. **`~agent/.local/bin` on PATH in the `sudo -u -H bash --login` mode** — provided by `/etc/profile.d/agentlinux.sh` (Artefact 1, §A.2). Carries over.
4. **`jq` present** — the recipe stamps `~/.claude/settings.json` `DISABLE_AUTOUPDATER=1` via `jq` (lines 60–70); `dnf install -y jq` in the EL9 harness (Ubuntu Docker image installs jq for the same reason).
5. **`DISABLE_AUTOUPDATER` settings-stamp** — OS-neutral (`jq` merge into a JSON file). Carries over.

**Conclusion:** AGT-02 requires **no recipe code change** for EL9; it requires the harness to provide `curl` + `jq` and the PATH wiring (already unchanged). It is the lowest-risk part of the port — which is exactly why it remains the milestone-close gate.

---

## D. Detection / Reuse / Remediate / Bail — EL9 evidence sources

Same four-state decision (Reuse / Create / Remediate / Bail per v0.3.4-REQUIREMENTS), re-sourced for EL9. Detection stays read-only (`plugin/lib/detect/*`).

| Probe (req ID) | Ubuntu evidence source | **EL9 evidence source** | Decision logic |
|----------------|------------------------|--------------------------|----------------|
| **DET-01** user | `getent passwd`, `id -nG`, `test -w ~` | **Same** (coreutils) | Reuse if bash + writable home + name match; else Bail/alt-user |
| **DET-02** Node — NodeSource | `dpkg-query -W nodejs` Version `*-1nodesource*` + `nodesource.{sources,list}` | `rpm -q nodejs` (release string contains `nodesource`) + `/etc/yum.repos.d/nodesource-nodejs.repo` | Reuse if `^v?22\.` + writable prefix |
| **DET-02** Node — distro pkg | `dpkg-query` Version without nodesource suffix | `rpm -q nodejs` from AppStream / `dnf module` nodejs | same |
| **DET-02** Node — managers (nvm/fnm/volta/mise/asdf/pnpm) | home-dir file probes (`detect/nodejs.sh` lines 112–117) | **Same** (home-dir paths are distro-neutral) | same |
| **DET-03** npm prefix | `npm config get prefix` + `stat -c %U:%G` + writability | **Same** | Remediate (chown/rebase) if not writable |
| **DET-04** catalog agents | `claude --version`, `get-shit-done-cc --help` banner, `playwright-cli --version`; binary owner; health probe | **Same** (binaries on PATH; GSD also detectable via `~user/.claude/get-shit-done/VERSION` per DET-04 Phase-17 amendment) | Reuse healthy / Remediate broken |
| **DET-05** sudoers | `/etc/sudoers.d/agentlinux` mode + owner + sha256 vs ADR-012 line | **Same** (`/etc/sudoers.d/` + `#includedir` present on EL9) | Remediate on drift |

**Net:** only the **DET-02 system-package arms** need an EL9 branch (`rpm -q` + repo-file path). Every other probe is already distro-neutral. The Reuse/Create/Remediate/Bail tokens and the `tests/bats/{13,14,15}-*.bats` assertions are unchanged.

---

## E. Catalog agents on EL9

The catalog ships three real agents (`plugin/catalog/agents/{claude-code,gsd,playwright-cli}`; `test-dummy` is test-only). No new agents in v0.3.5.

### E.1 claude-code — native installer (AGT-01/02/02b/03)
`curl … claude.ai/install.sh | bash -s $PINNED` → `~agent/.local/bin/claude`. **OS-neutral.** EL9 needs only `curl` + `jq` present (harness). Health: `claude --version` six-mode exit 0; `claude --help` no error tokens; `claude update` zero-EACCES (§C).

### E.2 gsd — npm global (AGT-04)
`npm install -g get-shit-done-cc@$PIN` + `get-shit-done-cc --global --claude` skill bootstrap (`gsd/install.sh`). **OS-neutral** (npm + `~/.claude/skills/` writes). Carries over unchanged. Banner-grep version-lock + `gsd-*` skill-dir assertion both filesystem-level.

### E.3 playwright-cli — npm global + skill wiring (AGT-05) — FLAG
Current recipe (`playwright-cli/install.sh`) is: `npm install -g @playwright/cli@$PIN` (OS-neutral) + `playwright-cli install --skills` writing `~/.claude/skills/playwright-cli/` (OS-neutral). **As written, this recipe does NOT download or launch a Chromium browser**, so it has **no apt/dnf browser-dependency step** — meaning the current AGT-05 form ports to EL9 **unchanged**.

> **Open question for the requirements author:** v0.3.0 AGT-05 historically referenced `npx playwright install` (browser download into `~/.cache/ms-playwright`) **and an ADR-012 sudo-prepend for apt `install-deps`**. The catalog has since narrowed to `@playwright/cli` with `--skills` and (per the file as read) **no browser download**. If any EL9 code path actually launches Chromium, the Ubuntu apt `install-deps` step has **no EL9 equivalent** — browser shared libs must come from an explicit `dnf install` list (nss, atk, at-spi2-atk, cups-libs, libdrm, libXcomposite, libXdamage, libXrandr, mesa-libgbm, alsa-lib, libxshmfence, pango, cairo). **Confirm against the live AGT-05 bats assertion in `tests/bats/50-agents.bats` whether browser download is exercised on EL9 before scoping a dnf-deps task.** This is the single highest-uncertainty item in the catalog port.

---

## F. Table-stakes parity set vs explicitly OUT

### F.1 Table-stakes parity set (v0.3.5 IN — the minimal "done")

- [ ] Full **BHV / RT / AGT / CLI / CAT / INST** bats contract green on AlmaLinux 9 (implementation may branch, contract may not)
- [ ] Six invocation modes resolve agent PATH on EL9 (§A) — four artefacts unchanged
- [ ] **AGT-02** zero-EACCES self-update green on EL9 (§C) — milestone-close gate
- [ ] **DET / REUSE / REMEDIATE / UX** brownfield contract green on EL9 (v0.3.4 carried; DET-02 system arm re-sourced — §D)
- [ ] Distro detect + branch: `distro_detect.sh` accepts AlmaLinux 9; provisioners branch apt→dnf, dpkg→rpm, locale tooling (§B.2/B.3)
- [ ] AlmaLinux 9 Docker matrix row + QEMU cloud-image row, both green in the release gate
- [ ] Catalog recipes verified on EL9 (claude-code, gsd, playwright-cli)

### F.2 Anti-features / explicitly OUT (confirmed from PROJECT.md "Out of Scope")

| Out-of-scope item | Why out | Source |
|-------------------|---------|--------|
| **AlmaLinux 10** | Deferred until first-person friction on it; filed as follow-up then, not pre-emptively | PROJECT.md L133 |
| **RHEL, Rocky, Fedora, CentOS Stream, openSUSE, any other dnf distro** | Until AlmaLinux 9 is the maintainer's daily driver for one release cycle (first-person-friction rule) | PROJECT.md L134 |
| **EL8 (RHEL/Alma 8)** | Not the maintainer's environment; single-version scope keeps matrix small | PROJECT.md L29, L220 |
| **AL-59 alt-user hollow-install wiring** | Distro-independent; touches `20-sudoers/30-nodejs/40-path-wiring` but planned separately under Epic AL-48 to preserve milestone boundary + matrix size | PROJECT.md L38, L135, L221 |
| **New catalog agents** beyond the existing three | Port-only milestone; catalog churn happens in feature milestones | PROJECT.md L137 |
| **Snap / flatpak / alternative packaging** | Out (curl-pipe-bash + optional package only) | PROJECT.md L136 |
| **Multi-arch (ARM)** | x86_64 only (carried forward, permanent for now) | PROJECT.md L167 |

> **The minimal parity set is confirmed: AlmaLinux 9, x86_64, the same three catalog agents, the same behavior contract — and nothing else from the EL family.**

---

## G. Feature dependencies → phase-ordering implications

```
distro_detect.sh (accept AlmaLinux 9 + export family)
    └──required by──> 10-agent-user.sh (EL9 locale: localectl/locale.conf)
    └──required by──> 30-nodejs.sh (rpm.nodesource + dnf install)
                          └──required by──> detect/nodejs.sh (rpm -q DET-02)
                                                └──required by──> REUSE-02 (EL9 Node reuse)
    └──required by──> 20-sudoers.sh (dnf install sudo fallback)

40-path-wiring.sh (four artefacts) ── UNCHANGED, but comment re-word ──> independent of family branch

Docker EL9 row ──gates──> bats contract on EL9 ──gates──> QEMU EL9 row ──gates──> AGT-02 EL9 ──gates──> release tag
```

**Ordering rationale for the roadmapper:**
1. **Distro detection + family branch first** — every provisioner reads it; nothing installs correctly without it.
2. **Node/dnf + locale branch next** — RT-01 and BHV-01 are the foundation the six-mode + agent tests stand on; DET-02 rpm-arm rides alongside the Node branch (same evidence surface).
3. **PATH wiring needs only a comment fix** — lowest effort, can land early; do NOT let the false Ubuntu "early-return" rationale leak into EL9.
4. **Harness (Docker then QEMU)** — Docker EL9 row unblocks fast iteration; QEMU EL9 row is the release gate (systemd/cron/locale faithfulness Docker can't fully reproduce, per ADR-007).
5. **AGT-02 last, as the gate** — it is OS-neutral code (§C); its only EL9 needs (`curl`, `jq`, PATH) are satisfied by steps 1–4. Keep it the milestone-close gate exactly as on Ubuntu.

**Research flags for the roadmapper:**
- **Phase touching `10-agent-user.sh` locale** — needs the EL9 `localectl`/`/etc/locale.conf` path researched concretely (no `locale-gen`/`update-locale`). Medium risk.
- **Phase touching `detect/nodejs.sh`** — rpm release-string format for NodeSource (`*nodesource*`) + AppStream `dnf module` arm needs a real EL9 probe. Medium risk.
- **Phase touching `playwright-cli/install.sh`** — resolve the §E.3 open question (does any EL9 path launch a browser?) before scoping a dnf browser-deps task. Highest uncertainty.
- **Bats availability in the EL9 Docker image** — `bats` is not in base AlmaLinux repos; needs EPEL or a vendored install. Low risk, but a harness gotcha.

---

## Sources

- Repo (HIGH): `plugin/provisioner/40-path-wiring.sh`, `10-agent-user.sh`, `30-nodejs.sh`, `20-sudoers.sh`; `plugin/lib/distro_detect.sh`, `detect/nodejs.sh`, `as_user.sh`; `tests/bats/helpers/invoke_modes.bash`, `51-agt02-release-gate.bats`, `52-agt02-brownfield-gate.bats`; `tests/docker/Dockerfile.ubuntu-24.04`; `plugin/catalog/agents/{claude-code,gsd,playwright-cli}/install.sh`; `.planning/milestones/v0.3.0-REQUIREMENTS.md`, `v0.3.4-REQUIREMENTS.md`; `.planning/PROJECT.md`; `.claude/skills/behavior-test-contract/SKILL.md`.
- EL9 shell init (MEDIUM, multi-source agreement): [Understanding shell profiles in RHEL — Red Hat](https://access.redhat.com/solutions/452073); [Bashrc vs bash_profile — GoLinuxCloud](https://www.golinuxcloud.com/bashrc-vs-bash-profile/); [bashrc vs bash_profile — phoenixNAP](https://phoenixnap.com/kb/bashrc-vs-bash-profile).
- EL9 cron / cron.d (MEDIUM): [System-wide cron directories on RHEL 9 — OneUptime](https://oneuptime.com/blog/post/2026-03-04-system-wide-cron-directories-rhel-9/view); [Set environment variables in cron jobs on RHEL 9 — OneUptime](https://oneuptime.com/blog/post/2026-03-04-set-environment-variables-cron-jobs-rhel-9/view).
- EL9 NodeSource / dnf (MEDIUM-HIGH): [nodesource/distributions setup_22.x (rpm)](https://github.com/nodesource/distributions/blob/master/scripts/rpm/setup_22.x); [rpm.nodesource.com](https://rpm.nodesource.com/); [Install Node.js 22 LTS on Rocky/AlmaLinux — computingforgeeks](https://computingforgeeks.com/install-nodejs-rhel-rocky-almalinux/).
- EL9 locale / C.UTF-8 (MEDIUM-HIGH): [Set up system locale on AlmaLinux 9 — RoseHosting](https://www.rosehosting.com/blog/how-to-set-up-system-locale-on-almalinux-9/); [RHEL 9.0 use C.UTF-8 for glibc-minimal-langpack — osbuild #2206](https://github.com/osbuild/osbuild-composer/issues/2206); [Configure locale on AlmaLinux 9 — LinuxShout](https://linux.how2shout.com/how-to-install-and-configure-locale-on-almalinux-9/).

---
*Feature research for: AlmaLinux 9 distro port (v0.3.5)*
*Researched: 2026-06-27*
