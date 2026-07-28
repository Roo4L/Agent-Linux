//! The ONLY module that touches the dtolnay `semver` crate. Isolates the
//! node-semver → dtolnay divergences (compound-range comma, `v`-prefix, lenient
//! parse) behind typed-error functions. Filled in Task 2.
