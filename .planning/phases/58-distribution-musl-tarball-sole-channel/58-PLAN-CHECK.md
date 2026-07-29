# Phase 58 — Plan Check

**Checked:** 2026-07-29
**Phase:** 58 — Distribution: musl Tarball as Sole Channel
**Plans:** 3 (58-01 W1, 58-02 W2, 58-03 W3) · 6 tasks
**Verdict:** ✅ **GO** (one WARNING to carry into execution — not blocking)

---

## Verdict Summary

The three plans are goal-complete and traceable. DIST-01/02 + GATE-01/05 each map
to concrete tasks with real deliverables and automated verifies. THE KEY CHECK
(#2) passes: every one of the 5 changed bats hunks is a **re-point to an
equivalent behavioral property**, not a silently dropped assertion — and each is
gated by a negative `dist/index.js` grep in the acceptance criteria so a lazy
delete-instead-of-repoint cannot slip through. THE COUPLED-SWAP CHECK (#3) passes:
an independent grep of the whole `tests/` tree confirms the planner's claim — the
only live agentlinux-CLI `dist/index.js`/`index.js` dependencies are in
`10-installer`, `13-reuse`, `40-registry-cli` (and the `60` fixture stub); the
`node_modules` hits in `14-remediate`/`30-runtime`/`72-phase51` are user-package /
playwright fixtures, correctly untouched. No missed dependency.

---

## Dimension Results

1. **Coverage (DIST-01/02, GATE-01/05):** ✅ All four map to concrete tasks with
   real deliverables. DIST-01 = W1 producer swap + W2 staging/exec swap + W3
   no-Node proof; DIST-02 = W1 15-item deletion inventory; GATE-01 = W2/W3 bats
   green on both distros; GATE-05 = W3 `AGENTLINUX_LEGACY_TS=1` inverse lever +
   retained `plugin/cli/` + retained Bash entrypoint. Requirement IDs present in
   every plan's `requirements:` frontmatter.

2. **★ bats re-points are equivalent, not weakenings:** ✅
   - **10-installer INST-02** (shebang→bin sha256/symlink): source confirms
     `:104,:123,:138` hash `head -1 dist/index.js`; re-point to staged-bin
     `sha256sum` is equal-or-stronger (whole-artifact byte-stability). Symlink-
     target assert (`:97,:133`) legitimately survives.
   - **13-reuse REUSE-03** (`find … index.js` → staged command @647,:670): the
     behavioral asserts (already-installed/no-op @653; reused-managed suffix
     @676) preserved; CLI-resolution mechanism moves off `dist/index.js`.
   - **60-curl-installer fixture** (`agentlinux-install` stub → `agentlinux` bin
     stub): happy-path sentinel preserved; sha256-tamper/main-wrapper/resolve_
     version tests correctly untouched.
   - **40-registry-cli:93** comment-only correction; `--version` assert survives.
   - **00-layout HRN-01** deb `@test` @45-47 is a directory-existence test for a
     directory being deleted → deleting the test is the correct response, not a
     dropped behavioral check.

3. **Coupled-swap completeness:** ✅ Independent grep verified. Planner's "only
   10/13/40/60" claim holds. registry_cli.rs (`:85-101` sanity, `:118-130`
   stage, `:157` symlink target) + install.sh (`:224` exe, `:229` exec) + the 4
   bats move in one wave (W2). No orphaned reference will red the suite.

4. **sha256-before-exec:** ✅ Preserved verbatim. install.sh gate at `:207`
   precedes extraction (`:218`) and exec (`:229`); W2 re-points ONLY the
   downstream exec target, gate untouched; tamper `@test` asserted still green.

5. **Reproducibility:** ✅ Two-builds→same-sha256 is a real automated verify
   (58-01 T1 `<automated>` runs build twice, compares `.sha256`). `[profile.release]`
   confirmed ABSENT today (correctly "you are ADDING one"); toolchain pins musl
   target (A2 satisfied). strip+build-id/remap approach sound (Pitfall 6).

6. **GATE-05 rollback:** ✅ `AGENTLINUX_LEGACY_TS=1` inverse lever real + smoke-
   tested (58-03 T1 default+rollback both run 10-installer), fail-loud on missing
   bundle. `plugin/cli/` (TS) correctly RETAINED as oracle (deletion deferred to
   Phase 59); Bash entrypoint retained.

7. **No-Node-prereq:** ✅ New `61-no-node-prereq.bats` (58-03 T2): static-link
   (`ldd`/`readelf`) + no-node-before-bin log-negative-assert (mirrors INST-05) +
   recipes-still-get-Node scoping. Correctly asserted, not asserted-by-hope.

8. **Purity / deps / Nyquist:** ✅ `agentlinux-core` in NO `files_modified` (grep
   confirmed). No new crates. All 6 tasks carry an `<automated>` verify — no
   3-task gap. Dependency chain sound: W1 produces `plugin/bin/agentlinux` → W2
   stages/execs it → W3 folds flags (`depends_on` 01→02→03 correct).

9. **Deferred honesty:** ✅ CI/QEMU 4-distro release gate + AGT-02 self-update
   correctly deferred to Phase 59 in all three plans + CONTEXT deferred list.

---

## WARNING (carry into execution — not blocking)

**W-1 [task_completeness · 58-02 HUNK C]** — 13-reuse REUSE-03 has TWO intermediate
`[[ -n "$cli" ]]` guards the plan action does not name explicitly:
`:649` (`__fail "… CLI index.js exists under …/dist/"` — a *positive existence*
assertion that becomes false after the swap) and `:671` (`|| skip "no CLI
index.js found"` — a skip guard whose semantics change). The plan's HUNK C names
only the `find` lines (647/670) and the terminal behavioral asserts (653/676).
Mitigation already in place: acceptance criterion @237 negative-greps
`dist/index.js` across 13-reuse, which forces the executor to eliminate the `:649`
message + `:671` skip. So the gate catches it — but the executor should re-point
`:649` to assert the staged `agentlinux` command resolves (equivalent property),
and drop/re-point the `:671` skip so REUSE-03 list-suffix is not silently skipped.
Recommend the verifier confirm neither guard degraded to a no-op skip.

---

## Sign-off

GO. Proceed to `/gsd-execute-phase 58`. The phase's two real failure modes
(dropped bats assertion; missed `dist/index.js` dependency) are both closed:
re-points are equivalent and grep-gated; the coupled set is complete and
independently verified. Carry W-1 as a verifier focus item.
