//! cmd — the verb adapters (the bin's I/O boundary over the pure
//! `agentlinux-core`).
//!
//! Seven verbs, in two groups:
//!
//! - **Read/state-only** — `list`, `adopt`, `pin`. Each reads through the file
//!   adapters (catalog/sentinel/cache), calls the pure gates
//!   (classify/derive_category/presence/reuse/remediate/parse_pin_spec), and
//!   prints. No recipe runs.
//! - **Recipe-dispatching** — `install`, `remove`, `upgrade`. Same shape, plus a
//!   `dispatcher::RecipeDispatcher` call that runs the agent's recipe as the
//!   install user.
//!
//! `provision` is the odd one out: it runs as ROOT, before any agent user or
//! Node exists, and orchestrates the steps in `crate::provision`. That is why
//! `main::dispatch` routes it through a different entry guard.
//!
//! Every verb keeps the same shape — resolve inputs, ask the pure core for a
//! decision, then do I/O. A verb never re-derives a decision the core owns.

/// The ADAPTER `statSync` re-validation: a reuse candidate the detect cache still
/// vouches for must still be a regular file at decision time. Stale-cache safety
/// for `install`, `adopt` and `upgrade` alike.
///
/// One named predicate rather than the three open-coded
/// `std::fs::metadata(..).map(|m| m.is_file()).unwrap_or(false)` chains it
/// replaces, because a reader counting the host reads in those verbs was
/// counting three unrelated-looking ones.
///
/// Deliberately NOT behind `install::PathExists`, and this is the distinction
/// that seam encodes: `PathExists` exists because the REMEDIATE-04 canonical
/// path comes from a HARDCODED map, so a fixture cannot move it and the test's
/// verdict became a property of the host. The path here comes from the detect
/// cache, which `AGENTLINUX_DETECT_CACHE` already steers — a fixture points it
/// wherever it likes, so the coupling `PathExists` was built to break does not
/// exist on this call. ADR-019 §1.
pub(crate) fn is_regular_file(path: impl AsRef<std::path::Path>) -> bool {
    std::fs::metadata(path)
        .map(|m| m.is_file())
        .unwrap_or(false)
}

#[cfg(test)]
mod cmd_helper_tests {
    /// `is_regular_file` decides whether a REUSE claim still has a binary behind
    /// it. `replace is_regular_file -> bool with true` survived, which makes
    /// every vanished binary look present — so a drifted reuse never gets
    /// reinstalled.
    #[test]
    fn only_a_real_file_is_a_regular_file() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("claude");
        std::fs::write(&file, b"#!/bin/sh\n").unwrap();

        assert!(super::is_regular_file(&file), "a real file is one");
        assert!(
            !super::is_regular_file(dir.path()),
            "a directory is not a regular file"
        );
        assert!(
            !super::is_regular_file(dir.path().join("gone")),
            "an absent path is not a regular file"
        );
    }
}

pub mod adopt;
pub mod install;
pub mod list;
pub mod pin;
pub mod provision;
pub mod remove;
pub mod upgrade;
