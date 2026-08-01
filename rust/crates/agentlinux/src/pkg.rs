//! pkg.rs — package-manager-neutral verbs (apt↔dnf) keyed on `Family` (PROV-03).
//!
//! The ONE auditable place the
//! apt↔dnf branch lives. Every hardcoded apt-get / dpkg / locale-gen /
//! NodeSource site collapses to a single verb here, each branching EXACTLY ONCE
//! on `Family` via a `match` (never an inline `if family` scattered across call
//! sites — 18-RESEARCH Anti-Pattern 2 / this plan's Pattern 2).
//!
//! The debian arm is the current Ubuntu command lifted byte-for-byte; the rhel
//! arm is the EL9 equivalent (dnf/rpm/locale.conf) — the proven v0.3.5 AlmaLinux
//! port, mechanically translated.
//!
//! Testability: every shell-out verb factors its ARGV into a pure `*_argv`
//! builder the unit tests assert WITHOUT running live apt/dnf; the live spawn
//! wraps the builder. `nodesource_repo_paths` + the argv builders are pure and
//! fully unit-tested (the shared source of truth with the idempotency gate and the
//! purge). `nodesource_prereqs` rhel installs ONLY ca-certificates (NEVER curl —
//! curl-minimal conflicts and gnupg/apt-transport-https do not exist
//! on EL9). `nodesource_module_reset` rhel resets the AppStream nodejs module
//!  so it cannot win over the NodeSource repo.

use crate::distro::Family;
use crate::sysio;
use std::io;
use std::io::Read;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::Duration;

/// Wall-clock bound on one package-manager invocation, overridable via
/// `AGENTLINUX_PKG_TIMEOUT_MS` (`0` disables it).
///
/// 20 minutes clears the slowest legitimate case — a cold `apt-get update` plus a
/// Node install over a slow mirror — while bounding the one that motivated it:
/// `dnf` against a mirror that completes the TCP handshake and then stalls has no
/// internal timeout of its own and will sit in "waiting for metadata"
/// indefinitely.
const DEFAULT_PKG_TIMEOUT_MS: u64 = 20 * 60 * 1000;

/// Env override for `DEFAULT_PKG_TIMEOUT_MS`.
const PKG_TIMEOUT_ENV: &str = "AGENTLINUX_PKG_TIMEOUT_MS";

/// How much of a failing child's stderr is kept for the error message.
const STDERR_TAIL: usize = 4096;

/// How long to wait for the stderr reader after the child has been reaped, before
/// giving up on its output. Mirrors `dispatcher::READER_DRAIN_GRACE` and exists
/// for the same reason — a leaked background process holding the pipe open.
const STDERR_DRAIN_GRACE: Duration = Duration::from_secs(5);

/// How long apt waits for the dpkg lock instead of failing outright.
///
/// A fresh cloud image runs `apt-daily`/`unattended-upgrades` from cloud-init, so
/// an install racing first boot finds `/var/lib/dpkg/lock-frontend` held. Without
/// this, apt exits 100 immediately and the provision aborts half-done; with it,
/// apt blocks until the background job finishes — which is what an operator would
/// do by hand.
const DPKG_LOCK_TIMEOUT: [&str; 2] = ["-o", "DPkg::Lock::Timeout=300"];

/// Build an `apt-get` argv with the dpkg-lock wait applied.
///
/// Every debian-arm command goes through here so the wait cannot be forgotten at
/// one call site — the failure it prevents (racing cloud-init's unattended
/// upgrade on first boot) shows up on whichever command happens to run first.
fn apt_get<'a>(args: &[&'a str]) -> Vec<&'a str> {
    std::iter::once("apt-get")
        .chain(DPKG_LOCK_TIMEOUT)
        .chain(args.iter().copied())
        .collect()
}

/// A command to run: `env` pairs prepended (the Bash `VAR=val cmd …` form) plus
/// the argv. Returned by every `*_argv` builder so a unit test asserts the exact
/// command the verb would spawn.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PkgCmd {
    /// Environment pairs set for JUST this command (e.g.
    /// `DEBIAN_FRONTEND=noninteractive`), mirroring the Bash inline `VAR=val`.
    pub env: Vec<(String, String)>,
    /// The argv, program first.
    pub argv: Vec<String>,
}

/// One finished package-manager run: the exit code plus whatever the child said
/// on stderr, which is where apt and dnf explain themselves.
struct PkgOutcome {
    exit_code: i32,
    /// Set when the run hit `bound_ms` rather than exiting on its own.
    timed_out: bool,
    /// The bound this run actually carried, so the failure message reports the
    /// number that applied instead of re-reading the environment later.
    bound_ms: Option<u64>,
    stderr: String,
}

impl PkgOutcome {
    const fn success(&self) -> bool {
        self.exit_code == 0 && !self.timed_out
    }

    /// The operator-facing reason this run failed, stderr included.
    ///
    /// The argv is rendered shell-shaped, not `{:?}`. The operator's next move is
    /// to run the command by hand; `["apt-get", "-o", "DPkg::Lock::Timeout=300",
    /// "update"]` makes them un-Rust it first.
    fn failure_reason(&self, argv: &[String]) -> String {
        let cmd = argv.join(" ");
        let what = match (self.timed_out, self.bound_ms) {
            (true, Some(ms)) => format!(
                "timed out after {ms}ms — raise or disable the bound with \
                 {PKG_TIMEOUT_ENV} if this is legitimately slow"
            ),
            (true, None) => "timed out".to_string(),
            (false, _) => format!("exited {}", self.exit_code),
        };
        let tail = self.stderr.trim();
        if tail.is_empty() {
            format!("`{cmd}` {what}; it printed nothing on stderr")
        } else {
            format!("`{cmd}` {what}: {tail}")
        }
    }
}

/// The bound one package-manager invocation gets. An unparseable override falls
/// back to the default rather than aborting the provision.
fn pkg_timeout_ms() -> Option<u64> {
    let configured = match std::env::var(PKG_TIMEOUT_ENV) {
        Err(_) => DEFAULT_PKG_TIMEOUT_MS,
        Ok(raw) => raw.trim().parse::<u64>().unwrap_or_else(|_| {
            crate::plog!(
                "agentlinux: ignoring unparseable {PKG_TIMEOUT_ENV}={raw:?}; \
                 using {DEFAULT_PKG_TIMEOUT_MS}ms"
            );
            DEFAULT_PKG_TIMEOUT_MS
        }),
    };
    (configured > 0).then_some(configured)
}

impl PkgCmd {
    fn new(env: &[(&str, &str)], argv: &[&str]) -> Self {
        Self {
            env: env
                .iter()
                .map(|(k, v)| (k.to_string(), v.to_string()))
                .collect(),
            argv: argv.iter().map(|s| s.to_string()).collect(),
        }
    }

    /// Spawn this command once and wait for it, bounded by `pkg_timeout_ms`.
    ///
    /// stdout stays inherited so the operator watches apt/dnf work in real time.
    /// stderr is teed AND kept (bounded to `STDERR_TAIL`) so a failure can quote
    /// the package manager's own explanation instead of just the argv. stdin is
    /// `/dev/null`: under `curl … | sudo bash` the installer's stdin is the
    /// SCRIPT, and an apt prompt that reads it consumes the rest of the installer.
    fn run(&self) -> io::Result<PkgOutcome> {
        // Every `PkgCmd` in this module is built from a literal argv, so this is
        // unreachable today — but indexing `[0]` on an empty argv would PANIC,
        // and a panic inside a privileged provisioner is the one failure mode
        // with no diagnostic at all. A clean error costs one line.
        let (program, args) = self.argv.split_first().ok_or_else(|| {
            io::Error::new(io::ErrorKind::InvalidInput, "pkg command has an empty argv")
        })?;
        let mut cmd = Command::new(program);
        cmd.args(args).stdin(Stdio::null()).stderr(Stdio::piped());
        for (k, v) in &self.env {
            cmd.env(k, v);
        }
        crate::dispatcher::own_process_group(&mut cmd);

        let mut child = cmd.spawn()?;
        let label = self.argv.join(" ");
        // Drain stderr on a thread: a package manager that fills the pipe buffer
        // while we sit in wait() would deadlock against us.
        let stderr_pipe = child.stderr.take();
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let _ = tx.send(tee_and_keep_tail(stderr_pipe));
        });
        let bound = pkg_timeout_ms();
        let (exit_code, timed_out) =
            crate::dispatcher::wait_with_timeout(&mut child, bound, &label);
        // BOUNDED, for the same reason `dispatcher::collect` is: the pipe closes
        // only when every holder closes it, and an apt/dnf postinst that starts a
        // daemon leaves that daemon holding our stderr. On the timeout path the
        // process-group kill closes it; on the exit-0-with-a-leaked-daemon path
        // nothing does, and a plain `join()` would wait for the daemon's lifetime.
        // Losing the stderr tail is a worse error message; blocking here is a
        // hung install.
        let stderr = rx.recv_timeout(STDERR_DRAIN_GRACE).unwrap_or_else(|_| {
            crate::plog!(
                "agentlinux: `{label}` finished but its stderr pipe is still held by \
                 a background process after {}s; its output is not included below",
                STDERR_DRAIN_GRACE.as_secs()
            );
            String::new()
        });
        Ok(PkgOutcome {
            exit_code,
            timed_out,
            bound_ms: bound,
            stderr,
        })
    }
}

/// Read a child's stderr to EOF, forwarding every byte to our own stderr and
/// keeping the last `STDERR_TAIL` bytes for the error message.
///
/// The TAIL rather than the head: apt and dnf print progress first and the actual
/// diagnosis last, so a head-bounded capture would keep the least useful half.
fn tee_and_keep_tail(pipe: Option<std::process::ChildStderr>) -> String {
    use std::io::Write;
    let Some(mut pipe) = pipe else {
        return String::new();
    };
    let mut kept: Vec<u8> = Vec::new();
    let mut buf = [0u8; 8192];
    loop {
        match pipe.read(&mut buf) {
            Ok(0) | Err(_) => break,
            Ok(n) => {
                let _ = std::io::stderr().write_all(&buf[..n]);
                let _ = std::io::stderr().flush();
                kept.extend_from_slice(&buf[..n]);
                if kept.len() > STDERR_TAIL {
                    // Drop from the front, keeping the most recent bytes.
                    kept.drain(..kept.len() - STDERR_TAIL);
                }
            }
        }
    }
    String::from_utf8_lossy(&kept).into_owned()
}

const DEB_FRONTEND: (&str, &str) = ("DEBIAN_FRONTEND", "noninteractive");

// ---------------------------------------------------------------------------
// pkg_install / pkg_is_installed / pkg_remove / pkg_autoremove
// ---------------------------------------------------------------------------

/// The command(s) `pkg_install` runs for `family`. Debian runs `apt-get update`
/// THEN the install; rhel is a single dnf install. `--no-install-recommends` /
/// `--setopt=install_weak_deps=False` are the parity pair.
pub fn install_cmds(family: Family, pkgs: &[&str]) -> Vec<PkgCmd> {
    match family {
        Family::Debian => {
            let mut install = vec!["install", "-y", "--no-install-recommends"];
            install.extend_from_slice(pkgs);
            vec![
                PkgCmd::new(&[DEB_FRONTEND], &apt_get(&["update"])),
                PkgCmd::new(&[DEB_FRONTEND], &apt_get(&install)),
            ]
        }
        Family::Rhel => {
            let mut install = vec!["dnf", "install", "-y", "--setopt=install_weak_deps=False"];
            install.extend_from_slice(pkgs);
            vec![PkgCmd::new(&[], &install)]
        }
    }
}

/// `pkg_install <pkg...>` — install one or more packages.
pub fn pkg_install(family: Family, pkgs: &[&str]) -> io::Result<()> {
    require_all_success(&install_cmds(family, pkgs))
}

/// The command `pkg_remove` runs (debian apt-get purge, rhel dnf remove).
pub fn remove_cmd(family: Family, pkgs: &[&str]) -> PkgCmd {
    match family {
        Family::Debian => {
            let mut argv = vec!["purge", "-y"];
            argv.extend_from_slice(pkgs);
            PkgCmd::new(&[DEB_FRONTEND], &apt_get(&argv))
        }
        Family::Rhel => {
            let mut argv = vec!["dnf", "remove", "-y"];
            argv.extend_from_slice(pkgs);
            PkgCmd::new(&[], &argv)
        }
    }
}

/// `pkg_remove <pkg...>` — remove packages (purge config on debian).
pub fn pkg_remove(family: Family, pkgs: &[&str]) -> io::Result<()> {
    require_success(&remove_cmd(family, pkgs))
}

/// The command `pkg_autoremove` runs.
pub fn autoremove_cmd(family: Family) -> PkgCmd {
    match family {
        Family::Debian => PkgCmd::new(&[DEB_FRONTEND], &apt_get(&["autoremove", "-y"])),
        Family::Rhel => PkgCmd::new(&[], &["dnf", "autoremove", "-y"]),
    }
}

/// `pkg_autoremove` — drop orphaned dependencies.
pub fn pkg_autoremove(family: Family) -> io::Result<()> {
    require_success(&autoremove_cmd(family))
}

// ---------------------------------------------------------------------------
// NodeSource verbs
// ---------------------------------------------------------------------------

/// The command(s) `nodesource_prereqs` runs. Debian: apt-get update THEN install
/// {curl, gnupg, ca-certificates, apt-transport-https}. Rhel: install ONLY
/// {ca-certificates} — NEVER curl.
pub fn nodesource_prereqs_cmds(family: Family) -> Vec<PkgCmd> {
    match family {
        Family::Debian => vec![
            PkgCmd::new(&[DEB_FRONTEND], &apt_get(&["update"])),
            PkgCmd::new(
                &[DEB_FRONTEND],
                &apt_get(&[
                    "install",
                    "-y",
                    "--no-install-recommends",
                    "curl",
                    "gnupg",
                    "ca-certificates",
                    "apt-transport-https",
                ]),
            ),
        ],
        Family::Rhel => vec![PkgCmd::new(
            &[],
            &[
                "dnf",
                "install",
                "-y",
                "--setopt=install_weak_deps=False",
                "ca-certificates",
            ],
        )],
    }
}

/// `nodesource_prereqs` — install the prerequisites setup_22.x expects.
pub fn nodesource_prereqs(family: Family) -> io::Result<()> {
    require_all_success(&nodesource_prereqs_cmds(family))
}

/// The NodeSource setup URL for `family` (deb vs rpm). The live verb pipes
/// `curl -fsSL <url> | bash -`; the URL is the family-specific, testable part.
pub fn nodesource_setup_url(family: Family) -> &'static str {
    match family {
        Family::Debian => "https://deb.nodesource.com/setup_22.x",
        Family::Rhel => "https://rpm.nodesource.com/setup_22.x",
    }
}

/// The pipe body `nodesource_setup` runs (under `bash -o pipefail -c`): the
/// NodeSource `curl … | bash -` pipe with `--connect-timeout`/`--max-time` bounds.
/// Split out so a unit test can assert its shape without a live network. The `url`
/// is always a compile-time `&'static str` from `nodesource_setup_url` (never
/// untrusted input), so interpolating it into the shell string is injection-safe —
/// that constraint is load-bearing. HTTPS + `curl -fsSL` cert verification is the
/// fetch-integrity control (ADR-005).
fn nodesource_setup_script(url: &str) -> String {
    // `--connect-timeout 30 --max-time 300`: a DNS/TLS stall or a slow hang can't
    // wedge provisioning forever. `--retry 3 --retry-connrefused` absorbs the
    // transient half of that — a DNS blip or a mirror 503 that one retry fixes,
    // which previously killed the whole provision. Success behavior is unchanged.
    format!(
        "curl -fsSL --connect-timeout 30 --max-time 300 --retry 3 --retry-delay 5 \
         --retry-connrefused {url} | bash -"
    )
}

/// `nodesource_setup` — run the pinned NodeSource setup_22.x script
/// (`curl -fsSL <url> | bash -`). The pipe runs under `bash -o pipefail -c` so a
/// curl 404/DNS/TLS failure propagates through the pipe as a non-zero status
/// (HIGH-1: a plain `bash -c` lacks pipefail and would exit 0 on a failed fetch,
/// matching the Bash verb's `set -euo pipefail`). The URL comes from
/// `nodesource_setup_url`; HTTPS + `curl -fsSL` cert verification is the
/// fetch-integrity control (ADR-005).
pub fn nodesource_setup(family: Family) -> io::Result<()> {
    let url = nodesource_setup_url(family);
    let script = nodesource_setup_script(url);
    // Through `PkgCmd` so the setup script inherits the same bound, stdin-null
    // and stderr capture as every other package operation. curl's `--max-time`
    // covers only the FETCH; the `| bash -` leg runs `apt-get update`/`dnf
    // makecache` internally, so the smaller half was the only bounded one.
    let cmd = PkgCmd::new(&[], &["bash", "-o", "pipefail", "-c", &script]);
    let outcome = cmd.run()?;
    if !outcome.success() {
        return Err(io::Error::other(format!(
            "nodesource_setup: setup script failed — {}",
            outcome.failure_reason(&cmd.argv)
        )));
    }
    Ok(())
}

/// `nodesource_repo_paths` — the family's NodeSource repo file paths. The single
/// source of truth shared by the idempotency gate and the purge,
/// byte-identical to `pkg.sh:144-160`.
pub fn nodesource_repo_paths(family: Family) -> Vec<PathBuf> {
    match family {
        Family::Debian => vec![
            PathBuf::from("/etc/apt/sources.list.d/nodesource.sources"),
            PathBuf::from("/etc/apt/sources.list.d/nodesource.list"),
            PathBuf::from("/etc/apt/preferences.d/nodejs"),
        ],
        Family::Rhel => vec![
            PathBuf::from("/etc/yum.repos.d/nodesource-nodejs.repo"),
            PathBuf::from("/etc/yum.repos.d/nodesource-nsolid.repo"),
        ],
    }
}

/// The command `nodesource_module_reset` runs, or `None` for a no-op (debian).
/// Rhel resets the AppStream nodejs module; non-fatal (`|| true`).
pub fn nodesource_module_reset_cmd(family: Family) -> Option<PkgCmd> {
    match family {
        Family::Rhel => Some(PkgCmd::new(
            &[],
            &["dnf", "-y", "module", "reset", "nodejs"],
        )),
        Family::Debian => None,
    }
}

/// `nodesource_module_reset` — defuse the AppStream `nodejs` module (rhel-only,
/// non-fatal); a no-op on debian.
pub fn nodesource_module_reset(family: Family) -> io::Result<()> {
    if let Some(cmd) = nodesource_module_reset_cmd(family) {
        // Non-fatal (Bash `|| true`) — a host with no `nodejs` module to reset is
        // the normal case. Reported, not swallowed: if the Node install later
        // loses to AppStream, this line says why.
        let outcome = cmd.run()?;
        if !outcome.success() {
            crate::plog!(
                "agentlinux: {} (non-fatal; no AppStream nodejs module to reset)",
                outcome.failure_reason(&cmd.argv)
            );
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// locale_ensure
// ---------------------------------------------------------------------------

/// The C.UTF-8 availability gate both arms end with: `locale -a | grep -Eiq
/// '^c\.utf-?8$'`. Modeled as a shell command so the `grep -Ei` regex matches
/// both `C.UTF-8` and the `C.utf8` form 24.04 reports.
fn locale_available_cmd() -> PkgCmd {
    PkgCmd::new(
        &[],
        &[
            "bash",
            "-c",
            "locale -a 2>/dev/null | grep -Eiq '^c\\.utf-?8$'",
        ],
    )
}

/// `locale_ensure <locale>` — enforce `loc` as the system LANG/LC_ALL then
/// verify it via the portable `locale -a` gate (BHV-01). C.UTF-8-ONLY contract:
/// any other locale is refused (fail closed).
///
/// Debian: the byte-for-byte Ubuntu path (locale-gen + update-locale, writing
/// `/etc/default/locale`). Rhel: write `/etc/locale.conf` via
/// `sysio::write_file_atomic` (NEVER cat>/tee; no locale-gen on EL9).
pub fn locale_ensure(family: Family, loc: &str) -> io::Result<()> {
    if loc != "C.UTF-8" {
        return Err(io::Error::other(format!(
            "locale_ensure supports only C.UTF-8 (got: {loc})"
        )));
    }
    match family {
        Family::Debian => {
            // Install `locales` if locale-gen is absent (best-effort), then
            // locale-gen + update-locale, then the availability gate.
            if sysio::which("locale-gen").is_none() {
                require_all_success(&install_cmds(Family::Debian, &["locales"]))?;
            }
            // locale-gen C.UTF-8 stays non-fatal (the Bash verb's `|| true`) —
            // on 24.04 C.UTF-8 is built in and locale-gen has nothing to do. But
            // a failure is no longer DISCARDED: if the gate below then fails,
            // this line is the only thing that says why.
            let locale_gen = PkgCmd::new(&[], &["locale-gen", "C.UTF-8"]).run()?;
            if !locale_gen.success() {
                crate::plog!(
                    "agentlinux: locale-gen C.UTF-8 {} (non-fatal; \
                     the `locale -a` gate below is authoritative)",
                    locale_gen.failure_reason(&["locale-gen".into(), "C.UTF-8".into()])
                );
            }
            require_success(&PkgCmd::new(
                &[],
                &["update-locale", "LANG=C.UTF-8", "LC_ALL=C.UTF-8"],
            ))?;
            require_locale_available()
        }
        Family::Rhel => {
            let body = format!("LANG={loc}\nLC_ALL={loc}\n");
            sysio::write_file_atomic(
                0o644,
                std::path::Path::new("/etc/locale.conf"),
                body.as_bytes(),
            )?;
            require_locale_available()
        }
    }
}

/// Run the `locale -a` availability gate, mapping a miss to an `Err`.
///
/// A read-only probe of state the caller just finished writing — a miss is a real
/// answer, not a transient one.
fn require_locale_available() -> io::Result<()> {
    if !locale_available_cmd().run()?.success() {
        return Err(io::Error::other(
            "locale_ensure: C.UTF-8 locale not available after enforcement \
             (checked with `locale -a`)",
        ));
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/// Run every command in sequence, failing fast on the first non-zero exit
/// (matches the Bash `set -e` sequencing of the multi-command verbs).
fn require_all_success(cmds: &[PkgCmd]) -> io::Result<()> {
    for c in cmds {
        require_success(c)?;
    }
    Ok(())
}

/// Run one command, mapping a non-zero exit to an `Err` (the `set -e` default
/// for a verb whose failure IS fatal — the individual `|| true` sites handle
/// their own non-fatality inline). The error quotes the child's stderr.
fn require_success(cmd: &PkgCmd) -> io::Result<()> {
    let outcome = cmd.run()?;
    if !outcome.success() {
        return Err(io::Error::other(outcome.failure_reason(&cmd.argv)));
    }
    Ok(())
}

#[cfg(test)]
mod pkg_tests {
    use super::*;

    /// Every debian argv carries the dpkg-lock wait — asserted once here and
    /// reused by each apt case so the option cannot be dropped from one site.
    fn assert_waits_for_dpkg_lock(argv: &[String]) {
        let pos = argv
            .iter()
            .position(|a| a == "-o")
            .unwrap_or_else(|| panic!("no -o option in {argv:?}"));
        assert_eq!(
            argv[pos + 1],
            "DPkg::Lock::Timeout=300",
            "apt must wait for the dpkg lock, not fail on it: {argv:?}"
        );
    }

    #[test]
    fn install_cmds_debian_updates_then_installs_noninteractive() {
        let cmds = install_cmds(Family::Debian, &["nodejs"]);
        assert_eq!(cmds.len(), 2);
        assert_eq!(
            cmds[0].argv,
            vec!["apt-get", "-o", "DPkg::Lock::Timeout=300", "update"]
        );
        assert_eq!(
            cmds[0].env,
            vec![("DEBIAN_FRONTEND".to_string(), "noninteractive".to_string())]
        );
        assert_eq!(
            cmds[1].argv,
            vec![
                "apt-get",
                "-o",
                "DPkg::Lock::Timeout=300",
                "install",
                "-y",
                "--no-install-recommends",
                "nodejs"
            ]
        );
        assert_eq!(
            cmds[1].env,
            vec![("DEBIAN_FRONTEND".to_string(), "noninteractive".to_string())]
        );
    }

    // The lock wait is on EVERY debian command, not just install. Whichever one
    // happens to run first is the one that races cloud-init's unattended upgrade.
    #[test]
    fn every_debian_command_waits_for_the_dpkg_lock() {
        for cmd in install_cmds(Family::Debian, &["nodejs"]) {
            assert_waits_for_dpkg_lock(&cmd.argv);
        }
        for cmd in nodesource_prereqs_cmds(Family::Debian) {
            assert_waits_for_dpkg_lock(&cmd.argv);
        }
        assert_waits_for_dpkg_lock(&remove_cmd(Family::Debian, &["nodejs"]).argv);
        assert_waits_for_dpkg_lock(&autoremove_cmd(Family::Debian).argv);
    }

    // …and NOT on the rhel arm, where the option does not exist and would make
    // dnf reject the command outright.
    #[test]
    fn rhel_commands_carry_no_apt_options() {
        for cmd in install_cmds(Family::Rhel, &["nodejs"]) {
            assert!(
                !cmd.argv.iter().any(|a| a.starts_with("DPkg::")),
                "apt option leaked into a dnf argv: {:?}",
                cmd.argv
            );
        }
    }

    #[test]
    fn install_cmds_rhel_single_dnf_weak_deps_false() {
        let cmds = install_cmds(Family::Rhel, &["nodejs"]);
        assert_eq!(cmds.len(), 1);
        assert_eq!(
            cmds[0].argv,
            vec![
                "dnf",
                "install",
                "-y",
                "--setopt=install_weak_deps=False",
                "nodejs"
            ]
        );
        assert!(cmds[0].env.is_empty());
    }

    #[test]
    fn remove_cmd_per_family() {
        assert_eq!(
            remove_cmd(Family::Debian, &["nodejs"]).argv,
            vec![
                "apt-get",
                "-o",
                "DPkg::Lock::Timeout=300",
                "purge",
                "-y",
                "nodejs"
            ]
        );
        assert_eq!(
            remove_cmd(Family::Rhel, &["nodejs"]).argv,
            vec!["dnf", "remove", "-y", "nodejs"]
        );
    }

    #[test]
    fn autoremove_cmd_per_family() {
        assert_eq!(
            autoremove_cmd(Family::Debian).argv,
            vec![
                "apt-get",
                "-o",
                "DPkg::Lock::Timeout=300",
                "autoremove",
                "-y"
            ]
        );
        assert_eq!(
            autoremove_cmd(Family::Rhel).argv,
            vec!["dnf", "autoremove", "-y"]
        );
    }

    #[test]
    fn nodesource_prereqs_rhel_only_ca_certificates_never_curl() {
        let cmds = nodesource_prereqs_cmds(Family::Rhel);
        assert_eq!(cmds.len(), 1);
        // ONLY ca-certificates — and crucially NEVER curl.
        assert!(cmds[0].argv.contains(&"ca-certificates".to_string()));
        assert!(
            !cmds[0].argv.iter().any(|a| a == "curl"),
            "rhel prereqs must NEVER install curl (curl-minimal conflicts): {:?}",
            cmds[0].argv
        );
        assert!(!cmds[0].argv.iter().any(|a| a == "gnupg"));
        assert!(!cmds[0].argv.iter().any(|a| a == "apt-transport-https"));
    }

    #[test]
    fn nodesource_prereqs_debian_installs_the_four_apt_prereqs() {
        let cmds = nodesource_prereqs_cmds(Family::Debian);
        assert_eq!(cmds.len(), 2);
        assert_eq!(
            cmds[0].argv,
            vec!["apt-get", "-o", "DPkg::Lock::Timeout=300", "update"]
        );
        for pkg in ["curl", "gnupg", "ca-certificates", "apt-transport-https"] {
            assert!(
                cmds[1].argv.iter().any(|a| a == pkg),
                "debian prereqs missing {pkg}"
            );
        }
    }

    #[test]
    fn nodesource_setup_url_per_family() {
        assert_eq!(
            nodesource_setup_url(Family::Debian),
            "https://deb.nodesource.com/setup_22.x"
        );
        assert_eq!(
            nodesource_setup_url(Family::Rhel),
            "https://rpm.nodesource.com/setup_22.x"
        );
    }

    #[test]
    fn nodesource_setup_script_carries_curl_timeouts_and_retries() {
        // The curl leg is bounded so a network stall can't hang forever, AND
        // retried so a DNS blip doesn't abort a whole provision.
        let s = nodesource_setup_script("https://example.test/setup_22.x");
        assert!(s.contains("--connect-timeout 30"), "script: {s}");
        assert!(s.contains("--max-time 300"), "script: {s}");
        assert!(s.contains("--retry 3"), "script: {s}");
        assert!(s.contains("--retry-connrefused"), "script: {s}");
        assert!(s.contains("| bash -"), "script: {s}");
    }

    // The package bound is on by default, overridable, and disengaged by an
    // explicit 0 — the same contract as the recipe bound.
    #[test]
    fn pkg_timeout_reads_env_with_a_safe_default() {
        let _g = crate::test_support::env_guard();
        std::env::remove_var(PKG_TIMEOUT_ENV);
        assert_eq!(pkg_timeout_ms(), Some(DEFAULT_PKG_TIMEOUT_MS));

        std::env::set_var(PKG_TIMEOUT_ENV, "1000");
        assert_eq!(pkg_timeout_ms(), Some(1000));

        std::env::set_var(PKG_TIMEOUT_ENV, "0");
        assert_eq!(pkg_timeout_ms(), None);

        std::env::set_var(PKG_TIMEOUT_ENV, "twenty minutes");
        assert_eq!(pkg_timeout_ms(), Some(DEFAULT_PKG_TIMEOUT_MS));

        std::env::remove_var(PKG_TIMEOUT_ENV);
    }

    // A failing command's stderr reaches the error message. Previously the error
    // carried only the argv, so `apt-get update` failing on an expired mirror key
    // read as "pkg verb failed" with the explanation discarded.
    #[test]
    fn failure_reason_quotes_the_childs_stderr() {
        let cmd = PkgCmd::new(
            &[],
            &[
                "bash",
                "-c",
                "echo 'E: mirror is unreachable' >&2; exit 100",
            ],
        );
        let outcome = cmd.run().unwrap();
        assert!(!outcome.success());
        assert_eq!(outcome.exit_code, 100);
        let reason = outcome.failure_reason(&cmd.argv);
        assert!(
            reason.contains("mirror is unreachable"),
            "stderr must reach the operator: {reason}"
        );
        assert!(reason.contains("exited 100"), "reason: {reason}");
    }

    // Only the LAST STDERR_TAIL bytes are kept: apt prints progress first and the
    // diagnosis last, so a head-bounded capture would keep the wrong half.
    #[test]
    fn stderr_capture_keeps_the_tail_not_the_head() {
        let script = format!(
            "head -c {} /dev/zero | tr '\\0' 'a' >&2; echo 'THE-REAL-ERROR' >&2; exit 1",
            STDERR_TAIL * 2
        );
        let cmd = PkgCmd::new(&[], &["bash", "-c", &script]);
        let outcome = cmd.run().unwrap();
        assert!(
            outcome.stderr.contains("THE-REAL-ERROR"),
            "the tail must survive the cap"
        );
        assert!(
            outcome.stderr.len() <= STDERR_TAIL + 1,
            "capture not bounded: {} bytes",
            outcome.stderr.len()
        );
    }

    // A package command is bounded: a wedged child is killed rather than hanging
    // the provision.
    #[test]
    fn a_wedged_package_command_is_killed_not_awaited() {
        let _g = crate::test_support::env_guard();
        std::env::set_var(PKG_TIMEOUT_ENV, "200");
        let start = std::time::Instant::now();
        let outcome = PkgCmd::new(&[], &["bash", "-c", "sleep 60"]).run().unwrap();
        std::env::remove_var(PKG_TIMEOUT_ENV);
        assert!(outcome.timed_out, "must report the timeout");
        assert!(!outcome.success());
        assert!(
            start.elapsed() < Duration::from_secs(10),
            "took {:?}",
            start.elapsed()
        );
    }

    // A package command that exits cleanly while leaking a background process
    // holding its stderr must not hang the call. An apt/dnf postinst that starts a
    // daemon is the real instance: the daemon inherits stderr, nothing signals it
    // (there was no timeout — the command SUCCEEDED), and an unbounded
    // `reader.join()` would wait for the daemon's lifetime.
    #[test]
    fn a_leaked_background_process_cannot_hang_a_package_command() {
        let start = std::time::Instant::now();
        let outcome = PkgCmd::new(&[], &["bash", "-c", "( sleep 120 ) & echo ok >&2"])
            .run()
            .unwrap();
        assert!(outcome.success(), "the command itself succeeded");
        assert!(
            start.elapsed() < STDERR_DRAIN_GRACE + Duration::from_secs(3),
            "must return on the drain grace, not the orphan's lifetime (took {:?})",
            start.elapsed()
        );
    }

    // A package command does NOT inherit the installer's stdin. Under
    // `curl … | sudo bash` that stdin is the installer SCRIPT, so a child that
    // reads it consumes the rest of the install. `read` must see EOF instantly.
    #[test]
    fn package_commands_get_no_stdin() {
        let outcome = PkgCmd::new(&[], &["bash", "-c", "read line && echo got: $line"])
            .run()
            .unwrap();
        assert_eq!(
            outcome.exit_code, 1,
            "read must hit EOF on /dev/null, not consume the parent's stdin"
        );
    }

    #[test]
    fn pipefail_propagates_failed_curl_leg() {
        // HIGH-1 regression: a failing left-hand pipe stage under `bash -o pipefail`
        // MUST yield a non-zero status. `false | bash -` is the exact shape a
        // curl 404/DNS/TLS failure produces (curl exits non-zero, bash reads EOF).
        // Without pipefail the pipe exits 0 (bash's status), silently masking the
        // fetch failure — which is the bug this fix restores parity for.
        let status = Command::new("bash")
            .arg("-o")
            .arg("pipefail")
            .arg("-c")
            .arg("false | bash -")
            .status()
            .expect("spawn bash");
        assert!(
            !status.success(),
            "pipefail must surface the failed left leg as non-zero"
        );

        // Control: WITHOUT pipefail the same pipe exits 0 — demonstrating the bug
        // the fix closes (documents why `-o pipefail` is load-bearing).
        let status_no_pf = Command::new("bash")
            .arg("-c")
            .arg("false | bash -")
            .status()
            .expect("spawn bash");
        assert!(
            status_no_pf.success(),
            "plain bash -c masks the failed leg (exit 0) — the bug pipefail fixes"
        );
    }

    #[test]
    fn nodesource_repo_paths_debian_three_paths_byte_identical() {
        let paths: Vec<String> = nodesource_repo_paths(Family::Debian)
            .into_iter()
            .map(|p| p.display().to_string())
            .collect();
        assert_eq!(
            paths,
            vec![
                "/etc/apt/sources.list.d/nodesource.sources".to_string(),
                "/etc/apt/sources.list.d/nodesource.list".to_string(),
                "/etc/apt/preferences.d/nodejs".to_string(),
            ]
        );
    }

    #[test]
    fn nodesource_repo_paths_rhel_two_paths_byte_identical() {
        let paths: Vec<String> = nodesource_repo_paths(Family::Rhel)
            .into_iter()
            .map(|p| p.display().to_string())
            .collect();
        assert_eq!(
            paths,
            vec![
                "/etc/yum.repos.d/nodesource-nodejs.repo".to_string(),
                "/etc/yum.repos.d/nodesource-nsolid.repo".to_string(),
            ]
        );
    }

    #[test]
    fn nodesource_module_reset_rhel_resets_debian_noop() {
        assert_eq!(
            nodesource_module_reset_cmd(Family::Rhel).unwrap().argv,
            vec!["dnf", "-y", "module", "reset", "nodejs"]
        );
        assert!(nodesource_module_reset_cmd(Family::Debian).is_none());
    }

    #[test]
    fn locale_ensure_rejects_non_c_utf8() {
        // C.UTF-8-only, fail closed — the reject fires BEFORE any family branch,
        // so this needs no live apt/dnf.
        let err = locale_ensure(Family::Debian, "en_US.UTF-8").unwrap_err();
        assert!(err.to_string().contains("only C.UTF-8"));
        let err = locale_ensure(Family::Rhel, "en_US.UTF-8").unwrap_err();
        assert!(err.to_string().contains("only C.UTF-8"));
    }
}
