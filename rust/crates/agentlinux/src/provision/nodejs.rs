//! provision/nodejs.rs — step 30: Node.js 22 LTS and the npm prefix.
//!
//! Installs Node.js 22 LTS via the NodeSource pre-Node bootstrap + the per-user
//! npm prefix, with observable state byte-identical to the Bash provisioner on
//! both the apt (deb.nodesource.com) and dnf (rpm.nodesource.com) paths.
//! Satisfies RT-01 (Node 22 LTS) and RT-04 (`~/.npmrc` carries
//! `prefix=<home>/.npm-global`; the belt-and-braces `NPM_CONFIG_PREFIX` env var is
//! step 40's job). Runs after `20-sudoers` and before
//! `40-path-wiring` in the numeric-ordered step vec.
//!
//! THE CRUX (the compiled-binary payoff): this step runs from the static musl bin
//! on a BARE host with NO Node — Node exists ONLY after `pkg::pkg_install(…,
//! ["nodejs"])`. The NodeSource `curl … setup_22.x | bash -` + apt/dnf are shelled
//! EXTERNAL (they come from the base image), never reimplemented; the setup runs
//! via `pkg::nodesource_setup`, which pipes a timeout-bounded curl
//! (`curl -fsSL --connect-timeout 30 --max-time 300 … | bash -`) under
//! `bash -o pipefail -c` so a failed fetch (404/DNS/TLS) propagates as a non-zero
//! status instead of being masked by the pipe's last stage. The integrity control
//! is HTTPS + `curl -fsSL` cert-verify + the GPG-signed repo the setup installs
//! (ADR-005; no body SHA — accepted).
//!
//! Dispatches on the pre-resolved `RESOLUTIONS[node]` token (only two real tokens):
//!  - `Reuse` → skip the NodeSource install + `.npmrc` bootstrap; warn if the npm
//!    prefix is not writable so the REMEDIATE-01 dispatch below catches it. Still
//!    runs the npm-prefix dispatch at the end.
//!  - `Create` → the CREATE path (prereqs → module-reset → idempotent repo-add →
//!    `pkg_install nodejs` → RT-01 verify → RT-04 npm-prefix layout + `.npmrc`).
//!  - `Remediate` | `ReuseWithWarning` | `Bail` → no `node` token lives at this
//!    layer (REMEDIATE-01 is the npm-prefix layer); defensive error / warn arm.
//!
//! The npm-prefix REMEDIATE-01 dispatch runs UNCONDITIONALLY after the create/reuse
//! split (orthogonal to whether Node was reused or freshly installed), matching
//! `30-nodejs.sh:154-172`.

use crate::pkg;
use crate::provision::{remediate_npm_prefix, ProvisionCtx, StepResolution};
use crate::sysio;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::Command;

/// `run` — the 30-nodejs.sh port. `ctx.resolutions.node` selects the CREATE/REUSE
/// path; the npm-prefix REMEDIATE-01 dispatch (`ctx.resolutions.npm_prefix`) runs
/// unconditionally afterward.
///
/// Not mutation-tested: an ADR-019 §5 seam gap. Reaches the NodeSource script,
/// `apt-get`/`dnf` and `node --version` with no injection point. Skipped with a
/// back-reference rather than left to redden the enforcing gate (ADR-020 §4,
/// third case). The REMEDIATE-01 dispatch it makes IS observed, through
/// `remediate_npm_prefix::chown_or_rebase_with`.
#[cfg_attr(test, mutants::skip)]
pub fn run(ctx: &ProvisionCtx) -> io::Result<()> {
    eprintln!("30-nodejs: starting");

    // Dispatch on RESOLUTIONS[node]. Two real tokens
    // (reuse|create); remediate/bail are defensive (no node token at this layer).
    let node_reused = match ctx.resolutions.node {
        StepResolution::Reuse => {
            eprintln!(
                "30-nodejs: REUSE branch — skipping the NodeSource nodejs install + .npmrc bootstrap"
            );
            // The active npm prefix may still diverge from the reused Node's
            // prefix; the npm-prefix dispatch below (REMEDIATE-01) handles it —
            // warn for transcript visibility.
            if !npm_prefix_writable_by_install_user(ctx) {
                eprintln!(
                    "30-nodejs: REUSE-02 succeeded but the npm prefix is not writable by \
                     the install user — REMEDIATE-01 npm-prefix dispatch follows"
                );
            }
            true
        }
        StepResolution::Create => false,
        StepResolution::Remediate | StepResolution::ReuseWithWarning => {
            // The Node-install layer only ever resolves CREATE or REUSE: node
            // drift is repaired by reinstalling, not by a separate remediation,
            // so `decide_core` never assigns these to `node`.
            return Err(io::Error::other(format!(
                "30-nodejs: unexpected RESOLUTIONS[node] = {:?} — no remediate or \
                 reuse-with-warning token is defined at the Node-install layer",
                ctx.resolutions.node
            )));
        }
    };

    // CREATE-path block — block-skipped (not an early
    // return) on REUSE so the npm-prefix REMEDIATE-01 dispatch still fires below.
    if !node_reused {
        create_path(ctx)?;
    }

    // npm-prefix layer dispatch (REMEDIATE-01) — UNCONDITIONAL, after the
    // create/reuse split. Orthogonal to whether Node was
    // reused or freshly installed.
    match ctx.resolutions.npm_prefix {
        StepResolution::Reuse => {
            eprintln!("30-nodejs: [REUSE] npm-prefix: writable by the install user; nothing to do");
        }
        StepResolution::Create => {
            // The CREATE path above bootstrapped the prefix (or no-op).
        }
        StepResolution::Remediate => {
            // The consent gate already passed upstream (--yes confirmed).
            remediate_npm_prefix::chown_or_rebase(ctx)?;
        }
        StepResolution::ReuseWithWarning => {
            // TTY operator declined chown/rebase; leave ownership as-is + a marker.
            eprintln!(
                "30-nodejs: [REUSE-WARN] component=npm-prefix — skipped (user declined \
                 remediation; manual fix needed). npm-global ownership unchanged."
            );
        }
    }

    eprintln!("30-nodejs: done");
    Ok(())
}

/// The CREATE path: prereqs → module-reset → idempotent
/// repo-add → `pkg_install nodejs` → RT-01 verify → RT-04 npm-prefix + `.npmrc`.
/// Not mutation-tested: a production wiring adapter (ADR-019 §5) — it drives
/// apt/dnf, the NodeSource setup script and `ensure_dir` as root. Its two
/// decisions are [`rt01_version_gate`] and [`prefix_layout_should_be_enforced`],
/// both asserted directly.
#[cfg_attr(test, mutants::skip)]
fn create_path(ctx: &ProvisionCtx) -> io::Result<()> {
    // Step 1: pre-reqs for setup_22.x, via the distro-neutral verb. Debian installs
    // the four apt prereqs after `apt-get update`; rhel installs ONLY
    // ca-certificates (never curl — curl-minimal conflicts on EL9). Idempotent.
    pkg::nodesource_prereqs(ctx.family)?;

    // Defuse a pre-existing AppStream `nodejs` module so the older distro module
    // cannot win over the NodeSource repo. rhel-only (`dnf -y module
    // reset nodejs || true`), a no-op on debian — the family branch lives in the
    // verb.
    pkg::nodesource_module_reset(ctx.family)?;

    // Step 2: idempotent NodeSource repo add. Gate on the family's repo file paths
    // (the single source of truth shared with the detect gate + purge cleanup): if
    // ANY family repo file is present a re-run short-circuits; else run the setup
    // script (which rm -fs + recreates, self-healing a missed gate byte-clean)
    let repo_present = pkg::nodesource_repo_paths(ctx.family)
        .iter()
        .any(|p| p.exists());
    if repo_present {
        eprintln!("30-nodejs: NodeSource repo already configured (gate: nodesource_repo_paths)");
    } else {
        eprintln!("30-nodejs: NodeSource repo absent — running setup_22.x");
        // Security: curl-pipe-bash from the pinned ADR-005 upstream; HTTPS +
        // `curl -fsSL` cert-verify is the integrity control.
        pkg::nodesource_setup(ctx.family)?;
    }

    // Step 3: install nodejs via the distro-neutral pkg_install verb (apt on
    // debian, dnf on rhel). Idempotent — no-op if the installed version satisfies
    // the repo-pinning policy set by setup_22.x.
    pkg::pkg_install(ctx.family, &["nodejs"])?;

    // Step 4: post-install verify (RT-01). Hard-fail if major < 22 (pinning broke
    // or the distro's built-in nodejs was installed first). The Bash uses
    // `return 1` (not `exit 1`) so the ERR trap fires with the correct src:line;
    // here that is an `Err` that aborts the provisioner loudly.
    let major = node_major_version()?;
    rt01_version_gate(major)?;
    eprintln!("30-nodejs: Node.js v{major} installed (RT-01 — v22 LTS)");

    // Step 5: per-user npm prefix layout (RT-04). bin/ and lib/ are created
    // proactively agent-owned so `npm install -g` never races to create them as
    // root. On RESOLUTIONS[npm-prefix]=reuse-with-warning (operator declined the
    // chown remediation), SKIP the ensure_dir chown so the decline is honored —
    // otherwise the CREATE-path ensure_dir would silently chown the prefix back to
    // the install user.
    let owner = format!("{u}:{u}", u = ctx.install_user);
    let npm_global = format!("{}/.npm-global", ctx.install_home);
    if prefix_layout_should_be_enforced(ctx.resolutions.npm_prefix) {
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
    let npmrc = format!("{}/.npmrc", ctx.install_home);
    let npmrc_path = Path::new(&npmrc);
    sysio::create_if_absent_0644(npmrc_path, &owner, ctx.fx.chown)?;
    sysio::ensure_line_in_file(&format!("prefix={npm_global}"), npmrc_path)?;
    std::fs::set_permissions(npmrc_path, std::fs::Permissions::from_mode(0o644))?;
    sysio::chown_by_name(npmrc_path, &owner)?;
    eprintln!("30-nodejs: wrote {npmrc} (prefix={npm_global} — RT-04)");

    Ok(())
}

/// `node --version` → the parsed MAJOR version. Runs the freshly-installed `node`
/// directly (as root, on PATH after the NodeSource install — exactly as the Bash
/// `node --version` runs from the root-executed 30-nodejs.sh). A missing binary or
/// an unparsable version maps to major 0 (→ the RT-01 hard-fail), mirroring the
/// Bash `${node_major:-0}` default.
/// Not mutation-tested: it spawns the freshly-installed `node` (ADR-019 §5).
/// The parse it wraps is [`parse_node_major`].
#[cfg_attr(test, mutants::skip)]
fn node_major_version() -> io::Result<u32> {
    let out = match Command::new("node").arg("--version").output() {
        Ok(o) => o,
        // ENOENT (node absent) → major 0 so the RT-01 gate hard-fails loudly.
        Err(_) => return Ok(0),
    };
    if !out.status.success() {
        return Ok(0);
    }
    Ok(parse_node_major(&String::from_utf8_lossy(&out.stdout)))
}

/// Parse `v22.11.0` → 22: strip a leading `v`, take the pre-`.` field. Anything
/// unparsable is major 0, which the RT-01 gate then hard-fails on — mirroring
/// the Bash `${node_major:-0}` default.
///
/// Split from the spawn so the parse is reachable without a `node` on PATH.
fn parse_node_major(stdout: &str) -> u32 {
    stdout
        .trim()
        .trim_start_matches('v')
        .split('.')
        .next()
        .and_then(|s| s.parse::<u32>().ok())
        .unwrap_or(0)
}

/// RT-01: v22 LTS or the provision aborts.
///
/// A pure verdict rather than an inline `if` because the COMPARISON is the
/// contract and every neighbouring spelling survived mutation — `==`, `>`, `<=`
/// each let some wrong major through. `<=` is the interesting one: it rejects
/// exactly v22, the only version that is supposed to pass.
fn rt01_version_gate(major: u32) -> io::Result<()> {
    if major < 22 {
        return Err(io::Error::other(format!(
            "30-nodejs: node v{major} installed but v22 LTS required (RT-01)"
        )));
    }
    Ok(())
}

/// Whether the CREATE path may (re-)establish the npm-prefix layout and its
/// ownership.
///
/// `ReuseWithWarning` means the operator DECLINED the chown remediation, so
/// enforcing the layout would silently chown the prefix back and undo the
/// decline. Every other resolution enforces.
fn prefix_layout_should_be_enforced(npm_prefix: StepResolution) -> bool {
    npm_prefix != StepResolution::ReuseWithWarning
}

/// Whether the install user's npm prefix (`<home>/.npm-global`) is writable by the
/// install user — the REUSE-branch warn probe. A missing prefix
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

#[cfg(test)]
mod nodejs_tests {
    use super::*;
    use crate::distro::Family;
    use crate::provision::StepResolutions;

    /// RT-01 accepts v22 and above and nothing below. Every neighbouring
    /// spelling of the comparison survived: `==` rejects everything except 21,
    /// `>` accepts only what it should reject, and `<=` rejects exactly v22 —
    /// the one version that is supposed to pass.
    #[test]
    fn the_rt01_gate_accepts_v22_and_up_and_nothing_below() {
        for major in [0, 1, 18, 20, 21] {
            let err = rt01_version_gate(major).expect_err("below v22 must abort");
            let msg = err.to_string();
            assert!(
                msg.contains(&format!("v{major}")) && msg.contains("RT-01"),
                "the diagnostic must name the version and the requirement, got {msg:?}"
            );
        }
        for major in [22, 23, 24, 99] {
            assert!(
                rt01_version_gate(major).is_ok(),
                "v{major} satisfies v22 LTS or newer"
            );
        }
    }

    /// `node --version` output → major. Anything unparsable is 0, which the gate
    /// above then hard-fails on — an unreadable version must never pass for a
    /// good one.
    #[test]
    fn the_node_version_parse_defaults_to_zero_on_anything_odd() {
        assert_eq!(parse_node_major("v22.11.0\n"), 22);
        assert_eq!(parse_node_major("22.11.0"), 22, "a bare version parses too");
        assert_eq!(
            parse_node_major("  v24.0.1  \n"),
            24,
            "whitespace is trimmed"
        );
        for odd in ["", "not a version", "vX.1.2", "\n", "v.1.2"] {
            assert_eq!(
                parse_node_major(odd),
                0,
                "{odd:?} must read as 0 so RT-01 rejects it"
            );
        }
    }

    /// A declined chown remediation must stay declined: enforcing the prefix
    /// layout would silently chown it back and undo the operator's choice.
    #[test]
    fn a_declined_prefix_remediation_is_not_re_enforced() {
        assert!(
            !prefix_layout_should_be_enforced(StepResolution::ReuseWithWarning),
            "reuse-with-warning is the operator declining — do not chown back"
        );
        for r in [
            StepResolution::Create,
            StepResolution::Reuse,
            StepResolution::Remediate,
        ] {
            assert!(
                prefix_layout_should_be_enforced(r),
                "{r:?} must establish the layout"
            );
        }
    }

    /// The REUSE-branch warn probe: is the prefix owned by the install user?
    /// Both constant replacements survived, and so did inverting the uid
    /// comparison — forced true reports a root-owned prefix as writable by the
    /// agent, which is the EACCES bug class AgentLinux exists to eliminate.
    #[test]
    fn the_prefix_probe_answers_on_real_ownership() {
        let home = tempfile::tempdir().unwrap();
        let me = nix::unistd::User::from_uid(nix::unistd::getuid())
            .ok()
            .flatten()
            .map(|u| u.name)
            .expect("the test process has a passwd entry");

        let mut ctx = ctx_with(
            StepResolution::Create,
            StepResolution::Create,
            home.path().to_str().unwrap(),
        );
        ctx.install_user = me;

        // No prefix yet → not-yet-writable.
        assert!(
            !npm_prefix_writable_by_install_user(&ctx),
            "a missing prefix is not yet writable"
        );

        // Created and owned by us → writable.
        std::fs::create_dir_all(home.path().join(".npm-global")).unwrap();
        assert!(
            npm_prefix_writable_by_install_user(&ctx),
            "a prefix we own is writable by us"
        );

        // A user with no passwd entry can own nothing.
        ctx.install_user = "no-such-user-agentlinux-fixture".to_string();
        assert!(
            !npm_prefix_writable_by_install_user(&ctx),
            "an unresolvable install user must not read as the owner"
        );
    }

    fn ctx_with(node: StepResolution, npm_prefix: StepResolution, home: &str) -> ProvisionCtx {
        ProvisionCtx {
            root: std::path::PathBuf::from("/"),
            fx: crate::provision::Effects::default(),
            install_user: "agent".into(),
            install_home: home.into(),
            family: Family::Debian,
            resolutions: StepResolutions {
                user: StepResolution::Create,
                sudoers: StepResolution::Create,
                node,
                npm_prefix,
            },
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

    // There is deliberately NO test driving `run` on a Create token here. The
    // one that used to sit at this spot asserted `run(&ctx).is_err()` against a
    // `Bail` token; when `Bail` stopped being representable at the step layer the
    // token became `Create`, and the assertion only still passed because an
    // unprivileged runner cannot apt-get. As root it ran the real NodeSource
    // install against `/`. `run` needs the package/exec seam `sudoers` already
    // has before it can be driven from a test at all.

    // The RT-04 npm-prefix layout paths are derived from install_home — a
    // non-default home lands the prefix + .npmrc under it verbatim (AL-59).
    #[test]
    fn rt04_prefix_paths_derive_from_install_home() {
        let ctx = ctx_with(
            StepResolution::Create,
            StepResolution::Create,
            "/home/claude",
        );
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

        sysio::create_if_absent_0644(&f, &owner, sysio::chown_by_name).unwrap();
        assert!(f.exists());
        assert_eq!(std::fs::read(&f).unwrap(), b"");
        assert_eq!(
            std::fs::metadata(&f).unwrap().permissions().mode() & 0o7777,
            0o644
        );

        // Now seed content and prove a present file is untouched (no-op).
        std::fs::write(&f, b"prefix=/home/agent/.npm-global\n").unwrap();
        sysio::create_if_absent_0644(&f, &owner, sysio::chown_by_name).unwrap();
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

        sysio::create_if_absent_0644(&f, &owner, sysio::chown_by_name).unwrap();
        sysio::ensure_line_in_file(line, &f).unwrap();
        let after_first = std::fs::read_to_string(&f).unwrap();
        assert_eq!(after_first, "prefix=/home/agent/.npm-global\n");

        // Re-run: create-if-absent is a no-op, ensure_line_in_file greps-before-
        // appends → byte-identical (no duplicate prefix line).
        sysio::create_if_absent_0644(&f, &owner, sysio::chown_by_name).unwrap();
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
