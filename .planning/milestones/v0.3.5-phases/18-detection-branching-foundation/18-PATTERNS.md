# Phase 18: Detection + Branching Foundation - Pattern Map

**Mapped:** 2026-06-28
**Files analyzed:** 9 (1 new, 8 modified) + 1 new ADR
**Analogs found:** 9 / 9 (every file has an in-repo analog — this is a port, not a greenfield build)

This phase ports an Ubuntu-only bash installer to also run on AlmaLinux 9 behind a
single `AGENTLINUX_DISTRO_FAMILY` ∈ `{debian, rhel}` abstraction. Every new/modified
file has a **same-file or sibling analog already in the tree** — the executor's job is
to mirror the existing bash conventions (source-once guard, `command -v log_error`
precondition, `return 1` not `exit 1` in sourced fragments, two-arm `case` on the
family bucket) rather than invent new structure. The single hardest contract trap is
preserving the `can_sudo_apt` JSON field name while generalizing its probe binary.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `plugin/lib/pkg.sh` (NEW) | utility (lib helper) | transform / dispatch | `plugin/lib/as_user.sh` (structure) + `plugin/lib/distro_detect.sh` (case-arm) | role-match (new abstraction, mirrors existing lib shape) |
| `plugin/lib/distro_detect.sh` (MOD) | config / gate | request-response (detect→export) | itself (add `almalinux` arm to existing `case`) | exact (same-file extension) |
| `plugin/bin/agentlinux-install` (MOD) | entrypoint | orchestration | itself (sourcing block :154-159, `ensure_jq` :280-289, `run_purge` :386-397) | exact (same-file) |
| `plugin/provisioner/10-agent-user.sh` (MOD) | provisioner step | transform (locale write) | itself (locale block :76-94) → call `locale_ensure` | exact (same-file) |
| `plugin/provisioner/20-sudoers.sh` (MOD) | provisioner step | request-response | itself (`sudo` install :25-29) → call `pkg_install sudo` | exact (same-file) |
| `plugin/provisioner/30-nodejs.sh` (MOD) | provisioner step | request-response (repo + install) | itself (prereqs :56-58, NodeSource gate :68-74, install :78) | exact (same-file) |
| `plugin/lib/detect/nodejs.sh` (MOD) | detect fragment | request-response (read-only probe) | itself (NodeSource dual-gate :84-90) | exact (same-file, add rhel arm) |
| `plugin/lib/detect/user.sh` (MOD) | detect fragment | request-response (read-only probe) | itself (`can_sudo_apt` probe :41-52) | exact (same-file, branch probe binary) |
| `packaging/curl-installer/install.sh` (MOD) | config / pre-gate | request-response | itself (`detect_ubuntu_version` :75-92) | exact (same-file, lockstep with distro_detect) |
| `docs/decisions/017-distro-family-bucket.md` (NEW) | docs (ADR) | n/a | existing `docs/decisions/ADR-0xx` (ADR-005, ADR-012 referenced) | role-match |

## Shared Conventions (every `plugin/lib/*.sh` and sourced fragment)

All three apply to the NEW `pkg.sh` and are extracted from the existing libs verbatim.
Mirror them exactly — the bats suite and the ERR trap depend on them.

### 1. Source-once guard (top of every lib)
**Source:** `plugin/lib/as_user.sh:14-16`, `plugin/lib/distro_detect.sh:10-12`, `plugin/lib/detect/user.sh:14-15`
```bash
# Source-once guard: safe to `. as_user.sh` repeatedly.
[[ -n "${AGENTLINUX_AS_USER_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_AS_USER_SH_SOURCED=1
```
**Apply to `pkg.sh`:** use the guard var name `AGENTLINUX_PKG_SH_SOURCED` (Research
Runtime-State Inventory mandates this exact name).

### 2. `log.sh`-sourced-first precondition (immediately after the guard)
**Source:** `plugin/lib/distro_detect.sh:16-19` (identical block in `as_user.sh:18-21`, `detect/user.sh:17-20`, `detect/nodejs.sh:25-28`)
```bash
if ! command -v log_error >/dev/null 2>&1; then
  printf 'distro_detect.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi
```
**Apply to `pkg.sh`:** same block, swap the filename in the message to `pkg.sh:`.

### 3. SPDX + one-line purpose header
**Source:** every lib, e.g. `plugin/lib/detect/user.sh:1-3`
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/pkg.sh — package-manager-neutral verbs (apt↔dnf) on $AGENTLINUX_DISTRO_FAMILY.
```

### 4. Two-arm family `case` (the canonical branch shape)
**Source:** `plugin/lib/distro_detect.sh:51-60` (version `case`), generalized to family.
Every verb in `pkg.sh` and every modified detect arm is a `case "$AGENTLINUX_DISTRO_FAMILY" in debian) … ;; rhel) … ;; esac`. **Never** inline `if [[ $FAMILY == rhel ]]` at a call site (Research Anti-Pattern 2). The debian arm must be **byte-for-byte the current Ubuntu code** lifted from its present call site.

---

## Pattern Assignments

### `plugin/lib/pkg.sh` (NEW — utility, transform/dispatch)

**Analog:** `plugin/lib/as_user.sh` (overall lib shape + guard) and the **13 current call
sites** whose debian arms are lifted verbatim. This is the load-bearing new file — build
it FIRST and source it from the entrypoint right after `distro_detect.sh`.

**Structure to mirror** (header + guard + precondition from Shared Conventions 1-3 above), then the verb set. Each verb's **debian arm is copied from the call site it replaces**:

**`pkg_install` debian arm** — lift from `provisioner/30-nodejs.sh:56-58` / `ensure_jq` at `bin/agentlinux-install:286-287` / `20-sudoers.sh:27-28` (all identical):
```bash
DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
```
rhel arm (new): `dnf install -y --setopt=install_weak_deps=False "$@"` (Research Pattern 2; `install_weak_deps=False` ≈ `--no-install-recommends`).

**`pkg_is_installed` debian arm** — the `dpkg-query` idiom lifted from `detect/nodejs.sh:84` generalized to a presence test:
```bash
dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
```
rhel arm (new): `rpm -q "$1" >/dev/null 2>&1`.

**`pkg_remove` / `pkg_autoremove` debian arms** — lift from `bin/agentlinux-install:394-396`:
```bash
DEBIAN_FRONTEND=noninteractive apt-get purge -y "$@"      # pkg_remove
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y      # pkg_autoremove
```
rhel arms (new): `dnf remove -y "$@"` and `dnf autoremove -y`.

**`nodesource_setup` debian arm** — lift from `30-nodejs.sh:73`:
```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
```
rhel arm (new): `curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -`.

**`nodesource_repo_paths`** (NEW helper — emits the family's repo file paths so the
idempotency gate in `30-nodejs.sh`, the detect gate in `detect/nodejs.sh`, and the purge
cleanup in `bin/agentlinux-install` all agree). debian set lifted from `30-nodejs.sh:68-69`
+ `bin/agentlinux-install:387-389`:
```
/etc/apt/sources.list.d/nodesource.sources
/etc/apt/sources.list.d/nodesource.list
/etc/apt/preferences.d/nodejs
```
rhel set (new): `/etc/yum.repos.d/nodesource-nodejs.repo` (+ `nodesource-nsolid.repo`).

**`locale_ensure <locale>`** — debian arm lifts the entire `10-agent-user.sh:76-94` block
(the `command -v locale-gen` install + `locale-gen` + `update-locale` + `locale -a` gate).
rhel arm writes `/etc/locale.conf` via the existing atomic primitive (see below).

**Atomic write primitive** — `locale_ensure`'s rhel arm and any config write MUST use
`write_file_atomic` from `idempotency.sh:39`, NOT `cat >`/`tee`:
```bash
# write_file_atomic <mode> <dest> — reads CONTENT FROM STDIN (idempotency.sh:56 `cat >"$tmp"`)
printf 'LANG=%s\nLC_ALL=%s\n' "$1" "$1" | write_file_atomic 0644 /etc/locale.conf
```
**Verified stdin convention** (resolves Research Assumption A2): `idempotency.sh:56` is
`cat >"$tmp"`, so `write_file_atomic` reads the file body from **stdin**; args are
`<mode> <dest>` only. Pipe the content in.

---

### `plugin/lib/distro_detect.sh` (MOD — config/gate, request-response)

**Analog:** itself. Add an `almalinux` arm to the existing `ID` gate and seed the new
family export. Keep `AGENTLINUX_DISTRO_VERSION` (downstream still branches on it).

**Current gate to replace** (`distro_detect.sh:46-60`):
```bash
if [[ "${ID:-}" != "ubuntu" ]]; then
  log_error "unsupported distro: ID=${ID:-unset} (required: ubuntu)"
  return 1
fi
case "${VERSION_ID:-}" in
  22.04 | 24.04 | 26.04)
    export AGENTLINUX_DISTRO_VERSION="$VERSION_ID"
    log_info "detected ubuntu ${VERSION_ID}" ;;
  *)
    log_error "unsupported ubuntu version: ${VERSION_ID:-unset} (required: 22.04, 24.04 or 26.04)"
    return 1 ;;
esac
```
**Replace with** a `case "${ID:-}"` two-arm (ubuntu→`FAMILY=debian`, almalinux→`FAMILY=rhel`,
9|9.* only) per Research Pattern 1 (lines 186-205). Match `ID` exactly — **never `ID_LIKE`**
(CLAUDE-level rule; admits Rocky/RHEL/Fedora otherwise). Keep Alma 10 / Rocky / RHEL
rejected with an honest message.

**Escape-hatch seed** (`distro_detect.sh:30-34`) currently only seeds VERSION:
```bash
if [[ "${AGENTLINUX_SKIP_DISTRO_CHECK:-0}" == "1" ]]; then
  export AGENTLINUX_DISTRO_VERSION="unchecked"
  log_warn "AGENTLINUX_SKIP_DISTRO_CHECK=1 — skipping /etc/os-release validation"
  return 0
fi
```
**Must also seed `AGENTLINUX_DISTRO_FAMILY`** (Research line 207-211): honor an explicit
`AGENTLINUX_DISTRO_FAMILY` override if set; else read `ID` from `/etc/os-release` when
present; else default `debian`. Without this, a unit-sourced `pkg.sh` dispatches on an
empty bucket.

---

### `plugin/bin/agentlinux-install` (MOD — entrypoint, orchestration)

**Analog:** itself. Three edits, all mirroring existing same-file idioms.

**1. Source `pkg.sh`** in the sourcing block (`:154-159`) — insert right after
`distro_detect.sh`, before `idempotency.sh`/`as_user.sh` (Research Pattern 2 / Assumption A3):
```bash
# shellcheck source=../lib/distro_detect.sh
. "$LIB_DIR/distro_detect.sh"
# shellcheck source=../lib/pkg.sh        # ← INSERT (verbs need FAMILY, set at detect_distro :435)
. "$LIB_DIR/pkg.sh"
# shellcheck source=../lib/idempotency.sh
. "$LIB_DIR/idempotency.sh"
```
Note: verbs are *sourced* here but only *called* after `detect_distro` runs (`:433/435`),
which sets `AGENTLINUX_DISTRO_FAMILY` — sourcing order is safe.

**2. `ensure_jq`** (`:280-289`) — replace the inline apt block with `pkg_install jq`:
```bash
# BEFORE (:286-287)
DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends jq
# AFTER
pkg_install jq
```

**3. `run_purge`** (`:386-397`) — replace the hardcoded NodeSource repo `rm -f`s with
`nodesource_repo_paths` iteration, and the `apt-get purge/autoremove` (`:394-396`) with
`pkg_remove nodejs` / `pkg_autoremove`. Keep the `rm -f /etc/sudoers.d/agentlinux` and the
agent-user removal (`:402-409`) distro-agnostic.

---

### `plugin/provisioner/10-agent-user.sh` (MOD — provisioner, transform)

**Analog:** itself (locale block `:70-94`). Replace the whole locale block with one verb call:
```bash
# Step 2: locale (BHV-01). EL9 path writes /etc/locale.conf; Ubuntu path keeps locale-gen.
locale_ensure C.UTF-8 || { log_error "C.UTF-8 locale not available"; return 1; }
```
The entire debian behavior (lines 76-94 — `command -v locale-gen` install, `locale-gen`,
`update-locale`, `locale -a` gate) moves **verbatim** into `locale_ensure`'s debian arm.
`ensure_user`/`ensure_dir` (`:67-68`) and the DOC-02 block (`:97+`) are distro-agnostic — leave them.

---

### `plugin/provisioner/20-sudoers.sh` (MOD — provisioner, request-response)

**Analog:** itself. Replace only the `sudo`-package install (`:25-29`):
```bash
# BEFORE
if ! command -v visudo >/dev/null 2>&1; then
  log_warn "visudo not found; installing 'sudo' package"
  DEBIAN_FRONTEND=noninteractive apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends sudo
fi
# AFTER
if ! command -v visudo >/dev/null 2>&1; then
  log_warn "visudo not found; installing 'sudo' package"
  pkg_install sudo
fi
```
Everything below (the `RESOLUTIONS[sudoers]` dispatch, `remediate::sudoers::install_or_overwrite`,
`ensure_dir /etc/sudoers.d`) is byte-identical on EL9 — do NOT touch (Research: sudoers drop-in is distro-agnostic).

---

### `plugin/provisioner/30-nodejs.sh` (MOD — provisioner, request-response)

**Analog:** itself (CREATE-path Steps 1-3, `:52-78`). The `RESOLUTIONS[node]` dispatch
(`:24-44`), RT-01 verify (`:80-88`), and npm-prefix layer (`:90-149`) are distro-agnostic — keep.

**Step 1 prereqs** (`:56-58`) — `pkg_install` the family-correct set. On rhel **drop**
`gnupg` + `apt-transport-https` and **never** `pkg_install curl` (curl-minimal conflict,
Pitfall 6); add the brownfield module reset (Research Pattern 3, lines 254-265):
```bash
# debian: curl gnupg ca-certificates apt-transport-https ; rhel: ca-certificates only
pkg_install ca-certificates        # + the debian-only extras inside pkg.sh / a family guard
dnf -y module reset nodejs || true # rhel-arm only, non-fatal — setup script does NOT reset (Pitfall 4)
```
(Keep the `module reset` confined to the rhel arm — express via a small helper in `pkg.sh`
or the family-correct prereq list, never an inline `if` at this site.)

**Step 2 NodeSource gate** (`:68-74`) — replace the hardcoded `nodesource.sources/list`
test with a `nodesource_repo_paths`-driven gate so the rhel repo file
(`/etc/yum.repos.d/nodesource-nodejs.repo`) short-circuits re-runs; call `nodesource_setup`
in the absent arm.

**Step 3 install** (`:78`) — `pkg_install nodejs`.

**Keep** the RT-01 hard-check (`:83-88`) unchanged — it already catches "AppStream's older module won".

---

### `plugin/lib/detect/nodejs.sh` (MOD — detect fragment, read-only probe)

**Analog:** itself, the NodeSource dual-gate (`:81-90`). Add a **rhel arm** that keys on
the `nodesource` substring (Research Code Example, lines 369-379):
```bash
# debian arm (current :84-90) — KEEP unchanged
ns_version=$(dpkg-query -W -f='${Version}\n' nodejs 2>/dev/null || true)
if [[ "$ns_version" == *"-1nodesource"* ]]; then
  if [[ -f /etc/apt/sources.list.d/nodesource.sources ]] \
    || [[ -f /etc/apt/sources.list.d/nodesource.list ]]; then
    entries+=("$(__det_nodejs_entry nodesource /usr/bin/node "$ns_version" "$user" /usr)")
  fi
fi
# rhel arm (NEW) — substring `nodesource`, not deb-specific `-1nodesource`
ns_version=$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' nodejs 2>/dev/null || true)
if [[ "$ns_version" == *nodesource* ]] && [[ -f /etc/yum.repos.d/nodesource-nodejs.repo ]]; then
  entries+=("$(__det_nodejs_entry nodesource /usr/bin/node "$ns_version" "$user" /usr)")
fi
```
Add an **AppStream-module arm** (rpm has nodejs, release lacks `nodesource`) as a distinct
source class — mirror the existing `distro_apt` arm at `:92-95`. Read-only invariant:
prefer `rpm -q`/file probes over bare `dnf` (which writes `/var/cache/dnf` and breaks the
`15-detection.bats` byte-equality invariant — Pitfall 5). The `__det_nodejs_entry` helper
(`:36-51`) and the per-user manager scans (`:111-117`) are distro-agnostic — leave them.

**Live-verify (Open Q1):** the exact `%{VERSION}-%{RELEASE}` string is unverified on this
dev host — confirm `nodesource` substring on `almalinux:9` (Phase 19 Docker arm) before locking.

---

### `plugin/lib/detect/user.sh` (MOD — detect fragment, read-only probe) — CONTRACT TRAP

**Analog:** itself, the `can_sudo_apt` probe (`:41-52`). Generalize the **probe binary
only**; keep the variable, the export, the JSON key, and the accessor names **unchanged**.

**Current probe** (`:48-52`):
```bash
if sudo -u "$user" -n /usr/bin/apt-get --help >/dev/null 2>&1; then
  can_sudo_apt=true
else
  can_sudo_apt=false
fi
```
**Generalize** (Research Code Example, lines 355-367) — keep the absolute-path security
rationale (`:41-47`), branch the binary:
```bash
case "${AGENTLINUX_DISTRO_FAMILY:-debian}" in
  rhel)   probe=/usr/bin/dnf;     probe_arg=--version ;;
  *)      probe=/usr/bin/apt-get; probe_arg=--help ;;
esac
if sudo -u "$user" -n "$probe" "$probe_arg" >/dev/null 2>&1; then
  can_sudo_apt=true          # ← variable name UNCHANGED (contract)
else
  can_sudo_apt=false
fi
```
**DO NOT RENAME** (Pitfall 7): `can_sudo_apt` (var), `DETECT_USER_CAN_SUDO_APT` (export,
`:73`), the JSON field `can_sudo_apt` (`:87`), and `detect::user_can_sudo_apt()` (`:99`)
are the DET-01 contract surface asserted by `render.sh:80,86` and the bats suite. The
absolute-path anchoring (`/usr/bin/...`) is a security control — preserve it for the dnf probe too.

---

### `packaging/curl-installer/install.sh` (MOD — config/pre-gate, request-response)

**Analog:** itself, `detect_ubuntu_version` (`:75-92`). Must accept `almalinux 9.*` in
**lockstep** with `distro_detect.sh` (the header comment `:71-73` already mandates lockstep).

**Current gate** (`:84-91`):
```bash
[[ "$id" == "ubuntu" ]] \
  || die "unsupported distro: ${id} (AgentLinux v0.3.0 supports Ubuntu only)"
case "$version" in
  22.04 | 24.04 | 26.04) ;;
  *) die "unsupported Ubuntu version: ${version} (...)" ;;
esac
```
**Generalize** to a `case "$id"` two-arm (ubuntu→22.04/24.04/26.04; almalinux→9|9.*; else
`die`), mirroring the `distro_detect.sh` arms exactly. Match `ID`, not `ID_LIKE`. Consider
renaming the function to `detect_supported_distro` (or keep + add a sibling) — the executor
should keep the two gates structurally identical so the fixture stays in lockstep.

---

### `docs/decisions/017-distro-family-bucket.md` (NEW — ADR)

**Analog:** existing ADRs under `docs/decisions/` (ADR-005 NodeSource curl-pipe, ADR-012
sudoers drop-in are the directly-referenced precedents). Record the family-bucket
(`AGENTLINUX_DISTRO_FAMILY`) + single-`pkg.sh`-branch decision and the rejected
alternatives (inline per-site `case`; AppStream `dnf module install nodejs:22`;
`localectl set-locale`). Mirror the existing ADR file's heading structure
(Status / Context / Decision / Consequences). ADRs skip `ai-deslop` review per CLAUDE.md.

---

## Cross-Cutting Path Branch (one change, three lockstep sites)

The NodeSource repo-file path moves Ubuntu→EL9 and is referenced in **three** places that
must branch together via `pkg.sh::nodesource_repo_paths` or re-runs/`--purge` break
(Research Runtime-State Inventory):

| Site | File:line | Current (debian) | Needs |
|------|-----------|------------------|-------|
| Idempotency gate | `provisioner/30-nodejs.sh:68-69` | `nodesource.sources` / `.list` | repo-paths verb |
| Detect gate | `lib/detect/nodejs.sh:86-87` | same two files | repo-paths verb (rhel: yum repo) |
| Purge cleanup | `bin/agentlinux-install:387-389` | same + `preferences.d/nodejs` | repo-paths verb |

Same rule for the locale path: Ubuntu `/etc/default/locale` → EL9 `/etc/locale.conf`,
both written by `locale_ensure` (the only writer).

## No Analog Found

None. Every file has an in-repo analog (same-file or a sibling lib/provisioner). This is a
port: the existing Ubuntu code IS the debian arm. The only genuinely new structure is the
`pkg.sh` verb dispatcher, and its shape is dictated by the existing lib conventions
(Shared Conventions 1-4) plus the 13 call sites it absorbs.

## Verified Facts (resolve Research assumptions)

- **A2 — `write_file_atomic` stdin convention: CONFIRMED.** `idempotency.sh:56` is
  `cat >"$tmp"`; the function takes `<mode> <dest>` args and reads content from **stdin**.
  Pipe `/etc/locale.conf` body in.
- **A3 — sourcing order: CONFIRMED.** Entrypoint sources libs at `:154-159` (top-level,
  inherited by all sourced provisioner/detect fragments, same as `as_user.sh`); insert
  `pkg.sh` between `distro_detect.sh` and `idempotency.sh`. `detect_distro` runs at `:433/435`
  (after sourcing, before any verb call) so `$AGENTLINUX_DISTRO_FAMILY` is set in time.
- **A1 / Q1 — `rpm -q nodejs` release string: UNVERIFIED on this dev host.** Pin the
  `nodesource` substring on the `almalinux:9` Docker arm (Phase 19) before locking the DET-02 classifier.

## Metadata

**Analog search scope:** `plugin/lib/`, `plugin/lib/detect/`, `plugin/provisioner/`,
`plugin/bin/`, `packaging/curl-installer/` (the exact file:line inventory was pre-verified
in 18-RESEARCH.md — confirmed against current code this session).
**Files scanned (read this session):** `distro_detect.sh`, `detect/user.sh`,
`detect/nodejs.sh`, `detect/render.sh`, `10-agent-user.sh`, `20-sudoers.sh`, `30-nodejs.sh`,
`bin/agentlinux-install` (3 ranges), `idempotency.sh`, `as_user.sh`, `curl-installer/install.sh`.
**Pattern extraction date:** 2026-06-28
