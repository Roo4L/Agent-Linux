//! provision/registry_cli.rs — port of `plugin/provisioner/50-registry-cli.sh`.
//!
//! The LAST provisioner step (numeric dispatch 10→20→30→40→50): stage the
//! `agentlinux` CLI bundle + the catalog snapshot under `/opt/agentlinux/`,
//! create the empty per-agent state dir (CAT-02 — no agent installed by
//! default), symlink `agentlinux` onto the install user's PATH, and verify the
//! symlink is executable AS the install user.
//!
//! Q1 (57-06, LOCKED): this step keeps symlinking the TS bundle's
//! `dist/index.js` — the run.sh harness re-points that symlink at the Rust musl
//! bin under `AGENTLINUX_STAGE_RUST_CLI=1`. The musl-binary swap is Phase 58
//! (DIST-01); this port stays observable-identical to master's TS-bundle staging
//! so the initial state a Rust-provisioned host leaves is byte-compatible with
//! the Bash provisioner (INST-02 re-runs the BASH installer over this state).
//!
//! Requirements satisfied (byte-for-byte with 50-registry-cli.sh):
//!   CLI-01 — `agentlinux` on the install user's PATH (symlink → dist/index.js)
//!   CAT-01 / CAT-03 — catalog + recipes staged under /opt/agentlinux/catalog/
//!   CAT-02 — state/installed.d/ created EMPTY (no agent installed here)
//!   CAT-05 — staged catalog byte-identical to the source catalog.json
//!   INST-02 — re-runnable (ensure_dir idempotent; cp -R byte-stable on identical
//!             src; ln -sfn idempotent when the symlink already points at target)
//!
//! # Source-tree discovery (the Rust-port seam)
//! The Bash derives `CLI_BUNDLE_SRC`/`CATALOG_SRC` from `BIN_DIR/../{cli,catalog}`
//! (the unpacked installer's sibling dirs). The Rust bin has no `BIN_DIR`; it
//! resolves the plugin source root from `$AGENTLINUX_SRC_ROOT` (the test harness
//! / release installer sets it) else the container-staged default
//! `/opt/agentlinux-src/plugin` — the ONE place run.sh copies the tree to. The
//! `dist`/`node_modules`/`package.json`/`catalog.json` sanity checks match the
//! Bash malformed-tarball guards (return an error, not a panic).

use crate::dispatcher;
use crate::provision::ProvisionCtx;
use crate::sysio;
use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

/// The container-staged plugin source root (run.sh copies /workspace →
/// /opt/agentlinux-src). Overridable via `$AGENTLINUX_SRC_ROOT` for the release
/// installer / a non-default layout.
const DEFAULT_SRC_ROOT: &str = "/opt/agentlinux-src/plugin";

/// Resolve the plugin source root: `$AGENTLINUX_SRC_ROOT` (nonempty) else the
/// container default. This is the Rust analogue of the Bash `BIN_DIR/..`.
fn src_root() -> PathBuf {
    match std::env::var("AGENTLINUX_SRC_ROOT") {
        Ok(v) if !v.is_empty() => PathBuf::from(v),
        _ => PathBuf::from(DEFAULT_SRC_ROOT),
    }
}

/// The staging version — `$AGENTLINUX_VERSION` else the bin's `CARGO_PKG_VERSION`
/// (synced to plugin/cli/package.json → 0.3.6). MUST match the version
/// `10-installer.bats` reads from package.json so the staged
/// `/opt/agentlinux/{cli,catalog}/<ver>/` paths line up. Public so the
/// orchestrator's banner + `--purge` recipe-path derivation share the one source.
pub fn agentlinux_version() -> String {
    std::env::var("AGENTLINUX_VERSION").unwrap_or_else(|_| env!("CARGO_PKG_VERSION").to_string())
}

/// `run` — the 50-registry-cli.sh port.
pub fn run(ctx: &ProvisionCtx) -> io::Result<()> {
    eprintln!("50-registry-cli: starting");

    let user = &ctx.install_user;
    let home = &ctx.install_home;
    let owner = format!("{user}:{user}");
    let version = agentlinux_version();

    let cli_stage_dir = PathBuf::from(format!("/opt/agentlinux/cli/{version}"));
    let catalog_stage_dir = PathBuf::from(format!("/opt/agentlinux/catalog/{version}"));
    let state_dir = PathBuf::from("/opt/agentlinux/state");
    let symlink = PathBuf::from(format!("{home}/.npm-global/bin/agentlinux"));

    let root = src_root();
    let cli_bundle_src = root.join("cli");
    let catalog_src = root.join("catalog");

    // Malformed-tarball sanity checks (50-registry-cli.sh:62-77): the build
    // pipeline must have populated the bundle. Fail with a clear message so
    // operators know the artifact is malformed, not a runtime bug.
    let dist_index = cli_bundle_src.join("dist").join("index.js");
    if !dist_index.is_file() {
        return Err(io::Error::other(format!(
            "CLI dist/index.js missing at {} — release tarball malformed?",
            cli_bundle_src.join("dist").display()
        )));
    }
    if !cli_bundle_src.join("node_modules").is_dir() {
        return Err(io::Error::other(format!(
            "CLI node_modules missing at {} — release tarball malformed?",
            cli_bundle_src.join("node_modules").display()
        )));
    }
    if !cli_bundle_src.join("package.json").is_file() {
        return Err(io::Error::other(format!(
            "CLI package.json missing at {} — release tarball malformed?",
            cli_bundle_src.join("package.json").display()
        )));
    }
    if !catalog_src.join("catalog.json").is_file() {
        return Err(io::Error::other(format!(
            "catalog.json missing at {} — release tarball malformed?",
            catalog_src.display()
        )));
    }

    // Stage the CLI bundle under the versioned dir (50-registry-cli.sh:84-97).
    // Layout: /opt/agentlinux/cli/<ver>/{dist/,node_modules/,package.json}.
    sysio::ensure_dir(Path::new("/opt/agentlinux"), 0o755, "root:root")?;
    if let Some(parent) = cli_stage_dir.parent() {
        sysio::ensure_dir(parent, 0o755, "root:root")?;
    }
    sysio::ensure_dir(&cli_stage_dir, 0o755, "root:root")?;
    sysio::ensure_dir(&cli_stage_dir.join("dist"), 0o755, "root:root")?;
    sysio::ensure_dir(&cli_stage_dir.join("node_modules"), 0o755, "root:root")?;
    // `cp -R <src>/. <dst>/` — copy the DIRECTORY CONTENTS into the existing dst
    // (not nested under a src-named subdir), matching the Bash `cp -R dist/. dst/`.
    copy_tree_contents(&cli_bundle_src.join("dist"), &cli_stage_dir.join("dist"))?;
    copy_tree_contents(
        &cli_bundle_src.join("node_modules"),
        &cli_stage_dir.join("node_modules"),
    )?;
    // `install -m 0644 -o root -g root package.json <stage>/package.json`.
    install_file(
        &cli_bundle_src.join("package.json"),
        &cli_stage_dir.join("package.json"),
        0o644,
        "root:root",
    )?;
    // `chmod -R u=rwX,go=rX` — dirs get x, files don't (X = conditional exec).
    chmod_recursive_ugo(&cli_stage_dir)?;
    // The entrypoint needs exec for all users; the shebang handles node dispatch.
    fs::set_permissions(
        cli_stage_dir.join("dist").join("index.js"),
        fs::Permissions::from_mode(0o755),
    )?;

    // Stage the catalog snapshot (50-registry-cli.sh:103-107).
    sysio::ensure_dir(&catalog_stage_dir, 0o755, "root:root")?;
    copy_tree_contents(&catalog_src, &catalog_stage_dir)?;
    chmod_recursive_ugo(&catalog_stage_dir)?;
    // install.sh / uninstall.sh must be executable for the CLI dispatcher.
    chmod_sh_scripts_0755(&catalog_stage_dir.join("agents"))?;

    // State dir — owned by the install user (the CLI writes sentinels via atomic
    // rename). CAT-02: installed.d/ is created EMPTY (50-registry-cli.sh:113-114).
    sysio::ensure_dir(&state_dir, 0o755, &owner)?;
    sysio::ensure_dir(&state_dir.join("installed.d"), 0o755, &owner)?;

    // Symlink `agentlinux` onto the install user's PATH (50-registry-cli.sh:123-126).
    // ln -sfn (force + no-deref) is idempotent; chown -h retargets the LINK.
    sysio::ensure_dir(Path::new(&format!("{home}/.npm-global/bin")), 0o755, &owner)?;
    let symlink_target = cli_stage_dir.join("dist").join("index.js");
    ln_sfn(&symlink_target, &symlink)?;
    chown_symlink(&symlink, &owner)?;
    eprintln!(
        "50-registry-cli: symlinked {} -> {}",
        symlink.display(),
        symlink_target.display()
    );

    // Verify the symlink resolves + is executable AS THE INSTALL USER
    // (50-registry-cli.sh:137-140, T-04-15). as_user prepends its own `--`; pass
    // the command + args verbatim without a leading `--`.
    let argv: Vec<String> = ["test", "-x", &symlink.to_string_lossy()]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let r = dispatcher::as_user(user, &argv, &[], false, None);
    if r.exit_code != 0 {
        return Err(io::Error::other(format!(
            "agentlinux symlink not executable as install user '{user}' (CLI-01 regression)"
        )));
    }

    eprintln!("50-registry-cli: done (CLI-01 + CAT-01..05 + INST-02 staging complete)");
    Ok(())
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
fn install_file(src: &Path, dst: &Path, mode: u32, owner: &str) -> io::Result<()> {
    let _ = fs::remove_file(dst);
    fs::copy(src, dst)?;
    fs::set_permissions(dst, fs::Permissions::from_mode(mode))?;
    chown_path(dst, owner)?;
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

/// `chown <owner> <path>` on a regular path (follows nothing special; the file
/// is a plain file/dir). Resolves `user:group` → uid/gid.
fn chown_path(path: &Path, owner: &str) -> io::Result<()> {
    let (uid, gid) = resolve_owner(owner)?;
    std::os::unix::fs::chown(path, Some(uid), Some(gid))
        .map_err(|e| io::Error::other(format!("chown {} failed: {e}", path.display())))
}

/// `chown -h <owner> <link>` — change the SYMLINK itself, not its target.
fn chown_symlink(link: &Path, owner: &str) -> io::Result<()> {
    let (uid, gid) = resolve_owner(owner)?;
    std::os::unix::fs::lchown(link, Some(uid), Some(gid))
        .map_err(|e| io::Error::other(format!("chown -h {} failed: {e}", link.display())))
}

/// Resolve `"user:group"` → `(uid, gid)` via the passwd/group DBs (mirrors
/// `sysio::resolve_owner`, which is private to that module).
fn resolve_owner(owner: &str) -> io::Result<(u32, u32)> {
    let (user, group) = owner
        .split_once(':')
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "owner must be user:group"))?;
    let uid = nix::unistd::User::from_name(user)
        .map_err(|e| io::Error::other(format!("resolve_owner: user {user}: {e}")))?
        .ok_or_else(|| io::Error::other(format!("resolve_owner: unknown user {user}")))?
        .uid
        .as_raw();
    let gid = nix::unistd::Group::from_name(group)
        .map_err(|e| io::Error::other(format!("resolve_owner: group {group}: {e}")))?
        .ok_or_else(|| io::Error::other(format!("resolve_owner: unknown group {group}")))?
        .gid
        .as_raw();
    Ok((uid, gid))
}

#[cfg(test)]
mod registry_cli_tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn src_root_honors_env_else_default() {
        let _g = crate::test_support::env_guard();
        std::env::remove_var("AGENTLINUX_SRC_ROOT");
        assert_eq!(src_root(), PathBuf::from(DEFAULT_SRC_ROOT));
        std::env::set_var("AGENTLINUX_SRC_ROOT", "/tmp/x/plugin");
        assert_eq!(src_root(), PathBuf::from("/tmp/x/plugin"));
        std::env::remove_var("AGENTLINUX_SRC_ROOT");
    }

    #[test]
    fn agentlinux_version_falls_back_to_cargo_pkg_version() {
        let _g = crate::test_support::env_guard();
        std::env::remove_var("AGENTLINUX_VERSION");
        assert_eq!(agentlinux_version(), env!("CARGO_PKG_VERSION"));
        std::env::set_var("AGENTLINUX_VERSION", "9.9.9");
        assert_eq!(agentlinux_version(), "9.9.9");
        std::env::remove_var("AGENTLINUX_VERSION");
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
