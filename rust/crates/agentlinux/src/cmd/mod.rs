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

pub mod adopt;
pub mod install;
pub mod list;
pub mod pin;
pub mod provision;
pub mod remove;
pub mod upgrade;
