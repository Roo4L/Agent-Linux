# Phase 28: rtk — Context

**Gathered:** 2026-06-30
**Status:** Ready for planning
**Mode:** Auto-generated (success criteria are the spec; grounded with live upstream recon)

<domain>
## Phase Boundary

Make rtk (RTK / Rust Token Killer) installable + removable via the catalog, AND
deliver the **prebuilt-binary installer enabler (ENABLE-01)** — the first
catalog `source_kind` that fetches a pinned GitHub release, verifies its
checksum, and installs an agent-owned binary to `~/.local/bin` (no root, no
`/usr/local` shim). rtk is the first consumer; phases 29–33 (gh, glab, trivy,
gitleaks, sentry-cli) reuse the same machinery.
</domain>

<decisions>
## Implementation Decisions

### Locked by success criteria + upstream recon (verified 2026-06-30)
- **Upstream:** `rtk-ai/rtk` (GitHub releases) — NOT the crates.io "Rust Type
  Kit" collision. `cargo install rtk` is never used.
- **Pin:** `v0.42.4` (tags are v-prefixed; latest is v0.43.0). `rtk --version`
  must report `0.42.4`.
- **Linux x86_64 asset:** `rtk-x86_64-unknown-linux-musl.tar.gz` (static musl,
  most portable). aarch64: `rtk-aarch64-unknown-linux-gnu.tar.gz`.
- **Checksum:** the release ships `checksums.txt` (838 bytes) listing sha256 per
  asset — verify the downloaded tarball against it BEFORE extracting (ENABLE-01
  core contract). Fail the install on mismatch.
- **Install target:** extract the `rtk` binary to `~/.local/bin/rtk`
  (agent-owned, already on PATH per the agent harness). No `/usr/local` shim.
- **Optional `rtk init` hook:** rtk can wire a hook into `~/.claude`. This is
  OPT-IN (not run by default). `remove` must revert the binary AND, if the hook
  was installed, the hook (`rtk ... --uninstall` or equivalent) symmetrically —
  no residue.
- **Symmetric + idempotent remove:** `agentlinux remove rtk` deletes the binary
  + its config/cache; idempotent on a missing install.

### Claude's discretion (resolve in plan/research)
- Exact shape of the prebuilt-binary `source_kind` in the catalog schema +
  `plugin/cli/src/runner.ts` (new fields: release repo, tag, asset pattern per
  arch, checksum-file name) vs. a recipe-driven download. Prefer the smallest
  change that keeps recipes declarative and reused by phases 29–33.
- Arch detection (x86_64 vs aarch64) and the musl-vs-gnu choice per arch.
- Where the download/extract happens (recipe env already provides
  AGENTLINUX_AGENT_HOME, PRESERVE_PATHS).
- How `rtk init`'s opt-in is surfaced (env flag / catalog metadata / post-install
  instruction).
</decisions>

<code_context>
## Existing Code Insights

- npm recipes (codex/gemini/opencode/qwen/ccusage, gsd, playwright) under
  `plugin/catalog/agents/<id>/{install,uninstall}.sh` are the recipe baseline;
  the prebuilt-binary recipe is a NEW source_kind.
- `plugin/cli/src/runner.ts` sets the recipe env contract (NPM_CONFIG_PREFIX,
  PATH agent-first, AGENTLINUX_PINNED_VERSION, AGENTLINUX_AGENT_HOME,
  AGENTLINUX_PRESERVE_PATHS). ENABLE-01 may extend it (e.g. a release-asset env)
  or keep everything in the recipe.
- `plugin/catalog/schema.json` validates entries; a prebuilt-binary kind needs
  schema support (catalog-schema skill).
- Behavior tests: `tests/bats/` (this phase adds an ENABLE-01/WORK-02 test:
  fetch → checksum → version → optional-hook → remove).
- `~/.local/bin` is agent-owned + on PATH in all six invocation modes (RT/BHV
  contract) — the correct, shim-free install target.
- `checksums.txt` format is the standard `sha256␣␣filename` per line.
</code_context>

<specifics>
## Specific Ideas

- Checksum verification is the security keystone — download checksums.txt, grep
  the asset line, `sha256sum -c` (or compute + compare), abort on mismatch
  BEFORE extract. No curl|tar without verification.
- curl-pipe safety mirrors the packaging/curl-installer discipline already in
  the repo (verify-before-execute).
- Keep the prebuilt-binary machinery generic enough that phase 29 (gh) is a
  catalog-entry + recipe change with no further CLI source edits (CAT-03 spirit).
</specifics>

<deferred>
## Deferred Ideas

- gh/glab/trivy/gitleaks/sentry-cli (phases 29–33) — they consume this enabler;
  not in scope for Phase 28 beyond making the machinery reusable.
</deferred>
