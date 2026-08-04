//! `agentlinux-core` — the pure, I/O-free logic core of the AgentLinux CLI.
//!
//! This crate MUST NOT use `std::process`, `std::fs`, or `std::env` so that
//! `cargo-mutants --package agentlinux-core` and `proptest` can scope
//! to it in isolation. All decision
//! logic lives here as functions over borrowed/owned data returning values or
//! typed errors; the `agentlinux` bin owns every side effect.

pub mod category;
pub mod classify;
pub mod detect_gates;
pub mod divergence;
pub mod pin_spec;
pub mod reuse;
pub mod schema_gen;
pub mod semver_shim;
pub mod time;
pub mod types;

/// Shared proptest strategy generators (TEST-01), consumed by the `proptests`
/// modules in classify/divergence/semver_shim/reuse. Test-only — compiled out of
/// the shipped crate. dtolnay `semver` ships no proptest/Arbitrary support, so
/// these are hand-written string strategies kept catalog-realistic (RESEARCH
/// §proptest Invariants).
#[cfg(test)]
pub mod proptest_strategies;
