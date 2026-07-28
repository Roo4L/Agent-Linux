//! recipe_env.rs — the ONE typed source of the recipe env contract (VERB-03).
//!
//! Port of `plugin/cli/src/runner.ts:30-120`. Three responsibilities, all
//! I/O-bearing, so they live in the bin (NOT the pure `agentlinux-core`):
//!
//! 1. `RecipeEnv` + `into_env_pairs()` — the SIX `AGENTLINUX_*` key strings in
//!    exactly one place. A rename is a compile error, so the ~25 unchanged Bash
//!    recipes that read `${AGENTLINUX_*}` (proven by
//!    `plugin/catalog/agents/gsd/install.sh:7-8`) can never silently desync.
//! 2. `resolve_install_user()` — precedence `$AGENTLINUX_USER` >
//!    `/etc/agentlinux.env` `AGENTLINUX_USER=` line > `agent`, POSIX-charset
//!    re-validated (`^[a-z][a-z0-9_-]*$`) so a malformed/tampered value can never
//!    reach a `sudo -u` argv (T-56-02) — malformed falls back to `agent`.
//! 3. `full_child_env()` — the FULL child environment the dispatcher sets: the 6
//!    pairs PLUS an EXPLICIT canonical PATH (Pitfall 3: `sudo -E` alone drops
//!    PATH to secure_path), HOME, NPM_CONFIG_PREFIX, LANG/LC_ALL, then extraEnv
//!    appended so later keys override earlier (mirrors the TS spread order,
//!    runner.ts:110-119).
//!
//! `dead_code` is allowed at module scope for this Wave-0 scaffold: the public
//! surface here (`RecipeEnv`, `resolve_install_user`, `full_child_env`) is
//! consumed by `dispatcher::dispatch_recipe` (Task 3) and the Wave-1/2 verb
//! adapters (Plans 02/03). The `#[cfg(test)]` module exercises every item now,
//! so nothing is truly unreachable — the allow only silences the "not yet wired
//! into a non-test caller" lint until those plans land, keeping the per-task
//! tree warning-clean. Remove once the verb layer imports these.
#![allow(dead_code)]

use std::fs;

/// POSIX-portable username charset — MUST mirror `remediate::validate_user_name`
/// (`plugin/lib/remediate.sh`) and `runner.ts:20`. Belt-and-suspenders
/// re-validation of the configured install user before it flows into `sudo -u`.
const DEFAULT_INSTALL_USER: &str = "agent";
const AGENTLINUX_ENV_FILE: &str = "/etc/agentlinux.env";

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
/// CLI `<name>`/`<spec>`. When the Wave-1/2 verb adapters wire real callers, keep
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

/// True iff `name` matches `^[a-z][a-z0-9_-]*$` — the POSIX-portable username
/// charset. Hand-rolled (no regex crate) so the charset lives inline and the bin
/// stays dependency-light.
fn is_valid_install_user(name: &str) -> bool {
    let mut chars = name.chars();
    match chars.next() {
        Some(c) if c.is_ascii_lowercase() => {}
        _ => return false, // must start with [a-z]
    }
    chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-')
}

/// Resolve the install user catalog ops run as (runner.ts:30-43).
///
/// Precedence: `$AGENTLINUX_USER` > the `AGENTLINUX_USER=` line in
/// `/etc/agentlinux.env` (root-owned) > `agent`. A value failing the POSIX
/// charset (malformed env / tampered read) falls back to `agent` —
/// defense-in-depth for both the guard check and the `sudo -u` dispatch user
/// (T-56-02). The env-file read is I/O; it lives HERE in the bin, not the core.
pub fn resolve_install_user() -> String {
    // 1. Env override (bats seam, 23-install-user.bats). Empty/unset → fall through.
    let mut raw = match std::env::var("AGENTLINUX_USER") {
        Ok(v) if !v.is_empty() => Some(v),
        _ => None,
    };

    // 2. The AGENTLINUX_USER= line in the root-owned env file (multiline match).
    if raw.is_none() {
        if let Ok(txt) = fs::read_to_string(AGENTLINUX_ENV_FILE) {
            for line in txt.lines() {
                if let Some(val) = line.strip_prefix("AGENTLINUX_USER=") {
                    raw = Some(val.trim().to_string());
                    break;
                }
            }
        }
        // Absent/unreadable env file (dev host, pre-AL-50 install) → default.
    }

    // 3. Charset-validate or fall back to `agent`.
    match raw {
        Some(v) if is_valid_install_user(&v) => v,
        _ => DEFAULT_INSTALL_USER.to_string(),
    }
}

/// The canonical PATH for a user given their home — byte-identical to
/// `runner.ts:104` / `AGENT_PATH` for `agent`. Set EXPLICITLY (not via
/// `sudo -E`) because Ubuntu's `secure_path` overrides an inherited PATH
/// (Pitfall 3), which would let recipes resolve `npm` from `/usr/bin` (EACCES).
fn canonical_path(home: &str) -> String {
    format!("{home}/.npm-global/bin:{home}/.local/bin:/usr/local/bin:/usr/bin:/bin")
}

/// Assemble the FULL child environment the dispatcher sets (runner.ts:105-118).
///
/// The 6 `AGENTLINUX_*` pairs, PLUS the canonical PATH/HOME/NPM_CONFIG_PREFIX/
/// LANG/LC_ALL for `user`'s home, then `extra` (extraEnv) appended so later keys
/// override earlier — mirroring the TS spread order so an extraEnv `LANG`
/// overrides the base `C.UTF-8`. `agent_home` in `recipe` is expected to already
/// be `/home/{user}` (the caller derives it alongside the resolved user).
pub fn full_child_env(
    recipe: RecipeEnv,
    user: &str,
    extra: &[(String, String)],
) -> Vec<(String, String)> {
    let home = format!("/home/{user}");
    let mut env: Vec<(String, String)> = recipe
        .into_env_pairs()
        .into_iter()
        .map(|(k, v)| (k.to_string(), v))
        .collect();
    // Explicit canonical PATH + locale + npm prefix (Pitfall 3).
    env.push(("PATH".to_string(), canonical_path(&home)));
    env.push(("HOME".to_string(), home.clone()));
    env.push((
        "NPM_CONFIG_PREFIX".to_string(),
        format!("{home}/.npm-global"),
    ));
    env.push(("LANG".to_string(), "C.UTF-8".to_string()));
    env.push(("LC_ALL".to_string(), "C.UTF-8".to_string()));
    // extraEnv appended last so it overrides base keys (dispatcher/consumer
    // dedups by keeping the LAST value for a key — matching the TS spread).
    env.extend(extra.iter().cloned());
    env
}

#[cfg(test)]
mod recipe_env_tests {
    use super::*;
    use std::sync::Mutex;

    // resolve_install_user reads a PROCESS-GLOBAL env var; serialize the tests
    // that mutate it so they don't race under cargo's parallel test threads.
    static ENV_LOCK: Mutex<()> = Mutex::new(());

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
        // The colon-join is the CALLER's job (loader.ts) — here we assert the
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

    #[test]
    fn resolve_user_from_valid_env_override() {
        let _g = ENV_LOCK.lock().unwrap();
        std::env::set_var("AGENTLINUX_USER", "claude");
        assert_eq!(resolve_install_user(), "claude");
        std::env::remove_var("AGENTLINUX_USER");
    }

    #[test]
    fn resolve_user_malformed_env_falls_back_to_agent() {
        let _g = ENV_LOCK.lock().unwrap();
        std::env::set_var("AGENTLINUX_USER", "Bad User!");
        assert_eq!(resolve_install_user(), "agent");
        std::env::remove_var("AGENTLINUX_USER");
    }

    #[test]
    fn resolve_user_absent_everywhere_is_agent() {
        let _g = ENV_LOCK.lock().unwrap();
        std::env::remove_var("AGENTLINUX_USER");
        // On this dev host /etc/agentlinux.env is absent → default `agent`.
        // (If a host DID have the file, the env override being unset means the
        //  file line wins; the default-branch assertion still holds when absent.)
        if !std::path::Path::new(AGENTLINUX_ENV_FILE).exists() {
            assert_eq!(resolve_install_user(), "agent");
        }
    }

    #[test]
    fn resolve_user_from_env_file_line() {
        // Exercise the parse logic directly against a temp file's content shape,
        // independent of /etc (which we can't write in the test sandbox). This
        // mirrors the exact strip_prefix + trim + charset path in
        // resolve_install_user's file branch.
        let txt = "SOME_OTHER=1\nAGENTLINUX_USER=claude\nMORE=2\n";
        let mut found = None;
        for line in txt.lines() {
            if let Some(val) = line.strip_prefix("AGENTLINUX_USER=") {
                found = Some(val.trim().to_string());
                break;
            }
        }
        let resolved = match found {
            Some(v) if is_valid_install_user(&v) => v,
            _ => DEFAULT_INSTALL_USER.to_string(),
        };
        assert_eq!(resolved, "claude");
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
