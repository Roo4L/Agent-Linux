//! provision/probe.rs — the DETECT-phase host readers that feed the pure gates.
//!
//! The Bash entrypoint runs `detect::run_once` (populating `DETECT_*` exports +
//! `/run/agentlinux-detect.json`) and `remediate::collect_all_decisions` then
//! consults `reuse::*_decision` over those exports to build `RESOLUTIONS[…]`
//! (remediate.sh:234-299). This module is the Rust analogue: thin readers that
//! answer "what is actually on this host" so `cmd/provision.rs` can call the
//! ALREADY-PORTED pure gates (`agentlinux_core::reuse::agent_decision` +
//! `detect_gates::*`) and assemble the `Resolutions` map.
//!
//! # The pure/I-O seam
//! Every reader here does I/O (fs / passwd DB / cache read). The DECISION stays
//! in the pure `agentlinux-core` gates — this module NEVER re-implements the
//! reuse/remediate logic, it only gathers inputs. Per-agent detect status comes
//! from the Phase-56 detect-cache adapter (`crate::cache`); absent cache → every
//! agent reads `absent` (→ Create), which is the fresh-install path the
//! provisioner runs on a clean host.
//!
//! # PROV-02 (57-06)
//! `cmd/provision.rs` iterates the Rust `canonical_path` map (main.rs) IN-PROCESS
//! and calls these readers + the pure gate per id — there is NO
//! `agentlinux reuse-decision` shell-out. The Rust map is the single authoritative
//! per-agent enumerator; the Bash `reuse/agents.sh` map is retained only as the
//! 13-reuse spec-contract shim + GATE-05 rollback fallback (plan-check B-1).

use crate::cache;
use agentlinux_core::types::DetectedAgent;
use std::path::Path;

/// The passwd-DB facts every user predicate below decides on. Splitting the
/// LOOKUP (I/O, one function) from the DECISION (pure, testable with a literal)
/// is what lets the adoption/shell/ownership rules be asserted on a root CI
/// runner, where the runner's own uid used to make the positive cases evaporate.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Account {
    pub uid: u32,
    /// The primary group — the group-write bit on a home only helps the user
    /// when this owns it.
    pub gid: u32,
    pub shell: String,
    pub home: String,
}

/// Read `name`'s passwd entry, or `None` when it does not exist / the lookup
/// fails. The single I/O point behind every predicate in this module.
#[must_use]
pub fn lookup(name: &str) -> Option<Account> {
    match nix::unistd::User::from_name(name) {
        Ok(Some(u)) => Some(Account {
            uid: u.uid.as_raw(),
            gid: u.gid.as_raw(),
            shell: u.shell.to_string_lossy().into_owned(),
            home: u.dir.to_string_lossy().into_owned(),
        }),
        _ => None,
    }
}

/// A per-agent detect reading — status + resolved path — sourced from the detect
/// cache. Absent from the cache → `absent` with an empty path (the fresh-install
/// default the Bash `${!var:-absent}` / `${!path_var:-}` produce).
#[derive(Debug, Clone)]
pub struct AgentProbe {
    pub status: String,
    pub path: String,
}

/// Read the detect status + path for a catalog id from the Phase-56 detect cache.
/// Absent cache or absent id → `status="absent"`, `path=""` — which
/// `agent_decision` maps to `Create` (the clean-host path).
#[must_use]
pub fn probe_agent(id: &str) -> AgentProbe {
    match cache::read_cached_agent_by_id(id) {
        Some(DetectedAgent { status, path, .. }) => AgentProbe { status, path },
        None => AgentProbe {
            status: "absent".to_string(),
            path: String::new(),
        },
    }
}

/// Whether a system user exists (passwd DB). Mirrors the Bash `id <user>` probe
/// that `reuse::user_decision` keys on. A lookup error is treated as "does not
/// exist" (a fresh host has no such user) — the conservative Create default,
/// which is why [`lookup`] collapses both into `None`.
#[must_use]
pub fn user_exists(name: &str) -> bool {
    lookup(name).is_some()
}

/// `remediate::user_adoptable` port (`plugin/lib/remediate.sh:109-126`). The
/// runtime adoption-safety gate: if the name does NOT exist, returns `true` (it
/// will be created fresh / a purge no-op is idempotent). If it DOES exist,
/// returns `true` only when its UID >= 1000 (a regular login account); an
/// EXISTING system account (UID < 1000) returns `false` so the caller refuses to
/// grant it NOPASSWD sudo + overwrite its home (H-1), and — on the purge path —
/// so `userdel -r` can never remove a system/daemon account. Reads the passwd DB
/// — NOT pure; call it at runtime (after require_root), never during DECIDE.
#[must_use]
pub fn user_adoptable(name: &str) -> bool {
    adoptable(lookup(name).as_ref())
}

/// The pure half of [`user_adoptable`]: `None` (absent, or an unreadable passwd
/// DB) → safe to create / an idempotent purge no-op; present → adoptable only at
/// UID >= 1000.
#[must_use]
pub fn adoptable(account: Option<&Account>) -> bool {
    match account {
        None => true,
        Some(a) => a.uid >= 1000,
    }
}

/// The REUSE-01 compatibility state of an existing install user. Two predicates
/// are irreconcilable and bail: the SHELL (no chsh handler) and a HOME the user
/// cannot write (adopting it would hand every later step the EACCES failure this
/// project exists to eliminate). Present + a bash login shell + a writable home →
/// Reuse (re-attach path wiring / [REMEDIATE-02]); absent → Create.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UserState {
    /// No such user — fresh CREATE (useradd).
    Absent,
    /// Exists with a bash login shell and a writable home — REUSE.
    Conforming,
    /// Exists but with a non-bash shell — irreconcilable, BAIL.
    WrongShell,
    /// Exists with a home directory the user cannot write (root-owned, or
    /// present but not user-writable) — irreconcilable, BAIL.
    HomeNotWritable,
}

/// The ownership + mode facts of a directory, as the home-writability predicate
/// needs them. Read as root, so `access(2)` would answer for root rather than for
/// the install user — the decision is made from uid + mode instead.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DirFacts {
    pub uid: u32,
    pub gid: u32,
    /// The permission bits only (`st_mode & 0o7777`).
    pub mode: u32,
}

/// Read `path`'s ownership + mode, or `None` when it does not exist / is
/// unreadable. Follows symlinks — the home entry in passwd is expected to be a
/// real directory, and a symlinked home is still the user's to write.
#[must_use]
pub fn dir_facts(path: &Path) -> Option<DirFacts> {
    use std::os::unix::fs::MetadataExt;
    std::fs::metadata(path).ok().map(|md| DirFacts {
        uid: md.uid(),
        gid: md.gid(),
        mode: md.mode() & 0o7777,
    })
}

/// Whether `account` can write its own home, given that home's facts. Pure.
///
/// `None` facts mean the home does not exist yet — that is the fresh-`useradd`
/// shape (10-agent-user creates it), NOT a failure. Owned by the user with the
/// owner-write bit → writable; otherwise the group/other write bits decide, and
/// group-write only counts when the user's primary group owns the directory.
#[must_use]
pub fn home_writable(account: &Account, facts: Option<&DirFacts>) -> bool {
    let Some(f) = facts else { return true };
    if f.uid == account.uid {
        return f.mode & 0o200 != 0;
    }
    f.mode & 0o002 != 0 || (f.mode & 0o020 != 0 && f.gid == account.gid)
}

/// The pure REUSE-01 user predicate: shell first (a wrong shell is
/// irreconcilable regardless of the home), then home writability.
#[must_use]
pub fn user_state_of(account: Option<&Account>, home: Option<&DirFacts>) -> UserState {
    let Some(a) = account else {
        return UserState::Absent;
    };
    if a.shell != "/bin/bash" && a.shell != "/usr/bin/bash" {
        return UserState::WrongShell;
    }
    if home_writable(a, home) {
        UserState::Conforming
    } else {
        UserState::HomeNotWritable
    }
}

/// Probe an existing install user's REUSE-01 compatibility. Reads the passwd DB
/// plus the home directory's ownership. I/O — the decision itself is
/// [`user_state_of`].
#[must_use]
pub fn user_state(user: &str) -> UserState {
    let account = lookup(user);
    let home = account
        .as_ref()
        .and_then(|a| dir_facts(Path::new(&a.home)));
    user_state_of(account.as_ref(), home.as_ref())
}

/// The on-host state of `/etc/sudoers.d/agentlinux`, feeding the REMEDIATE-03
/// decision. Mirrors the Bash `DETECT_SUDOERS_PRESENT` / `DETECT_SUDOERS_NOPASSWD_OK`
/// exports (`detect/sudoers.sh`): the canonical file carries the exact
/// `<user> ALL=(ALL) NOPASSWD: ALL` line (ADR-012); a present-but-drifted file
/// (e.g. a narrow package-scoped NOPASSWD) lacks it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SudoersState {
    /// No drop-in — fresh CREATE.
    Absent,
    /// Present with the canonical ADR-012 NOPASSWD line — REUSE (no-op).
    Canonical,
    /// Present but WITHOUT the canonical line — a state-overwriting REMEDIATE.
    Drifted,
}

/// The canonical drop-in path — the same constant `provision::sudoers` writes.
pub const SUDOERS_FILE: &str = "/etc/sudoers.d/agentlinux";

/// Probe `/etc/sudoers.d/agentlinux`. Absent file → `Absent`; a file containing
/// the exact canonical `<user> ALL=(ALL) NOPASSWD: ALL` line → `Canonical`; a
/// present file lacking it → `Drifted`. I/O — call at runtime (post require_root),
/// never during a pure test.
#[must_use]
pub fn sudoers_state(user: &str) -> SudoersState {
    sudoers_state_at(Path::new(SUDOERS_FILE), user)
}

/// [`sudoers_state`] against an arbitrary path — the seam a test drives with a
/// tempdir fixture instead of the host's real `/etc`.
#[must_use]
pub fn sudoers_state_at(path: &Path, user: &str) -> SudoersState {
    sudoers_state_of(std::fs::read_to_string(path).ok().as_deref(), user)
}

/// The pure line-matching half — where the drift-detection bug actually lives
/// (a `%agent` group form, a `Defaults` line, a leading tab, `NOPASSWD:ALL` with
/// no space). `None` content = no such file.
#[must_use]
pub fn sudoers_state_of(content: Option<&str>, user: &str) -> SudoersState {
    let Some(content) = content else {
        return SudoersState::Absent;
    };
    let canonical = format!("{user} ALL=(ALL) NOPASSWD: ALL");
    if content.lines().any(|l| l.trim() == canonical) {
        SudoersState::Canonical
    } else {
        SudoersState::Drifted
    }
}

/// The on-host state of the install user's npm-global prefix, feeding the
/// REMEDIATE-01 decision. Mirrors `reuse::npm_prefix_decision`: absent → create;
/// present-and-owned-by-the-install-user → reuse; present-but-wrong-owner → a
/// state-overwriting remediate (chown or rebase, chosen by the ACT `strategy_for`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NpmPrefixState {
    /// `<home>/.npm-global` does not exist — fresh CREATE (30-nodejs makes it).
    Absent,
    /// Exists and is owned by the install user — REUSE.
    OwnedByUser,
    /// Exists but owned by someone else (e.g. root) — brownfield REMEDIATE.
    WrongOwner,
}

/// The EFFECTIVE npm prefix for the install user: the `prefix=<path>` line in
/// `<home>/.npmrc` if present, else the canonical `<home>/.npm-global`. Mirrors the
/// Bash `DETECT_NPM_PREFIX_PATH` — a brownfield host may point npm at a foreign
/// prefix (e.g. a root-owned `/usr/local/...`) via `.npmrc`, which the REMEDIATE-01
/// rebase arm migrates away from.
#[must_use]
pub fn effective_npm_prefix(home: &str) -> String {
    let default = format!("{home}/.npm-global");
    match std::fs::read_to_string(format!("{home}/.npmrc")) {
        Ok(content) => content
            .lines()
            .filter_map(|l| l.split_once('='))
            .find(|(k, _)| k.trim() == "prefix")
            .map(|(_, v)| v.trim().to_string())
            .filter(|v| !v.is_empty())
            .unwrap_or(default),
        Err(_) => default,
    }
}

/// Probe the install user's EFFECTIVE npm prefix ownership + location. Absent →
/// `Absent` (30-nodejs creates the canonical one); present, owned by the install
/// user AND under home → `OwnedByUser` (Reuse); present but wrong-owner OR off-home
/// → `WrongOwner` (a REMEDIATE-01 chown-or-rebase, strategy chosen by the ACT).
/// Uses `symlink_metadata` (no deref) + the passwd DB. I/O.
#[must_use]
pub fn npm_prefix_state(user: &str, home: &str) -> NpmPrefixState {
    npm_prefix_state_for_uid(lookup(user).map(|a| a.uid), home)
}

/// [`npm_prefix_state`] with the expected owner's uid supplied rather than looked
/// up — the seam that lets a test point `home` at a tempdir it owns (and at one
/// it does not) without needing a second real account on the host. `None` uid =
/// the install user does not exist, so nothing on disk can be owned by them.
#[must_use]
pub fn npm_prefix_state_for_uid(uid: Option<u32>, home: &str) -> NpmPrefixState {
    use std::os::unix::fs::MetadataExt;
    let prefix = effective_npm_prefix(home);
    let md = match std::fs::symlink_metadata(&prefix) {
        Err(_) => return NpmPrefixState::Absent,
        Ok(md) => md,
    };
    let under_home = prefix.starts_with(&format!("{home}/"));
    if uid == Some(md.uid()) && under_home {
        NpmPrefixState::OwnedByUser
    } else {
        NpmPrefixState::WrongOwner
    }
}

#[cfg(test)]
mod probe_tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn probe_agent_absent_when_no_cache() {
        let mut env_scope = crate::test_support::EnvScope::new();
        env_scope.set("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect-probe.json");
        let p = probe_agent("claude-code");
        assert_eq!(p.status, "absent");
        assert!(p.path.is_empty());
        env_scope.unset("AGENTLINUX_DETECT_CACHE");
    }

    #[test]
    fn probe_agent_reads_cache_status_and_path() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("detect.json");
        std::fs::write(
            &path,
            r#"{"agents":[{"id":"gsd","status":"healthy","path":"/home/agent/.claude/gsd-core/VERSION","version":"1.37.1"}]}"#,
        )
        .unwrap();
        env_scope.set("AGENTLINUX_DETECT_CACHE", &path);

        let p = probe_agent("gsd");
        assert_eq!(p.status, "healthy");
        assert_eq!(p.path, "/home/agent/.claude/gsd-core/VERSION");

        env_scope.unset("AGENTLINUX_DETECT_CACHE");
    }

    #[test]
    fn user_exists_true_for_root_false_for_bogus() {
        assert!(user_exists("root"));
        assert!(!user_exists("nonexistent-user-xyz-9042"));
    }

    /// A passwd entry literal — the whole point of the `Account` seam is that a
    /// test states the facts instead of hoping the host supplies them.
    fn acct(uid: u32, shell: &str) -> Account {
        Account {
            uid,
            gid: uid,
            shell: shell.to_string(),
            home: format!("/home/u{uid}"),
        }
    }

    // --- user_adoptable / adoptable (H-1) ---

    #[test]
    fn user_adoptable_refuses_existing_system_account() {
        // root is UID 0 (< 1000) and always exists → refuse (H-1). This is the
        // literal case run_purge must NOT feed to `userdel -r`.
        assert!(!user_adoptable("root"));
        // daemon is a UID<1000 system account present on every Linux host.
        assert!(!user_adoptable("daemon"));
    }

    #[test]
    fn adoptable_allows_a_regular_login_and_an_absent_name() {
        // The POSITIVE case, asserted from a literal — it used to be guarded by
        // `if self_uid >= 1000`, so it evaporated on the root CI runners and the
        // Docker bats containers, leaving only refusals behind.
        assert!(adoptable(Some(&acct(1000, "/bin/bash"))));
        assert!(adoptable(Some(&acct(65_534, "/usr/sbin/nologin"))));
        // Absent (or an unreadable passwd DB) → create-fresh / purge no-op.
        assert!(adoptable(None));
        assert!(user_adoptable("nonexistent-user-xyz-9042"));
    }

    #[test]
    fn adoptable_refuses_every_system_uid_boundary() {
        assert!(!adoptable(Some(&acct(0, "/bin/bash"))));
        assert!(!adoptable(Some(&acct(999, "/bin/bash"))));
        // 1000 is the first regular login uid — the boundary itself is adoptable.
        assert!(adoptable(Some(&acct(1000, "/bin/bash"))));
    }

    // --- user_state (REUSE-01) ---

    #[test]
    fn user_state_absent_when_no_passwd_entry() {
        assert_eq!(user_state_of(None, None), UserState::Absent);
        assert_eq!(user_state("nonexistent-user-xyz-9042"), UserState::Absent);
    }

    #[test]
    fn user_state_conforming_for_both_bash_paths() {
        let facts = DirFacts {
            uid: 1000,
            gid: 1000,
            mode: 0o755,
        };
        assert_eq!(
            user_state_of(Some(&acct(1000, "/bin/bash")), Some(&facts)),
            UserState::Conforming
        );
        assert_eq!(
            user_state_of(Some(&acct(1000, "/usr/bin/bash")), Some(&facts)),
            UserState::Conforming
        );
    }

    #[test]
    fn user_state_wrong_shell_bails_before_the_home_check() {
        // A wrong shell is irreconcilable whatever the home looks like — assert
        // the ordering, not just the outcome.
        let good_home = DirFacts {
            uid: 1000,
            gid: 1000,
            mode: 0o755,
        };
        for shell in ["/usr/sbin/nologin", "/bin/sh", "/bin/false", ""] {
            assert_eq!(
                user_state_of(Some(&acct(1000, shell)), Some(&good_home)),
                UserState::WrongShell,
                "shell {shell:?} must be irreconcilable"
            );
        }
    }

    #[test]
    fn user_state_home_not_writable_is_the_reuse01_bail() {
        // REUSE-01: a brownfield `agent` whose home is root-owned must NOT be
        // adopted — every later step would write into a home it cannot write,
        // which is the EACCES class AgentLinux exists to eliminate.
        let root_owned = DirFacts {
            uid: 0,
            gid: 0,
            mode: 0o755,
        };
        assert_eq!(
            user_state_of(Some(&acct(1000, "/bin/bash")), Some(&root_owned)),
            UserState::HomeNotWritable
        );
        // Owned by the user but read-only → equally unusable.
        let read_only = DirFacts {
            uid: 1000,
            gid: 1000,
            mode: 0o555,
        };
        assert_eq!(
            user_state_of(Some(&acct(1000, "/bin/bash")), Some(&read_only)),
            UserState::HomeNotWritable
        );
    }

    #[test]
    fn home_writable_honors_group_and_other_write_bits() {
        let a = acct(1000, "/bin/bash");
        // Not the owner, but the user's primary group owns it and can write.
        assert!(home_writable(
            &a,
            Some(&DirFacts {
                uid: 0,
                gid: 1000,
                mode: 0o775
            })
        ));
        // Group-writable, but by a group the user is not the primary member of —
        // supplementary groups are not consulted, so this must NOT count.
        assert!(!home_writable(
            &a,
            Some(&DirFacts {
                uid: 0,
                gid: 42,
                mode: 0o775
            })
        ));
        // World-writable is enough.
        assert!(home_writable(
            &a,
            Some(&DirFacts {
                uid: 0,
                gid: 0,
                mode: 0o777
            })
        ));
        // An absent home is the fresh-useradd shape, not a failure.
        assert!(home_writable(&a, None));
    }

    #[test]
    fn dir_facts_reads_ownership_and_permission_bits() {
        let d = tempfile::tempdir().unwrap();
        let sub = d.path().join("home");
        std::fs::create_dir(&sub).unwrap();
        std::fs::set_permissions(&sub, std::fs::Permissions::from_mode(0o750)).unwrap();
        let f = dir_facts(&sub).expect("existing dir must read");
        assert_eq!(f.mode, 0o750, "mode is masked to the permission bits");
        assert_eq!(f.uid, nix::unistd::Uid::current().as_raw());
        assert!(dir_facts(&d.path().join("no-such-dir")).is_none());
    }

    // --- sudoers_state (REMEDIATE-03 drift detection) ---

    #[test]
    fn sudoers_state_absent_when_the_dropin_is_missing() {
        let d = tempfile::tempdir().unwrap();
        assert_eq!(
            sudoers_state_at(&d.path().join("agentlinux"), "agent"),
            SudoersState::Absent
        );
        assert_eq!(sudoers_state_of(None, "agent"), SudoersState::Absent);
    }

    #[test]
    fn sudoers_state_canonical_matches_the_exact_adr012_line() {
        let canonical = "# header\nagent ALL=(ALL) NOPASSWD: ALL\n";
        assert_eq!(
            sudoers_state_of(Some(canonical), "agent"),
            SudoersState::Canonical
        );
        // Surrounding whitespace is trimmed per line, so an indented grant still
        // counts as canonical (sudo parses it identically).
        assert_eq!(
            sudoers_state_of(Some("\tagent ALL=(ALL) NOPASSWD: ALL  \n"), "agent"),
            SudoersState::Canonical
        );
    }

    #[test]
    fn sudoers_state_drifted_for_every_near_miss_form() {
        // These are the forms a hand-narrowed or hand-edited drop-in actually
        // takes. Each is NOT the canonical ADR-012 line, so each must read as
        // Drifted (a --yes overwrite), never as Canonical (a silent no-op).
        for near_miss in [
            "%agent ALL=(ALL) NOPASSWD: ALL\n",       // group form
            "agent ALL=(ALL) NOPASSWD:ALL\n",         // no space after the colon
            "agent ALL=(ALL) NOPASSWD: /usr/bin/apt\n", // deliberately narrowed
            "agent ALL=(ALL) ALL\n",                  // password required
            "Defaults:agent !requiretty\n",
            "",
        ] {
            assert_eq!(
                sudoers_state_of(Some(near_miss), "agent"),
                SudoersState::Drifted,
                "{near_miss:?} must not read as canonical"
            );
        }
    }

    #[test]
    fn sudoers_state_is_per_user() {
        // A drop-in granting `claude` is drift for an `agent` install (AL-50).
        let content = Some("claude ALL=(ALL) NOPASSWD: ALL\n");
        assert_eq!(sudoers_state_of(content, "claude"), SudoersState::Canonical);
        assert_eq!(sudoers_state_of(content, "agent"), SudoersState::Drifted);
    }

    #[test]
    fn sudoers_state_at_reads_the_file() {
        let d = tempfile::tempdir().unwrap();
        let f = d.path().join("agentlinux");
        std::fs::write(&f, "agent ALL=(ALL) NOPASSWD: ALL\n").unwrap();
        assert_eq!(sudoers_state_at(&f, "agent"), SudoersState::Canonical);
    }

    // --- effective_npm_prefix / npm_prefix_state (REMEDIATE-01) ---

    #[test]
    fn effective_npm_prefix_defaults_to_npm_global() {
        let d = tempfile::tempdir().unwrap();
        let home = d.path().to_string_lossy().into_owned();
        assert_eq!(effective_npm_prefix(&home), format!("{home}/.npm-global"));
    }

    #[test]
    fn effective_npm_prefix_honors_an_npmrc_prefix_line() {
        let d = tempfile::tempdir().unwrap();
        let home = d.path().to_string_lossy().into_owned();
        // A brownfield host pointing npm at a root-owned foreign prefix — the
        // case the REMEDIATE-01 rebase arm migrates away from.
        std::fs::write(
            d.path().join(".npmrc"),
            "//registry.npmjs.org/:_authToken=x\nprefix = /usr/local\n",
        )
        .unwrap();
        assert_eq!(effective_npm_prefix(&home), "/usr/local");
    }

    #[test]
    fn effective_npm_prefix_ignores_an_empty_or_absent_prefix_line() {
        let d = tempfile::tempdir().unwrap();
        let home = d.path().to_string_lossy().into_owned();
        std::fs::write(d.path().join(".npmrc"), "prefix=\nregistry=https://x\n").unwrap();
        assert_eq!(effective_npm_prefix(&home), format!("{home}/.npm-global"));
    }

    #[test]
    fn npm_prefix_state_absent_when_the_prefix_does_not_exist() {
        let d = tempfile::tempdir().unwrap();
        let home = d.path().to_string_lossy().into_owned();
        assert_eq!(
            npm_prefix_state_for_uid(Some(0), &home),
            NpmPrefixState::Absent
        );
    }

    #[test]
    fn npm_prefix_state_owned_by_user_when_uid_matches_and_under_home() {
        let d = tempfile::tempdir().unwrap();
        let home = d.path().to_string_lossy().into_owned();
        std::fs::create_dir(d.path().join(".npm-global")).unwrap();
        let me = nix::unistd::Uid::current().as_raw();
        assert_eq!(
            npm_prefix_state_for_uid(Some(me), &home),
            NpmPrefixState::OwnedByUser
        );
    }

    #[test]
    fn npm_prefix_state_wrong_owner_for_a_foreign_uid() {
        let d = tempfile::tempdir().unwrap();
        let home = d.path().to_string_lossy().into_owned();
        std::fs::create_dir(d.path().join(".npm-global")).unwrap();
        // The dir exists but belongs to someone else — the brownfield chown case.
        let not_me = nix::unistd::Uid::current().as_raw().wrapping_add(1);
        assert_eq!(
            npm_prefix_state_for_uid(Some(not_me), &home),
            NpmPrefixState::WrongOwner
        );
        // An install user who does not exist owns nothing.
        assert_eq!(
            npm_prefix_state_for_uid(None, &home),
            NpmPrefixState::WrongOwner
        );
    }

    #[test]
    fn npm_prefix_state_wrong_owner_when_npmrc_points_off_home() {
        // Owned by us, but OUTSIDE home (an .npmrc rebase target) → the rebase
        // arm, not reuse. `/tmp` is ours-or-not, so use a dir we just made.
        let outside = tempfile::tempdir().unwrap();
        let d = tempfile::tempdir().unwrap();
        let home = d.path().to_string_lossy().into_owned();
        std::fs::write(
            d.path().join(".npmrc"),
            format!("prefix={}\n", outside.path().display()),
        )
        .unwrap();
        let me = nix::unistd::Uid::current().as_raw();
        assert_eq!(
            npm_prefix_state_for_uid(Some(me), &home),
            NpmPrefixState::WrongOwner
        );
    }
}
