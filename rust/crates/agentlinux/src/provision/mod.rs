//! provision — the pre-Node provisioner steps, one module per numbered stage.
//!
//! The orchestrator lives in `cmd/provision.rs` and owns the order; this module
//! holds the five steps (`agent_user`, `sudoers`, `nodejs`, `path_wiring`,
//! `registry_cli`) plus the shared `Resolutions`/`ProvisionCtx` types they
//! consume.
//!
//! DECIDE-THEN-ACT: the per-component decision tokens (`Resolutions`) are
//! computed UP FRONT — the pure gates own that decision — and the steps only do
//! I/O, dispatching on their token. A step never re-derives a decision.
//!
//! The decision vocabulary narrows between the two phases. DECIDE produces a
//! [`Resolution`], which includes `Bail`; the orchestrator then exits 65 on every
//! bail before any step runs, and hands the steps a [`StepResolution`], which has
//! no `Bail` variant to handle.

pub mod agent_user;
pub mod log;
pub mod nodejs;
pub mod path_wiring;
pub mod probe;
pub mod registry_cli;
pub mod remediate;
pub mod remediate_npm_prefix;
pub mod sudoers;
pub mod wizard;

use crate::distro::Family;
use std::io;
use std::path::{Path, PathBuf};

/// The per-component decision token — the DECIDE phase's output for one
/// provisioner component. Mirrors the Bash `RESOLUTIONS[<component>]` values
/// (`create`/`reuse`/`remediate`/`reuse-with-warning`/`bail`) that
/// `remediate::collect_all_decisions` populates. A step dispatches on its own
/// token and does ONLY I/O — it never re-derives the decision.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Resolution {
    /// Fresh provision — run the CREATE path (useradd/locale/…).
    Create,
    /// Compatible existing state — skip the identity-mutating CREATE steps.
    Reuse,
    /// Compatible except for a fixable drift owned by a LATER component's step
    /// (acts identically to `Reuse` on THIS component's identity).
    Remediate,
    /// Operator declined a state-overwriting remediation — keep existing state,
    /// emit a `[REUSE-WARN]` marker, skip the CREATE steps.
    ReuseWithWarning,
    /// Incompatible host state — unreachable inside the step loop (a bail exits
    /// 65 before run_provisioners); a step treats it as a defensive error.
    Bail,
}

/// A resolution as the STEP layer sees it — the same tokens minus `Bail`.
///
/// By the time the step loop runs, `remediate::flush_or_exit` has already exited
/// 65 on every bail, so no step can encounter one. Saying that in the type rather
/// than in a comment deletes a `Bail => Err("unreachable…")` arm from each of the
/// four dispatching steps — arms reachable only by a bug, whose tests asserted
/// nothing beyond the struct literal they had just written.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StepResolution {
    Create,
    Reuse,
    Remediate,
    ReuseWithWarning,
}

/// The per-component tokens the DECIDE phase produces.
///
/// The core components (user/sudoers/node/npm-prefix) start at `Create` — the
/// steps are idempotent CREATE/REUSE on a clean host — and
/// `remediate::decide_core` overwrites them with the real host verdict.
#[derive(Debug, Clone)]
pub struct Resolutions {
    pub user: Resolution,
    pub sudoers: Resolution,
    pub node: Resolution,
    pub npm_prefix: Resolution,
}

impl Default for Resolutions {
    fn default() -> Self {
        Self {
            user: Resolution::Create,
            sudoers: Resolution::Create,
            node: Resolution::Create,
            npm_prefix: Resolution::Create,
        }
    }
}

impl Resolutions {
    /// Narrow every token to a [`StepResolution`], or return the component name
    /// of the first that is still `Bail`.
    ///
    /// The `Err` arm is the one place the "flush_or_exit ran first" invariant is
    /// checked, replacing four per-step defensive arms.
    pub fn into_step(self) -> Result<StepResolutions, &'static str> {
        Ok(StepResolutions {
            user: narrow(self.user).ok_or("user")?,
            sudoers: narrow(self.sudoers).ok_or("sudoers")?,
            node: narrow(self.node).ok_or("node")?,
            npm_prefix: narrow(self.npm_prefix).ok_or("npm-prefix")?,
        })
    }
}

/// `Resolutions` after the bail flush — what every step dispatches on.
#[derive(Debug, Clone, Copy)]
pub struct StepResolutions {
    pub user: StepResolution,
    pub sudoers: StepResolution,
    pub node: StepResolution,
    pub npm_prefix: StepResolution,
}

/// `Resolution` → `StepResolution`, `None` for `Bail`.
fn narrow(r: Resolution) -> Option<StepResolution> {
    match r {
        Resolution::Create => Some(StepResolution::Create),
        Resolution::Reuse => Some(StepResolution::Reuse),
        Resolution::Remediate => Some(StepResolution::Remediate),
        Resolution::ReuseWithWarning => Some(StepResolution::ReuseWithWarning),
        Resolution::Bail => None,
    }
}

/// The privileged operations a step performs that a test cannot: changing a
/// file's owner, asking `visudo` whether a sudoers file parses, installing a
/// package. Injected as fn pointers (the shape `cmd/upgrade.rs`'s `UpgradeDeps`
/// and `npm.rs`'s `NpmDispatcher` already use) so a step's ORDERING and its
/// error handling — install only after visudo accepts, re-assert ownership after
/// the marker block — are assertable without root and without a real host.
#[derive(Clone, Copy)]
pub struct Effects {
    /// `chown <user>:<group> <path>`, owner given as `"user:group"`.
    ///
    /// Production binds the O_NOFOLLOW variant. Every path this effect is called
    /// on is a regular file, and half of them sit inside the install user's own
    /// home — where a path-based chown hands root's authority to whatever a
    /// planted symlink points at.
    pub chown: fn(&Path, &str) -> io::Result<()>,
    /// `mkdir -p` + re-assert mode and owner.
    pub ensure_dir: fn(&Path, u32, &str) -> io::Result<()>,
    /// `chown -h` — retarget the SYMLINK's owner, never its target.
    pub chown_symlink: fn(&Path, &str) -> io::Result<()>,
    /// `chown -R <user>:<group> <path>`, owner given as `"user:group"`.
    ///
    /// Separate from [`Effects::chown`] because the recursive walk is where the
    /// damage lives: REMEDIATE-01's chown strategy runs it as root over a
    /// directory the operator named. Without a door, `apply_chown -> Ok(())`
    /// (the remediation silently does nothing) and `resolve_user_group ->
    /// Ok((0, 0))` (`chown -R 0:0` over the agent's npm prefix — the EACCES bug
    /// this project exists to eliminate, reported as a completed remediation)
    /// both survived a full mutation run.
    pub chown_recursive: fn(&Path, &str) -> io::Result<()>,
    /// `visudo -cf <path>` — `Err` when the file does not parse.
    pub visudo_validate: fn(&Path) -> io::Result<()>,
    /// The family-correct package install verb.
    pub pkg_install: fn(Family, &[&str]) -> io::Result<()>,
    /// `command -v <name>` — `None` when the program is not on PATH.
    pub which: fn(&str) -> Option<PathBuf>,
    /// Run argv as a user (the dispatcher's `as_user`), so a step's subprocess
    /// FAILURE arms — an npm install that exits non-zero, an `npm ls` that times
    /// out — are reachable without a live npm.
    pub as_user: crate::dispatcher::AsUser,
}

impl Default for Effects {
    fn default() -> Self {
        Self {
            chown: crate::sysio::chown_by_name_nofollow,
            ensure_dir: crate::sysio::ensure_dir,
            chown_symlink: crate::sysio::chown_symlink_by_name,
            chown_recursive: crate::provision::remediate_npm_prefix::chown_recursive_by_name,
            visudo_validate: crate::sysio::visudo_validate,
            pkg_install: crate::pkg::pkg_install,
            which: crate::sysio::which,
            as_user: crate::dispatcher::as_user,
        }
    }
}

impl std::fmt::Debug for Effects {
    /// Hand-written because `Effects` is all function pointers, which have no
    /// useful Debug. The placeholder still has to APPEAR: `ProvisionCtx` derives
    /// Debug and carries one, and a step that logs its context is the main way
    /// an operator sees what a failing provision was working with.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Effects { .. }")
    }
}

#[cfg(test)]
mod effects_debug_tests {
    /// `replace fmt -> std::fmt::Result with Ok(Default::default())` survived,
    /// which renders the field as nothing at all — so a logged context silently
    /// loses it.
    #[test]
    fn effects_renders_a_placeholder_rather_than_nothing() {
        let rendered = format!("{:?}", super::Effects::default());
        assert_eq!(rendered, "Effects { .. }");
        assert!(
            !rendered.is_empty(),
            "an empty Debug makes a logged ProvisionCtx lose the field entirely"
        );
    }
}

/// The context every provisioner step receives — the settled install identity,
/// the distro family, the resolution tokens, and the mutation-gate flags. A step
/// reads what it needs and does I/O; it never re-resolves the user or re-detects
/// the distro (both are settled once in the orchestrator).
#[derive(Debug, Clone)]
pub struct ProvisionCtx {
    /// Filesystem root every system-owned artefact is written under — `/` in
    /// production, a TempDir in tests. The per-user artefacts already route
    /// through `install_home`, so together the two make a step's whole write set
    /// redirectable.
    pub root: PathBuf,
    /// The privileged operations, injected. See [`Effects`].
    pub fx: Effects,
    /// The resolved install user (`--user` > `$AGENTLINUX_USER` > `agent`,
    /// charset+reserved-validated upstream).
    pub install_user: String,
    /// `/home/<install_user>` — derived alongside the user.
    pub install_home: String,
    /// The detected package-manager family (apt↔dnf fork point).
    pub family: Family,
    /// The per-component DECIDE-phase tokens, already narrowed past `Bail`.
    ///
    /// `--yes` is deliberately NOT carried here: consent is resolved once, during
    /// DECIDE, and the answer is already baked into these tokens. A step that
    /// re-read a `yes` flag could reach a different conclusion than the one the
    /// operator was shown.
    pub resolutions: StepResolutions,
}

impl ProvisionCtx {
    /// Resolve an absolute system path (`/etc/sudoers.d`) under [`Self::root`].
    ///
    /// No `root == "/"` fast path: `Path::new("/").join("etc/sudoers.d")` is
    /// already `/etc/sudoers.d`, so the branch bought nothing and cost the one
    /// thing that matters here — it was a surface on which a wrong edit (or a
    /// surviving `==`/`!=` mutant) would silently point every rooted test at the
    /// live filesystem, as root, inside the Docker and QEMU harnesses.
    #[must_use]
    pub fn sys(&self, absolute: &str) -> PathBuf {
        self.root.join(absolute.trim_start_matches('/'))
    }

    /// The production context: the real filesystem root and the real effects.
    #[must_use]
    pub fn new(
        install_user: String,
        install_home: String,
        family: Family,
        resolutions: StepResolutions,
    ) -> Self {
        Self {
            root: PathBuf::from("/"),
            fx: Effects::default(),
            install_user,
            install_home,
            family,
            resolutions,
        }
    }
}

#[cfg(test)]
mod provision_mod_tests {
    use super::*;

    // This module owns the DECIDE→step narrowing the whole provisioner rests on.

    #[test]
    fn the_default_resolutions_are_a_clean_host() {
        let r = Resolutions::default();
        assert_eq!(r.user, Resolution::Create);
        assert_eq!(r.sudoers, Resolution::Create);
        assert_eq!(r.node, Resolution::Create);
        assert_eq!(r.npm_prefix, Resolution::Create);
    }

    #[test]
    fn narrowing_drops_bail_and_names_the_component_that_carried_it() {
        // The one place the "flush ran first" invariant is checked. Every step
        // dispatches on the narrowed type, so a `Bail` that survived the flush
        // must stop the run here rather than reach a step's `_ =>` arm.
        let clean = Resolutions::default().into_step().unwrap();
        assert_eq!(clean.user, StepResolution::Create);

        for (component, mut r) in [
            ("user", Resolutions::default()),
            ("sudoers", Resolutions::default()),
            ("node", Resolutions::default()),
            ("npm-prefix", Resolutions::default()),
        ] {
            match component {
                "user" => r.user = Resolution::Bail,
                "sudoers" => r.sudoers = Resolution::Bail,
                "node" => r.node = Resolution::Bail,
                _ => r.npm_prefix = Resolution::Bail,
            }
            assert_eq!(r.into_step().unwrap_err(), component);
        }
    }

    #[test]
    fn every_non_bail_token_narrows_to_its_own_counterpart() {
        for (wide, narrow_expected) in [
            (Resolution::Create, StepResolution::Create),
            (Resolution::Reuse, StepResolution::Reuse),
            (Resolution::Remediate, StepResolution::Remediate),
            (
                Resolution::ReuseWithWarning,
                StepResolution::ReuseWithWarning,
            ),
        ] {
            let r = Resolutions {
                sudoers: wide,
                ..Default::default()
            };
            assert_eq!(r.into_step().unwrap().sudoers, narrow_expected);
        }
    }

    #[test]
    fn sys_joins_absolute_paths_under_the_root() {
        let ctx = ProvisionCtx::new(
            "agent".into(),
            "/home/agent".into(),
            Family::Debian,
            Resolutions::default().into_step().unwrap(),
        );
        // Production: root is `/`, so a system path is itself.
        assert_eq!(ctx.sys("/etc/sudoers.d"), PathBuf::from("/etc/sudoers.d"));

        let mut rooted = ctx.clone();
        rooted.root = PathBuf::from("/tmp/fixture");
        assert_eq!(
            rooted.sys("/etc/sudoers.d"),
            PathBuf::from("/tmp/fixture/etc/sudoers.d")
        );
        // The leading slash is stripped, never treated as "start from /".
        assert!(rooted.sys("/etc").starts_with("/tmp/fixture"));
    }

    #[test]
    fn a_production_ctx_carries_the_real_root_and_effects() {
        let ctx = ProvisionCtx::new(
            "agent".into(),
            "/home/agent".into(),
            Family::Rhel,
            Resolutions::default().into_step().unwrap(),
        );
        assert_eq!(ctx.root, PathBuf::from("/"));
        // The default effects are the real ones, not a test stub — and the chown
        // is the symlink-refusing variant, not the path-based one. Binding
        // A path-based chown here would compile, pass every step test (they inject
        // their own), and silently reopen the root-follows-a-symlink hole.
        assert!(std::ptr::fn_addr_eq(
            ctx.fx.chown,
            crate::sysio::chown_by_name_nofollow as fn(&Path, &str) -> io::Result<()>
        ));
    }
}
