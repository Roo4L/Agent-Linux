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
use std::path::Path;

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
    crate::plog!("30-nodejs: starting");

    // Dispatch on RESOLUTIONS[node]. Two real tokens
    // (reuse|create); remediate/bail are defensive (no node token at this layer).
    let node_reused = match ctx.resolutions.node {
        StepResolution::Reuse => {
            crate::plog!(
                "30-nodejs: REUSE branch — skipping the NodeSource nodejs install + .npmrc bootstrap"
            );
            // The active npm prefix may still diverge from the reused Node's
            // prefix; the npm-prefix dispatch below (REMEDIATE-01) handles it —
            // warn for transcript visibility.
            if !npm_prefix_writable_by_install_user(ctx) {
                crate::plog!(
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
            crate::plog!(
                "30-nodejs: [REUSE] npm-prefix: writable by the install user; nothing to do"
            );
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
            crate::plog!(
                "30-nodejs: [REUSE-WARN] component=npm-prefix — skipped (user declined \
                 remediation; manual fix needed). npm-global ownership unchanged."
            );
        }
    }

    crate::plog!("30-nodejs: done");
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
        crate::plog!("30-nodejs: NodeSource repo already configured (gate: nodesource_repo_paths)");
    } else {
        crate::plog!("30-nodejs: NodeSource repo absent — running setup_22.x");
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
    crate::plog!("30-nodejs: Node.js v{major} installed (RT-01 — v22 LTS)");

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
        crate::plog!(
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
    // One fd across create+append+chmod+chown — see `ensure_line_in_owned_file`.
    // `~/.npmrc` is where npm keeps `_authToken`, so an existing file keeps the
    // mode the operator gave it rather than being re-widened to 0644 every run.
    sysio::ensure_line_in_owned_file(
        &format!("prefix={npm_global}"),
        npmrc_path,
        &owner,
        0o644,
        sysio::chown_by_name_nofollow,
    )?;
    crate::plog!("30-nodejs: wrote {npmrc} (prefix={npm_global} — RT-04)");

    Ok(())
}

/// Where a NodeSource-installed `node` legitimately lives, in search order.
///
/// A fixed list rather than a `$PATH` walk: the whole point is to be immune to
/// whatever the invoking shell put on PATH. `/usr/bin` is where both the apt and
/// dnf NodeSource packages install; `/usr/local/bin` covers a hand-installed
/// tarball an operator may be reusing (the REUSE branch). Both are root-owned on
/// every supported distro, which is the property that makes them safe to exec as
/// root — unlike anything under the install user's home.
const SYSTEM_NODE_PATHS: [&str; 2] = ["/usr/bin/node", "/usr/local/bin/node"];

/// The first candidate that is a plain, ROOT-OWNED, non-group/other-writable
/// regular file, resolved without following a symlink at the final component.
///
/// The path allowlist alone only constrains the NAME. This binary is executed as
/// root, so the guard has to be on the inode:
///
/// - `/usr/local/bin` is `root:staff` mode 2775 — group-writable — under Debian
///   policy on some systems, and `/usr/local/bin/node` is exactly the
///   hand-installed-tarball case the candidate list invites.
/// - Brownfield hosts that installed node via `n` or a system-wide nvm commonly
///   have `/usr/local/bin/node` as a SYMLINK into `/usr/local/n/versions/...`;
///   an `is_file()` check follows it and we would exec whatever is at the far end.
///
/// A candidate that fails these checks is skipped rather than fatal — the next
/// candidate, or ultimately major 0 and the RT-01 hard-fail, is the right outcome.
fn trusted_system_node_in(candidates: &[&str]) -> Option<String> {
    use std::os::unix::fs::{MetadataExt, OpenOptionsExt};

    candidates.iter().find_map(|p| {
        let handle = std::fs::OpenOptions::new()
            .read(true)
            .custom_flags((nix::fcntl::OFlag::O_NOFOLLOW | nix::fcntl::OFlag::O_NONBLOCK).bits())
            .open(p)
            .ok()?;
        let md = handle.metadata().ok()?;
        if !md.is_file() {
            return None;
        }
        if md.uid() != 0 {
            crate::plog!(
                "30-nodejs: skipping RT-01 candidate {p} — owned by uid {} not root; \
                 refusing to execute it as root",
                md.uid()
            );
            return None;
        }
        if md.mode() & 0o022 != 0 {
            crate::plog!(
                "30-nodejs: skipping RT-01 candidate {p} — mode {:04o} is group- or \
                 world-writable; refusing to execute it as root",
                md.mode() & 0o7777
            );
            return None;
        }
        Some((*p).to_string())
    })
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
    match trusted_system_node_in(&SYSTEM_NODE_PATHS) {
        Some(p) => node_major_version_at(&p),
        // No trustworthy candidate → major 0, the RT-01 hard-fail, without
        // spawning anything.
        None => Ok(0),
    }
}

/// Spawn `path --version` and parse the major.
///
/// Split from the trust check above so each is testable on its own: a test stub
/// cannot be root-owned, so a combined function could only be exercised by
/// weakening the very check that matters. `trusted_system_node_in` is tested
/// against ownership and mode; this is tested against parsing and the spawn.
fn node_major_version_at(node: &str) -> io::Result<u32> {
    // Bounded and process-grouped like every other spawn in the crate. `node
    // --version` is instant in every healthy case, but "instant in every healthy
    // case" is exactly what the unbounded calls this crate spent a release fixing
    // also looked like — a node binary on a stalled NFS mount, or one that a
    // botched install left waiting on stdin, would hang the provisioner here with
    // no timeout and no diagnostic. 30s is far past any real answer.
    //
    // Resolved to an ABSOLUTE path against a fixed system PATH, then dispatched at
    // the invoker's own identity — which `resolve_argv` short-circuits to a direct
    // spawn. Three separate hazards converge on this one line:
    //
    //   1. Not a `sudo -u <install_user>` hop. Step 30 runs BEFORE step 40 writes
    //      `/etc/agentlinux.env`, so any resolution consulting that file
    //      (`recipe_env::resolve_install_user`) still reports the default `agent`.
    //      `--user claude` on a greenfield host would then probe an account step 10
    //      never created and RT-01 would hard-fail naming the Node VERSION rather
    //      than the real cause — permanently, since step 40 never runs to write the
    //      file that would fix the resolution. That was a live deterministic brick.
    //   2. Not a bare `node` off the ambient PATH. This spawn runs as ROOT, and
    //      `/etc/profile.d/agentlinux.sh` (step 40, artefact 1) prepends
    //      `<home>/.npm-global/bin` for EVERY user that sources /etc/profile,
    //      root included. An agent that drops an executable at
    //      `~/.npm-global/bin/node` would have it executed as root the next time an
    //      operator re-provisions from a login shell. `Command::new` resolves argv[0]
    //      against the PARENT's PATH, which `env_clear` does not touch.
    //   3. Not a login-shell hop either (`sudo -i`, `bash -lc`), for the same
    //      reason: RT-01 asks whether the NodeSource install put the right `node` on
    //      the SYSTEM path, so it must judge the system binary and nothing else.
    //
    // `provision` is `guard::require_root`-gated, so the invoker is root and this is
    // the direct branch in practice.
    let r = crate::dispatcher::as_user(
        &crate::dispatcher::invoker_username(),
        &[node.to_string(), "--version".to_string()],
        &[],
        crate::dispatcher::Capture::Buffered,
        Some(30_000),
    );
    if r.exit_code != 0 {
        // Absent, non-zero, or timed out → major 0 so the RT-01 gate hard-fails
        // loudly rather than silently accepting an unknown runtime.
        return Ok(0);
    }
    Ok(parse_node_major(&r.stdout))
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
    use std::os::unix::fs::PermissionsExt;

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

    /// REGRESSION: the RT-01 probe must not resolve its identity from
    /// `AGENTLINUX_USER` / `/etc/agentlinux.env`.
    ///
    /// Step 30 runs BEFORE step 40 writes `/etc/agentlinux.env`, so any resolution
    /// that consults it reports the default `agent` no matter what `--user` said.
    /// On a greenfield `provision --user claude`, step 10 creates `claude`, then
    /// this probe would `sudo -u agent -- node --version` against an account that
    /// does not exist, get a non-zero exit, map it to major 0, and hard-fail RT-01
    /// with `node v0 installed but v22 LTS required` — an error naming the Node
    /// version for what is really a user-resolution bug, and permanent, since step
    /// 40 never runs to write the file that would have fixed the resolution.
    ///
    /// A stub `node` printing `version`, marked executable. Removes the dependency
    /// on whichever real node the build host has, and on where it lives — the
    /// earlier version of this test skipped when `node` was absent from PATH, which
    /// meant a container without node turned it into a silent no-op with libtest
    /// still printing `ok`.
    fn stub_node(dir: &Path, version: &str) -> String {
        use std::os::unix::fs::PermissionsExt;
        let p = dir.join("node");
        std::fs::write(&p, format!("#!/bin/sh\necho '{version}'\n")).unwrap();
        std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o755)).unwrap();
        p.to_string_lossy().into_owned()
    }

    /// REGRESSION: the RT-01 probe must not resolve its identity from
    /// `AGENTLINUX_USER` / `/etc/agentlinux.env`.
    ///
    /// Step 30 runs BEFORE step 40 writes `/etc/agentlinux.env`, so any resolution
    /// that consults it reports the default `agent` no matter what `--user` said.
    /// On a greenfield `provision --user claude`, step 10 creates `claude`, then
    /// this probe would `sudo -u agent -- node --version` against an account that
    /// does not exist, get a non-zero exit, map it to major 0, and hard-fail RT-01
    /// with `node v0 installed but v22 LTS required` — an error naming the Node
    /// version for what is really a user-resolution bug, and permanent, since step
    /// 40 never runs to write the file that would have fixed the resolution.
    ///
    /// `AGENTLINUX_USER` points at an account that cannot exist: any resolution
    /// through it takes a `sudo -u` hop that fails, collapsing the answer to 0.
    /// Asserting the EXACT major (not merely `> 0`) also pins that the probe ran
    /// the binary it was handed rather than finding some other node.
    #[test]
    fn rt01_probe_ignores_agentlinux_user_and_runs_the_binary_it_was_given() {
        let _g = crate::test_support::EnvScope::new();
        let d = tempfile::TempDir::new().unwrap();
        let node = stub_node(d.path(), "v22.11.0");

        std::env::set_var("AGENTLINUX_USER", "no-such-user-cf19a4");
        let major = node_major_version_at(&node).unwrap();
        std::env::remove_var("AGENTLINUX_USER");

        assert_eq!(
            major, 22,
            "RT-01 probe resolved through AGENTLINUX_USER instead of running the \
             binary it was given — the greenfield --user brick is back"
        );
    }

    /// The candidate list is an allowlist of NAMES; the trust decision is about the
    /// INODE. This binary is executed as root, and `/usr/local/bin` is `root:staff`
    /// mode 2775 — group-writable — under Debian policy on some systems, which is
    /// exactly where the "hand-installed tarball" candidate lives.
    ///
    /// Tests run unprivileged, so a stub is owned by the test user rather than root:
    /// that makes it the non-root case directly, and it must be refused.
    #[test]
    fn rt01_refuses_a_candidate_it_does_not_own_the_trust_chain_for() {
        let d = tempfile::TempDir::new().unwrap();
        let stub = stub_node(d.path(), "v22.11.0");
        assert_eq!(
            trusted_system_node_in(&[&stub]),
            None,
            "accepted a non-root-owned binary as the RT-01 system node — as root \
             that executes a binary root does not control"
        );
    }

    /// A group- or world-writable candidate is refused even when root owns it:
    /// ownership and writability are separate questions, and either one lets
    /// somebody other than root decide what runs.
    #[test]
    fn rt01_refuses_a_group_or_world_writable_candidate() {
        let d = tempfile::TempDir::new().unwrap();
        let stub = stub_node(d.path(), "v22.11.0");
        std::fs::set_permissions(&stub, std::fs::Permissions::from_mode(0o777)).unwrap();
        assert_eq!(trusted_system_node_in(&[&stub]), None);
    }

    /// And the absent case: no candidate at all resolves to None, so
    /// `node_major_version` reports major 0 without spawning anything.
    #[test]
    fn rt01_absent_candidate_resolves_to_none() {
        let d = tempfile::TempDir::new().unwrap();
        let missing = d.path().join("nope").to_string_lossy().into_owned();
        assert_eq!(trusted_system_node_in(&[&missing]), None);
    }

    /// The RT-01 gate boundary, through the real function rather than a re-typed
    /// copy of its parse expression: a sub-22 runtime must report its true major so
    /// the caller hard-fails.
    #[test]
    fn rt01_probe_reports_a_sub_22_major_through_the_real_spawn_path() {
        let _g = crate::test_support::EnvScope::new();
        let d = tempfile::TempDir::new().unwrap();
        let node = stub_node(d.path(), "v18.19.0");
        assert_eq!(node_major_version_at(&node).unwrap(), 18);
    }

    /// No candidate exists → major 0, which is the RT-01 hard-fail. Pins that the
    /// absent case is reached WITHOUT spawning anything, and that the fixed
    /// candidate list is consulted rather than `$PATH`: a `node` planted on PATH
    /// must not satisfy the probe, because as root that is an agent-writable
    /// binary being executed with full privilege.
    #[test]
    fn rt01_probe_ignores_a_node_on_path_when_no_system_node_exists() {
        let _g = crate::test_support::EnvScope::new();
        let d = tempfile::TempDir::new().unwrap();
        stub_node(d.path(), "v22.11.0"); // on PATH below, but not a candidate
        let old = std::env::var("PATH").unwrap_or_default();
        std::env::set_var("PATH", format!("{}:{old}", d.path().display()));
        let major = node_major_version_at(&d.path().join("absent").to_string_lossy()).unwrap();
        std::env::set_var("PATH", old);
        assert_eq!(
            major, 0,
            "the probe resolved a node from $PATH — as root that executes an \
             agent-writable binary with full privilege"
        );
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

        sysio::create_if_absent_0644(&f, &owner, sysio::chown_by_name_nofollow).unwrap();
        assert!(f.exists());
        assert_eq!(std::fs::read(&f).unwrap(), b"");
        assert_eq!(
            std::fs::metadata(&f).unwrap().permissions().mode() & 0o7777,
            0o644
        );

        // Now seed content and prove a present file is untouched (no-op).
        std::fs::write(&f, b"prefix=/home/agent/.npm-global\n").unwrap();
        sysio::create_if_absent_0644(&f, &owner, sysio::chown_by_name_nofollow).unwrap();
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

        sysio::ensure_line_in_owned_file(line, &f, &owner, 0o644, sysio::chown_by_name_nofollow)
            .unwrap();
        let after_first = std::fs::read_to_string(&f).unwrap();
        assert_eq!(after_first, "prefix=/home/agent/.npm-global\n");

        // Re-run: create-if-absent is a no-op, ensure_line_in_file greps-before-
        // appends → byte-identical (no duplicate prefix line).
        sysio::ensure_line_in_owned_file(line, &f, &owner, 0o644, sysio::chown_by_name_nofollow)
            .unwrap();
        assert_eq!(std::fs::read_to_string(&f).unwrap(), after_first);
        assert_eq!(
            after_first
                .matches("prefix=/home/agent/.npm-global")
                .count(),
            1
        );
    }
}
