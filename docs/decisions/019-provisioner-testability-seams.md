# 019: Provisioner testability seams — injected effects, a root prefix, and what stays untested

**Status:** Accepted
**Date:** 2026-07-31

## Context

The Rust cutover (v0.4.0) moved the provisioner from Bash to Rust without
changing its shape: five ordered steps, each doing privileged systems I/O —
`useradd`, `chown`, `visudo`, `apt-get`/`dnf`, symlinks into `/opt` and `/etc`.
In Bash that half was tested only end-to-end, through Docker and QEMU. The Rust
port inherited the same situation: the code that decides *what* to do was
testable, and every line that *does* it was not.

A code-quality review made the consequence concrete. Tests existed for the
privileged half, but they asserted the struct literal they had just written, or
re-typed the function body into the test and compared it to itself, or wrapped
their assertions in `if !Path::new("/etc/agentlinux.env").exists()` so the body
evaporated on exactly the hosts the project targets. `install_or_overwrite` —
the function that installs the `NOPASSWD: ALL` sudoers drop-in — had no test at
all.

This ADR records the seams introduced in response, and, as importantly, the
places deliberately left unseamed, so a reviewer can tell a decision from an
oversight.

## Decision

### 1. Privileged operations are injected as fn pointers

`ProvisionCtx` carries an `Effects` struct of plain `fn` pointers: `chown`,
`chown_symlink`, `ensure_dir`, `visudo_validate`, `pkg_install`, `which`,
`as_user`. Production wires the real implementations; a test substitutes
recording or failing doubles.

Fn pointers rather than a `&dyn Effects` trait object because:

- it matches the convention already in the crate (`cmd/upgrade.rs`'s
  `UpgradeDeps`, `npm.rs`'s `NpmDispatcher`, `detect.rs`'s `LoginRun`), and one
  convention beats two;
- `Effects` stays `Copy`, so overriding one operation is
  `ctx.fx.visudo_validate = visudo_rejects;` with `..Effects::default()`, not a
  builder;
- there is no dynamic dispatch and no lifetime on `ProvisionCtx`.

**Accepted cost:** fn pointers cannot capture, so a recording double needs
somewhere to record. Four step modules therefore carry a `thread_local!` spy
harness with the same `record`/`calls`/`reset_calls` shape. A trait object would
collapse those into one `RecordingEffects`. This is the main argument against the
choice, and it is real — the test scaffolding is larger than it needs to be. It
is accepted because the alternative changes every step signature to gain tidier
test doubles, and because the duplication is confined to `#[cfg(test)]`.

### 2. A step's write set is redirected by two fields, not one

`ProvisionCtx.root` prefixes every SYSTEM path (`ctx.sys("/etc/sudoers.d")`),
and `ProvisionCtx.install_home` already prefixed every per-user path. Together
they make a step's whole write set land inside a `TempDir`.

`sys()` deliberately has **no** `root == "/"` fast path. `Path::new("/").join(
"etc/x")` is already `/etc/x`, so the branch bought nothing, and it was a
surface on which a wrong edit — or a surviving `==`/`!=` mutant — would silently
point every rooted test at the live filesystem, as root, inside the Docker and
QEMU harnesses.

**Known gap:** the two fields are a convention, not an invariant. `ProvisionCtx`
has public fields, so `ProvisionCtx { root: tempdir, install_home:
"/home/agent".into(), .. }` compiles and would write into the real home. A
`ProvisionCtx::rooted(root)` constructor deriving `install_home` under `root`
would make the safe combination the only reachable one. Not done yet.

### 3. Nothing in the DECIDE phase may read the host

`decide_core_with` takes a `HostFacts` value and a `Prompter`. It reads no
filesystem, no passwd DB and no stdin; `HostFacts::probe` is the one place that
does, and the orchestrator calls it. An earlier revision of this ADR claimed the
property while `decide_core_with` still called `probe::user_state` and
`probe::npm_prefix_state` inline — which had a second cost beyond the claim
being false: a fixture could only steer the user verdict by naming a user no
host would have, so `UserState::Absent` was the only reachable arm, and
`Conforming`, `WrongShell` and `HomeNotWritable` — two of which raise the `Bail`
that stops the provisioner touching a brownfield host — had no coverage at all.

This is the strictest rule here, because breaking it fails in a way that is
worse than a missing test: the suite passed unprivileged
(the 0440 drop-in is unreadable, so a provisioned host looked clean) and
inverted as root (the same fixture classified `Drifted`, and a "clean host needs
no answers" test consented to a remediation nobody asked for). The Docker and
QEMU harnesses run as root.

**Consequence, enforced:** `cargo test` must produce identical results as an
unprivileged user, as root, and with a terminal attached. A test whose verdict
depends on the runner is a bug regardless of which way it currently falls.

The TTY axis is listed because it was missed once, in the change that introduced
`provision_with`: the orchestrator built its `Prompter` internally from the
ambient `stdin().is_terminal()`, so the bail-ordering test prompted on a real
terminal and `cargo test` HUNG indefinitely for anyone running it in a shell —
while passing on CI's non-TTY runner. That is the worse direction for a
runner-dependent test, and the same class as reading the host's `/etc`. The
consent surface is now a `ProvisionDeps` field, and `cmd/install.rs` takes its
`is_tty` the same way.

### 3b. The orchestrator's phase ORDER is a property, so it needs a seam too

`provision_with(args, &ProvisionDeps)` injects the phases `provision` composes.
The orderings are the contract — `--purge` before distro detection,
`--report-only`/`--dry-run` returning before the step loop, the bail flush before
`log::init` and before any step, the detect re-scan after the steps and before
adoption — and while every dependency was reached statically, all of them could
be permuted with the whole suite still green. That includes §4's
NO-MUTATION-SNAPSHOT contract, whose entire content is "nothing ran before the
flush": it was asserted on `flush_bails` in isolation, never on the sequence.

### 4. Library code returns exit codes; it does not exit

`remediate::flush_bails` returns `Result<(), ExitCode>` rather than calling
`std::process::exit(65)`. The NO-MUTATION-SNAPSHOT contract — print every
`[BAIL]`, exit 65, mutate nothing — is the most safety-critical thing the
provisioner does, and a library function that ends the process makes it
structurally unassertable: a test reaching it kills the test binary.
`std::process::exit` appears nowhere in production code.

### 5. What is deliberately still untested

`provision::agent_user` and `provision::nodejs` reach `useradd`, `apt-get`/`dnf`,
the NodeSource script and `node --version` with no injection point, and no test
drives their `run`. `cmd/provision::run_purge` spawns `pkill`/`userdel`
unconditionally.

**Production wiring adapters.** Pushing an ambient read behind a seam leaves a
one-line adapter that performs it — `cmd/install::real_is_tty`, and the
`ProvisionDeps::default` field initialisers. Those lines are unkillable by
construction: observing them requires reasserting the very coupling the seam
removed (attaching a real pty, a real passwd DB). They carry
`#[cfg_attr(test, mutants::skip)]` with a back-reference here, per ADR-020 §4.

This is a real cost of the design and is stated so it is not rediscovered: every
seam of this kind trades a testable branch for an untestable adapter. The trade
is worth it because the adapter is one line with no logic, while the branch it
freed carries the decision. Prefer the shape that needs NO skip where it exists —
`real_choose_user` has none, because the caller re-validates whatever the wizard
returns, which kills both of its mutants and closes a trust gap at the same time.

`pkg.rs`'s executor half — `pkg_install`, `pkg_remove`, `nodesource_setup` — is
part of the SAME gap and is named here explicitly, because this list is read by
people triaging a red mutation gate and that gate matches changed *lines in
files*, not modules. Those three have no callers outside the modules above, so
seaming them is the same piece of work; without the name, a contributor whose
diff lands in `pkg.rs` has no auditable answer.

This is a **gap, not a decision** — it is recorded here so it is not mistaken
for one. The seam these need is the same `Effects` bag the other steps use; the
work is threading it through, plus routing `nodejs`'s NodeSource repo paths
through `ctx.sys()`. Two consequences follow while it is outstanding:

- the RT-01 `major < 22` hard-fail and the `ReuseWithWarning` skip-the-chown
  branch have no test at any level;
- a test that drives `nodejs::run` with a `Create` token performs a real Node
  install. One existed, asserting `is_err()`; it passed only because an
  unprivileged runner cannot `apt-get`, and as root it ran a live NodeSource
  install against `/`. It has been deleted rather than left to do that.

Until those seams land, the Docker and QEMU suites are the only coverage for
those two steps, and the honest description of the provisioner is "the sudoers,
PATH-wiring and registry-CLI steps are unit-testable; the user and Node steps
are not."

## Consequences

- A step's ordering and its error handling are assertable without root: the
  sudoers tests pin that `visudo` validates the tmpfile *before* the destination
  is written, that a failed post-install verify is a hard error, and that the
  tmpfile is cleaned on both paths.
- `Effects` advertises more capability than the steps uniformly use.
  `pkg_install` has one consumer while the module making four package-manager
  calls bypasses it. A reader of the struct will over-estimate how much of the
  privileged surface is injected; §5 is the correction.
- Test scaffolding is larger than a trait-object design would need (§1).
- Reviewers should treat §2's public-field gap and §5's unseamed steps as known
  and tracked, not as new findings.

## References

- ADR-012 — the agent user's `NOPASSWD: ALL` drop-in this provisioner installs
- ADR-020 — the mutation-testing policy that keeps these tests honest
- ADR-002 — behavior contract framing; the bats suite remains the spec
