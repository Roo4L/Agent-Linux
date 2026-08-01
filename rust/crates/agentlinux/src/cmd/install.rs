//! cmd/install.rs — `agentlinux install <name>` (CLI-03, VERB-01/02/03).
//!
//! The decision flow:
//! loadCatalog → resolve entry → honor test_only → REUSE-03 / REMEDIATE-04
//! short-circuits → decideVersion → dispatchRecipe → writeSentinel. This is the
//! FIRST verb to exercise the dispatcher (VERB-02) on a REAL recipe with
//! the RecipeEnv contract (VERB-03) end-to-end.
//!
//! # The pure/adapter seam
//! The DECISION lives in the pure core: `reuse_gate`/`remediate_gate`
//! (detect_gates.rs) + `decide_version` (classify.rs). The verb NEVER re-derives.
//! The post-gate host I/O — `tryReuse`'s `statSync` reuse re-validation
//! (install.ts:183-188 via the shared cache adapter) and the post-uninstall
//! `existsSync` — lives HERE in the adapter, not in the pure gate.
//!
//! # DI seam
//! A `RecipeDispatcher` fn is injected so unit tests exercise the branch selection
//! plus the exit map and literals without spawning a real recipe (mirrors the TS
//! `dispatcher?` DI param). Production passes `dispatcher::dispatch_recipe`.

use crate::catalog;
use crate::cli::InstallArgs;
use crate::dispatcher::{self, Capture, RecipeDispatcher};
use crate::recipe_env::{recipe_child_env, recipe_path, resolve_install_user};
use crate::rewire;
use crate::sentinel::{self, Sentinel};
use crate::{agent_home, canonical_path, host_paths};
use agentlinux_core::classify::decide_version;
use agentlinux_core::detect_gates::{remediate_gate, reuse_gate, RemediateReason};
use agentlinux_core::semver_shim;
use agentlinux_core::types::CatalogEntry as CoreCatalogEntry;
use std::io::IsTerminal;
use std::process::ExitCode;

const EX_USAGE: u8 = 64;
const EX_DATAERR: u8 = 65;

/// Where the verb's user-visible lines go.
///
/// The output strings ARE the acceptance contract — `▸ installing`, `[REUSE-03]`,
/// `[REMEDIATE-04]`, `[DRY-RUN]` are grepped byte-for-byte by the bats suite — so
/// they need a sink a test can read back. Without one the only thing a Rust test
/// could do was re-`format!` the same literals inside its own body and compare
/// them to themselves, which passes even if the verb prints nothing at all.
pub struct Out<'a> {
    pub out: &'a mut dyn std::io::Write,
    pub err: &'a mut dyn std::io::Write,
}

/// A line to stdout / stderr. Write errors on a closed pipe are not the verb's
/// business — the exit code is.
macro_rules! outln {
    ($o:expr, $($arg:tt)*) => { let _ = writeln!($o.out, $($arg)*); };
}
macro_rules! errln {
    ($o:expr, $($arg:tt)*) => { let _ = writeln!($o.err, $($arg)*); };
}
// `cmd/provision.rs` writes its detection report and its [DRY-RUN] markers
// through the same sink, so the two verbs share one pair of line macros rather
// than each growing its own.
pub(crate) use {errln, outln};

/// "Does this path exist on the host?" — the REMEDIATE-04 post-uninstall check,
/// injected.
///
/// The canonical path comes from a hardcoded map (`/home/agent/.local/bin/claude`
/// and friends), so a test cannot move it out of the way. Reading the real
/// filesystem therefore made the remediate test pass only on a host WITHOUT
/// Claude Code installed — it went red on the product's primary deployment, and
/// in the QEMU suite after `agentlinux install claude-code`. Same class of
/// host-coupling as reading the real /etc/sudoers.d.
pub type PathExists = fn(&std::path::Path) -> bool;

/// Whether the REUSE-03 gate may run at all.
///
/// Three separate reasons to skip it, and each is a different intent:
/// `--force` means "reinstall regardless", `--version` means "I want THIS
/// version, not whatever is lying around", and an existing sentinel means the
/// agent is already managed so there is nothing to adopt.
///
/// Extracted from `install_into` because the condition was only reachable by
/// running the whole verb, and three mutants lived in it: turning either `&&`
/// into `||` reuses a pre-existing binary when the operator explicitly asked
/// for a fresh or pinned install, and `delete !` inverts `--force` into the
/// only case that DOES reuse.
const fn reuse_is_eligible(force: bool, explicit_version: bool, already_managed: bool) -> bool {
    !force && !explicit_version && !already_managed
}

/// Whether the REMEDIATE-04 gate may run.
///
/// Same first two reasons as [`reuse_is_eligible`] — but an existing sentinel is
/// NOT a reason to skip: a managed agent can still have drifted to a
/// non-canonical path, which is exactly what remediation is for.
const fn remediate_is_eligible(force: bool, explicit_version: bool) -> bool {
    !force && !explicit_version
}

/// The production check.
fn real_path_exists(p: &std::path::Path) -> bool {
    p.exists()
}

/// "Is stdin a terminal?" — the REMEDIATE-04 consent surface, injected.
///
/// Read inline it made the verb's verdict depend on whether the suite was run
/// from a terminal: `the_remediate_arm_…` asserted exit 65 (refused, non-TTY)
/// and got exit 1 under a pty, because the TTY branch auto-passes. A test whose
/// result depends on the runner's terminal is the same defect class as one that
/// depends on the runner's uid — and it fails on a developer's machine while
/// passing on CI, which is the worse direction.
pub type IsTty = fn() -> bool;

/// The production check.
///
/// Not mutation-tested — ADR-019 §5, "production wiring adapters". This is the
/// one line that reads the ambient terminal, and it exists precisely so nothing
/// else does; a test that could observe it would have to attach or detach a real
/// pty around the process, which is the coupling the seam removes. Both mutants
/// (`-> true`, `-> false`) are therefore unkillable HERE while being observable
/// in production — `-> false` turns an interactive install's REMEDIATE-04
/// auto-pass into an exit-65 bail — so the behaviour they change is asserted
/// through the seam instead: `install_into` takes `IsTty`, and the consent arms
/// are covered from literals on both settings.
#[cfg_attr(test, mutants::skip)]
fn real_is_tty() -> bool {
    std::io::stdin().is_terminal()
}

/// `agentlinux install <name>` body.
#[must_use]
pub fn install(name: &str, opts: &InstallArgs) -> ExitCode {
    install_with(name, opts, dispatcher::dispatch_recipe)
}

/// DI-seam variant with the real stdout/stderr wired up.
#[must_use]
pub fn install_with(name: &str, opts: &InstallArgs, dispatch: RecipeDispatcher) -> ExitCode {
    let mut out = std::io::stdout();
    let mut err = std::io::stderr();
    install_into(
        name,
        opts,
        dispatch,
        real_path_exists,
        real_is_tty,
        &mut Out {
            out: &mut out,
            err: &mut err,
        },
    )
}

/// DI-seam variant — the testable core (tests inject a stub dispatcher).
#[must_use]
pub fn install_into(
    name: &str,
    opts: &InstallArgs,
    dispatch: RecipeDispatcher,
    path_exists: PathExists,
    is_tty: IsTty,
    o: &mut Out<'_>,
) -> ExitCode {
    // --dry-run + --yes is contradictory (dry-run never mutates; --yes is a
    // mutation gate). Reject upfront with exit 64.
    if opts.dry_run && opts.yes {
        errln!(
                o,
            "agentlinux install: contradictory flags — --dry-run forbids --yes (dry-run never mutates; --yes is a mutation gate)"
        );
        return ExitCode::from(EX_USAGE);
    }

    // loadCatalog(validate:true) — install is a mutation path.
    let catalog_dir = catalog::resolve_catalog_dir();
    let agents = match catalog::load_catalog(&catalog_dir, catalog::Validate::Required) {
        Ok(a) => a,
        Err(e) => {
            errln!(o, "{e}");
            return ExitCode::from(1);
        }
    };

    let Some(entry) = catalog::find_entry(&agents, name, o.err) else {
        return ExitCode::from(EX_USAGE);
    };

    // test_only entries are refused unless --include-test.
    if entry.test_only && !opts.include_test {
        errln!(
            o,
            "agentlinux: {name} is a test-only entry; pass --include-test to install"
        );
        return ExitCode::from(EX_USAGE);
    }

    // --version present but not valid semver → 64.
    if let Some(v) = opts.version.as_deref() {
        if semver_shim::valid(v).is_none() {
            errln!(o, "agentlinux: --version '{v}' is not a valid semver");
            return ExitCode::from(EX_USAGE);
        }
    }

    let existing = match sentinel::read_sentinel(&entry.id) {
        Ok(s) => s,
        Err(e) => {
            errln!(
                o,
                "agentlinux: failed to read sentinel for {}: {e}",
                entry.id
            );
            return ExitCode::from(1);
        }
    };

    let core_entry = CoreCatalogEntry::from(entry);
    let home = agent_home();
    let canonical = canonical_path(&entry.id);
    let user = resolve_install_user();

    // Compute the reuse/remediate candidates once (used by both --dry-run and the
    // real path). tryReuse is skipped on --force / --version / an existing sentinel;
    // tryRemediate is skipped on --force / --version (but fires even with a sentinel).
    let detected = crate::cache::read_cached_agent_by_id(&entry.id);
    let reuse_hit = if reuse_is_eligible(opts.force, opts.version.is_some(), existing.is_some()) {
        try_reuse(&core_entry, detected.as_ref(), canonical, &home)
    } else {
        None
    };
    let remediate_hit = if remediate_is_eligible(opts.force, opts.version.is_some()) {
        detected
            .as_ref()
            .and_then(|d| remediate_gate(&core_entry, d, host_paths(canonical, &home)))
    } else {
        None
    };

    // UX-01: --dry-run early-return. No dispatch, no sentinel.
    if opts.dry_run {
        // For dry-run, tryRemediate is only consulted when reuse didn't hit
        // (install.ts:80 — `!reuseHit`).
        let remediate_for_dry = if reuse_hit.is_none() {
            remediate_hit.as_ref()
        } else {
            None
        };
        let decision = if reuse_hit.is_some() {
            "reuse"
        } else if remediate_for_dry.is_some() {
            "remediate"
        } else {
            "create"
        };
        let would_action = match decision {
            "reuse" => format!(
                "short-circuit (binary at {})",
                reuse_hit.as_ref().map_or("?", |h| h.binary_path.as_str())
            ),
            "remediate" => {
                let r = remediate_for_dry.unwrap();
                format!(
                    "uninstall + reinstall (reason: {}; detected at {}; canonical at {})",
                    r.reason.as_str(),
                    r.detected_path,
                    r.canonical_path
                )
            }
            _ => format!("dispatch install.sh at version {}", entry.pinned_version),
        };
        // The Commander install command exposes no `--json` flag,
        // so install.ts's `opts.json` dry-run branch is unreachable in practice —
        // the CLI always prints the `[DRY-RUN]` text line. Match that behavior.
        outln!(
            o,
            "[DRY-RUN] {}: {decision} — would {would_action}",
            entry.id
        );
        return ExitCode::SUCCESS;
    }

    // REUSE-03: write a status:"reused" sentinel, no dispatch.
    if let Some(hit) = reuse_hit {
        let now = sentinel::now_iso8601();
        let mut s = Sentinel::new(
            entry.id.clone(),
            hit.version.clone(),
            "curated".into(),
            false,
        );
        s.installed_at = Some(now.clone());
        s.status = Some("reused".to_string());
        s.binary_path = Some(hit.binary_path.clone());
        s.detected_source = Some(hit.detected_source.clone());
        s.reused_at = Some(now);
        s.compatibility_window_at_reuse = entry.compatibility_window.clone();
        if let Err(e) = sentinel::write_sentinel(&s) {
            errln!(
                o,
                "agentlinux: failed to write sentinel for {}: {e}",
                entry.id
            );
            return ExitCode::from(1);
        }
        outln!(
            o,
            "[REUSE-03] {} reused: binary={} version={} (in window {}) status=healthy",
            entry.id,
            hit.binary_path,
            hit.version,
            entry.compatibility_window.as_deref().unwrap_or("")
        );
        return ExitCode::SUCCESS;
    }

    // REMEDIATE-04.
    if let Some(rem) = remediate_hit {
        let is_migration = rem.reason == RemediateReason::PathMismatch;
        let dv = rem.detected_version.as_deref();
        let dv_in_window = dv.is_some_and(|d| {
            entry
                .compatibility_window
                .as_deref()
                .is_some_and(|w| !w.is_empty() && semver_shim::satisfies(d, w))
        });
        let preserve_version = if is_migration && dv_in_window {
            dv
        } else {
            None
        };
        let install_version = preserve_version
            .map(str::to_string)
            .unwrap_or_else(|| entry.pinned_version.clone());
        let install_source = if preserve_version.is_some() {
            "override"
        } else {
            "curated"
        };
        let action_word = if is_migration {
            "migrate npm→native (uninstall + reinstall)"
        } else {
            "uninstall + reinstall"
        };

        // --yes is the sole consent surface (no env-var equivalent). TTY mode
        // auto-passes.
        let is_tty = is_tty();
        if !opts.yes && !is_tty {
            errln!(
                    o,
                "Refusing to proceed — 1 component needs Remediate (run with --yes to apply, or --dry-run to preview):\n"
            );
            errln!(
                o,
                "[BAIL] component={} reason={} hint=run with --yes to {}",
                entry.id,
                rem.reason.as_str(),
                if is_migration { "migrate" } else { "reinstall" }
            );
            errln!(
                    o,
                "\nExit code 65 (EX_DATAERR — incompatible host state). See agentlinux install --help."
            );
            return ExitCode::from(EX_DATAERR);
        }

        outln!(
                o,
            "[REMEDIATE-04] {} component={} reason={} detected_path={} canonical_path={} install_version={}{} — {}",
            entry.id,
            entry.id,
            rem.reason.as_str(),
            rem.detected_path,
            rem.canonical_path,
            install_version,
            if preserve_version.is_some() {
                " (preserving your version)"
            } else {
                ""
            },
            action_word
        );

        // Step 1: uninstall.sh. Version = existing sentinel version else the pin.
        let uninstall_version = existing
            .as_ref()
            .map(|s| s.version.clone())
            .unwrap_or_else(|| entry.pinned_version.clone());
        let uninstall_path = recipe_path(&catalog_dir, &entry.id, &entry.uninstall_recipe_path);
        let uninstall_env = recipe_child_env(entry, &uninstall_version, &catalog_dir, &user);
        let uninstall_result = dispatch(&user, &uninstall_path, &uninstall_env, Capture::Buffered);
        if uninstall_result.exit_code != 0 {
            errln!(
                o,
                "[REMEDIATE-04:uninstall-fail] {} uninstall.sh exited {}",
                entry.id,
                uninstall_result.exit_code
            );
            if !uninstall_result.stderr.is_empty() {
                errln!(o, "{}", uninstall_result.stderr);
            }
            return ExitCode::from(1);
        }

        // Post-uninstall verification: the binary must be gone
        // at BOTH the canonical + detected path, else abort (exit 1). ADAPTER I/O.
        let canonical_present = path_exists(std::path::Path::new(&rem.canonical_path));
        let detected_present = path_exists(std::path::Path::new(&rem.detected_path));
        if canonical_present || detected_present {
            errln!(
                    o,
                "[REMEDIATE-04:uninstall-incomplete] {} uninstall.sh exited 0 but binary still present (canonical={canonical_present} detected={detected_present})",
                entry.id
            );
            return ExitCode::from(1);
        }

        // Step 2: install.sh at install_version (streaming).
        let install_path = recipe_path(&catalog_dir, &entry.id, &entry.install_recipe_path);
        outln!(o, "▸ reinstalling {} {}…", entry.id, install_version);
        let install_env = recipe_child_env(entry, &install_version, &catalog_dir, &user);
        let install_result = dispatch(&user, &install_path, &install_env, Capture::Streamed);
        if install_result.exit_code != 0 {
            let now = sentinel::now_iso8601();
            let mut s = Sentinel::new(
                entry.id.clone(),
                install_version.clone(),
                install_source.into(),
                false,
            );
            s.installed_at = Some(now.clone());
            s.status = Some("broken-after-remediate".to_string());
            s.remediated_at = Some(now);
            s.remediate_failure_reason = Some("install-failed-post-uninstall".to_string());
            let _ = sentinel::write_sentinel(&s);
            errln!(
                    o,
                "[REMEDIATE-04:half-uninstalled] {} install.sh exited {} after uninstall succeeded — manual recovery needed (run agentlinux remove {} then agentlinux install {})",
                entry.id, install_result.exit_code, entry.id, entry.id
            );
            if !install_result.stderr.is_empty() {
                errln!(o, "{}", install_result.stderr);
            }
            return ExitCode::from(1);
        }

        // Step 3: success sentinel + remediated_at.
        let now = sentinel::now_iso8601();
        let mut s = Sentinel::new(
            entry.id.clone(),
            install_version.clone(),
            install_source.into(),
            false,
        );
        s.installed_at = Some(now.clone());
        s.status = Some("installed".to_string());
        s.remediated_at = Some(now);
        if let Err(e) = sentinel::write_sentinel(&s) {
            errln!(
                o,
                "agentlinux: failed to write sentinel for {}: {e}",
                entry.id
            );
            return ExitCode::from(1);
        }
        outln!(
            o,
            "[REMEDIATE-04] {}: {} at {install_version} ({install_source})",
            entry.id,
            if is_migration {
                "migrated to native"
            } else {
                "reinstalled"
            }
        );
        rewire::reconcile_cross_wiring(&entry.id, &agents, &catalog_dir.to_string_lossy(), &user);
        return ExitCode::SUCCESS;
    }

    // decideVersion — the pure decision.
    let decision = decide_version(
        &core_entry,
        opts.version.as_deref(),
        existing
            .as_ref()
            .map(agentlinux_core::types::Sentinel::from)
            .as_ref(),
    );

    // Idempotent short-circuit.
    if !opts.force {
        if let Some(ex) = existing.as_ref() {
            if semver_shim::eq(&ex.version, &decision.version).unwrap_or(false) {
                outln!(
                    o,
                    "{}: already installed at {} ({}); no-op",
                    entry.id,
                    ex.version,
                    ex.source
                );
                return ExitCode::SUCCESS;
            }
        }
    }

    // create path: dispatch install.sh streaming.
    let install_path = recipe_path(&catalog_dir, &entry.id, &entry.install_recipe_path);
    outln!(o, "▸ installing {} {}…", entry.id, decision.version);
    let env = recipe_child_env(entry, &decision.version, &catalog_dir, &user);
    let result = dispatch(&user, &install_path, &env, Capture::Streamed);
    if result.exit_code != 0 {
        errln!(
            o,
            "{}: install.sh failed (exit {})",
            entry.id,
            result.exit_code
        );
        if !result.stderr.is_empty() {
            errln!(o, "{}", result.stderr);
        }
        // Propagate the recipe exit code.
        return exit_from_code(result.exit_code);
    }

    let now = sentinel::now_iso8601();
    let mut s = Sentinel::new(
        entry.id.clone(),
        decision.version.clone(),
        decision.source.clone(),
        decision.sticky,
    );
    s.installed_at = Some(now);
    s.status = Some("installed".to_string());
    if let Err(e) = sentinel::write_sentinel(&s) {
        errln!(
            o,
            "agentlinux: failed to write sentinel for {}: {e}",
            entry.id
        );
        return ExitCode::from(1);
    }
    outln!(
        o,
        "{}: installed {} ({})",
        entry.id,
        decision.version,
        decision.source
    );
    rewire::reconcile_cross_wiring(&entry.id, &agents, &catalog_dir.to_string_lossy(), &user);
    ExitCode::SUCCESS
}

// ---------------------------------------------------------------------------
// Adapter helpers
// ---------------------------------------------------------------------------

/// The full `ReuseHit` — the pure `reuse_gate` verdict PLUS the host `statSync`
/// re-validation + the `detected_source` label. Mirrors the
/// TS `ReuseHit` shape.
struct ReuseHit {
    binary_path: String,
    version: String,
    detected_source: String,
}

/// tryReuse = the PURE `reuse_gate` + the host `std::fs::metadata(...).is_file()`
/// re-validation HERE in the adapter. Stale-cache safety: the
/// cache may report a binary that was removed since detect ran.
fn try_reuse(
    core_entry: &CoreCatalogEntry,
    detected: Option<&agentlinux_core::types::DetectedAgent>,
    canonical: Option<&str>,
    home: &str,
) -> Option<ReuseHit> {
    let candidate = reuse_gate(core_entry, detected?, host_paths(canonical, home))?;
    if !crate::cmd::is_regular_file(&candidate.path) {
        return None;
    }
    Some(ReuseHit {
        binary_path: candidate.path,
        version: candidate.version,
        detected_source: "pre-existing".to_string(),
    })
}

/// Map a recipe exit code to an `ExitCode` (0-255), collapsing an out-of-range
/// code to 1 like a shell would.
fn exit_from_code(code: i32) -> ExitCode {
    ExitCode::from(u8::try_from(code).unwrap_or(1))
}

#[cfg(test)]
mod install_tests {
    use super::*;
    use crate::dispatcher::DispatchResult;
    use tempfile::tempdir;

    /// REUSE-03 adopts a pre-existing binary — but only one that is actually
    /// THERE. `delete !` on the regular-file check survived, which inverts it:
    /// a binary that exists is refused and a path with nothing behind it is
    /// adopted, so the sentinel records a reuse of a file that is not present.
    /// Replacing the whole function with `None` survived too, which silently
    /// turns every REUSE-03 into a plain install.
    #[test]
    fn reuse_adopts_only_a_binary_that_is_really_there() {
        use agentlinux_core::types::DetectedAgent;

        let dir = tempdir().unwrap();
        let bin = dir.path().join("claude");
        let canonical = bin.to_str().unwrap();

        let entry: crate::catalog::FullCatalogEntry = serde_json::from_value(serde_json::json!({
            "id": "claude-code", "display_name": "C", "description": "d",
            "source_kind": "script", "pinned_version": "2.1.98",
            "install_recipe_path": "install.sh", "uninstall_recipe_path": "uninstall.sh",
            "compatibility_window": ">=2.0.0 <3.0.0",
        }))
        .unwrap();
        let core = CoreCatalogEntry::from(&entry);
        let detected = DetectedAgent {
            id: "claude-code".to_string(),
            status: "healthy".to_string(),
            path: canonical.to_string(),
            version: "2.1.98".to_string(),
        };

        // Detected at the canonical path, in window, and the file exists.
        std::fs::write(&bin, b"#!/bin/sh\n").unwrap();
        let hit = try_reuse(&core, Some(&detected), Some(canonical), "/home/agent")
            .expect("a present, in-window binary at the canonical path is reusable");
        assert_eq!(hit.binary_path, canonical);
        assert_eq!(hit.version, "2.1.98");
        assert_eq!(hit.detected_source, "pre-existing");

        // Same detection, but the binary is gone — the cache can be stale.
        std::fs::remove_file(&bin).unwrap();
        assert!(
            try_reuse(&core, Some(&detected), Some(canonical), "/home/agent").is_none(),
            "a cache entry whose binary has vanished must not be adopted"
        );

        // Nothing detected at all → nothing to reuse.
        std::fs::write(&bin, b"#!/bin/sh\n").unwrap();
        assert!(
            try_reuse(&core, None, Some(canonical), "/home/agent").is_none(),
            "no detection means no reuse, however present the file is"
        );
    }

    /// REUSE-03 runs only on a plain `install <name>`: no --force, no explicit
    /// --version, no existing sentinel. Three mutants survived on that
    /// condition, and each one reuses a pre-existing binary in a case where the
    /// operator explicitly asked not to — `--force` means reinstall regardless,
    /// `--version` means THIS version rather than whatever is lying around, and
    /// an existing sentinel means there is nothing left to adopt.
    ///
    /// Asserted as a full truth table: eight inputs, one eligible.
    #[test]
    fn reuse_runs_only_on_a_plain_install() {
        for force in [false, true] {
            for version in [false, true] {
                for managed in [false, true] {
                    let want = !force && !version && !managed;
                    assert_eq!(
                        reuse_is_eligible(force, version, managed),
                        want,
                        "force={force} explicit_version={version} already_managed={managed}"
                    );
                }
            }
        }
        assert!(
            reuse_is_eligible(false, false, false),
            "the plain install is the ONLY eligible shape"
        );
    }

    /// REMEDIATE-04 shares the first two skips but NOT the sentinel one: a
    /// managed agent can still have drifted to a non-canonical path, which is
    /// exactly what remediation exists to fix. `replace && with ||` survived,
    /// which would remediate under --force and --version too — turning an
    /// explicit pinned install into an uninstall+reinstall of something else.
    #[test]
    fn remediation_is_skipped_by_force_and_version_but_not_by_a_sentinel() {
        assert!(remediate_is_eligible(false, false));
        assert!(!remediate_is_eligible(true, false), "--force skips it");
        assert!(!remediate_is_eligible(false, true), "--version skips it");
        assert!(!remediate_is_eligible(true, true));

        // The distinction from reuse: a sentinel does not appear here at all,
        // so a managed-but-drifted agent still gets remediated.
        assert!(
            remediate_is_eligible(false, false),
            "an already-managed agent is still a remediation candidate"
        );
        assert!(
            !reuse_is_eligible(false, false, true),
            "…while reuse skips it — the two gates differ on exactly this input"
        );
    }

    fn write_catalog(dir: &std::path::Path) {
        std::fs::write(
            dir.join("catalog.json"),
            r#"{"version":"0.3.6","agents":[
                {"id":"test-dummy","display_name":"Test","description":"d","source_kind":"script",
                 "pinned_version":"0.0.1","install_recipe_path":"install.sh",
                 "uninstall_recipe_path":"uninstall.sh","test_only":true,"tags":["test-only"]}
            ]}"#,
        )
        .unwrap();
    }

    fn args(
        force: bool,
        version: Option<&str>,
        include_test: bool,
        yes: bool,
        dry_run: bool,
        name: &str,
    ) -> InstallArgs {
        InstallArgs {
            name: name.to_string(),
            force,
            version: version.map(str::to_string),
            include_test,
            yes,
            dry_run,
        }
    }

    /// A dispatcher that always succeeds (exit 0), so the create/remediate paths
    /// reach their sentinel write without a real recipe.
    fn ok_dispatch(_u: &str, _p: &str, _e: &[(String, String)], _s: Capture) -> DispatchResult {
        DispatchResult {
            exit_code: 0,
            stdout: String::new(),
            stderr: String::new(),
            streamed: matches!(_s, Capture::Streamed),
        }
    }

    /// A dispatcher that fails (exit 7) — the recipe-failure exit-map row.
    fn fail_dispatch(_u: &str, _p: &str, _e: &[(String, String)], _s: Capture) -> DispatchResult {
        DispatchResult {
            exit_code: 7,
            stdout: String::new(),
            stderr: "recipe boom".to_string(),
            streamed: matches!(_s, Capture::Streamed),
        }
    }

    /// Point the catalog/state/detect-cache reads at fixtures for the lifetime of
    /// `env_scope` — which restores them on drop, so a failing assertion cannot
    /// leak a fixture path into whatever test runs next.
    fn set_env(
        env_scope: &mut crate::test_support::EnvScope,
        cat: &std::path::Path,
        state: &std::path::Path,
    ) {
        env_scope.set("AGENTLINUX_CATALOG_DIR", cat);
        env_scope.set("AGENTLINUX_STATE_DIR", state);
        env_scope.set("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect.json");
    }

    // --- Usage exit rows (64) ---

    #[test]
    fn dry_run_and_yes_is_64() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());
        assert_eq!(
            install_with(
                "test-dummy",
                &args(false, None, true, true, true, "test-dummy"),
                ok_dispatch
            ),
            ExitCode::from(EX_USAGE)
        );
    }

    #[test]
    fn unknown_agent_is_64() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());
        assert_eq!(
            install_with(
                "ghost",
                &args(false, None, false, false, false, "ghost"),
                ok_dispatch
            ),
            ExitCode::from(EX_USAGE)
        );
    }

    #[test]
    fn test_only_without_include_test_is_64() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());
        assert_eq!(
            install_with(
                "test-dummy",
                &args(false, None, false, false, false, "test-dummy"),
                ok_dispatch
            ),
            ExitCode::from(EX_USAGE)
        );
    }

    #[test]
    fn bad_version_semver_is_64() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());
        assert_eq!(
            install_with(
                "test-dummy",
                &args(
                    false,
                    Some("not-a-semver"),
                    true,
                    false,
                    false,
                    "test-dummy"
                ),
                ok_dispatch
            ),
            ExitCode::from(EX_USAGE)
        );
    }

    // --- create path + --version override → source=override ---

    #[test]
    fn create_path_writes_curated_sentinel() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());
        assert_eq!(
            install_with(
                "test-dummy",
                &args(false, None, true, false, false, "test-dummy"),
                ok_dispatch
            ),
            ExitCode::SUCCESS
        );
        let s = sentinel::read_sentinel("test-dummy").unwrap().unwrap();
        assert_eq!(s.version, "0.0.1");
        assert_eq!(s.source, "curated");
        assert_eq!(s.status.as_deref(), Some("installed"));
    }

    #[test]
    fn version_override_records_source_override() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());
        assert_eq!(
            install_with(
                "test-dummy",
                &args(false, Some("9.9.9"), true, false, false, "test-dummy"),
                ok_dispatch
            ),
            ExitCode::SUCCESS
        );
        let s = sentinel::read_sentinel("test-dummy").unwrap().unwrap();
        assert_eq!(s.version, "9.9.9");
        assert_eq!(s.source, "override");
    }

    // --- idempotent no-op ---

    #[test]
    fn idempotent_second_install_is_noop() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());
        // First install writes the sentinel.
        let _ = install_with(
            "test-dummy",
            &args(false, None, true, false, false, "test-dummy"),
            ok_dispatch,
        );
        // Second is a no-op: even a failing dispatcher must NOT run (short-circuit).
        assert_eq!(
            install_with(
                "test-dummy",
                &args(false, None, true, false, false, "test-dummy"),
                fail_dispatch
            ),
            ExitCode::SUCCESS
        );
    }

    // --- recipe failure propagates the exit code ---

    #[test]
    fn recipe_failure_propagates_exit_code() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());
        // A fresh install with a failing recipe → exit 7 (propagated), no sentinel.
        assert_eq!(
            install_with(
                "test-dummy",
                &args(false, None, true, false, false, "test-dummy"),
                fail_dispatch
            ),
            ExitCode::from(7)
        );
        assert!(sentinel::read_sentinel("test-dummy").unwrap().is_none());
    }

    // --- --dry-run: no dispatch, no sentinel, exit 0 ---

    #[test]
    fn dry_run_creates_no_sentinel_and_does_not_dispatch() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());
        // A failing dispatcher must never run under --dry-run.
        assert_eq!(
            install_with(
                "test-dummy",
                &args(false, None, true, false, true, "test-dummy"),
                fail_dispatch
            ),
            ExitCode::SUCCESS
        );
        assert!(sentinel::read_sentinel("test-dummy").unwrap().is_none());
    }

    // --- exact literal shapes (byte strings incl. ▸ + [REUSE-03]/[REMEDIATE-04]) ---
    //
    // Captured from the verb's own sink. The previous version of this test
    // re-`format!`ed the same literals inside its body and compared them to
    // string constants — it passed if `install_into` printed nothing at all, so
    // a dropped line, a reordered argument or a wrong branch were all invisible.

    /// Run the verb capturing both streams; returns (exit, stdout, stderr).
    /// Nothing exists — the default for tests that never reach the
    /// post-uninstall check. Stated as a fixture rather than inherited from the
    /// runner's filesystem.
    fn nothing_exists(_p: &std::path::Path) -> bool {
        false
    }

    /// Not a terminal — the curl-installer shape, and a fixture rather than a
    /// property of however the suite was launched.
    fn no_tty() -> bool {
        false
    }

    fn run_capturing(
        name: &str,
        opts: &InstallArgs,
        dispatch: RecipeDispatcher,
    ) -> (ExitCode, String, String) {
        run_capturing_with(name, opts, dispatch, nothing_exists)
    }

    fn run_capturing_with(
        name: &str,
        opts: &InstallArgs,
        dispatch: RecipeDispatcher,
        path_exists: PathExists,
    ) -> (ExitCode, String, String) {
        let mut out: Vec<u8> = Vec::new();
        let mut err: Vec<u8> = Vec::new();
        let code = install_into(
            name,
            opts,
            dispatch,
            path_exists,
            no_tty,
            &mut Out {
                out: &mut out,
                err: &mut err,
            },
        );
        (
            code,
            String::from_utf8(out).unwrap(),
            String::from_utf8(err).unwrap(),
        )
    }

    #[test]
    fn a_fresh_install_prints_the_progress_and_completion_lines() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());

        let (code, out, _err) = run_capturing(
            "test-dummy",
            &args(false, None, true, false, false, "test-dummy"),
            ok_dispatch,
        );

        assert_eq!(code, ExitCode::SUCCESS);
        assert!(
            out.contains("▸ installing test-dummy 0.0.1…\n"),
            "stdout={out:?}"
        );
        assert!(
            out.contains("test-dummy: installed 0.0.1 (curated)\n"),
            "stdout={out:?}"
        );
    }

    #[test]
    fn a_second_install_prints_the_no_op_line_and_does_not_dispatch() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());
        let a = args(false, None, true, false, false, "test-dummy");
        assert_eq!(
            run_capturing("test-dummy", &a, ok_dispatch).0,
            ExitCode::SUCCESS
        );

        // A failing dispatcher proves the second run never reaches the recipe.
        let (code, out, _err) = run_capturing("test-dummy", &a, fail_dispatch);

        assert_eq!(code, ExitCode::SUCCESS);
        assert!(
            out.contains("test-dummy: already installed at 0.0.1 (curated); no-op\n"),
            "stdout={out:?}"
        );
    }

    #[test]
    fn the_dry_run_marker_is_byte_exact() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());

        let (code, out, _err) = run_capturing(
            "test-dummy",
            &args(false, None, true, false, true, "test-dummy"),
            fail_dispatch,
        );

        assert_eq!(code, ExitCode::SUCCESS);
        assert_eq!(
            out,
            "[DRY-RUN] test-dummy: create — would dispatch install.sh at version 0.0.1\n"
        );
    }

    #[test]
    fn the_remediate_arm_prints_its_marker_and_the_reinstall_line() {
        // REMEDIATE-04: an agent detected at a NON-canonical path is uninstalled
        // and reinstalled. Both markers are grepped by the bats suite and
        // neither had any Rust coverage.
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        let detect = tempdir().unwrap();
        std::fs::write(
            cat.path().join("catalog.json"),
            r#"{"version":"0.3.6","agents":[
                {"id":"claude-code","display_name":"Claude Code","description":"d",
                 "source_kind":"script","pinned_version":"2.1.98",
                 "install_recipe_path":"install.sh","uninstall_recipe_path":"uninstall.sh",
                 "test_only":true,"tags":["agent"]}
            ]}"#,
        )
        .unwrap();
        // Healthy at a NON-canonical path. Whether the post-uninstall "binary is
        // gone" check passes is now a fixture (`nothing_exists`) rather than a
        // property of the runner's filesystem — the canonical path is hardcoded
        // to /home/agent/.local/bin/claude, so reading the real FS made this test
        // pass only on a host without Claude Code installed.
        let cache = detect.path().join("detect.json");
        std::fs::write(
            &cache,
            r#"{"agents":[{"id":"claude-code","status":"healthy",
                 "path":"/usr/local/bin/claude","version":"2.1.90"}]}"#,
        )
        .unwrap();
        env_scope
            .set("AGENTLINUX_CATALOG_DIR", cat.path())
            .set("AGENTLINUX_STATE_DIR", state.path())
            .set("AGENTLINUX_DETECT_CACHE", &cache);

        // Without consent the verb refuses, names the component, and exits 65…
        let (code, _out, err) = run_capturing(
            "claude-code",
            &args(false, None, true, false, false, "claude-code"),
            fail_dispatch,
        );
        assert_eq!(code, ExitCode::from(EX_DATAERR));
        assert!(
            err.contains("[BAIL] component=claude-code reason="),
            "stderr={err:?}"
        );

        // …and with --yes it uninstalls, reinstalls, and says so.
        let (code, out, _err) = run_capturing(
            "claude-code",
            &args(false, None, true, true, false, "claude-code"),
            ok_dispatch,
        );
        assert_eq!(code, ExitCode::SUCCESS, "stdout={out:?}");
        assert!(
            out.contains("[REMEDIATE-04] claude-code component=claude-code reason="),
            "stdout={out:?}"
        );
        assert!(
            out.contains("▸ reinstalling claude-code 2.1.98…\n"),
            "stdout={out:?}"
        );
    }

    #[test]
    fn a_binary_still_present_after_uninstall_aborts_before_reinstalling() {
        // The other side of REMEDIATE-04's post-uninstall verification: the
        // uninstall recipe exited 0 but the binary is still there, so the verb
        // must refuse rather than reinstall over it. This branch was previously
        // reachable only by accident — on a host that HAD the binary, where it
        // turned the sibling test red instead of being asserted here.
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        let detect = tempdir().unwrap();
        std::fs::write(
            cat.path().join("catalog.json"),
            r#"{"version":"0.3.6","agents":[
                {"id":"claude-code","display_name":"Claude Code","description":"d",
                 "source_kind":"script","pinned_version":"2.1.98",
                 "install_recipe_path":"install.sh","uninstall_recipe_path":"uninstall.sh",
                 "test_only":true,"tags":["agent"]}
            ]}"#,
        )
        .unwrap();
        let cache = detect.path().join("detect.json");
        std::fs::write(
            &cache,
            r#"{"agents":[{"id":"claude-code","status":"healthy",
                 "path":"/usr/local/bin/claude","version":"2.1.90"}]}"#,
        )
        .unwrap();
        env_scope
            .set("AGENTLINUX_CATALOG_DIR", cat.path())
            .set("AGENTLINUX_STATE_DIR", state.path())
            .set("AGENTLINUX_DETECT_CACHE", &cache);

        fn everything_exists(_p: &std::path::Path) -> bool {
            true
        }

        let (code, out, err) = run_capturing_with(
            "claude-code",
            &args(false, None, true, true, false, "claude-code"),
            ok_dispatch,
            everything_exists,
        );
        assert_eq!(code, ExitCode::from(1), "stdout={out:?} stderr={err:?}");
        assert!(
            err.contains("[REMEDIATE-04:uninstall-incomplete] claude-code"),
            "stderr={err:?}"
        );
        // …and it must NOT have gone on to reinstall.
        assert!(
            !out.contains("reinstalling"),
            "reinstalled over a binary that is still present: {out:?}"
        );
    }

    #[test]
    fn usage_errors_name_the_agent_on_stderr() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());

        let (code, out, err) = run_capturing(
            "ghost",
            &args(false, None, false, false, false, "ghost"),
            ok_dispatch,
        );

        assert_eq!(code, ExitCode::from(EX_USAGE));
        assert!(err.contains("agentlinux: no such agent in catalog: ghost\n"));
        // The available-agents hint lists the non-test-only ids.
        assert!(err.contains("  available: "), "stderr={err:?}");
        assert!(out.is_empty(), "a usage error prints nothing to stdout");
    }
}
