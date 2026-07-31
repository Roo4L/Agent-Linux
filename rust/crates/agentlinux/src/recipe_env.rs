//! recipe_env.rs — the ONE typed source of the recipe env contract (VERB-03),
//! and the ONE source of where an install user's files live.
//!
//! Four responsibilities, all I/O-bearing, so they live in the bin (NOT the pure
//! `agentlinux-core`):
//!
//! 1. `RecipeEnv` + `into_env_pairs()` — the SIX `AGENTLINUX_*` key strings in
//!    exactly one place. A rename is a compile error, so the ~25 Bash recipes
//!    that read `${AGENTLINUX_*}` (e.g. `plugin/catalog/agents/gsd/install.sh`)
//!    can never silently desync.
//! 2. `resolve_install_user()` — precedence `$AGENTLINUX_USER` >
//!    `/etc/agentlinux.env` `AGENTLINUX_USER=` line > `agent`, POSIX-charset
//!    re-validated (`^[a-z][a-z0-9_-]*$`) so a malformed/tampered value can never
//!    reach a `sudo -u` argv — malformed falls back to `agent`.
//! 3. `install_home()` / `agent_home()` / `npm_prefix()` / `canonical_path()` —
//!    the path layout. Every module that needs "where does this user's stuff
//!    live" routes through these; the literals appear nowhere else.
//! 4. `base_child_env()` / `full_child_env()` — the child environment the
//!    dispatcher sets: the 6 pairs PLUS an EXPLICIT canonical PATH (`sudo -E`
//!    alone drops PATH to Ubuntu's `secure_path`), HOME, NPM_CONFIG_PREFIX and
//!    LANG/LC_ALL, then any extra pairs appended so later keys override earlier.

use std::fs;

const DEFAULT_INSTALL_USER: &str = "agent";
const AGENTLINUX_ENV_FILE: &str = "/etc/agentlinux.env";

/// The env file every consumer reads — `/etc/agentlinux.env`, or the path in
/// `$AGENTLINUX_ENV_FILE`.
///
/// The override is a TEST SEAM and grants no new authority: `$AGENTLINUX_USER`
/// already overrides this file outright (step 1 of [`resolve_install_user`]), so
/// anyone who can set the one can already set the other. It exists because the
/// alternative — `if !Path::new("/etc/agentlinux.env").exists()` around a test
/// body — silently deletes the assertion on exactly the hosts AgentLinux
/// provisions, which is where these tests matter most.
#[must_use]
pub fn env_file_path() -> String {
    match std::env::var("AGENTLINUX_ENV_FILE") {
        Ok(v) if !v.is_empty() => v,
        _ => AGENTLINUX_ENV_FILE.to_string(),
    }
}

/// The typed recipe env — the SIX `AGENTLINUX_*` values the dispatcher injects.
/// String-typed to match the process-env contract (all values are strings).
///
/// SECURITY (M1) — trust boundary: these values cross into the recipe child as
/// ENVIRONMENT values (not argv, not shell text), so none can inject inside the
/// dispatcher. But the ~25 Bash recipes `cd`/`source`/write to `catalog_dir`,
/// `agent_home`, and `install_log`. That is safe ONLY because those fields are
/// resolved upstream from trusted sources — `catalog_dir` from the catalog
/// loader, `install_log` a hard-coded constant (`/var/log/agentlinux-install.log`,
/// runner.ts:110), `agent_home` from the resolved install user — NOT from the raw
/// CLI `<name>`/`<spec>`. When the verb adapters wire real callers, keep
/// `install_log` a constant and do NOT let any of these become caller-supplied
/// without the loader's path constraint, or a path-traversal/arbitrary-write
/// reaches a recipe running under `sudo -u` (root-equivalent per ADR-012).
#[derive(Debug, Clone)]
pub struct RecipeEnv {
    pub pinned_version: String,
    pub catalog_dir: String,
    pub agent_home: String,
    pub source_kind: String,
    pub install_log: String,
    /// Colon-joined home-relative paths uninstall.sh must preserve; empty string
    /// (still present) when the entry has no preserve_paths.
    pub preserve_paths: String,
}

impl RecipeEnv {
    /// The 6 `("AGENTLINUX_…", value)` pairs. The key literals appear in exactly
    /// this one function — a field rename here is a compile error, satisfying
    /// VERB-03's "a rename cannot silently desync" invariant.
    pub fn into_env_pairs(self) -> [(&'static str, String); 6] {
        [
            ("AGENTLINUX_PINNED_VERSION", self.pinned_version),
            ("AGENTLINUX_CATALOG_DIR", self.catalog_dir),
            ("AGENTLINUX_AGENT_HOME", self.agent_home),
            ("AGENTLINUX_SOURCE_KIND", self.source_kind),
            ("AGENTLINUX_INSTALL_LOG", self.install_log),
            ("AGENTLINUX_PRESERVE_PATHS", self.preserve_paths),
        ]
    }
}

/// Reserved / system account names an install user may never be. Case-folded
/// before comparison; the whole `systemd-*` prefix is rejected separately.
const RESERVED_USER_NAMES: &[&str] = &[
    "root",
    "daemon",
    "bin",
    "sys",
    "sync",
    "games",
    "man",
    "lp",
    "mail",
    "news",
    "uucp",
    "proxy",
    "www-data",
    "backup",
    "list",
    "irc",
    "gnats",
    "nobody",
    "_apt",
    "systemd-network",
    "systemd-resolve",
    "systemd-timesync",
    "messagebus",
    "sshd",
];

/// True iff `name` matches `^[a-z][a-z0-9_-]*$` — the POSIX-portable username
/// charset. Hand-rolled (no regex crate) so the charset lives inline and the bin
/// stays dependency-light.
///
/// CHARSET ONLY, deliberately. This is the predicate behind the RESOLUTION
/// fallback: a malformed `$AGENTLINUX_USER` or env-file line degrades to `agent`
/// rather than failing, because every verb resolves an install user and most of
/// them (`list`, `pin`) have no business dying over a stale env file. A RESERVED
/// name is a different case — it is well-formed, so falling back would silently
/// provision a DIFFERENT user than the operator configured. The verb that
/// creates state re-validates with [`is_reserved_user_name`] and exits EX_USAGE
/// instead; see `cmd/provision::validate_user_name`.
#[must_use]
pub fn is_valid_install_user(name: &str) -> bool {
    let mut chars = name.chars();
    match chars.next() {
        Some(c) if c.is_ascii_lowercase() => {}
        _ => return false, // must start with [a-z]
    }
    chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-')
}

/// True iff `name` is a reserved / system account an install user may never be.
/// Case-insensitive, and the whole `systemd-*` prefix is reserved.
#[must_use]
pub fn is_reserved_user_name(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    lower.starts_with("systemd-") || RESERVED_USER_NAMES.contains(&lower.as_str())
}

/// Resolve the install user catalog ops run as.
///
/// Precedence: `$AGENTLINUX_USER` > the `AGENTLINUX_USER=` line in
/// `/etc/agentlinux.env` (root-owned) > `agent`. A value failing the POSIX
/// charset (malformed env / tampered read) falls back to `agent` —
/// defense-in-depth for both the guard check and the `sudo -u` dispatch user
/// The env-file read is I/O; it lives HERE in the bin, not the core.
pub fn resolve_install_user() -> String {
    // 1. Env override (bats seam, 23-install-user.bats). Empty/unset → fall through.
    let env_user = match std::env::var("AGENTLINUX_USER") {
        Ok(v) if !v.is_empty() => Some(v),
        _ => None,
    };

    // 2. The AGENTLINUX_USER= line in the root-owned env file (multiline match).
    //    Absent/unreadable env file (dev host, pre-AL-50 install) → default.
    let file_text = if env_user.is_none() {
        fs::read_to_string(env_file_path()).ok()
    } else {
        None
    };

    resolve_install_user_from(env_user.as_deref(), file_text.as_deref())
}

/// The pure precedence + validation half of [`resolve_install_user`]: the
/// `$AGENTLINUX_USER` value (if any) and the env file's TEXT (if it was read) in,
/// the settled install user out. Every branch — override, file line, malformed,
/// absent — is a literal here rather than a state of the host.
#[must_use]
pub fn resolve_install_user_from(env_user: Option<&str>, file_text: Option<&str>) -> String {
    let raw = env_user.map(str::to_string).or_else(|| {
        file_text.and_then(|txt| {
            txt.lines()
                .find_map(|line| line.strip_prefix("AGENTLINUX_USER="))
                .map(|val| val.trim().to_string())
        })
    });

    // Charset-validate or fall back to `agent`.
    match raw {
        Some(v) if is_valid_install_user(&v) => v,
        _ => DEFAULT_INSTALL_USER.to_string(),
    }
}

/// The home directory of install user `user`.
///
/// This is the ONE place `/home/{user}` is spelled. Every other module that needs
/// an install home — the recipe env, the npm probe env, the provisioner's path
/// wiring — routes through here, so the layout assumption is stated once and can
/// be changed once.
///
/// KNOWN LIMITATION: this is the *conventional* home, not the passwd home. Adopting
/// a user whose passwd entry says `/var/lib/bob` still yields `/home/bob`. Fixing
/// that means resolving `nix::unistd::User::from_name(user).dir` here — a single
/// edit precisely because this function exists.
pub(crate) fn install_home(user: &str) -> String {
    format!("/home/{user}")
}

/// The agent home the presence/managed-dir heuristics run against —
/// `$AGENTLINUX_AGENT_HOME` when set, else the configured install user's home.
///
/// The env override exists so a test (and a non-default install layout) can point
/// the detection gates at a staged tree. The fallback goes through
/// `install_home(resolve_install_user())` rather than a literal `/home/agent`, so
/// a host configured with `AGENTLINUX_USER=bob` gets `/home/bob` and not a
/// silently wrong `/home/agent`.
pub(crate) fn agent_home() -> String {
    match std::env::var("AGENTLINUX_AGENT_HOME") {
        Ok(v) if !v.is_empty() => v,
        _ => install_home(&resolve_install_user()),
    }
}

/// The npm global prefix for `home` — the ONE spelling of `<home>/.npm-global`.
pub(crate) fn npm_prefix(home: &str) -> String {
    format!("{home}/.npm-global")
}

/// The canonical PATH for a user given their home. Set EXPLICITLY (not via
/// `sudo -E`) because Ubuntu's `secure_path` overrides an inherited PATH, which
/// would let recipes resolve `npm` from `/usr/bin` and fail with EACCES.
///
/// `pub(crate)`: the ONE source of the canonical PATH literal.
/// `provision::path_wiring` reuses it for the `/etc/agentlinux.env` and
/// `/etc/cron.d/agentlinux` PATH lines so the provisioner's emitted bytes are
/// byte-identical to the recipe env (a cross-module test asserts the three-way
/// equality). Stays `home`-parameterized — the caller supplies the resolved
/// install home, never a hardcoded `/home/agent`.
pub(crate) fn canonical_path(home: &str) -> String {
    format!("{home}/.npm-global/bin:{home}/.local/bin:/usr/local/bin:/usr/bin:/bin")
}

/// The non-`AGENTLINUX_*` half of a recipe child env: the explicit canonical
/// PATH, HOME, npm prefix and locale for `home`.
///
/// Shared by `full_child_env` (recipe dispatch) and `npm::npm_env_for` (the npm
/// probes), which previously carried byte-identical copies of these five pairs.
pub(crate) fn base_child_env(home: &str) -> Vec<(String, String)> {
    vec![
        ("PATH".to_string(), canonical_path(home)),
        ("HOME".to_string(), home.to_string()),
        ("NPM_CONFIG_PREFIX".to_string(), npm_prefix(home)),
        ("LANG".to_string(), "C.UTF-8".to_string()),
        ("LC_ALL".to_string(), "C.UTF-8".to_string()),
    ]
}

/// The install log every recipe appends to.
const INSTALL_LOG: &str = "/var/log/agentlinux-install.log";

/// The recipe child env for one catalog entry at `version`.
///
/// `install`, `remove` and `upgrade` must agree on this by definition — a recipe
/// gets the same environment whichever verb invoked it. It is defined once here
/// so a change to the contract cannot land in two verbs out of three.
pub fn recipe_child_env(
    entry: &crate::catalog::FullCatalogEntry,
    version: &str,
    catalog_dir: &std::path::Path,
    user: &str,
) -> Vec<(String, String)> {
    let recipe = RecipeEnv {
        pinned_version: version.to_string(),
        catalog_dir: catalog_dir.to_string_lossy().to_string(),
        agent_home: install_home(user),
        source_kind: entry.source_kind.clone().unwrap_or_default(),
        install_log: INSTALL_LOG.to_string(),
        preserve_paths: entry.preserve_paths.clone().unwrap_or_default().join(":"),
    };
    full_child_env(recipe, user, &[])
}

/// `<catalog_dir>/agents/<id>/<recipe>` — the absolute path of a recipe script.
///
/// TRUST: `id` and the recipe filename are catalog-derived, and the catalog is an
/// installer-owned root-written artifact under `/opt/agentlinux/catalog` whose
/// schema constrains recipe paths — so there is no traversal guard here. If the
/// catalog ever becomes caller-influenced, add a `..`/absolute reject mirroring
/// `catalog::load_catalog`'s `preserve_paths` check.
pub fn recipe_path(catalog_dir: &std::path::Path, id: &str, recipe: &str) -> String {
    catalog_dir
        .join("agents")
        .join(id)
        .join(recipe)
        .to_string_lossy()
        .to_string()
}

/// Assemble the FULL child environment the dispatcher sets.
///
/// The 6 `AGENTLINUX_*` pairs, PLUS `base_child_env` for `user`'s home, then
/// `extra` appended so later keys override earlier — an `extra` `LANG` overrides
/// the base `C.UTF-8`. `agent_home` in `recipe` is expected to already be
/// `install_home(user)` (the caller derives it alongside the resolved user).
pub fn full_child_env(
    recipe: RecipeEnv,
    user: &str,
    extra: &[(String, String)],
) -> Vec<(String, String)> {
    let mut env: Vec<(String, String)> = recipe
        .into_env_pairs()
        .into_iter()
        .map(|(k, v)| (k.to_string(), v))
        .collect();
    env.extend(base_child_env(&install_home(user)));
    // `extra` last so it overrides base keys (the consumer dedups by keeping the
    // LAST value for a key).
    env.extend(extra.iter().cloned());
    env
}

#[cfg(test)]
mod recipe_env_tests {
    use super::*;

    fn sample() -> RecipeEnv {
        RecipeEnv {
            pinned_version: "2.1.7".into(),
            catalog_dir: "/opt/agentlinux/catalog/0.3.0".into(),
            agent_home: "/home/agent".into(),
            source_kind: "npm".into(),
            install_log: "/var/log/agentlinux-install.log".into(),
            preserve_paths: String::new(),
        }
    }

    #[test]
    fn into_env_pairs_yields_the_six_named_pairs() {
        let pairs = sample().into_env_pairs();
        assert_eq!(pairs.len(), 6);
        assert_eq!(pairs[0], ("AGENTLINUX_PINNED_VERSION", "2.1.7".to_string()));
        assert_eq!(
            pairs[1],
            (
                "AGENTLINUX_CATALOG_DIR",
                "/opt/agentlinux/catalog/0.3.0".to_string()
            )
        );
        assert_eq!(
            pairs[2],
            ("AGENTLINUX_AGENT_HOME", "/home/agent".to_string())
        );
        assert_eq!(pairs[3], ("AGENTLINUX_SOURCE_KIND", "npm".to_string()));
        assert_eq!(
            pairs[4],
            (
                "AGENTLINUX_INSTALL_LOG",
                "/var/log/agentlinux-install.log".to_string()
            )
        );
        assert_eq!(pairs[5], ("AGENTLINUX_PRESERVE_PATHS", String::new()));
    }

    #[test]
    fn preserve_paths_join_including_empty() {
        // The colon-join is the CALLER's job — here we assert the
        // typed field carries the joined string verbatim, incl. the empty case.
        let joined = ["a".to_string(), ".config/x".to_string()].join(":");
        let mut e = sample();
        e.preserve_paths = joined;
        assert_eq!(e.into_env_pairs()[5].1, "a:.config/x");

        let empty: Vec<String> = vec![];
        let mut e2 = sample();
        e2.preserve_paths = empty.join(":");
        assert_eq!(e2.into_env_pairs()[5].1, ""); // empty string, key still present
    }

    /// Point the env-file read at a fixture and clear the env override, so the
    /// FILE branch is what runs — on any host, provisioned or not.
    fn with_env_file(contents: Option<&str>) -> (crate::test_support::EnvScope, tempfile::TempDir) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("agentlinux.env");
        if let Some(c) = contents {
            std::fs::write(&path, c).unwrap();
        }
        let mut scope = crate::test_support::EnvScope::new();
        scope
            .unset("AGENTLINUX_USER")
            .set("AGENTLINUX_ENV_FILE", &path);
        (scope, dir)
    }

    #[test]
    fn resolve_user_from_valid_env_override() {
        let mut scope = crate::test_support::EnvScope::new();
        scope.set("AGENTLINUX_USER", "claude");
        assert_eq!(resolve_install_user(), "claude");
    }

    #[test]
    fn resolve_user_malformed_env_falls_back_to_agent() {
        let mut scope = crate::test_support::EnvScope::new();
        scope.set("AGENTLINUX_USER", "Bad User!");
        assert_eq!(resolve_install_user(), "agent");
    }

    #[test]
    fn resolve_user_absent_everywhere_is_agent() {
        // Env override unset AND the env file absent — the dev-host default.
        // Pointed at a path that does not exist rather than guarded by "if the
        // real /etc file is missing", so it asserts on a provisioned host too.
        let (_scope, _dir) = with_env_file(None);
        assert_eq!(resolve_install_user(), "agent");
    }

    #[test]
    fn resolve_user_reads_the_env_file_line() {
        // The FILE branch of the real function — not a re-typed copy of its parse
        // loop. Deleting that branch now fails here.
        let (_scope, _dir) = with_env_file(Some("SOME_OTHER=1\nAGENTLINUX_USER=claude\nMORE=2\n"));
        assert_eq!(resolve_install_user(), "claude");
    }

    #[test]
    fn env_override_beats_the_env_file_line() {
        let (mut scope, _dir) = with_env_file(Some("AGENTLINUX_USER=fromfile\n"));
        scope.set("AGENTLINUX_USER", "fromenv");
        assert_eq!(resolve_install_user(), "fromenv");
    }

    #[test]
    fn a_malformed_env_file_line_falls_back_to_agent() {
        // A tampered/garbage value must never reach a `sudo -u` argv (T-56-02).
        let (_scope, _dir) = with_env_file(Some("AGENTLINUX_USER=../../root\n"));
        assert_eq!(resolve_install_user(), "agent");
    }

    #[test]
    fn only_the_first_env_file_line_counts() {
        let (_scope, _dir) = with_env_file(Some("AGENTLINUX_USER=first\nAGENTLINUX_USER=second\n"));
        assert_eq!(resolve_install_user(), "first");
    }

    #[test]
    fn resolve_install_user_from_covers_every_precedence_branch() {
        // The pure core, stated as a table — no process env, no filesystem.
        assert_eq!(resolve_install_user_from(Some("claude"), None), "claude");
        assert_eq!(
            resolve_install_user_from(None, Some("AGENTLINUX_USER=claude\n")),
            "claude"
        );
        // Trailing whitespace is trimmed (the env file is written by a shell).
        assert_eq!(
            resolve_install_user_from(None, Some("AGENTLINUX_USER=claude  \n")),
            "claude"
        );
        // A key that merely CONTAINS the name is not the key.
        assert_eq!(
            resolve_install_user_from(None, Some("X_AGENTLINUX_USER=claude\n")),
            "agent"
        );
        assert_eq!(resolve_install_user_from(None, None), "agent");
        assert_eq!(resolve_install_user_from(Some("Bad User!"), None), "agent");
    }

    #[test]
    fn the_reserved_denylist_covers_root_and_the_systemd_prefix() {
        assert!(is_reserved_user_name("root"));
        assert!(is_reserved_user_name("daemon"));
        assert!(is_reserved_user_name("nobody"));
        // Case-insensitive, so a capitalised spelling cannot slip past.
        assert!(is_reserved_user_name("Root"));
        // The whole systemd-* family, including names not on the literal list.
        assert!(is_reserved_user_name("systemd-network"));
        assert!(is_reserved_user_name("systemd-anything-at-all"));
        // …and a normal name is not reserved.
        assert!(!is_reserved_user_name("agent"));
        assert!(!is_reserved_user_name("claude"));
    }

    #[test]
    fn a_reserved_name_is_well_formed_and_must_not_silently_fall_back() {
        // The deliberate split between the two predicates, pinned so the
        // asymmetry reads as a decision rather than an oversight.
        //
        // `root` PASSES the charset check — it is a perfectly legal POSIX
        // username — so the resolution path returns it verbatim rather than
        // degrading to `agent`. Falling back here would silently provision a
        // different user than the operator configured. It is the state-creating
        // verb that must refuse it, loudly:
        // `cmd/provision::default_path_reserved_name_is_ex_usage` asserts the
        // EX_USAGE exit.
        assert!(is_valid_install_user("root"));
        assert!(is_reserved_user_name("root"));
        assert_eq!(resolve_install_user_from(Some("root"), None), "root");

        // A MALFORMED value is the other case: nothing sensible to surface, and
        // every verb resolves a user, so it degrades to the default instead.
        assert!(!is_valid_install_user("Bad User!"));
        assert_eq!(resolve_install_user_from(Some("Bad User!"), None), "agent");
    }

    #[test]
    fn env_file_path_defaults_to_etc_and_honors_the_override() {
        let mut scope = crate::test_support::EnvScope::new();
        scope.unset("AGENTLINUX_ENV_FILE");
        assert_eq!(env_file_path(), AGENTLINUX_ENV_FILE);
        scope.set("AGENTLINUX_ENV_FILE", "/tmp/fixture.env");
        assert_eq!(env_file_path(), "/tmp/fixture.env");
        // An empty override is not an override.
        scope.set("AGENTLINUX_ENV_FILE", "");
        assert_eq!(env_file_path(), AGENTLINUX_ENV_FILE);
    }

    #[test]
    fn canonical_path_for_agent_is_byte_identical() {
        // runner.test.ts:80-88 — the exact AGENT_PATH literal.
        assert_eq!(
            canonical_path("/home/agent"),
            "/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin"
        );
    }

    #[test]
    fn full_child_env_assembles_path_locale_and_extra_override() {
        let env = full_child_env(
            sample(),
            "agent",
            &[
                ("CUSTOM_VAR".to_string(), "hello".to_string()),
                ("LANG".to_string(), "en_US.UTF-8".to_string()),
            ],
        );
        // Helper: last value wins (mirrors the TS spread dedup).
        let get = |k: &str| -> Option<String> {
            env.iter()
                .rev()
                .find(|(key, _)| key == k)
                .map(|(_, v)| v.clone())
        };
        assert_eq!(
            get("PATH").as_deref(),
            Some("/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin")
        );
        assert_eq!(get("HOME").as_deref(), Some("/home/agent"));
        assert_eq!(
            get("NPM_CONFIG_PREFIX").as_deref(),
            Some("/home/agent/.npm-global")
        );
        assert_eq!(get("LC_ALL").as_deref(), Some("C.UTF-8"));
        assert_eq!(get("CUSTOM_VAR").as_deref(), Some("hello"));
        // extraEnv LANG overrides the base C.UTF-8.
        assert_eq!(get("LANG").as_deref(), Some("en_US.UTF-8"));
        // The 6 AGENTLINUX_* pairs are present.
        assert_eq!(get("AGENTLINUX_PINNED_VERSION").as_deref(), Some("2.1.7"));
    }
}
