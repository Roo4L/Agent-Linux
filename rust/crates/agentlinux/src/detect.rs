//! detect.rs — the DETECT-phase host scanner that WRITES the detect cache.
//!
//! Port of `plugin/lib/detect/agents.sh` (`detect::agents_probe`). The `provision`
//! verb runs [`scan_and_write`] AFTER the step loop (so PATH wiring + Node are in
//! place) and BEFORE agent adoption, populating `/run/agentlinux-detect.json` with
//! the `.agents` section. A subsequent `agentlinux install <id>` / `adopt --all`
//! then reads that cache (via [`crate::cache`]) and the pure gates
//! (`detect_gates::{reuse_gate,remediate_gate}`) can fire REUSE-03 / REMEDIATE-04.
//!
//! # Why the provisioner has to write it
//! The Rust `cmd/install.rs` REMEDIATE-04 handler is fully wired — but it consults
//! the detect cache to learn a brownfield binary's on-host PATH. With no writer,
//! every `install` saw an absent cache → `detected = None` → the remediation gate
//! never fired and the verb fell straight through to a plain install. This module
//! is that writer.
//!
//! # The pure/I-O seam
//! Every reader here does I/O (catalog read, a login-shell `command -v`, a version
//! probe, `stat`). The DECISION stays in the pure `agentlinux-core` gates — this
//! module only gathers host facts and serializes them. The pure helpers
//! ([`verify_binary`], [`agent_rows`], [`extract_semver`], [`classify`]) carry the
//! `#[cfg(test)]` coverage.
//!
//! # Security
//! Probed binary stdout is NEVER fed to a shell evaluator: the version regex-scan
//! ([`extract_semver`]) accepts only `[0-9.]` + a lowercase-alnum prerelease tail,
//! so an adversarial banner cannot inject shell/ANSI bytes into the cache. The
//! GSD VERSION-file fallback is owner-gated (a planted symlink to a root-only file
//! reports `root` → refused) exactly as the Bash probe did.

use crate::catalog::{self, FullCatalogEntry};
use crate::dispatcher;

/// The original three carry bespoke version-probe flags + a strict `--help`-exit-0
/// health gate their behavior contract asserts; every other tool uses the generic
/// probe. Mirrors `DETECT_AGENT_LEGACY_IDS` (detect/agents.sh).
const LEGACY_IDS: &[&str] = &["claude-code", "gsd", "playwright-cli"];

/// A resolved per-agent detect record — the 6 fields the Bash probe wrote. Only
/// `id`/`status`/`path`/`version` are read back by [`crate::cache`]; `binary` +
/// `owner` are retained for cache-shape parity with the Bash `detect::agents_probe`
/// output and any external reader.
#[derive(Debug, Clone, PartialEq, Eq)]
struct AgentRecord {
    id: String,
    binary: String,
    path: String,
    version: String,
    owner: String,
    status: String,
}

/// Extract the `command -v <bin>` binary token from a `post_install_verify` string.
/// Mirrors the Bash `capture("command -v (?<b>[^ ]+)")` — the first token after
/// the FIRST `command -v `. `None` when the marker is absent or the token empty.
fn verify_binary(verify: &str) -> Option<String> {
    let idx = verify.find("command -v ")?;
    let rest = &verify[idx + "command -v ".len()..];
    let tok = rest.split_whitespace().next()?;
    (!tok.is_empty()).then(|| tok.to_string())
}

/// Derive `(id, binary)` rows for every PATH-resolvable catalog tool: non-`mcp`,
/// non-`test_only` entries whose `post_install_verify` contains `command -v <bin>`.
/// MCP entries (registration-based, no PATH binary) and the `test-dummy` fixture
/// are excluded. Mirrors `__det_agent_rows` (catalog order preserved).
fn agent_rows(entries: &[FullCatalogEntry]) -> Vec<(String, String)> {
    entries
        .iter()
        .filter(|e| !e.test_only && e.source_kind.as_deref() != Some("mcp"))
        .filter_map(|e| {
            let bin = verify_binary(e.post_install_verify.as_deref()?)?;
            Some((e.id.clone(), bin))
        })
        .collect()
}

/// Extract the FIRST `MAJOR.MINOR.PATCH(-prerelease)?` semver substring from
/// arbitrary probe output, or `None`. Rust port of the Bash
/// `grep -Eo '[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?'` — leftmost match, digits +
/// dots + a lowercase-alnum-dot-hyphen prerelease tail only. A leading `v`/`V` is
/// naturally excluded (matching starts at the first digit → the Bash `tr -d 'vV'`).
fn extract_semver(text: &str) -> Option<String> {
    let bytes = text.as_bytes();
    let n = bytes.len();
    for start in 0..n {
        if !bytes[start].is_ascii_digit() {
            continue;
        }
        if let Some(end) = match_semver_at(bytes, start) {
            return Some(text[start..end].to_string());
        }
    }
    None
}

/// Try to match `\d+\.\d+\.\d+(-[a-z0-9.-]+)?` anchored at `start`. Returns the
/// end byte-index (exclusive) on success. Greedy on each digit run + the
/// prerelease tail, matching `grep -Eo` leftmost-longest at this position.
fn match_semver_at(bytes: &[u8], start: usize) -> Option<usize> {
    let n = bytes.len();
    let digits = |i: &mut usize| -> bool {
        let s = *i;
        while *i < n && bytes[*i].is_ascii_digit() {
            *i += 1;
        }
        *i > s
    };
    let mut i = start;
    // MAJOR
    if !digits(&mut i) {
        return None;
    }
    // .MINOR
    if i >= n || bytes[i] != b'.' {
        return None;
    }
    i += 1;
    if !digits(&mut i) {
        return None;
    }
    // .PATCH
    if i >= n || bytes[i] != b'.' {
        return None;
    }
    i += 1;
    if !digits(&mut i) {
        return None;
    }
    // Optional -prerelease ([a-z0-9.-]+, at least one char after the hyphen).
    if i < n && bytes[i] == b'-' {
        let mut j = i + 1;
        let tail_start = j;
        while j < n
            && (bytes[j].is_ascii_digit()
                || bytes[j].is_ascii_lowercase()
                || bytes[j] == b'.'
                || bytes[j] == b'-')
        {
            j += 1;
        }
        if j > tail_start {
            i = j;
        }
    }
    Some(i)
}

/// Classify a probed agent: `absent` is handled by the caller (no binary).
/// Present → `healthy` when a version parsed AND (for a legacy id) `--help` exited
/// 0; else `broken`. Mirrors the two `detect::agents_probe` health arms.
fn classify(id: &str, version: &str, legacy_help_ok: bool) -> &'static str {
    let versioned = !version.is_empty();
    let healthy = if LEGACY_IDS.contains(&id) {
        legacy_help_ok && versioned
    } else {
        versioned
    };
    if healthy {
        "healthy"
    } else {
        "broken"
    }
}

/// The child env for the login-shell probe hop: the canonical `PATH`/`HOME` for
/// the install home (so `~/.local/bin` + `~/.npm-global/bin` resolve even before
/// the profile sources them) plus every `AGENTLINUX_*` seam. Mirrors the adoption
/// child env — a login shell then layers `/etc/profile.d/agentlinux.sh` on top.
fn probe_env(home: &str) -> Vec<(String, String)> {
    let mut env: Vec<(String, String)> = vec![
        ("PATH".to_string(), crate::recipe_env::canonical_path(home)),
        ("HOME".to_string(), home.to_string()),
    ];
    for (k, v) in std::env::vars() {
        if k.starts_with("AGENTLINUX_") {
            env.push((k, v));
        }
    }
    env
}

/// Run `script` as `user` through a login shell (sourcing the agent profile so
/// PATH resolves agent-owned bins), returning `(exit_code, trimmed_stdout)`.
/// Bounded so a wedged probe can never hang an unattended provision.
fn login_run(user: &str, home: &str, script: &str) -> (i32, String) {
    let argv: Vec<String> = ["bash", "--login", "-c", script]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let r = dispatcher::as_user(user, &argv, &probe_env(home), false, Some(PROBE_TIMEOUT_MS));
    (r.exit_code, r.stdout.trim().to_string())
}

/// Per-probe timeout — a version/`command -v` shell-out is sub-second; finite so a
/// hung binary cannot wedge the whole scan.
const PROBE_TIMEOUT_MS: u64 = 8_000;

/// Probe an agent's version via its id-specific flag(s). The legacy three parse
/// `--version` (gsd: `--help`, no `--version` flag); the rest try
/// `--version`/`version`/`--help` in turn. First semver wins. `binary` is a
/// catalog-sourced token (trusted); it is the ONLY interpolated value.
fn probe_version(user: &str, home: &str, id: &str, binary: &str) -> String {
    let flags: &[&str] = match id {
        "claude-code" | "playwright-cli" => &["--version"],
        "gsd" => &["--help"],
        _ => &["--version", "version", "--help"],
    };
    for flag in flags {
        let (_rc, out) = login_run(user, home, &format!("{binary} {flag} 2>/dev/null"));
        if let Some(v) = extract_semver(&out) {
            return v;
        }
    }
    String::new()
}

/// `user:group` owner of `path` (following symlinks, as Bash `stat -c '%U:%G'`
/// does), or `"unknown"` on any error. Not read by the pure gate — retained for
/// cache-shape parity.
fn owner_of(path: &str) -> String {
    use std::os::unix::fs::MetadataExt;
    let md = match std::fs::metadata(path) {
        Ok(m) => m,
        Err(_) => return "unknown".to_string(),
    };
    let user = nix::unistd::User::from_uid(nix::unistd::Uid::from_raw(md.uid()))
        .ok()
        .flatten()
        .map_or_else(|| md.uid().to_string(), |u| u.name);
    let group = nix::unistd::Group::from_gid(nix::unistd::Gid::from_raw(md.gid()))
        .ok()
        .flatten()
        .map_or_else(|| md.gid().to_string(), |g| g.name);
    format!("{user}:{group}")
}

/// Probe a single `(id, binary)` row into an [`AgentRecord`]. Resolves the binary
/// on the install user's login PATH; on a miss, GSD falls back to its deployed
/// `~/.claude/gsd-core/VERSION` (owner-gated). Absent everywhere → `status=absent`.
fn probe_one(user: &str, home: &str, id: &str, binary: &str) -> AgentRecord {
    let (rc, bin_path) = login_run(user, home, &format!("command -v {binary}"));
    let resolved = if rc == 0 && !bin_path.is_empty() {
        Some(bin_path)
    } else {
        None
    };

    if let Some(path) = resolved {
        let version = probe_version(user, home, id, binary);
        let owner = owner_of(&path);
        // Legacy ids additionally gate health on `--help` exit 0.
        let legacy_help_ok = if LEGACY_IDS.contains(&id) {
            login_run(user, home, &format!("{binary} --help >/dev/null 2>&1")).0 == 0
        } else {
            true
        };
        let status = classify(id, &version, legacy_help_ok);
        return AgentRecord {
            id: id.to_string(),
            binary: binary.to_string(),
            path,
            version,
            owner,
            status: status.to_string(),
        };
    }

    // GSD deployed-system fallback: its binary is a bootstrapper, so an absent
    // binary is also classified from the deployed VERSION file — but only when
    // that file is owned by the install user (a planted symlink to a root file
    // reports root → refuse, treat as absent).
    if id == "gsd" {
        let ver_file = format!("{home}/.claude/gsd-core/VERSION");
        if let Some(rec) = gsd_version_file_record(user, &ver_file) {
            return rec;
        }
    }

    AgentRecord {
        id: id.to_string(),
        binary: binary.to_string(),
        path: String::new(),
        version: String::new(),
        owner: String::new(),
        status: "absent".to_string(),
    }
}

/// The GSD deployed-`VERSION`-file presence signal, owner-gated. `Some` only when
/// the file exists AND is owned by `user`; a non-empty trimmed body → healthy,
/// empty → broken. `None` (→ caller reports `absent`) when missing or foreign-owned.
fn gsd_version_file_record(user: &str, ver_file: &str) -> Option<AgentRecord> {
    use std::os::unix::fs::MetadataExt;
    let md = std::fs::metadata(ver_file).ok()?;
    let owned =
        matches!(nix::unistd::User::from_name(user), Ok(Some(u)) if u.uid.as_raw() == md.uid());
    if !owned {
        return None;
    }
    let ver: String = std::fs::read_to_string(ver_file)
        .ok()?
        .split_whitespace()
        .collect();
    let status = if ver.is_empty() { "broken" } else { "healthy" };
    Some(AgentRecord {
        id: "gsd".to_string(),
        binary: "gsd-core".to_string(),
        path: ver_file.to_string(),
        version: ver,
        owner: owner_of(ver_file),
        status: status.to_string(),
    })
}

/// Serialize the records into the `{agents: [...]}` cache doc + write it to the
/// resolved detect-cache path (`$AGENTLINUX_DETECT_CACHE` else
/// `/run/agentlinux-detect.json`). Best-effort: returns the write error for the
/// caller to log; never panics.
fn write_cache(records: &[AgentRecord]) -> std::io::Result<()> {
    let agents: Vec<serde_json::Value> = records
        .iter()
        .map(|r| {
            serde_json::json!({
                "id": r.id,
                "binary": r.binary,
                "path": r.path,
                "version": r.version,
                "owner": r.owner,
                "status": r.status,
            })
        })
        .collect();
    let doc = serde_json::json!({ "agents": agents });
    let body = serde_json::to_string_pretty(&doc).unwrap_or_else(|_| "{\"agents\":[]}".to_string());
    std::fs::write(crate::cache::detect_cache_path(), body)
}

/// Scan the host for every catalog agent + write the detect cache's `.agents`
/// section. The `provision` verb's post-step, best-effort call: a catalog-read or
/// cache-write failure is logged and swallowed (a provision that already did the
/// real work must not fail because detection could not persist), but the common
/// path leaves `/run/agentlinux-detect.json` populated so REUSE-03 / REMEDIATE-04
/// can fire on the next `agentlinux install`.
pub fn scan_and_write(user: &str, home: &str) {
    let catalog_dir = catalog::resolve_catalog_dir();
    let entries = match catalog::load_catalog(&catalog_dir, false) {
        Ok(e) => e,
        Err(e) => {
            crate::provision::log::line(&format!(
                "agentlinux provision: detect scan skipped — catalog unreadable ({e}); \
                 REUSE-03/REMEDIATE-04 will see an absent cache"
            ));
            return;
        }
    };
    let records: Vec<AgentRecord> = agent_rows(&entries)
        .into_iter()
        .map(|(id, binary)| probe_one(user, home, &id, &binary))
        .collect();
    if let Err(e) = write_cache(&records) {
        crate::provision::log::line(&format!(
            "agentlinux provision: detect cache write failed ({e}); \
             REUSE-03/REMEDIATE-04 will see an absent cache"
        ));
    }
}

#[cfg(test)]
mod detect_tests {
    use super::*;

    #[test]
    fn verify_binary_extracts_first_token() {
        assert_eq!(
            verify_binary("command -v claude").as_deref(),
            Some("claude")
        );
        assert_eq!(
            verify_binary("command -v gsd-core >/dev/null 2>&1").as_deref(),
            Some("gsd-core")
        );
        // Marker absent → None.
        assert_eq!(verify_binary("test -f ~/.claude"), None);
        // Marker present but nothing after → None.
        assert_eq!(verify_binary("command -v "), None);
    }

    fn entry(
        id: &str,
        source_kind: Option<&str>,
        verify: Option<&str>,
        test_only: bool,
    ) -> FullCatalogEntry {
        FullCatalogEntry {
            id: id.to_string(),
            display_name: id.to_string(),
            description: String::new(),
            homepage: None,
            license: None,
            source_kind: source_kind.map(str::to_string),
            npm_package_name: None,
            requires_secret: None,
            secret_env: None,
            endpoint_url: None,
            pinned_version: "1.0.0".to_string(),
            version_constraint: None,
            compatibility_window: None,
            install_recipe_path: "install.sh".to_string(),
            uninstall_recipe_path: "uninstall.sh".to_string(),
            rewire_recipe_path: None,
            post_install_verify: verify.map(str::to_string),
            preserve_paths_file: None,
            preserve_paths: None,
            tags: Vec::new(),
            test_only,
        }
    }

    #[test]
    fn agent_rows_filters_mcp_test_and_verifyless_entries() {
        let entries = vec![
            entry(
                "claude-code",
                Some("script"),
                Some("command -v claude"),
                false,
            ),
            entry("github-mcp", Some("mcp"), Some("command -v gh-mcp"), false), // mcp → excluded
            entry("test-dummy", Some("script"), Some("command -v dummy"), true), // test_only → excluded
            entry("no-verify", Some("binary"), None, false), // no verify → excluded
            entry(
                "gitleaks",
                Some("binary"),
                Some("command -v gitleaks version"),
                false,
            ),
        ];
        let rows = agent_rows(&entries);
        assert_eq!(
            rows,
            vec![
                ("claude-code".to_string(), "claude".to_string()),
                ("gitleaks".to_string(), "gitleaks".to_string()),
            ]
        );
    }

    #[test]
    fn extract_semver_finds_first_match() {
        assert_eq!(extract_semver("1.2.3").as_deref(), Some("1.2.3"));
        assert_eq!(
            extract_semver("v0.42.4 (Claude Code)").as_deref(),
            Some("0.42.4")
        );
        assert_eq!(
            extract_semver("Version: 2.11.0-beta.1 build").as_deref(),
            Some("2.11.0-beta.1")
        );
        // Leading two-part number is skipped; the real 3-part match wins.
        assert_eq!(
            extract_semver("released 2024 as 1.7.0").as_deref(),
            Some("1.7.0")
        );
        // No 3-part semver → None (adversarial / non-version output).
        assert_eq!(extract_semver("no version here 12.9"), None);
        assert_eq!(extract_semver(""), None);
    }

    #[test]
    fn extract_semver_rejects_shell_metacharacters_in_prerelease() {
        // A prerelease tail stops at the first non-[a-z0-9.-] byte — `$(...)`
        // injection bytes never enter the captured version.
        assert_eq!(
            extract_semver("1.2.3-rc1;rm -rf /").as_deref(),
            Some("1.2.3-rc1")
        );
        assert_eq!(
            extract_semver("1.2.3-a$(whoami)").as_deref(),
            Some("1.2.3-a")
        );
    }

    #[test]
    fn classify_legacy_requires_help_ok_and_version() {
        // Legacy: needs BOTH a version and --help exit 0.
        assert_eq!(classify("claude-code", "1.2.3", true), "healthy");
        assert_eq!(classify("claude-code", "1.2.3", false), "broken");
        assert_eq!(classify("claude-code", "", true), "broken");
        // Generic: version alone is the health signal (--help conventions vary).
        assert_eq!(classify("gitleaks", "8.18.0", false), "healthy");
        assert_eq!(classify("gitleaks", "", true), "broken");
    }
}
