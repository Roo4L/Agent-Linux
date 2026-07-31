//! provision/remediate_npm_prefix.rs — REMEDIATE-01 npm-prefix handler, a port of
//! the npm-prefix `chown_or_rebase` remediation (REMEDIATE-01).
//!
//! The state-overwriting action the `RESOLUTIONS[npm-prefix]=remediate` token
//! selects (dispatched from `provision::nodejs::run`). The consent gate has already
//! enforced `--yes` (or registered a bail) upstream before this runs.
//!
//! Strategy selector:
//!  - `chown` — the prefix is UNDER the install user's home AND trivially
//!    salvageable (only allowlisted entries: `lib/`, `bin/`, `share/`, `etc/`,
//!    `package.json`, `package-lock.json`, and `lib/node_modules` empty/absent).
//!    One `chown -R <user>:<user> <prefix>`.
//!  - `rebase` — otherwise (incl. system paths, or a prefix holding third-party
//!    global modules). Create `~user/.npm-global` (bin/ + lib/), point
//!    `~user/.npmrc` at it, migrate global modules best-effort; the OLD prefix is
//!    NEVER deleted.
//!
//! Security: `chown -R` fires ONLY when all three of
//! {prefix-under-home, trivially-salvageable} hold — so system paths (`/usr`,
//! `/usr/local`) and prefixes containing third-party module trees are never chowned;
//! they rebase instead.
//!
//! # Where the prefix and old owner come from
//! The prefix is derived from the canonical `<install_home>/.npm-global`, and
//! the OLD owner from that prefix's on-disk owner — not from a detect-cache
//! record. The observable mutation (chown the tree, or rebase npm's configured
//! prefix and migrate modules) does not depend on which source is used; only the
//! provenance of the "old prefix path" would change.
//!
//! REACHABILITY: this path IS live. `cmd::provision` calls
//! `remediate::decide_core`, which resolves `npm_prefix` to `Remediate` on a
//! brownfield host with a wrongly-owned prefix, and `nodejs::run` then calls
//! `chown_or_rebase` below. It runs as root against a directory the agent user
//! controls — read the Security paragraph before changing anything here.

use crate::dispatcher::Capture;
use crate::provision::ProvisionCtx;
use crate::sysio;
use std::io;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::Path;

/// The catalog agents excluded from module migration (they own their own install),
/// plus `npm` itself — byte-for-byte with the Bash `excluded_json`
const MIGRATION_EXCLUDED: &[&str] = &[
    "npm",
    "@anthropic-ai/claude-code",
    "get-shit-done-cc",
    "@opengsd/gsd-core",
    "@playwright/cli",
];

/// The migration strategy the selector picks.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Strategy {
    Chown,
    Rebase,
}

/// `chown_or_rebase` — the REMEDIATE-01 entry point dispatched from
/// `provision::nodejs::run`. Runs the strategy selector, then chowns or rebases so
/// the prefix is writable by the install user and `npm install -g` never races root
pub fn chown_or_rebase(ctx: &ProvisionCtx) -> io::Result<()> {
    let user = &ctx.install_user;
    let user_home = &ctx.install_home;
    // The EFFECTIVE prefix — the `.npmrc` `prefix=` line if the brownfield host
    // points npm at a foreign location (a root-owned `/usr/local/...` that must
    // rebase), else the canonical `<home>/.npm-global` (an under-home wrong-owner
    // that chowns). Matches the `npm_prefix_state` probe that drove this dispatch.
    let prefix = crate::provision::probe::effective_npm_prefix(user_home);

    if prefix.is_empty() {
        return Err(io::Error::other(
            "[REMEDIATE-01:fail] reason=detect-cache-missing-prefix-path",
        ));
    }

    // The OLD owner (the sudo target for `npm ls -g` — its npm view of the OLD
    // prefix is canonical). Fall back to root when unknown/absent (rebase still
    // works against an empty manifest).
    let old_owner = prefix_owner_user(Path::new(&prefix)).unwrap_or_else(|| "root".to_string());

    match strategy_for(Path::new(&prefix), user_home) {
        Strategy::Chown => apply_chown(&prefix, user),
        Strategy::Rebase => apply_rebase(ctx, &prefix, &old_owner),
    }
}

/// `remediate::nodejs::_strategy_for` port. `chown`
/// only when the prefix is under `user_home` AND trivially salvageable; `rebase`
/// otherwise. Under-home is a literal prefix-match (no readlink) — rebase is the
/// safe default when symlinks would confuse containment.
fn strategy_for(prefix: &Path, user_home: &str) -> Strategy {
    let prefix_str = prefix.to_string_lossy();
    let under_home = prefix_str.starts_with(&format!("{user_home}/"));
    if !under_home {
        return Strategy::Rebase;
    }
    if is_trivially_salvageable(prefix) {
        Strategy::Chown
    } else {
        Strategy::Rebase
    }
}

/// `remediate::nodejs::_is_trivially_salvageable` port.
/// True iff `prefix` contains ONLY allowlisted entries (`lib/`, `bin/`, `share/`,
/// `etc/`, `package.json`, `package-lock.json`) AND `lib/node_modules` is
/// empty/absent. Any non-allowlist entry (e.g. a user-installed module) forces a
/// rebase — this is the gate that prevents chown from clobbering third-party trees.
/// A non-existent prefix is vacuously salvageable.
fn is_trivially_salvageable(prefix: &Path) -> bool {
    if !prefix.is_dir() {
        return true;
    }
    const ALLOWED: &[&str] = &[
        "lib",
        "bin",
        "share",
        "etc",
        "package.json",
        "package-lock.json",
    ];
    let entries = match std::fs::read_dir(prefix) {
        Ok(e) => e,
        Err(_) => return true, // unreadable → the Bash `|| true` treats as no entry
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if !ALLOWED.contains(&name.as_ref()) {
            return false;
        }
    }
    // A populated lib/node_modules/<pkg>/ means a user installed a global module
    // under the prefix — an agent-unwritable third-party tree we must NOT chown.
    let node_modules = prefix.join("lib/node_modules");
    if node_modules.is_dir() {
        if let Ok(mut it) = std::fs::read_dir(&node_modules) {
            if it.next().is_some() {
                return false;
            }
        }
    }
    true
}

/// `remediate::nodejs::_apply_chown` port.
/// `chown -R <user>:<user> <prefix>`. Emits the `[REMEDIATE-01] strategy=chown`
/// marker; a chown failure is a hard error with `[REMEDIATE-01:fail]`.
fn apply_chown(prefix: &str, user: &str) -> io::Result<()> {
    eprintln!("[REMEDIATE-01] strategy=chown path={prefix} new_owner={user}:{user}");
    let (uid, gid) = resolve_user_group(user)?;
    if let Err(e) = chown_recursive(Path::new(prefix), uid, gid) {
        eprintln!("[REMEDIATE-01:fail] reason=chown-denied path={prefix}");
        return Err(e);
    }
    eprintln!("[REMEDIATE-01] chown complete: {prefix} now {user}:{user}");
    Ok(())
}

/// Point `.npmrc` at `prefix`, replacing any existing `prefix=` line and
/// preserving every other line (registry, auth tokens) verbatim. Idempotent: a
/// second call on an already-pointed file rewrites identical bytes.
fn set_npmrc_prefix(npmrc: &Path, prefix: &str) -> io::Result<()> {
    let existing = std::fs::read_to_string(npmrc).unwrap_or_default();
    let mut out: Vec<String> = existing
        .lines()
        .filter(|l| !l.split_once('=').is_some_and(|(k, _)| k.trim() == "prefix"))
        .map(str::to_string)
        .collect();
    out.push(format!("prefix={prefix}"));
    let mut body = out.join("\n");
    body.push('\n');
    sysio::write_file_atomic(0o644, npmrc, body.as_bytes())
}

/// `remediate::nodejs::_apply_rebase` port. Create
/// `~user/.npm-global` (bin/ + lib/), point `~user/.npmrc` at it, then migrate
/// global modules from the OLD prefix best-effort (per-module failures logged
/// `[REMEDIATE-01:partial]`, no abort). The OLD prefix is NEVER deleted.
fn apply_rebase(ctx: &ProvisionCtx, old_prefix: &str, old_owner: &str) -> io::Result<()> {
    let user = &ctx.install_user;
    let user_home = &ctx.install_home;
    let new_prefix = format!("{user_home}/.npm-global");
    eprintln!("[REMEDIATE-01] strategy=rebase from={old_prefix} to={new_prefix}");

    let owner = format!("{user}:{user}");
    // ensure_dir creates OR re-asserts mode+ownership, so a partial prior rebase
    // converges to the canonical state.
    if (ctx.fx.ensure_dir)(Path::new(&new_prefix), 0o755, &owner).is_err()
        || (ctx.fx.ensure_dir)(Path::new(&format!("{new_prefix}/bin")), 0o755, &owner).is_err()
        || (ctx.fx.ensure_dir)(Path::new(&format!("{new_prefix}/lib")), 0o755, &owner).is_err()
    {
        eprintln!("[REMEDIATE-01:fail] reason=mkdir-denied path={new_prefix}");
        return Err(io::Error::other(format!(
            "[REMEDIATE-01:fail] reason=mkdir-denied path={new_prefix}"
        )));
    }

    // ~user/.npmrc with the prefix line: atomic create-if-absent, then idempotent
    // ensure_line_in_file, then re-assert ownership+mode.
    let npmrc = format!("{user_home}/.npmrc");
    let npmrc_path = Path::new(&npmrc);
    if !npmrc_path.exists() {
        if let Err(e) = sysio::create_if_absent_0644(npmrc_path, &owner, ctx.fx.chown) {
            eprintln!("[REMEDIATE-01:fail] reason=npmrc-write-denied path={npmrc}");
            return Err(e);
        }
    }
    // REPLACE any existing `prefix=` line rather than appending a second one.
    // npm honours the LAST prefix line while `probe::effective_npm_prefix` reads
    // the FIRST, so an append left the two disagreeing and REMEDIATE-01 re-ran
    // its whole module migration on every provision, forever.
    set_npmrc_prefix(npmrc_path, &new_prefix)?;
    std::fs::set_permissions(npmrc_path, std::fs::Permissions::from_mode(0o644))?;
    (ctx.fx.chown)(npmrc_path, &owner)?;
    eprintln!("[REMEDIATE-01] wrote ~{user}/.npmrc with prefix={new_prefix}");

    // Enumerate + migrate modules from the OLD prefix, best-effort.
    let modules = enumerate_modules(ctx, old_owner, old_prefix);
    let (mut migrated, mut failed) = (0u32, 0u32);
    if modules.is_empty() {
        eprintln!(
            "[REMEDIATE-01] no modules to migrate from {old_prefix} \
             (empty or only catalog/npm entries)"
        );
    } else {
        eprintln!(
            "[REMEDIATE-01] migrating {} modules from {old_prefix}",
            modules.len()
        );
        for pkg_at_ver in &modules {
            // The npm-level `--` stops a `-flag@1` package name being reparsed as an
            // npm flag.
            let argv: Vec<String> = ["npm", "install", "-g", "--", pkg_at_ver]
                .iter()
                .map(|s| s.to_string())
                .collect();
            // M-2: bound the npm install (300s, the dispatcher's buffered-npm
            // convention) so a wedged/slow registry can't hang provisioning.
            let r = (ctx.fx.as_user)(user, &argv, &[], Capture::Buffered, Some(300_000));
            if r.exit_code == 0 {
                eprintln!("[REMEDIATE-01:migrated] module={pkg_at_ver}");
                migrated += 1;
            } else {
                eprintln!("[REMEDIATE-01:partial] module={pkg_at_ver} reason=npm-install-failed");
                failed += 1;
            }
        }
    }

    eprintln!(
        "[REMEDIATE-01] rebase complete: migrated={migrated} failed={failed} \
         old_prefix={old_prefix} (NOT deleted; user cleanup)"
    );
    Ok(())
}

/// `remediate::nodejs::_enumerate_modules` port.
/// `npm ls -g --json --depth=0` as the OLD owner with `NPM_CONFIG_PREFIX=<old_prefix>`,
/// parse the top-level dependency ids to `pkg@version`, minus npm + the catalog
/// agents. A failure yields an empty manifest (the Bash `|| printf '{}'`).
fn enumerate_modules(ctx: &ProvisionCtx, old_owner: &str, old_prefix: &str) -> Vec<String> {
    let argv: Vec<String> = ["npm", "ls", "-g", "--json", "--depth=0"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let env = vec![("NPM_CONFIG_PREFIX".to_string(), old_prefix.to_string())];
    // M-2: bound the npm enumeration (300s) so a wedged registry can't hang.
    let r = (ctx.fx.as_user)(old_owner, &argv, &env, Capture::Buffered, Some(300_000));
    let raw = if r.exit_code == 0 && !r.stdout.trim().is_empty() {
        r.stdout
    } else {
        "{}".to_string()
    };
    parse_module_manifest(&raw)
}

/// Parse the `npm ls -g --json` output into `pkg@version` lines, excluding the
/// catalog agents + npm. Pure — the JSON-shape half of `_enumerate_modules`
/// (the `jq` filter), unit-testable without a live npm.
fn parse_module_manifest(raw: &str) -> Vec<String> {
    let val: serde_json::Value = match serde_json::from_str(raw) {
        Ok(v) => v,
        Err(_) => return Vec::new(),
    };
    let deps = match val.get("dependencies").and_then(|d| d.as_object()) {
        Some(d) => d,
        None => return Vec::new(),
    };
    deps.iter()
        .filter(|(k, _)| !MIGRATION_EXCLUDED.contains(&k.as_str()))
        .map(|(k, v)| {
            let ver = v
                .get("version")
                .and_then(|s| s.as_str())
                .unwrap_or("latest");
            format!("{k}@{ver}")
        })
        .collect()
}

/// The on-disk owner USER of `path` (the LHS of the Bash `user:group`), resolved
/// from the metadata uid → the passwd name. `None` if the path is absent or the uid
/// has no passwd entry.
fn prefix_owner_user(path: &Path) -> Option<String> {
    let uid = std::fs::metadata(path).ok()?.uid();
    nix::unistd::User::from_uid(nix::unistd::Uid::from_raw(uid))
        .ok()
        .flatten()
        .map(|u| u.name)
}

/// Recursive `chown -R uid:gid <path>` — walks the tree, chowning every entry.
/// Mirrors the Bash `chown -R`'s DEFAULT `-P` mode: symlinks are chowned via
/// `lchown` (the link itself, NOT its target) and are NOT recursed into. This is
/// the security-load-bearing behavior — a symlink under the prefix pointing at a
/// system tree must never cause that tree to be chowned to the install user.
fn chown_recursive(path: &Path, uid: u32, gid: u32) -> io::Result<()> {
    chown_recursive_with(path, uid, gid, &|p, u, g| {
        // lchown the entry itself (never dereference a symlink) — `chown -RP`.
        std::os::unix::fs::lchown(p, Some(u), Some(g))
    })
}

/// [`chown_recursive`] with the per-entry chown injected.
///
/// The seam is what makes the WALK assertable. Chowning to one's own uid is a
/// no-op, so an unprivileged test cannot tell "descended into the symlink and
/// chowned the target" from "stopped at the link" by inspecting owners — the
/// escape-the-prefix bug this guards against was invisible to it. A recording
/// chown makes the visited set the observable instead.
fn chown_recursive_with(
    path: &Path,
    uid: u32,
    gid: u32,
    chown: &dyn Fn(&Path, u32, u32) -> io::Result<()>,
) -> io::Result<()> {
    chown(path, uid, gid)?;
    // Recurse only into REAL directories, never through a symlinked dir (use
    // symlink_metadata so a symlink-to-dir is treated as a leaf).
    let md = std::fs::symlink_metadata(path)?;
    if md.file_type().is_dir() {
        for entry in std::fs::read_dir(path)?.flatten() {
            chown_recursive_with(&entry.path(), uid, gid, chown)?;
        }
    }
    Ok(())
}

/// Resolve `<user>` → its (uid, gid) via the passwd entry (the user's primary group).
fn resolve_user_group(user: &str) -> io::Result<(u32, u32)> {
    let u = nix::unistd::User::from_name(user)
        .map_err(|e| io::Error::other(format!("resolve_user_group: user {user}: {e}")))?
        .ok_or_else(|| io::Error::other(format!("resolve_user_group: unknown user {user}")))?;
    Ok((u.uid.as_raw(), u.gid.as_raw()))
}

#[cfg(test)]
mod remediate_npm_prefix_tests {
    use super::*;
    use crate::dispatcher::DispatchResult;
    use crate::provision::Effects;
    use std::cell::RefCell;
    use std::path::PathBuf;
    use tempfile::TempDir;

    // strategy_for: a prefix OUTSIDE the user home always rebases (system paths
    // like /usr/local are never chowned) — remediate/nodejs.sh:71-73.
    #[test]
    fn strategy_system_path_outside_home_rebases() {
        assert_eq!(
            strategy_for(Path::new("/usr/local"), "/home/agent"),
            Strategy::Rebase
        );
        assert_eq!(
            strategy_for(Path::new("/opt/node"), "/home/agent"),
            Strategy::Rebase
        );
    }

    // strategy_for: a prefix UNDER home that is trivially salvageable → chown.
    #[test]
    fn strategy_under_home_salvageable_chowns() {
        let d = TempDir::new().unwrap();
        let home = d.path().to_string_lossy().into_owned();
        let prefix = d.path().join(".npm-global");
        std::fs::create_dir_all(prefix.join("bin")).unwrap();
        std::fs::create_dir_all(prefix.join("lib")).unwrap();
        assert_eq!(strategy_for(&prefix, &home), Strategy::Chown);
    }

    // strategy_for: a prefix under home holding a THIRD-PARTY global module tree
    // (lib/node_modules/<pkg>) is NOT salvageable → rebase (never chown a
    // third-party tree) — remediate/nodejs.sh:55-60.
    #[test]
    fn strategy_under_home_with_third_party_module_rebases() {
        let d = TempDir::new().unwrap();
        let home = d.path().to_string_lossy().into_owned();
        let prefix = d.path().join(".npm-global");
        std::fs::create_dir_all(prefix.join("lib/node_modules/cowsay")).unwrap();
        assert_eq!(strategy_for(&prefix, &home), Strategy::Rebase);
    }

    // strategy_for: a NON-ALLOWLIST entry at the top level (e.g. a stray file) forces
    // a rebase — remediate/nodejs.sh:42-52.
    #[test]
    fn strategy_under_home_with_stray_entry_rebases() {
        let d = TempDir::new().unwrap();
        let home = d.path().to_string_lossy().into_owned();
        let prefix = d.path().join(".npm-global");
        std::fs::create_dir_all(&prefix).unwrap();
        std::fs::write(prefix.join("random-file.txt"), b"x").unwrap();
        assert_eq!(strategy_for(&prefix, &home), Strategy::Rebase);
    }

    // is_trivially_salvageable: a non-existent prefix is vacuously salvageable
    #[test]
    fn salvageable_missing_prefix_is_vacuously_true() {
        assert!(is_trivially_salvageable(Path::new(
            "/no/such/prefix/agentlinux-xyzzy"
        )));
    }

    // is_trivially_salvageable: an empty lib/node_modules is fine (only becomes
    // unsalvageable once a module directory lands under it).
    #[test]
    fn salvageable_empty_node_modules_ok() {
        let d = TempDir::new().unwrap();
        let prefix = d.path().join(".npm-global");
        std::fs::create_dir_all(prefix.join("lib/node_modules")).unwrap();
        std::fs::create_dir_all(prefix.join("bin")).unwrap();
        assert!(is_trivially_salvageable(&prefix));
    }

    // parse_module_manifest: parses top-level deps to pkg@version, excluding the
    // catalog agents + npm.
    #[test]
    fn parse_manifest_emits_pkg_at_version_excluding_catalog() {
        let raw = r#"{
            "dependencies": {
                "npm": {"version": "10.0.0"},
                "@anthropic-ai/claude-code": {"version": "1.2.3"},
                "cowsay": {"version": "1.6.0"},
                "left-pad": {"version": "1.3.0"}
            }
        }"#;
        let mut mods = parse_module_manifest(raw);
        mods.sort();
        assert_eq!(mods, vec!["cowsay@1.6.0", "left-pad@1.3.0"]);
    }

    // parse_module_manifest: a version-less dep defaults to `latest`; an empty /
    // malformed manifest yields no modules.
    #[test]
    fn parse_manifest_defaults_latest_and_handles_empty() {
        let raw = r#"{"dependencies": {"foo": {}}}"#;
        assert_eq!(parse_module_manifest(raw), vec!["foo@latest"]);
        assert!(parse_module_manifest("{}").is_empty());
        assert!(parse_module_manifest("not json").is_empty());
        assert!(parse_module_manifest(r#"{"dependencies": {}}"#).is_empty());
    }

    // chown_recursive must NOT follow a symlink out of the prefix (chown -RP
    // default): a symlink pointing at a tree the caller does not own must be
    // lchowned as the link, never dereferenced to chown its target. We verify the
    // target file's owner is unchanged after a recursive chown to our OWN uid
    // (running unprivileged, chowning to self is a no-op that still exercises the
    // walk without needing root). The key assertion is that the walk does not
    // recurse THROUGH the symlink — a target OUTSIDE the walked dir is never
    // visited.
    #[test]
    fn chown_recursive_does_not_recurse_through_symlink() {
        let d = TempDir::new().unwrap();
        // outside/ holds a file the walk must never touch.
        let outside = d.path().join("outside");
        std::fs::create_dir_all(&outside).unwrap();
        let outside_file = outside.join("do-not-touch");
        std::fs::write(&outside_file, b"x").unwrap();

        // prefix/ contains a symlink -> outside/. A -R that followed it would visit
        // outside/do-not-touch.
        let prefix = d.path().join("prefix");
        std::fs::create_dir_all(&prefix).unwrap();
        std::os::unix::fs::symlink(&outside, prefix.join("link")).unwrap();

        // Record the visited set instead of inspecting owners: the walk chowns to
        // the CALLER's own uid in this test, so following the link would be an
        // unobservable no-op. This assertion fails if `symlink_metadata` becomes
        // `metadata` — the change that lets a planted symlink hand an arbitrary
        // tree to the install user.
        let visited = std::cell::RefCell::new(Vec::new());
        chown_recursive_with(&prefix, 0, 0, &|p, _u, _g| {
            visited.borrow_mut().push(p.to_path_buf());
            Ok(())
        })
        .unwrap();

        let visited = visited.into_inner();
        assert_eq!(
            visited,
            vec![prefix.clone(), prefix.join("link")],
            "the walk must visit the prefix and the LINK ITSELF, and stop there"
        );
        assert!(
            !visited.contains(&outside_file),
            "descended through the symlink into {}",
            outside_file.display()
        );
    }

    #[test]
    fn chown_recursive_chowns_the_link_not_its_target() {
        // The other half: that the per-entry chown is `lchown`, not `chown`.
        // Owners cannot show this unprivileged, but a DANGLING symlink can —
        // `lchown` succeeds on one, `chown` follows it and fails ENOENT. So this
        // returning Ok is only possible if the link itself is what gets chowned.
        let d = TempDir::new().unwrap();
        let prefix = d.path().join("prefix");
        std::fs::create_dir_all(&prefix).unwrap();
        std::os::unix::fs::symlink(d.path().join("no-such-target"), prefix.join("dangling"))
            .unwrap();

        let uid = nix::unistd::getuid().as_raw();
        let gid = nix::unistd::getgid().as_raw();
        chown_recursive(&prefix, uid, gid)
            .expect("a dangling symlink must be lchowned, not dereferenced");
    }

    // The rebase .npmrc write establishes the prefix line byte-exactly (the RT-04
    // shape) and is idempotent. Exercised unprivileged against a temp home so it
    // pins the observable outcome without needing the module-migration shell-out.
    // --- apply_rebase, driven for real ---
    //
    // The previous test re-typed apply_rebase's body inline (ensure_dir +
    // create_if_absent + ensure_line_in_file) and asserted on its own copy, so it
    // passed if apply_rebase were deleted. With `as_user` injected, the module
    // migration and its failure arms are reachable without a live npm.

    thread_local! {
        static NPM_CALLS: RefCell<Vec<Vec<String>>> = const { RefCell::new(Vec::new()) };
    }

    fn record_npm(argv: &[String]) {
        NPM_CALLS.with(|c| c.borrow_mut().push(argv.to_vec()));
    }

    fn npm_calls() -> Vec<Vec<String>> {
        NPM_CALLS.with(|c| c.borrow().clone())
    }

    thread_local! {
        /// The user and env `npm ls` was invoked with. Recorded because those two
        /// ARE the contract: enumerate as the OLD owner against the OLD prefix.
        /// The stub used to discard both, so the test named after them asserted
        /// only the argv — a compile-time constant naming neither.
        static LS_CONTEXT: RefCell<Option<(String, Vec<(String, String)>)>> =
            const { RefCell::new(None) };
    }

    fn record_ls_context(user: &str, env: &[(String, String)]) {
        LS_CONTEXT.with(|c| *c.borrow_mut() = Some((user.to_string(), env.to_vec())));
    }

    fn ls_context() -> (String, Vec<(String, String)>) {
        LS_CONTEXT
            .with(|c| c.borrow().clone())
            .expect("npm ls must run")
    }

    fn ok(stdout: &str) -> DispatchResult {
        DispatchResult {
            exit_code: 0,
            stdout: stdout.to_string(),
            stderr: String::new(),
            streamed: false,
        }
    }

    /// `npm ls` lists two modules; every `npm install` succeeds.
    fn npm_two_modules(
        u: &str,
        argv: &[String],
        e: &[(String, String)],
        _s: crate::dispatcher::Capture,
        _t: Option<u64>,
    ) -> DispatchResult {
        record_npm(argv);
        if argv.get(1).is_some_and(|a| a == "ls") {
            record_ls_context(u, e);
            ok(r#"{"dependencies":{"tsx":{"version":"4.7.0"},"npm":{"version":"10.0.0"}}}"#)
        } else {
            ok("")
        }
    }

    /// `npm ls` lists one module; the install of it fails.
    fn npm_install_fails(
        _u: &str,
        argv: &[String],
        _e: &[(String, String)],
        _s: crate::dispatcher::Capture,
        _t: Option<u64>,
    ) -> DispatchResult {
        record_npm(argv);
        if argv.get(1).is_some_and(|a| a == "ls") {
            ok(r#"{"dependencies":{"tsx":{"version":"4.7.0"}}}"#)
        } else {
            DispatchResult {
                exit_code: 1,
                stdout: String::new(),
                stderr: "E404".to_string(),
                streamed: false,
            }
        }
    }

    /// `npm ls` times out (the dispatcher maps a buffered timeout to exit 1).
    fn npm_ls_times_out(
        _u: &str,
        argv: &[String],
        _e: &[(String, String)],
        _s: crate::dispatcher::Capture,
        _t: Option<u64>,
    ) -> DispatchResult {
        record_npm(argv);
        DispatchResult {
            exit_code: 1,
            stdout: String::new(),
            stderr: String::new(),
            streamed: false,
        }
    }

    fn rebase_ctx(home: &Path, as_user: crate::dispatcher::AsUser) -> ProvisionCtx {
        NPM_CALLS.with(|c| c.borrow_mut().clear());
        let uid = nix::unistd::getuid();
        let uname = nix::unistd::User::from_uid(uid).unwrap().unwrap().name;
        ProvisionCtx {
            root: PathBuf::from("/"),
            fx: Effects {
                as_user,
                ..Effects::default()
            },
            install_user: uname,
            install_home: home.to_string_lossy().into_owned(),
            family: crate::distro::Family::Debian,
            resolutions: crate::provision::Resolutions::default()
                .into_step()
                .unwrap(),
        }
    }

    #[test]
    fn rebase_creates_the_prefix_and_points_npmrc_at_it() {
        let d = TempDir::new().unwrap();
        let ctx = rebase_ctx(d.path(), npm_two_modules);

        apply_rebase(&ctx, "/usr/local", "root").unwrap();

        let new_prefix = d.path().join(".npm-global");
        assert!(new_prefix.join("bin").is_dir());
        assert!(new_prefix.join("lib").is_dir());
        assert_eq!(
            std::fs::read_to_string(d.path().join(".npmrc")).unwrap(),
            format!("prefix={}\n", new_prefix.display())
        );
    }

    #[test]
    fn rebase_converges_and_preserves_other_npmrc_lines() {
        // The writer used to APPEND a prefix line while the reader took the
        // FIRST match and npm took the LAST, so the effective prefix never
        // changed and REMEDIATE-01 re-migrated every module on every provision.
        let d = TempDir::new().unwrap();
        std::fs::write(
            d.path().join(".npmrc"),
            "prefix=/usr/local\n//registry.npmjs.org/:_authToken=keep-me\n",
        )
        .unwrap();
        let ctx = rebase_ctx(d.path(), npm_two_modules);
        let new_prefix = format!("{}/.npm-global", d.path().display());

        apply_rebase(&ctx, "/usr/local", "root").unwrap();

        let npmrc = std::fs::read_to_string(d.path().join(".npmrc")).unwrap();
        assert_eq!(npmrc.matches("prefix=").count(), 1, "npmrc={npmrc:?}");
        assert!(npmrc.contains("_authToken=keep-me"), "npmrc={npmrc:?}");
        // The probe now agrees with npm: one prefix line, and it is the new one.
        assert_eq!(
            crate::provision::probe::effective_npm_prefix(&ctx.install_home),
            new_prefix
        );

        // A second rebase is a fixed point.
        let before = npmrc.clone();
        apply_rebase(&ctx, "/usr/local", "root").unwrap();
        assert_eq!(
            std::fs::read_to_string(d.path().join(".npmrc")).unwrap(),
            before
        );
    }

    #[test]
    fn rebase_migrates_every_module_except_the_excluded_ones() {
        let d = TempDir::new().unwrap();
        let ctx = rebase_ctx(d.path(), npm_two_modules);

        apply_rebase(&ctx, "/usr/local", "root").unwrap();

        let installs: Vec<Vec<String>> = npm_calls()
            .into_iter()
            .filter(|a| a.get(1).is_some_and(|x| x == "install"))
            .collect();
        // `npm` itself is excluded from migration; tsx is not.
        assert_eq!(installs.len(), 1, "calls={:?}", npm_calls());
        assert_eq!(
            installs[0],
            vec!["npm", "install", "-g", "--", "tsx@4.7.0"]
                .into_iter()
                .map(str::to_string)
                .collect::<Vec<_>>(),
            "the npm-level `--` must precede the package name"
        );
    }

    #[test]
    fn rebase_enumerates_as_the_old_owner_against_the_old_prefix() {
        // The OLD owner's npm view of the OLD prefix is the canonical manifest;
        // enumerating as the NEW user would list the (empty) new prefix.
        let d = TempDir::new().unwrap();
        let ctx = rebase_ctx(d.path(), npm_two_modules);

        apply_rebase(&ctx, "/usr/local", "root").unwrap();

        let ls = npm_calls()
            .into_iter()
            .find(|a| a.get(1).is_some_and(|x| x == "ls"))
            .expect("npm ls must run");
        assert_eq!(ls, vec!["npm", "ls", "-g", "--json", "--depth=0"]);

        // The argv above names neither the user nor the prefix, so it cannot
        // distinguish a correct run from one that enumerates as the NEW user or
        // against the NEW prefix — either of which lists an empty manifest and
        // migrates nothing while reporting success.
        let (user, env) = ls_context();
        assert_eq!(user, "root", "must enumerate as the OLD owner");
        assert_eq!(
            env.iter()
                .find(|(k, _)| k == "NPM_CONFIG_PREFIX")
                .map(|(_, v)| v.as_str()),
            Some("/usr/local"),
            "must enumerate against the OLD prefix, env={env:?}"
        );
    }

    #[test]
    fn a_failed_module_is_partial_not_fatal() {
        // Best-effort migration: one module failing must not abort the rebase,
        // because the npmrc/prefix half has already converged.
        let d = TempDir::new().unwrap();
        let ctx = rebase_ctx(d.path(), npm_install_fails);

        apply_rebase(&ctx, "/usr/local", "root").unwrap();

        assert!(d.path().join(".npm-global/bin").is_dir());
    }

    #[test]
    fn a_timed_out_enumeration_yields_an_empty_manifest() {
        // `npm ls` failing (a timeout maps to a non-zero exit) means "nothing to
        // migrate", never a parse of garbage or an abort.
        let d = TempDir::new().unwrap();
        let ctx = rebase_ctx(d.path(), npm_ls_times_out);

        apply_rebase(&ctx, "/usr/local", "root").unwrap();

        assert!(
            !npm_calls()
                .iter()
                .any(|a| a.get(1).is_some_and(|x| x == "install")),
            "no module may be installed from an empty manifest"
        );
    }
}
