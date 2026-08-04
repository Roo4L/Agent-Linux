# 011: Stability-first version pinning with explicit reconciliation

**Status:** Accepted
**Date:** 2026-04-19

## Context

`agentlinux install <name>` could be a thin wrapper that shells out to `sudo -u
agent -H npm install -g <npm-package>` and accepts whatever version npm serves
at the moment. This was the implicit assumption behind ADR-008 and the earlier
version of the Phase 4 plan.

Two problems surfaced during Phase 4 smart-discuss (2026-04-19):

1. **It provides no value over what users could do themselves.** A user who
   could run `sudo -u agent npm install -g @anthropic-ai/claude-code` by hand
   does not need a CLI to do it for them. The product-level answer to "why use
   AgentLinux?" collapses.

2. **Upstream instability hits users immediately.** Claude Code, GSD, and
   Playwright publish to npm daily-to-weekly; occasional broken versions ship
   (documented incident: GSD upstream bug present in latest, fixed days later).
   A thin-wrapper AgentLinux always pulls the latest, exposing users to every
   upstream regression the moment it publishes.

Alternatives considered (see `docs/research/v0.3.0/stability-model-reconsideration.md`):

- **A'. Custom CLI + version-locked catalog** — ship a `pinned_version` field
  per catalog entry; `agentlinux install` honors the pin; `agentlinux upgrade`
  diffs installed vs pinned vs upstream-latest and offers a 3-way reconcile;
  `agentlinux pin` sets sticky overrides.
- **B'. Private apt/dpkg repo** — each agent is an AgentLinux-published `.deb`
  served from a PPA. Rejected: `apt upgrade` creates a split-brain with Claude
  Code's npm-based self-updater (AGT-02 regression), PPA infra (INF-01) pulled
  forward from v0.4+, `.deb` doesn't port to Fedora/Arch (DST-01..03 would need
  parallel `.rpm`/pacman tracks), 10× submitter friction vs JSON+shell.
- **C'. Nix-flavored symlink profiles + lockfile** — reproducible, atomic swap,
  per-agent pinning. More elegant; adds novel symlink-swap semantics and GC
  machinery. Deferred to v0.4+ as a UX upgrade on top of A'.
- **D'. Thin wrapper (no pinning)** — the rejected baseline; collapses the
  product value.

## Decision

Adopt **Option A'** for v0.3.0: custom CLI + version-locked catalog + explicit
reconciliation verbs.

Concrete implications:

1. **Catalog schema extension.** Every entry in `plugin/catalog/catalog.json`
   declares a `pinned_version` field (required, semver). Each release bundles
   a catalog snapshot at `/opt/agentlinux/catalog/<version>/catalog.json` that
   AgentLinux CI has end-to-end-tested against the full Docker+QEMU matrix
   before tag.

2. **`agentlinux upgrade` verb.** Detects per-agent divergence — `synced`,
   `override-ahead`, or `override-behind` — by comparing `/opt/agentlinux/state/installed.json`
   (the sentinel `agentlinux install` writes at install time) against
   `npm ls -g --json` output and the new release's catalog snapshot. Presents
   a 3-way diff per diverged agent; user picks [keep override] / [accept
   curated] / [accept upstream latest] per agent, or applies `--reset-all-curated`
   / `--respect-overrides` / `--all-latest`.

3. **`agentlinux pin` verb.** Sets sticky-override flags so power-users who run
   ahead of the curated set aren't re-nagged on every release. Cleared
   automatically on `pin <name>=curated`. Precedent: Homebrew's `brew pin`.

4. **AGT-02 remains a permission invariant, not a version invariant.** When a
   user runs `claude update` and escapes our pin, the test still verifies
   no-sudo / no-EACCES on the self-update path. Companion test **AGT-02b**
   verifies "install pinned version produces exactly that version on disk."

5. **Six new requirement IDs** are introduced in `REQUIREMENTS.md`:
   - CAT-04: Every catalog entry declares `pinned_version` validated by JSON
     Schema.
   - CAT-05: Release artifact includes a catalog snapshot sibling to the
     tarball and `.sha256`.
   - CLI-06: `agentlinux upgrade` detects per-agent divergence and offers
     per-agent reconcile.
   - CLI-07: `agentlinux pin <name>=<curated|latest|x.y.z>` sets persistent
     override semantics.
   - TST-08: CI installs the pinned combo and runs the full bats suite before
     the release tag is published (Phase 6 release-gate).
   - AGT-02b: Installing the pinned version produces exactly that version;
     `claude --version` matches `pinned_version`.

6. **Phase 4 plan count grows from 5 to 7.** New plans 04-06 (`upgrade` verb
   + reconcile flow) and 04-07 (catalog snapshot + `pin` verb).

7. **Escape hatch is supported, not fought.** When a user runs `claude update`
   or `npm install -g <pkg>@latest`, AgentLinux records the divergence via
   sentinel inspection; the next `agentlinux upgrade` surfaces the diff rather
   than silently overwriting the user's choice.

## Consequences

- **Release cadence bottleneck moves to CI.** Continuous flow is preserved
  (PR edits one JSON line, CI green, tag ships in ~1 hour) but gated on the
  pinned-combo suite passing. Broken upstream combos cannot ship.
- **`agentlinux install` is no longer a trivial `npm install -g` shim.** It
  writes `installed.json` with `{version, source: curated|override|latest}`
  and this file is the source of truth for divergence detection.
- **AgentLinux marketing message becomes crisp.** "We ship a tested combo,
  you can go ahead if you want, we reconcile on release" is a product claim
  we can defend end-to-end.
- **Submitter contract extends.** Adding a new agent still requires only a
  JSON entry + install.sh + uninstall.sh, but the JSON entry now carries a
  `pinned_version`. Bumping the pin is a one-line PR that CI validates.
- **v0.4+ migration to Nix-style profiles (Option C') stays open.** A' is a
  strict subset of what C' enables; moving to symlink profiles later reuses
  the same catalog schema, lockfile concept, and reconcile UX; only the
  install mechanism changes. ADR-012 (when authored) will capture that
  migration if it proves necessary.
- **CLI complexity grows.** `upgrade` and `pin` are non-trivial: the reconcile
  UX, sticky-override semantics, sentinel read/write, and snapshot manifest
  handling are real surface. Review-loop + bats coverage must be thorough.
- **Release pipeline (Phase 6) gains one step.** Publish `catalog-<version>.json`
  as a sibling of the release tarball + `.sha256`. The installer reads this
  snapshot; the CLI persists a copy under `/opt/agentlinux/catalog/`.
- **Phase 5 AGT-02 test grows one assertion** (AGT-02b verifies
  `claude --version == pinned_version`).

## References

- `docs/research/v0.3.0/cli-vs-apt-advisor.md` — earlier (2026-04-18) advisor
  research comparing custom CLI to apt/dnf/dpkg. Recommended Option A; did not
  yet consider the stability-first criterion.
- `docs/research/v0.3.0/stability-model-reconsideration.md` — this ADR's
  primary justification; reversal-analysis section explains why the earlier
  research's conclusion extends to A' rather than flipping to B'.
- ADR-004 — per-user npm prefix (the substrate this ADR builds on).
- ADR-008 — Commander.js for the CLI (unchanged; A' just adds more verbs).
- Nix flakes (`flake.lock`), Homebrew (`brew pin` + `brew outdated`), mise
  (`mise.lock`), npm (`package-lock.json` + `overrides`) — prior art; all
  cited in the reconsideration research.
