# 017: Distro-family bucket (AGENTLINUX_DISTRO_FAMILY) + single pkg.sh dispatch

**Status:** Accepted
**Date:** 2026-06-28

## Context

v0.3.5 ports the Ubuntu-only AgentLinux installer to also run on AlmaLinux 9.
The two distros diverge on every package and locale operation: `apt-get`/`dpkg`
vs `dnf`/`rpm`, `locale-gen` + `/etc/default/locale` vs a direct `/etc/locale.conf`
write, and `deb.nodesource.com` vs `rpm.nodesource.com`. Before this phase the
installer hardcoded those Ubuntu mechanisms at ~13 call sites spread across five
files (`distro_detect.sh`, the three provisioners `10-agent-user.sh`/`20-sudoers.sh`/
`30-nodejs.sh`, the entrypoint `bin/agentlinux-install`, and the detection
fragments `detect/nodejs.sh`/`detect/user.sh`).

Two framing facts shaped the decision:

- **The behavior contract asserts outcomes, not package managers** (ADR-002). The
  bats suite checks that Node ≥ 22 is installed, that passwordless sudo works, that
  `C.UTF-8` appears in `locale -a`, and that a NodeSource-installed Node is classified
  as such — never *which* package manager produced those outcomes. So the port is a
  mechanical call-site substitution behind one abstraction, with **Ubuntu behavior
  preserved byte-for-byte**.

- **The scope is AlmaLinux 9 ONLY.** This is a port to one new distro, not a claim
  of EL-family support. Rocky, RHEL, CentOS, Fedora, and AlmaLinux 8/10 are out of
  scope and stay explicitly rejected.

The question this ADR records: how should the apt↔dnf divergence be expressed in
the codebase so it stays auditable, keeps Ubuntu green, and leaves a clean path for
a future EL-family expansion without making any family-wide promise now?

## Decision

Introduce **one** distro-family bucket and route **every** package/locale/NodeSource
operation through **one** dispatch layer.

1. **`lib/distro_detect.sh` exports `AGENTLINUX_DISTRO_FAMILY ∈ {debian, rhel}`** —
   the single fork point. `detect_distro` matches on the os-release `ID` field
   exactly (`ubuntu` → `debian`, `almalinux` → `rhel`), admitting AlmaLinux at
   `VERSION_ID` `9` or `9.*` only. Every downstream layer reads this env var; no
   call site ever re-parses `/etc/os-release`. The existing `AGENTLINUX_DISTRO_VERSION`
   export is preserved. The escape hatch (`AGENTLINUX_SKIP_DISTRO_CHECK=1`) now also
   seeds a family (explicit override → os-release `ID` → `debian` default) so a
   unit-sourced consumer never dispatches on an empty bucket.

2. **`lib/pkg.sh` (new) is the one place the apt↔dnf branch lives.** It exposes
   exactly the verbs the call sites need — `pkg_install`, `pkg_is_installed`,
   `pkg_remove`, `pkg_autoremove`, `nodesource_prereqs`, `nodesource_setup`,
   `nodesource_repo_paths`, `nodesource_module_reset`, `locale_ensure` — each a
   two-arm `case "$AGENTLINUX_DISTRO_FAMILY"`. The **debian arm of every verb is
   lifted byte-for-byte** from its current Ubuntu call site; the **rhel arm** carries
   the EL9 equivalent (`dnf install -y --setopt=install_weak_deps=False`, `rpm -q`,
   `rpm.nodesource.com/setup_22.x`, a `/etc/locale.conf` write via `write_file_atomic`).
   `pkg.sh` is sourced from the entrypoint immediately after `distro_detect.sh` and
   before `idempotency.sh`; it only *declares* functions at source time, so verbs
   resolve at call time after `detect_distro` exports the family.

3. **The 13 call sites become verb calls.** Provisioners and the entrypoint call
   `locale_ensure C.UTF-8`, `pkg_install sudo`, `nodesource_prereqs`/`nodesource_setup`/
   `pkg_install nodejs`, `pkg_install jq`, and iterate `nodesource_repo_paths` for the
   install idempotency gate, the detect gate, and the `--purge` cleanup (one source of
   truth, three lockstep sites). No call site ever inlines `if [[ $FAMILY == rhel ]]`.

4. **JSON contract field names are preserved while their probes generalize.** The
   DET-01 field `user.can_sudo_apt` (asserted by `render.sh` and the bats suite) keeps
   its name; only the *probe binary* branches (`/usr/bin/apt-get --help` on debian,
   `/usr/bin/dnf --version` on rhel, both absolute-path anchored).

5. **The curl-installer pre-gate stays in lockstep.** `packaging/curl-installer/install.sh`
   (`detect_supported_distro`) mirrors the same two-arm `case` so the pre-gate and the
   in-installer gate accept and reject the same set.

## Consequences

- **One auditable branch point.** The apt↔dnf fork lives once per verb in `pkg.sh`;
  a CI grep guard (`grep -rn 'apt-get\|dpkg' plugin/`) should match only inside the
  debian arms of `pkg.sh`. Reviewers reason about the divergence in one file instead
  of chasing 13 sites across five files.

- **Ubuntu behavior is provably unchanged.** Because every debian arm is the prior
  command lifted verbatim, the Ubuntu Docker rows stay byte-for-byte green; the
  abstraction is purely additive. The bats behavior contract survives unchanged.

- **A future EL-family expansion is a small, contained follow-on** — adding another
  `ID` arm in `distro_detect.sh` plus the corresponding verb arms in `pkg.sh` — but
  **no family-wide claim is made now.** This is AlmaLinux 9 ONLY. Rocky/RHEL/CentOS/
  Fedora and AlmaLinux 8/10 remain explicitly rejected with an honest message; the
  abstraction makes a later expansion cheap without promising it today (see
  ADR-016 / the "name the real consumer before the ceremony" principle).

- **Deferred scope** stays out: AlmaLinux 10, RHEL, and Rocky are not supported and
  are not on this milestone. The two-bucket `{debian, rhel}` design accommodates them
  structurally, but each would need its own validation pass (NodeSource availability,
  SELinux posture, os-release `ID`) before any acceptance claim.

### Rejected alternatives

- **Inline `if [[ $FAMILY == rhel ]]` at each call site** — rejected. That scatters
  the same two-arm branch across 13 sites in five files: 13× duplicated drift that no
  single review can audit, and the exact thing one dispatch layer exists to prevent.

- **AppStream `dnf module install nodejs:22`** instead of the NodeSource RPM —
  rejected. AppStream stream availability drifts across 9.x minor releases (18/20 are
  reliable, 22 is not guaranteed), there is no pinned default, and it diverges from
  the NodeSource-everywhere invariant that ADR-005 / ADR-006 established for the deb
  path. `nodesource_setup` uses `rpm.nodesource.com/setup_22.x` (which sets
  `module_hotfixes=1`), and `nodesource_module_reset` runs `dnf -y module reset
  nodejs` (rhel-only, no-op on debian) to defuse an already-installed AppStream
  stream on brownfield hosts. The RT-01 `node --version` ≥ 22 hard-check is retained.

- **`localectl set-locale`** for the EL9 locale — rejected. `localectl` needs
  `systemd-localed` over D-Bus, which is absent in Docker test containers and would
  hang or fail vacuously. The rhel arm of `locale_ensure` writes `/etc/locale.conf`
  directly (C.UTF-8 is a glibc 2.34 built-in on EL9 — no `locale-gen`, no langpack).

- **Branching on os-release `ID_LIKE`** instead of `ID` — rejected. `ID_LIKE="rhel
  centos fedora"` would silently admit Rocky/RHEL/CentOS/Fedora — out of scope,
  untested, a false promise. The gate matches `ID=almalinux` exactly (project
  convention; also EL-01).

- **`microdnf` / `almalinux/9-minimal`** as the package manager — rejected. Only full
  `dnf` has the `module` subcommand and weak-deps control the NodeSource defuse and
  the `--no-install-recommends` analogue depend on; the minimal image is out of scope.

## References

- ADR-002 — behavior-contract framing (outcomes, not implementations; the rule that
  lets the package manager branch freely while observables hold).
- ADR-005 — system Node.js via NodeSource over version managers (the deb path the rhel
  RPM path mirrors).
- ADR-006 — curl-pipe-bash + deb install mechanism (the NodeSource acceptance the rhel
  arm preserves).
- ADR-012 — agent-user full sudo (`20-sudoers.sh` routes only its `sudo`-package
  install through `pkg_install`; the 0440 root:root drop-in install/validate path is
  untouched).
- `plugin/lib/distro_detect.sh`, `plugin/lib/pkg.sh` — the files this ADR documents.
- REQUIREMENTS.md — EL-01 (family detection + escape-hatch seed), EL-02 (verb dispatch;
  all 13 sites routed; Ubuntu byte-for-byte).
- Phase 18 plans 18-01..18-05 SUMMARY.md — what shipped against this decision.
