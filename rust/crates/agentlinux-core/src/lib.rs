//! `agentlinux-core` — the pure, I/O-free logic core of the AgentLinux CLI.
//!
//! This crate MUST NOT use `std::process`, `std::fs`, or `std::env` so that
//! Phase 54's `cargo-mutants --package agentlinux-core` and `proptest` can scope
//! to it in isolation (RESEARCH §Pattern 1 / §Phase-54-readiness). All decision
//! logic lives here as functions over borrowed/owned data returning values or
//! typed errors; the `agentlinux` bin owns every side effect.

pub mod classify;
pub mod divergence;
pub mod semver_shim;
pub mod types;
