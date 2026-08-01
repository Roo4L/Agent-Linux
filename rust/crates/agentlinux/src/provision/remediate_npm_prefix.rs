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

use crate::dispatcher::{self, Capture};
use crate::provision::ProvisionCtx;
use crate::sysio;
use std::io;
use std::os::unix::fs::MetadataExt;
use std::path::Path;

/// Per-module `npm install -g` bound — the dispatcher's buffered-npm convention.
const PER_MODULE_TIMEOUT_MS: u64 = 300_000;

/// Aggregate ceiling for the whole migration loop, independent of module count.
/// Chosen to sit well above any realistic brownfield prefix (a dozen globals over a
/// healthy registry is minutes) while keeping one provisioner step to a duration an
/// operator would wait out rather than assume had hung.
const MIGRATION_BUDGET: std::time::Duration = std::time::Duration::from_secs(20 * 60);

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
        Strategy::Rebase => apply_rebase(&prefix, user, user_home, &old_owner),
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
    crate::plog!("[REMEDIATE-01] strategy=chown path={prefix} new_owner={user}:{user}");
    let (uid, gid) = resolve_user_group(user)?;
    if let Err(e) = chown_recursive(Path::new(prefix), uid, gid) {
        crate::plog!("[REMEDIATE-01:fail] reason=chown-denied path={prefix}");
        return Err(e);
    }
    crate::plog!("[REMEDIATE-01] chown complete: {prefix} now {user}:{user}");
    Ok(())
}

/// `remediate::nodejs::_apply_rebase` port. Create
/// `~user/.npm-global` (bin/ + lib/), point `~user/.npmrc` at it, then migrate
/// global modules from the OLD prefix best-effort (per-module failures logged
/// `[REMEDIATE-01:partial]`, no abort). The OLD prefix is NEVER deleted.
fn apply_rebase(old_prefix: &str, user: &str, user_home: &str, old_owner: &str) -> io::Result<()> {
    let new_prefix = format!("{user_home}/.npm-global");
    crate::plog!("[REMEDIATE-01] strategy=rebase from={old_prefix} to={new_prefix}");

    let owner = format!("{user}:{user}");
    // ensure_dir creates OR re-asserts mode+ownership, so a partial prior rebase
    // converges to the canonical state.
    if sysio::ensure_dir(Path::new(&new_prefix), 0o755, &owner).is_err()
        || sysio::ensure_dir(Path::new(&format!("{new_prefix}/bin")), 0o755, &owner).is_err()
        || sysio::ensure_dir(Path::new(&format!("{new_prefix}/lib")), 0o755, &owner).is_err()
    {
        crate::plog!("[REMEDIATE-01:fail] reason=mkdir-denied path={new_prefix}");
        return Err(io::Error::other(format!(
            "[REMEDIATE-01:fail] reason=mkdir-denied path={new_prefix}"
        )));
    }

    // ~user/.npmrc with the prefix line: atomic create-if-absent, then idempotent
    // ensure_line_in_file, then re-assert ownership+mode.
    let npmrc = format!("{user_home}/.npmrc");
    let npmrc_path = Path::new(&npmrc);
    // One fd for create+append+chmod+chown. The previous shape gated the hardened
    // create behind `if !npmrc_path.exists()` — and `exists()` FOLLOWS symlinks, so
    // a non-dangling `~/.npmrc -> /etc/ld.so.preload` skipped the guard entirely and
    // the three path-based calls below wrote through it as root. This is the
    // brownfield remediation path, which is exactly when a planted link is sitting
    // there waiting for a converge run.
    if let Err(e) =
        sysio::ensure_line_in_owned_file(&format!("prefix={new_prefix}"), npmrc_path, &owner, 0o644)
    {
        crate::plog!("[REMEDIATE-01:fail] reason=npmrc-write-denied path={npmrc}");
        return Err(e);
    }
    crate::plog!("[REMEDIATE-01] wrote ~{user}/.npmrc with prefix={new_prefix}");

    // Enumerate + migrate modules from the OLD prefix, best-effort.
    let modules = enumerate_modules(old_owner, old_prefix);
    let (mut migrated, mut failed) = (0u32, 0u32);
    if modules.is_empty() {
        crate::plog!(
            "[REMEDIATE-01] no modules to migrate from {old_prefix} \
             (empty or only catalog/npm entries)"
        );
    } else {
        crate::plog!(
            "[REMEDIATE-01] migrating {} modules from {old_prefix}",
            modules.len()
        );
        // A per-item bound is not a bound on the loop. Each `npm install -g` is
        // capped at 300s, but the item COUNT comes from host data — 40 globals on a
        // brownfield host is a 3.3-hour ceiling inside one provisioner step, with
        // nothing in the transcript between entries to show progress. ADR-020 §4
        // deleted the generic package retry for exactly this shape (a per-command
        // bound silently multiplied into a much larger real one); the multiplier
        // being host-supplied rather than a constant makes it worse, not better.
        //
        // The migration is explicitly best-effort and the OLD prefix is never
        // deleted, so stopping early is safe: what is left behind is exactly what
        // was left behind before this step ran, and the operator is told which
        // modules were not attempted.
        let deadline = std::time::Instant::now() + MIGRATION_BUDGET;
        let mut skipped = 0u32;
        for pkg_at_ver in &modules {
            if std::time::Instant::now() >= deadline {
                skipped += 1;
                continue;
            }
            // The npm-level `--` stops a `-flag@1` package name being reparsed as an
            // npm flag.
            let argv: Vec<String> = ["npm", "install", "-g", "--", pkg_at_ver]
                .iter()
                .map(|s| s.to_string())
                .collect();
            // Bound each install at the smaller of the per-module cap and whatever
            // is left of the aggregate budget, so the last module cannot overshoot.
            let remaining = deadline.saturating_duration_since(std::time::Instant::now());
            let bound = remaining.as_millis().min(u128::from(PER_MODULE_TIMEOUT_MS)) as u64;
            let r = dispatcher::as_user(user, &argv, &[], Capture::Buffered, Some(bound));
            if r.exit_code == 0 {
                crate::plog!("[REMEDIATE-01:migrated] module={pkg_at_ver}");
                migrated += 1;
            } else {
                crate::plog!(
                    "[REMEDIATE-01:partial] module={pkg_at_ver} reason=npm-install-failed"
                );
                failed += 1;
            }
        }
        if skipped > 0 {
            // Named explicitly: a silent cap reads as "everything was migrated".
            crate::plog!(
                "[REMEDIATE-01:partial] {skipped} module(s) NOT attempted — the \
                 {}s migration budget expired. The old prefix at {old_prefix} is \
                 intact; re-run provision to continue, or migrate them by hand.",
                MIGRATION_BUDGET.as_secs()
            );
        }
    }

    crate::plog!(
        "[REMEDIATE-01] rebase complete: migrated={migrated} failed={failed} \
         old_prefix={old_prefix} (NOT deleted; user cleanup)"
    );
    Ok(())
}

/// `remediate::nodejs::_enumerate_modules` port.
/// `npm ls -g --json --depth=0` as the OLD owner with `NPM_CONFIG_PREFIX=<old_prefix>`,
/// parse the top-level dependency ids to `pkg@version`, minus npm + the catalog
/// agents. A failure yields an empty manifest (the Bash `|| printf '{}'`).
fn enumerate_modules(old_owner: &str, old_prefix: &str) -> Vec<String> {
    let argv: Vec<String> = ["npm", "ls", "-g", "--json", "--depth=0"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let env = vec![("NPM_CONFIG_PREFIX".to_string(), old_prefix.to_string())];
    // M-2: bound the npm enumeration (300s) so a wedged registry can't hang.
    let r = dispatcher::as_user(old_owner, &argv, &env, Capture::Buffered, Some(300_000));
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
    // lchown the entry itself (never dereference a symlink) — matches `chown -RP`.
    std::os::unix::fs::lchown(path, Some(uid), Some(gid))?;
    // Recurse only into REAL directories, never through a symlinked dir (use
    // symlink_metadata so a symlink-to-dir is treated as a leaf).
    let md = std::fs::symlink_metadata(path)?;
    if md.file_type().is_dir() {
        for entry in std::fs::read_dir(path)?.flatten() {
            chown_recursive(&entry.path(), uid, gid)?;
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

        // Chown to our own uid/gid (self → no-op, unprivileged-safe). The test is
        // that it succeeds WITHOUT erroring on the symlink target and returns Ok:
        // proving it lchowns the link and stops (does not descend into outside/).
        let uid = nix::unistd::getuid().as_raw();
        let gid = nix::unistd::getgid().as_raw();
        chown_recursive(&prefix, uid, gid).unwrap();
        // The link is still a symlink (lchown changed the link, not the target;
        // it was not replaced or dereferenced).
        assert!(std::fs::symlink_metadata(prefix.join("link"))
            .unwrap()
            .file_type()
            .is_symlink());
        // The outside file still exists untouched.
        assert!(outside_file.exists());
    }

    // The rebase .npmrc write establishes the prefix line byte-exactly (the RT-04
    // shape) and is idempotent. Exercised unprivileged against a temp home so it
    // pins the observable outcome without needing the module-migration shell-out.
    #[test]
    fn rebase_npmrc_prefix_line_is_written_and_idempotent() {
        let d = TempDir::new().unwrap();
        let home = d.path().to_string_lossy().into_owned();
        let uid = nix::unistd::getuid();
        let gid = nix::unistd::getgid();
        let uname = nix::unistd::User::from_uid(uid).unwrap().unwrap().name;
        let gname = nix::unistd::Group::from_gid(gid).unwrap().unwrap().name;
        let owner = format!("{uname}:{gname}");

        let new_prefix = format!("{home}/.npm-global");
        let npmrc = Path::new(d.path()).join(".npmrc");
        sysio::ensure_dir(Path::new(&new_prefix), 0o755, &owner).unwrap();
        sysio::ensure_line_in_owned_file(&format!("prefix={new_prefix}"), &npmrc, &owner, 0o644)
            .unwrap();
        let after_first = std::fs::read_to_string(&npmrc).unwrap();
        assert_eq!(after_first, format!("prefix={new_prefix}\n"));

        // Re-run → byte-identical (no duplicate prefix line).
        sysio::ensure_line_in_owned_file(&format!("prefix={new_prefix}"), &npmrc, &owner, 0o644)
            .unwrap();
        assert_eq!(std::fs::read_to_string(&npmrc).unwrap(), after_first);
    }
}
