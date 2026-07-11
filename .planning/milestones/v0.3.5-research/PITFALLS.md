# Pitfalls Research

**Domain:** Porting a Debian/Ubuntu-tested bash installer (agent-user provisioner + six-mode PATH wiring + NOPASSWD sudoers + Node.js runtime + catalog CLI) to AlmaLinux 9 (EL9) — v0.3.5, AL-47.
**Researched:** 2026-06-27
**Confidence:** HIGH on SELinux-ssh / locale tooling / dnf-module / apt-dpkg break sites (verified against current EL9 docs + the actual code); MEDIUM on SELinux-systemd and secure_path blast radius (depends on targeted-policy user mapping, verified by reasoning + RH docs).

> **Scope note for the roadmapper.** These are EL9-specific traps: things that are GREEN on Ubuntu today and silently break on AlmaLinux 9. Each pitfall names the exact break site (file:line), which of the six invocation modes / which bats file it breaks, the prevention, the v0.3.5 phase that owns it, and a detection/test idea. Phases referenced:
>
> | Phase tag | Scope (from PROJECT.md target features) |
> |-----------|------------------------------------------|
> | **P-DETECT** | distro detection + branching in `plugin/lib/` (apt→dnf, dpkg→rpm) |
> | **P-PROV** | provisioner EL9 branches: `10`-locale, `20`-sudoers, `30`-nodejs, `40`-path-wiring |
> | **P-BROWN** | brownfield detection port (`plugin/lib/detect/*`) rpm/dnf |
> | **P-CAT** | catalog recipe EL9 verification (claude-code / gsd / playwright `--with-deps`) |
> | **P-HARNESS** | Docker EL9 row + QEMU AlmaLinux cloud-image row (ADR-007) |
> | **P-REL** | release-gate: AlmaLinux 9 green before tag |

---

## Critical Pitfalls

### Pitfall 1: SELinux (enforcing by default) denies sshd the agent's `authorized_keys` → BHV-02 non-interactive SSH mode silently fails

**What goes wrong:**
AlmaLinux 9 ships SELinux in **enforcing/targeted** mode out of the box (Ubuntu ships AppArmor, effectively permissive for this workload). When `~agent/.ssh/authorized_keys` is created by a root process — the bats `setup()` in `tests/bats/20-agent-user.bats:31-33` does exactly this (`install -d -m 0700 .../.ssh` + `install -m 0600 ... authorized_keys`), and cloud-init / a human admin does the equivalent on a real host — the file is labeled with the **creating process's** default type (e.g. `unconfined_u:object_r:user_home_t` or `…:default_t`), **not** `ssh_home_t`. `sshd` runs confined as `sshd_t` and is only permitted to read `ssh_home_t`. Result: public-key auth is silently refused, the connection falls through to "Permission denied (publickey)", and **`run_ssh` (BHV-02) fails for the whole `tests/bats/20-agent-user.bats` SSH block** — while every other mode (su -, sudo -i, cron, systemd) stays green, so it looks like "just the SSH tests are flaky."

**Why it happens:**
The Ubuntu harness never had to think about file labels — there is no enforcing MAC layer reading those files. The label-on-create comes from the parent dir / process domain, and `install`/`cp`/`mv` do **not** apply the policy's target context the way a fresh `useradd` or a `restorecon` would. `/home/agent/.ssh` even at the default `/home` location can carry a wrong label when its contents are written by a non-login root process.

**How to avoid:**
After any code path writes into `~agent/.ssh` (or `~agent` more broadly), run `restorecon -R -F -v /home/agent` (or at minimum `/home/agent/.ssh`). For the **default `/home/agent` location restorecon is sufficient** — the shipped targeted policy already maps `/home/[^/]+/\.ssh(/.*)?` → `ssh_home_t`, so no `semanage fcontext` is needed. `semanage fcontext -a -t ssh_home_t …` is **only** required if the agent home is relocated outside `/home` (out of v0.3.5 scope). Apply restorecon in two places: (a) the **harness** `setup()` after it installs `authorized_keys` (P-HARNESS), and (b) the **installer/provisioner** as a guard after it touches files under the agent home (P-PROV), guarded by `command -v restorecon` so it is a no-op on Ubuntu / SELinux-disabled hosts.

**The anti-pattern to reject:** `setenforce 0` or `SELINUX=disabled` in `/etc/selinux/config`. This makes the bats suite green while shipping a product that breaks on every real enforcing AlmaLinux host — the *exact* "paper over the environment bug" failure class CLAUDE.md forbids. The maintainer runs AlmaLinux daily with SELinux enforcing; a disable would fail first-person friction on day one. The correct fix is a few `restorecon` calls, not a policy downgrade.

**Warning signs:**
`run_ssh` tests fail with "Permission denied (publickey)" while `run_sudo_u_i` / `run_interactive` pass; `ausearch -m avc -ts recent` (or `/var/log/audit/audit.log`) shows `denied { read }` for `comm="sshd" … tcontext=…:user_home_t`; `ls -Z /home/agent/.ssh/authorized_keys` shows a type other than `ssh_home_t`.

**Phase to address:** P-HARNESS (test-setup restorecon) + P-PROV (installer restorecon guard). **Detection/test idea:** a bats assertion `ls -Z /home/agent/.ssh/authorized_keys | grep -q ssh_home_t` gated to run only when `getenforce` is `Enforcing`; plus a post-install AVC-denial check (`ausearch -m avc -ts boot` is empty for `sshd_t`/`agent`).

---

### Pitfall 2: EL9 has no `locale-gen`, no `update-locale`, no `locales` package, and no `/etc/default/locale` — the locale step in `10-agent-user.sh` apt-installs into the void

**What goes wrong:**
`plugin/provisioner/10-agent-user.sh:76-94` is hardcoded Debian: it `command -v locale-gen`, and on miss runs `apt-get update && apt-get install -y locales`, then `locale-gen C.UTF-8`, then `update-locale LANG=… LC_ALL=…` (which writes `/etc/default/locale`). On EL9 **none of these exist**: there is no `locale-gen`, no `update-locale`, no `locales` apt package, and `apt-get` is absent — so the `command -v locale-gen` miss branch tries `apt-get` and dies with `apt-get: command not found`, tripping the ERR trap and failing the install at the very first provisioner. Separately, the BHV-01 assertions `tests/bats/20-agent-user.bats:59-67` hard-grep `/etc/default/locale` for `LANG=C.UTF-8` / `LC_ALL=C.UTF-8` — a file EL9 never creates (EL uses `/etc/locale.conf`).

**Why it happens:**
Debian provisions locales imperatively (`locale-gen` compiles them from `/etc/locale.gen`; `update-locale` writes `/etc/default/locale`). EL provisions them declaratively: glibc langpacks (`glibc-langpack-*`) drop precompiled locales, and the system locale lives in `/etc/locale.conf` (managed by `localectl`). The whole imperative toolchain the installer leans on is Debian-only.

**How to avoid:**
Good news verified: **`C.UTF-8` is a glibc built-in on EL9** even with only `glibc-minimal-langpack` installed (RHEL 9 / glibc 2.34 — Red Hat backported it), so `locale -a | grep -i '^c\.utf-8$'` **passes on AlmaLinux 9 without installing anything** — the BHV-01 "C.UTF-8 available" check at `20-agent-user.bats:69-73` survives unchanged. The EL branch of `10-agent-user.sh` must: (a) skip the `locale-gen`/`update-locale`/`apt-get install locales` block entirely; (b) write the system locale to **`/etc/locale.conf`** (`LANG=C.UTF-8`\n`LC_ALL=C.UTF-8`) instead of `/etc/default/locale`; (c) the `40-path-wiring.sh` artefacts already `export LANG/LC_ALL` in `/etc/profile.d/agentlinux.sh` + `/etc/agentlinux.env` + `/etc/cron.d/agentlinux`, so all six modes still see C.UTF-8 regardless. For the **test contract**: either write `/etc/default/locale` *as well* on EL (cheap, keeps the existing assertion green), or branch the BHV-01 assertion per-distro to grep `/etc/locale.conf` on EL. Note: only `C.UTF-8` is safe to assume — `en_US.UTF-8` would need `glibc-langpack-en` (see Pitfall 7).

**Warning signs:**
Install aborts at `10-agent-user: starting` with `apt-get: command not found`; or all three BHV-01 `/etc/default/locale` tests fail with "file not found" while the `locale -a` test passes; perl emits `setlocale: LC_CTYPE cannot be set` noise.

**Phase to address:** P-PROV (locale branch in `10-agent-user.sh`) + P-HARNESS/spec (BHV-01 assertion portability). **Detection/test idea:** assert `localectl status` reports `C.UTF-8` (or `/etc/locale.conf` contains it) on EL; keep the cross-distro `locale -a` check as the real correctness gate.

---

### Pitfall 3: dnf module-stream collision — AppStream ships a `nodejs` module; a brownfield host with it installed conflicts with NodeSource 22

**What goes wrong:**
`plugin/provisioner/30-nodejs.sh:71-78` runs `curl … deb.nodesource.com/setup_22.x | bash -` then `apt-get install nodejs`. On EL9 the analogue is `rpm.nodesource.com/setup_22.x` + `dnf install nodejs`, but EL adds a layer Debian doesn't have: **dnf modules**. RHEL 9 AppStream defines a `nodejs` module with streams (18/20/22) and — critically — **defines no default stream**, so a clean AlmaLinux 9 cloud image has *no* nodejs installed and a bare `dnf install nodejs` would fail with "no package nodejs available" unless a stream is enabled or a non-modular repo (NodeSource) supplies it. Worse, on a **brownfield** host (the v0.3.4 world this project now lives in) where someone ran `dnf module install nodejs:18`, installing NodeSource's `nodejs` package **conflicts** with the module-locked RPM, and `dnf` errors with a modular-filtering / "package … is filtered out by modular filtering" or a version-lock conflict.

**Why it happens:**
NodeSource's EL `setup_22.x` sets **`module_hotfixes=1`** in `/etc/yum.repos.d/nodesource-nodejs.repo` (verified against the upstream script), which lets NodeSource packages bypass modular filtering — **this is enough for the greenfield cloud image**. But `module_hotfixes` does **not** reset a stream that is already *installed*; a pre-existing `dnf module install nodejs:NN` leaves an installed module RPM that still collides. The NodeSource setup script itself does **not** run `dnf module reset/disable nodejs` (verified).

**How to avoid:**
For greenfield (the primary v0.3.5 acceptance path): rely on NodeSource's `module_hotfixes=1` + `dnf install -y nodejs` — no module reset needed. For brownfield robustness: before/around the NodeSource install on EL, run `dnf -y module reset nodejs` (and treat its failure as non-fatal) so any pre-enabled/installed AppStream stream is cleared, then install from NodeSource. Mirror the dual-gate idempotency the deb path already has (`30-nodejs.sh:68-74`): gate on the repo file `/etc/yum.repos.d/nodesource-nodejs.repo` existing. Keep the `RT-01` post-install `node --version >= 22` hard-check (`30-nodejs.sh:83-87`) — it already catches "AppStream's older nodejs got installed first."

**Warning signs:**
`dnf install nodejs` reports "Unable to find a match" (no stream enabled, module_hotfixes missing) or "package nodejs-1:18… is filtered out by modular filtering" or a conflict against an installed `nodejs:18` module; `node --version` returns an 18.x/20.x after install (AppStream won the resolution) tripping the RT-01 guard.

**Phase to address:** P-PROV (`30-nodejs.sh` EL branch) — also relevant to P-BROWN (detecting a pre-existing AppStream module, see Pitfall 9). **Detection/test idea:** bats on EL: after install, `rpm -q nodejs` shows the `nodesource` vendor/`…nodesource…` release string AND `node --version` starts `v22.`; a brownfield fixture that `dnf module install nodejs:18` first, then runs the installer, must still land Node 22.

---

### Pitfall 4: `apt-get` / `dpkg` are hardcoded across the installer and the brownfield detector — every one is a hard failure on EL9

**What goes wrong:**
The package-manager calls are scattered and all Debian:
- `plugin/bin/agentlinux-install:286-287` (`ensure_jq` → `apt-get update`/`apt-get install jq`)
- `plugin/bin/agentlinux-install:395-396` (`--purge --remove-nodejs` → `apt-get purge nodejs` / `apt-get autoremove`)
- `plugin/provisioner/10-agent-user.sh:78-79` (`locales` — see Pitfall 2)
- `plugin/provisioner/20-sudoers.sh:27-28` (`sudo` package)
- `plugin/provisioner/30-nodejs.sh:56-78` (`curl gnupg ca-certificates apt-transport-https`, NodeSource deb, `nodejs`)
- `plugin/lib/detect/nodejs.sh:84` (`dpkg-query -W -f='${Version}' nodejs`)
- `plugin/lib/detect/user.sh:48` (`sudo -u user -n /usr/bin/apt-get --help` — the "can this user sudo-install?" probe)

On EL9, `apt-get`/`dpkg`/`dpkg-query` do not exist; each call dies (or, for the detector, mis-reports). Because they're sprinkled across entrypoint + 3 provisioners + 2 detectors, a single "if EL then dnf" at one site is insufficient — this needs a **package-manager abstraction**.

**Why it happens:**
v0.3.0 was Ubuntu-only by explicit constraint; there was no reason to abstract the package manager. The brownfield detector (v0.3.4) deepened the dependency: `detect/user.sh` literally encodes "can sudo apt-get" as a capability signal.

**How to avoid:**
Add a thin distro-dispatch layer in `plugin/lib/` (alongside the already-present `distro_detect.sh`) exposing `pkg_install`, `pkg_remove`, `pkg_query_version`, and `pkg_repo_present` that branch on `AGENTLINUX_DISTRO_ID` (apt/dpkg vs dnf/rpm). Route **every** call above through it. For the detector's `can_sudo_apt` capability, generalize to `can_sudo_pkg` probing `/usr/bin/dnf --version` on EL (keep the absolute-path anchoring that `user.sh:42-48` documents — same shadow-binary defense). EL equivalents: `apt-get install` → `dnf install -y`; `apt-get purge X` → `dnf remove -y X`; `dpkg-query -W -f='${Version}' nodejs` → `rpm -q --qf '%{VERSION}-%{RELEASE}' nodejs`; `DEBIAN_FRONTEND=noninteractive` has no EL analogue (dnf is non-interactive with `-y`).

**Warning signs:**
`apt-get: command not found` / `dpkg-query: command not found` anywhere in the transcript; `detect/user.sh` always reports `can_sudo_apt=false` on EL (because the probe binary is missing) → brownfield remediation decisions skew.

**Phase to address:** P-DETECT (the `pkg_*` abstraction) consumed by P-PROV + P-BROWN. **Detection/test idea:** grep guard in CI — `grep -rn 'apt-get\|dpkg' plugin/` must only match inside the apt branch of the abstraction; a bats EL run reaches `agentlinux-install complete` (proves no stray pkg call fired).

---

### Pitfall 5: NodeSource repo is a different mechanism on EL (rpm repo + GPG key import), and the brownfield "is NodeSource installed?" gate checks Debian-only paths

**What goes wrong:**
Two coupled break sites:
1. **Install** (`30-nodejs.sh:60-74`): the deb path adds `/etc/apt/sources.list.d/nodesource.{sources,list}` via `setup_22.x | bash`. The rpm path creates **`/etc/yum.repos.d/nodesource-nodejs.repo`** (+ `nodesource-nsolid.repo`) and imports the GPG key `https://rpm.nodesource.com/gpgkey/ns-operations-public.key` (verified). The dual-filename idempotency gate at `30-nodejs.sh:68-69` and the purge cleanup at `agentlinux-install:387-389` (`rm nodesource.sources/.list`, `apt/preferences.d/nodejs`) both reference paths that **don't exist on EL** — so re-runs don't short-circuit and `--purge` leaves the NodeSource repo + imported GPG key behind.
2. **Detect** (`detect/nodejs.sh:85-90`): classifies "NodeSource APT" by `dpkg-query` version containing `-1nodesource` **AND** `nodesource.sources/.list` present. On EL both gates are structurally wrong (no dpkg, no `.sources`), so a NodeSource-installed Node on a brownfield EL host is mis-detected as absent → the installer re-adds the repo / mis-decides reuse.

**Why it happens:**
The deb822/legacy `.list` dual-gate was a careful Debian-migration detail; it has no EL meaning. The `-1nodesource` Debian version suffix becomes a `…nodesource…` RPM **release** string queried differently.

**How to avoid:**
EL branch of the repo add: gate on `/etc/yum.repos.d/nodesource-nodejs.repo`; import the GPG key explicitly (`rpm --import` or let dnf fetch via `gpgkey=` — the script sets it). EL branch of detect: `rpm -q nodejs` release contains `nodesource` AND `/etc/yum.repos.d/nodesource-nodejs.repo` present. EL branch of purge: `rm -f /etc/yum.repos.d/nodesource-nodejs.repo /etc/yum.repos.d/nodesource-nsolid.repo` and (optionally) `dnf remove -y nodejs`. Do **not** verify the setup script body SHA (NodeSource publishes none — same ADR-005 acceptance as the deb path); HTTPS + the GPG-signed repo is the integrity control.

**Warning signs:**
Second `agentlinux-install` run re-downloads/re-adds the NodeSource repo (INST-02 idempotency regression); `--purge` leaves `/etc/yum.repos.d/nodesource-*.repo` behind; brownfield report shows Node "absent" on a host where `node --version` returns v22 from `/usr/bin/node`.

**Phase to address:** P-PROV (`30-nodejs.sh`) + P-BROWN (`detect/nodejs.sh`) + purge in `agentlinux-install`. **Detection/test idea:** EL idempotency bats: run installer twice, assert no NodeSource fetch on the second pass; purge bats: assert `/etc/yum.repos.d/nodesource-nodejs.repo` is gone after `--purge`.

---

### Pitfall 6: EL9 `sudo` secure_path is narrower than Ubuntu's (no `/usr/local/bin`) — and the NOPASSWD drop-in inherits it

**What goes wrong:**
EL9's default `/etc/sudoers` sets `Defaults secure_path = /sbin:/bin:/usr/sbin:/usr/bin` — **notably excluding `/usr/local/bin`**, which Ubuntu's default secure_path *includes* (`…:/usr/local/bin:…:/snap/bin`). The ADR-012 drop-in `/etc/sudoers.d/agentlinux` (`20-sudoers.sh`) grants `agent ALL=(ALL) NOPASSWD: ALL` but **inherits the global `secure_path`**. `plugin/lib/as_user.sh` already documents that `secure_path` shadows the `-E`-preserved PATH ("Pitfall 1" in its header). Consequence on EL: a **bare** `sudo -u agent <tool>` (non-login) resolves commands only from the four secure_path dirs — so a tool the agent installed to `/usr/local/bin` (or `~/.local/bin`, `~/.npm-global/bin`) is invisible to non-login sudo. On Ubuntu the `/usr/local/bin` case happened to work; on EL it silently does not.

**Why it happens:**
secure_path is a `Defaults` line, global to all sudoers including drop-ins; the EL value is deliberately minimal. This is a real cross-distro behavior delta, not a config the installer set.

**How to avoid:**
Audit whether AgentLinux ever resolves a tool through **bare** sudo. The canonical AGT-02 path is safe: `tests/bats/51-agt02-release-gate.bats:46,59,69` and the `run_sudo_u*` helpers all use **login shells** (`bash --login` / `sudo -i`), which re-source `/etc/profile.d/agentlinux.sh` and **re-prepend** the agent paths *after* secure_path runs — so PATH ends with `~/.npm-global/bin` first regardless of secure_path. `detect/agents.sh` correctly uses `as_user_login` for the same reason (`as_user.sh:46-54`). The residual EL risk is any **future** bare-`as_user <tool-in-/usr/local/bin>`. If one is needed, do **not** widen the global secure_path; scope it to the agent: `Defaults:agent secure_path="/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"` in the drop-in (visudo-validated, byte-stable per BHV-07). Note `requiretty` is **not** a concern: EL7+ (incl. EL9) removed `Defaults requiretty` from the shipped sudoers (verified), so NOPASSWD works from cron/systemd/non-TTY ssh without a `!requiretty` override — but a defensive `Defaults:agent !requiretty` in the drop-in is cheap insurance for hosts upgraded from EL6.

**Warning signs:**
`sudo -u agent some-local-bin-tool` → "command not found" on EL but works on Ubuntu; `sudo -lU agent` shows the inherited narrow secure_path; an agent's `sudo <tool>` (agent escalating) can't find a `/usr/local/bin` helper.

**Phase to address:** P-PROV (`20-sudoers.sh`, only if a bare-sudo tool resolution is found) + P-CAT (recipes that shell out via sudo). **Detection/test idea:** a bats that asserts `sudo -lU agent` includes the agent npm/local bin in secure_path (only if the scoped override is added); keep the six-mode BHV tests as the real guard since they already exercise login-shell PATH.

---

### Pitfall 7: Package-name drift — EL package names differ from Debian for the exact deps the installer pulls, so `dnf install <debian-name>` 404s

**What goes wrong:**
Even after the `pkg_*` abstraction (Pitfall 4) routes to dnf, passing Debian package *names* fails: `dnf install` errors "No match for argument". The specific names the installer/harness/recipes need that drift:

| Need | Debian name (in code today) | EL9 name |
|------|------------------------------|----------|
| cron daemon | `cron` (Dockerfile.ubuntu-24.04:94) | **`cronie`** |
| `ps`/`pkill` (purge `pkill -u agent`, `agentlinux-install:403`) | `procps` | **`procps-ng`** |
| en_US locale (if ever needed beyond C.UTF-8) | `locales` | **`glibc-langpack-en`** |
| GnuPG (NodeSource key) | `gnupg` (`30-nodejs.sh:58`) | **`gnupg2`** |
| `useradd`/`userdel` | (in `passwd`/base) | **`shadow-utils`** |
| `command -v which` (some recipes) | `which` (present) | **`which`** (NOT in minimal images) |
| `tar`, `gzip`, `curl`, `ca-certificates` | present on Ubuntu base | often **absent** on `almalinux:9` / `-minimal` |
| `ss` (sshd-up poll, `20-agent-user.bats:40`) | `iproute2` | **`iproute`** |
| `openssh-server`, `jq` | same | same (no drift) |

Note `apt-transport-https` (`30-nodejs.sh:58`) has **no EL equivalent and is unneeded** (dnf does HTTPS natively) — dropping it on EL is correct, not a substitution.

**Why it happens:**
Debian and Fedora/EL package-naming lineages diverged decades ago; the `-ng` / `glibc-langpack-*` / `cronie` names are EL-isms with no warning until the install 404s.

**How to avoid:**
Maintain an EL name map alongside the `pkg_*` abstraction. Ensure the EL Docker base and the QEMU guest have `tar gzip curl ca-certificates which procps-ng cronie iproute` before the installer runs (or have the installer pull them). For the NodeSource GPG import, `gnupg2` (provides `gpg`) — though dnf's `gpgkey=` import doesn't actually need a standalone gpg binary.

**Warning signs:**
`dnf install cron` / `dnf install procps` / `dnf install gnupg` → "No match for argument"; `pkill: command not found` in `--purge`; `ss: command not found` makes the sshd-up poll loop time out (→ Pitfall 1 SSH tests look broken for the wrong reason); `which: command not found` in a recipe.

**Phase to address:** P-DETECT (name map) + P-PROV + P-HARNESS (base-image package list). **Detection/test idea:** CI lints the EL name map against `dnf provides`; the EL Docker image build failing loudly is itself the test.

---

### Pitfall 8: QEMU AlmaLinux cloud-image harness — `--ignore-missing --check` **vacuously passes** on the `-latest` filename, plus default-user / datasource divergence

**What goes wrong:**
`tests/qemu/boot.sh` + `tests/qemu/cloud-images.txt` encode Ubuntu assumptions. Porting them naively introduces a **silent checksum bypass**: AlmaLinux publishes `AlmaLinux-9-GenericCloud-latest.x86_64.qcow2` (a rolling pointer) but its `CHECKSUM` file lists only **versioned** names (`AlmaLinux-9-GenericCloud-9.8-20260526.x86_64.qcow2`, verified GNU `hash␠␠filename` format). `boot.sh:179` runs `sha256sum --ignore-missing --check CHECKSUM` against the downloaded `-latest` file — and because **no row matches `-latest`**, `--ignore-missing` checks *zero rows and exits 0*: the integrity gate (the harness's loudly-documented "Pitfall 10 — verify on EVERY cache hit") **passes without verifying anything**. That is worse than no check. Secondary divergences:
- **GNU format is compatible** (good — no BSD-style `SHA256 (f) = h` reparse needed, verified), so only the filename-match problem bites.
- **Default cloud-init user is `almalinux`** (verified), not `root` and not Ubuntu's `ubuntu`/`cloud-user`. `boot.sh` drives the guest as `root@localhost` via a `users: - name: root` + `disable_root: false` seed (`cloud-init/user-data:12-15`); EL cloud images default to `PermitRootLogin` that may reject root, expecting the `almalinux` sudo user. The in-guest install step (`boot.sh:386-394`) runs `bash plugin/bin/agentlinux-install` as root — on EL it likely needs to land as `almalinux` + `sudo`.
- **`-latest` defeats the cache-key trick**: the CI `actions/cache` keys on `hashFiles('cloud-images.txt')` so "rotating a URL invalidates the cache" — but a `-latest` URL never changes its text while the bytes rotate, so a stale cached image is served indefinitely.
- BIOS boot + `console=ttyS0` are fine on AlmaLinux GenericCloud (no UEFI/OVMF requirement, serial console present) — **not** a break, noted to scope out trivia.

**Why it happens:**
The Ubuntu manifest happens to list the exact server-cloudimg filename the harness downloads, so `--ignore-missing` matched a real row. AlmaLinux's `-latest`/versioned split breaks that coincidence, and `--ignore-missing` converts the mismatch into a false pass instead of a failure.

**How to avoid:**
Pin the **dated/versioned** AlmaLinux image filename in `cloud-images.txt` (e.g. `AlmaLinux-9-GenericCloud-9.8-20260526.x86_64.qcow2`) so the downloaded filename **matches a CHECKSUM row** — and add a guard that the `sha256sum --check` actually validated ≥1 file (fail if zero rows matched, killing the vacuous-pass class everywhere). Drive the guest over `almalinux@…` + `sudo` (or inject root via `runcmd: sed -i PermitRootLogin` / `write_files` to sshd_config) rather than assuming root SSH. Keep one AlmaLinux row per supported point release; bump it deliberately (which also re-keys the CI cache).

**Warning signs:**
QEMU run reports checksum "OK" in zero seconds with no filename echoed; `sha256sum -c` output is empty; root SSH to the AlmaLinux guest hangs/refuses while `almalinux@` works; CI serves a months-old image after upstream rotated `-latest`.

**Phase to address:** P-HARNESS (QEMU row + boot.sh EL branch) + P-REL (release gate must boot the EL row). **Detection/test idea:** assert the `sha256sum --check` line count of validated files ≥1; a deliberate-corruption test (flip a byte) must make `boot.sh` exit 1, proving the gate is live on EL.

---

### Pitfall 9: rpm-vs-dpkg detection logic — the brownfield decision layer assumes a dpkg world

**What goes wrong:**
Beyond `detect/nodejs.sh` (Pitfall 5) and `detect/user.sh` (Pitfall 4), the v0.3.4 brownfield layer's reuse/remediate decisions lean on Debian facts: `detect/README.md` lists allowed probes as `dpkg-query`, `apt list --installed`; the Node "distro_apt" classification (`detect/nodejs.sh:92-95`) has no EL counterpart for "Node came from AppStream module" (which is the *most likely* pre-existing EL Node source, see Pitfall 3). A brownfield AlmaLinux host that already has AppStream Node, or a NodeSource RPM, or a `dnf module`-installed stream, is mis-classified, so the Reuse/Create/Remediate/Bail decision is made on wrong inputs — the precise failure mode v0.3.4 exists to prevent, reintroduced on EL.

**Why it happens:**
The detection layer was authored against the only distro it had to support; "installed?" was synonymous with "dpkg knows about it."

**How to avoid:**
Port each probe through the `pkg_*` abstraction and add an EL Node source class: **AppStream-module Node** (`dnf module list --enabled nodejs` / `rpm -q nodejs` with a non-NodeSource release) distinct from **NodeSource RPM**. Mark it "remediate or bail" per the same compatibility-window logic the deb path uses. Keep the read-only invariant (`tests/bats/15-detection.bats` snapshots /etc /home /usr/local/bin /opt and asserts byte-equality before/after detection) — the EL probes must stay non-mutating (no `dnf` cache writes; `rpm -q` and `dnf module list` are read-only, but `dnf` can touch `/var/cache/dnf` — prefer `rpm`/file probes, or point dnf at `--cacheonly`).

**Warning signs:**
On a brownfield EL host, the pre-flight report shows Node "absent" or "distro_apt" when AppStream Node is installed; `15-detection.bats` read-only invariant fails because a `dnf` probe wrote to `/var/cache/dnf`.

**Phase to address:** P-BROWN. **Detection/test idea:** EL brownfield fixtures (AppStream `nodejs:18` installed; NodeSource RPM installed; nvm-managed Node) each produce the correct report classification; the read-only snapshot invariant stays green on EL.

---

### Pitfall 10: `distro_detect.sh` hard-rejects everything that isn't Ubuntu — the installer refuses to run on AlmaLinux 9 at all

**What goes wrong:**
`plugin/lib/distro_detect.sh:46-60` returns non-zero unless `ID == ubuntu` and `VERSION_ID ∈ {22.04, 24.04, 26.04}`; `agentlinux-install:435` calls `detect_distro` and lets the ERR trap abort. Until this is widened, **nothing else in v0.3.5 can be tested on a real AlmaLinux host** — the installer exits at the gate. (Already partially structured for this: the file exports `AGENTLINUX_DISTRO_VERSION` "for downstream provisioners that need to branch," so the intent exists.)

**Why it happens:**
Deliberate v0.3.0 fail-closed design ("refuses to run on anything other than Ubuntu").

**How to avoid:**
Extend `detect_distro` to accept `ID=almalinux` (and `ID_LIKE` containing `rhel`/`fedora` is *not* in scope — match `almalinux` exactly per the AlmaLinux-9-ONLY constraint) with `VERSION_ID` matching `9` / `9.*`. Export a normalized `AGENTLINUX_DISTRO_ID` (`ubuntu`|`almalinux`) and `AGENTLINUX_DISTRO_FAMILY` (`debian`|`el`) that the `pkg_*` abstraction and every provisioner branch consume — this is the single fork point. Keep the fail-closed posture for unsupported EL versions (reject Alma 10 / RHEL / Rocky explicitly per scope) so the error message stays honest.

**Warning signs:**
`unsupported distro: ID=almalinux` in the transcript and exit 1 before any provisioner runs.

**Phase to address:** P-DETECT (first thing built — everything else depends on it). **Detection/test idea:** a bats that runs the installer on the AlmaLinux Docker image and reaches `agentlinux-install complete`; a negative test that AlmaLinux 10 / Rocky is still refused.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `setenforce 0` / `SELINUX=disabled` to make SSH tests pass | Green bats in an afternoon | Ships a product that breaks on every enforcing EL host; violates CLAUDE.md "fix the environment, don't paper over it"; fails maintainer's first-person friction immediately | **Never** |
| One-off `if [[ $ID == almalinux ]]` branches inline at each apt site | Fast to write the first one | 7+ scattered forks drift; the 8th call gets missed and 404s in prod; impossible to test the dispatch in isolation | Never — build the `pkg_*` abstraction first (Pitfall 4) |
| Keep `--ignore-missing` on the AlmaLinux checksum without a "≥1 verified" guard | Reuses the Ubuntu code path verbatim | Silent integrity bypass (Pitfall 8) — a corrupt/tampered image boots and the release gate is blind | Never — add the validated-count assertion |
| Pin `AlmaLinux-9-GenericCloud-latest` in the manifest | No version bump churn | Rolling bytes + static URL → stale CI cache forever + checksum row never matches | Never — pin the dated filename |
| Write `/etc/default/locale` on EL purely to satisfy the BHV-01 grep | Keeps the existing assertion green with zero test edits | A Debianism leaks onto EL hosts; mild confusion; harmless file | Acceptable as a bridge — prefer also writing `/etc/locale.conf` and branching the assertion |
| Skip `dnf module reset nodejs` (rely on `module_hotfixes` only) | Greenfield works, less code | Brownfield host with AppStream `nodejs:NN` installed conflicts (Pitfall 3) | Acceptable for the greenfield acceptance path; revisit for brownfield EL support |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| NodeSource on EL9 | Assume `dnf install nodejs` "just works" like apt | `module_hotfixes=1` repo (NodeSource sets it) handles greenfield; gate idempotency on `/etc/yum.repos.d/nodesource-nodejs.repo`; GPG key auto-imported via `gpgkey=` |
| sshd + SELinux | Expect `cp`/`install` of `authorized_keys` to be readable by sshd | `restorecon -RF ~agent/.ssh` after writing; default `/home` location needs no `semanage` |
| AlmaLinux cloud image | SSH in as `root` like the Ubuntu harness | Default user is `almalinux` (sudo); drive install via `almalinux@ + sudo` or explicitly enable root SSH in the seed |
| dnf as a "detection" probe | Run `dnf` read-probes in the read-only detection pass | `dnf` writes `/var/cache/dnf` → breaks the `15-detection.bats` byte-equality invariant; prefer `rpm -q` / file existence, or `--cacheonly` |
| systemd `User=agent` (BHV-04) under SELinux | Assume it behaves like Ubuntu | Targeted policy leaves useradd-created users `unconfined_u` (execution of home binaries allowed) — likely fine, but verify with an AVC scan; don't assume, test |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| QEMU TCG fallback on the EL row | AlmaLinux boot 20-30x slower, CI timeout | Keep `boot.sh`'s `/dev/kvm` fail-fast (`boot.sh:132-142`) for the EL row too | Any CI runner without nested KVM |
| `dnf` metadata refresh per provisioner call | Each `dnf install` re-downloads repo metadata (slow vs apt's cached lists) | Refresh dnf cache once up-front; pass `-y` and avoid repeated `makecache` | EL `30-nodejs.sh` if every step re-runs `dnf makecache` |
| Re-downloading the `-latest` AlmaLinux image every run | Multi-hundred-MB pull each CI run | Pin dated filename so `actions/cache` hits and the checksum row matches | The moment `-latest` rotates |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Disabling SELinux to pass tests | Ships with MAC off; every confined-service protection lost on the user's host | `restorecon` the few mislabeled paths; keep enforcing |
| Vacuous checksum pass on `-latest` (Pitfall 8) | Tampered/corrupt cloud image boots in the release gate undetected | Pin dated filename + assert ≥1 file actually verified |
| Widening global `secure_path` to reach agent bins | Every sudoer (not just `agent`) gets agent-home dirs on PATH — privilege-escalation surface | Scope to `Defaults:agent secure_path=…` in the drop-in, visudo-validated |
| Trusting NodeSource RPM release string from agent-writable state | Detector reads attacker-controlled bytes | Mirror `detect/agents.sh`'s ownership gate (`stat -c %U` must equal install user) before trusting any discovered file |
| `dnf install` without GPG verification | MITM on Node binary | Keep `gpgcheck=1` + the NodeSource `gpgkey=` import; never `--nogpgcheck` |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Error "unsupported distro: ID=almalinux" with no hint during the port window | Maintainer can't tell if it's unimplemented vs broken | Until P-DETECT lands, a clear "AlmaLinux 9 support is in progress (v0.3.5)" message beats a bare reject |
| `apt-get: command not found` mid-install on EL | Looks like a host problem, not a missing port | Fail at the distro gate with a named reason, not deep inside provisioner 3 |
| Silent locale fallback to `C`/`POSIX` on minimal EL | perl/locale warnings spam every agent command | Write `/etc/locale.conf` + verify `C.UTF-8` present; the langpack is a no-op since C.UTF-8 is built in |

## "Looks Done But Isn't" Checklist

- [ ] **EL install completes:** Often missing — verify `agentlinux-install complete` is actually reached on AlmaLinux 9 (distro gate widened, every `apt`/`dpkg` routed through `pkg_*`).
- [ ] **BHV-02 SSH on enforcing SELinux:** Often missing `restorecon` — verify `run_ssh` passes with `getenforce=Enforcing` AND `ausearch -m avc -ts boot` shows no `sshd_t`/`agent` denial (green-with-permissive is a false pass).
- [ ] **Locale contract:** Often missing the file-path branch — verify the BHV-01 assertion is satisfied on EL (via `/etc/locale.conf` or a dual write), not just the `locale -a` check.
- [ ] **Node is v22 from NodeSource, not AppStream:** Often missing the module reset on brownfield — verify `rpm -q nodejs` shows a `nodesource` release and `node --version` is `v22.`.
- [ ] **Idempotent re-run + purge on EL:** Often missing the EL repo-file paths — verify second run short-circuits and `--purge` removes `/etc/yum.repos.d/nodesource-*.repo`.
- [ ] **QEMU checksum actually verifies:** Often a vacuous pass — verify the `sha256sum --check` matched ≥1 row (a flipped byte must fail the run).
- [ ] **Brownfield detection on EL:** Often dpkg-blind — verify AppStream-Node / NodeSource-RPM / nvm fixtures each classify correctly and the read-only snapshot invariant holds.
- [ ] **All six modes green on EL, not five:** SSH is the one that quietly fails (Pitfall 1) while interactive/sudo/cron/systemd pass — confirm `run_ssh` specifically.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| SELinux denied authorized_keys | LOW | `restorecon -RF /home/agent/.ssh` (no reinstall); add the call to harness `setup()` + provisioner guard |
| apt/dpkg hardcode 404 on EL | MEDIUM | Introduce `pkg_*` abstraction, route all sites, re-run; no host cleanup needed (install aborted early, idempotent) |
| AppStream Node won, RT-01 tripped | MEDIUM | `dnf module reset nodejs`, `dnf remove nodejs`, re-add NodeSource repo, `dnf install -y nodejs`, re-run installer |
| Vacuous QEMU checksum shipped a bad image | HIGH | Add validated-count guard, pin dated filename, purge image cache, re-run release gate; audit any release cut while the gate was blind |
| secure_path hides a `/usr/local/bin` tool | LOW | Add scoped `Defaults:agent secure_path=…` to the drop-in (visudo-validated), re-run `20-sudoers.sh` |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1. SELinux ssh context | P-HARNESS + P-PROV | `run_ssh` green under `getenforce=Enforcing` + zero `sshd_t` AVCs |
| 2. Locale tooling absent | P-PROV (+ spec) | `locale -a` has C.UTF-8; BHV-01 file assertion satisfied on EL |
| 3. dnf module collision | P-PROV (+ P-BROWN) | `rpm -q nodejs` shows nodesource + `node --version` = v22; brownfield `nodejs:18` fixture still lands v22 |
| 4. apt/dpkg hardcode | P-DETECT (consumed by P-PROV/P-BROWN) | EL install reaches "complete"; no stray `apt`/`dpkg` in transcript |
| 5. NodeSource rpm mechanism | P-PROV + P-BROWN | EL double-run idempotent; `--purge` removes `.repo`; NodeSource Node detected on brownfield EL |
| 6. secure_path narrower | P-PROV (if bare-sudo found) + P-CAT | six-mode BHV green; `sudo -lU agent` shows scoped path if override added |
| 7. package-name drift | P-DETECT + P-HARNESS | EL image build succeeds; `pkill`/`ss`/`cronie` present |
| 8. QEMU image checksum/user | P-HARNESS + P-REL | flipped-byte test fails the run; guest driven via `almalinux@`+sudo |
| 9. rpm-vs-dpkg detection | P-BROWN | EL brownfield fixtures classify correctly; read-only invariant holds |
| 10. distro gate rejects EL | P-DETECT | installer runs on AlmaLinux 9; Alma 10 / Rocky still refused |

## Sources

- C.UTF-8 built into RHEL 9 / glibc-minimal-langpack: [osbuild-composer #2206](https://github.com/osbuild/osbuild-composer/issues/2206), [Red Hat: Using langpacks (RHEL 8/9)](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/configuring_basic_system_settings/assembly_using-langpacks_configuring-basic-system-settings), [AlmaLinux 9 locale guide](https://linux.how2shout.com/how-to-install-and-configure-locale-on-almalinux-9/) — confidence HIGH.
- dnf module streams (no default stream in RHEL 9; reset before enable): [Red Hat: Managing versions of application stream content (RHEL 9)](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/managing_software_with_the_dnf_tool/assembly_managing-versions-of-application-stream-content_managing-software-with-the-dnf-tool), [Install Node.js 22 on Rocky/AlmaLinux](https://computingforgeeks.com/install-nodejs-rhel-rocky-almalinux/) — confidence HIGH.
- NodeSource EL `setup_22.x` sets `module_hotfixes=1`, imports GPG key, creates `/etc/yum.repos.d/nodesource-nodejs.repo`, does NOT reset the AppStream module: [nodesource/distributions scripts/rpm/setup_22.x](https://github.com/nodesource/distributions/blob/master/scripts/rpm/setup_22.x) (fetched + read verbatim) — confidence HIGH.
- SELinux + sshd authorized_keys context (`ssh_home_t`, restorecon for default /home, semanage only for relocated homes): [blog.tinned-software.net SSH-key + SELinux](https://blog.tinned-software.net/ssh-key-authentication-is-not-working-selinux/), [Red Hat solution 3948421](https://access.redhat.com/solutions/3948421), [ansible/ansible #2907](https://github.com/ansible/ansible/issues/2907) — confidence HIGH.
- AlmaLinux 9 GenericCloud default user `almalinux`, image + CHECKSUM URLs, GNU checksum format: [AlmaLinux Generic Cloud wiki](https://wiki.almalinux.org/cloud/Generic-cloud.html), [AlmaLinux Generic Cloud on local](https://wiki.almalinux.org/cloud/Generic-cloud-on-local.html), CHECKSUM file fetched verbatim (`hash␠␠filename`, versioned names, no GPG wrapper) — confidence HIGH.
- EL9 default sudoers `secure_path = /sbin:/bin:/usr/sbin:/usr/bin` (no /usr/local/bin); `requiretty` removed since EL7: [Red Hat solution 1298644](https://access.redhat.com/solutions/1298644), [sudo.ws secure_path default](https://www.sudo.ws/posts/2024/09/why-sudo-1.9.16-enables-secure_path-by-default/), [requiretty removed RHEL7+](https://support.icewarp.co.in/hc/en-us/articles/20849614452121--Defaults-requiretty-option-removed-from-etc-sudoers-file) — confidence HIGH.
- Code break sites (read directly this session): `plugin/lib/distro_detect.sh`, `plugin/bin/agentlinux-install`, `plugin/provisioner/{10,20,30,40,50}-*.sh`, `plugin/lib/{as_user,idempotency,detect}.sh`, `plugin/lib/detect/{nodejs,user,agents}.sh`, `plugin/catalog/agents/{claude-code,playwright-cli}/install.sh`, `tests/qemu/{boot.sh,cloud-images.txt,cloud-init/user-data}`, `tests/docker/Dockerfile.ubuntu-24.04`, `tests/bats/20-agent-user.bats`, `tests/bats/51-agt02-release-gate.bats`, `tests/bats/helpers/invoke_modes.bash` — confidence HIGH (primary source).

---
*Pitfalls research for: AlmaLinux 9 (EL9) port of the AgentLinux installer — v0.3.5 / AL-47*
*Researched: 2026-06-27*
