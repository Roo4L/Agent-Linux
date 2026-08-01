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

/// After a REMEDIATE-04 uninstall, the binary must be gone from BOTH the
/// canonical and the detected path.
///
/// `replace || with &&` survived, which only aborts when the binary survives in
/// *both* places — so the ordinary half-failure, where one copy is removed and
/// the other is not, sails through and the reinstall lands on top of a binary
/// the uninstall was supposed to have taken away.
const fn uninstall_left_something_behind(canonical: bool, detected: bool) -> bool {
    canonical || detected
}

/// A path mismatch is a MIGRATION: the binary MOVES, it is not replaced. Every
/// other remediation reason reinstalls in place.
///
/// The distinction reaches the operator in three separate lines — the planned
/// action, the `--yes` hint, and the past-tense confirmation — so getting it
/// backwards tells them the opposite of what happened three times over.
/// `replace == with !=` survived on it.
pub(crate) const fn is_migration(reason: RemediateReason) -> bool {
    matches!(reason, RemediateReason::PathMismatch)
}

/// Echo a recipe's stderr, when it has any.
///
/// One helper rather than three copies of the same `if !…is_empty()`. Each copy
/// carried its own surviving `delete !`, which drops a failing recipe's stderr —
/// the only diagnosis of WHY an install or a REMEDIATE-04 teardown failed — and
/// prints a blank line after every success instead.
pub(crate) fn echo_stderr_if_any(o: &mut Out<'_>, stderr: &str) {
    if !stderr.is_empty() {
        errln!(o, "{stderr}");
    }
}

/// Which version a REMEDIATE-04 run should install.
///
/// A MIGRATION (same version, wrong path) keeps the detected version when it is
/// inside the declared window — moving a binary must not silently upgrade it.
/// Every other remediation reason, and any version outside the window, takes the
/// curated pin. `replace == with !=` survived on the reason test, which swaps
/// the two: a genuine out-of-window remediation would preserve the very version
/// it was supposed to replace.
fn preserve_version_for<'a>(
    reason: RemediateReason,
    detected_version: Option<&'a str>,
    window: Option<&str>,
) -> Option<&'a str> {
    if reason == RemediateReason::PathMismatch && version_in_window(detected_version, window) {
        detected_version
    } else {
        None
    }
}

/// The `[DRY-RUN] would:` line for a decision.
///
/// Extracted because deleting either the `"reuse"` or the `"remediate"` arm
/// survived, and each deletion silently demotes its case to the catch-all
/// "dispatch install.sh" — telling an operator that a run which would have
/// short-circuited, or torn down and reinstalled, is going to do a plain
/// install. A dry run exists to be believed.
fn dry_run_would_action(
    decision: &str,
    reuse_binary: Option<&str>,
    remediate: Option<&agentlinux_core::detect_gates::RemediateHit>,
    pinned_version: &str,
) -> String {
    match decision {
        "reuse" => format!("short-circuit (binary at {})", reuse_binary.unwrap_or("?")),
        "remediate" => match remediate {
            Some(r) => format!(
                "uninstall + reinstall (reason: {}; detected at {}; canonical at {})",
                r.reason.as_str(),
                r.detected_path,
                r.canonical_path
            ),
            None => format!("dispatch install.sh at version {pinned_version}"),
        },
        _ => format!("dispatch install.sh at version {pinned_version}"),
    }
}

/// Whether a detected version sits inside an entry's declared compatibility
/// window — with an ABSENT or EMPTY window meaning "no", never "anything goes".
///
/// `delete !` and `replace && with ||` both survived here. Either one makes an
/// empty `compatibility_window` string satisfy every version, so a migration
/// preserves whatever version happened to be on the host instead of installing
/// the curated pin.
fn version_in_window(detected: Option<&str>, window: Option<&str>) -> bool {
    detected.is_some_and(|d| window.is_some_and(|w| !w.is_empty() && semver_shim::satisfies(d, w)))
}

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
///
/// Not mutation-tested: it asks the real filesystem (ADR-019 §5). Every caller
/// takes [`PathExists`] as an injected dep for exactly that reason — the
/// REMEDIATE-04 canonical path comes from a hardcoded map a fixture cannot
/// move, so an inline `p.exists()` made the verb's verdict a property of the
/// host the suite ran on.
#[cfg_attr(test, mutants::skip)]
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
/// Not mutation-tested: binds the real streams, dispatcher, path check and
/// consent surface (ADR-019 §5). Every decision lives in [`install_into`].
#[cfg_attr(test, mutants::skip)]
pub fn install(name: &str, opts: &InstallArgs) -> ExitCode {
    install_with(name, opts, dispatcher::dispatch_recipe)
}

/// DI-seam variant with the real stdout/stderr wired up.
#[must_use]
pub fn install_with(name: &str, opts: &InstallArgs, dispatch: RecipeDispatcher) -> ExitCode {
    let mut out = std::io::stdout();
    let mut err = crate::provision::log::err_sink();
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
        let would_action = dry_run_would_action(
            decision,
            reuse_hit.as_ref().map(|h| h.binary_path.as_str()),
            remediate_for_dry,
            &entry.pinned_version,
        );
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
        let is_migration = is_migration(rem.reason);
        let preserve_version = preserve_version_for(
            rem.reason,
            rem.detected_version.as_deref(),
            entry.compatibility_window.as_deref(),
        );
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
            echo_stderr_if_any(o, &uninstall_result.stderr);
            return ExitCode::from(1);
        }

        // Post-uninstall verification: the binary must be gone
        // at BOTH the canonical + detected path, else abort (exit 1). ADAPTER I/O.
        let canonical_present = path_exists(std::path::Path::new(&rem.canonical_path));
        let detected_present = path_exists(std::path::Path::new(&rem.detected_path));
        if uninstall_left_something_behind(canonical_present, detected_present) {
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
            echo_stderr_if_any(o, &install_result.stderr);
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

    // Idempotent short-circuit — matching on the version ALONE was wrong. When
    // REMEDIATE-04's uninstall succeeded and the reinstall then failed, the verb
    // records the requested version with `status=broken-after-remediate`, and the
    // tool is now GONE from the host. Comparing only versions made the obvious
    // recovery — re-run `agentlinux install <id>` — print "already installed; no-op"
    // and exit 0 over a host with no binary. `upgrade` does not rescue it either
    // for script/binary-kind entries, which source `installed` from this same
    // sentinel, so the row reads Synced. Only a status we actually vouch for may
    // satisfy a convergence check.
    const CONVERGED_STATUSES: [&str; 2] = ["installed", "reused"];
    if !opts.force {
        if let Some(ex) = existing.as_ref() {
            let status = ex.status.as_deref().unwrap_or("installed");
            let converged = CONVERGED_STATUSES.contains(&status);
            if semver_shim::eq(&ex.version, &decision.version).unwrap_or(false) && converged {
                outln!(
                    o,
                    "{}: already installed at {} ({}); no-op",
                    entry.id,
                    ex.version,
                    ex.source
                );
                return ExitCode::SUCCESS;
            }
            if !converged {
                println!(
                    "{}: sentinel records status={status} at {} — reinstalling rather \
                     than trusting it",
                    entry.id, ex.version
                );
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
        echo_stderr_if_any(o, &result.stderr);
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

    /// A REMEDIATE-04 uninstall must leave NEITHER copy behind. `replace || with
    /// &&` survived, which only aborts when the binary survives in both places —
    /// so the ordinary half-failure, one copy removed and one not, sails through
    /// and the reinstall lands on top of what the uninstall should have removed.
    #[test]
    fn a_half_completed_uninstall_is_not_a_completed_one() {
        assert!(
            !uninstall_left_something_behind(false, false),
            "both gone is the only clean outcome"
        );
        assert!(
            uninstall_left_something_behind(true, false),
            "the canonical copy surviving is a failure on its own"
        );
        assert!(
            uninstall_left_something_behind(false, true),
            "so is the detected copy surviving on its own"
        );
        assert!(uninstall_left_something_behind(true, true));
    }

    /// A path mismatch MOVES a binary; every other reason replaces one in place.
    /// The word reaches the operator three times — planned action, --yes hint,
    /// past-tense confirmation — so `replace == with !=` tells them the opposite
    /// of what happened, three times over.
    #[test]
    fn only_a_path_mismatch_is_a_migration() {
        use agentlinux_core::detect_gates::RemediateReason;
        assert!(is_migration(RemediateReason::PathMismatch));
        assert!(
            !is_migration(RemediateReason::Broken),
            "a BROKEN install is reinstalled in place, not migrated"
        );
    }

    /// A failing recipe's stderr is the only diagnosis of WHY it failed, and it
    /// must not be replaced by a blank line on every success. One `delete !`
    /// survived in each of the three places this used to be written out.
    #[test]
    fn a_failing_recipe_echoes_its_stderr_and_a_quiet_one_stays_quiet() {
        let (mut o, mut e) = (Vec::new(), Vec::new());
        echo_stderr_if_any(
            &mut Out {
                out: &mut o,
                err: &mut e,
            },
            "npm ERR! EACCES /home/agent/.npm-global",
        );
        assert!(
            String::from_utf8(e).unwrap().contains("EACCES"),
            "the cause must reach the operator"
        );

        let (mut o, mut e) = (Vec::new(), Vec::new());
        echo_stderr_if_any(
            &mut Out {
                out: &mut o,
                err: &mut e,
            },
            "",
        );
        assert!(
            String::from_utf8(e).unwrap().is_empty(),
            "an empty stderr must print NOTHING — not a blank line after every success"
        );
    }

    /// A MIGRATION (same version, wrong path) keeps the detected version when it
    /// is inside the declared window: moving a binary must not silently upgrade
    /// it. Every other reason, and any version outside the window, takes the
    /// curated pin. `replace == with !=` survived, which swaps the two — an
    /// out-of-window remediation would preserve the very version it exists to
    /// replace.
    #[test]
    fn only_an_in_window_migration_preserves_the_detected_version() {
        use agentlinux_core::detect_gates::RemediateReason;
        let window = Some(">=2.0.0 <3.0.0");

        assert_eq!(
            preserve_version_for(RemediateReason::PathMismatch, Some("2.1.0"), window),
            Some("2.1.0"),
            "a migration inside the window keeps what is installed"
        );
        assert_eq!(
            preserve_version_for(RemediateReason::PathMismatch, Some("9.9.9"), window),
            None,
            "…but not one outside it"
        );
        assert_eq!(
            preserve_version_for(RemediateReason::Broken, Some("2.1.0"), window),
            None,
            "a BROKEN install takes the curated pin — preserving the version that \
             is broken would defeat the remediation entirely"
        );
        assert_eq!(
            preserve_version_for(RemediateReason::PathMismatch, None, window),
            None,
            "nothing detected, nothing to preserve"
        );
    }

    /// A dry run exists to be believed. Deleting either named arm survived, and
    /// each demotes its case to the catch-all "dispatch install.sh" — telling
    /// the operator a run that would short-circuit, or tear down and reinstall,
    /// is going to do a plain install instead.
    #[test]
    fn each_dry_run_decision_describes_what_it_would_actually_do() {
        use agentlinux_core::detect_gates::{RemediateHit, RemediateReason};

        let hit = RemediateHit {
            reason: RemediateReason::PathMismatch,
            detected_path: "/usr/local/bin/claude".to_string(),
            canonical_path: "/home/agent/.local/bin/claude".to_string(),
            detected_version: Some("2.1.0".to_string()),
        };

        let reuse = dry_run_would_action(
            "reuse",
            Some("/home/agent/.local/bin/claude"),
            None,
            "2.1.98",
        );
        assert!(
            reuse.contains("short-circuit") && reuse.contains("/home/agent/.local/bin/claude"),
            "a reuse says it will NOT install, and names the binary: {reuse:?}"
        );

        let remediate = dry_run_would_action("remediate", None, Some(&hit), "2.1.98");
        assert!(
            remediate.contains("uninstall + reinstall")
                && remediate.contains("/usr/local/bin/claude")
                && remediate.contains("/home/agent/.local/bin/claude"),
            "a remediation names both paths it will move between: {remediate:?}"
        );

        let create = dry_run_would_action("create", None, None, "2.1.98");
        assert!(
            create.contains("dispatch install.sh") && create.contains("2.1.98"),
            "a plain install names the version: {create:?}"
        );

        // The three must not collapse into one another — which is exactly what a
        // deleted arm does.
        assert_ne!(reuse, create);
        assert_ne!(remediate, create);
        assert_ne!(reuse, remediate);
    }

    /// An ABSENT or EMPTY compatibility window means "not in window", never
    /// "anything goes". `delete !` and `replace && with ||` both survived, and
    /// either makes an empty window satisfy every version — so a migration
    /// preserves whatever happened to be on the host instead of installing the
    /// curated pin.
    #[test]
    fn an_empty_compatibility_window_admits_nothing() {
        assert!(version_in_window(Some("2.1.0"), Some(">=2.0.0 <3.0.0")));
        assert!(!version_in_window(Some("1.0.0"), Some(">=2.0.0 <3.0.0")));

        assert!(
            !version_in_window(Some("2.1.0"), Some("")),
            "an EMPTY window admits nothing — it is not a wildcard"
        );
        assert!(
            !version_in_window(Some("2.1.0"), None),
            "an absent window admits nothing either"
        );
        assert!(
            !version_in_window(None, Some(">=2.0.0 <3.0.0")),
            "no detected version cannot be in any window"
        );
    }

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

    /// REGRESSION: a `broken-after-remediate` sentinel must NOT satisfy the
    /// idempotent short-circuit.
    ///
    /// When REMEDIATE-04's uninstall succeeded and the reinstall then failed, the
    /// verb records the requested version with that status — and the tool is GONE
    /// from the host. Matching on version alone made the obvious recovery, re-running
    /// `agentlinux install <id>`, print "already installed; no-op" and exit 0 over a
    /// host with no binary. `upgrade` does not rescue it either for script/binary-kind
    /// entries: they source `installed` from this same sentinel, so the row reads
    /// Synced and `should_reinstall` returns None.
    ///
    /// Pinned by asserting the recipe actually RAN — a failing dispatcher whose exit
    /// code reaches the caller can only happen if the short-circuit was declined.
    #[test]
    fn a_broken_after_remediate_sentinel_does_not_short_circuit_install() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());

        let mut s = Sentinel::new("test-dummy".into(), "0.0.1".into(), "curated".into(), false);
        s.status = Some("broken-after-remediate".to_string());
        sentinel::write_sentinel(&s).unwrap();

        // Same version as the catalog pin, so ONLY the status can decline the
        // short-circuit. exit 7 proves the recipe was dispatched.
        assert_eq!(
            install_with(
                "test-dummy",
                &args(false, None, true, false, false, "test-dummy"),
                fail_dispatch
            ),
            ExitCode::from(7),
            "a sentinel recording a broken install was treated as converged"
        );
    }

    /// The complement: a healthy `installed` sentinel at the same version still
    /// short-circuits. Without this, declining the short-circuit for EVERY status
    /// would pass the test above while reinstalling on every run.
    #[test]
    fn an_installed_sentinel_still_short_circuits() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());

        let mut s = Sentinel::new("test-dummy".into(), "0.0.1".into(), "curated".into(), false);
        s.status = Some("installed".to_string());
        sentinel::write_sentinel(&s).unwrap();

        // A failing dispatcher must never run.
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
