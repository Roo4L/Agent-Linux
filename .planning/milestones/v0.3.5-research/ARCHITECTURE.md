# Architecture Research — v0.3.5 AlmaLinux 9 Support (EL9 port)

**Domain:** Distro-port integration architecture for a bash installer + TS registry CLI + two-tier (Docker/QEMU) test harness
**Researched:** 2026-06-27
**Confidence:** HIGH (every call site verified against source at file:line; external facts — cloud image, Docker tag, NodeSource EL repo path — verified against upstream)

> Scope discipline: this is a PORT, not a redesign. The agent-user model, the CLI/catalog design, and the bats behavior contract are FIXED. The only new structure is a distro-family abstraction so the same installer runs on `apt/dpkg` (Debian-family) and `dnf/rpm` (EL-family) hosts, plus an AlmaLinux 9 row in each harness tier. AlmaLinux 9 ONLY — no Alma 10 / RHEL / Rocky / Fedora.

---

## Standard Architecture

### System Overview — where the distro coupling lives today

```
┌──────────────────────────────────────────────────────────────────────┐
│  ENTRYPOINT   plugin/bin/agentlinux-install                            │
│   • sources lib/distro_detect.sh  ← (1) detection: ubuntu-only gate    │
│   • ensure_jq()                   ← (2) apt-get install jq             │
│   • run_purge()                   ← (2) apt files + apt-get purge      │
├──────────────────────────────────────────────────────────────────────┤
│  LIB    plugin/lib/                                                     │
│   distro_detect.sh   ID==ubuntu gate, exports AGENTLINUX_DISTRO_VERSION │
│   idempotency.sh     ensure_user/ensure_dir/visudo_validate (agnostic) │
│   detect/nodejs.sh   ← (2) dpkg-query + nodesource.{sources,list} gate  │
│   detect/user.sh     ← (2) sudo -u … /usr/bin/apt-get --help probe      │
├──────────────────────────────────────────────────────────────────────┤
│  PROVISIONERS   plugin/provisioner/   (sourced in numeric order)        │
│   10-agent-user.sh   useradd(agnostic) + LOCALE (apt/locale-gen) ←(3)   │
│   20-sudoers.sh      sudoers.d(agnostic) + visudo via apt-get   ←(3)   │
│   30-nodejs.sh       NodeSource APT + apt-get install nodejs    ←(3)   │
│   40-path-wiring.sh  profile.d/.bashrc/env/cron.d   (AGNOSTIC)         │
│   50-registry-cli.sh /opt staging + npm-prefix symlink (AGNOSTIC)      │
├──────────────────────────────────────────────────────────────────────┤
│  HARNESS                                                               │
│   tests/docker/   run.sh + Dockerfile.ubuntu-{22,24,26}.04  ← (4)      │
│   tests/qemu/     boot.sh + cloud-images.txt + cloud-init/  ← (4)      │
│   tests/bats/     CONTRACT — mostly outcome assertions; a FEW           │
│                   Ubuntu-path assertions need parameterizing ← (4)      │
└──────────────────────────────────────────────────────────────────────┘
```

Five touch-areas, numbered to the question. (5) — phase order — closes the doc.

### Component Responsibilities (port lens)

| Component | What changes for EL9 | Shape of the change |
|-----------|----------------------|---------------------|
| `lib/distro_detect.sh` | Accept `ID=almalinux` v9; export a family bucket | Add `AGENTLINUX_DISTRO_FAMILY` (`debian`\|`rhel`); two-arm `case "$ID"` |
| `lib/pkg.sh` (NEW) | Single place to branch apt↔dnf, locale, NodeSource | `pkg_install` / `pkg_is_installed` / `pkg_remove` / `nodesource_setup` / `locale_ensure` |
| `provisioner/10` | Locale provisioning | `/etc/default/locale`+`locale-gen` → `/etc/locale.conf` (C.UTF-8 is a glibc built-in on EL9) |
| `provisioner/20` | Ensure `visudo` present | `apt-get install sudo` → `dnf install -y sudo`; `/etc/sudoers.d` is identical |
| `provisioner/30` | Node 22 install | NodeSource **rpm** repo + `dnf install nodejs` |
| `provisioner/40`,`50` | Nothing | Fully distro-agnostic — POSIX/systemd/cron/npm-prefix paths |
| `detect/nodejs.sh`,`detect/user.sh` | Package-DB + sudo-pkg probe | `dpkg-query`→`rpm -q`; apt repo gate→yum repo gate; `apt-get` probe→`dnf` |
| `tests/docker/*` | Add `almalinux-9` arm | New `Dockerfile.almalinux-9`; param `run.sh` arg; matrix row |
| `tests/qemu/*` | Add `almalinux-9` arm | Manifest row; param `boot.sh`; EL cloud-init seed |
| `tests/bats/*` | Parameterize ~4 Ubuntu-path assertions | locale-conf path, NodeSource repo path, `dpkg-query`→`rpm` |

---

## 1. Distro detection — the family-bucket abstraction

### Current state (verified)

`plugin/lib/distro_detect.sh:29-61` — `detect_distro()` sources `/etc/os-release` inside the function body (`. /etc/os-release`, line 44), hard-rejects unless `ID == ubuntu` (line 46-49), then a `case "$VERSION_ID"` accepts `22.04|24.04|26.04` and **exports `AGENTLINUX_DISTRO_VERSION`** (line 51-60). An escape hatch `AGENTLINUX_SKIP_DISTRO_CHECK=1` exports `AGENTLINUX_DISTRO_VERSION=unchecked` and returns 0 (line 30-34) — used by bats unit sourcing on non-Ubuntu dev hosts.

### AlmaLinux 9 `/etc/os-release` (verified facts)

```
ID="almalinux"
ID_LIKE="rhel centos fedora"
VERSION_ID="9.6"          # 9.x; the cloud image as of research is 9.6
PLATFORM_ID="platform:el9"
```

### Recommendation — minimal two-arm family bucket

Add **one new export** `AGENTLINUX_DISTRO_FAMILY` ∈ {`debian`, `rhel`} alongside the existing `AGENTLINUX_DISTRO_VERSION`. Keep the version export (downstream provisioners already branch on it for the uutils/26.04 case). The bucket is the single switch every other layer reads — provisioners and the `pkg.sh` lib never re-parse `/etc/os-release`.

```bash
# distro_detect.sh — after `. /etc/os-release`
case "${ID:-}" in
  ubuntu)
    export AGENTLINUX_DISTRO_FAMILY=debian
    case "${VERSION_ID:-}" in
      22.04|24.04|26.04) export AGENTLINUX_DISTRO_VERSION="$VERSION_ID" ;;
      *) log_error "unsupported ubuntu version: ${VERSION_ID:-unset}"; return 1 ;;
    esac
    ;;
  almalinux)
    export AGENTLINUX_DISTRO_FAMILY=rhel
    case "${VERSION_ID:-}" in
      9|9.*) export AGENTLINUX_DISTRO_VERSION="$VERSION_ID" ;;   # 9.x only
      *) log_error "unsupported almalinux version: ${VERSION_ID:-unset} (required: 9.x)"; return 1 ;;
    esac
    ;;
  *)
    log_error "unsupported distro: ID=${ID:-unset} (required: ubuntu | almalinux)"
    return 1 ;;
esac
log_info "detected ${ID} ${VERSION_ID} (family=${AGENTLINUX_DISTRO_FAMILY})"
```

**Design notes:**
- **Match on `ID`, not `ID_LIKE`.** The milestone is AlmaLinux-9-only; matching `ID=almalinux` keeps the door explicitly closed to Rocky/RHEL/Fedora (which would match `ID_LIKE` tokens). Family expansion later is a one-line `case` arm, not an `ID_LIKE` heuristic. (`ID_LIKE` is still useful documentation of the bucket rationale, but it should not be the gate — first-person-friction scope rule.)
- **Escape hatch must also seed the family.** `AGENTLINUX_SKIP_DISTRO_CHECK=1` currently only sets `AGENTLINUX_DISTRO_VERSION=unchecked`. It must now also export a family so a unit-sourced `pkg.sh` doesn't dispatch on an empty bucket. Cheapest correct behavior: read `ID` from `/etc/os-release` when present to pick the family, else default `debian`. (Or honor an explicit `AGENTLINUX_DISTRO_FAMILY` override env for cross-distro CI sourcing.)
- This is the **lowest-churn** detection shape: one new export, one added `case` arm, no new file. Downstream consumers read `$AGENTLINUX_DISTRO_FAMILY`.

Confidence: HIGH.

---

## 2. Package-manager abstraction — thin dispatch lib (recommended) vs scattered ifs

### All apt/dpkg/locale/visudo call sites (verified, file:line)

| # | Site | Current call | Family-specific? |
|---|------|--------------|------------------|
| a | `plugin/bin/agentlinux-install:286-287` | `apt-get update` + `apt-get install -y … jq` (`ensure_jq`) | YES |
| b | `plugin/bin/agentlinux-install:387-389` | `rm -f /etc/apt/sources.list.d/nodesource.{sources,list}`, `…/preferences.d/nodejs` (purge) | YES (yum repo path) |
| c | `plugin/bin/agentlinux-install:394-396` | `apt-get purge -y nodejs` + `apt-get autoremove -y` (purge `--remove-nodejs`) | YES |
| d | `plugin/provisioner/10-agent-user.sh:76-80` | `command -v locale-gen`; `apt-get install … locales` | YES (no `locales` pkg on EL9) |
| e | `plugin/provisioner/10-agent-user.sh:85-86` | `locale-gen C.UTF-8`; `update-locale …` | YES (no such tools on EL9) |
| f | `plugin/provisioner/10-agent-user.sh:90` | `locale -a \| grep -Eiq '^c\.utf-?8$'` (verify) | NO — portable outcome check |
| g | `plugin/provisioner/20-sudoers.sh:25-28` | `command -v visudo`; `apt-get install … sudo` | YES (install branch only) |
| h | `plugin/provisioner/30-nodejs.sh:56-58` | `apt-get update` + install `curl gnupg ca-certificates apt-transport-https` | YES |
| i | `plugin/provisioner/30-nodejs.sh:68-74` | gate on `nodesource.{sources,list}`; `curl …deb.nodesource.com/setup_22.x \| bash` | YES |
| j | `plugin/provisioner/30-nodejs.sh:78` | `apt-get install -y … nodejs` | YES |
| k | `plugin/lib/detect/nodejs.sh:84` | `dpkg-query -W -f='${Version}' nodejs` | YES (`rpm -q`) |
| l | `plugin/lib/detect/nodejs.sh:86-87` | gate on `nodesource.{sources,list}` | YES (yum repo path) |
| m | `plugin/lib/detect/user.sh:48` | `sudo -u "$user" -n /usr/bin/apt-get --help` (`can_sudo_apt`) | YES (`/usr/bin/dnf`) |

Distro-agnostic by contrast (no change): `idempotency.sh` `ensure_user`/`ensure_dir`/`visudo_validate`/`write_file_atomic`/`ensure_marker_block` (`useradd`, `install(1)`, `chmod/chown`, `visudo -cf` all exist identically on EL9), and the `/etc/sudoers.d` install in `remediate/sudoers.sh` (the drop-in mechanism, `0440 root:root`, `visudo -cf` gate is standard EL9 sudo).

### Recommendation: a single thin dispatch lib `plugin/lib/pkg.sh` (NEW)

Source it from the entrypoint right after `distro_detect.sh` (`agentlinux-install:154-155`), so every provisioner and detect fragment inherits the helpers. Provide exactly the verbs the 13 sites need:

```bash
pkg_install <pkgs...>        # debian: DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends "$@"
                             # rhel:   dnf install -y "$@"
pkg_is_installed <pkg>       # debian: dpkg-query -W -f='${Status}' | grep -q "install ok installed"
                             # rhel:   rpm -q "$pkg" >/dev/null
pkg_remove <pkg>             # debian: apt-get purge -y ; rhel: dnf remove -y
pkg_autoremove               # debian: apt-get autoremove -y ; rhel: dnf autoremove -y
nodesource_setup             # debian: curl …deb.nodesource.com/setup_22.x | bash -
                             # rhel:   curl …rpm.nodesource.com/setup_22.x | bash -
nodesource_repo_paths        # echo the repo file(s) to gate-on / rm:
                             #   debian: /etc/apt/sources.list.d/nodesource.sources (+ .list legacy, + preferences.d/nodejs)
                             #   rhel:   /etc/yum.repos.d/nodesource-nodejs.repo (+ nodesource-nsolid.repo)
locale_ensure C.UTF-8        # debian: install 'locales' if locale-gen absent; locale-gen; update-locale → /etc/default/locale
                             # rhel:   C.UTF-8 is a glibc built-in (present even with glibc-minimal-langpack); write /etc/locale.conf
                             # both:   verify via `locale -a | grep -Eiq '^c\.utf-?8$'`
```

**Why a lib, not scattered `if [[ $FAMILY == rhel ]]`:** the 13 sites span 5 files. Inlining the branch at each would (1) duplicate the family check ~13×, (2) bloat each provisioner past readability, and (3) give the `bash-engineer`/`qa-engineer` reviewers 13 places to keep in sync. A lib centralizes the branch in one auditable unit with its own bats coverage, and each call site becomes a single readable verb (`pkg_install jq`, `nodesource_setup`). Each provisioner's **observable behavior is unchanged**, which is what keeps the bats contract intact (the contract asserts outcomes — node ≥ 22, sudo works, `C.UTF-8` in `locale -a` — not which package manager produced them).

**Why this is the lowest-churn option that preserves the contract:**
- Call-site diff is mechanical: `DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends jq` → `pkg_install jq`. ~13 line-level edits, no control-flow restructuring.
- The DECIDE-THEN-ACT flow, the `RESOLUTIONS[...]` dispatch in each provisioner, the idempotency primitives, and the entrypoint's source order are all untouched.
- The 6 family-agnostic call sites stay as-is (#f and everything in `idempotency.sh`).

**Anti-pattern rejected:** a full "OS-abstraction layer" with a pluggable driver registry. That is ceremony for a two-distro, single-version target — name the real consumer (one EL9 daily-driver) and ship the minimum-viable branch. Two `case "$AGENTLINUX_DISTRO_FAMILY"` arms per verb is the right size.

`locale_ensure` could alternatively be its own `plugin/lib/locale.sh` if `pkg.sh` gets crowded — but folding it in keeps one new file. Recommend one file unless review pushes back.

Confidence: HIGH (call sites verified; verb set covers all 13).

---

## 3. Per-provisioner branch classification

### `10-agent-user.sh`
| Step | Lines | Classification | EL9 branch |
|------|-------|----------------|-----------|
| `RESOLUTIONS[user]` dispatch | 28-55 | **Agnostic** | none |
| `ensure_user` + `ensure_dir` home | 67-68 | **Agnostic** | `useradd --create-home --shell /bin/bash --user-group` exists on EL9; `/bin/bash` present |
| **Locale provisioning** | 76-94 | **NEEDS EL9 BRANCH** | This is the single biggest provisioner change. On EL9 there is no `locale-gen`, no `update-locale`, no `locales` apt package, and no `/etc/default/locale`. `C.UTF-8` is a **glibc built-in** on EL9 (present even with `glibc-minimal-langpack`), so the rhel arm: optionally `dnf install -y glibc-langpack-en`, then write `LANG=C.UTF-8`/`LC_ALL=C.UTF-8` to **`/etc/locale.conf`** (direct atomic write; avoid `localectl set-locale` which needs `systemd-localed` running — not guaranteed in a Docker test container). Route through `locale_ensure` from `pkg.sh`. |
| Locale verify | 90 | **Agnostic** | `locale -a \| grep -Eiq '^c\.utf-?8$'` already matches EL9's `C.utf8` — the case-insensitive/optional-dash regex was written for exactly this portability. Keep. |
| DOC-02 `CLAUDE.md` marker block | 105-159 | **Agnostic** | `ensure_marker_block` + `chmod`/`chown` |

### `20-sudoers.sh`
| Step | Lines | Classification | EL9 branch |
|------|-------|----------------|-----------|
| Ensure `visudo` present | 25-29 | **NEEDS EL9 BRANCH (install only)** | `apt-get install … sudo` → `pkg_install sudo`. EL9 cloud images ship `sudo`, but the minimal Docker image may not — keep the guard. |
| `ensure_dir /etc/sudoers.d` | 32 | **Agnostic** | identical path on EL9 |
| `RESOLUTIONS[sudoers]` dispatch + `install_or_overwrite` | 41-71 | **Agnostic** | `/etc/sudoers.d/agentlinux` drop-in, `0440 root:root`, `visudo -cf` gate, the ADR-012 `agent ALL=(ALL) NOPASSWD: ALL` line — all standard EL9 sudo. `#includedir /etc/sudoers.d` is default in EL9 `/etc/sudoers`. |

### `30-nodejs.sh`
| Step | Lines | Classification | EL9 branch |
|------|-------|----------------|-----------|
| `RESOLUTIONS[node]` reuse dispatch | 24-49 | **Agnostic** | (reuse check delegates to `detect/nodejs.sh`, see below) |
| Pre-req packages | 56-58 | **NEEDS EL9 BRANCH** | `curl gnupg ca-certificates apt-transport-https` → on EL9 drop `apt-transport-https` (apt-only), use `gnupg2`; `pkg_install curl gnupg2 ca-certificates` |
| NodeSource repo gate + setup | 68-74 | **NEEDS EL9 BRANCH** | gate on **`/etc/yum.repos.d/nodesource-nodejs.repo`** instead of `nodesource.{sources,list}`; `nodesource_setup` runs `curl -fsSL https://rpm.nodesource.com/setup_22.x \| bash -` (verified: writes `/etc/yum.repos.d/nodesource-nodejs.repo`, runs `dnf makecache`) |
| Install `nodejs` | 78 | **NEEDS EL9 BRANCH** | `pkg_install nodejs` → `dnf install -y nodejs` |
| Node ≥ 22 verify | 83-88 | **Agnostic** | `node --version` parse |
| npm-prefix layout + `.npmrc` | 90-119 | **Agnostic** | per-user prefix `~agent/.npm-global` (ADR-004); identical on EL9 |
| npm-prefix `RESOLUTIONS[npm-prefix]` dispatch | 123-149 | **Agnostic** | `chown_or_rebase` etc. |

> **Pitfall flag for the planner:** NodeSource's EL setup script historically mis-detects distros whose `ID_LIKE` lacks a standard RHEL token and bails. AlmaLinux IS officially supported by NodeSource, but verify on the real almalinux:9 image early (Phase 19) — if it ever trips, the documented workaround is touching `/etc/redhat-release` (which AlmaLinux already ships). Treat as a verification item, not a blocker.

### `40-path-wiring.sh`
| Step | Lines | Classification |
|------|-------|----------------|
| All four artefacts (`/etc/profile.d/agentlinux.sh`, `~agent/.bashrc` marker, `/etc/agentlinux.env`, `/etc/cron.d/agentlinux`) | 30-130 | **FULLY AGNOSTIC** |

`/etc/profile.d/*.sh` is sourced by `/etc/profile` on EL9; `/etc/cron.d` is read by `cronie` on EL9 (same vixie-derived semantics — literal `PATH=`, no `$PATH` expansion); systemd `EnvironmentFile` is identical. The `write_file_atomic` helper that dodges uutils' `/dev/stdin` bug (Ubuntu 26.04) is harmless on EL9. The `--top` `.bashrc` marker placement still works against EL9's `/etc/skel/.bashrc` non-interactive early-return. **No code branch.** (One operational note: BHV-03/BHV-04 need `cronie`/systemd present — provided by the Docker image and the cloud image, not by this provisioner.)

### `50-registry-cli.sh`
**FULLY AGNOSTIC.** Stages CLI + catalog under `/opt/agentlinux/`, symlinks `agentlinux` into `~agent/.npm-global/bin`, `as_user agent test -x`. No package-manager, no distro paths. No branch.

### Detect layer (part of the contract via DET/REUSE tests)
| Site | Lines | EL9 branch |
|------|-------|-----------|
| `detect/nodejs.sh` NodeSource gate | 84-90 | `dpkg-query -W nodejs` → `rpm -q nodejs` / `rpm -q --qf '%{VERSION}'`; gate `nodesource.{sources,list}` → `/etc/yum.repos.d/nodesource-nodejs.repo`. The NodeSource version marker `-1nodesource` is a deb-version-string convention; on EL9 the rpm release carries `nodesource` similarly — confirm the substring match against an actual `rpm -q` output in Phase 18/19. |
| `detect/user.sh` `can_sudo_apt` | 41-52, 97-99 | rename/branch to a package-agnostic probe: `sudo -u "$user" -n /usr/bin/dnf --version` on rhel. Keep the absolute-path anchoring rationale (security comment lines 42-46). |

Confidence: HIGH on the agnostic/branch split; MEDIUM on the exact NodeSource rpm version-string marker (verify against real `rpm -q` output).

---

## 4. Harness extension — Docker row + QEMU row

### 4a. Docker (fast path)

**Current matrix definitions (verified):**
- `.github/workflows/test.yml` `bats-docker` job: `matrix.ubuntu: [ubuntu-22.04, ubuntu-24.04, ubuntu-26.04]`.
- `.github/workflows/release.yml` gate-2: `matrix.ubuntu: [ubuntu-22.04, ubuntu-24.04, ubuntu-26.04]` (line 138).
- `tests/docker/run.sh:47-58` whitelist `case`: `ubuntu-22.04 | ubuntu-24.04 | ubuntu-26.04`. Builds `IMG="agentlinux-test:${UBUNTU_VERSION}"`, `DF="$HERE/Dockerfile.${UBUNTU_VERSION}"` (line 62-63). The rest of `run.sh` (systemd-in-Docker boot, CLI-bundle splice, `agentlinux-install`, `bats tests/bats/`) is **distro-agnostic** — it execs inside whatever image the arg names.

**AlmaLinux 9 Docker row — additions:**
1. **NEW `tests/docker/Dockerfile.almalinux-9`** — `FROM almalinux:9` (verified tag; `almalinux:9`, `almalinux:9.8` exist; the rolling `9` tag is the right pin for a "latest 9.x" target). Mirror `Dockerfile.ubuntu-24.04`'s structure:
   - Keep the **`cli-builder` stage `FROM node:22-slim` unchanged** — it is hermetic (no NodeSource touchpoint at build time) and produces the same `dist/` + pruned `node_modules/`. Only the final stage's base changes.
   - Final stage `dnf install -y` the EL9 equivalents of the Ubuntu package set: `systemd systemd-sysv` (→ on EL9 just `systemd`), `cronie` (not `cron`), `openssh-server`, `sudo`, `glibc-langpack-en` (locale), `jq`, `curl`, `python3`, `file`, `util-linux`, `ca-certificates`, `bash`, `coreutils`. **`bats` is NOT in EL9 base/AppStream** → enable EPEL (`dnf install -y epel-release && dnf install -y bats`) or install bats via npm/git. `ShellCheck` is also EPEL-only (optional; debugging convenience).
   - Same systemd-in-Docker recipe: mask `systemd-logind`, `systemd-resolved`, `systemd-networkd`, `systemd-tmpfiles-*`; `ssh-keygen -A`; `VOLUME /sys/fs/cgroup`; `STOPSIGNAL SIGRTMIN+3`; `CMD ["/sbin/init"]`. The runtime flags in `run.sh` (`--privileged --cgroupns=host -e container=docker -v /sys/fs/cgroup:rw --tmpfs /run --tmpfs /tmp`) are distro-agnostic and unchanged.
   - Copy the builder trio to `/opt/cli-prebuilt/{dist,node_modules,package.json}` (identical to Ubuntu Dockerfile lines 131-133); the splice in `run.sh:162-169` is unchanged.
2. **MODIFY `tests/docker/run.sh`** — generalize the arg from "ubuntu version" to "target": add `almalinux-9` to the `case` (line 47-58) and the usage text (line 26). The `IMG`/`DF` interpolation already parameterizes by the arg string, so no other change. Optionally rename the `UBUNTU_VERSION` var to `TARGET` for honesty (cosmetic).
3. **MODIFY `.github/workflows/test.yml`** — add `almalinux-9` to `matrix.ubuntu` (rename the dimension to `target` for clarity; `fail-fast: false` already set so a red Alma arm still reports Ubuntu arms).
4. **MODIFY `.github/workflows/release.yml`** gate-2 matrix (line 138) — add `almalinux-9`.

### 4b. QEMU (release gate)

**Current definitions (verified):**
- `tests/qemu/cloud-images.txt` — three rows, format `<version> <image-url> <sha256sums-url>` (lines 15-17), all `cloud-images.ubuntu.com/.../SHA256SUMS`.
- `tests/qemu/boot.sh` — strips optional `ubuntu-` prefix (line 92-93); `grep`s the manifest row (line 106); maps version→codename `22.04→jammy|24.04→noble|26.04→resolute` (line 115-124); hardcodes `IMG_NAME="ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"` (line 160); verifies via `sha256sum --ignore-missing --check "${RELEASE}-SHA256SUMS"` (line 179); renders `cloud-init/{user-data,meta-data}` (line 240-246); boots; sshes `root@localhost`; runs installer + bats over SSH.
- `cloud-init/user-data` — `packages: [bats, jq, ca-certificates, curl]`; `runcmd: systemctl enable --now ssh`.
- `.github/workflows/nightly-qemu.yml` + `release.yml` gate-3: `matrix.ubuntu: ['22.04','24.04','26.04']`.

**AlmaLinux 9 QEMU row — additions:**
1. **MODIFY `tests/qemu/cloud-images.txt`** — add an Alma row. **Verified image + checksum:** base dir `https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/`. **Pin the dated filename, not `-latest`:** the AlmaLinux `CHECKSUM` file lists the dated artifact (`AlmaLinux-9-GenericCloud-9.6-20250522.x86_64.qcow2`), so the `-latest` symlink name would NOT match a `sha256sum --check` row. Manifest row should carry the dated image URL + the `CHECKSUM` URL. Because the manifest format (codename map, `-server-cloudimg-amd64` naming, GNU `SHA256SUMS`) is Ubuntu-shaped, the cleanest change is to **add a 4th column** (e.g. an explicit cached image filename) or widen the schema so boot.sh doesn't have to synthesize the name.
2. **MODIFY `tests/qemu/boot.sh`** — parameterize four Ubuntu-isms:
   - **arg parse** (line 92-93): also accept `almalinux-9` / `9` and a target family.
   - **codename map** (line 115-124): only needed to build Ubuntu URLs; for Alma there is no codename — skip when family=rhel.
   - **`IMG_NAME`** (line 160): derive from the manifest column instead of the hardcoded `ubuntu-…-cloudimg` pattern.
   - **checksum verify** (line 179): AlmaLinux's `CHECKSUM` is GNU-`sha256sum -c`-compatible, so `sha256sum --ignore-missing --check CHECKSUM` works — but the cached filename must equal the `CHECKSUM` row's filename (hence pinning the dated name in step 1).
   - The `qemu-img` overlay, resize-to-12G, `-cdrom seed.iso`, KVM fail-fast, SSH-over-hostfwd, build-release tarball, scp, in-guest install + bats — all distro-agnostic; unchanged.
3. **NEW `tests/qemu/cloud-init/almalinux-9/user-data`** (EL cloud-init differs):
   - `runcmd: systemctl enable --now sshd` (service is **`sshd`** on EL, not `ssh`).
   - `bats` is not in EL9 base → either `dnf install -y epel-release` first then `bats`, OR (simpler, fewer mirrors) drop bats from cloud-init and rely on the bats binary shipped in the second tarball that `boot.sh` already scps (`node_modules/bats`, line 370-373 / 404-405 — `boot.sh` already prefers `./node_modules/bats/bin/bats`). Recommend the latter: keep the EL seed minimal (`jq`, `ca-certificates`, `curl`) and let the bundled bats run. `meta-data` can be reused as-is (only `instance-id`/`local-hostname`).
   - `disable_root: false` + injected `ssh_authorized_keys` works on EL cloud images (root SSH via key); `ssh_pwauth: false` fine.
4. **MODIFY `.github/workflows/nightly-qemu.yml` + `release.yml` gate-3** — add the Alma arm to the matrix (rename dimension to `target`; the workflow_dispatch `choice` options in nightly need an `almalinux-9` entry too).
5. **MODIFY `docs/HARNESS.md` + `.claude/skills/qemu-harness/SKILL.md`** — add the Alma cloud-image row + the "adding a non-Ubuntu target" touchpoints (the skill's "Adding a new Ubuntu version" section §"four touchpoints" generalizes).

> The qemu-harness skill already anticipated this: its Growth-plan line says "When Fedora / Alma / Arch land as targets, this skill extends with their cloud-image URLs and any distro-specific cloud-init differences." The `sshd`-vs-`ssh` service name and the EPEL/bats gap are exactly those differences.

### 4c. The bats CONTRACT — a FEW Ubuntu-path assertions to parameterize

The contract is mostly outcome-based and ports unchanged, but a grep surfaced assertions that hardcode Ubuntu/apt artifacts. These must become distro-aware so the SAME `@test` passes on both families (the spec stays one contract; only the path it checks branches):

| File:line | Assertion | Fix |
|-----------|-----------|-----|
| `tests/bats/20-agent-user.bats:59,64` | `BHV-01: /etc/default/locale has LANG=/LC_ALL=C.UTF-8` | distro-aware: check `/etc/locale.conf` on rhel. The `locale -a` checks (69-70, and BHV-02/04/05/06 `C.UTF-8` over SSH/systemd/sudo/login) are **already portable** — keep. |
| `tests/bats/10-installer.bats:78,106` | INST-02 byte-stability snapshot lists `/etc/apt/sources.list.d/nodesource.sources` | add the EL repo path; note `find … -type f` silently skips a missing path (`2>/dev/null`), so the test won't *fail* on EL9 — but it would stop verifying the NodeSource file's byte-stability. Branch the path to preserve coverage parity. |
| `tests/bats/40-registry-cli.bats:656-659` | INST-04 purge asserts `nodesource.sources`/`.list` removed | branch to assert `/etc/yum.repos.d/nodesource-nodejs.repo` removed on rhel. |
| `tests/bats/52-agt02-brownfield-gate.bats:122`; `tests/bats/helpers/brownfield.bash:86,139,503` | `dpkg-query -W -f='${Status}' nodejs` to detect/seed Node | branch to `rpm -q nodejs`; the brownfield seed `apt-get install -y nodejs` → `dnf install -y nodejs`. |
| `tests/bats/helpers/brownfield.bash:78,285`; `14-remediate.bats:473,671`; `15-preflight-ux.bats:70` | sudoers fixtures grant `NOPASSWD: /usr/bin/apt-get` | branch the fixture to `/usr/bin/dnf` on rhel (these drive the `can_sudo_apt`→`can_sudo_pkg` probe). |

The cleanest mechanism: a tiny bats helper (e.g. `tests/bats/helpers/distro.bash`) exposing `locale_conf_path`, `nodesource_repo_path`, `pkg_query_installed`, mirroring `pkg.sh`. Keeps the spec single-sourced. This is the "implementation may diverge per distro, the contract must not" rule made concrete.

Confidence: HIGH (matrix defs + bats assertions verified at file:line; cloud image + Docker tag + NodeSource rpm path verified upstream).

---

## 5. Suggested phase/build order (numbering starts at Phase 18)

```
Phase 18  Detection + family bucket + pkg dispatch + per-provisioner branches
   │        (distro_detect.sh family arm; NEW lib/pkg.sh; branch 10/20/30,
   │         detect/nodejs.sh, detect/user.sh, entrypoint ensure_jq+purge)
   ▼
Phase 19  Docker AlmaLinux 9 row  (fast feedback substrate)
   │        (NEW Dockerfile.almalinux-9; param run.sh + test.yml matrix)
   ▼
Phase 20  Behavior-test-green on AlmaLinux 9  (parameterize the ~4 bats path
   │        assertions; NEW helpers/distro.bash; full BHV/RT/AGT/CLI/CAT/INST
   │        contract green in the Alma Docker arm)
   ▼
Phase 21  Catalog verify on EL9  (claude-code/gsd/playwright recipes + AGT-02
   │        self-update green on EL9; surface any chromium EL9 system-lib deps)
   ▼
Phase 22  QEMU release-gate row + pipeline gate  (cloud-images.txt Alma row;
            param boot.sh + EL cloud-init seed; nightly-qemu + release.yml
            gate-2/gate-3 Alma arms; HARNESS.md + qemu skill)  ← milestone exit
```

**Dependency rationale (explicit):**
- **18 is the foundation** — nothing installs on EL9 until detection accepts AlmaLinux and the provisioners branch apt→dnf. Parts of 18 can be unit-sourced on the Ubuntu dev host via `AGENTLINUX_SKIP_DISTRO_CHECK=1` + a `AGENTLINUX_DISTRO_FAMILY=rhel` override, but **real validation requires Phase 19's substrate** — so 18 and 19 are tightly coupled and should be co-developed (18 lands the branch; 19 proves it produces a green install). Treat 19's Docker arm as 18's acceptance gate.
- **19 before 20** — you need a green *install* on Alma before you can iterate the *test suite* to green; and you want the ~90s Docker loop (not the ~5min QEMU loop) for the many small fixes Phase 20 will require.
- **20 before 21** — the catalog/AGT-02 tests run *inside* the bats suite (`50-agents.bats`, `51-agt02-release-gate.bats`); the suite must be green-able first. 21 may surface recipe-level EL9 deps (chromium runtime libs: `nss atk at-spi2-atk libdrm libxkbcommon` etc. under different rpm names) — those are recipe/system-dep fixes, not contract changes.
- **21/20 can overlap** once the Docker arm is green: catalog verification doesn't block the non-agent contract tests.
- **22 last** — QEMU is the slow, authoritative gate (ADR-007: "Docker alone is disqualified"; a red QEMU run blocks the release). Iterate everything in Docker (18-21), then prove it once in QEMU and wire the release-pipeline arm. Per ADR-007 + the project's "QEMU green before any release" rule, **Phase 22 is the milestone exit gate** — AlmaLinux 9 must be green in `release.yml` gate-2 (Docker) AND gate-3 (QEMU) before the v0.3.5 tag.

**New vs modified files (explicit):**

*NEW:*
- `plugin/lib/pkg.sh` — apt↔dnf dispatch + `nodesource_setup` + `locale_ensure`
- `tests/docker/Dockerfile.almalinux-9`
- `tests/qemu/cloud-init/almalinux-9/user-data` (meta-data likely reusable)
- `tests/bats/helpers/distro.bash` — bats-side distro-aware path helpers
- ADR (e.g. `docs/decisions/017-distro-family-bucket.md`) — record the family-bucket + dnf-branch decision

*MODIFIED:*
- `plugin/lib/distro_detect.sh` (family bucket + almalinux arm + escape-hatch family seed)
- `plugin/provisioner/10-agent-user.sh` (locale → `locale_ensure`)
- `plugin/provisioner/20-sudoers.sh` (visudo install → `pkg_install`)
- `plugin/provisioner/30-nodejs.sh` (prereqs + NodeSource + nodejs install branches)
- `plugin/lib/detect/nodejs.sh` (`rpm -q` + yum-repo gate)
- `plugin/lib/detect/user.sh` (`can_sudo_apt` → pkg-agnostic probe)
- `plugin/bin/agentlinux-install` (`ensure_jq` + `run_purge` apt branches)
- `tests/docker/run.sh` (accept `almalinux-9` target)
- `tests/qemu/boot.sh` (target param: prefix/codename/image-name/ssh-service/checksum)
- `tests/qemu/cloud-images.txt` (Alma dated-image row, possibly +1 column)
- `tests/bats/20-agent-user.bats`, `10-installer.bats`, `40-registry-cli.bats`, `52-agt02-brownfield-gate.bats`, `tests/bats/helpers/brownfield.bash`, `14-remediate.bats`, `15-preflight-ux.bats` (distro-aware path/fixtures)
- `.github/workflows/test.yml`, `nightly-qemu.yml`, `release.yml` (matrix arms; rename dimension `ubuntu`→`target`)
- `docs/HARNESS.md`, `.claude/skills/qemu-harness/SKILL.md` (Alma rows + non-Ubuntu touchpoints)

---

## Anti-Patterns (port-specific)

### Anti-Pattern 1: Branching on `ID_LIKE` instead of `ID`
**What people do:** match `ID_LIKE=*rhel*` so "all EL distros" work at once.
**Why it's wrong:** silently pulls in Rocky/RHEL/CentOS-Stream/Fedora that the milestone explicitly defers and that the harness does not test — a green install on an untested distro is a false promise.
**Do this instead:** gate on `ID=almalinux` + `VERSION_ID=9.*`. Family expansion is a future one-line `case` arm with its own harness row.

### Anti-Pattern 2: Scattering `if [[ $FAMILY == rhel ]]` across 13 call sites
**What people do:** inline the package-manager branch at each apt call.
**Why it's wrong:** 13× duplicated family checks across 5 files; reviewers and future distros must chase every site; high drift risk.
**Do this instead:** one `plugin/lib/pkg.sh` with `pkg_install`/`pkg_is_installed`/`nodesource_setup`/`locale_ensure`; each call site becomes one verb.

### Anti-Pattern 3: Using `localectl set-locale` in the locale provisioner
**What people do:** mirror the "official" EL9 way (`localectl set-locale LANG=C.UTF-8`).
**Why it's wrong:** `localectl` talks to `systemd-localed` over D-Bus, which may not be running in a Docker test container (BHV-01 would fail vacuously or hang).
**Do this instead:** write `/etc/locale.conf` directly via the existing atomic primitives; `C.UTF-8` is a glibc built-in on EL9 so no generation step is needed. Verify with the already-portable `locale -a` grep.

### Anti-Pattern 4: Caching the AlmaLinux `-latest` qcow2 against the dated `CHECKSUM`
**What people do:** point the manifest at `AlmaLinux-9-GenericCloud-latest.x86_64.qcow2`.
**Why it's wrong:** the `CHECKSUM` file names the dated artifact, so `sha256sum --check` finds no matching row and either skips silently (`--ignore-missing`) or fails — defeating Pitfall-10 "verify on every cache hit."
**Do this instead:** pin the dated image filename + URL in `cloud-images.txt`; the cached filename then matches a `CHECKSUM` row.

---

## Integration Points

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `distro_detect.sh` → everything | `AGENTLINUX_DISTRO_FAMILY` env export | single switch; provisioners never re-parse os-release |
| `pkg.sh` → provisioners + detect | sourced verbs (`pkg_install`, …) | one place the apt↔dnf branch lives; one place to bats-test it |
| installer → NodeSource | `rpm.nodesource.com/setup_22.x` (rhel) / `deb.nodesource.com` (debian) | writes `/etc/yum.repos.d/nodesource-nodejs.repo`; verify EL9 distro-detect doesn't trip |
| `run.sh`/`boot.sh` → image | arg-named Dockerfile / manifest row | already parameterized by arg; generalize `ubuntu`→`target` |
| bats spec → host | `helpers/distro.bash` path helpers | keeps one contract; branches only the asserted path |
| catalog recipes → EL9 | npm-global + curl native installer | recipes themselves are pkg-manager-free; chromium runtime libs are the one EL9 system-dep risk (Phase 21) |

---

## Sources

- Source-verified at file:line in this repo: `plugin/lib/distro_detect.sh`, `plugin/lib/idempotency.sh`, `plugin/lib/detect/{nodejs,user}.sh`, `plugin/provisioner/{10,20,30,40,50}-*.sh`, `plugin/bin/agentlinux-install`, `tests/docker/{run.sh,Dockerfile.ubuntu-24.04}`, `tests/qemu/{boot.sh,cloud-images.txt,cloud-init/*}`, `tests/bats/*.bats` + `helpers/brownfield.bash`, `.github/workflows/{test,nightly-qemu,release}.yml`, `docs/decisions/007-docker-plus-qemu-harness.md`, `.claude/skills/qemu-harness/SKILL.md` — HIGH.
- AlmaLinux 9 GenericCloud qcow2 + CHECKSUM location: [AlmaLinux repo — 9/cloud/x86_64/images](https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/), [AlmaLinux Wiki — Generic Cloud image](https://wiki.almalinux.org/cloud/Generic-cloud.html) — HIGH.
- `almalinux:9` Docker tag (+ `9-minimal`): [Docker Hub — official almalinux image](https://hub.docker.com/_/almalinux), [AlmaLinux Wiki — Docker images](https://wiki.almalinux.org/containers/docker-images.html) — HIGH.
- NodeSource EL `setup_22.x` writes `/etc/yum.repos.d/nodesource-nodejs.repo`, supports dnf/EL9: [nodesource/distributions scripts/rpm/setup_22.x](https://github.com/nodesource/distributions/blob/master/scripts/rpm/setup_22.x), [rpm.nodesource.com](https://rpm.nodesource.com/) — HIGH.
- EL9 locale (C.UTF-8 glibc built-in; `/etc/locale.conf`; `glibc-langpack-*`; `localectl`): [RHEL 9 — configure system locale](https://oneuptime.com/blog/post/2026-03-04-configure-system-locale-keyboard-layout-rhel-9/view), [osbuild/osbuild-composer #2206 — C.UTF-8 on glibc-minimal-langpack](https://github.com/osbuild/osbuild-composer/issues/2206) — MEDIUM.

---
*Architecture research for: AgentLinux v0.3.5 AlmaLinux 9 distro port*
*Researched: 2026-06-27*
