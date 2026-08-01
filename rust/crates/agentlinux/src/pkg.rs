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
use std::path::PathBuf;
use std::process::Command;

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

    /// Spawn this command, inheriting stdio, returning the exit status as an
    /// `io::Result` (a non-zero exit is a non-fatal `Ok(status)` — the caller
    /// decides fatality, matching the individual Bash verbs' `|| true` sites).
    /// Not mutation-tested: the one place this module spawns a real process
    /// (ADR-019 §5). What gets spawned is asserted through the `*_cmd` builders,
    /// and what happens to the exit status through the [`Runner`] seam.
    #[cfg_attr(test, mutants::skip)]
    fn run(&self) -> io::Result<std::process::ExitStatus> {
        let mut cmd = Command::new(&self.argv[0]);
        cmd.args(&self.argv[1..]);
        for (k, v) in &self.env {
            cmd.env(k, v);
        }
        cmd.status()
    }
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
            let mut install = vec!["apt-get", "install", "-y", "--no-install-recommends"];
            install.extend_from_slice(pkgs);
            vec![
                PkgCmd::new(&[DEB_FRONTEND], &["apt-get", "update"]),
                PkgCmd::new(&[DEB_FRONTEND], &install),
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
///
/// Not mutation-tested: a production wiring adapter (ADR-019 §5) — it runs
/// `apt-get`/`dnf` as root. The argv is asserted through [`install_cmds`] and
/// the failure handling through [`run_all_with`].
#[cfg_attr(test, mutants::skip)]
pub fn pkg_install(family: Family, pkgs: &[&str]) -> io::Result<()> {
    run_all(&install_cmds(family, pkgs))
}

/// The command `pkg_remove` runs (debian apt-get purge, rhel dnf remove).
pub fn remove_cmd(family: Family, pkgs: &[&str]) -> PkgCmd {
    match family {
        Family::Debian => {
            let mut argv = vec!["apt-get", "purge", "-y"];
            argv.extend_from_slice(pkgs);
            PkgCmd::new(&[DEB_FRONTEND], &argv)
        }
        Family::Rhel => {
            let mut argv = vec!["dnf", "remove", "-y"];
            argv.extend_from_slice(pkgs);
            PkgCmd::new(&[], &argv)
        }
    }
}

/// `pkg_remove <pkg...>` — remove packages (purge config on debian).
///
/// Not mutation-tested: as [`pkg_install`]; argv via [`remove_cmd`].
#[cfg_attr(test, mutants::skip)]
pub fn pkg_remove(family: Family, pkgs: &[&str]) -> io::Result<()> {
    run_one(&remove_cmd(family, pkgs))
}

/// The command `pkg_autoremove` runs.
pub fn autoremove_cmd(family: Family) -> PkgCmd {
    match family {
        Family::Debian => PkgCmd::new(&[DEB_FRONTEND], &["apt-get", "autoremove", "-y"]),
        Family::Rhel => PkgCmd::new(&[], &["dnf", "autoremove", "-y"]),
    }
}

/// `pkg_autoremove` — drop orphaned dependencies.
///
/// Not mutation-tested: as [`pkg_install`]; argv via [`autoremove_cmd`].
#[cfg_attr(test, mutants::skip)]
pub fn pkg_autoremove(family: Family) -> io::Result<()> {
    run_one(&autoremove_cmd(family))
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
            PkgCmd::new(&[DEB_FRONTEND], &["apt-get", "update"]),
            PkgCmd::new(
                &[DEB_FRONTEND],
                &[
                    "apt-get",
                    "install",
                    "-y",
                    "--no-install-recommends",
                    "curl",
                    "gnupg",
                    "ca-certificates",
                    "apt-transport-https",
                ],
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
/// Not mutation-tested: a production wiring adapter (ADR-019 §5) — it runs the
/// prereq installs as root. The argv is asserted through
/// [`nodesource_prereqs_cmds`], the failure handling through [`run_all_with`].
#[cfg_attr(test, mutants::skip)]
pub fn nodesource_prereqs(family: Family) -> io::Result<()> {
    run_all(&nodesource_prereqs_cmds(family))
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
    // `--connect-timeout 30 --max-time 300` (M-1/M-3): a DNS/TLS stall or a slow
    // hang can't wedge provisioning forever — success behavior is byte-identical.
    format!("curl -fsSL --connect-timeout 30 --max-time 300 {url} | bash -")
}

/// `nodesource_setup` — run the pinned NodeSource setup_22.x script
/// (`curl -fsSL <url> | bash -`). The pipe runs under `bash -o pipefail -c` so a
/// curl 404/DNS/TLS failure propagates through the pipe as a non-zero status
/// (HIGH-1: a plain `bash -c` lacks pipefail and would exit 0 on a failed fetch,
/// matching the Bash verb's `set -euo pipefail`). The URL comes from
/// `nodesource_setup_url`; HTTPS + `curl -fsSL` cert verification is the
/// fetch-integrity control (ADR-005).
/// Not mutation-tested: a production wiring adapter (ADR-019 §5) — it pipes the
/// NodeSource setup script into `bash -o pipefail` as root, over the network.
/// The URL is asserted through [`nodesource_setup_url`] and the script shape
/// through [`nodesource_setup_script`], which carry the ADR-005 fetch-integrity
/// contract; only the spawn and its status check are unreachable here.
#[cfg_attr(test, mutants::skip)]
pub fn nodesource_setup(family: Family) -> io::Result<()> {
    let url = nodesource_setup_url(family);
    let script = nodesource_setup_script(url);
    let status = Command::new("bash")
        .arg("-o")
        .arg("pipefail")
        .arg("-c")
        .arg(&script)
        .status()?;
    if !status.success() {
        return Err(io::Error::other(format!(
            "nodesource_setup: setup script failed ({status})"
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
/// Not mutation-tested: as [`nodesource_prereqs`]; argv via
/// [`nodesource_module_reset_cmd`].
#[cfg_attr(test, mutants::skip)]
pub fn nodesource_module_reset(family: Family) -> io::Result<()> {
    if let Some(cmd) = nodesource_module_reset_cmd(family) {
        // Non-fatal: swallow a non-zero exit (Bash `|| true`).
        let _ = cmd.run()?;
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
/// Not mutation-tested: a production wiring adapter (ADR-019 §5) — it spawns
/// `locale-gen`/`update-locale` as root and writes `/etc/locale.conf`. The gate
/// it ends on is asserted through [`require_locale_available_with`], and the
/// resulting BHV-02 behaviour by the bats contract.
#[cfg_attr(test, mutants::skip)]
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
                run_all(&install_cmds(Family::Debian, &["locales"]))?;
            }
            // locale-gen C.UTF-8 (non-fatal, Bash `|| true`).
            let _ = Command::new("locale-gen").arg("C.UTF-8").status();
            let status = Command::new("update-locale")
                .arg("LANG=C.UTF-8")
                .arg("LC_ALL=C.UTF-8")
                .status()?;
            if !status.success() {
                return Err(io::Error::other("locale_ensure: update-locale failed"));
            }
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
#[cfg_attr(test, mutants::skip)]
fn require_locale_available() -> io::Result<()> {
    require_locale_available_with(PkgCmd::run)
}

fn require_locale_available_with(run: Runner) -> io::Result<()> {
    let status = run(&locale_available_cmd())?;
    if !status.success() {
        return Err(io::Error::other(
            "locale_ensure: C.UTF-8 locale not available after enforcement",
        ));
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/// How a [`PkgCmd`] gets executed. A seam because everything below decides what
/// to do with an exit status, and reaching those decisions through the real
/// [`PkgCmd::run`] means spawning `apt-get`/`dnf` as root.
type Runner = fn(&PkgCmd) -> io::Result<std::process::ExitStatus>;

/// Run every command in sequence, failing fast on the first non-zero exit
/// (matches the Bash `set -e` sequencing of the multi-command verbs).
#[cfg_attr(test, mutants::skip)]
fn run_all(cmds: &[PkgCmd]) -> io::Result<()> {
    run_all_with(cmds, PkgCmd::run)
}

fn run_all_with(cmds: &[PkgCmd], run: Runner) -> io::Result<()> {
    for c in cmds {
        run_one_with(c, run)?;
    }
    Ok(())
}

/// Run one command, mapping a non-zero exit to an `Err` (the `set -e` default
/// for a verb whose failure IS fatal — the individual `|| true` sites handle
/// their own non-fatality inline).
#[cfg_attr(test, mutants::skip)]
fn run_one(cmd: &PkgCmd) -> io::Result<()> {
    run_one_with(cmd, PkgCmd::run)
}

fn run_one_with(cmd: &PkgCmd, run: Runner) -> io::Result<()> {
    let status = run(cmd)?;
    if !status.success() {
        return Err(io::Error::other(format!(
            "pkg verb failed: {:?} ({status})",
            cmd.argv
        )));
    }
    Ok(())
}

#[cfg(test)]
mod pkg_tests {
    use super::*;
    use std::os::unix::process::ExitStatusExt;
    use std::sync::atomic::{AtomicUsize, Ordering};

    fn status(code: i32) -> io::Result<std::process::ExitStatus> {
        Ok(std::process::ExitStatus::from_raw(code << 8))
    }
    fn ok_run(_c: &PkgCmd) -> io::Result<std::process::ExitStatus> {
        status(0)
    }
    fn failing_run(_c: &PkgCmd) -> io::Result<std::process::ExitStatus> {
        status(1)
    }

    /// A non-zero exit from a package verb is fatal, and the error names the
    /// argv so an operator can see WHICH command failed. `delete !` survived on
    /// that check — inverted, a failed `apt-get install` reports success and the
    /// provision continues onto a step whose prerequisite never landed.
    #[test]
    fn a_failed_package_command_is_an_error_naming_its_argv() {
        let cmd = PkgCmd::new(&[], &["apt-get", "install", "-y", "nodejs"]);

        assert!(run_one_with(&cmd, ok_run).is_ok(), "exit 0 is success");

        let err = run_one_with(&cmd, failing_run).expect_err("exit 1 must be fatal");
        let msg = err.to_string();
        assert!(
            msg.contains("apt-get") && msg.contains("nodejs"),
            "the failure must name the command that failed, got {msg:?}"
        );
    }

    /// `run_all` is the `set -e` sequencing of the multi-command verbs: the
    /// first failure stops the sequence. Without this, a failed `apt-get update`
    /// is followed by the `install` that depends on it.
    #[test]
    fn a_sequence_stops_at_the_first_failure() {
        static CALLS: AtomicUsize = AtomicUsize::new(0);
        fn second_fails(_c: &PkgCmd) -> io::Result<std::process::ExitStatus> {
            let n = CALLS.fetch_add(1, Ordering::SeqCst);
            if n == 1 {
                Ok(std::process::ExitStatus::from_raw(1 << 8))
            } else {
                Ok(std::process::ExitStatus::from_raw(0))
            }
        }
        let cmds = [
            PkgCmd::new(&[], &["apt-get", "update"]),
            PkgCmd::new(&[], &["apt-get", "install", "-y", "curl"]),
            PkgCmd::new(&[], &["apt-get", "clean"]),
        ];

        CALLS.store(0, Ordering::SeqCst);
        assert!(run_all_with(&cmds, second_fails).is_err());
        assert_eq!(
            CALLS.load(Ordering::SeqCst),
            2,
            "the third command must NOT run after the second failed"
        );

        CALLS.store(0, Ordering::SeqCst);
        assert!(run_all_with(&cmds, ok_run).is_ok());
    }

    /// The locale gate is the last word of `locale_ensure`: if `locale -a` does
    /// not list C.UTF-8 after enforcement, provisioning must fail rather than
    /// continue onto a host whose non-interactive SSH sessions get the wrong
    /// locale (BHV-02).
    #[test]
    fn an_unavailable_locale_fails_the_gate() {
        assert!(require_locale_available_with(ok_run).is_ok());
        let err = require_locale_available_with(failing_run)
            .expect_err("a missing locale must not pass the gate");
        assert!(
            err.to_string().contains("C.UTF-8"),
            "the diagnostic must name the locale, got {err}"
        );
    }

    #[test]
    fn install_cmds_debian_updates_then_installs_noninteractive() {
        let cmds = install_cmds(Family::Debian, &["nodejs"]);
        assert_eq!(cmds.len(), 2);
        assert_eq!(cmds[0].argv, vec!["apt-get", "update"]);
        assert_eq!(
            cmds[0].env,
            vec![("DEBIAN_FRONTEND".to_string(), "noninteractive".to_string())]
        );
        assert_eq!(
            cmds[1].argv,
            vec![
                "apt-get",
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
            vec!["apt-get", "purge", "-y", "nodejs"]
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
            vec!["apt-get", "autoremove", "-y"]
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
        assert_eq!(cmds[0].argv, vec!["apt-get", "update"]);
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
    fn nodesource_setup_script_carries_curl_timeouts() {
        // M-3: the curl leg is bounded so a network stall can't hang forever.
        let s = nodesource_setup_script("https://example.test/setup_22.x");
        assert!(s.contains("--connect-timeout 30"), "script: {s}");
        assert!(s.contains("--max-time 300"), "script: {s}");
        assert!(s.contains("| bash -"), "script: {s}");
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
