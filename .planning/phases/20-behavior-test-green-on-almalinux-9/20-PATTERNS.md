# Phase 20: Behavior-Test-Green on AlmaLinux 9 - Pattern Map

**Mapped:** 2026-06-28
**Files analyzed:** 10 (1 new, 9 modified)
**Analogs found:** 10 / 10

This is a **test-harness + test-helper phase** (RESEARCH §Summary): ~2/3 of the EL9
RED is substrate (`Dockerfile.almalinux-9` package gaps + Docker `noexec /tmp`); ~1/3
is genuine Debian-path assertion generalization (`brownfield.bash`, BHV-01, INST-02,
REUSE-01 family token). No `plugin/` product code is touched — the product side
(`distro_detect.sh`, `pkg.sh`, `detect/user.sh`) already branches on
`AGENTLINUX_DISTRO_FAMILY` and is verified correct on EL9. Sequence: **Wave 1
substrate → Wave 2 helpers → Wave 3 guarded restorecon**, validating after each wave
with `run.sh almalinux-9` (full suite, in order) **and** `run.sh ubuntu-24.04`
(no regression).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality | Wave |
|-------------------|------|-----------|----------------|---------------|------|
| `tests/docker/Dockerfile.almalinux-9` (M) | config (test image) | batch (build) | `tests/docker/Dockerfile.ubuntu-24.04` | exact (sibling) | 1 |
| `tests/docker/run.sh` (M) | config (harness driver) | batch (build/run) | self (shared across all rows) | in-place | 1 |
| `tests/bats/helpers/distro.bash` (NEW) | helper (family dispatch) | transform (case-on-family) | `helpers/detection.bash`, `helpers/invoke_modes.bash`, `helpers/brownfield.bash` | role+shape match | 2 |
| `tests/bats/helpers/brownfield.bash` (M) | helper (fixture builder) | batch (state seeding) | self (debian arm = current verbatim) | in-place | 2 |
| `tests/bats/20-agent-user.bats` (M) | test (BHV-01..06) | request-response | self (setup + locale asserts) | in-place | 2+3 |
| `tests/bats/10-installer.bats` (M) | test (INST-02 idempotency) | file-I/O (snapshot) | self (find snapshot list) | in-place | 2 |
| `tests/bats/13-reuse.bats` (M) | test (REUSE-01) | request-response | self (lib-chain seeding) | in-place | 2 |
| `tests/bats/15-detection.bats` (M) | test (DET-03) | request-response | self (npm-prefix probe) | in-place (spike) | 2 |
| `tests/bats/helpers/tty-driver.py` (M) | helper (pexpect driver) | event-driven (TTY) | self (add bounded timeout) | in-place (defensive) | 2 |
| `tests/bats/50-agents.bats` (M) | test (AGT setup_file) | request-response | self (SSH re-seed site) | in-place | 3 |

---

## Wave 1 — Substrate (no assertion edits; flips ~40 false-RED green, keeps Ubuntu byte-identical)

### `tests/docker/Dockerfile.almalinux-9` (config, batch)

**Analog / in-place target:** the existing `dnf install` RUN block at **lines 88-99**.
Add `diffutils openssh-clients iproute` (and optionally `policycoreutils`) to the dnf
set. The header comment block (lines 69-87) documents every package's reason — extend
it in the same style when adding the three packages.

**Exact current RUN block to mirror (lines 88-99):**
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
      ca-certificates bash util-linux \
      procps-ng shellcheck && \
    dnf clean all && rm -rf /var/cache/dnf
```

**What to add (RESEARCH §Environment Availability table):**
- `diffutils` — provides `diff`; absent → `diff: command not found` fails every
  NO-MUTATION snapshot + idempotency test (INST-02, DET-read-only, UX-01/03×4,
  REMEDIATE-02, 40-registry-cli).
- `openssh-clients` — provides `ssh` client (image only ships `openssh-server`);
  absent → BHV-02 + **every** six-mode SSH assertion (30-runtime RT-01/02/04, 40/50/51).
- `iproute` — provides `ss` for the sshd readiness poll (non-fatal; image auto-starts sshd).
- `policycoreutils` (optional) — provides `restorecon`; lets the Wave-3 guarded call
  exercise the real binary path. The guard makes it safe to omit (no-op on Docker).

**Convention to preserve:** the comment block explains *why* each package is present
and which packages are deliberately ABSENT (full `curl`/`coreutils` cause minimal-vs-full
file conflicts — lines 12-19, 78-87). Keep the new additions inside the
`--setopt=install_weak_deps=False` invocation; do NOT add a separate RUN layer.

---

### `tests/docker/run.sh` (config, batch) — **SHARED across ALL rows**

**Analog / in-place target:** the `docker run` invocation at **lines 111-119**, tmpfs
flag at **line 116**.

**Exact current invocation (lines 111-119):**
```bash
CID=$(docker run --rm -d \
  --privileged \
  --cgroupns=host \
  -e container=docker \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --tmpfs /run --tmpfs /tmp \
  -v "$REPO_ROOT":/workspace:ro \
  -w /workspace \
  "$IMG")
```

**The one-line fix (RESEARCH §Code Examples, line 196):** change `--tmpfs /tmp` →
`--tmpfs /tmp:exec` on line 116:
```bash
  --tmpfs /run --tmpfs /tmp:exec \
```

**Why:** Docker's `--tmpfs /tmp` mounts `noexec`; the PATH-stub harnesses
(`18-pkg-dispatch`, `18-detect-el9`) write executable stubs under
`BATS_TEST_TMPDIR` (= `/tmp/bats-run-*`) which then cannot `execve`. Bash falls
through to the real `dnf`/`rpm`/`curl` (exit 0, empty capture → grep fails) or dies
`126` (apt-get on EL9). RESEARCH proves both files go **20/20 and 7/7 green with stubs
untouched** the instant `/tmp` is exec-able.

**CRITICAL — Ubuntu-safety of this shared change:** `run.sh` is the single entrypoint
for all four targets (`case "$TARGET"` line 47-58). This tmpfs flag is therefore applied
to Ubuntu rows too. RESEARCH (§Common Pitfalls 5, §Assumptions A5) confirms this is
safe: exec-on-`/tmp` is the normal default *outside* Docker, so the Ubuntu rows execute
identically; the same `noexec /tmp` was silently breaking the *debian* arm of the
Phase-18 stub files (they were only ever validated by dev-host unit-sourcing). Verify
the systemd-in-Docker boot still reaches `running`/`degraded` (the
`is-system-running --wait` poll at lines 134-143) on every row after the change.
Do **not** branch the flag per-target — one unconditional `--tmpfs /tmp:exec` is the
faithful single-point fix.

---

## Wave 2 — Helper generalization (the genuine PAR-01 / EL-08 scope)

### `tests/bats/helpers/distro.bash` (NEW helper, transform)

**Analogs (mirror their shape):** `helpers/detection.bash` (smallest, cleanest verb
file), `helpers/invoke_modes.bash`, `helpers/brownfield.bash`, `helpers/assertions.bash`.

**Shape conventions to copy from the analogs:**

1. **Sourced via `load`, NO `set -euo pipefail`** — every helper file states this
   invariant. From `invoke_modes.bash` lines 9-13:
   ```bash
   #   - No `set -euo pipefail` at top: this file is SOURCED by bats via
   #     `load 'helpers/invoke_modes'`; strict mode inside a sourced library
   #     leaks into the test framework and breaks TAP output.
   ```
   `assertions.bash` (lines 5-8) and `brownfield.bash` (lines 26-27) repeat the same rule.
   Consumers add `load 'helpers/distro'` next to the existing `load` lines (see
   `20-agent-user.bats` lines 19-20).

2. **Header doc-comment block** — every helper opens with a `# tests/bats/helpers/<name>.bash`
   path line + a purpose paragraph + a Design-invariants/notes list. Copy this structure
   (see `detection.bash` lines 1-16, `assertions.bash` lines 1-17).

3. **Function naming** — flat `snake_case` verb names, no namespacing for test helpers
   (`snapshot_paths`, `run_ssh`, `assert_path_has`, `setup_brownfield_host`). Use the
   `distro_*` prefix already named by RESEARCH §Helper Design.

4. **FD-3 diagnostics where a verb is chatty** — mirror `brownfield.bash`'s
   `log_brownfield` (lines 42-48) only if a verb needs to log; pure dispatch verbs don't.

**Family-detect entry verb (RESEARCH §Distro-Aware Helper Design, lines 125-130) —
container-side, no product libs required:**
```bash
# tests/bats/helpers/distro.bash — sourced via `load 'helpers/distro'`. No set -euo (sourced).
distro_family() {
  [[ -n "${_AGENTLINUX_TEST_FAMILY:-}" ]] && { printf '%s' "$_AGENTLINUX_TEST_FAMILY"; return 0; }
  local id=""; [[ -r /etc/os-release ]] && id=$(. /etc/os-release; printf '%s' "${ID:-}")
  case "$id" in almalinux) _AGENTLINUX_TEST_FAMILY=rhel ;; *) _AGENTLINUX_TEST_FAMILY=debian ;; esac
  printf '%s' "$_AGENTLINUX_TEST_FAMILY"
}
```

**The verb set the residue actually needs (RESEARCH §Helper Design table) — every
`debian` arm is the current hardcoded line lifted byte-for-byte so Ubuntu stays identical:**

| Verb | rhel arm | debian arm (current verbatim) | Consumer |
|------|----------|-------------------------------|----------|
| `distro_family` | `rhel` from `/etc/os-release` ID | `debian` | all verbs; `13-reuse`/`15-detection` token seed |
| `distro_locale_file` | `/etc/locale.conf` | `/etc/default/locale` | BHV-01 (`20-agent-user`) |
| `distro_assert_locale <LANG\|LC_ALL>` | grep `^LANG=C.UTF-8` in `/etc/locale.conf` | same in `/etc/default/locale` | BHV-01 |
| `distro_nodesource_repo_paths` | `/etc/yum.repos.d/nodesource-nodejs.repo` | `/etc/apt/sources.list.d/nodesource.sources` | INST-02 snapshot list |
| `distro_pkg_is_installed <pkg>` | `rpm -q` | `dpkg-query -W -f='${Status}' … \| grep -q 'install ok installed'` | brownfield Node gate |
| `distro_install_node22` | `curl rpm.nodesource.com/setup_22.x \| bash -; dnf module reset nodejs -y \|\| true; dnf install -y nodejs` | `curl deb.nodesource.com…; apt-get install -y nodejs` | `setup_brownfield_host`, `_brownfield_baseline` |
| `distro_sudoers_pkg_line <user>` | `agent ALL=(ALL) NOPASSWD: /usr/bin/dnf` | `…: /usr/bin/apt-get, /usr/bin/apt` | REUSE-01 narrow-grant fixture |
| `distro_ssh_unit` | `sshd` | `ssh` | `20`/`50` setup `systemctl start <unit>` |
| `distro_restore_ssh_context <dir>` | `command -v restorecon >/dev/null && restorecon -R -F "$dir" \|\| true` | `:` (no-op) | the two SSH-seeding sites (EL-06) |

**`distro_install_node22` full pattern (RESEARCH §Code Examples, lines 213-225)** — copy
this verbatim; the `debian` arm is exactly `brownfield.bash` lines 86-89/139-141:
```bash
distro_install_node22() {
  case "$(distro_family)" in
    rhel)
      command -v node >/dev/null && rpm -q nodejs >/dev/null 2>&1 && return 0
      curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
      dnf -y module reset nodejs >/dev/null 2>&1 || true
      dnf install -y nodejs >/dev/null 2>&1 ;;
    debian)
      dpkg-query -W -f='${Status}' nodejs 2>/dev/null | grep -q 'install ok installed' && return 0
      curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
      DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs >/dev/null 2>&1 ;;
  esac
}
```

**Don't hand-roll (RESEARCH §Don't Hand-Roll):** where a *product* lib is already
sourced (the `13`/`14`/`15` lib-chain tests), reuse the product verb
`nodesource_repo_paths` (`plugin/lib/pkg.sh:145`) rather than re-hardcoding repo paths
in `distro.bash` — the product verb is the single source of truth and is already
family-correct. Use `distro_nodesource_repo_paths` only where no product lib is sourced
(e.g. the `10-installer` INST-02 snapshot test, which runs container-side).

**CI grep guard to add (RESEARCH line 132):** after the refactor,
`grep -rn 'apt-get\|dpkg-query\|deb.nodesource\|/etc/default/locale\|systemctl start ssh\b' tests/bats/*.bats tests/bats/helpers/*.bash`
should match ONLY inside the `debian` arm of `distro.bash`.

---

### `tests/bats/helpers/brownfield.bash` (helper, batch) — the single biggest work item

**In-place targets — the hardcoded Debian sites RESEARCH flagged, branch each on
`distro_family` (debian arm = current line verbatim):**

**(a) NOPASSWD-for-apt sudoers fragment — `setup_brownfield_host`, lines 74-83:**
```bash
  if [[ ! -f /etc/sudoers.d/local-agent-apt ]]; then
    log_brownfield "installing NOPASSWD-for-apt sudoers fragment"
    local tmp
    tmp=$(mktemp)
    printf 'agent ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt\n' >"$tmp"   # ← distro_sudoers_pkg_line
    if visudo -cf "$tmp" >/dev/null; then
      install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/local-agent-apt
    fi
    rm -f "$tmp"
  fi
```

**(b) Node-present gate + NodeSource install — `setup_brownfield_host`, lines 85-90:**
```bash
  if ! dpkg-query -W -f='${Status}' nodejs 2>/dev/null | grep -q "install ok installed"; then
    log_brownfield "installing NodeSource Node 22 (apt-get install -y nodejs)"
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs >/dev/null 2>&1
  fi
```
→ replace the whole block with `distro_install_node22`.

**(c) `_brownfield_baseline` — same NodeSource block, lines 139-142:**
```bash
  if ! dpkg-query -W -f='${Status}' nodejs 2>/dev/null | grep -q "install ok installed"; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs >/dev/null 2>&1
  fi
```
→ replace with `distro_install_node22`. (The `0440` ADR-012 sudoers line at 136,
`NOPASSWD: ALL`, is family-agnostic — leave as is.)

**(d) REMEDIATE-03 drift fixture narrow grant — `setup_brownfield_for_remediate_03_drift`,
line 285:**
```bash
  printf 'agent ALL=(ALL) NOPASSWD: /usr/bin/apt-get\n' >"$tmp"   # ← distro_sudoers_pkg_line (narrow)
```

**(e) Second NodeSource block — lines 503-507** (Plan 14-03 REMEDIATE-04 fixtures;
identical shape to (b)/(c)) → replace with `distro_install_node22`.

**Ubuntu-preservation:** the `debian` arm of each new `distro.bash` verb is these exact
lines, so the Ubuntu rows run identical commands; only the `case` selector is new
(RESEARCH §Common Pitfalls 5).

---

### `tests/bats/20-agent-user.bats` (test, request-response) — BHV-01 locale + SSH unit

**(a) BHV-01 locale assertions — lines 59-67 (the Debian `/etc/default/locale` path):**
```bash
@test "BHV-01: /etc/default/locale has LANG=C.UTF-8" {
  run grep -E '^LANG=C\.UTF-8$' /etc/default/locale
  assert_exit_zero "BHV-01"
}

@test "BHV-01: /etc/default/locale has LC_ALL=C.UTF-8" {
  run grep -E '^LC_ALL=C\.UTF-8$' /etc/default/locale
  assert_exit_zero "BHV-01"
}
```
→ route through `distro_assert_locale LANG` / `distro_assert_locale LC_ALL` (EL9 path
`/etc/locale.conf`). **Assert the SAME observable at the family-correct path — never
`skip`** (RESEARCH §Pitfall 4). NOTE the `locale -a` test at lines 69-73 already passes
portably (accepts `C.utf8`) — leave it untouched.

**(b) `systemctl start ssh` unit name — `setup()`, line 37:**
```bash
    systemctl start ssh >/dev/null 2>&1 || true
```
→ `systemctl start "$(distro_ssh_unit)"` (EL9 unit = `sshd`). The `ss -lnt … ':22 '`
readiness poll (lines 39-42) is portable once `iproute` is in the image (Wave 1).

**(c) Add `load 'helpers/distro'`** next to the existing loads (lines 19-20):
```bash
load 'helpers/invoke_modes'
load 'helpers/assertions'
```

---

### `tests/bats/10-installer.bats` (test, file-I/O) — INST-02 idempotency snapshot

**In-place target — the `find` snapshot file-list, lines 71-81, hardcoded Debian repo path
on line 78:**
```bash
  find \
    /etc/profile.d/agentlinux.sh \
    /etc/agentlinux.env \
    /etc/cron.d/agentlinux \
    /home/agent/.bashrc \
    /home/agent/CLAUDE.md \
    /home/agent/.npmrc \
    /etc/apt/sources.list.d/nodesource.sources \
    "/opt/agentlinux/catalog/${version}/catalog.json" \
    "/opt/agentlinux/catalog/${version}/agents/test-dummy/install.sh" \
    -type f -exec sha256sum {} + >"$pre" 2>/dev/null
```

**Fix (RESEARCH §Per-File Map row `10-installer`):** replace the literal
`/etc/apt/sources.list.d/nodesource.sources` with the family-correct path from
`distro_nodesource_repo_paths` (EL9 = `/etc/yum.repos.d/nodesource-nodejs.repo`). On EL9
the missing Debian path makes `find` exit 1 → test fails; the family-correct path fixes
it. Depends on `diffutils` (Wave 1) for the actual `diff`. Also add `load 'helpers/distro'`.

---

### `tests/bats/13-reuse.bats` (test, request-response) — REUSE-01 family token seed

**Root cause (RESEARCH §Per-File Map):** REUSE-01 tests that exercise the *real*
`detect::run_once agent` (lines 109-110, 63-64) probe sudo with `/usr/bin/apt-get` on EL9
and return `can_sudo_apt=false`, because the test sources `distro_detect.sh` but never
calls `detect_distro`, leaving `AGENTLINUX_DISTRO_FAMILY` unset → the product probe
defaults to the debian arm (`plugin/lib/detect/user.sh:53`,
`case "${AGENTLINUX_DISTRO_FAMILY:-debian}"`).

**In-place target — the lib-chain helper, lines 39-48:**
```bash
__source_lib_chain() {
  source "$LIB_DIR/log.sh"
  source "$LIB_DIR/distro_detect.sh"
  source "$LIB_DIR/as_user.sh"
  source "$LIB_DIR/detect.sh"
}
```

**Fix:** call `detect_distro` after sourcing `distro_detect.sh` (it `export`s
`AGENTLINUX_DISTRO_FAMILY` — `plugin/lib/distro_detect.sh:45,60-61`) so the downstream
`detect::run_once` probe picks the `rhel` arm (`/usr/bin/dnf`) on EL9. Equivalently seed
the token via `distro_family`. The tests that hardcode
`DETECT_USER_CAN_SUDO_APT=...` overrides (lines 130-136) are family-agnostic and need no
change; only the live-probe tests (lines 58-65, 105-114) need the seed. The narrow-grant
fixture path consumes `distro_sudoers_pkg_line` via the generalized `brownfield.bash`.

---

### `tests/bats/15-detection.bats` (test, request-response) — DET-03 spike

**In-place target — DET-03 npm-prefix probe, lines 184-208** (`effective_prefix` /
`NPM_CONFIG_PREFIX` via `as_user_login`).

**Action (RESEARCH §Open Questions 1, Assumptions A2 — MEDIUM risk):** this is an
**early-Wave-2 spike, not a known edit.** Login-shell PATH+LANG propagate correctly on
EL9 (proven via SSH and passing 22-agent-sudo modes), so DET-03 is *likely* a
fixture/assertion detail — but verify: run the DET-03 probe under `sudo -u agent -i` on
EL9. If `NPM_CONFIG_PREFIX` exports correctly → assertion/fixture fix here; if NOT → it's
a `plugin/lib/as_user.sh` **product** defect and must be escalated (out of the
test-only scope). The DET-read-only invariant (line 118) just needs `diffutils` (Wave 1).

---

### `tests/bats/helpers/tty-driver.py` (helper, event-driven) — defensive timeout

**Action (RESEARCH §Open Questions 2, Assumptions A3, §Don't Hand-Roll):** add a bounded
pexpect timeout so the EL9 15-preflight-ux hang (~13 min unbounded wait at test ~138)
becomes a fast, diagnosable failure. This is **defensive** — the underlying cause is the
brownfield fixture mis-setting EL9 state (fixed by the `brownfield.bash` generalization
above), but add the timeout regardless. No in-repo analog for the timeout shape; follow
pexpect's standard `timeout=` kwarg on `expect()`/`spawn`.

---

## Wave 3 — Guarded restorecon (EL-06; no-op on Docker, real under Phase 22 QEMU)

Both SSH-seeding sites write `~agent/.ssh/authorized_keys`, then must follow with a
**guarded** `restorecon -R -F /home/agent/.ssh` so a confined `sshd_t` can read the key
under real SELinux. The guard is mandatory because `restorecon` (`policycoreutils`) is
absent in the Docker image — an unguarded call aborts the harness (RESEARCH §Pitfall 3).
Use the `distro_restore_ssh_context` verb (no-op `:` on the debian arm; guarded
`command -v restorecon >/dev/null && restorecon -R -F "$dir" || true` on rhel).

**Site 1 — `tests/bats/20-agent-user.bats` `setup()`, lines 28-43** (keys written at
lines 31-33):
```bash
    install -d -m 0700 -o agent -g agent /home/agent/.ssh
    install -m 0600 -o agent -g agent \
      /root/.ssh/id_ed25519.pub /home/agent/.ssh/authorized_keys
    # ← insert: distro_restore_ssh_context /home/agent/.ssh
    systemctl start ssh >/dev/null 2>&1 || true   # ← also becomes distro_ssh_unit (Wave 2)
```

**Site 2 — `tests/bats/50-agents.bats` `setup_file()`, lines 53-64** (re-seeds the
pubkey after `40-*.bats` INST-04 `--purge`/`userdel -r` deletes `/home/agent`):
```bash
  if [[ -f /root/.ssh/id_ed25519.pub ]] \
    && [[ ! -f /home/agent/.ssh/authorized_keys ]]; then
    install -d -m 0700 -o agent -g agent /home/agent/.ssh
    install -m 0600 -o agent -g agent \
      /root/.ssh/id_ed25519.pub /home/agent/.ssh/authorized_keys
    # ← insert: distro_restore_ssh_context /home/agent/.ssh
    systemctl start ssh >/dev/null 2>&1 || true   # ← also distro_ssh_unit (Wave 2)
    for _ in $(seq 1 5); do
      if ss -lnt 2>/dev/null | grep -q ':22 '; then break; fi
      sleep 1
    done
  fi
```

**Installer path note (RESEARCH §SELinux Verdict, point a):** the installer itself does
NOT seed `~agent/.ssh` (keys come from cloud-init/external), so there is no installer
restorecon site to add in Phase 20 — both sites are in the test harness. State this
plainly in the plan/summary; do not invent an installer site.

**SELinux reality to document (RESEARCH §SELinux-in-Docker Verdict):** enforcing SELinux
is structurally unavailable on the Docker row (AppArmor host kernel, no `selinuxfs`), so
on Docker the restorecon call is a deliberate no-op and the six modes go green via
`openssh-clients` + `sshd`. The real enforcing-SELinux six-modes proof is **Phase 22
QEMU**. NEVER `setenforce 0`.

---

## Shared Patterns

### Family dispatch (the one fork point)
**Source:** NEW `tests/bats/helpers/distro.bash` `distro_family` verb (mirrors product
`plugin/lib/distro_detect.sh:45` `detect_distro`).
**Apply to:** every generalized site below. One `case` per concept; the `debian` arm is
the current line verbatim. Auditable by the CI grep guard.

### Sourced-helper invariant (no strict mode)
**Source:** `helpers/invoke_modes.bash` lines 9-13, `helpers/assertions.bash` lines 5-8,
`helpers/brownfield.bash` lines 26-27.
**Apply to:** `distro.bash` — NO `set -euo pipefail`; consumers add `load 'helpers/distro'`.

### Guarded restorecon
**Source:** `distro_restore_ssh_context` (RESEARCH line 120, §Pitfall 3).
**Apply to:** both SSH-seeding sites (`20-agent-user.bats` setup, `50-agents.bats`
setup_file). `command -v restorecon >/dev/null && restorecon -R -F "$dir" || true`.

### Reuse the product verb, don't re-hardcode
**Source:** `plugin/lib/pkg.sh:145` `nodesource_repo_paths` (already family-correct).
**Apply to:** any test where a product lib is sourced (13/14/15 lib-chain tests) — call
the product verb, not a test re-implementation. Use `distro_nodesource_repo_paths` only
container-side where no product lib is loaded (10-installer INST-02).

---

## No Analog Found

None. Every file maps either to a sibling (`Dockerfile.ubuntu-24.04`), to itself
(in-place edits), or to an existing helper whose shape the new `distro.bash` mirrors.
The product side that the tests dispatch through (`distro_detect.sh`, `pkg.sh`,
`detect/user.sh`) already exists and is family-correct — Phase 20 does not touch it.

## Metadata

**Analog search scope:** `tests/docker/`, `tests/bats/`, `tests/bats/helpers/`,
`plugin/lib/`, `plugin/lib/detect/`.
**Files scanned:** Dockerfile.almalinux-9, run.sh, detection.bash, invoke_modes.bash,
assertions.bash, brownfield.bash, 20-agent-user.bats, 10-installer.bats, 13-reuse.bats,
15-detection.bats, 50-agents.bats, distro_detect.sh, pkg.sh, detect/user.sh.
**Pattern extraction date:** 2026-06-28
