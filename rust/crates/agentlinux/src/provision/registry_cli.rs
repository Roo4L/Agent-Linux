//! provision/registry_cli.rs — port of `plugin/provisioner/50-registry-cli.sh`.
//!
//! The LAST provisioner step (numeric dispatch 10→20→30→40→50): stage the
//! `agentlinux` CLI bundle + the catalog snapshot under `/opt/agentlinux/`,
//! create the empty per-agent state dir (CAT-02 — no agent installed by
//! default), symlink `agentlinux` onto the install user's PATH, and verify the
//! symlink is executable AS the install user.
//!
//! Q1 (58-02, LANDED — DIST-01): this step now stages the static musl bin
//! (`plugin/bin/agentlinux` under the plugin source root) as the default
//! `agentlinux` command, symlinking THAT bin onto the install user's PATH. The
//! TS bundle (`dist/index.js` + `node_modules/`) no longer ships and is no
//! longer staged. Phase 57's `dist/index.js` symlink is replaced; the catalog +
//! recipe + state staging (CAT-01/02/03/05) is UNCHANGED — only the CLI
//! artifact's identity moves from a Node script to a compiled binary.
//!
//! Requirements satisfied (parity with the swapped 50-registry-cli.sh contract):
//!   CLI-01 — `agentlinux` on the install user's PATH (symlink → the musl bin)
//!   CAT-01 / CAT-03 — catalog + recipes staged under /opt/agentlinux/catalog/
//!   CAT-02 — state/installed.d/ created EMPTY (no agent installed here)
//!   CAT-05 — staged catalog byte-identical to the source catalog.json
//!   INST-02 — re-runnable (ensure_dir idempotent; install byte-stable on
//!             identical src; ln -sfn idempotent when the symlink already points
//!             at target — the staged bin's sha256 is stable across a re-run)
//!
//! # Source-tree discovery (the Rust-port seam)
//! The Bash derives `CLI_BUNDLE_SRC`/`CATALOG_SRC` from `BIN_DIR/../{bin,catalog}`
//! (the unpacked tarball's sibling dirs). The Rust bin has no `BIN_DIR`; it
//! resolves the plugin source root from `$AGENTLINUX_SRC_ROOT` (the test harness
//! / release installer sets it) else the container-staged default
//! `/opt/agentlinux-src/plugin` — the ONE place run.sh copies the tree to. The
//! `bin/agentlinux` + `catalog.json` sanity checks match the Bash
//! malformed-tarball guards (return an error, not a panic).

use crate::dispatcher;
use crate::provision::ProvisionCtx;

use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

/// The container-staged plugin source root (run.sh copies /workspace →
/// /opt/agentlinux-src). Overridable via `$AGENTLINUX_SRC_ROOT` for the release
/// installer / a non-default layout.
const DEFAULT_SRC_ROOT: &str = "/opt/agentlinux-src/plugin";

/// Resolve the plugin source root — the Rust analogue of the Bash `BIN_DIR/..`.
/// Precedence:
///   1. `$AGENTLINUX_SRC_ROOT` (nonempty) — the explicit override.
///   2. The running bin's own grandparent, when it looks like a plugin root.
///      The shipped tarball lays the bin at `<plugin>/bin/agentlinux`, so
///      `current_exe()/../..` is the `<plugin>` dir holding `bin/` + `catalog/`.
///      This is what makes the SOLE distribution path work: the curl-installer
///      extracts to `/opt/agentlinux/install/<ver>/plugin` and execs the bin
///      WITHOUT setting the env var (OBS-04) — deriving from the bin's location
///      is the Bash `BIN_DIR/..` behavior the earlier port dropped.
///   3. `DEFAULT_SRC_ROOT` — the container-test default (`run.sh` stages the
///      tree there and runs the provisioner bin from an unrelated off-tree path,
///      so its grandparent is NOT a plugin root and correctly falls through).
fn src_root() -> PathBuf {
    if let Ok(v) = std::env::var("AGENTLINUX_SRC_ROOT") {
        if !v.is_empty() {
            return PathBuf::from(v);
        }
    }
    if let Some(candidate) = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().and_then(Path::parent).map(Path::to_path_buf))
    {
        if looks_like_plugin_root(&candidate) {
            return candidate;
        }
        // Attempted-and-rejected: leave a breadcrumb so a future packaging drift
        // (bin relocated, catalog/ moved) is diagnosable from the provisioner
        // log — instead of surfacing only as a misleading "release tarball
        // malformed?" against the tier-3 default the operator never chose
        // (the OBS-04 class of confusion).
        eprintln!(
            "50-registry-cli: bin-relative src root {} lacks bin/agentlinux+catalog/; \
             falling back to {DEFAULT_SRC_ROOT}",
            candidate.display()
        );
    }
    PathBuf::from(DEFAULT_SRC_ROOT)
}

/// A dir is a plugin root if it holds the two things the staging step copies:
/// the `bin/agentlinux` payload and the `catalog/` tree. Guards the current_exe
/// derivation so an off-tree provisioner bin (run.sh) falls through to the
/// container default instead of pointing staging at a bogus root.
fn looks_like_plugin_root(root: &Path) -> bool {
    root.join("bin/agentlinux").is_file() && root.join("catalog").is_dir()
}

/// Strip a version string down to its bare `X.Y.Z` base for use as an on-disk
/// path segment: drop a leading `v` and anything from the first `-` (pre-release
/// suffix). `v0.4.0-rc1` → `0.4.0`, `v0.4.0` → `0.4.0`, `0.4.0` → `0.4.0`.
///
/// OBS-05: the curl-installer passes `AGENTLINUX_VERSION=<tag>` (e.g.
/// `v0.4.0-rc1`) into `provision`, which drove the `/opt/agentlinux/{cli,catalog}/
/// <ver>/` staging paths. But at RUNTIME the agent shell has no `AGENTLINUX_VERSION`,
/// so the catalog resolver fell back to `CARGO_PKG_VERSION` (`0.4.0`) and looked
/// in a DIFFERENT dir than staging wrote — `agentlinux list` then failed
/// "catalog.json not found". Normalizing both sides to the bare base reconciles
/// them: the release version-lock guarantees the tag base == `CARGO_PKG_VERSION`,
/// so `normalize(tag) == CARGO_PKG_VERSION` and staging == runtime. `run.sh` never
/// caught this because it leaves the var unset (both sides already `0.4.0`).
pub(crate) fn normalize_version(v: &str) -> String {
    let no_v = v.strip_prefix('v').unwrap_or(v);
    // Split on the first `-` (pre-release) OR `+` (SemVer build metadata) so a
    // future `v0.4.0+build.5`-style tag still reduces to the bare base.
    no_v.split(['-', '+']).next().unwrap_or(no_v).to_string()
}

/// The staging version — normalized `$AGENTLINUX_VERSION` else the bin's
/// `CARGO_PKG_VERSION` (synced to plugin/cli/package.json → 0.4.0). MUST match
/// the version `10-installer.bats` reads from package.json AND the runtime
/// `catalog::default_catalog_dir()` resolver so the staged
/// `/opt/agentlinux/{cli,catalog}/<ver>/` paths line up on BOTH sides (OBS-05).
/// Public so the orchestrator's banner, the `--purge` recipe-path derivation,
/// and the runtime catalog resolver all share this one normalized source.
pub fn agentlinux_version() -> String {
    let raw = std::env::var("AGENTLINUX_VERSION")
        .unwrap_or_else(|_| env!("CARGO_PKG_VERSION").to_string());
    let normalized = normalize_version(&raw);
    // A garbage/empty AGENTLINUX_VERSION ("", "v", "-rc1") normalizes to empty,
    // which would corrupt the /opt/agentlinux/<ver>/ layout to a bare trailing
    // slash on BOTH staging and runtime. Fall back to the compiled version
    // (never empty) so the on-disk path is always well-formed.
    if normalized.is_empty() {
        return env!("CARGO_PKG_VERSION").to_string();
    }
    normalized
}

/// `run` — the 50-registry-cli.sh port: stage the payload, then verify the
/// symlink resolves AS THE INSTALL USER (50-registry-cli.sh:137-140, T-04-15).
///
/// The staging half is [`stage`]; the verification shells out through the
/// dispatcher, which is why it is not part of it.
pub fn run(ctx: &ProvisionCtx) -> io::Result<()> {
    let symlink = stage(ctx)?;

    // as_user prepends its own `--`; pass the command + args verbatim.
    let argv: Vec<String> = ["test", "-x", &symlink.to_string_lossy()]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let r = dispatcher::as_user(&ctx.install_user, &argv, &[], false, None);
    if r.exit_code != 0 {
        return Err(io::Error::other(format!(
            "agentlinux symlink not executable as install user '{}' (CLI-01 regression)",
            ctx.install_user
        )));
    }

    eprintln!("50-registry-cli: done (CLI-01 + CAT-01..05 + INST-02 staging complete)");
    Ok(())
}

/// Stage the musl bin, the catalog snapshot, the state dir and the PATH symlink.
/// Returns the symlink path. Every write lands under `ctx.root` and every
/// ownership change goes through `ctx.fx`, so the whole step is drivable from a
/// TempDir — which is what makes "install.sh is executable", "the bin is 0755"
/// and "the state dir belongs to the install user" assertable at all.
pub fn stage(ctx: &ProvisionCtx) -> io::Result<PathBuf> {
    eprintln!("50-registry-cli: starting");

    let user = &ctx.install_user;
    let home = &ctx.install_home;
    let owner = format!("{user}:{user}");
    let version = agentlinux_version();

    let cli_stage_dir = ctx.sys(&format!("/opt/agentlinux/cli/{version}"));
    let catalog_stage_dir = ctx.sys(&format!("/opt/agentlinux/catalog/{version}"));
    let state_dir = ctx.sys("/opt/agentlinux/state");
    let symlink = PathBuf::from(format!("{home}/.npm-global/bin/agentlinux"));

    let root = src_root();
    // DIST-01: the shipped CLI is the static musl bin at plugin/bin/agentlinux
    // (the Wave-1 tarball payload), NOT the TS bundle under plugin/cli/.
    let cli_bin_src = root.join("bin").join("agentlinux");
    let catalog_src = root.join("catalog");

    // Malformed-tarball sanity checks (parity with 50-registry-cli.sh's guards,
    // re-pointed to the musl bin): the release pipeline must have populated the
    // bin. Fail with a clear message so operators know the artifact is malformed,
    // not a runtime bug.
    let cli_bin_meta = fs::symlink_metadata(&cli_bin_src).ok();
    let cli_bin_is_regular = cli_bin_meta
        .as_ref()
        .map(|m| m.file_type().is_file())
        .unwrap_or(false);
    if !cli_bin_is_regular {
        return Err(io::Error::other(format!(
            "agentlinux musl bin missing (or not a regular file) at {} — release tarball malformed?",
            cli_bin_src.display()
        )));
    }
    // The shipped bin must be executable (the static bin is the entrypoint the
    // symlink resolves to; a non-executable bin is a malformed release).
    let cli_bin_executable = cli_bin_meta
        .as_ref()
        .map(|m| m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false);
    if !cli_bin_executable {
        return Err(io::Error::other(format!(
            "agentlinux musl bin at {} is not executable — release tarball malformed?",
            cli_bin_src.display()
        )));
    }
    if !catalog_src.join("catalog.json").is_file() {
        return Err(io::Error::other(format!(
            "catalog.json missing at {} — release tarball malformed?",
            catalog_src.display()
        )));
    }

    // Stage the musl bin under the versioned dir. Layout:
    // /opt/agentlinux/cli/<ver>/bin/agentlinux — the `install -m 0755 -o root
    // -g root` of the single static bin replaces the Bash `cp -R dist/. …`.
    let cli_bin_stage = cli_stage_dir.join("bin").join("agentlinux");
    (ctx.fx.ensure_dir)(&ctx.sys("/opt/agentlinux"), 0o755, "root:root")?;
    if let Some(parent) = cli_stage_dir.parent() {
        (ctx.fx.ensure_dir)(parent, 0o755, "root:root")?;
    }
    (ctx.fx.ensure_dir)(&cli_stage_dir, 0o755, "root:root")?;
    (ctx.fx.ensure_dir)(&cli_stage_dir.join("bin"), 0o755, "root:root")?;
    // `install -m 0755 -o root -g root <bin> <stage>/bin/agentlinux` — the bin
    // is world-executable so any user (incl. the agent via the PATH symlink) can
    // run it; no Node/shebang dispatch (it is a static binary).
    install_file(ctx, &cli_bin_src, &cli_bin_stage, 0o755, "root:root")?;

    // Stage the catalog snapshot (50-registry-cli.sh:103-107).
    (ctx.fx.ensure_dir)(&catalog_stage_dir, 0o755, "root:root")?;
    copy_tree_contents(&catalog_src, &catalog_stage_dir)?;
    chmod_recursive_ugo(&catalog_stage_dir)?;
    // install.sh / uninstall.sh must be executable for the CLI dispatcher.
    chmod_sh_scripts_0755(&catalog_stage_dir.join("agents"))?;

    // State dir — owned by the install user (the CLI writes sentinels via atomic
    // rename). CAT-02: installed.d/ is created EMPTY (50-registry-cli.sh:113-114).
    (ctx.fx.ensure_dir)(&state_dir, 0o755, &owner)?;
    (ctx.fx.ensure_dir)(&state_dir.join("installed.d"), 0o755, &owner)?;

    // Symlink `agentlinux` onto the install user's PATH (50-registry-cli.sh:123-126).
    // ln -sfn (force + no-deref) is idempotent; chown -h retargets the LINK.
    (ctx.fx.ensure_dir)(Path::new(&format!("{home}/.npm-global/bin")), 0o755, &owner)?;
    let symlink_target = cli_bin_stage.clone();
    ln_sfn(&symlink_target, &symlink)?;
    (ctx.fx.chown_symlink)(&symlink, &owner)?;
    eprintln!(
        "50-registry-cli: symlinked {} -> {}",
        symlink.display(),
        symlink_target.display()
    );

    Ok(symlink)
}

/// `cp -R <src>/. <dst>/` — recursively copy the CONTENTS of `src` into the
/// (existing) `dst` dir. Files overwrite; dirs are created. Preserves the file
/// bytes; mode is re-normalized afterward by `chmod_recursive_ugo` (matching the
/// Bash `cp -R` then `chmod -R`). Symlinks are copied as symlinks (cp -R default
/// on a link inside a tree is to copy the link), but our source trees (dist,
/// node_modules, catalog) hold regular files + dirs.
fn copy_tree_contents(src: &Path, dst: &Path) -> io::Result<()> {
    if !dst.is_dir() {
        fs::create_dir_all(dst)?;
    }
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        let from = entry.path();
        let to = dst.join(entry.file_name());
        if file_type.is_dir() {
            copy_tree_contents(&from, &to)?;
        } else if file_type.is_symlink() {
            // Copy the link target verbatim (cp -R copies a symlink as a symlink).
            let target = fs::read_link(&from)?;
            let _ = fs::remove_file(&to);
            std::os::unix::fs::symlink(&target, &to)?;
        } else {
            let _ = fs::remove_file(&to);
            fs::copy(&from, &to)?;
        }
    }
    Ok(())
}

/// `install -m <mode> -o <u> -g <g> <src> <dst>` — copy the file bytes, set the
/// exact mode, chown to owner. Overwrites an existing dst.
fn install_file(
    ctx: &ProvisionCtx,
    src: &Path,
    dst: &Path,
    mode: u32,
    owner: &str,
) -> io::Result<()> {
    let _ = fs::remove_file(dst);
    fs::copy(src, dst)?;
    fs::set_permissions(dst, fs::Permissions::from_mode(mode))?;
    (ctx.fx.chown)(dst, owner)?;
    Ok(())
}

/// `chmod -R u=rwX,go=rX <root>` — dirs (and already-executable files) get the
/// `x` bit; plain files get read-only for group/other and rw for the owner. `X`
/// (conditional execute) applies `x` only to dirs OR files that already have an
/// exec bit set. We reproduce that: a dir → 0755, a file with any exec bit → 0755,
/// else 0644.
fn chmod_recursive_ugo(root: &Path) -> io::Result<()> {
    let meta = fs::symlink_metadata(root)?;
    if meta.file_type().is_symlink() {
        // Do not chmod through a symlink.
        return Ok(());
    }
    if meta.is_dir() {
        fs::set_permissions(root, fs::Permissions::from_mode(0o755))?;
        for entry in fs::read_dir(root)? {
            chmod_recursive_ugo(&entry?.path())?;
        }
    } else {
        let had_exec = meta.permissions().mode() & 0o111 != 0;
        let mode = if had_exec { 0o755 } else { 0o644 };
        fs::set_permissions(root, fs::Permissions::from_mode(mode))?;
    }
    Ok(())
}

/// `find <agents_dir> -name '*.sh' -exec chmod 0755 {} +` — make every recipe
/// script executable. A missing agents dir is a no-op (a catalog with no agents).
fn chmod_sh_scripts_0755(agents_dir: &Path) -> io::Result<()> {
    if !agents_dir.is_dir() {
        return Ok(());
    }
    for entry in fs::read_dir(agents_dir)? {
        let entry = entry?;
        let path = entry.path();
        let ft = entry.file_type()?;
        if ft.is_dir() {
            chmod_sh_scripts_0755(&path)?;
        } else if ft.is_file() && path.extension().is_some_and(|e| e == "sh") {
            fs::set_permissions(&path, fs::Permissions::from_mode(0o755))?;
        }
    }
    Ok(())
}

/// `ln -sfn <target> <link>` — force + no-deref: atomically replace an existing
/// link/file with a symlink to `target`, without chasing through an existing
/// symlink. `remove_file` then `symlink` reproduces `-f` (the symlink syscall
/// itself is not atomic-replace, but this matches the Bash observable: the link
/// ends pointing at target regardless of prior state).
fn ln_sfn(target: &Path, link: &Path) -> io::Result<()> {
    // -n: if `link` is an existing symlink to a directory, do NOT descend into it;
    // removing the link path itself handles that. remove_file removes a symlink
    // (even a dangling one) without touching its target.
    match fs::symlink_metadata(link) {
        Ok(_) => {
            fs::remove_file(link)?;
        }
        Err(e) if e.kind() == io::ErrorKind::NotFound => {}
        Err(e) => return Err(e),
    }
    std::os::unix::fs::symlink(target, link)?;
    Ok(())
}

#[cfg(test)]
mod registry_cli_tests {
    use super::*;
    use crate::provision::{Effects, Resolution, Resolutions};
    use std::cell::RefCell;
    use tempfile::tempdir;

    // --- `stage`, driven end-to-end under a test root ---
    //
    // Twelve tests and none of them ran the step, so "the recipes are
    // executable", "the staged bin is 0755", "the state dir belongs to the
    // install user" and "the symlink points at the staged bin" were all
    // unasserted from Rust.

    thread_local! {
        static OWNERS: RefCell<Vec<(PathBuf, String)>> = const { RefCell::new(Vec::new()) };
    }

    fn fake_chown(path: &Path, owner: &str) -> io::Result<()> {
        OWNERS.with(|c| c.borrow_mut().push((path.to_path_buf(), owner.to_string())));
        Ok(())
    }

    fn fake_ensure_dir(path: &Path, mode: u32, owner: &str) -> io::Result<()> {
        fs::create_dir_all(path)?;
        fs::set_permissions(path, fs::Permissions::from_mode(mode))?;
        fake_chown(path, owner)
    }

    fn owner_of(path: &Path) -> Option<String> {
        OWNERS.with(|c| {
            c.borrow()
                .iter()
                .rev()
                .find(|(p, _)| p == path)
                .map(|(_, o)| o.clone())
        })
    }

    /// Lay out a plausible plugin source root: the musl bin plus a catalog with
    /// one agent carrying an install.sh and a non-executable data file.
    fn plugin_root(at: &Path) -> PathBuf {
        let root = at.join("src/plugin");
        fs::create_dir_all(root.join("bin")).unwrap();
        fs::write(root.join("bin/agentlinux"), b"\x7fELF-ish").unwrap();
        fs::set_permissions(root.join("bin/agentlinux"), fs::Permissions::from_mode(0o755)).unwrap();
        let agent = root.join("catalog/agents/test-dummy");
        fs::create_dir_all(&agent).unwrap();
        fs::write(root.join("catalog/catalog.json"), r#"{"agents":[]}"#).unwrap();
        // Deliberately NOT executable in the source tree — chmod_sh_scripts_0755
        // is what has to fix that.
        fs::write(agent.join("install.sh"), "#!/usr/bin/env bash\n").unwrap();
        fs::set_permissions(agent.join("install.sh"), fs::Permissions::from_mode(0o644)).unwrap();
        fs::write(agent.join("uninstall.sh"), "#!/usr/bin/env bash\n").unwrap();
        fs::set_permissions(agent.join("uninstall.sh"), fs::Permissions::from_mode(0o644)).unwrap();
        fs::write(agent.join("notes.txt"), "not a script\n").unwrap();
        root
    }

    fn ctx_at(root: &Path) -> ProvisionCtx {
        OWNERS.with(|c| c.borrow_mut().clear());
        let home = root.join("home/agent");
        fs::create_dir_all(&home).unwrap();
        ProvisionCtx {
            root: root.to_path_buf(),
            fx: Effects {
                chown: fake_chown,
                ensure_dir: fake_ensure_dir,
                chown_symlink: fake_chown,
                ..Effects::default()
            },
            install_user: "agent".into(),
            install_home: home.to_string_lossy().into_owned(),
            family: crate::distro::Family::Debian,
            resolutions: Resolutions::seed_create(),
            yes: false,
            dry_run: false,
        }
    }

    fn mode_of(path: &Path) -> u32 {
        fs::metadata(path).unwrap().permissions().mode() & 0o7777
    }

    /// Run `stage` with the source root and version pinned via env.
    fn stage_at(root: &Path) -> io::Result<PathBuf> {
        let src = plugin_root(root);
        let mut env_scope = crate::test_support::EnvScope::new();
        env_scope
            .set("AGENTLINUX_SRC_ROOT", &src)
            .set("AGENTLINUX_VERSION", "v9.9.9-rc1");
        stage(&ctx_at(root))
    }

    #[test]
    fn stage_installs_the_musl_bin_0755_root_owned() {
        let d = tempdir().unwrap();
        stage_at(d.path()).unwrap();
        let staged = d.path().join("opt/agentlinux/cli/9.9.9/bin/agentlinux");
        assert!(staged.is_file());
        assert_eq!(mode_of(&staged), 0o755);
        assert_eq!(owner_of(&staged).as_deref(), Some("root:root"));
    }

    #[test]
    fn stage_makes_every_recipe_script_executable() {
        // A staged install.sh that is not executable makes `agentlinux install
        // <anything>` fail at dispatch — and nothing else in the tree checks it.
        let d = tempdir().unwrap();
        stage_at(d.path()).unwrap();
        let agent = d
            .path()
            .join("opt/agentlinux/catalog/9.9.9/agents/test-dummy");
        assert_eq!(mode_of(&agent.join("install.sh")), 0o755);
        assert_eq!(mode_of(&agent.join("uninstall.sh")), 0o755);
        // A non-script data file stays 0644.
        assert_eq!(mode_of(&agent.join("notes.txt")), 0o644);
    }

    #[test]
    fn stage_creates_an_empty_state_dir_owned_by_the_install_user() {
        // CAT-02: installed.d must exist and be EMPTY — no agent is installed by
        // default — and the CLI writes sentinels into it as the install user.
        let d = tempdir().unwrap();
        stage_at(d.path()).unwrap();
        let installed = d.path().join("opt/agentlinux/state/installed.d");
        assert!(installed.is_dir());
        assert_eq!(fs::read_dir(&installed).unwrap().count(), 0);
        assert_eq!(owner_of(&installed).as_deref(), Some("agent:agent"));
    }

    #[test]
    fn stage_symlinks_the_staged_bin_onto_the_users_path() {
        let d = tempdir().unwrap();
        let link = stage_at(d.path()).unwrap();
        assert_eq!(link, d.path().join("home/agent/.npm-global/bin/agentlinux"));
        assert_eq!(
            fs::read_link(&link).unwrap(),
            d.path().join("opt/agentlinux/cli/9.9.9/bin/agentlinux")
        );
        // chown -h, not chown: the LINK is retargeted, never its root-owned target.
        assert_eq!(owner_of(&link).as_deref(), Some("agent:agent"));
    }

    #[test]
    fn stage_replaces_a_stale_symlink_without_following_it() {
        let d = tempdir().unwrap();
        let bin = d.path().join("home/agent/.npm-global/bin");
        fs::create_dir_all(&bin).unwrap();
        std::os::unix::fs::symlink("/opt/agentlinux/cli/0.0.1/bin/agentlinux", bin.join("agentlinux"))
            .unwrap();

        let link = stage_at(d.path()).unwrap();

        assert_eq!(
            fs::read_link(&link).unwrap(),
            d.path().join("opt/agentlinux/cli/9.9.9/bin/agentlinux")
        );
    }

    #[test]
    fn stage_is_idempotent() {
        let d = tempdir().unwrap();
        stage_at(d.path()).unwrap();
        let first = fs::read(d.path().join("opt/agentlinux/cli/9.9.9/bin/agentlinux")).unwrap();
        stage_at(d.path()).unwrap();
        let second = fs::read(d.path().join("opt/agentlinux/cli/9.9.9/bin/agentlinux")).unwrap();
        assert_eq!(first, second);
        assert_eq!(
            mode_of(&d.path().join("opt/agentlinux/cli/9.9.9/bin/agentlinux")),
            0o755
        );
    }

    #[test]
    fn stage_refuses_a_malformed_tarball() {
        // Each guard names the artefact that is wrong, so an operator can tell a
        // bad release from a runtime bug.
        let d = tempdir().unwrap();
        let src = plugin_root(d.path());
        let mut env_scope = crate::test_support::EnvScope::new();
        env_scope
            .set("AGENTLINUX_SRC_ROOT", &src)
            .set("AGENTLINUX_VERSION", "9.9.9");

        // (a) a non-executable bin
        fs::set_permissions(src.join("bin/agentlinux"), fs::Permissions::from_mode(0o644)).unwrap();
        let err = stage(&ctx_at(d.path())).unwrap_err();
        assert!(err.to_string().contains("not executable"), "err={err}");

        // (b) a missing catalog.json
        fs::set_permissions(src.join("bin/agentlinux"), fs::Permissions::from_mode(0o755)).unwrap();
        fs::remove_file(src.join("catalog/catalog.json")).unwrap();
        let err = stage(&ctx_at(d.path())).unwrap_err();
        assert!(err.to_string().contains("catalog.json missing"), "err={err}");

        // (c) a missing bin
        fs::remove_file(src.join("bin/agentlinux")).unwrap();
        let err = stage(&ctx_at(d.path())).unwrap_err();
        assert!(err.to_string().contains("musl bin missing"), "err={err}");
    }

    #[test]
    fn stage_and_the_runtime_resolver_agree_on_the_version_dir() {
        // OBS-05: staging normalized `v9.9.9-rc1` while the runtime resolver read
        // the bare CARGO_PKG_VERSION, so `agentlinux list` looked in a directory
        // staging never wrote. Assert the two land in the SAME place.
        let d = tempdir().unwrap();
        stage_at(d.path()).unwrap();
        let mut env_scope = crate::test_support::EnvScope::new();
        env_scope.set("AGENTLINUX_VERSION", "v9.9.9-rc1");
        assert!(d
            .path()
            .join(format!("opt/agentlinux/catalog/{}", agentlinux_version()))
            .join("catalog.json")
            .is_file());
    }

    #[test]
    fn src_root_honors_env_else_default() {
        let mut env_scope = crate::test_support::EnvScope::new();
        env_scope.unset("AGENTLINUX_SRC_ROOT");
        // With the env var unset the current_exe derivation runs first, but the
        // test runner's own bin is not laid out as a plugin root (no sibling
        // bin/agentlinux + catalog/), so it correctly falls through to the
        // container default.
        assert_eq!(src_root(), PathBuf::from(DEFAULT_SRC_ROOT));
        env_scope.set("AGENTLINUX_SRC_ROOT", "/tmp/x/plugin");
        assert_eq!(src_root(), PathBuf::from("/tmp/x/plugin"));
        env_scope.unset("AGENTLINUX_SRC_ROOT");
    }

    #[test]
    fn looks_like_plugin_root_matches_the_shipped_tarball_layout() {
        // OBS-04 regression: the real curl-installer extracts the tarball to
        // <inst>/plugin (bin/agentlinux + catalog/) and execs the bin WITHOUT
        // AGENTLINUX_SRC_ROOT — so src_root must be able to recognize a plugin
        // root by its payload and derive staging from the bin's own location.
        let dir = tempdir().unwrap();
        let plugin = dir.path().join("plugin");
        // Not a plugin root until BOTH payload markers exist.
        std::fs::create_dir_all(plugin.join("bin")).unwrap();
        assert!(!looks_like_plugin_root(&plugin), "bin/ alone is not a root");
        std::fs::write(plugin.join("bin/agentlinux"), b"#!/bin/true\n").unwrap();
        assert!(
            !looks_like_plugin_root(&plugin),
            "bin/agentlinux without catalog/ is not a root"
        );
        std::fs::create_dir_all(plugin.join("catalog")).unwrap();
        assert!(
            looks_like_plugin_root(&plugin),
            "bin/agentlinux + catalog/ IS the shipped plugin root"
        );
        // A bare unrelated dir is never a plugin root.
        assert!(!looks_like_plugin_root(dir.path()));
    }

    #[test]
    fn agentlinux_version_falls_back_to_cargo_pkg_version() {
        let mut env_scope = crate::test_support::EnvScope::new();
        env_scope.unset("AGENTLINUX_VERSION");
        assert_eq!(agentlinux_version(), env!("CARGO_PKG_VERSION"));
        env_scope.set("AGENTLINUX_VERSION", "9.9.9");
        assert_eq!(agentlinux_version(), "9.9.9");
        env_scope.unset("AGENTLINUX_VERSION");
    }

    #[test]
    fn normalize_version_strips_v_prefix_and_prerelease_suffix() {
        // OBS-05 regression: a release/RC tag must reduce to the bare X.Y.Z base
        // so the staging path == the runtime CARGO_PKG_VERSION lookup.
        assert_eq!(normalize_version("v0.4.0-rc1"), "0.4.0");
        assert_eq!(normalize_version("v0.4.0"), "0.4.0");
        assert_eq!(normalize_version("0.4.0"), "0.4.0");
        assert_eq!(normalize_version("0.4.0-rc.2"), "0.4.0");
        assert_eq!(normalize_version("v9.9.9-test"), "9.9.9");
        // Bare fixture versions bats uses are unaffected.
        assert_eq!(normalize_version("9.9.9"), "9.9.9");
        // SemVer build metadata is stripped too.
        assert_eq!(normalize_version("v0.4.0+build.5"), "0.4.0");
        assert_eq!(normalize_version("v0.4.0-rc1+build.5"), "0.4.0");
    }

    #[test]
    fn agentlinux_version_falls_back_when_normalized_empty() {
        // A garbage AGENTLINUX_VERSION that normalizes to empty must not corrupt
        // the /opt/agentlinux/<ver>/ path — fall back to the compiled version.
        let mut env_scope = crate::test_support::EnvScope::new();
        env_scope.set("AGENTLINUX_VERSION", "v");
        assert_eq!(agentlinux_version(), env!("CARGO_PKG_VERSION"));
        env_scope.set("AGENTLINUX_VERSION", "");
        assert_eq!(agentlinux_version(), env!("CARGO_PKG_VERSION"));
        env_scope.unset("AGENTLINUX_VERSION");
    }

    #[test]
    fn agentlinux_version_normalizes_a_tag_to_its_base() {
        // The curl-installer sets AGENTLINUX_VERSION to the raw tag; staging must
        // resolve to the bare base so it matches the runtime catalog lookup.
        let mut env_scope = crate::test_support::EnvScope::new();
        env_scope.set("AGENTLINUX_VERSION", "v0.4.0-rc1");
        assert_eq!(agentlinux_version(), "0.4.0");
        env_scope.unset("AGENTLINUX_VERSION");
    }

    #[test]
    fn copy_tree_contents_copies_files_and_nested_dirs() {
        let src = tempdir().unwrap();
        let dst = tempdir().unwrap();
        fs::create_dir_all(src.path().join("sub")).unwrap();
        fs::write(src.path().join("a.js"), b"a").unwrap();
        fs::write(src.path().join("sub").join("b.js"), b"b").unwrap();

        copy_tree_contents(src.path(), dst.path()).unwrap();

        assert_eq!(fs::read(dst.path().join("a.js")).unwrap(), b"a");
        assert_eq!(fs::read(dst.path().join("sub").join("b.js")).unwrap(), b"b");
    }

    #[test]
    fn copy_tree_contents_is_byte_stable_on_rerun() {
        let src = tempdir().unwrap();
        let dst = tempdir().unwrap();
        fs::write(src.path().join("catalog.json"), b"{\"x\":1}").unwrap();
        copy_tree_contents(src.path(), dst.path()).unwrap();
        let first = fs::read(dst.path().join("catalog.json")).unwrap();
        // Re-run with identical src → byte-identical dst (INST-02).
        copy_tree_contents(src.path(), dst.path()).unwrap();
        let second = fs::read(dst.path().join("catalog.json")).unwrap();
        assert_eq!(first, second);
    }

    #[test]
    fn chmod_recursive_ugo_dirs_755_plain_files_644() {
        let root = tempdir().unwrap();
        fs::create_dir_all(root.path().join("d")).unwrap();
        fs::write(root.path().join("d").join("f.txt"), b"x").unwrap();
        fs::set_permissions(
            root.path().join("d").join("f.txt"),
            fs::Permissions::from_mode(0o600),
        )
        .unwrap();
        chmod_recursive_ugo(root.path()).unwrap();
        let dmode = fs::metadata(root.path().join("d"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        let fmode = fs::metadata(root.path().join("d").join("f.txt"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(dmode, 0o755);
        assert_eq!(fmode, 0o644);
    }

    #[test]
    fn chmod_recursive_ugo_keeps_exec_bit_on_scripts() {
        let root = tempdir().unwrap();
        let script = root.path().join("run.sh");
        fs::write(&script, b"#!/bin/sh\n").unwrap();
        fs::set_permissions(&script, fs::Permissions::from_mode(0o744)).unwrap();
        chmod_recursive_ugo(root.path()).unwrap();
        let mode = fs::metadata(&script).unwrap().permissions().mode() & 0o777;
        // Had an exec bit → X applies → 0755.
        assert_eq!(mode, 0o755);
    }

    #[test]
    fn ln_sfn_creates_and_retargets_idempotently() {
        let dir = tempdir().unwrap();
        let t1 = dir.path().join("t1");
        let t2 = dir.path().join("t2");
        fs::write(&t1, b"1").unwrap();
        fs::write(&t2, b"2").unwrap();
        let link = dir.path().join("link");

        ln_sfn(&t1, &link).unwrap();
        assert_eq!(fs::read_link(&link).unwrap(), t1);
        // Re-run pointing at the same target — idempotent.
        ln_sfn(&t1, &link).unwrap();
        assert_eq!(fs::read_link(&link).unwrap(), t1);
        // Retarget (force replaces an existing link).
        ln_sfn(&t2, &link).unwrap();
        assert_eq!(fs::read_link(&link).unwrap(), t2);
    }

    #[test]
    fn chmod_sh_scripts_recurses_and_sets_0755() {
        let agents = tempdir().unwrap();
        let dir = agents.path().join("test-dummy");
        fs::create_dir_all(&dir).unwrap();
        let install = dir.join("install.sh");
        fs::write(&install, b"#!/bin/sh\n").unwrap();
        fs::set_permissions(&install, fs::Permissions::from_mode(0o644)).unwrap();
        // A non-.sh file is left alone.
        let readme = dir.join("README.md");
        fs::write(&readme, b"x").unwrap();
        fs::set_permissions(&readme, fs::Permissions::from_mode(0o644)).unwrap();

        chmod_sh_scripts_0755(agents.path()).unwrap();

        assert_eq!(
            fs::metadata(&install).unwrap().permissions().mode() & 0o777,
            0o755
        );
        assert_eq!(
            fs::metadata(&readme).unwrap().permissions().mode() & 0o777,
            0o644
        );
    }
}
