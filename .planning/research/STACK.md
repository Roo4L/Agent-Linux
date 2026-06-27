# Stack Research — AlmaLinux 9 Port (v0.3.5)

**Domain:** Distro port of an existing curl-pipe-bash installer (apt/Ubuntu → dnf/EL9)
**Researched:** 2026-06-27
**Confidence:** HIGH (NodeSource EL9 script, C.UTF-8-in-glibc, Playwright-no-dnf, curl-minimal conflict all web-verified against current sources)

> Scope reminder: AlmaLinux **9 only**. Everything below is what the STACK must *add or change* for EL9 at parity with the validated Ubuntu path. The agent-user model, per-user npm prefix, "never sudo npm -g", six-mode PATH wiring, registry CLI, catalog design, and bats contract are unchanged and out of scope.

---

## TL;DR for the requirements author

1. **Package manager is the whole job.** Eight call sites invoke `apt-get`/`dpkg`; they need a `pkg::*` abstraction or per-distro branch. Mapping table below; each row cites the exact file:line.
2. **Node.js: keep NodeSource, swap the repo.** Use `rpm.nodesource.com/setup_22.x` + `dnf install --setopt=nodesource-nodejs.module_hotfixes=1 nodejs`. Same Node 22 LTS line, same `-1nodesource` version marker the detect probe already keys on, consistent with ADR-005. The AppStream `nodejs` module is the only landmine and `module_hotfixes=1` defuses it.
3. **Locale gets *simpler*, not harder.** EL9 glibc 2.34 ships `C.UTF-8` built-in — no `locales` package, no `locale-gen`, no `glibc-langpack`. The EL9 branch *deletes* work (skip `locale-gen`/`update-locale`, which are Debian-only).
4. **sudoers is a no-op port.** `/etc/sudoers.d/` + `visudo` + the `agent ALL=(ALL) NOPASSWD: ALL` drop-in behave identically on EL9. `wheel` is irrelevant (we use a per-user file, not group sudo). No EL9 `Defaults` breaks it.
5. **Playwright is the one real catalog risk.** `playwright install-deps` has **no dnf code path** — it shells out to `apt-get` and dies on EL9. The recipe must pre-install chromium runtime deps via `dnf` itself. Claude Code (native glibc binary) and GSD (pure npm) port unchanged.

---

## Recommended Stack

### Core Technologies (EL9 additions / swaps)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **dnf** (full, not microdnf) | EL9 system | Package install / query / remove | Only `dnf` has the `module` subcommand and weak-deps control the installer needs; `microdnf` (AlmaLinux `9-minimal`) lacks both. Target `almalinux:9` + generic-cloud, mirroring the apt-full Ubuntu path. |
| **rpm** | EL9 system | Package presence / version / file-list queries | Direct `dpkg-query` analogue. Detect-layer keys on `%{VERSION}-%{RELEASE}` (carries the `-1nodesource` marker). |
| **NodeSource rpm repo** | `setup_22.x` (EL9) | Node.js 22 LTS | Same upstream + same `-1nodesource` version suffix as the Ubuntu deb path (ADR-005); guarantees Node 22 regardless of AppStream module state. Repo file: `/etc/yum.repos.d/nodesource-nodejs.repo`. |
| **glibc `C.UTF-8`** | glibc 2.34 (EL9 built-in) | LANG/LC_ALL=C.UTF-8 (BHV-01) | Built into EL9 glibc — **no package, no generation**. Replaces the entire `locales`/`locale-gen`/`update-locale` Ubuntu dance. |
| **sudo** (provides `visudo`) | EL9 AppStream/BaseOS | sudoers drop-in validation (BHV-07) | Same package, same `visudo -cf`, same `#includedir /etc/sudoers.d` default. Drop-in content is byte-identical to Ubuntu. |
| **cronie** (provides `crond`) | EL9 BaseOS | `/etc/cron.d/agentlinux` honored (BHV-03) | EL9 cron is `cronie` (Ubuntu = `cron`). **Not guaranteed on cloud/minimal images** — must be ensured for the cron mode to actually fire. |

### Supporting Libraries / Base packages (EL9 dnf names)

Exact EL9 names for the Ubuntu equivalents the installer touches. "Default present" is for the **AlmaLinux 9 Generic Cloud** image and the `almalinux:9` container; flagged where NOT reliably present.

| Ubuntu pkg | EL9 dnf pkg | Default present on EL9? | Notes |
|------------|-------------|-------------------------|-------|
| `curl` | `curl` / `curl-minimal` | ✅ `curl-minimal` (provides `/usr/bin/curl`, HTTPS-capable) | **Do NOT `dnf install curl`** — it conflicts with `curl-minimal` and needs `--allowerasing`. Just use the present binary. |
| `ca-certificates` | `ca-certificates` | ✅ | Idempotent re-install is harmless; usually a no-op. |
| `jq` | `jq` | ❌ not default | In **EL9 AppStream** (no EPEL needed). `ensure_jq` → `dnf install -y jq`. |
| `tar` | `tar` | ✅ | Used by curl-installer tarball extraction. |
| `gzip` | `gzip` | ✅ | As above. |
| `git` | `git` | ❌ not default | EL9 AppStream. Not required by the installer core or the three recipes; install only if a future recipe needs it. |
| `which` | `which` | ✅ (deprecated upstream) | **Not needed** — installer uses `command -v` (shell builtin) everywhere. Do not add a dependency on it. |
| `procps` | `procps-ng` | ⚠️ usually present | Provides `pkill`/`ps` used by `--purge`. Ensure before `pkill -u agent` if targeting a stripped image. |
| `cron` | `cronie` | ❌ not guaranteed | Needed for BHV-03 (`/etc/cron.d/agentlinux`). `dnf install -y cronie && systemctl enable --now crond`. |
| `openssh-server` | `openssh-server` | ✅ on cloud image; ⚠️ on container | Needed only for the BHV-02 (SSH) mode under test; cloud images ship sshd. |
| `sudo` | `sudo` | ✅ cloud; ⚠️ container | `20-sudoers` already installs it if `visudo` missing. |
| `gnupg2` | `gnupg2` | ⚠️ — but **not needed** | apt needed gnupg for repo keys; dnf/rpm verify the NodeSource repo key via `rpm`/`gpgcheck` natively. Drop the gnupg dependency on EL9. |
| `shadow-utils` (useradd/groupadd/userdel) | `shadow-utils` | ✅ | Same `useradd --create-home --shell /bin/bash --user-group` works. |
| `util-linux` | `util-linux` | ✅ | Core; always present. |
| `apt-transport-https` | — | n/a | **Drop entirely** — dnf speaks HTTPS natively. |

### Development / Harness Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Docker image `almalinux:9` | Fast CI matrix row | Full `dnf`. Add as a `tests/docker/Dockerfile.almalinux-9` sibling to the Ubuntu rows. |
| QEMU `AlmaLinux-9-GenericCloud-latest.x86_64.qcow2` | Release-gate row (ADR-007) | cloud-init image; full `dnf`, sshd, sudo, cloud-init present. The systemd/locale/cloud-init paths Docker can't reproduce. |
| `almalinux/9-minimal` (microdnf) | **Avoid** | microdnf lacks `dnf module`; out of scope for v0.3.5. |

---

## The apt→dnf / dpkg→rpm mapping (every row ties to a call site)

| Operation | Ubuntu (current) | EL9 (port) | Call site(s) |
|-----------|------------------|-----------|--------------|
| Refresh metadata | `apt-get update` | (omit — `dnf -y install` refreshes; or `dnf makecache`) | `bin/agentlinux-install:286`, `10-agent-user.sh:78`, `20-sudoers.sh:27`, `30-nodejs.sh:56` |
| Install, no weak deps | `DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends X` | `dnf install -y --setopt=install_weak_deps=False X` | `bin/agentlinux-install:287` (jq), `10-agent-user.sh:79` (locales — **delete**), `20-sudoers.sh:28` (sudo), `30-nodejs.sh:57-58,78` |
| Query presence | `dpkg -s X` | `rpm -q X` | (detect layer) |
| Query version | `dpkg-query -W -f='${Version}\n' nodejs` | `rpm -q --queryformat '%{VERSION}-%{RELEASE}\n' nodejs` | `lib/detect/nodejs.sh:84` |
| List package files | `dpkg -L X` | `rpm -ql X` | (not currently used; for parity) |
| Remove / purge | `apt-get purge -y nodejs` | `dnf remove -y nodejs` | `bin/agentlinux-install:394-395` |
| Autoremove | `apt-get autoremove -y` | `dnf autoremove -y` | `bin/agentlinux-install:396` |
| `noninteractive` env | `DEBIAN_FRONTEND=noninteractive` | (none — `dnf -y` is non-interactive) | all of the above |
| Can-user-sudo-pkgmgr probe | `sudo -u "$user" -n /usr/bin/apt-get --help` | `sudo -u "$user" -n /usr/bin/dnf --help` | `lib/detect/user.sh:48` (field `user.can_sudo_apt`, `render.sh:80`) |
| NodeSource repo files (detect dual-gate) | `/etc/apt/sources.list.d/nodesource.{sources,list}` | `/etc/yum.repos.d/nodesource-nodejs.repo` (+ `nodesource-nsolid.repo`) | `lib/detect/nodejs.sh:86-87`, gate in `30-nodejs.sh:68-69` |
| NodeSource repo files (purge) | rm `…/nodesource.{sources,list}`, `…/preferences.d/nodejs` | rm `/etc/yum.repos.d/nodesource-*.repo` | `bin/agentlinux-install:387-389` |
| Distro gate | `ID==ubuntu && VERSION_ID∈{22.04,24.04,26.04}` | add `ID==almalinux && VERSION_ID=~^9` (or `ID_LIKE` contains `rhel`) | `lib/distro_detect.sh:46-60`, `packaging/curl-installer/install.sh:75-92` |

**Note on `--no-install-recommends`:** the EL9 equivalent is `--setopt=install_weak_deps=False` (RPM "weak deps" = Debian "recommends"). `--nodocs` is a separate, optional size trim.

---

## Node.js on EL9 — chosen path + rationale

**Decision: NodeSource rpm `setup_22.x`, with the module conflict explicitly defused.**

```bash
# EL9 branch of 30-nodejs.sh (replaces the apt pre-reqs + deb setup + apt install)
# curl is already present (curl-minimal); ca-certificates ensure is cheap.
dnf install -y --setopt=install_weak_deps=False ca-certificates

# Idempotent repo add — gate on the .repo file (analogue of the deb822 gate).
if [[ ! -f /etc/yum.repos.d/nodesource-nodejs.repo ]]; then
  curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
fi

# module_hotfixes=1 lets the NodeSource package win over the AppStream nodejs
# module. The setup script does NOT disable the module itself (verified), so
# this flag (or a prior `dnf module reset -y nodejs`) is mandatory.
dnf install -y --setopt=nodesource-nodejs.module_hotfixes=1 nodejs
```

**Why this over the alternatives:**

| Path | Verdict | Why |
|------|---------|-----|
| **NodeSource rpm setup_22.x** ✅ | **Chosen** | Mirrors the validated Ubuntu deb path (ADR-005, RT-01). Guarantees Node 22 LTS. The rpm Version-Release carries the same `-1nodesource` substring (e.g. `2:22.x.x-1nodesource.el9`) that `lib/detect/nodejs.sh` already greps for — only the *query command* changes (`dpkg-query`→`rpm -q`), not the classification logic. |
| AppStream `dnf module install nodejs:22` | Rejected | Stream availability drifts across 9.x minors (18/20 are the reliably-present streams; 22 is not guaranteed on every minor), EL9 doesn't pin a default stream, and it diverges from the "NodeSource everywhere" invariant. Would force the detect probe to learn a second "distro module" source class with no upside. |
| Distro default `dnf install nodejs` | Rejected | Lands whatever the enabled module offers (often 18/20), violating RT-01 (Node 22 LTS). |
| nvm/fnm/volta | Rejected (already) | Per-user version managers are an explicit anti-pattern (CLAUDE.md, DOC-02 body). |

**The module-stream landmine (the one EL9 gotcha):** NodeSource's `setup_22.x` writes the repo but **does not** run `dnf module disable/reset nodejs` (verified by reading the script). Without `module_hotfixes=1`, a host with the AppStream `nodejs` module enabled can shadow the NodeSource package and pull an older Node. `module_hotfixes=1` is the NodeSource-documented fix; `dnf module reset -y nodejs` before install is an equivalent belt-and-braces.

**Detect-probe change (`lib/detect/nodejs.sh`):** swap the Ubuntu dual-gate —
- `dpkg-query -W -f='${Version}\n' nodejs` → `rpm -q --queryformat '%{VERSION}-%{RELEASE}\n' nodejs`
- repo-file gate `nodesource.{sources,list}` → `nodesource-nodejs.repo`
The `*"-1nodesource"*` substring test and the prefix-writability logic stay as-is.

---

## Locale on EL9 — the simplification

**EL9 glibc 2.34 ships `C.UTF-8` as a built-in locale.** No package, no `locale-gen`, no `glibc-langpack`. The Ubuntu block at `10-agent-user.sh:76-94` (install `locales`, run `locale-gen C.UTF-8`, `update-locale`) is **Debian-only** and must be skipped on EL9.

EL9 locale branch:
1. **Skip** `locale-gen` / `update-locale` (both Debian tools; absent on EL9).
2. Verify presence: `locale -a | grep -Eiq '^c\.utf-?8$'` — the existing check (`10-agent-user.sh:90`) works unchanged and passes on EL9 out of the box.
3. System-wide enforcement is already covered by the additive artefacts `40-path-wiring.sh` writes (`/etc/profile.d/agentlinux.sh` and `/etc/agentlinux.env` both `export LANG/LC_ALL=C.UTF-8`). The Debian `/etc/default/locale` write has an EL9 analogue (`/etc/locale.conf`, via `localectl set-locale`) but it is **not required** given those artefacts — keep it out to avoid scope creep.

**On the question's `en_US.UTF-8`:** the behavior contract (BHV-01) is `C.UTF-8`, not `en_US.UTF-8`, so no langpack is needed. *If* `en_US.UTF-8` were ever required, the EL9 package is **`glibc-langpack-en`** (and `localedef -i en_US -f UTF-8 en_US.UTF-8` to generate ad hoc). Documented for completeness; not in v0.3.5 scope.

---

## sudoers on EL9 — confirmed no-op port

| Concern | EL9 reality | Impact on the drop-in |
|---------|-------------|-----------------------|
| `/etc/sudoers.d/` include | Present; `/etc/sudoers` ships `#includedir /etc/sudoers.d` by default | None — same path as Ubuntu (`20-sudoers.sh`, `lib/remediate/sudoers.sh:36`). |
| `visudo -cf` | Same binary (from `sudo` pkg); same validation | None — `lib/remediate/sudoers.sh:60,73` and `lib/idempotency.sh:187` work unchanged. |
| `agent ALL=(ALL) NOPASSWD: ALL` | Valid identical syntax | None — byte-identical drop-in, 0440 root:root. |
| `wheel` group | EL9 admin-group convention (Ubuntu uses `sudo` group) | **Irrelevant** — AgentLinux uses a per-user drop-in file, not group membership. Do not add the agent to `wheel`. |
| `Defaults requiretty` | **Not** set in RHEL 9 default sudoers (removed long ago) | None — no tty needed for non-interactive `sudo -u agent`. |
| `Defaults secure_path` | Set (`/sbin:/bin:/usr/sbin:/usr/bin`), same as Ubuntu | Already handled — `as_user` uses `-E` + the env/profile artefacts carry the agent prefix (the existing Pitfall-1 mitigation applies identically). |
| `!visiblepw` / env_reset | EL9 defaults match Ubuntu's hardening | None affecting a NOPASSWD-ALL grant across the six modes. |

**Verdict:** `20-sudoers.sh` and `lib/remediate/sudoers.sh` need **zero EL9 logic** beyond ensuring the `sudo` package is present (swap the install line `apt-get install sudo` → `dnf install -y sudo` at `20-sudoers.sh:28`).

---

## Catalog recipes on EL9

| Recipe | EL9 status | Change needed |
|--------|-----------|---------------|
| **claude-code** | ✅ Portable as-is | `curl -fsSL https://claude.ai/install.sh \| bash -s <ver>` is a distro-agnostic glibc binary → `~/.local/bin/claude` (RHEL 8+/AlmaLinux 9 officially supported, glibc). The recipe's binary-path check (`~/.local/bin/claude`) already matches. No change. |
| **gsd** | ✅ Portable as-is | Pure `npm install -g get-shit-done-cc` into the per-user prefix. Distro-independent. No change. |
| **playwright-cli** | ⚠️ **Needs an EL9 deps step** | See below — the single real catalog change in v0.3.5. |

### Playwright on EL9 — the deps problem (HIGH confidence, this is the milestone's sharpest edge)

`@playwright/cli install --skills` triggers Playwright's browser-deps install. **Playwright's `install-deps` has no dnf/yum/microdnf code path** — it detects an unknown distro, falls back to assuming Ubuntu 24.04, and shells out to `apt-get`, which fails on EL9 with `sh: apt-get: command not found` (microsoft/playwright #41318, #29559; playwright-python #3087 on Rocky 9). The Ubuntu recipe relies on this auto-deps step running under the NOPASSWD drop-in; on EL9 it cannot work.

**EL9 fix:** pre-install the chromium runtime deps via `dnf` in the recipe **before** the bootstrapper runs, and skip Playwright's own deps step (run the install, let the apt fallback fail-soft, or set the env that suppresses it). Minimal headless-chromium dep set on EL9:

```bash
dnf install -y --setopt=install_weak_deps=False \
  nss nspr atk at-spi2-atk at-spi2-core cups-libs libdrm libxkbcommon \
  libXcomposite libXdamage libXfixes libXrandr libXext libX11 libxcb \
  mesa-libgbm pango cairo alsa-lib expat glib2 gtk3 libgcc \
  liberation-fonts
```

(Fuller GUI set adds `dbus-libs`, `nss-util`, `xdg-utils`, `ca-certificates`, `glibc` — all present in base.) This runs via the agent's NOPASSWD sudo, same as the Ubuntu apt step. Confidence HIGH that dnf-side pre-install is required; the exact minimal list should be pinned by an actual `playwright-cli` headless-chromium smoke on an `almalinux:9` box during the phase.

---

## Installation (EL9 reference snippets)

```bash
# jq (entrypoint ensure_jq, EL9 branch)
dnf install -y --setopt=install_weak_deps=False jq

# sudo/visudo (20-sudoers, EL9 branch)
dnf install -y --setopt=install_weak_deps=False sudo

# cron daemon for BHV-03 (NEW on EL9 — Ubuntu assumed cron present)
dnf install -y cronie && systemctl enable --now crond

# Node 22 LTS (30-nodejs, EL9 branch)
curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
dnf install -y --setopt=nodesource-nodejs.module_hotfixes=1 nodejs
```

---

## What NOT to Use / NOT to Add (explicit list for the porter)

| Avoid | Why | Do instead |
|-------|-----|------------|
| `dnf install curl` | Conflicts with pre-installed `curl-minimal`; needs `--allowerasing` and can break other tooling | Use the present `/usr/bin/curl` (curl-minimal is HTTPS-capable). Only `command -v curl` to confirm. |
| `apt-transport-https` analogue | dnf speaks HTTPS natively | Drop the line entirely. |
| `gnupg2` for repo keys | rpm/dnf verify the NodeSource repo key natively (`gpgcheck`) | Drop the gnupg dependency on EL9. |
| `glibc-langpack-en` / `locale-gen` / `localedef` | `C.UTF-8` is built into EL9 glibc 2.34 | Skip all locale generation; just verify with `locale -a`. |
| `which` package | Installer uses `command -v` | No dependency. |
| Adding `agent` to `wheel` | We grant via a per-user `/etc/sudoers.d/agentlinux`, not group sudo | Keep the existing drop-in; ignore `wheel`. |
| `dnf module install nodejs:22` | Stream availability drifts; diverges from NodeSource invariant | NodeSource `setup_22.x` + `module_hotfixes=1`. |
| `microdnf` / `almalinux/9-minimal` target | No `dnf module`, no weak-deps control | Target full `dnf` (`almalinux:9`, generic-cloud). |
| Relying on Playwright `install-deps`/`--with-deps` on EL9 | No dnf path; falls back to apt-get and fails | Pre-install chromium deps via `dnf` in the recipe. |
| New ADRs/abstractions for "the EL family" | v0.3.5 is AlmaLinux-9-only (first-person-friction rule) | Branch on `ID`/`ID_LIKE`; defer RHEL/Rocky/Fedora/Alma-10. |

---

## Integration shape (not greenfield)

The existing code is a single Ubuntu branch with hardcoded `apt-get`/`dpkg`. Two viable integration patterns; recommend **(A)** for the small, finite call-site count:

- **(A) `lib/pkg.sh` thin abstraction** — `pkg::install`, `pkg::query_version`, `pkg::remove`, `pkg::repo_present`, dispatched on `AGENTLINUX_DISTRO_FAMILY` (set by `distro_detect.sh`). Replaces ~8 raw `apt-get`/`dpkg` sites. Keeps provisioners distro-agnostic; matches the "behavior contract constant, implementation branches" milestone framing.
- **(B) Inline `case "$AGENTLINUX_DISTRO_FAMILY"` per call site** — lower abstraction, more duplication; fine if the porter wants minimal indirection.

`distro_detect.sh` must learn a family token (`debian` vs `rhel`) alongside the version, because downstream provisioners (`30-nodejs.sh`, `10-agent-user.sh`, `20-sudoers.sh`) and `lib/detect/nodejs.sh` + `lib/detect/user.sh` all need to branch. The curl-installer gate (`packaging/curl-installer/install.sh:75-92`) must accept `almalinux` `9` in lockstep (the file already documents the lockstep requirement).

---

## Alternatives Considered

| Recommended | Alternative | When the alternative would win |
|-------------|-------------|--------------------------------|
| NodeSource rpm setup_22.x | AppStream `nodejs:22` module | If a future milestone wanted zero third-party repos and EL9 reliably shipped a 22 stream — not today. |
| `module_hotfixes=1` | `dnf module reset -y nodejs` before install | Equivalent; `reset` is more explicit but adds a step. Either is acceptable; pick one and keep it byte-stable. |
| `lib/pkg.sh` abstraction | Inline per-site `case` | Inline is fine given only ~8 sites; abstraction pays off if Rocky/RHEL land later. |
| Pre-install chromium deps via dnf | Pin a Playwright env that skips deps + document manual install | Only if upstream Playwright ships a dnf path (open feature request #41318 — not implemented as of 2026-06). |

---

## Version Compatibility

| Component | Compatible with | Notes |
|-----------|-----------------|-------|
| NodeSource `nodejs` rpm `2:22.x-1nodesource.el9` | AlmaLinux 9.x | `module_hotfixes=1` required to beat the AppStream module. |
| `C.UTF-8` | glibc ≥ 2.34 (EL9) | Built-in; verify via `locale -a`. EL9 minor updates do not regress this. |
| Claude Code native installer | glibc-based EL (RHEL/Alma 8+) | Bundled ripgrep is glibc — fine on EL9 (the musl caveat is Alpine-only). |
| `@playwright/cli` chromium | EL9 + manual dnf deps | Browser binary itself runs once the dnf-side libs are present; only the auto-deps installer is apt-bound. |

---

## Sources

- NodeSource `setup_22.x` (rpm) — https://github.com/nodesource/distributions/blob/master/scripts/rpm/setup_22.x — verified: writes `/etc/yum.repos.d/nodesource-nodejs.repo`, uses dnf, **does not** disable the AppStream module. HIGH.
- NodeSource RPM landing — https://rpm.nodesource.com/ — `module_hotfixes=1` / `--setopt=nodesource-nodejs.module_hotfixes=1` documented for EL8/9 module-conflict bypass; version format `2:<ver>-1nodesource`. HIGH.
- AlmaLinux Wiki, Application Streams — https://wiki.almalinux.org/series/system/SystemSeriesA01.html — EL9 modularity / nodejs streams (18/20 reliably present, no pinned default). MEDIUM-HIGH.
- microsoft/playwright #41318, #29559; microsoft/playwright-cli #309; playwright-python #3087 — https://github.com/microsoft/playwright/issues/41318 — `install-deps` has no dnf path, apt-get fallback fails on Rocky/Alma 9. HIGH.
- Chromium RPM deps (Fedora `chromium.spec`; Remotion Linux deps) — https://src.fedoraproject.org/rpms/chromium/blob/rawhide/f/chromium.spec , https://www.remotion.dev/docs/miscellaneous/linux-dependencies — canonical EL chromium runtime dep set. MEDIUM-HIGH (pin exact minimal list via on-box smoke).
- glibc `C.UTF-8` built-in on EL9 — https://www.rosehosting.com/blog/how-to-set-up-system-locale-on-almalinux-9/ , https://linux.how2shout.com/how-to-install-and-configure-locale-on-almalinux-9/ — C.UTF-8 present without langpacks; langpacks are split `glibc-langpack-*`. HIGH.
- curl-minimal conflict — https://www.jeffgeerling.com/blog/2024/fixing-curl-install-failures-ansible-on-red-hat-derivative-oses/ — `dnf install curl` conflicts with `curl-minimal`, needs `--allowerasing`. HIGH.
- microdnf in `almalinux/9-minimal` — https://hub.docker.com/r/almalinux/9-minimal , devcontainers/features #774 — minimal image uses microdnf (no `module`). HIGH.
- Claude Code native installer distro support — https://code.claude.com/docs/en/setup , https://www.morphllm.com/claude-code-linux — RHEL 8+/glibc supported; binary at `~/.local/bin/claude`. MEDIUM-HIGH.
- AlmaLinux cloud-images (Packer) — https://github.com/AlmaLinux/cloud-images — generic-cloud baseline (full dnf, cloud-init, sshd, sudo). MEDIUM.

Code call sites cited from the worktree (`plugin/…`, `packaging/…`) read directly, not from the web.

---
*Stack research for: AlmaLinux 9 port of the AgentLinux installer (v0.3.5)*
*Researched: 2026-06-27*
