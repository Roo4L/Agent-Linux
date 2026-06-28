# Phase 20: Behavior-Test-Green on AlmaLinux 9 - Context

**Gathered:** 2026-06-28
**Status:** Ready for planning
**Mode:** Auto-generated (test-conformance/refactor phase — locked decisions from REQUIREMENTS/ROADMAP; discuss skipped)

<domain>
## Phase Boundary

Drive the full existing behavior contract — `BHV` / `RT` / `AGT` / `CLI` / `CAT` /
`INST` (v0.3.0) and `DET` / `REUSE` / `REMEDIATE` / `UX` (v0.3.4) — GREEN on the
AlmaLinux 9 Docker row, with Ubuntu-path assertions generalized to distro-aware
helpers rather than weakened or skipped. Requirements: EL-06, EL-08, PAR-01.

In scope:
- **PAR-01:** every bats file green on the `almalinux-9` Docker row; Ubuntu-specific
  path/tool assertions (locale.conf path, NodeSource repo path, `dpkg-query`→`rpm -q`,
  sudoers fixtures, apt-vs-dnf detectors) generalized through a distro-aware helper
  layer (`tests/bats/helpers/distro.bash` or extensions to the existing helpers) —
  assert the SAME observable on EL9, never `skip`/weaken.
- **EL-06:** all six invocation modes (interactive bash login, non-interactive SSH,
  cron, systemd `User=agent`, `sudo -u agent`, `sudo -u agent -i`) green on EL9.
  In particular any path writing `~agent/.ssh/authorized_keys` (installer AND test
  harness `setup`) follows with `restorecon -R -F ~agent/.ssh` so confined `sshd_t`
  can read it and non-interactive SSH authenticates. **SELinux stays enforcing —
  `setenforce 0` / `SELINUX=disabled` is NEVER used to make a test pass.**
- **EL-08:** the v0.3.4 four-state brownfield flow (Reuse / Create / Remediate /
  Bail) produces the same per-component decisions on EL9 as Ubuntu, driven by the
  EL-07 evidence sources; `agentlinux install --dry-run` observably non-mutating on
  EL9 (exits 0, host snapshot byte-identical); `--yes` consent + exit codes 64/65/1/0
  behave as on Ubuntu. Verified with AppStream-Node, NodeSource-RPM, and nvm-managed
  fixtures.

Out of scope: the QEMU release-gate row + the real-enforcing-SELinux re-confirmation
+ the milestone-close AGT-02 gate (Phase 22 / HARN-02 / PAR-02 / REL-01); catalog
agent install verification (Phase 21 / REC-01). Once the Docker arm is generally
green, Phase 21 may overlap.

</domain>

<decisions>
## Implementation Decisions

### Locked (from REQUIREMENTS.md + ROADMAP, non-negotiable)
- Generalize, never weaken: a Debian-specific assertion becomes a distro-aware
  helper asserting the same observable on EL9. No `skip` to make EL9 green.
- SELinux stays enforcing; the fix for non-interactive SSH is `restorecon -R -F
  ~agent/.ssh`, never disabling SELinux.
- The behavior contract is the invariant; the implementation may branch
  (apt→dnf, dpkg→rpm, locale-gen→/etc/locale.conf) but the asserted observable
  must hold identically on both families.
- Preserve Ubuntu green: every change must keep all Ubuntu rows green
  byte-for-equivalent (the distro-aware helper dispatches on family).

### Claude's Discretion
The helper design (new `tests/bats/helpers/distro.bash` vs extending the existing
`assertions.bash`/`detection.bash`/`brownfield.bash`/`invoke_modes.bash`), the
per-file generalization tactics, and the root-cause fixes are at Claude's
discretion, guided by the Phase 19 inventory and the success criteria.

</decisions>

<code_context>
## Existing Code Insights

### Phase 19 starting work-list (the live EL9 RED inventory — Phase 20's input)
From 19-01-SUMMARY (real `almalinux:9` Docker run): **1 green, 6 red inventoried**,
9 deferred. RED files + themes:
- `18-detect-el9` (3 fail), `18-pkg-dispatch` (14 fail, BOTH arms) — **harness
  hermeticity**, NOT a product regression. ⚠ Per Phase 19 code review the cause is
  NOT "real dnf/rpm shadows the PATH stubs" (the stubs PATH-prepend and DO shadow).
  Root-cause each file first. Known leaks: `18-detect-el9.bats` keys the user probe
  on `$(id -un)` = ambient user = **root** inside `docker exec` (host runs as the dev
  user); `detect/nodejs.sh` + version-manager scans resolve the container's real
  system Node via PATH (fixtures isolate HOME but not PATH-resolved Node).
- `10-installer` (9 fail: INST-01 log banner, INST-02 idempotency, DOC-02 CLAUDE.md,
  CAT-05 catalog snapshot), `13-reuse` (5: REUSE-01 `user_can_sudo_apt` needs dnf
  parity), `14-remediate` (19: REMEDIATE-01..04 + NO-MUTATION snapshots — apt/npm/
  sudoers brownfield paths), `15-detection` (2: DET-03 npm prefix probe, read-only
  invariant byte-drift).
- 9 not-yet-inventoried (slow per-test installer re-runs): `15-preflight-ux`,
  `20-agent-user`, `22-agent-sudo`, `30-runtime`, `40-registry-cli`, `50-agents`,
  `51/52-agt02`, `60-curl-installer`.

### Existing test helpers (the analogs to extend / the dispatch home)
`tests/bats/helpers/`: `assertions.bash`, `brownfield.bash`, `detection.bash`,
`invoke_modes.bash`, `tty-driver.py`. The six-invocation-mode harness lives in
`invoke_modes.bash` — the `restorecon ~agent/.ssh` fix likely lands in the
installer AND the harness `setup` that seeds authorized_keys.

### Substrate
`tests/docker/Dockerfile.almalinux-9` + `run.sh almalinux-9` (Phase 19) — the
green-able substrate to iterate against. Docker IS available locally.

</code_context>

<specifics>
## Specific Ideas

- The full per-file green sweep re-runs the installer per test and is slow — plan
  for iterative Docker cycles; consider running the suite per-file or in groups.
- **Open research question (flag if it forces a decision): SELinux-enforcing-in-
  Docker feasibility.** Phase 19 noted the Docker substrate loads no enforcing
  SELinux policy (containers on an AppArmor/Ubuntu CI host can't run EL9 SELinux
  enforcing). EL-06 requires "six modes under enforcing SELinux." Research must
  resolve honestly whether the Docker row can actually exercise enforcing SELinux,
  or whether the `restorecon` code lands + six modes go green on the Docker row
  (SELinux not truly enforcing there) while the real enforcing-SELinux six-modes
  proof is the Phase 22 QEMU row (per the REQUIREMENTS EL-06 note). NEVER
  `setenforce 0` to pass.

</specifics>

<deferred>
## Deferred Ideas

None new — QEMU enforcing-SELinux re-confirmation + AGT-02 milestone gate are
Phase 22; catalog verify is Phase 21.

</deferred>
