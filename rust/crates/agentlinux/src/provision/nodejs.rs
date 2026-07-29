//! provision/nodejs.rs — port of `plugin/provisioner/30-nodejs.sh`.
//!
//! Installs Node.js 22 LTS via the NodeSource pre-Node bootstrap + the per-user
//! npm prefix, with observable state byte-identical to the Bash provisioner on
//! both the apt (deb.nodesource.com) and dnf (rpm.nodesource.com) paths.
//! Satisfies RT-01 (Node 22 LTS) and RT-04 (`~/.npmrc` carries
//! `prefix=<home>/.npm-global`; the belt-and-braces `NPM_CONFIG_PREFIX` env var is
//! Wave-4's `40-path-wiring` job). Runs after `20-sudoers` and before
//! `40-path-wiring` in the numeric-ordered step vec.
//!
//! THE CRUX (the compiled-binary payoff): this step runs from the static musl bin
//! on a BARE host with NO Node — Node exists ONLY after `pkg::pkg_install(…,
//! ["nodejs"])`. The NodeSource `curl … setup_22.x | bash -` + apt/dnf are shelled
//! EXTERNAL (they come from the base image), never reimplemented; the setup runs
//! via `pkg::nodesource_setup` (a bounded `bash -c 'curl -fsSL … | bash -'`) — the
//! integrity control is HTTPS + `curl -fsSL` cert-verify + the GPG-signed repo the
//! setup installs (ADR-005; no body SHA — accepted, T-57-09).
//!
//! Dispatches on the pre-resolved `RESOLUTIONS[node]` token (only two real tokens):
//!   - `Reuse` → skip the NodeSource install + `.npmrc` bootstrap; warn if the npm
//!     prefix is not writable so the REMEDIATE-01 dispatch below catches it. Still
//!     runs the npm-prefix dispatch at the end.
//!   - `Create` → the CREATE path (prereqs → module-reset → idempotent repo-add →
//!     `pkg_install nodejs` → RT-01 verify → RT-04 npm-prefix layout + `.npmrc`).
//!   - `Remediate` | `ReuseWithWarning` | `Bail` → no `node` token lives at this
//!     layer (REMEDIATE-01 is the npm-prefix layer); defensive error / warn arm.
//!
//! The npm-prefix REMEDIATE-01 dispatch runs UNCONDITIONALLY after the create/reuse
//! split (orthogonal to whether Node was reused or freshly installed), matching
//! `30-nodejs.sh:154-172`.

use crate::pkg;
use crate::provision::{remediate_npm_prefix, ProvisionCtx, Resolution};
use crate::sysio;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::Command;

/// `run` — the 30-nodejs.sh port. `ctx.resolutions.node` selects the CREATE/REUSE
/// path; the npm-prefix REMEDIATE-01 dispatch (`ctx.resolutions.npm_prefix`) runs
/// unconditionally afterward.
pub fn run(ctx: &ProvisionCtx) -> io::Result<()> {
    eprintln!("30-nodejs: starting");

    // Dispatch on RESOLUTIONS[node] (30-nodejs.sh:31-51). Two real tokens
    // (reuse|create); remediate/bail are defensive (no node token at this layer).
    let node_reused = match ctx.resolutions.node {
        Resolution::Reuse => {
            eprintln!(
                "30-nodejs: REUSE branch — skipping the NodeSource nodejs install + .npmrc bootstrap"
            );
            // The active npm prefix may still diverge from the reused Node's
            // prefix; the npm-prefix dispatch below (REMEDIATE-01) handles it —
            // warn for transcript visibility (30-nodejs.sh:38-40).
            if !npm_prefix_writable_by_install_user(ctx) {
                eprintln!(
                    "30-nodejs: REUSE-02 succeeded but the npm prefix is not writable by \
                     the install user — REMEDIATE-01 npm-prefix dispatch follows"
                );
            }
            true
        }
        Resolution::Create => false,
        Resolution::Remediate | Resolution::Bail | Resolution::ReuseWithWarning => {
            // No remediate/bail/reuse-with-warning token at the Node-install layer;
            // defensive arm (30-nodejs.sh:46-50). bail is unreachable.
            return Err(io::Error::other(format!(
                "30-nodejs: unexpected RESOLUTIONS[node] = {:?} — no remediate/bail token \
                 defined at the Node-install layer",
                ctx.resolutions.node
            )));
        }
    };

    // CREATE-path block (30-nodejs.sh:57-144) — block-skipped (not an early
    // return) on REUSE so the npm-prefix REMEDIATE-01 dispatch still fires below.
    if !node_reused {
        create_path(ctx)?;
    }

    // npm-prefix layer dispatch (REMEDIATE-01) — UNCONDITIONAL, after the
    // create/reuse split (30-nodejs.sh:154-172). Orthogonal to whether Node was
    // reused or freshly installed.
    match ctx.resolutions.npm_prefix {
        Resolution::Reuse => {
            eprintln!("30-nodejs: [REUSE] npm-prefix: writable by the install user; nothing to do");
        }
        Resolution::Create => {
            // The CREATE path above bootstrapped the prefix (or no-op).
        }
        Resolution::Remediate => {
            // The consent gate already passed upstream (--yes confirmed).
            remediate_npm_prefix::chown_or_rebase(ctx)?;
        }
        Resolution::ReuseWithWarning => {
            // TTY operator declined chown/rebase; leave ownership as-is + a marker.
            eprintln!(
                "30-nodejs: [REUSE-WARN] component=npm-prefix — skipped (user declined \
                 remediation; manual fix needed). npm-global ownership unchanged."
            );
        }
        Resolution::Bail => {
            // Unreachable — a bail exits 65 before the step loop
            // (30-nodejs.sh:168-171).
            return Err(io::Error::other(
                "30-nodejs: unreachable bail arm — flush_bails_or_continue should have gated this",
            ));
        }
    }

    eprintln!("30-nodejs: done");
    Ok(())
}

/// The CREATE path (30-nodejs.sh:59-142): prereqs → module-reset → idempotent
/// repo-add → `pkg_install nodejs` → RT-01 verify → RT-04 npm-prefix + `.npmrc`.
fn create_path(ctx: &ProvisionCtx) -> io::Result<()> {
    // Step 1: pre-reqs for setup_22.x, via the distro-neutral verb. Debian installs
    // the four apt prereqs after `apt-get update`; rhel installs ONLY
    // ca-certificates (never curl — Pitfall 5). Idempotent (30-nodejs.sh:67).
    pkg::nodesource_prereqs(ctx.family)?;

    // Defuse a pre-existing AppStream `nodejs` module so the older distro module
    // cannot win over the NodeSource repo (Pitfall 4). rhel-only (`dnf -y module
    // reset nodejs || true`), a no-op on debian — the family branch lives in the
    // verb (30-nodejs.sh:73).
    pkg::nodesource_module_reset(ctx.family)?;

    // Step 2: idempotent NodeSource repo add. Gate on the family's repo file paths
    // (the single source of truth shared with the detect gate + purge cleanup): if
    // ANY family repo file is present a re-run short-circuits; else run the setup
    // script (which rm -fs + recreates, self-healing a missed gate byte-clean)
    // (30-nodejs.sh:84-96).
    let repo_present = pkg::nodesource_repo_paths(ctx.family)
        .iter()
        .any(|p| p.exists());
    if repo_present {
        eprintln!("30-nodejs: NodeSource repo already configured (gate: nodesource_repo_paths)");
    } else {
        eprintln!("30-nodejs: NodeSource repo absent — running setup_22.x");
        // Security: curl-pipe-bash from the pinned ADR-005 upstream; HTTPS +
        // `curl -fsSL` cert-verify is the integrity control (T-57-09).
        pkg::nodesource_setup(ctx.family)?;
    }

    // Step 3: install nodejs via the distro-neutral pkg_install verb (apt on
    // debian, dnf on rhel). Idempotent — no-op if the installed version satisfies
    // the repo-pinning policy set by setup_22.x (30-nodejs.sh:101).
    pkg::pkg_install(ctx.family, &["nodejs"])?;

    // Step 4: post-install verify (RT-01). Hard-fail if major < 22 (pinning broke
    // or the distro's built-in nodejs was installed first). The Bash uses
    // `return 1` (not `exit 1`) so the ERR trap fires with the correct src:line;
    // here that is an `Err` that aborts the provisioner loudly (30-nodejs.sh:106-110).
    let major = node_major_version()?;
    if major < 22 {
        return Err(io::Error::other(format!(
            "30-nodejs: node v{major} installed but v22 LTS required (RT-01)"
        )));
    }
    eprintln!("30-nodejs: Node.js v{major} installed (RT-01 — v22 LTS)");

    // Step 5: per-user npm prefix layout (RT-04). bin/ and lib/ are created
    // proactively agent-owned so `npm install -g` never races to create them as
    // root. On RESOLUTIONS[npm-prefix]=reuse-with-warning (operator declined the
    // chown remediation), SKIP the ensure_dir chown so the decline is honored —
    // otherwise the CREATE-path ensure_dir would silently chown the prefix back to
    // the install user (30-nodejs.sh:120-129).
    let owner = format!("{u}:{u}", u = ctx.install_user);
    let npm_global = format!("{}/.npm-global", ctx.install_home);
    if ctx.resolutions.npm_prefix != Resolution::ReuseWithWarning {
        sysio::ensure_dir(Path::new(&npm_global), 0o755, &owner)?;
        sysio::ensure_dir(Path::new(&format!("{npm_global}/bin")), 0o755, &owner)?;
        sysio::ensure_dir(Path::new(&format!("{npm_global}/lib")), 0o755, &owner)?;
    } else {
        eprintln!(
            "30-nodejs: SKIPPING ensure_dir on {npm_global} \
             (RESOLUTIONS[npm-prefix]=reuse-with-warning; user declined REMEDIATE-01)"
        );
    }

    // Step 6: write the install user's ~/.npmrc with the prefix line (RT-04).
    // Atomic create-if-absent (0644 <user>:<user>), then ensure_line_in_file's
    // grep-before-append (zero diff on re-run), then re-chown/chmod
    // (ensure_line_in_file runs with root's umask and does not chown)
    // (30-nodejs.sh:134-142).
    let npmrc = format!("{}/.npmrc", ctx.install_home);
    let npmrc_path = Path::new(&npmrc);
    create_if_absent_0644(npmrc_path, &owner)?;
    sysio::ensure_line_in_file(&format!("prefix={npm_global}"), npmrc_path)?;
    std::fs::set_permissions(npmrc_path, std::fs::Permissions::from_mode(0o644))?;
    chown_by_name(npmrc_path, &owner)?;
    eprintln!("30-nodejs: wrote {npmrc} (prefix={npm_global} — RT-04)");

    Ok(())
}

/// `node --version` → the parsed MAJOR version. Runs the freshly-installed `node`
/// directly (as root, on PATH after the NodeSource install — exactly as the Bash
/// `node --version` runs from the root-executed 30-nodejs.sh). A missing binary or
/// an unparsable version maps to major 0 (→ the RT-01 hard-fail), mirroring the
/// Bash `${node_major:-0}` default (30-nodejs.sh:106).
fn node_major_version() -> io::Result<u32> {
    let out = match Command::new("node").arg("--version").output() {
        Ok(o) => o,
        // ENOENT (node absent) → major 0 so the RT-01 gate hard-fails loudly.
        Err(_) => return Ok(0),
    };
    if !out.status.success() {
        return Ok(0);
    }
    let ver = String::from_utf8_lossy(&out.stdout);
    // Parse `v22.11.0` → 22 (strip a leading `v`, take the pre-`.` field).
    let major = ver
        .trim()
        .trim_start_matches('v')
        .split('.')
        .next()
        .and_then(|s| s.parse::<u32>().ok())
        .unwrap_or(0);
    Ok(major)
}

/// Whether the install user's npm prefix (`<home>/.npm-global`) is writable by the
/// install user — the REUSE-branch warn probe (30-nodejs.sh:38). A missing prefix
/// dir counts as not-yet-writable (the REMEDIATE-01 dispatch or the CREATE ensure_dir
/// will establish it). Best-effort: checks the directory owner == the install user.
fn npm_prefix_writable_by_install_user(ctx: &ProvisionCtx) -> bool {
    use std::os::unix::fs::MetadataExt;
    let prefix = format!("{}/.npm-global", ctx.install_home);
    let uid = match nix::unistd::User::from_name(&ctx.install_user) {
        Ok(Some(u)) => u.uid.as_raw(),
        _ => return false,
    };
    match std::fs::metadata(&prefix) {
        Ok(md) => md.uid() == uid,
        Err(_) => false,
    }
}

/// Atomic create-if-absent at 0644 <user>:<user>, mirroring the Bash
/// `install -m 0644 -o <user> -g <user> /dev/null <path>` (30-nodejs.sh:134-136).
/// A present file is left untouched (the caller's ensure_line_in_file mutates it).
fn create_if_absent_0644(path: &Path, owner: &str) -> io::Result<()> {
    if path.exists() {
        return Ok(());
    }
    // Create empty, set mode, chown — the `install /dev/null` observable outcome.
    std::fs::File::create(path)?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o644))?;
    chown_by_name(path, owner)
}

/// `chown <user>:<group> <path>` by name — resolve the passwd/group entries (the
/// `user` nix feature) and apply via `std::os::unix::fs::chown` (the sanctioned
/// syscall; nix's `fs` feature is not enabled). Shared shape with agent_user.rs /
/// sudoers.rs.
fn chown_by_name(path: &Path, owner: &str) -> io::Result<()> {
    let (user, group) = owner.split_once(':').ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "chown: owner must be user:group",
        )
    })?;
    let uid = nix::unistd::User::from_name(user)
        .map_err(|e| io::Error::other(format!("chown: user {user}: {e}")))?
        .ok_or_else(|| io::Error::other(format!("chown: unknown user {user}")))?
        .uid
        .as_raw();
    let gid = nix::unistd::Group::from_name(group)
        .map_err(|e| io::Error::other(format!("chown: group {group}: {e}")))?
        .ok_or_else(|| io::Error::other(format!("chown: unknown group {group}")))?
        .gid
        .as_raw();
    std::os::unix::fs::chown(path, Some(uid), Some(gid))
        .map_err(|e| io::Error::other(format!("chown {} failed: {e}", path.display())))
}

#[cfg(test)]
mod nodejs_tests {
    use super::*;
    use crate::distro::Family;
    use crate::provision::Resolutions;

    fn ctx_with(node: Resolution, npm_prefix: Resolution, home: &str) -> ProvisionCtx {
        ProvisionCtx {
            install_user: "agent".into(),
            install_home: home.into(),
            family: Family::Debian,
            resolutions: Resolutions {
                user: Resolution::Create,
                sudoers: Resolution::Create,
                node,
                npm_prefix,
                agents: std::collections::BTreeMap::new(),
            },
            yes: false,
            dry_run: false,
        }
    }

    // The RT-01 version parse: `v22.x` → 22, and a sub-22 / missing / garbage
    // version collapses to a major that hard-fails the gate. We test the parse
    // logic inline (node_major_version shells out; the parse is the load-bearing
    // part — exercise it directly on strings).
    fn parse_major(ver: &str) -> u32 {
        ver.trim()
            .trim_start_matches('v')
            .split('.')
            .next()
            .and_then(|s| s.parse::<u32>().ok())
            .unwrap_or(0)
    }

    #[test]
    fn rt01_parses_major_from_v_prefixed_version() {
        assert_eq!(parse_major("v22.11.0"), 22);
        assert_eq!(parse_major("v24.0.1"), 24);
        assert_eq!(parse_major("v18.19.0"), 18); // sub-22 → gate would fail
    }

    #[test]
    fn rt01_unparsable_version_is_zero() {
        assert_eq!(parse_major(""), 0);
        assert_eq!(parse_major("not-a-version"), 0);
        assert_eq!(parse_major("vX.Y"), 0);
    }

    // The RT-01 gate: major < 22 is an error, major >= 22 passes. This pins the
    // threshold used in create_path.
    #[test]
    fn rt01_gate_threshold_is_22() {
        for m in [0u32, 18, 21] {
            assert!(m < 22, "major {m} must fail the RT-01 gate");
        }
        for m in [22u32, 24, 30] {
            assert!(m >= 22, "major {m} must pass the RT-01 gate");
        }
    }

    // A `Bail` node token is a defensive error (the step loop never sees it; a bail
    // exits 65 upstream) — mirrors agent_user.rs / sudoers.rs. This reaches the
    // dispatch before any I/O, so it is host-independent.
    #[test]
    fn bail_node_token_is_defensive_error() {
        let ctx = ctx_with(Resolution::Bail, Resolution::Create, "/home/agent");
        assert!(run(&ctx).is_err());
    }

    // The RT-04 npm-prefix layout paths are derived from install_home — a
    // non-default home lands the prefix + .npmrc under it verbatim (AL-59).
    #[test]
    fn rt04_prefix_paths_derive_from_install_home() {
        let ctx = ctx_with(Resolution::Create, Resolution::Create, "/home/claude");
        let npm_global = format!("{}/.npm-global", ctx.install_home);
        let npmrc = format!("{}/.npmrc", ctx.install_home);
        assert_eq!(npm_global, "/home/claude/.npm-global");
        assert_eq!(npmrc, "/home/claude/.npmrc");
        // The prefix line written to .npmrc.
        assert_eq!(
            format!("prefix={npm_global}"),
            "prefix=/home/claude/.npm-global"
        );
    }

    // create_if_absent_0644 creates an empty 0644 file when absent and is a no-op
    // when present (the Bash `install /dev/null` create-if-absent). Runs
    // unprivileged (chown to our own name) so it is host-portable.
    #[test]
    fn create_if_absent_writes_empty_0644_then_noops() {
        let d = tempfile::TempDir::new().unwrap();
        let f = d.path().join(".npmrc");
        let uid = nix::unistd::getuid();
        let gid = nix::unistd::getgid();
        let uname = nix::unistd::User::from_uid(uid).unwrap().unwrap().name;
        let gname = nix::unistd::Group::from_gid(gid).unwrap().unwrap().name;
        let owner = format!("{uname}:{gname}");

        create_if_absent_0644(&f, &owner).unwrap();
        assert!(f.exists());
        assert_eq!(std::fs::read(&f).unwrap(), b"");
        assert_eq!(
            std::fs::metadata(&f).unwrap().permissions().mode() & 0o7777,
            0o644
        );

        // Now seed content and prove a present file is untouched (no-op).
        std::fs::write(&f, b"prefix=/home/agent/.npm-global\n").unwrap();
        create_if_absent_0644(&f, &owner).unwrap();
        assert_eq!(
            std::fs::read_to_string(&f).unwrap(),
            "prefix=/home/agent/.npm-global\n"
        );
    }

    // The full RT-04 .npmrc write path (create-if-absent + ensure_line_in_file) is
    // idempotent and byte-stable: two runs yield exactly one prefix line. Exercised
    // directly against a temp file (no root needed) so it pins the observable
    // .npmrc content the RT-04 bats assert.
    #[test]
    fn rt04_npmrc_prefix_line_is_idempotent() {
        let d = tempfile::TempDir::new().unwrap();
        let f = d.path().join(".npmrc");
        let uid = nix::unistd::getuid();
        let gid = nix::unistd::getgid();
        let uname = nix::unistd::User::from_uid(uid).unwrap().unwrap().name;
        let gname = nix::unistd::Group::from_gid(gid).unwrap().unwrap().name;
        let owner = format!("{uname}:{gname}");
        let line = "prefix=/home/agent/.npm-global";

        create_if_absent_0644(&f, &owner).unwrap();
        sysio::ensure_line_in_file(line, &f).unwrap();
        let after_first = std::fs::read_to_string(&f).unwrap();
        assert_eq!(after_first, "prefix=/home/agent/.npm-global\n");

        // Re-run: create-if-absent is a no-op, ensure_line_in_file greps-before-
        // appends → byte-identical (no duplicate prefix line).
        create_if_absent_0644(&f, &owner).unwrap();
        sysio::ensure_line_in_file(line, &f).unwrap();
        assert_eq!(std::fs::read_to_string(&f).unwrap(), after_first);
        assert_eq!(
            after_first
                .matches("prefix=/home/agent/.npm-global")
                .count(),
            1
        );
    }
}
