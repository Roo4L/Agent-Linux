//! cmd — the verb adapters (bin I/O boundary over the pure `agentlinux-core`).
//!
//! Wave 1 (Plan 02): the read-only / state-only verbs `list`, `adopt`, `pin`.
//! Each reads through the Task-1 file adapters (catalog/sentinel/cache), calls
//! the already-ported pure gates (classify/derive_category/presence/reuse/
//! remediate/parse_pin_spec), and emits the byte-compatible TS stdout. None of
//! them dispatch a recipe — all recipe dispatch is Plan 03 (install/remove/
//! upgrade).

pub mod adopt;
pub mod install;
pub mod list;
pub mod pin;
pub mod remove;
pub mod upgrade;
