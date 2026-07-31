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
/// The REMEDIATE-01 entry point, and the ONLY one production calls — `nodejs::run`
/// dispatches here, never to [`chown_or_rebase_with`].
///
/// It carried a skip claiming its two host reads made it unobservable. That was
/// false: `effective_npm_prefix` reads only under `ctx.install_home`, and on the
/// Chown arm `prefix_owner_user`'s value is never used. Against a TempDir home
/// the whole function is hermetic, so `-> Ok(())` — REMEDIATE-01 dispatches,
/// nothing happens, the prefix stays root-owned, provision reports success — is
/// killable on any host, and the skip was the only thing keeping it out of the
/// gate. That also means the module's reported score counted it as absent rather
/// than caught.
///
/// The second wrongly-justified skip in as many rounds (after
/// `cmd::provision::resolve_wrong_shell`), and the same mistake as `apply_chown`
/// vs this function: killed one frame down, excused one frame up. ADR-020 §4
/// forbids a skip that hides a killable mutant precisely because it makes the
/// enforcing gate lie about itself.
pub fn chown_or_rebase(ctx: &ProvisionCtx) -> io::Result<()> {
    let user_home = &ctx.install_home;
    // The EFFECTIVE prefix — the `.npmrc` `prefix=` line if the brownfield host
    // points npm at a foreign location (a root-owned `/usr/local/...` that must
    // rebase), else the canonical `<home>/.npm-global` (an under-home wrong-owner
    // that chowns). Matches the `npm_prefix_state` probe that drove this dispatch.
    //
    // The OLD owner is the sudo target for `npm ls -g` — its npm view of the OLD
    // prefix is canonical. Falls back to root when unknown/absent (rebase still
    // works against an empty manifest).
    let prefix = crate::provision::probe::effective_npm_prefix(user_home);
    let old_owner = prefix_owner_user(Path::new(&prefix)).unwrap_or_else(|| "root".to_string());
    chown_or_rebase_with(ctx, &prefix, &old_owner)
}

/// [`chown_or_rebase`] over the two host facts it reads.
///
/// Split for the reason its siblings are (`resolve_wrong_shell_with`,
/// `decide_core_with`, `should_prompt_from`): both reads sat between the `ctx`
/// seam and the decision, so `chown_or_rebase -> Ok(())` survived — REMEDIATE-01
/// dispatched, nothing happened, the prefix stayed root-owned, and
/// `agentlinux provision` printed "complete" and exited 0. That is byte-for-byte
/// the observable an earlier commit claimed to have eliminated; it had killed it
/// on `apply_chown` and left it alive on the only caller.
///
/// Nothing else here could be stated either: which strategy is wired to which
/// verb. Swapping the two match arms sends `chown -R` at `/usr/local`.
fn chown_or_rebase_with(ctx: &ProvisionCtx, prefix: &str, old_owner: &str) -> io::Result<()> {
    if prefix.is_empty() {
        return Err(io::Error::other(
            "[REMEDIATE-01:fail] reason=detect-cache-missing-prefix-path",
        ));
    }

    match strategy_for(Path::new(prefix), &ctx.install_home) {
        Strategy::Chown => apply_chown(ctx, prefix, &ctx.install_user),
        Strategy::Rebase => apply_rebase(ctx, prefix, old_owner),
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
///
/// Takes `ctx` for the same reason `apply_rebase` does. It used to call
/// `resolve_user_group` + `chown_recursive` directly, which meant the whole
/// strategy=chown arm had no door: `strategy_for` decided correctly WHICH arm to
/// take and then nothing observed what that arm did. Both
/// `apply_chown -> Ok(())` — the remediation silently does nothing, the prefix
/// stays root-owned, and the provisioner reports success — and
/// `resolve_user_group -> Ok((0, 0))` — `chown -R 0:0` over the agent's own npm
/// prefix — survived a full mutation run with the suite green.
fn apply_chown(ctx: &ProvisionCtx, prefix: &str, user: &str) -> io::Result<()> {
    eprintln!("[REMEDIATE-01] strategy=chown path={prefix} new_owner={user}:{user}");
    let owner = format!("{user}:{user}");
    if let Err(e) = (ctx.fx.chown_recursive)(Path::new(prefix), &owner) {
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
    // No outer `if !exists()`: `create_if_absent_0644` returns early when the
    // path is present, and the mode and owner are re-asserted unconditionally
    // below either way — so the guard changed nothing observable and its mutant
    // (`delete !`) was equivalent by construction. Deleting the branch removes
    // the mutant rather than annotating it, which is the better of the two.
    if let Err(e) = sysio::create_if_absent_0644(npmrc_path, &owner, ctx.fx.chown) {
        eprintln!("[REMEDIATE-01:fail] reason=npmrc-write-denied path={npmrc}");
        return Err(e);
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
        let tally = migrate_modules(ctx, user, &modules, &mut |m| eprintln!("{m}"));
        migrated = tally.0;
        failed = tally.1;
    }

    eprintln!(
        "[REMEDIATE-01] rebase complete: migrated={migrated} failed={failed} \
         old_prefix={old_prefix} (NOT deleted; user cleanup)"
    );
    Ok(())
}

/// Install each module as the install user, returning `(migrated, failed)`.
///
/// Split out because the counters and the operator-facing markers are the only
/// record of what a rebase actually moved, and both went to a global `eprintln!`
/// where nothing could read them back. Three mutants survived: `== -> !=`, which
/// logs a SUCCESSFUL install as `[REMEDIATE-01:partial] reason=npm-install-failed`
/// and a failed one as `[REMEDIATE-01:migrated]`; and `+= -> *=` on each counter,
/// which — since both start at 0 — makes the summary read `migrated=0 failed=0`
/// however the run went.
fn migrate_modules(
    ctx: &ProvisionCtx,
    user: &str,
    modules: &[String],
    log: &mut dyn FnMut(&str),
) -> (u32, u32) {
    let (mut migrated, mut failed) = (0u32, 0u32);
    for pkg_at_ver in modules {
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
            log(&format!("[REMEDIATE-01:migrated] module={pkg_at_ver}"));
            migrated += 1;
        } else {
            log(&format!(
                "[REMEDIATE-01:partial] module={pkg_at_ver} reason=npm-install-failed"
            ));
            failed += 1;
        }
    }
    (migrated, failed)
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
    parse_module_manifest(&manifest_or_empty(r.exit_code, &r.stdout))
}

/// The raw manifest to parse: `npm ls`'s stdout only when it BOTH succeeded and
/// produced something, else the empty object (the Bash `|| printf '{}'`).
///
/// Both conditions, not either: `&& -> ||` survived because the one fixture for
/// this returned exit 1 AND empty stdout, satisfying neither disjunct. Under the
/// mutant a failed or timed-out `npm ls` whose stdout carries a truncated JSON
/// prefix gets parsed as if it were a complete manifest.
fn manifest_or_empty(exit_code: i32, stdout: &str) -> String {
    if exit_code == 0 && !stdout.trim().is_empty() {
        stdout.to_string()
    } else {
        "{}".to_string()
    }
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
/// Not mutation-tested: a real `stat` plus a real passwd lookup, with no
/// injection point — an ADR-019 §5 seam gap, not an adapter over tested halves.
/// Its three mutants matter (`Some("xyzzy")` enumerates as a user nobody holds,
/// so the manifest comes back empty and a rebase migrates NOTHING while
/// reporting success), so this is debt, not a decision: closing it means giving
/// `chown_or_rebase` the owner as a parameter all the way from the caller.
#[cfg_attr(test, mutants::skip)]
fn prefix_owner_user(path: &Path) -> Option<String> {
    let uid = std::fs::metadata(path).ok()?.uid();
    nix::unistd::User::from_uid(nix::unistd::Uid::from_raw(uid))
        .ok()
        .flatten()
        .map(|u| u.name)
}

/// The production [`Effects::chown_recursive`]: resolve `"user:group"` through
/// the passwd DB, then walk. The two halves it composes are both tested —
/// [`resolve_user_group`] against a name no host has, and the walk through
/// [`chown_recursive_with`] — so this line binds them and nothing else.
pub fn chown_recursive_by_name(path: &Path, owner: &str) -> io::Result<()> {
    let user = owner.split(':').next().unwrap_or(owner);
    let (uid, gid) = resolve_user_group(user)?;
    chown_recursive(path, uid, gid)
}

/// Recursive `chown -R uid:gid <path>` — walks the tree, chowning every entry.
/// Mirrors the Bash `chown -R`'s DEFAULT `-P` mode: symlinks are chowned via
/// `lchown` (the link itself, NOT its target) and are NOT recursed into. This is
/// the security-load-bearing behavior — a symlink under the prefix pointing at a
/// system tree must never cause that tree to be chowned to the install user.
/// Not mutation-tested: this binds the real `lchown` to the walk and does
/// nothing else (ADR-019 §5). The WALK — the security-load-bearing half, which
/// must not follow a symlink out of the prefix — is asserted through
/// [`chown_recursive_with`] with a recording chown; observing this one would
/// need a real foreign uid, i.e. root.
#[cfg_attr(test, mutants::skip)]
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

    /// The user a dispatch ran as, and the env it carried.
    type DispatchContext = (String, Vec<(String, String)>);

    thread_local! {
        /// The user and env `npm ls` was invoked with. Recorded because those two
        /// ARE the contract: enumerate as the OLD owner against the OLD prefix.
        /// The stub used to discard both, so the test named after them asserted
        /// only the argv — a compile-time constant naming neither.
        static LS_CONTEXT: RefCell<Option<DispatchContext>> = const { RefCell::new(None) };
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

    thread_local! {
        /// The `(path, mode, owner)` of every `ensure_dir` the rebase asked for.
        static DIRS: RefCell<Vec<(String, u32, String)>> = const { RefCell::new(Vec::new()) };
        /// The `(path, owner)` of every plain and every RECURSIVE chown.
        static CHOWNS: RefCell<Vec<(String, String)>> = const { RefCell::new(Vec::new()) };
    }

    /// `ensure_dir` that performs the CREATE and the MODE but records the owner
    /// instead of chowning.
    ///
    /// The real `sysio::ensure_dir` resolves `"user:group"` through the passwd
    /// AND group DBs. `apply_rebase` builds that string as `format!("{user}:{user}")`,
    /// so taking `Effects::default()` here made these tests require the runner's
    /// primary group to be NAMED the same as the runner. Root satisfies that
    /// (`root:root`) and so does every user-private-group distro, so it was green
    /// in CI and in both harnesses — and failed on any host where the invoking
    /// user's primary group is `users` or `staff`, with `[REMEDIATE-01:fail]
    /// reason=mkdir-denied` saying nothing about groups. A seam was present and
    /// the fixture declined it.
    fn recording_ensure_dir(p: &Path, mode: u32, owner: &str) -> io::Result<()> {
        DIRS.with(|d| {
            d.borrow_mut()
                .push((p.to_string_lossy().into_owned(), mode, owner.to_string()))
        });
        if !p.is_dir() {
            std::fs::create_dir_all(p)?;
        }
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(p, std::fs::Permissions::from_mode(mode))
    }

    fn dirs_created() -> Vec<(String, u32, String)> {
        DIRS.with(|d| d.borrow().clone())
    }

    /// The same reasoning as `recording_ensure_dir`, one line down.
    ///
    /// `apply_rebase` also chowns `~user/.npmrc` through `ctx.fx.chown`, and the
    /// first version of this fixture left that at `Effects::default()` — so six
    /// tests still resolved `"agent:agent"` through the real passwd and group
    /// DBs and passed only because the runner happens to be a uid named `agent`
    /// in a gid named `agent`, making the chown a permitted self-chown. On any
    /// other login they fail with `reason=npmrc-write-denied`, which says nothing
    /// about names. Recording it means a fabricated fixture user works.
    fn recording_chown(p: &Path, owner: &str) -> io::Result<()> {
        CHOWNS.with(|c| {
            c.borrow_mut()
                .push((p.to_string_lossy().into_owned(), owner.to_string()))
        });
        Ok(())
    }

    fn chowns() -> Vec<(String, String)> {
        CHOWNS.with(|c| c.borrow().clone())
    }

    /// An install user no passwd DB contains: every owner-taking effect in the
    /// rebase path must be injected, so nothing here may resolve a real name.
    const FIXTURE_USER: &str = "agentlinux-fixture-user";

    fn rebase_ctx(home: &Path, as_user: crate::dispatcher::AsUser) -> ProvisionCtx {
        NPM_CALLS.with(|c| c.borrow_mut().clear());
        DIRS.with(|d| d.borrow_mut().clear());
        CHOWNS.with(|c| c.borrow_mut().clear());
        ProvisionCtx {
            root: PathBuf::from("/"),
            fx: Effects {
                as_user,
                ensure_dir: recording_ensure_dir,
                chown: recording_chown,
                chown_recursive: recording_chown,
                ..Effects::default()
            },
            // A name NO host has, deliberately. A literal that happens to match
            // the runner ("agent" on this box) still passes when a chown escapes
            // the seam, because chowning a file to its own owner succeeds — so
            // the fixture would keep the coupling it was written to remove.
            install_user: FIXTURE_USER.to_string(),
            install_home: home.to_string_lossy().into_owned(),
            family: crate::distro::Family::Debian,
            resolutions: crate::provision::Resolutions::default()
                .into_step()
                .unwrap(),
        }
    }

    // The strategy=chown arm. `strategy_for` is well covered, so the code decided
    // correctly WHICH arm to take and then nothing observed what that arm did:
    // `apply_chown -> Ok(())` (the remediation silently does nothing; the prefix
    // stays root-owned and the provisioner reports success) and
    // `resolve_user_group -> Ok((0, 0))` (`chown -R 0:0` over the agent's own npm
    // prefix — the EACCES bug AgentLinux exists to eliminate, handed back as a
    // completed remediation) both survived a full mutation run.

    #[test]
    fn the_selector_wires_each_strategy_to_its_own_verb() {
        // `strategy_for` is exhaustively tested and both verbs are driven, but
        // nothing observed that the selector connects the right one to the right
        // verdict — `chown_or_rebase -> Ok(())` survived, i.e. REMEDIATE-01
        // dispatches, nothing happens, and provision reports success. And
        // swapping the two match arms sends `chown -R` at /usr/local.
        let d = TempDir::new().unwrap();
        let home = d.path().to_string_lossy().into_owned();

        // Under home and trivially salvageable -> CHOWN, and the rebase verb's
        // npm dispatch must not fire.
        let under = d.path().join(".npm-global");
        std::fs::create_dir_all(&under).unwrap();
        let ctx = rebase_ctx(d.path(), npm_two_modules);
        chown_or_rebase_with(&ctx, &under.to_string_lossy(), "root").unwrap();
        assert_eq!(
            chowns(),
            vec![(
                under.display().to_string(),
                format!("{FIXTURE_USER}:{FIXTURE_USER}")
            )],
            "the chown arm must chown the prefix"
        );
        assert!(
            npm_calls().is_empty(),
            "the chown arm must not migrate modules"
        );

        // A system path OUTSIDE home always rebases — never chowned.
        let ctx = rebase_ctx(d.path(), npm_two_modules);
        apply_rebase(&ctx, "/usr/local", "root").unwrap();
        let rebase_calls = npm_calls();
        let ctx = rebase_ctx(d.path(), npm_two_modules);
        chown_or_rebase_with(&ctx, "/usr/local", "root").unwrap();
        assert_eq!(
            npm_calls(),
            rebase_calls,
            "a prefix outside {home} must take the rebase arm"
        );
        assert!(
            !chowns().iter().any(|(p, _)| p == "/usr/local"),
            "a system prefix must NEVER be chowned"
        );
    }

    #[test]
    fn each_module_outcome_is_counted_and_named_correctly() {
        // The counters and markers are the only record of what a rebase moved,
        // and they went to a global eprintln! where nothing read them back:
        // `== -> !=` logged a SUCCESSFUL install as `[REMEDIATE-01:partial]
        // reason=npm-install-failed`, and `+= -> *=` pinned both counters at 0.
        fn one_fails(
            _u: &str,
            argv: &[String],
            _e: &[(String, String)],
            _c: Capture,
            _t: Option<u64>,
        ) -> DispatchResult {
            record_npm(argv);
            DispatchResult {
                // The `--` is argv[3], so the package is argv[4].
                exit_code: i32::from(argv[4].starts_with("bad")),
                stdout: String::new(),
                stderr: String::new(),
                streamed: false,
            }
        }
        let d = TempDir::new().unwrap();
        let mut ctx = rebase_ctx(d.path(), one_fails);
        ctx.fx.as_user = one_fails;

        let modules = vec![
            "good-a@1.0.0".to_string(),
            "bad-b@2.0.0".to_string(),
            "good-c@3.0.0".to_string(),
        ];
        let mut lines = Vec::new();
        let (migrated, failed) = migrate_modules(&ctx, FIXTURE_USER, &modules, &mut |m| {
            lines.push(m.to_string())
        });

        assert_eq!((migrated, failed), (2, 1));
        assert_eq!(
            lines,
            vec![
                "[REMEDIATE-01:migrated] module=good-a@1.0.0".to_string(),
                "[REMEDIATE-01:partial] module=bad-b@2.0.0 reason=npm-install-failed".to_string(),
                "[REMEDIATE-01:migrated] module=good-c@3.0.0".to_string(),
            ],
            "the marker must name what actually happened to each module"
        );
    }

    #[test]
    fn the_manifest_is_used_only_when_npm_ls_both_succeeded_and_spoke() {
        // BOTH conditions. The single fixture for this returned exit 1 AND empty
        // stdout, satisfying neither disjunct, so `&& -> ||` survived — and under
        // it a failed or timed-out `npm ls` whose stdout carries a truncated JSON
        // prefix is parsed as though it were a complete manifest.
        let body = r#"{"dependencies":{"x":{"version":"1.0.0"}}}"#;
        assert_eq!(
            manifest_or_empty(0, body),
            body,
            "a clean run is the manifest"
        );
        // Failed but talkative — the case the mutant lets through.
        assert_eq!(manifest_or_empty(1, body), "{}");
        // Succeeded but silent.
        assert_eq!(manifest_or_empty(0, "   \n "), "{}");
        assert_eq!(manifest_or_empty(1, ""), "{}");
    }

    #[test]
    fn the_production_entry_point_actually_remediates() {
        // `chown_or_rebase` is what `nodejs::run` calls; `chown_or_rebase_with`
        // has no production caller. Driving only the latter left the observable
        // that matters — dispatch, do nothing, report success — reachable by a
        // wrong edit to the four lines that compute `prefix` and `old_owner`.
        let d = TempDir::new().unwrap();
        let prefix = d.path().join(".npm-global");
        std::fs::create_dir_all(&prefix).unwrap();
        let ctx = rebase_ctx(d.path(), npm_two_modules);

        chown_or_rebase(&ctx).unwrap();

        // It resolved the canonical under-home prefix and took the chown arm.
        assert_eq!(
            chowns(),
            vec![(
                prefix.display().to_string(),
                format!("{FIXTURE_USER}:{FIXTURE_USER}")
            )],
            "the entry point must reach the prefix, not merely return Ok"
        );
    }

    #[test]
    fn an_empty_effective_prefix_is_refused_rather_than_acted_on() {
        // The detect cache had no prefix path. Acting on "" would mean
        // `chown -R` or a rebase rooted at the empty string.
        let d = TempDir::new().unwrap();
        let ctx = rebase_ctx(d.path(), npm_two_modules);
        let err = chown_or_rebase_with(&ctx, "", "root").unwrap_err();
        assert!(err.to_string().contains("detect-cache-missing-prefix-path"));
        assert!(
            chowns().is_empty() && npm_calls().is_empty(),
            "nothing may run"
        );
    }

    #[test]
    fn chown_retargets_the_prefix_at_the_install_user_recursively() {
        let d = TempDir::new().unwrap();
        let prefix = d.path().join(".npm-global");
        std::fs::create_dir_all(&prefix).unwrap();
        let ctx = rebase_ctx(d.path(), npm_two_modules);

        apply_chown(&ctx, &prefix.to_string_lossy(), FIXTURE_USER).unwrap();

        // ONE recursive chown, of the prefix, to the install user's own
        // user:group. Not root, and not the invoking user.
        assert_eq!(
            chowns(),
            vec![(
                prefix.display().to_string(),
                format!("{FIXTURE_USER}:{FIXTURE_USER}")
            )]
        );
    }

    #[test]
    fn a_failed_chown_is_a_hard_error_not_a_silent_skip() {
        // REMEDIATE-01's whole purpose is that `npm install -g` stops racing
        // root. A chown that could not be applied and was reported as success
        // leaves exactly the state the remediation was invoked to remove.
        fn denied(_p: &Path, _o: &str) -> io::Result<()> {
            Err(io::Error::other("chown: Operation not permitted"))
        }
        let d = TempDir::new().unwrap();
        let mut ctx = rebase_ctx(d.path(), npm_two_modules);
        ctx.fx.chown_recursive = denied;

        assert!(apply_chown(&ctx, &d.path().to_string_lossy(), FIXTURE_USER).is_err());
    }

    #[test]
    fn the_production_recursive_chown_refuses_a_name_no_host_has() {
        // The wiring adapter `chown_recursive_by_name` splits "user:group" and
        // resolves the LHS. A name that does not resolve must be an error, not a
        // silent (0, 0) — which is what `chown -R root:root` on the agent's
        // prefix would be.
        let d = TempDir::new().unwrap();
        let err = chown_recursive_by_name(d.path(), "agentlinux-no-such-user:x").unwrap_err();
        assert!(
            err.to_string().contains("unknown user"),
            "unexpected error: {err}"
        );
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
        // The prefix must end up owned by the INSTALL USER at 0755 — the whole
        // point of the rebase is that the agent can write its own npm prefix
        // without sudo. Asserting the ownership argument, not just that a
        // directory appeared: the previous fixture performed the real chown and
        // so could assert nothing about it.
        assert_eq!(
            dirs_created(),
            vec![
                (
                    new_prefix.display().to_string(),
                    0o755,
                    format!("{FIXTURE_USER}:{FIXTURE_USER}")
                ),
                (
                    new_prefix.join("bin").display().to_string(),
                    0o755,
                    format!("{FIXTURE_USER}:{FIXTURE_USER}")
                ),
                (
                    new_prefix.join("lib").display().to_string(),
                    0o755,
                    format!("{FIXTURE_USER}:{FIXTURE_USER}")
                ),
            ]
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
