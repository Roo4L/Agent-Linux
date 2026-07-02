# Phase 19: Docker AlmaLinux 9 Row - Research

**Researched:** 2026-06-28
**Domain:** CI test-substrate infrastructure (systemd-in-Docker, dnf package set, GitHub Actions matrix)
**Confidence:** HIGH (every unknown verified on a live `almalinux:9` container this session)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None — `19-CONTEXT.md` records this as a pure infrastructure phase.

### Claude's Discretion
All implementation choices are at Claude's discretion. Mirror the existing Ubuntu
Docker rows (`tests/docker/Dockerfile.ubuntu-24.04`, `run.sh`, the
`--privileged --cgroupns=host` systemd-in-Docker recipe per ADR-007) and the
existing CI matrix structure. Use the ROADMAP success criteria, HARN-01, ADR-007,
and the Phase 18 `AGENTLINUX_DISTRO_FAMILY` abstraction to guide decisions.

### Deferred Ideas (OUT OF SCOPE)
- Full behavior-contract green on EL9 → **Phase 20 / PAR-01** (Phase 19 only needs a
  green install + a *runnable* bats invocation).
- Catalog verify on EL9 → **Phase 21 / REC-01**.
- QEMU AlmaLinux 9 row + release-gate wiring → **Phase 22 / HARN-02 / REL-01**.
- AlmaLinux 10 / RHEL / Rocky / Fedora → deferred until Alma 9 is daily-driver one cycle.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HARN-01 | A new `almalinux-9` Docker matrix row runs the bats suite in CI; a `tests/docker/Dockerfile.almalinux-9` stands up a systemd-capable EL9 substrate; `tests/docker/run.sh` and `test.yml`/`release.yml` gate-2 carry the arm. | Live-verified EL9 package set, EPEL→bats path, systemd-in-Docker boot recipe (boots `running` in 2s), NodeSource RPM string, and a minimal matrix-generalization plan — all below. |
</phase_requirements>

## Summary

Phase 19 stands up a fast-feedback `almalinux:9` Docker substrate structurally
identical to the three Ubuntu rows. Every technical unknown the CONTEXT flagged
was resolved this session by running a live `almalinux:9` container (Docker is
available on this dev host): bats is **not** in base/AppStream but **is** in EPEL
(`bats-1.8.0-1.el9`), EPEL ships via `epel-release` in the default-enabled `extras`
repo; `curl-minimal` is preinstalled (so **never** `dnf install curl`); the
systemd-in-Docker `--privileged --cgroupns=host` recipe boots to `running` in 2s
and `systemd-run --uid` works (dbus-broker supplies the bus); C.UTF-8 is a glibc
builtin (no `locales`/`locale-gen`); and the NodeSource RPM release string is
`22.23.1-1nodesource` — **confirming the `nodesource` substring** that resolves the
carried Phase 18 Open Q1 / STATE.md concern.

The work is three mechanical edits plus one new file: (1) write
`tests/docker/Dockerfile.almalinux-9` — same two-stage shape (the `node:22-slim`
cli-builder stage is **byte-identical and reused as-is**; only the final stage's
`FROM` + package install + mask lines change to EL9 equivalents); (2) add an
`almalinux-9` case to `tests/docker/run.sh` (the image/Dockerfile naming already
generalizes — only the `case` allow-list, usage text, and "ubuntu version"→"target"
wording change); (3) add `almalinux-9` to the **gate-2 Docker matrix** in both
`test.yml` and `release.yml`, renaming that one job's matrix dimension
`ubuntu`→`target` (each job's matrix is independent, so gate-3-qemu and
gate-4-pinned-combo stay untouched — QEMU EL9 is Phase 22, pinned-combo is ADR-011).

**Primary recommendation:** Clone `Dockerfile.ubuntu-24.04`, keep the cli-builder
stage verbatim, translate the final stage to EL9 (`dnf` + `epel-release` + `bats`,
`cron`→`cronie`, `dbus`→`dbus-broker`, drop `systemd-sysv`/`locales`/`locale-gen`,
keep the same `systemctl mask` unit names with `|| true`), add the `almalinux-9`
case to `run.sh`, and add the arm to gate-2 only. Phase 19's gate is **green install
+ runnable bats** — the CI arm may legitimately be red on individual bats files
until Phase 20; `fail-fast: false` isolates it from the Ubuntu arms.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| EL9 test substrate (image) | Docker build (`Dockerfile.almalinux-9`) | — | Per-target image is the unit of the harness matrix (ADR-007). |
| Hermetic CLI artifact | Docker build stage (`node:22-slim` cli-builder) | run.sh splice | Distro-independent; produced once, spliced at boot — reused byte-identical. |
| systemd PID-1 + bus | Container runtime (run.sh flags) | image (mask units) | `--privileged --cgroupns=host` + `container=docker` is a runtime contract; image only masks fighting units. |
| Install-under-test | `agentlinux-install` (Phase 18 rhel arms) | image (deps present) | The installer's own dnf/NodeSource path is *under test*, not a build dep. |
| bats invocation | run.sh (`bats tests/bats/`) | image (EPEL bats) | Same entrypoint across all targets; image only needs `bats` on PATH. |
| Matrix fan-out | GitHub Actions (`test.yml`, `release.yml` gate-2) | run.sh | CI passes the target name; run.sh resolves image+Dockerfile. |

## Standard Stack

This is an infrastructure phase — the "stack" is the EL9 base image + repos, not
application libraries. All rows below are **[VERIFIED: live `almalinux:9` container, 2026-06-28]**.

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| `almalinux:9` base image | 9.8 (Olive Jaguar) | EL9 test substrate | `ID=almalinux`, `VERSION_ID=9.8`, `PLATFORM_ID=platform:el9`; accepted by `distro_detect.sh` `9 \| 9.*` arm. `/etc/redhat-release` present (NodeSource fallback). |
| `systemd` | 252-67.el9 | PID 1 (BHV-04 real, not vacuous) | `/sbin/init → ../lib/systemd/systemd` already in base; boots to `running` in 2s under the recipe. |
| `epel-release` | 9-9.el9 (from `extras`, enabled by default) | unlocks `bats`, `shellcheck` | Canonical EL extra-packages repo; one `dnf install epel-release` then deps resolve. |
| `bats` | 1.8.0-1.el9 (EPEL) | run the behavior suite in-container | Ubuntu 22.04 ships 1.8.2; 1.8.0 is adequate (`run` helper + `--separate-stderr`). **EPEL, not vendored** — simplest, mirrors apt's `bats` package. |
| `node:22-slim` (cli-builder stage) | node 22 | hermetic CLI build | **Reused byte-identical from the Ubuntu rows** — distro-independent throwaway builder; no change. |

### Supporting (final-stage `dnf` package set — EL9 names)
| Ubuntu (apt) name | EL9 (dnf) name | Purpose | Verified available |
|-------------------|----------------|---------|--------------------|
| `systemd systemd-sysv` | `systemd` (no `-sysv`; it *is* the init) | PID 1 | ✅ |
| `cron` | `cronie` | BHV-02/03 daemon | ✅ |
| `openssh-server` | `openssh-server` | BHV-03 sshd + `ssh-keygen -A` | ✅ |
| `bats` | `bats` (EPEL) | run suite | ✅ (after `epel-release`) |
| `locales` + `locale-gen`/`update-locale` | **(none — drop)** | C.UTF-8 | ✅ builtin (`locale -a` shows `C.utf8`) |
| `sudo` | `sudo` | BHV-05 / sudoers | ✅ |
| `dbus` | `dbus-broker` (EL9 default; `dbus` meta also works) | system bus for `systemd-run --uid` | ✅ (smoke-tested OK) |
| `jq` | `jq` | 40-registry-cli.bats JSON + 15-detection invariant | ✅ |
| `curl` | **(none — DO NOT install)** | — | `curl-minimal-7.76.1` preinstalled; `dnf install curl` triggers the curl/curl-minimal conflict (Phase 18 Pitfall 6) |
| `python3` | `python3` | 60-curl-installer.bats local http.server | ✅ |
| `file` | `file` | curl-installer gzip magic check | ✅ |
| `ca-certificates bash coreutils util-linux` | same names | base utils | ✅ |
| `shellcheck` (optional) | `shellcheck` (EPEL) | interactive debug | ✅ (EPEL) |
| (implicit) | `procps-ng` (optional) | `ps` for `docker exec` debugging — absent from base | ✅ optional |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| EPEL `bats` | Vendor a pinned `bats` tarball into the image | More hermetic / no EPEL network dep, but adds a download+extract layer and a version to maintain. EPEL is the lower-friction match to the apt `bats` package; choose vendoring only if EPEL availability becomes flaky in CI. |
| `dbus-broker` | `dbus-daemon` (the `dbus` meta-package) | Both expose `/run/dbus/system_bus_socket`; `dbus-broker` is the EL9 default and was smoke-verified. Either satisfies BHV-04. |

**EPEL enablement (one line, before the bats install):**
```bash
dnf install -y --setopt=install_weak_deps=False epel-release
```

**Version verification (already run this session):**
```bash
docker run --rm almalinux:9 bash -c 'dnf install -y epel-release >/dev/null && dnf list bats'
# → bats.noarch 1.8.0-1.el9 epel   [VERIFIED 2026-06-28]
```

## Architecture Patterns

### System Architecture Diagram

```
 GitHub Actions (test.yml bats-docker  /  release.yml gate-2-docker)
        │  matrix.target ∈ {ubuntu-22.04, ubuntu-24.04, ubuntu-26.04, almalinux-9}
        ▼
 tests/docker/run.sh <target>
        │
        ├─(1)─ docker build -f Dockerfile.<target>  (context = repo root)
        │          │
        │          ├─ Stage 1: cli-builder (node:22-slim)  ── REUSED VERBATIM ──┐
        │          │     pnpm install --frozen-lockfile && build && prune --prod │
        │          │                                                             ▼
        │          └─ Stage 2: FROM almalinux:9 ─ dnf (epel→bats, cronie,        │
        │                       dbus-broker, …) ─ mask units ─ ssh-keygen -A     │
        │                       COPY --from=cli-builder dist+node_modules ◄──────┘
        │                       CMD ["/sbin/init"]
        │
        ├─(2)─ docker run --privileged --cgroupns=host -e container=docker
        │          -v /sys/fs/cgroup:rw --tmpfs /run --tmpfs /tmp   (PID 1 = systemd)
        │          └─ wait: systemctl is-system-running → running|degraded (EL9: running, 2s)
        │
        ├─(3)─ cp /workspace → /opt/agentlinux-src   (writable copy)
        │          splice /opt/cli-prebuilt/{dist,node_modules,package.json} into plugin/cli/
        │
        ├─(4)─ docker exec … agentlinux-install   ── Phase 18 rhel arms exercised for real:
        │          distro_detect (almalinux 9.* → FAMILY=rhel) → pkg.sh dnf verbs →
        │          nodesource_setup (rpm.nodesource.com) → locale.conf → sudoers drop-in
        │
        └─(5)─ docker exec … bats tests/bats/   → propagate exit code → PASS/FAIL banner
```

### Recommended File Layout (additions only)
```
tests/docker/
├── Dockerfile.almalinux-9     # NEW — clone of ubuntu-24.04, EL9 final stage
├── Dockerfile.ubuntu-24.04    # template to mirror (richest analog)
└── run.sh                     # MODIFY — add almalinux-9 case + "target" wording
.github/workflows/
├── test.yml                   # MODIFY — bats-docker matrix: ubuntu→target + almalinux-9
└── release.yml                # MODIFY — gate-2-docker matrix only: ubuntu→target + almalinux-9
```

### Pattern 1: Two-stage Dockerfile, builder reused verbatim
**What:** Stage 1 (`FROM node:22-slim AS cli-builder`) is identical across all four
rows — copy `plugin/cli/{package.json,pnpm-lock.yaml,tsconfig.json,src}`,
`corepack enable && pnpm install --frozen-lockfile && pnpm run build && pnpm prune --prod`.
Stage 2 changes only `FROM`, the package install, and the mask list.
**When to use:** Always — keeps the CLI artifact byte-equivalent so a CLI bug can't
hide on one distro. Do **not** re-derive the builder for EL9.
**Example (EL9 final stage — translated from `Dockerfile.ubuntu-24.04`):**
```dockerfile
# Source: live almalinux:9 probe 2026-06-28 + Dockerfile.ubuntu-24.04 structure
FROM almalinux:9

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# EPEL first (unlocks bats + shellcheck), then the EL9 package set.
# curl is DELIBERATELY ABSENT: curl-minimal is preinstalled and `dnf install
# curl` conflicts (Phase 18 Pitfall 6). No systemd-sysv (systemd IS the init on
# EL9). No locales/locale-gen: C.UTF-8 is a glibc builtin (locale -a → C.utf8).
RUN dnf install -y --setopt=install_weak_deps=False epel-release && \
    dnf install -y --setopt=install_weak_deps=False \
      systemd \
      cronie openssh-server \
      bats sudo \
      dbus-broker \
      jq \
      python3 \
      file \
      ca-certificates bash coreutils util-linux \
      procps-ng shellcheck && \
    dnf clean all && rm -rf /var/cache/dnf

# Systemd-in-Docker: mask units that fight containerized PID 1. resolved/networkd
# are NOT installed on minimal EL9 — `systemctl mask` still no-ops cleanly on an
# absent unit (creates the /dev/null symlink); `|| true` is belt-and-suspenders.
RUN rm -f /lib/systemd/system/multi-user.target.wants/* && \
    systemctl mask \
      systemd-logind.service \
      systemd-resolved.service \
      systemd-networkd.service \
      systemd-tmpfiles-setup.service \
      systemd-tmpfiles-clean.service \
      systemd-tmpfiles-clean.timer || true

# SSH host keys at build time (sshd started later by systemd).
RUN mkdir -p /run/sshd && ssh-keygen -A

# Pre-built CLI bundle from the builder stage — IDENTICAL to the Ubuntu rows.
COPY --from=cli-builder /build/cli/dist /opt/cli-prebuilt/dist
COPY --from=cli-builder /build/cli/node_modules /opt/cli-prebuilt/node_modules
COPY --from=cli-builder /build/cli/package.json /opt/cli-prebuilt/package.json

VOLUME /sys/fs/cgroup
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
```

### Pattern 2: run.sh stays target-agnostic — add a case, generalize wording
**What:** `IMG="agentlinux-test:${TARGET}"` and `DF="$HERE/Dockerfile.${TARGET}"`
already generalize. The only required edits: add `almalinux-9` to the `case`
allow-list, update `usage()`, and rename the local var / log strings from
"ubuntu version"→"target". The systemd wait (`running|degraded`), the splice, the
installer call, and `bats tests/bats/` are all distro-neutral.
**Example (case edit):**
```bash
# Source: tests/docker/run.sh:47-58 (existing) — add the alma arm
case "$TARGET" in
  ubuntu-22.04 | ubuntu-24.04 | ubuntu-26.04 | almalinux-9) ;;
  -h | --help) usage; exit 0 ;;
  *) printf 'tests/docker/run.sh: unsupported target: %s\n' "$TARGET" >&2
     usage; exit 64 ;;
esac
```

### Pattern 3: Add the arm to gate-2 only; matrices are job-scoped
**What:** Each GitHub Actions job owns its own `strategy.matrix`. Adding
`almalinux-9` to the Docker matrix does **not** touch the QEMU matrix.
```yaml
# test.yml  bats-docker  AND  release.yml  gate-2-docker
strategy:
  fail-fast: false          # already present — keeps Ubuntu arms reporting if alma is red
  matrix:
    target:                 # renamed from `ubuntu`
      - ubuntu-22.04
      - ubuntu-24.04
      - ubuntu-26.04
      - almalinux-9
steps:
  - run: bash tests/docker/run.sh ${{ matrix.target }}   # was matrix.ubuntu
```
**Leave untouched:** `release.yml` `gate-3-qemu` (`matrix.ubuntu` — QEMU EL9 is
**Phase 22**) and `gate-4-pinned-combo` (hardcoded `ubuntu-24.04` — ADR-011 pinned
catalog combo, out of scope).

### Anti-Patterns to Avoid
- **Adding `curl` to the dnf list.** Breaks on the curl/curl-minimal conflict.
  The installer's NodeSource path uses `curl -fsSL` which `curl-minimal` already provides.
- **Re-deriving the cli-builder stage for EL9.** It's distro-independent; copy it verbatim so the CLI artifact can't diverge per distro.
- **Renaming the QEMU (`gate-3`) matrix dimension or hardcoded pinned-combo.** Those are Phase 22 / ADR-011, not Phase 19.
- **`dnf install locales` / `locale-gen`.** No such package on EL9; C.UTF-8 is built into glibc. The `locale_ensure` rhel arm already writes `/etc/locale.conf` at install time — the image only needs the builtin (which is present).
- **Masking via `/usr/lib/...` absolute paths.** `systemctl mask <unit>` keys on the unit *name*; usrmerge means `/lib` == `/usr/lib`. Use unit names, not paths (matches the Ubuntu rows).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| bats on EL9 | A custom curl+make bats install | `dnf install epel-release && dnf install bats` | EPEL ships a maintained `bats-1.8.0-1.el9`; mirrors the apt `bats` package one-liner. |
| systemd-in-Docker boot | A custom init/entrypoint shim | The existing `--privileged --cgroupns=host -e container=docker` recipe in run.sh | Already proven; verified to boot `running` in 2s on EL9 this session. |
| CLI build per distro | An EL9-specific Node build path | The shared `node:22-slim` cli-builder stage | One artifact, spliced identically; avoids per-distro skew. |
| C.UTF-8 locale | locale-gen/glibc-langpack gymnastics | Nothing — it's a glibc builtin on EL9 | `locale -a` already lists `C.utf8`; the existing `^c\.utf-?8$` gate matches. |

**Key insight:** The Ubuntu harness already solved every hard problem (systemd PID 1,
the splice, the wait loop, exit-code propagation). Phase 19 is a *translation*
(apt→dnf names, +EPEL, −locales/−systemd-sysv), not a redesign.

## Common Pitfalls

### Pitfall 1: `dnf install curl` (curl-minimal conflict)
**What goes wrong:** Image build fails — `curl` vs preinstalled `curl-minimal` file conflict.
**Why it happens:** EL9 minimal ships `curl-minimal`, which provides the `curl` binary.
**How to avoid:** Never list `curl` in the dnf set. The installer's `curl -fsSL` works with curl-minimal.
**Warning signs:** `Error: Transaction test ... conflicts with curl-minimal`.
**[VERIFIED: `curl-minimal-7.76.1-40.el9` preinstalled, `curl` absent]**

### Pitfall 2: bats missing because EPEL not enabled
**What goes wrong:** `dnf install bats` → "No matching Packages"; the bats step in run.sh fails.
**Why it happens:** bats is in EPEL, not base/AppStream.
**How to avoid:** `dnf install -y epel-release` (in the default-enabled `extras` repo) **before** the bats install, in the same RUN or an earlier layer.
**Warning signs:** `dnf list bats` → "No matching Packages" on the base image.
**[VERIFIED: bats absent from base; `bats-1.8.0-1.el9` present after `epel-release`]**

### Pitfall 3: Renaming the QEMU/pinned-combo matrix dimension
**What goes wrong:** Phase 19 accidentally wires an EL9 QEMU arm (no Alma cloud image exists yet → Phase 22) or perturbs the ADR-011 pinned-combo gate.
**Why it happens:** Over-eager "generalize `ubuntu`→`target`" across the whole file.
**How to avoid:** Rename/extend **only** `test.yml` `bats-docker` and `release.yml` `gate-2-docker`. Leave `gate-3-qemu` and `gate-4-pinned-combo` byte-for-byte.
**Warning signs:** A diff touching `gate-3-qemu`'s `matrix.ubuntu` or the `tests/qemu/boot.sh` call.

### Pitfall 4: Expecting the EL9 CI arm to be green at Phase 19 close
**What goes wrong:** Planner treats "alma arm red" as a Phase 19 failure and over-scopes bug-fixing into this phase.
**Why it happens:** Phase boundary nuance — Phase 19 delivers the *substrate* + a *runnable* bats invocation + a green **install**; full bats-contract-green is **Phase 20 / PAR-01**.
**How to avoid:** Acceptance = `run.sh almalinux-9` builds, boots, `agentlinux-install` completes 0, and `bats tests/bats/` *executes*. Individual red bats files are expected and fed forward to Phase 20. `fail-fast: false` keeps the Ubuntu arms reporting.
**Warning signs:** A task list that includes "make 50-agents.bats green on EL9" (that's Phase 20/21).

### Pitfall 5: NodeSource AppStream module shadowing (already mitigated in Phase 18)
**What goes wrong:** EL9's AppStream `nodejs` module wins over the NodeSource repo → Node v18/v20 instead of v22.
**Why it happens:** setup_22.x does not reset the AppStream module.
**How to avoid:** Phase 18 already ships `nodesource_module_reset` (`dnf -y module reset nodejs`). Phase 19 just *confirms* it works for real in the container.
**Warning signs:** post-install `node --version` is v18/v20; `rpm -q nodejs` release lacks `nodesource`.
**[VERIFIED this session: `dnf install nodejs` after setup_22.x → `node v22.23.1`, release `1nodesource`]**

## Code Examples

### Resolve Phase 18 Open Q1 — the NodeSource RPM release string (a Phase 19 task)
```bash
# Source: live almalinux:9 run, 2026-06-28  [VERIFIED]
curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
dnf install -y nodejs
rpm -q --qf '%{VERSION}-%{RELEASE}\n' nodejs
# → 22.23.1-1nodesource          ← substring `nodesource` PRESENT (resolves A1)
node --version
# → v22.23.1                      ← RT-01 (node ≥ 22) holds; AppStream not shadowing (A4 holds)
```
**Planning consequence:** The DET-02 / REUSE-02 classifier keying on the
**`nodesource` substring** (already in `plugin/lib/detect/nodejs.sh` per Phase 18)
is confirmed correct on real EL9. Plan a Phase 19 task that *captures this transcript*
as the resolution of STATE.md's NodeSource concern (no code change expected — just
confirmation that the shipped classifier matches reality).

### systemd-in-Docker boot check on EL9 (already wired in run.sh)
```bash
# Source: smoke test this session  [VERIFIED]
CID=$(docker run --rm -d --privileged --cgroupns=host -e container=docker \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /tmp agentlinux-test:almalinux-9)
docker exec "$CID" systemctl is-system-running   # → running  (2s; not even degraded)
docker exec "$CID" bash -c 'useradd -m t; systemd-run --uid=t --wait /bin/true'  # → OK (dbus-broker bus)
```

## Runtime State Inventory

> This is a greenfield-infra phase (new file + CI edits). No rename/migration of
> stored runtime state. Categories checked for completeness:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no datastore keys touched. | None |
| Live service config | None — CI matrix lives in git (`test.yml`/`release.yml`), not a UI. | Code edit only |
| OS-registered state | None — Docker images are ephemeral per-run. | None |
| Secrets/env vars | None — no new secrets; `GITHUB_TOKEN` usage unchanged. | None |
| Build artifacts | New Docker image `agentlinux-test:almalinux-9` built per CI run (ephemeral, `--rm`). No persisted artifact. | None |

**Verified:** the only persistent change is three tracked files + one new tracked file under `tests/docker/` and `.github/workflows/`.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Docker (dev host) | local smoke/iteration | ✅ | 29.3.0 | — |
| `almalinux:9` image | substrate | ✅ (pullable) | 9.8 | — |
| EPEL (`epel-release`) | bats, shellcheck | ✅ | 9-9.el9 (extras) | vendor bats tarball |
| `bats` (EPEL) | run the suite | ✅ | 1.8.0-1.el9 | vendor tarball |
| `dbus-broker` | BHV-04 system bus | ✅ | (EL9 default) | `dbus` meta-package |
| NodeSource EL9 repo | install-under-test | ✅ (reachable) | setup_22.x → node 22.23.1 | — |
| GitHub Actions `ubuntu-24.04` runner | builds the alma image (Docker-in-runner) | ✅ (existing) | — | — |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** EPEL bats → vendored tarball (only if EPEL flakes in CI; not currently needed).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bats (the `tests/bats/` behavior-contract suite — the spec per CLAUDE.md). EL9 image installs `bats-1.8.0-1.el9` from EPEL. |
| Config file | none — bats runs via `tests/docker/run.sh almalinux-9` inside the matrixed image. |
| Quick run command | `bash tests/docker/run.sh almalinux-9` (local; Docker available on dev host) |
| Full suite command | gate-2 Docker matrix in CI (`test.yml` bats-docker / `release.yml` gate-2-docker) across all four targets |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HARN-01 | EL9 image builds (two-stage, EPEL bats spliced CLI) | infra/smoke | `docker build -f tests/docker/Dockerfile.almalinux-9 .` | ❌ Wave 0 (new Dockerfile) |
| HARN-01 | systemd boots PID 1; reaches `running` | infra/smoke | `run.sh almalinux-9` wait-loop (existing logic) | ✅ run.sh logic exists; ❌ alma case |
| HARN-01 | `agentlinux-install` completes 0 on EL9 (Phase 18 rhel arms) | integration | `run.sh almalinux-9` installer step | ✅ installer exists; exercised for first time here |
| HARN-01 | `bats tests/bats/` *executes* (runnable invocation) | integration | `run.sh almalinux-9` bats step | ✅ suite exists; alma greenness is Phase 20 |
| HARN-01 | CI matrix carries the `almalinux-9` arm | CI | gate-2 in test.yml + release.yml | ❌ Wave 0 (matrix edit) |
| (resolves A1) | NodeSource RPM release contains `nodesource` | confirmation | `rpm -q --qf '%{VERSION}-%{RELEASE}' nodejs` inside the alma container | ✅ verified (`22.23.1-1nodesource`) |

### Sampling Rate
- **Per task commit:** `bash tests/docker/run.sh almalinux-9` locally (Docker on dev host) — fast EL9 feedback (~90s build+boot+install, then bats).
- **Per wave merge:** the full gate-2 Docker matrix (all four targets) green where expected (alma bats may be partially red until Phase 20 — that is the Phase 20 gate, not Phase 19).
- **Phase gate:** `run.sh almalinux-9` builds + boots + install exits 0 + bats *runs*; CI arm present with `fail-fast: false`.

### Wave 0 Gaps
- [ ] `tests/docker/Dockerfile.almalinux-9` — new file (EL9 final stage; cli-builder reused).
- [ ] `tests/docker/run.sh` — add `almalinux-9` case + generalize "ubuntu version"→"target" wording.
- [ ] `.github/workflows/test.yml` — `bats-docker` matrix: `ubuntu`→`target`, add `almalinux-9`.
- [ ] `.github/workflows/release.yml` — `gate-2-docker` matrix only: `ubuntu`→`target`, add `almalinux-9`.
- [ ] (no new bats files — the existing contract is reused; EL9-specific bats fixtures land in Phase 20)

## Security Domain

> `security_enforcement` not set to false in config — included. This phase adds no
> auth/session/crypto surface; it is CI substrate. Applicable controls below.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | yes (minimal) | GitHub Actions `permissions: contents: read` default already set in both workflows; gate-2 needs no escalation. Do not add token scope. |
| V5 Input Validation | no | matrix values are a fixed allow-list, not user input. |
| V6 Cryptography | no (reuse) | NodeSource fetch integrity is `curl -fsSL` HTTPS + repo gpgkey (ADR-005, Phase 18) — unchanged. |

### Known Threat Patterns for {EL9 Docker substrate}
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Untrusted base image | Tampering | Pin to official `almalinux:9` (Docker Official Image); digest observed `sha256:d2515c…` this session. Optionally pin by digest if reproducibility is required (Ubuntu rows pin by tag — match that convention). |
| EPEL supply chain | Tampering | `epel-release` is the canonical EL extras package; bats from EPEL is signed by the EPEL key. Acceptable for a *test* image (not shipped to users). |
| `--privileged` container | Elevation | Already accepted for the Ubuntu rows (required for systemd PID 1); scoped to ephemeral CI containers (`--rm`), never a production path. No new exposure. |
| Token over-scope in CI | Elevation | Keep `permissions: contents: read`; the alma arm reuses the existing gate-2 job permissions. |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Ubuntu-only Docker matrix (`ubuntu` dimension) | Generalized `target` dimension incl. `almalinux-9` | This phase | Matrix now spans two distro families; `fail-fast: false` already in place. |
| `cron`/`dbus`/`locales` apt names | `cronie`/`dbus-broker`/(builtin C.UTF-8) on EL9 | This phase | EL9 final stage diverges from the apt set; cli-builder stage stays shared. |
| Open Q1 (NodeSource rpm string unverifiable on dev host) | Resolved: `22.23.1-1nodesource` on live `almalinux:9` | This phase | DET-02 `nodesource`-substring classifier confirmed correct. |

**Deprecated/outdated:** none — the Ubuntu harness pattern is current and directly reused.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| — | (none) | — | All Phase-19 technical claims were verified on a live `almalinux:9` container this session (bats/EPEL, package set, systemd boot, dbus-broker bus, C.UTF-8 builtin, NodeSource string). |

**This table is intentionally empty:** every load-bearing claim is `[VERIFIED]`.
Residual *uncertainty* is behavioral, not factual — see Open Questions.

## Open Questions (ACKNOWLEDGED)

1. **Does the *full* `agentlinux-install` complete 0 end-to-end on EL9 in-container?**
   - **ADDRESSED BY TASK 19-01-03 — captured at execution time, not a planning-blocking unknown.**
   - What we know: each Phase 18 rhel arm (distro_detect, pkg.sh verbs, nodesource_setup, locale.conf, module_reset) is unit-green; NodeSource + node 22 + systemd + dbus all verified in isolation this session.
   - What's unclear: the *composed* installer run (sudoers drop-in via visudo, 50-registry-cli provisioner, any provisioner that still has a latent apt assumption) has never executed on real EL9 — Phase 19 is the first time. Expect to surface 1–N real EL9 install bugs and feed them back into Phase 18 code (the CONTEXT explicitly anticipates this).
   - Recommendation: plan a "first green install" task with headroom for small Phase-18 follow-up fixes; keep `AGENTLINUX_DOCKER_KEEP_CONTAINER=1` debugging in the toolkit.

2. **Which individual bats files are red on EL9 (Phase 20 inventory)?**
   - **ADDRESSED BY TASK 19-01-03 — captured at execution time, not a planning-blocking unknown.**
   - What we know: Phase 19's gate is a *runnable* invocation, not full green.
   - What's unclear: the exact red set (locale assertion paths, detection fixtures, agent installs) — that inventory *is* Phase 20's input.
   - Recommendation: capture the alma `bats` run output at Phase 19 close as the Phase 20 worklist; do not fix them in Phase 19.

3. **SELinux-in-Docker:** EL9 containers do not load an enforcing SELinux policy (no
   - **SCOPED OUT — EL9 containers load no enforcing SELinux policy; real enforcement is the Phase 22 QEMU concern.**
   per-container kernel policy), so SELinux nuances (`restorecon` on `~agent/.ssh`)
   are **not** exercised by Phase 19 — they are a **Phase 22 QEMU** concern (the
   milestone-close gate is enforcing-SELinux EL9). Do not scope SELinux work into Phase 19.

## Project Constraints (from CLAUDE.md)
- **Never `sudo npm install -g`** / no `/usr/local` wrapper shims — N/A to this phase (no install path change), but the EL9 image must not introduce them.
- **Behavior tests in `tests/bats/` are the spec** — reuse the existing suite unchanged; do not fork EL9-specific assertions in Phase 19 (that's Phase 20).
- **Docker-only is insufficient for release (ADR-007)** — Phase 19 is the *fast-feedback* layer only; the EL9 QEMU release gate is Phase 22. Do not claim release-readiness from a green Docker arm.
- **Every release tarball ships a `.sha256`** — unaffected (build/publish jobs untouched).
- **Review loop:** changed files → `tests/docker/*` (Dockerfile + run.sh) → `bash-engineer`, `qa-engineer`, `security-engineer`, `ai-deslop`; workflow YAML → `bash-engineer`/`qa-engineer` + `security-engineer` (CI permissions). Not externally-facing copy (skip `external-audience-auditor`).

## Sources

### Primary (HIGH confidence — live verification this session)
- `docker run --rm almalinux:9 …` (2026-06-28) — os-release 9.8, curl-minimal preinstalled, systemd 252, EPEL `bats-1.8.0-1.el9`, full package-name availability, C.UTF-8 builtin, NodeSource `22.23.1-1nodesource`, systemd-in-Docker boot `running` in 2s + `systemd-run --uid` OK.
- `tests/docker/run.sh`, `tests/docker/Dockerfile.ubuntu-{22,24,26}.04` — the harness pattern being mirrored.
- `.github/workflows/test.yml` (bats-docker), `.github/workflows/release.yml` (gate-2/3/4) — matrix structure.
- `plugin/lib/pkg.sh`, `plugin/lib/distro_detect.sh` — Phase 18 rhel arms exercised in-container.
- `docs/decisions/007-docker-plus-qemu-harness.md` — two-layer harness scope.
- `.planning/phases/18-detection-branching-foundation/18-RESEARCH.md` — Open Q1, Pitfalls 4–6, DET-02 classifier.

### Secondary (MEDIUM)
- `.planning/STATE.md` — NodeSource rpm-string blocker (now resolved), phase scope.
- `.planning/phases/19-docker-almalinux-9-row/19-CONTEXT.md` — phase boundary + discretion.

### Tertiary (LOW)
- None — no unverified web claims were relied upon.

## Metadata

**Confidence breakdown:**
- Standard stack (EL9 package set, EPEL bats, NodeSource string): HIGH — live-verified.
- Architecture (Dockerfile two-stage, run.sh case, matrix edit): HIGH — direct mirror of working Ubuntu rows + live systemd boot test.
- Pitfalls: HIGH — curl-minimal conflict and EPEL/bats both reproduced live.
- Composed install greenness on EL9: MEDIUM — unit arms verified, end-to-end run is Phase 19's first real exercise (Open Q1/Q2 above).

**Research date:** 2026-06-28
**Valid until:** ~2026-07-28 (stable; EL9 minor bumps or EPEL bats version drift are the only likely changes — re-probe `dnf list bats` if it slips).
