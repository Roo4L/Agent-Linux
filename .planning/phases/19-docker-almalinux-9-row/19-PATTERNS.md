# Phase 19: Docker AlmaLinux 9 Row - Pattern Map

**Mapped:** 2026-06-28
**Files analyzed:** 4 (1 new, 3 modified)
**Analogs found:** 4 / 4 (all exact — direct in-repo mirror)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `tests/docker/Dockerfile.almalinux-9` (NEW) | config (container image) | batch (build → boot → test) | `tests/docker/Dockerfile.ubuntu-24.04` | exact (clone; stage 1 byte-identical, stage 2 apt→dnf translation) |
| `tests/docker/run.sh` (MODIFIED) | test harness / entrypoint | batch (build+boot+install+bats) | itself — existing `case`/allowlist + wording | exact (in-place edit; logic already target-agnostic) |
| `.github/workflows/test.yml` (MODIFIED) | config (CI) | event-driven (push/PR) | the `bats-docker` job's own matrix block | exact (matrix dimension rename + arm) |
| `.github/workflows/release.yml` (MODIFIED) | config (CI) | event-driven (tag/dispatch) | the `gate-2-docker` job's own matrix block | exact (matrix dimension rename + arm; gate-3/4 untouched) |

All four files have an exact in-repo analog — this is a *translation* phase, not a design phase. The planner should treat every excerpt below as copy-target text, not inspiration.

---

## Pattern Assignments

### `tests/docker/Dockerfile.almalinux-9` (config, batch) — NEW

**Analog:** `tests/docker/Dockerfile.ubuntu-24.04`

The file is a two-stage Dockerfile. **Stage 1 (cli-builder) is copied byte-for-byte.** **Stage 2 (final image) is translated apt→dnf.** The structural skeleton (ENV → package RUN → mask RUN → ssh-keygen RUN → COPY --from=cli-builder trio → VOLUME/STOPSIGNAL/CMD) is preserved in the same order.

**Stage 1 — cli-builder — COPY VERBATIM** (`Dockerfile.ubuntu-24.04` lines 38-53). This MUST be byte-identical across all four rows so a CLI bug cannot hide on one distro (anti-pattern: re-deriving the builder for EL9):
```dockerfile
FROM node:22-slim AS cli-builder
WORKDIR /build/cli
# Copy package manifests first for Docker-layer cache hit on source-only edits.
COPY plugin/cli/package.json plugin/cli/pnpm-lock.yaml ./
COPY plugin/cli/tsconfig.json ./
COPY plugin/cli/src ./src
RUN corepack enable \
    && corepack prepare pnpm@latest --activate \
    && pnpm install --frozen-lockfile \
    && pnpm run build \
    && pnpm prune --prod
```

**Stage 2 — final image FROM + ENV.** Ubuntu original (`Dockerfile.ubuntu-24.04` lines 58-62):
```dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8
```
EL9 translation — drop `DEBIAN_FRONTEND` (apt-only), keep `LANG`/`LC_ALL`:
```dockerfile
FROM almalinux:9

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8
```

**Stage 2 — package install.** This is the core delta. Ubuntu original (`Dockerfile.ubuntu-24.04` lines 91-103):
```dockerfile
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      systemd systemd-sysv \
      cron openssh-server \
      bats locales sudo \
      dbus \
      jq \
      curl \
      python3 \
      file \
      ca-certificates bash coreutils util-linux \
      shellcheck && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
```
EL9 translation — `epel-release` first (unlocks `bats`+`shellcheck`), then the dnf set. Per-package deltas: `systemd systemd-sysv`→`systemd` (no `-sysv`; systemd IS init on EL9); `cron`→`cronie`; `bats locales`→`bats` (drop `locales` — C.UTF-8 is a glibc builtin); `dbus`→`dbus-broker`; **drop `curl`** (curl-minimal preinstalled, `dnf install curl` triggers the curl/curl-minimal conflict — Pitfall 1); add `procps-ng` (optional `ps` for debug). Names verified live on `almalinux:9`, 2026-06-28:
```dockerfile
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
```

**Stage 2 — systemd mask block.** Ubuntu original (`Dockerfile.ubuntu-24.04` lines 108-115) — copy the unit *names* verbatim (usrmerge makes `/lib`==`/usr/lib`; `systemctl mask` keys on the name). Add `|| true` for EL9 because resolved/networkd aren't installed on minimal EL9 (mask still no-ops cleanly, the `|| true` is belt-and-suspenders):
```dockerfile
# Ubuntu (lines 108-115):
RUN rm -f /lib/systemd/system/multi-user.target.wants/* && \
    systemctl mask \
      systemd-logind.service \
      systemd-resolved.service \
      systemd-networkd.service \
      systemd-tmpfiles-setup.service \
      systemd-tmpfiles-clean.service \
      systemd-tmpfiles-clean.timer
```
EL9: identical body, append ` || true` to the `systemctl mask … .timer` line.

**Stage 2 — ssh host keys.** Copy verbatim (`Dockerfile.ubuntu-24.04` line 118):
```dockerfile
RUN mkdir -p /run/sshd && ssh-keygen -A
```

**Stage 2 — locale.** Ubuntu has a `locale-gen`/`update-locale` RUN (lines 120-122). **DROP this entirely on EL9** — `locale-gen`/`update-locale` don't exist on EL9 and C.UTF-8 is a glibc builtin (`locale -a` → `c.utf8`). The `ENV LANG/LC_ALL` above is sufficient; the installer's own `locale_ensure` rhel arm writes `/etc/locale.conf` at install time.

**Stage 2 — COPY --from=cli-builder trio.** Copy VERBATIM (`Dockerfile.ubuntu-24.04` lines 131-133) — the splice contract in run.sh depends on these exact paths:
```dockerfile
COPY --from=cli-builder /build/cli/dist /opt/cli-prebuilt/dist
COPY --from=cli-builder /build/cli/node_modules /opt/cli-prebuilt/node_modules
COPY --from=cli-builder /build/cli/package.json /opt/cli-prebuilt/package.json
```

**Stage 2 — runtime trailer.** Copy VERBATIM (`Dockerfile.ubuntu-24.04` lines 136-140):
```dockerfile
VOLUME /sys/fs/cgroup
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
```

---

### `tests/docker/run.sh` (test harness, batch) — MODIFIED

**Analog:** the existing file itself. Logic is already target-agnostic: `IMG="agentlinux-test:${UBUNTU_VERSION}"` (line 62) and `DF="$HERE/Dockerfile.${UBUNTU_VERSION}"` (line 63) already resolve any target name. The build/boot/wait/splice/install/bats flow (lines 82-182) is fully distro-neutral. **Only three things change: the `case` allowlist, the `usage()` text, and the "ubuntu version"→"target" wording/var-name.**

**Edit 1 — the `case` allowlist** (lines 47-58). Add `almalinux-9` to the accept arm and generalize the error string:
```bash
# CURRENT (lines 47-58):
case "$UBUNTU_VERSION" in
  ubuntu-22.04 | ubuntu-24.04 | ubuntu-26.04) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf 'tests/docker/run.sh: unsupported ubuntu version: %s\n' "$UBUNTU_VERSION" >&2
    usage
    exit 64
    ;;
esac
```
Target: add `| almalinux-9` to the first arm; change the error string to `unsupported target: %s`.

**Edit 2 — `usage()` heredoc** (lines 24-40). Change the synopsis line (line 26) from:
```bash
usage: tests/docker/run.sh <ubuntu-22.04|ubuntu-24.04|ubuntu-26.04>
```
to include `|almalinux-9`, and generalize the prose if it says "Ubuntu version".

**Edit 3 — variable + log wording.** Optional but recommended for clarity: rename the local `UBUNTU_VERSION` (lines 42, 43, 47, 54, 62, 63) → `TARGET`, and the banner strings (lines 75, 77) / `KEEP_CONTAINER` doc comment (line 18). The PASS/FAIL banner (lines 73-79) is the only user-facing string mentioning the version:
```bash
echo "== PASS: agentlinux-install + bats on ${UBUNTU_VERSION} =="
echo "== FAIL: agentlinux-install + bats on ${UBUNTU_VERSION} (exit ${FINAL_STATUS}) ==" >&2
```

**Do NOT touch** the systemd `--privileged --cgroupns=host -e container=docker -v /sys/fs/cgroup:rw --tmpfs` recipe (lines 111-119), the `is-system-running` wait loop accepting `running|degraded` (lines 133-143 — EL9 reaches `running` in 2s, verified), the splice (lines 162-169), the installer call (line 172), or the bats call (line 177). All proven distro-neutral.

---

### `.github/workflows/test.yml` (config/CI, event-driven) — MODIFIED

**Analog:** the `bats-docker` job's own matrix block (lines 114-153). **Scope: this one job only.**

**Edit — matrix dimension `ubuntu`→`target` + add the arm** (lines 125-135):
```yaml
# CURRENT (lines 130-135):
    strategy:
      fail-fast: false
      matrix:
        ubuntu:
          - ubuntu-22.04
          - ubuntu-24.04
          - ubuntu-26.04
```
Target — rename `ubuntu:`→`target:`, append `- almalinux-9` (`fail-fast: false` is already present, keeps Ubuntu arms reporting if Alma is red):
```yaml
    strategy:
      fail-fast: false
      matrix:
        target:
          - ubuntu-22.04
          - ubuntu-24.04
          - ubuntu-26.04
          - almalinux-9
```

**Edit — the consuming step** (line 153). The downstream reference MUST be renamed in lockstep with the dimension or the Ubuntu arms break:
```yaml
# CURRENT (line 153):
        run: bash tests/docker/run.sh ${{ matrix.ubuntu }}
# TARGET:
        run: bash tests/docker/run.sh ${{ matrix.target }}
```
The `Skip if no bats suite yet` guard step (lines 142-150) is unchanged.

---

### `.github/workflows/release.yml` (config/CI, event-driven) — MODIFIED

**Analog:** the `gate-2-docker` job's own matrix block (lines 127-142). **Scope: gate-2 ONLY. Leave `gate-3-qemu` (lines 148-221) and `gate-4-pinned-combo` (lines 229-238) byte-for-byte untouched — those are Phase 22 / ADR-011.**

**Edit — gate-2 matrix `ubuntu`→`target` + add the arm** (lines 135-138). Note this job uses the inline flow-list form (different from test.yml's block form):
```yaml
# CURRENT (lines 135-138):
    strategy:
      fail-fast: false
      matrix:
        ubuntu: [ubuntu-22.04, ubuntu-24.04, ubuntu-26.04]
```
Target:
```yaml
    strategy:
      fail-fast: false
      matrix:
        target: [ubuntu-22.04, ubuntu-24.04, ubuntu-26.04, almalinux-9]
```

**Edit — the consuming step** (line 142):
```yaml
# CURRENT (line 142):
        run: bash tests/docker/run.sh ${{ matrix.ubuntu }}
# TARGET:
        run: bash tests/docker/run.sh ${{ matrix.target }}
```

**DO NOT TOUCH — gate-3-qemu** keeps `matrix.ubuntu: ['22.04','24.04','26.04']` (line 155) and `bash tests/qemu/boot.sh ${{ matrix.ubuntu }}` (line 209). **DO NOT TOUCH — gate-4-pinned-combo** keeps its hardcoded `bash tests/docker/run.sh ubuntu-24.04` (line 238). A diff touching either is the Pitfall-3 warning sign.

---

## Shared Patterns

### Two-stage builder reuse (cli-builder verbatim)
**Source:** `tests/docker/Dockerfile.ubuntu-24.04` lines 38-53
**Apply to:** the new `Dockerfile.almalinux-9`
The `FROM node:22-slim AS cli-builder` stage is distro-independent and produced once per row. Copy it byte-for-byte — never re-derive it for EL9. The final image only consumes its output via the `COPY --from=cli-builder` trio (lines 131-133).

### systemd-in-Docker runtime contract
**Source:** `tests/docker/run.sh` lines 111-143 (already written; distro-neutral)
**Apply to:** all targets (already does)
`--privileged --cgroupns=host -e container=docker -v /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /tmp` + `CMD ["/sbin/init"]` + `STOPSIGNAL SIGRTMIN+3`. The image side only masks the fighting units (Dockerfile mask block). EL9 boots `running` in 2s under this recipe (verified live). No change required.

### CI matrix dimension rename in lockstep
**Source:** `test.yml` lines 132/153, `release.yml` lines 138/142
**Apply to:** both workflow edits
When renaming `matrix.ubuntu`→`matrix.target`, the `run:` step's `${{ matrix.<name> }}` reference MUST change in the same commit, or the Ubuntu arms pass an empty target to `run.sh` (→ exit 64). The dimension and its consumer are a unit.

### EPEL-before-bats ordering
**Source:** RESEARCH §EPEL enablement + Pitfall 2; verified `bats-1.8.0-1.el9`
**Apply to:** `Dockerfile.almalinux-9` package RUN
`dnf install -y epel-release` MUST precede (or share the same `&&` RUN as) the `bats`/`shellcheck` install — bats is in EPEL, not base/AppStream. The single chained `RUN dnf install … epel-release && dnf install … bats …` shown above satisfies this.

---

## No Analog Found

None. Every file in this phase mirrors an existing in-repo file with an exact analog. The cli-builder stage, systemd recipe, splice, wait loop, and matrix structure are all reused; only the EL9 package-name translation and the `ubuntu`→`target` rename are net-new, and both are mechanical 1:1 substitutions verified live.

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| — | — | — | (none — full analog coverage) |

## Metadata

**Analog search scope:** `tests/docker/` (Dockerfile.ubuntu-24.04 as richest template + run.sh), `.github/workflows/` (test.yml bats-docker, release.yml gate-2/3/4).
**Files scanned:** 4 (all read in full; each ≤ 365 lines, single-pass).
**Pattern extraction date:** 2026-06-28
**Key cross-file constraint:** the splice in `run.sh` (lines 162-169) hard-depends on the Dockerfile's `/opt/cli-prebuilt/{dist,node_modules,package.json}` paths — keep those COPY targets identical in `Dockerfile.almalinux-9`.
