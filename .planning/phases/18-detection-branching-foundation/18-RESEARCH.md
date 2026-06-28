# Phase 18: Detection + Branching Foundation - Research

**Researched:** 2026-06-28
**Domain:** Distro-port infrastructure — generalize an Ubuntu-only bash installer to also run on AlmaLinux 9 (apt→dnf, dpkg→rpm, locale-gen→/etc/locale.conf, NodeSource APT→RPM) behind a single `AGENTLINUX_DISTRO_FAMILY` abstraction
**Confidence:** HIGH (every call site re-verified at file:line against current code; NodeSource RPM mechanism confirmed verbatim upstream; one residual unknown — exact `rpm -q` release string — scoped to live Docker verification per STATE.md concern)

## Summary

Phase 18 is the load-bearing foundation of the v0.3.5 AlmaLinux 9 port. Nothing
else installs on EL9 until `distro_detect.sh` stops hard-rejecting AlmaLinux and
the ~13 hardcoded `apt-get`/`dpkg`/`locale-gen` call sites route through a new
package-manager-neutral dispatch layer (`lib/pkg.sh`) that branches on a new
`AGENTLINUX_DISTRO_FAMILY` ∈ `{debian, rhel}` export. This is a **port, not a
redesign**: the bats behavior contract asserts *outcomes* (node ≥ 22, sudo works,
`C.UTF-8` in `locale -a`, NodeSource classification), not which package manager
produced them — so the entire job is mechanical call-site substitution behind one
auditable abstraction, with **Ubuntu behavior preserved byte-for-byte**.

The five EL9 facts that drive the implementation are all verified: (1) NodeSource
RPM `setup_22.x` writes `/etc/yum.repos.d/nodesource-nodejs.repo`, sets
`module_hotfixes=1`, imports GPG key `ns-operations-public.key`, and does **not**
reset the AppStream `nodejs` module (so brownfield robustness needs an explicit
`dnf module reset nodejs`); (2) `C.UTF-8` is a glibc 2.34 built-in on EL9 — no
`locale-gen`, no langpack, just a direct write to `/etc/locale.conf`; (3) the
sudoers drop-in is byte-identical on EL9 (only the `sudo`-package-install verb
changes); (4) `dnf install curl` must be avoided (curl-minimal conflict) and
`apt-transport-https`/`gnupg` dropped; (5) the brownfield detector keys on a
`nodesource` substring in `rpm -q --qf '%{VERSION}-%{RELEASE}' nodejs` plus the
yum repo file, replacing the dpkg dual-gate.

The single contract-preservation trap a planner must encode: the DET-01 JSON field
is named `user.can_sudo_apt` and is asserted by the bats suite + `render.sh`. The
**probe** generalizes (apt-get→dnf on rhel) but the **field name must stay
`can_sudo_apt`** — renaming it would break the behavior contract. The same
"implementation branches, observable holds" rule governs every change in this
phase.

**Primary recommendation:** Build `lib/pkg.sh` FIRST (sourced from the entrypoint
immediately after `distro_detect.sh`), give `distro_detect.sh` an `almalinux` arm
that also seeds `AGENTLINUX_DISTRO_FAMILY`, then convert each of the 13 call sites
to a single verb (`pkg_install jq`, `nodesource_setup`, `locale_ensure C.UTF-8`).
Never inline `if [[ $FAMILY == rhel ]]` at call sites. Keep all JSON contract field
names. Validate against Phase 19's `almalinux:9` Docker substrate — unit-sourcing
on the Ubuntu dev host only proves the abstraction surface.

## Architectural Responsibility Map

This phase is a single-tier system installer (no client/server/CDN tiers). The
relevant "tiers" are the installer's internal strata; mapping confirms each
capability lands in the correct stratum and not, e.g., inline in a provisioner.

| Capability | Primary Stratum | Secondary Stratum | Rationale |
|------------|-----------------|-------------------|-----------|
| Distro recognition + family bucket | `lib/distro_detect.sh` | — | Single fork point; every consumer reads `$AGENTLINUX_DISTRO_FAMILY`, never re-parses os-release |
| Package install/query/remove verbs | `lib/pkg.sh` (NEW) | — | One auditable place the apt↔dnf branch lives; the 13 sites become verbs |
| NodeSource repo setup + repo-path knowledge | `lib/pkg.sh` (`nodesource_setup`, `nodesource_repo_paths`) | `provisioner/30-nodejs.sh` (gate), `bin/agentlinux-install` (purge) | Repo mechanism differs by family; centralize so install + detect + purge agree |
| Locale provisioning | `lib/pkg.sh` (`locale_ensure`) | `provisioner/10-agent-user.sh` (caller) | EL9 path *deletes* the locale-gen block; the branch belongs in the verb, not the provisioner |
| Sudoers `sudo`-package presence | `lib/pkg.sh` (`pkg_install sudo`) | `provisioner/20-sudoers.sh` | Only the install verb changes; drop-in install/validate is distro-agnostic |
| Brownfield Node classification | `lib/detect/nodejs.sh` | `lib/pkg.sh` (query verbs) | Detection infrastructure stratum (per SUMMARY: DET-02 rpm arm is Phase 18, not catalog) |
| Brownfield sudo-capability probe | `lib/detect/user.sh` | — | Generalize probe binary; **preserve `can_sudo_apt` JSON field name** |
| Curl-installer pre-gate | `packaging/curl-installer/install.sh` | — | Must accept `almalinux 9.*` in lockstep with `distro_detect.sh` |

## Standard Stack

This is a port; the "stack" is the set of EL9 tools/mechanisms that replace the
Ubuntu ones. No new third-party libraries are added.

### Core
| Tool / Mechanism | Version | Purpose | Why Standard |
|------------------|---------|---------|--------------|
| `dnf` (full, not microdnf) | EL9 system | install/query/remove/module | Only full `dnf` has the `module` subcommand + weak-deps control; `almalinux/9-minimal` (microdnf) is out of scope [VERIFIED: STACK.md call-site analysis] |
| `rpm -q` | EL9 system | package presence + version-release query | Direct `dpkg-query` analogue; keys on `%{VERSION}-%{RELEASE}` [VERIFIED: repo code at detect/nodejs.sh:84] |
| NodeSource RPM `setup_22.x` | EL9 (`pub_22`/`nodistro`) | Node.js 22 LTS | Mirrors the validated Ubuntu deb path (ADR-005); guarantees Node 22 regardless of AppStream module state; repo file `/etc/yum.repos.d/nodesource-nodejs.repo`, `module_hotfixes=1`, gpgkey `ns-operations-public.key` [VERIFIED: fetched setup_22.x 2026-06-28] |
| glibc `C.UTF-8` built-in | glibc 2.34 (EL9) | LANG/LC_ALL=C.UTF-8 (BHV-01) | Built into EL9 glibc — no package, no generation; write `/etc/locale.conf` directly [CITED: osbuild-composer#2206; rosehosting/how2shout EL9 locale guides] |
| `sudo` / `visudo` | EL9 BaseOS | sudoers drop-in validation | Same binary, same `visudo -cf`, same `#includedir /etc/sudoers.d` default; drop-in byte-identical [CITED: access.redhat.com/solutions/1298644] |

### Supporting (package-name drift map — `dnf install <debian-name>` 404s otherwise)
| Need | Ubuntu name (in code today) | EL9 dnf name | Default present on `almalinux:9`? |
|------|------------------------------|--------------|-----------------------------------|
| HTTPS fetch | `curl` | `curl` / `curl-minimal` | ✅ — **do NOT `dnf install curl`** (curl-minimal conflict; needs `--allowerasing`) [CITED: jeffgeerling.com curl-minimal] |
| JSON | `jq` | `jq` (AppStream) | ❌ — `pkg_install jq` |
| GnuPG for repo key | `gnupg` | — | **Drop** — dnf/rpm verify NodeSource key natively via `gpgkey=`+`gpgcheck=1` |
| apt HTTPS transport | `apt-transport-https` | — | **Drop entirely** — dnf speaks HTTPS natively |
| en_US locale (not needed; C.UTF-8 only) | `locales` | `glibc-langpack-en` | n/a — C.UTF-8 is built-in, no langpack |
| cron daemon (Phase 19 image, not provisioner) | `cron` | `cronie` | ❌ not guaranteed |
| ps/pkill (purge) | `procps` | `procps-ng` | ⚠️ usually present |
| ss (sshd poll, harness) | `iproute2` | `iproute` | ⚠️ |

### Alternatives Considered
| Instead of | Could Use | Tradeoff (why rejected) |
|------------|-----------|-------------------------|
| NodeSource RPM `setup_22.x` | AppStream `dnf module install nodejs:22` | Stream availability drifts across 9.x minors (18/20 reliable, 22 not guaranteed); no pinned default; diverges from the NodeSource-everywhere invariant (RT-01) |
| `module_hotfixes=1` (greenfield) | `dnf module reset nodejs` before install | Equivalent for greenfield; `reset` additionally clears an *already-installed* AppStream stream → **use BOTH**: rely on `module_hotfixes` (set by setup script) + add an explicit `dnf -y module reset nodejs` (non-fatal) for brownfield robustness |
| `lib/pkg.sh` thin dispatch | Inline `case "$FAMILY"` per call site | 13× duplicated branch across 5 files; unauditable drift; rejected (Anti-Pattern 2) |
| Write `/etc/locale.conf` directly | `localectl set-locale` | `localectl` needs `systemd-localed` over D-Bus — not guaranteed in Docker test containers; would hang/fail vacuously (Anti-Pattern 3) |

**Installation:** No package installs needed to develop Phase 18 on the Ubuntu dev
host. Real validation requires the `almalinux:9` Docker image (Phase 19, co-developed).
Unit-source on the dev host via:
```bash
AGENTLINUX_SKIP_DISTRO_CHECK=1 AGENTLINUX_DISTRO_FAMILY=rhel bash -c '. plugin/lib/log.sh; . plugin/lib/distro_detect.sh; . plugin/lib/pkg.sh; ...'
```

**Version verification:** No npm packages in scope. The one version-sensitive fact
— the NodeSource `nodejs` RPM `%{VERSION}-%{RELEASE}` string — is NOT verifiable
on this Ubuntu dev host and is scoped to live confirmation on `almalinux:9` in
Phase 18/19 (see Open Questions Q1; STATE.md concern). Confirmed upstream:
`module_hotfixes=1`, repo path, GPG key URL all verbatim from `setup_22.x` (fetched 2026-06-28).

## Architecture Patterns

### System Architecture Diagram — distro fork flow

```
                         /etc/os-release
                              │
                              ▼
            ┌───────────────────────────────────┐
            │  lib/distro_detect.sh               │
            │  detect_distro()                    │
            │   case "$ID":                       │
            │     ubuntu    → FAMILY=debian       │
            │     almalinux → FAMILY=rhel (9.* ok)│
            │     *         → reject (clear msg)  │
            │   exports AGENTLINUX_DISTRO_FAMILY  │ ◄── single fork point
            │           + AGENTLINUX_DISTRO_VERSION│
            └───────────────────────────────────┘
                              │ $AGENTLINUX_DISTRO_FAMILY
              ┌───────────────┼──────────────────────────────┐
              ▼               ▼                              ▼
   ┌──────────────────┐  ┌──────────────────┐   ┌──────────────────────┐
   │  lib/pkg.sh (NEW)│  │  provisioners     │   │  lib/detect/*         │
   │  branches once   │  │  call verbs only  │   │  classify by family   │
   │   pkg_install    │◄─┤  10: locale_ensure│   │  nodejs.sh: rpm -q +  │
   │   pkg_is_installed│  │  20: pkg_install  │   │    yum repo gate +    │
   │   pkg_remove     │  │      sudo         │   │    AppStream arm      │
   │   pkg_autoremove │  │  30: nodesource_  │   │  user.sh: dnf probe   │
   │   nodesource_setup│ │      setup +      │   │    (field name UNCHANGED│
   │   nodesource_     │  │      pkg_install  │   │     = can_sudo_apt)   │
   │     repo_paths    │  │      nodejs       │   └──────────────────────┘
   │   locale_ensure   │  │  40/50: AGNOSTIC  │
   └──────────────────┘  └──────────────────┘
              │                                          ▲
              ▼                                          │
   debian arm: apt-get/dpkg/locale-gen          rhel arm: dnf/rpm/locale.conf
   (BYTE-FOR-BYTE PRESERVED)                     (NEW)

   Lockstep pre-gate (separate entry path):
   packaging/curl-installer/install.sh  detect_ubuntu_version() → accept almalinux 9.*
```

A reader can trace a fresh EL9 install: os-release → `detect_distro` sets
FAMILY=rhel → entrypoint sources `pkg.sh` → `ensure_jq` calls `pkg_install jq`
(→ `dnf install -y jq`) → provisioner 10 calls `locale_ensure C.UTF-8`
(→ write `/etc/locale.conf`) → provisioner 30 calls `nodesource_setup`
(→ `curl rpm.nodesource.com/setup_22.x | bash`) + `pkg_install nodejs` → detect
layer classifies any pre-existing Node via `rpm -q` + yum repo gate.

### Recommended Project Structure (files touched in Phase 18)
```
plugin/
├── lib/
│   ├── distro_detect.sh        # MODIFY: almalinux arm + FAMILY export + escape-hatch seed
│   ├── pkg.sh                  # NEW: the single apt↔dnf branch (all 13 sites)
│   └── detect/
│       ├── nodejs.sh           # MODIFY: rpm -q + yum repo gate + AppStream arm
│       └── user.sh             # MODIFY: dnf probe; KEEP can_sudo_apt field name
├── provisioner/
│   ├── 10-agent-user.sh        # MODIFY: locale block → locale_ensure C.UTF-8
│   ├── 20-sudoers.sh           # MODIFY: apt-get install sudo → pkg_install sudo
│   ├── 30-nodejs.sh            # MODIFY: prereqs + NodeSource + nodejs via pkg.sh; + dnf module reset
│   └── 40-path-wiring.sh       # MODIFY (optional): distro-neutral comment reword only — NO code change
├── bin/
│   └── agentlinux-install      # MODIFY: ensure_jq + run_purge apt branches → pkg.sh; source pkg.sh
packaging/curl-installer/
    └── install.sh              # MODIFY: detect_ubuntu_version → accept almalinux 9.* (lockstep)
docs/decisions/
    └── 017-distro-family-bucket.md  # NEW: ADR recording the family-bucket + dnf-branch decision
```

### Pattern 1: Family-bucket export in `distro_detect.sh`
**What:** Add one new export `AGENTLINUX_DISTRO_FAMILY` and one `case "$ID"` arm.
Keep the existing `AGENTLINUX_DISTRO_VERSION` export (downstream still branches on it).
**When to use:** The single fork point; every other layer reads the env var, never re-parses os-release.
**Example:**
```bash
# Source: ARCHITECTURE.md §1 + current distro_detect.sh:44-60 [VERIFIED in repo]
. /etc/os-release   # scoped inside detect_distro()
case "${ID:-}" in
  ubuntu)
    export AGENTLINUX_DISTRO_FAMILY=debian
    case "${VERSION_ID:-}" in
      22.04|24.04|26.04) export AGENTLINUX_DISTRO_VERSION="$VERSION_ID" ;;
      *) log_error "unsupported ubuntu version: ${VERSION_ID:-unset} (required: 22.04, 24.04 or 26.04)"; return 1 ;;
    esac ;;
  almalinux)
    export AGENTLINUX_DISTRO_FAMILY=rhel
    case "${VERSION_ID:-}" in
      9|9.*) export AGENTLINUX_DISTRO_VERSION="$VERSION_ID" ;;   # 9.x ONLY
      *) log_error "unsupported almalinux version: ${VERSION_ID:-unset} (required: 9.x)"; return 1 ;;
    esac ;;
  *)
    log_error "unsupported distro: ID=${ID:-unset} (required: ubuntu | almalinux)"
    return 1 ;;
esac
```
**Escape-hatch fix (EL-01 explicit):** `AGENTLINUX_SKIP_DISTRO_CHECK=1` currently only
seeds `AGENTLINUX_DISTRO_VERSION=unchecked` (distro_detect.sh:30-34). It MUST now also
seed a family so a unit-sourced `pkg.sh` doesn't dispatch on an empty bucket. Honor an
explicit `AGENTLINUX_DISTRO_FAMILY` override env if set; else read `ID` from
`/etc/os-release` when present; else default `debian`.

### Pattern 2: Thin verb dispatch in `lib/pkg.sh`
**What:** Exactly the verbs the 13 sites need, each a two-arm `case`. No driver registry.
**When to use:** Source from the entrypoint right after `distro_detect.sh` (line 155),
before `idempotency.sh`/`as_user.sh`, so every provisioner + detect fragment inherits it.
Verbs branch at call-time on `$AGENTLINUX_DISTRO_FAMILY` (set when `detect_distro` runs at
entrypoint line 435 — after sourcing, before any verb call).
**Example:**
```bash
# Source: ARCHITECTURE.md §2 verb set + STACK.md apt→dnf mapping [VERIFIED call sites]
pkg_install() {   # debian: apt-get update && apt-get install -y --no-install-recommends "$@"
  case "$AGENTLINUX_DISTRO_FAMILY" in
    debian) DEBIAN_FRONTEND=noninteractive apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" ;;
    rhel)   dnf install -y --setopt=install_weak_deps=False "$@" ;;   # weak_deps ≈ --no-install-recommends
  esac
}
pkg_is_installed() {  # debian: dpkg-query Status; rhel: rpm -q
  case "$AGENTLINUX_DISTRO_FAMILY" in
    debian) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed" ;;
    rhel)   rpm -q "$1" >/dev/null 2>&1 ;;
  esac
}
nodesource_setup() {  # debian: deb.nodesource.com; rhel: rpm.nodesource.com
  case "$AGENTLINUX_DISTRO_FAMILY" in
    debian) curl -fsSL https://deb.nodesource.com/setup_22.x | bash - ;;
    rhel)   curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - ;;
  esac
}
locale_ensure() {  # debian: install locales + locale-gen + update-locale; rhel: write /etc/locale.conf
  case "$AGENTLINUX_DISTRO_FAMILY" in
    debian) command -v locale-gen >/dev/null 2>&1 || pkg_install locales
            locale-gen "$1" >/dev/null 2>&1 || true
            update-locale "LANG=$1" "LC_ALL=$1" ;;          # writes /etc/default/locale
    rhel)   printf 'LANG=%s\nLC_ALL=%s\n' "$1" "$1" | write_file_atomic 0644 /etc/locale.conf ;;  # C.UTF-8 glibc built-in
  esac
  locale -a 2>/dev/null | grep -Eiq '^c\.utf-?8$'   # already-portable correctness gate (keep)
}
```
Note: `write_file_atomic <mode> <dest>` exists (idempotency.sh:39) and reads content
from stdin — confirm the exact stdin/arg convention when wiring `locale_ensure`.

### Pattern 3: NodeSource RPM install in `30-nodejs.sh`
```bash
# Source: fetched setup_22.x (2026-06-28) + STACK.md [VERIFIED upstream]
# Pre-reqs: drop apt-transport-https + gnupg on rhel; ca-certificates only (curl already present)
pkg_install ca-certificates              # NEVER pkg_install curl on rhel (curl-minimal conflict)
dnf -y module reset nodejs || true       # rhel only, brownfield robustness — non-fatal (setup script does NOT reset)
# Idempotent gate on the repo file (analogue of the deb822 dual-gate):
if [[ ! -f /etc/yum.repos.d/nodesource-nodejs.repo ]]; then nodesource_setup; fi
pkg_install nodejs                        # → dnf install -y nodejs ; module_hotfixes=1 lets NodeSource win
# KEEP the RT-01 post-install `node --version` >= 22 hard-check (30-nodejs.sh:83-88) — it already
# catches "AppStream's older module won the resolution".
```

### Anti-Patterns to Avoid
- **Branching on `ID_LIKE` instead of `ID`:** `ID_LIKE="rhel centos fedora"` would silently
  admit Rocky/RHEL/CentOS/Fedora — out of scope, untested, a false promise. Gate on `ID=almalinux`.
- **Scattering `if [[ $FAMILY == rhel ]]` across 13 sites:** 13× duplicated drift across 5 files. Build `pkg.sh` first.
- **`localectl set-locale`:** needs systemd-localed/D-Bus, absent in Docker. Write `/etc/locale.conf` directly.
- **`dnf install curl`:** conflicts with `curl-minimal`. Use the present binary.
- **Renaming the `can_sudo_apt` JSON field:** breaks the DET-01 contract + bats assertions. Generalize the *probe*, keep the *field name*.
- **`setenforce 0`:** out of Phase 18 scope (SELinux is EL-06/Phase 20) but never the fix — restorecon, not policy downgrade.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| NodeSource repo config + GPG | A hand-written `.repo` file + `rpm --import` | `curl rpm.nodesource.com/setup_22.x \| bash -` (`nodesource_setup`) | Setup script writes the repo, sets `module_hotfixes=1`, configures `gpgkey=` + `gpgcheck=1` — verified verbatim; same ADR-005 acceptance as the deb path |
| AppStream module conflict resolution | Custom version-pinning / exclude rules | `module_hotfixes=1` (greenfield, set by setup script) + `dnf -y module reset nodejs` (brownfield) | The documented NodeSource fix; reinventing it invites the RT-01 failure mode |
| C.UTF-8 locale generation | `localedef`/`glibc-langpack`/`locale-gen` | Direct `/etc/locale.conf` write (it's a glibc 2.34 built-in) | EL9 ships C.UTF-8; any generation step is dead code that can fail/hang |
| Atomic config file write | `cat >` / `tee` / temp-file dance | `write_file_atomic 0644 /etc/locale.conf` (idempotency.sh:39) | Existing primitive dodges the uutils `/dev/stdin` bug + guarantees atomicity |
| Package presence check | `which node` / parsing `dnf list` | `rpm -q` (rhel) / `dpkg-query` (debian) via `pkg_is_installed` | Read-only, authoritative, no `/var/cache/dnf` write (preserves DET read-only invariant) |

**Key insight:** Every "custom" approach here re-implements something the package
manager or an existing primitive already does correctly — and each reinvention is a
new EL9 failure mode (hangs, conflicts, byte-instability) that the bats contract
would catch only after wasted iteration.

## Runtime State Inventory

This phase is a code/config refactor (generalizing call sites). It writes
**no new persistent runtime state** beyond what the existing Ubuntu installer
already writes; the EL9 branch writes the *same logical artifacts* to
EL-appropriate paths. Inventory of state-path divergences a planner must track:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — this phase stores no databases/datastores; the installer is stateless beyond filesystem artifacts | None |
| Live service config | NodeSource repo registration moves path: Ubuntu `/etc/apt/sources.list.d/nodesource.{sources,list}` + `/etc/apt/preferences.d/nodejs` → EL9 `/etc/yum.repos.d/nodesource-nodejs.repo` (+ `nodesource-nsolid.repo`). The **idempotency gate** (30-nodejs.sh:68-69), the **detect gate** (detect/nodejs.sh:86-87), and the **purge cleanup** (agentlinux-install:387-389) all reference these paths and must branch in lockstep or re-runs won't short-circuit and `--purge` leaves the repo behind | Branch all three path sites via `nodesource_repo_paths` |
| OS-registered state | System locale: Ubuntu `/etc/default/locale` → EL9 `/etc/locale.conf`. No Task Scheduler / systemd-unit / pm2 equivalents in this phase | `locale_ensure` writes the family-correct path |
| Secrets/env vars | NodeSource GPG key import: `https://rpm.nodesource.com/gpgkey/ns-operations-public.key` (auto-imported by dnf via `gpgkey=`). No secret renames — code-only | None beyond the setup script's auto-import |
| Build artifacts | None — no compiled artifacts in Phase 18 (the CLI build is untouched). The `pkg.sh` source-once guard must follow the repo convention (`AGENTLINUX_PKG_SH_SOURCED`) | Add source-once guard to new `pkg.sh` |

**Canonical question — after every file is updated, what runtime state still
carries the old assumption?** On a *brownfield EL9 host*: a pre-existing AppStream
`dnf module install nodejs:18` leaves an installed module RPM that `module_hotfixes`
alone does NOT clear → the explicit `dnf -y module reset nodejs` is the migration
step (not just a code edit). This is the one runtime-state item that is a genuine
data/state action rather than a pure code rename.

## Common Pitfalls

### Pitfall 1: Distro gate hard-rejects AlmaLinux 9 (blocks everything)
**What goes wrong:** `distro_detect.sh:46-49` returns non-zero unless `ID==ubuntu`; the entrypoint's ERR trap aborts before any provisioner runs.
**Why it happens:** Deliberate v0.3.0 fail-closed design.
**How to avoid:** Add the `almalinux` arm (Pattern 1) FIRST. Match `ID` exactly (not `ID_LIKE`); keep Alma 10 / Rocky / RHEL explicitly rejected with an honest message.
**Warning signs:** `unsupported distro: ID=almalinux` + exit 1 before provisioner 10.

### Pitfall 2: 13 hardcoded apt/dpkg sites each die `command not found` on EL9
**What goes wrong:** `apt-get`/`dpkg`/`dpkg-query`/`locale-gen`/`update-locale` don't exist on EL9; each call trips the ERR trap.
**Why it happens:** v0.3.0 was Ubuntu-only by constraint; no abstraction existed.
**How to avoid:** Build `pkg.sh` first, route ALL 13 sites through verbs. CI grep guard: `grep -rn 'apt-get\|dpkg' plugin/` must only match inside the debian arm of `pkg.sh`.
**Warning signs:** any `apt-get: command not found` / `dpkg-query: command not found` in the EL9 transcript; install aborts inside a provisioner rather than at the gate.

### Pitfall 3: locale step apt-installs into the void on EL9
**What goes wrong:** `10-agent-user.sh:76-86` does `command -v locale-gen` → miss → `apt-get install locales` → `apt-get: command not found`; and BHV-01 asserts `/etc/default/locale`, a file EL9 never creates.
**How to avoid:** EL9 arm of `locale_ensure` skips the entire locale-gen block, writes `/etc/locale.conf`. The `locale -a | grep -Eiq '^c\.utf-?8$'` check (line 90) is already portable and passes on EL9 out of the box. (The BHV-01 *test* assertion path branch is Phase 20, not Phase 18 — but `locale_ensure` must write the correct file now.)
**Warning signs:** install aborts at `10-agent-user: starting` with `apt-get: command not found`; perl `setlocale: LC_CTYPE cannot be set` noise.

### Pitfall 4: AppStream `nodejs` module collision on brownfield EL9
**What goes wrong:** A host with `dnf module install nodejs:18` already run conflicts with the NodeSource `nodejs` package ("filtered out by modular filtering" / version-lock conflict), or `node --version` returns 18.x (AppStream won), tripping RT-01.
**Why it happens:** `module_hotfixes=1` (set by setup script) handles greenfield but does NOT reset an *already-installed* stream; the setup script does not run `dnf module reset` (verified 2026-06-28).
**How to avoid:** `dnf -y module reset nodejs || true` before the NodeSource install (rhel arm). Keep the RT-01 `node >= 22` hard-check.
**Warning signs:** `dnf install nodejs` reports modular-filtering error or conflict; post-install `node --version` is v18/v20; `rpm -q nodejs` lacks a `nodesource` release.

### Pitfall 5: NodeSource detect gate checks Debian-only paths → brownfield misclassification
**What goes wrong:** `detect/nodejs.sh:84-90` keys on `dpkg-query` + `nodesource.{sources,list}`. On EL9 both gates are structurally wrong → a NodeSource-installed Node is mis-detected as absent → installer re-adds the repo / mis-decides reuse (the v0.3.4-class bug reappearing on EL).
**How to avoid:** EL9 arm: `rpm -q --qf '%{VERSION}-%{RELEASE}' nodejs` release contains **`nodesource`** AND `/etc/yum.repos.d/nodesource-nodejs.repo` present. Add an AppStream-module Node source class (rpm has nodejs, release lacks `nodesource`) distinct from NodeSource-RPM. Keep DET read-only — prefer `rpm -q`/file probes over bare `dnf` (which writes `/var/cache/dnf` and would break the `15-detection.bats` byte-equality invariant).
**Warning signs:** brownfield report shows Node "absent" where `node --version` returns v22; `15-detection.bats` read-only invariant fails.

### Pitfall 6: `dnf install curl` breaks the install (curl-minimal conflict)
**What goes wrong:** EL9 ships `curl-minimal`; `dnf install curl` demands `--allowerasing` and can break other tooling.
**How to avoid:** Never `pkg_install curl` on rhel. `curl-minimal` is HTTPS-capable; only `command -v curl` to confirm presence.
**Warning signs:** `dnf` error about conflicting `curl`/`curl-minimal`, transaction abort.

### Pitfall 7: Renaming `can_sudo_apt` breaks the contract
**What goes wrong:** `user.can_sudo_apt` is a DET-01 JSON field emitted by `render.sh:80,86` + `user.sh:73,87,99`, asserted by the bats suite. Renaming to `can_sudo_pkg` is a contract break.
**How to avoid:** Generalize the **probe binary** only — `sudo -u "$user" -n /usr/bin/dnf --version` on rhel (keep the absolute-path anchoring security rationale at user.sh:42-46). Keep `DETECT_USER_CAN_SUDO_APT`, the JSON field `can_sudo_apt`, and `detect::user_can_sudo_apt()` names unchanged.
**Warning signs:** `15-detection.bats` / DET-01 fixture assertions fail on the renamed field even though the probe works.

## Code Examples

### can_sudo_apt probe generalization (keep field, branch binary)
```bash
# Source: detect/user.sh:41-52 [VERIFIED in repo] — generalize the probe binary
case "${AGENTLINUX_DISTRO_FAMILY:-debian}" in
  rhel)   probe=/usr/bin/dnf;     probe_arg=--version ;;
  *)      probe=/usr/bin/apt-get; probe_arg=--help ;;
esac
if sudo -u "$user" -n "$probe" "$probe_arg" >/dev/null 2>&1; then
  can_sudo_apt=true   # ← variable + JSON field name UNCHANGED (contract)
else
  can_sudo_apt=false
fi
```

### NodeSource RPM detect arm (substring on `nodesource`, not deb `-1nodesource`)
```bash
# Source: detect/nodejs.sh:81-90 [VERIFIED] + Open Question Q1
ns_version=$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' nodejs 2>/dev/null || true)   # rhel arm
# Robust classification: match the `nodesource` substring (present in the RELEASE
# field, e.g. 22.x.x-1nodesource.el9) rather than the deb-specific `-1nodesource`.
if [[ "$ns_version" == *nodesource* ]] \
   && [[ -f /etc/yum.repos.d/nodesource-nodejs.repo ]]; then
  entries+=("$(__det_nodejs_entry nodesource /usr/bin/node "$ns_version" "$user" /usr)")
fi
```

## State of the Art

| Old (Ubuntu / current code) | New (EL9 branch) | When Changed | Impact |
|------------------------------|------------------|--------------|--------|
| `apt-get install` | `dnf install -y --setopt=install_weak_deps=False` | EL9 arm | `--no-install-recommends` ≈ `install_weak_deps=False` |
| `dpkg-query -W -f='${Version}'` | `rpm -q --qf '%{VERSION}-%{RELEASE}'` | EL9 arm | release field carries `nodesource` marker |
| `locale-gen` + `update-locale` → `/etc/default/locale` | direct write `/etc/locale.conf` (C.UTF-8 glibc built-in) | EL9 arm | locale step *deletes* work |
| `deb.nodesource.com/setup_22.x` + apt | `rpm.nodesource.com/setup_22.x` + dnf + `module_hotfixes=1` | EL9 arm | `/etc/yum.repos.d/nodesource-nodejs.repo` |
| `apt-transport-https`, `gnupg` prereqs | dropped | EL9 arm | dnf does HTTPS + GPG natively |

**Deprecated/outdated on EL9:**
- `locale-gen`/`update-locale`/`locales` package — absent on EL9; do not call.
- `apt-transport-https` — no EL equivalent and unneeded.
- The deb-specific `-1nodesource` substring as the *sole* classifier — works coincidentally on the rpm VERSION-RELEASE join but key on `nodesource` for robustness.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The NodeSource `nodejs` RPM `%{VERSION}-%{RELEASE}` contains the substring `nodesource` (e.g. `22.x.x-1nodesource.el9`) | Code Examples / Open Q1 | DET-02/REUSE-02 misclassify NodeSource Node on brownfield EL9 → re-add repo / wrong reuse decision. **MUST verify on `almalinux:9` in Phase 18/19** (STATE.md concern) |
| A2 | `write_file_atomic` reads file content from stdin (used for `/etc/locale.conf`) | Pattern 2 | If it takes content as an arg, `locale_ensure` wiring differs — confirm the convention at idempotency.sh:39 before coding (cheap to verify) |
| A3 | Sourcing `pkg.sh` at entrypoint line ~156 (after distro_detect, before idempotency) makes verbs available to all provisioners + detect fragments | Pattern 2 | If a detect fragment is sourced in a subshell that doesn't inherit, verbs unavailable — verify the detect.sh sourcing path inherits the entrypoint env (it does today for as_user) |
| A4 | NodeSource setup_22.x runs its own distro detection cleanly on `almalinux:9` (AlmaLinux officially supported; `/etc/redhat-release` present as fallback) | Open Q2 | If it trips, `node` never installs — spot-check on the real image (Phase 19); documented workaround is touching `/etc/redhat-release` (already shipped) |
| A5 | `dnf install -y --setopt=install_weak_deps=False` is the correct `--no-install-recommends` analogue and does not break NodeSource install | Pattern 2 | If weak-deps exclusion drops a runtime dep, Node install incomplete — low risk; verify on Docker arm |

## Open Questions

1. **Exact NodeSource RPM `%{VERSION}-%{RELEASE}` string on `almalinux:9` (the STATE.md flagged concern).**
   - What we know: the setup script writes the repo with `module_hotfixes=1` and a `pub_22/nodistro` baseurl (fetched verbatim 2026-06-28); the deb path carries `-1nodesource`; the rpm release historically carries `nodesource` (e.g. `1nodesource.el9`).
   - What's unclear: the precise release string under the newer `nodistro` repo layout — could be `…nodesource.el9` or a `nodistro`-flavored variant.
   - Recommendation: in Phase 18 (validated on the Phase 19 Docker arm), run `dnf install -y nodejs` then `rpm -q --qf '%{VERSION}-%{RELEASE}\n' nodejs` on `almalinux:9` and pin the classifier to the `nodesource` substring confirmed there. Do NOT ship the deb-specific `-1nodesource` match as the sole gate. This is a planning task, not a blocker.

2. **NodeSource setup_22.x distro-detection on AlmaLinux 9.**
   - What we know: AlmaLinux is officially supported by NodeSource; `/etc/redhat-release` is present.
   - What's unclear: nothing blocking — historical issues (#1653/#1717) were older script versions.
   - Recommendation: spot-check on the real `almalinux:9` image early in Phase 19; treat as a verification item.

## Environment Availability

This phase is developed on the Ubuntu dev host; real validation needs the
`almalinux:9` Docker substrate (Phase 19, co-developed). The dependencies the
phase's *code* assumes at EL9 runtime:

| Dependency | Required By | Available on `almalinux:9` base | Version | Fallback |
|------------|------------|----------------------------------|---------|----------|
| `dnf` (full) | pkg.sh rhel arm | ✅ | EL9 | none needed (microdnf out of scope) |
| `rpm` | detect + pkg_is_installed | ✅ | EL9 | — |
| `curl` (curl-minimal) | NodeSource fetch | ✅ | — | do NOT install (conflict) |
| `jq` | detection layer | ❌ not default | AppStream | `pkg_install jq` |
| `sudo`/`visudo` | 20-sudoers | ⚠️ container may lack | BaseOS | `pkg_install sudo` |
| glibc C.UTF-8 | locale_ensure | ✅ built-in | 2.34 | none (built-in) |
| `almalinux:9` Docker image | Phase 19 acceptance gate | ✅ (rolling `9` tag) | 9.x | — |

**Missing dependencies with no fallback:** none — every gap (`jq`, `sudo`) has a
`pkg_install` fallback the installer already performs.

**Cannot verify on this dev host:** the exact `rpm -q nodejs` release string (Q1) —
deferred to the Docker arm.

## Validation Architecture

This phase is testable installer behavior with measurable acceptance, so Nyquist
validation applies (nyquist_validation not disabled in config).

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bats (behavior-contract suite under `tests/bats/`) — the spec per CLAUDE.md |
| Config file | none — bats runs via `tests/docker/run.sh <target>` inside the matrixed image |
| Quick run command | `bash tests/docker/run.sh ubuntu-24.04` (existing); `bash tests/docker/run.sh almalinux-9` (lands Phase 19) |
| Full suite command | `bash tests/docker/run.sh ubuntu-22.04 && bash tests/docker/run.sh ubuntu-24.04 && bash tests/docker/run.sh ubuntu-26.04` (Ubuntu byte-for-byte regression) |
| Unit-source (dev host) | `AGENTLINUX_SKIP_DISTRO_CHECK=1 AGENTLINUX_DISTRO_FAMILY=rhel` to source pkg.sh verbs and assert dispatch without a real EL9 host |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| EL-01 | `distro_detect.sh` accepts almalinux 9.*, exports FAMILY, rejects Alma 10/Rocky/RHEL; escape hatch seeds family | unit (bats) | bats sourcing `detect_distro` with stubbed `/etc/os-release` fixtures (ID=almalinux/rocky/almalinux v10) | ⚠️ extend `15-detection.bats` or new `18-distro-detect.bats` — ❌ Wave 0 |
| EL-02 | pkg.sh verbs dispatch debian↔rhel; all 13 sites routed; Ubuntu byte-for-byte | unit (bats) + Ubuntu regression | bats asserting `pkg_install`/`pkg_is_installed`/`pkg_remove` emit the right command per FAMILY; `grep -rn 'apt-get\|dpkg' plugin/` only matches inside pkg.sh debian arm | ❌ Wave 0 (new `pkg.sh` unit test) |
| EL-03 | Node 22 installs via NodeSource RPM; AppStream module defused; RT-01 node>=22 holds | integration (Docker, Phase 19) | `almalinux-9` row reaches install complete; `rpm -q nodejs` shows `nodesource`; `node --version` = v22 | ❌ depends on Phase 19 substrate |
| EL-04 | locale: `/etc/locale.conf` written; `locale -a` has C.UTF-8; no locale-gen call | integration (Docker) | `locale -a \| grep -Eiq '^c\.utf-?8$'`; assert no `apt-get`/`locale-gen` in EL9 transcript | ⚠️ `20-agent-user.bats` (assertion path branch is Phase 20) |
| EL-05 | sudoers drop-in installs via visudo path, 0440 root:root, `agent ALL=(ALL) NOPASSWD: ALL`, six modes pass | integration (Docker) | existing `22-agent-sudo.bats` outcomes on `almalinux-9` | ✅ exists (outcome-portable) |
| EL-07 | brownfield EL9 Node classified by rpm + yum repo vs AppStream vs absent; can_sudo probe via dnf; field name preserved | unit + integration | DET-02 fixtures: NodeSource-RPM / AppStream-module / absent each classify correctly; `15-detection.bats` read-only invariant holds | ⚠️ EL fixtures land Phase 20; Phase 18 ships the rpm arm + unit assertion — ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** unit-source pkg.sh + distro_detect assertions on the dev host (fast); `shellcheck`/`pre-commit run --all-files`.
- **Per wave merge:** `bash tests/docker/run.sh ubuntu-24.04` (Ubuntu regression — byte-for-byte preserved) + `almalinux-9` once Phase 19 lands.
- **Phase gate:** Ubuntu Docker rows green (no regression) + the `almalinux-9` row reaching `agentlinux-install complete` (co-developed with Phase 19); TST-07 behavior-coverage-auditor gate at the phase boundary.

### Wave 0 Gaps
- [ ] `tests/bats/18-distro-detect.bats` (or extend `15-detection.bats`) — EL-01 fixtures: accept almalinux 9.*, reject Alma 10 / Rocky / RHEL, escape-hatch seeds FAMILY.
- [ ] `plugin/lib/pkg.sh` unit assertions — EL-02 verb dispatch per FAMILY (can run on dev host via FAMILY override).
- [ ] EL-07 detect-arm unit assertion — `nodesource` substring + yum repo gate classification (rpm output can be stubbed at unit level; live confirmation on Docker arm).
- [ ] CI grep guard — `grep -rn 'apt-get\|dpkg' plugin/` matches only inside pkg.sh debian arm.
- *(Deeper EL9 brownfield fixtures — AppStream `nodejs:18` installed, NodeSource-RPM, nvm — and the BHV-01 locale assertion-path branch land in Phase 20 per SUMMARY reconciled decision; Phase 18 ships the detection rpm arm + unit coverage only.)*

## Project Constraints (from CLAUDE.md)

The planner MUST verify Phase 18 plans honor these directives (same authority as locked decisions):
- **Never `sudo npm install -g`** anywhere — irrelevant to Phase 18's package work (no npm-global changes) but the `as_user`/per-user-prefix model must remain untouched.
- **Behavior tests in `tests/bats/` are the spec.** Do not pin implementation choices as requirements; the contract asserts outcomes. Ubuntu rows must stay green (byte-for-byte).
- **No wrapper shims at `/usr/local/bin/`** pointing to agent-owned binaries.
- **Distro detection matches on `ID`, not `ID_LIKE`** (project convention + EL-01).
- **Match `ID=almalinux` exactly; reject Rocky/RHEL/Fedora/Alma 8/10** — AlmaLinux-9-ONLY scope.
- **SELinux stays enforcing** — `restorecon`, never `setenforce 0` (EL-06/Phase 20 scope, but the principle binds: don't paper over the environment).
- **Review loop:** changed `plugin/*.sh` → `bash-engineer`, `security-engineer`, `qa-engineer`, `ai-deslop`, `dev-docs-auditor`; bats spec → `qa-engineer`, `behavior-coverage-auditor`. `dev-docs-auditor` keeps `docs/internals/` in sync for `plugin/lib`/`plugin/provisioner` changes.
- **ADR-017** (planned): record the family-bucket + dnf-branch decision (`docs/decisions/017-distro-family-bucket.md`).

## Sources

### Primary (HIGH confidence — verified at file:line in this worktree, 2026-06-28)
- `plugin/lib/distro_detect.sh` (current Ubuntu-only gate, escape hatch at :30-34, ID gate :46, version case :51-60)
- `plugin/lib/detect/nodejs.sh` (DET-02 dual-gate :84-90, classification arms), `plugin/lib/detect/user.sh` (can_sudo_apt probe :41-52, JSON field :73/87/99), `plugin/lib/detect/render.sh` (can_sudo_apt field :80/86)
- `plugin/provisioner/10-agent-user.sh` (locale block :76-94), `20-sudoers.sh` (sudo install :27-28), `30-nodejs.sh` (prereqs :56-58, NodeSource gate :68-73, install :78, RT-01 check :83-88)
- `plugin/bin/agentlinux-install` (sourcing order :139-159, ensure_jq :280-287, purge :387-396, detect_distro call :433-435)
- `plugin/lib/idempotency.sh` (write_file_atomic :39, ensure_user :151, visudo_validate :187), `plugin/lib/as_user.sh` (as_user :32, as_user_login :46)
- `packaging/curl-installer/install.sh` (detect_ubuntu_version lockstep gate :75-92)
- `tests/docker/run.sh` (whitelist + UBUNTU_VERSION arg), `tests/bats/*.bats` (suite inventory)
- NodeSource `setup_22.x` (rpm) — https://rpm.nodesource.com/setup_22.x — **fetched verbatim 2026-06-28**: writes `/etc/yum.repos.d/nodesource-nodejs.repo`, sets `module_hotfixes=1`, gpgkey `ns-operations-public.key`, `gpgcheck=1`, does NOT run `dnf module reset/disable`

### Secondary (MEDIUM-HIGH — v0.3.5 research synthesis, web-verified)
- `.planning/research/{SUMMARY,STACK,ARCHITECTURE,PITFALLS}.md` — the v0.3.5 EL9 research corpus (call sites + EL9 facts cross-checked against current code this session)
- glibc `C.UTF-8` built-in on EL9 — https://github.com/osbuild/osbuild-composer/issues/2206 ; AlmaLinux 9 locale guides (rosehosting, how2shout)
- `curl-minimal` conflict — https://www.jeffgeerling.com/blog/2024/fixing-curl-install-failures-ansible-on-red-hat-derivative-oses/
- EL9 sudoers `secure_path`/`requiretty` — https://access.redhat.com/solutions/1298644

### Tertiary (LOW — needs live confirmation)
- Exact NodeSource `nodejs` RPM `%{VERSION}-%{RELEASE}` string on `almalinux:9` — UNVERIFIED on this dev host; pin on the Phase 19 Docker arm (Open Q1)

## Metadata

**Confidence breakdown:**
- Standard stack (apt→dnf mapping, NodeSource RPM, locale, sudoers): HIGH — every call site re-verified in current code; NodeSource mechanism fetched verbatim.
- Architecture (pkg.sh dispatch + family bucket): HIGH — verb set covers all 13 sites; sourcing order confirmed.
- Pitfalls: HIGH — distro gate / apt-dpkg / locale / dnf-module / curl-minimal all verified; contract-field-preservation (can_sudo_apt) confirmed against render.sh + user.sh.
- NodeSource rpm version-string classifier: MEDIUM — `nodesource` substring is the robust key; exact string deferred to live Docker verification (Q1, STATE.md concern).

**Research date:** 2026-06-28
**Valid until:** ~2026-07-28 (stable; NodeSource repo layout + EL9 facts are slow-moving). Re-verify Q1 against `almalinux:9` before locking the DET-02 classifier.
