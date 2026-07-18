# Phase 28: rtk — Research

**Researched:** 2026-06-30
**Domain:** Catalog prebuilt-binary installer enabler (ENABLE-01) + first consumer (rtk / WORK-02)
**Confidence:** HIGH (every upstream claim verified live against the release + the running binary)

## Summary

Phase 28 delivers two coupled things: the catalog's first **prebuilt-binary
`source_kind`** (ENABLE-01) and its first consumer, **rtk** (WORK-02). The
machinery fetches a pinned GitHub release tarball, verifies it against the
release's `checksums.txt` *before* extraction, and installs an agent-owned
binary to `~/.local/bin` — no root, no `/usr/local` shim. rtk is pinned to
`rtk-ai/rtk@0.42.4`; phases 29–33 (gh, glab, trivy, gitleaks, sentry-cli)
reuse the same machinery.

The single most important architectural finding: **the existing CLI requires
essentially zero TypeScript changes.** `runner.ts` already dispatches any
recipe as a bash script for any `source_kind` and passes
`AGENTLINUX_SOURCE_KIND`, `AGENTLINUX_PINNED_VERSION`, and
`AGENTLINUX_AGENT_HOME`. `upgrade.ts` already falls back to the sentinel's
declared version for non-npm kinds and gates upstream-latest resolution on
`source_kind === "npm"`. The catalog is staged with `cp -R "$CATALOG_SRC"/.`
(whole-tree recursive copy), so a new `plugin/catalog/lib/` directory rides
along to `/opt/agentlinux/catalog/<ver>/lib/` with **no provisioner edit**.
The only CLI-surface change is a one-line schema enum addition
(`"npm" | "script"` → add `"binary"`), mirrored in `types.ts`.

**Primary recommendation:** Add `"binary"` to the `source_kind` enum; put the
curl→verify→extract→arch-detect logic in a **shared sourced shell helper**
(`plugin/catalog/lib/prebuilt-binary.sh`) that rtk's `install.sh` sources via
`${AGENTLINUX_CATALOG_DIR}/lib/prebuilt-binary.sh`. Keep `init`-hook wiring
**opt-in via a post-install instruction** (user runs `rtk init -g`
themselves), and make `remove` defensively run rtk's own built-in
`rtk init --uninstall -g --auto-patch` before deleting the binary + its
config/cache. This is the smallest change that keeps recipes declarative and
makes phase 29 (gh) a catalog-entry + recipe change with **zero further CLI
source edits** (CAT-03 spirit).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (from 28-CONTEXT.md `<decisions>` — locked by success criteria + upstream recon, verified 2026-06-30)
- **Upstream:** `rtk-ai/rtk` (GitHub releases) — NOT the crates.io "Rust Type Kit" collision. `cargo install rtk` is never used.
- **Pin:** `v0.42.4` (tags are v-prefixed; latest is v0.43.0). `rtk --version` must report `0.42.4`.
- **Linux x86_64 asset:** `rtk-x86_64-unknown-linux-musl.tar.gz` (static musl, most portable). aarch64: `rtk-aarch64-unknown-linux-gnu.tar.gz`.
- **Checksum:** the release ships `checksums.txt` (838 bytes) listing sha256 per asset — verify the downloaded tarball against it BEFORE extracting (ENABLE-01 core contract). Fail the install on mismatch.
- **Install target:** extract the `rtk` binary to `~/.local/bin/rtk` (agent-owned, already on PATH per the agent harness). No `/usr/local` shim.
- **Optional `rtk init` hook:** rtk can wire a hook into `~/.claude`. This is OPT-IN (not run by default). `remove` must revert the binary AND, if the hook was installed, the hook (`rtk … --uninstall` or equivalent) symmetrically — no residue.
- **Symmetric + idempotent remove:** `agentlinux remove rtk` deletes the binary + its config/cache; idempotent on a missing install.

### Claude's Discretion (resolve in plan/research)
- Exact shape of the prebuilt-binary `source_kind` in the catalog schema + `plugin/cli/src/runner.ts` (new fields: release repo, tag, asset pattern per arch, checksum-file name) vs. a recipe-driven download. Prefer the smallest change that keeps recipes declarative and reused by phases 29–33.
- Arch detection (x86_64 vs aarch64) and the musl-vs-gnu choice per arch.
- Where the download/extract happens (recipe env already provides AGENTLINUX_AGENT_HOME, PRESERVE_PATHS).
- How `rtk init`'s opt-in is surfaced (env flag / catalog metadata / post-install instruction).

### Deferred Ideas (OUT OF SCOPE)
- gh/glab/trivy/gitleaks/sentry-cli (phases 29–33) — they consume this enabler; not in scope for Phase 28 beyond making the machinery reusable.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ENABLE-01 | Catalog supports a prebuilt-binary entry kind — fetch pinned release, verify checksum, install binary to `~/.local/bin` (agent-owned, no root, no `/usr/local` shim); `remove` deletes binary + config/cache symmetrically. | §Architecture Patterns (Pattern 1–4), §Don't Hand-Roll, §Code Examples (verify/extract/arch). Schema delta = one enum value; shared `prebuilt-binary.sh` helper; no `runner.ts`/`upgrade.ts` change. |
| WORK-02 | `agentlinux install rtk` installs RTK from `rtk-ai/rtk` (never `cargo install rtk`); optional `rtk init` hook into `~/.claude` is opt-in with symmetric `--uninstall`; `remove` reverts binary + hook. | §rtk init Hook (verified live: `rtk init --uninstall` exists), §Runtime State Inventory, §Validation Architecture (TST-07 + OPS-01). Pin 0.42.4 confirmed via `rtk --version`. |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Fetch pinned release asset | Recipe (`install.sh` via shared `prebuilt-binary.sh`) | — | curl+arch logic is easiest to test in the bats harness; keeps CLI source generic (CAT-03) |
| Checksum verification (BEFORE extract) | Recipe / shared helper | — | Security keystone; pure shell (`sha256sum -c`), no TS needed |
| Arch detection (musl/gnu select) | Recipe / shared helper | — | `uname -m` → asset map; per-tool variety stays in shell |
| Install to `~/.local/bin` | Recipe | runner.ts env (`AGENTLINUX_AGENT_HOME`) | Agent-owned path already on PATH in all six invocation modes |
| `source_kind` validation | catalog `schema.json` + `types.ts` | loader.ts (ajv) | One-line enum extension; existing ajv pipeline validates it |
| Recipe dispatch + env contract | `runner.ts` (UNCHANGED) | — | Already dispatches any recipe as bash for any source_kind |
| Upgrade/divergence reporting | `upgrade.ts` (UNCHANGED) | sentinel | Already reads sentinel.version for non-npm; latest-resolution gated on npm |
| `rtk init` hook into `~/.claude` | rtk's own binary (user-run, opt-in) | uninstall.sh (defensive revert) | rtk owns the Claude/opencode/gemini config formats; we don't reimplement them |
| Catalog staging to `/opt` | provisioner `50-registry-cli.sh` (UNCHANGED) | — | `cp -R "$CATALOG_SRC"/.` already copies any new subdir (e.g. `lib/`) |

## Standard Stack

### Core
| Library / Tool | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| `rtk-ai/rtk` release `v0.42.4` | 0.42.4 (binary reports `rtk 0.42.4`) | The tool being installed | Pinned per ADR-011; verified live `rtk --version` → `rtk 0.42.4` [VERIFIED: ran the downloaded binary] |
| `curl -fsSL` | system (coreutils-adjacent, preinstalled) | Download asset + checksums.txt | Already the repo's download primitive (`packaging/curl-installer/install.sh`) [VERIFIED: codebase] |
| `sha256sum -c` | GNU coreutils (preinstalled on Ubuntu/Alma) | Verify checksum before extract | Exactly the pattern the curl-installer uses (`sha256sum -c`) [VERIFIED: `packaging/curl-installer/install.sh:190`] |
| `tar -xzf` | GNU tar (preinstalled) | Extract the `rtk` binary | rtk tarball is a single top-level `rtk` file (no nesting) [VERIFIED: `tar -tzvf`] |

### Supporting (no new dependencies)
| Mechanism | Purpose | When to Use |
|-----------|---------|-------------|
| `plugin/catalog/lib/prebuilt-binary.sh` (NEW shared shell helper) | Factor curl→verify→extract→arch so phases 29–33 reuse it | Sourced by every `binary` recipe via `${AGENTLINUX_CATALOG_DIR}/lib/` |
| `head -c 2 … \| od -An -tx1` gzip magic check | Detect 404-as-HTML / proxy-rewrite before checksum | Mirror curl-installer Pitfall-2 guard (`file(1)` not preinstalled) [VERIFIED: `install.sh:177-185`] |
| `command -v rtk && rtk --version` | `post_install_verify` smoke | Catalog `post_install_verify` field (existing pattern) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Recipe-driven download + shared shell helper (RECOMMENDED) | Declarative schema fields (release_repo, asset-pattern, checksum-file, bin-path, strip-components) resolved in `runner.ts` (TypeScript) | Declarative pushes per-tool variety (gh nests `bin/gh` under a versioned dir; trivy/gitleaks are flat; sentry-cli is a bare binary with a different checksum scheme; some ship `.zip`) into a leaky pile of schema fields + TS extract logic that is harder to test in the bats harness. Recipe+helper keeps the variety in shell where the harness exercises it, and needs only a one-line enum change. |
| `~/.local/bin` (LOCKED) | `~/.npm-global/bin` | Wrong tier — that prefix is npm-owned; binary tools belong in `~/.local/bin` (RT/BHV PATH contract) |
| `rtk-x86_64-unknown-linux-musl.tar.gz` (static musl) | `.deb` / `.rpm` asset | `.deb`/`.rpm` need root + a package manager — violates the no-root, agent-owned contract |
| Pin via GitHub release (LOCKED) | `cargo install rtk` | crates.io `rtk` is the unrelated "Rust Type Kit" — the canonical collision the requirement forbids |

**No `npm install` / no new npm dependency.** ENABLE-01 is pure shell + a one-line schema change.

**Version verification (live, 2026-06-30):**
- Tag pinned: `v0.42.4`; latest upstream `v0.43.0` (we intentionally pin behind). [VERIFIED: gh release list]
- `rtk --version` → `rtk 0.42.4`. [VERIFIED: executed the extracted binary]
- Asset download counts on `v0.42.4`: musl-x86_64 = 61,384; checksums.txt = 100,422 — release is real and widely consumed. [VERIFIED: gh release view JSON]

## Architecture Patterns

### System Architecture Diagram

```
  agentlinux install rtk
          │
          ▼
  loadCatalog()  ── ajv validate (source_kind: "binary" now in enum) ──┐
          │                                                             │
          ▼                                                  schema.json + types.ts
  dispatchRecipe()  [runner.ts — UNCHANGED]
   env: AGENTLINUX_PINNED_VERSION=0.42.4
        AGENTLINUX_AGENT_HOME=/home/agent
        AGENTLINUX_SOURCE_KIND=binary
        AGENTLINUX_CATALOG_DIR=/opt/agentlinux/catalog/<ver>
          │
          ▼
  agents/rtk/install.sh
          │  source ${AGENTLINUX_CATALOG_DIR}/lib/prebuilt-binary.sh
          ▼
  ┌─────────────────────────────────────────────────────────┐
  │ 1. al_detect_arch:  uname -m → musl|gnu asset            │
  │       x86_64  → rtk-x86_64-unknown-linux-musl.tar.gz     │
  │       aarch64 → rtk-aarch64-unknown-linux-gnu.tar.gz     │
  │       else    → die "unsupported arch"                   │
  │ 2. curl -fsSL release/<asset>      → $tmp/$asset         │
  │    curl -fsSL release/checksums.txt → $tmp/checksums.txt │
  │ 3. gzip magic check (1f 8b)  ── fail → die               │
  │ 4. grep "<asset>$" checksums.txt | sha256sum -c          │
  │       MISMATCH ── die BEFORE extract  ◀── SECURITY GATE  │
  │ 5. tar -xzf $asset → extract top-level `rtk`             │
  │ 6. install -m 0755 rtk → ~/.local/bin/rtk                │
  │ 7. assert: rtk --version contains 0.42.4                 │
  │ 8. print opt-in instruction: "run `rtk init -g` to wire" │
  └─────────────────────────────────────────────────────────┘
          │
          ▼
  sentinel written  (source_kind=binary, version=0.42.4)

  ── USER (opt-in, manual) ───────────────────────────────────
  rtk init -g  → writes ~/.claude/{RTK.md, CLAUDE.md @ref,
                 settings.json hook}, ~/.config/rtk/filters.toml

  ── agentlinux remove rtk ───────────────────────────────────
  agents/rtk/uninstall.sh
   1. if rtk on PATH: rtk init --uninstall -g --auto-patch  (revert hook)
                      rtk init --uninstall -g --opencode    (if applicable)
   2. rm -f ~/.local/bin/rtk
   3. rm -rf ~/.config/rtk ~/.local/share/rtk   (config/cache — ENABLE-01)
   4. rm -f ~/.claude/settings.json.bak          (rtk's own backup residue)
   (idempotent: every step guarded / `|| true`)
```

### Recommended Project Structure
```
plugin/catalog/
├── schema.json                       # +"binary" in source_kind enum
├── catalog.json                      # +rtk entry (source_kind: "binary")
├── lib/
│   └── prebuilt-binary.sh            # NEW shared helper (sourced, not +x)
└── agents/rtk/
    ├── install.sh                    # arch + fetch + verify + extract + opt-in msg
    └── uninstall.sh                  # hook revert + rm binary + config/cache
plugin/cli/src/types.ts              # source_kind union +"binary"
tests/bats/57-catalog-binary.bats    # NEW: ENABLE-01 + WORK-02 lifecycle (TST-07 + OPS-01)
```

### Pattern 1: Verify-before-extract (the security keystone)
**What:** Download asset + `checksums.txt`, assert gzip magic, `sha256sum -c` the
single relevant line, and only then extract. Abort on any mismatch.
**When to use:** Every prebuilt-binary install. Non-negotiable for ENABLE-01.
**Example:** see §Code Examples → "Checksum verification".

### Pattern 2: Arch detection with clean failure
**What:** `uname -m` maps to the per-arch asset; unsupported arches `die` with a
clear message rather than installing a wrong-arch binary.
**When to use:** Every binary recipe. rtk has musl for x86_64 and **gnu only**
for aarch64 (no musl aarch64 asset exists — confirmed in the asset list).

### Pattern 3: Shared sourced helper (reuse keystone, CAT-03)
**What:** Put the boilerplate in `plugin/catalog/lib/prebuilt-binary.sh`; recipes
set a few variables (repo, tag, per-arch asset map, bin name) and call helper
functions. Provisioner stages it automatically (`cp -R "$CATALOG_SRC"/.`).
**When to use:** So phase 29 (gh) is a catalog-entry + recipe change with **zero
CLI source edits**. Per-tool archive-layout differences (flat vs nested vs zip)
are handled by a `bin_path_in_archive` recipe variable passed to the extractor.

### Pattern 4: Opt-in hook via post-install instruction + defensive revert
**What:** Install **never** auto-runs `rtk init` (it would mutate `~/.claude`
without consent). The recipe prints "run `rtk init -g` to wire rtk into Claude
Code." Uninstall defensively runs `rtk init --uninstall` (idempotent — no-op if
the user never opted in) before deleting the binary.
**When to use:** Any tool whose install can mutate other agents' config dirs.

### Anti-Patterns to Avoid
- **`curl … | tar -xz` (pipe straight to extract):** skips verification — the
  exact class of bug `packaging/curl-installer/install.sh` documents. Always
  stage to a tmpdir and verify first.
- **Deleting `~/.local/bin/rtk` before reverting the hook:** `rtk init
  --uninstall` needs the binary to run. Revert the hook **first**, then delete.
- **Auto-running `rtk init` at install time:** mutates `~/.claude/settings.json`
  and `CLAUDE.md` without consent; breaks the opt-in contract (WORK-02).
- **Hardcoding the pin in the recipe:** read `AGENTLINUX_PINNED_VERSION` and
  prepend `v` for the tag — keeps ADR-011 the single source of truth.
- **`cargo install rtk`:** installs the unrelated crates.io "Rust Type Kit."
- **Adding declarative extract fields to `runner.ts`:** unnecessary TS surface;
  the bats harness can't exercise TS extract logic as directly as shell.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Checksum verification | Custom hash compare loop | `sha256sum -c` (filename-column form, chdir into tmpdir) | Coreutils, preinstalled; same pattern the repo already trusts |
| Hook revert in `~/.claude` | Re-parse + edit settings.json/CLAUDE.md ourselves | `rtk init --uninstall -g --auto-patch` (built-in, verified to exist) | rtk owns the format incl. its `settings.json.bak`; reimplementing risks corrupting user config |
| Recipe dispatch / env | New TS dispatch path for binary kind | Existing `runner.ts` (dispatches any source_kind as bash) | Already passes pin/home/source_kind; no change needed |
| Upgrade/divergence for binary kind | New upgrade branch | Existing `upgrade.ts` non-npm path (reads sentinel.version, no upstream latest) | Already handles `source_kind !== "npm"` |
| Catalog staging of `lib/` | New provisioner copy step | Existing `cp -R "$CATALOG_SRC"/.` whole-tree copy | New subdir rides along automatically |
| 404-as-HTML detection | Trust curl exit alone | gzip magic-byte check (`1f8b`) before sha256 | `-f` can be stripped by proxies; gives a precise error (curl-installer Pitfall 2) |

**Key insight:** ENABLE-01 looks like "new installer machinery" but is almost
entirely **assembly of patterns the repo already owns** (verify-before-extract
from the curl-installer; bash-recipe dispatch from runner.ts; sentinel-based
upgrade from upgrade.ts). The genuinely new artifacts are a one-line schema
enum, a ~80-line shared shell helper, and two short recipes.

## Runtime State Inventory

> rtk is an install-and-mutate-other-config tool, so this matters even though the phase is "greenfield catalog entry."

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — rtk stores no database/datastore keyed on a renamed string. | None (verified: no rename in this phase). |
| Live service config | `rtk init -g` mutates **other agents' config** (NOT in git): `~/.claude/settings.json` (adds a `PreToolUse`/Bash hook `rtk hook claude`), `~/.claude/CLAUDE.md` (`@RTK.md` reference), `~/.claude/RTK.md`. Opencode/gemini/codex variants via `--opencode`/`--gemini`/`--codex`. | uninstall.sh runs `rtk init --uninstall -g --auto-patch` (and per-agent flags if those were used) BEFORE deleting the binary. [VERIFIED: ran `rtk init` + `rtk init --uninstall` live] |
| OS-registered state | None — no systemd unit, cron, or Task Scheduler entry. The "hook" is a Claude Code PreToolUse hook (config-file only), not an OS daemon. | None. |
| Secrets/env vars | None — rtk needs no credential (Appendix C: "no credential — offline/local ops"). | None. |
| Build artifacts | rtk's own runtime state: `~/.config/rtk/` (`filters.toml`, `config.toml`) and `~/.local/share/rtk/` (`.hook_warn_last` — written on *any* rtk invocation, even `--version`-adjacent subcommands). These SURVIVE `rtk init --uninstall`. | `remove` must `rm -rf ~/.config/rtk ~/.local/share/rtk` (ENABLE-01 "config/cache" clause). Also `rm -f ~/.claude/settings.json.bak` (rtk leaves a backup). [VERIFIED: filesystem inspection after init + uninstall] |

**Critical verified nuance:** `rtk init --uninstall` reverts the `~/.claude`
artifacts (removes RTK.md, strips the `@RTK.md` line, removes the hook entry —
leaving `settings.json` with an empty `PreToolUse: []` scaffold and a
`settings.json.bak`), but **does NOT** remove `~/.config/rtk` or
`~/.local/share/rtk`. Our `remove` owns those.

## Common Pitfalls

### Pitfall 1: Extracting before verifying
**What goes wrong:** A tampered/corrupted/404-HTML "tarball" gets extracted; a
malicious binary lands in `~/.local/bin`.
**Why it happens:** `curl | tar` convenience; or verifying after extract.
**How to avoid:** Stage to `mktemp -d`, gzip-magic check, `sha256sum -c`, THEN
extract. `trap 'rm -rf "$tmp"' EXIT`.
**Warning signs:** Any `tar` invocation that reads from a URL or from a file not
yet checksum-verified.

### Pitfall 2: checksums.txt filename-column mismatch
**What goes wrong:** `sha256sum -c` reports "FAILED open or read" because the
checksum line's filename doesn't match the local file path.
**Why it happens:** rtk's `checksums.txt` lists bare asset names
(`<hash>␣␣rtk-x86_64-unknown-linux-musl.tar.gz`); `sha256sum -c` resolves that
filename relative to CWD.
**How to avoid:** Download the asset under its exact upstream name into the
tmpdir, `grep` the single matching line into a `<asset>.sha256` file, and run
`(cd "$tmp" && sha256sum -c "<asset>.sha256")`. [VERIFIED: format is the standard
two-space `<sha256>␣␣<filename>` — see §Code Examples.]

### Pitfall 3: Wrong-arch binary on aarch64
**What goes wrong:** Assuming a musl aarch64 asset exists. It does not — only
`rtk-aarch64-unknown-linux-gnu.tar.gz` is published.
**How to avoid:** Map `x86_64→musl`, `aarch64→gnu` explicitly; `die` on anything
else. [VERIFIED: full asset list has no aarch64-musl.]

### Pitfall 4: Deleting the binary before the hook revert
**What goes wrong:** `remove` deletes `~/.local/bin/rtk`, then can't run `rtk
init --uninstall` → orphaned hook left in `~/.claude/settings.json` pointing at
a now-missing `rtk hook claude` command (every Bash tool call in Claude Code
then errors).
**How to avoid:** Order in uninstall.sh: (1) `command -v rtk` guard → revert
hook, (2) delete binary, (3) delete config/cache.

### Pitfall 5: `rtk init --uninstall` leaves residue our `remove` must own
**What goes wrong:** Phase passes the "hook reverted" check but `~/.config/rtk`,
`~/.local/share/rtk`, and `~/.claude/settings.json.bak` survive — failing the
ENABLE-01 "no residue" / "config/cache deleted" contract.
**How to avoid:** Explicitly `rm -rf` those after the built-in revert. Treat the
empty `PreToolUse: []` scaffold in a pre-existing user `settings.json` as
user-owned (do NOT delete settings.json itself).

### Pitfall 6: `file(1)` not present on minimal images
**What goes wrong:** Using `file` to detect archive type fails on minimal
Ubuntu/Alma/Docker bases.
**How to avoid:** `head -c 2 … | od -An -tx1` for the gzip magic (`1f8b`) —
coreutils only. [VERIFIED: curl-installer uses exactly this.]

## Code Examples

> Verified against the live `rtk-ai/rtk@v0.42.4` release on 2026-06-30.

### Checksum verification (verify BEFORE extract)
```bash
# Source: live checksums.txt (https://github.com/rtk-ai/rtk/releases/download/v0.42.4/checksums.txt)
# Format confirmed — standard two-space sha256sum form:
#   34975116da11e09e502501daf758143e0b22ed3a42a10eb67fb693a6270d9e36  rtk-x86_64-unknown-linux-musl.tar.gz
tmp=$(mktemp -d -t agentlinux-rtk.XXXXXX); trap 'rm -rf "$tmp"' EXIT
base="https://github.com/rtk-ai/rtk/releases/download/v${AGENTLINUX_PINNED_VERSION}"

curl -fsSL "${base}/${asset}"        -o "${tmp}/${asset}"        || die "download ${asset} failed"
curl -fsSL "${base}/checksums.txt"   -o "${tmp}/checksums.txt"   || die "download checksums.txt failed"

# gzip magic guard (404-as-HTML / proxy-rewrite) — coreutils only
magic=$(head -c 2 "${tmp}/${asset}" | od -An -tx1 | tr -d ' \n')
[[ "$magic" == "1f8b" ]] || die "${asset} not gzip (magic=${magic:-empty}) — refusing"

# select only the asset's line, then verify it
grep -E "  ${asset}\$" "${tmp}/checksums.txt" > "${tmp}/${asset}.sha256" \
  || die "no checksum line for ${asset}"
( cd "$tmp" && sha256sum -c "${asset}.sha256" ) >/dev/null 2>&1 \
  || die "SHA256 verification failed for ${asset} — aborting BEFORE extract"
```

### Arch detection (musl x86_64 / gnu aarch64)
```bash
# Source: live asset list (gh release view v0.42.4 --repo rtk-ai/rtk)
case "$(uname -m)" in
  x86_64)          asset="rtk-x86_64-unknown-linux-musl.tar.gz" ;;
  aarch64|arm64)   asset="rtk-aarch64-unknown-linux-gnu.tar.gz"  ;;
  *) die "rtk: unsupported architecture '$(uname -m)' (only x86_64, aarch64)" ;;
esac
```

### Extract just the binary to ~/.local/bin
```bash
# Source: tar -tzvf rtk-x86_64-unknown-linux-musl.tar.gz
#   -rwxr-xr-x runner/runner 10047104 ... rtk      ← single top-level file, NO nested dir
dest="${AGENTLINUX_AGENT_HOME}/.local/bin"
mkdir -p "$dest"
tar -xzf "${tmp}/${asset}" -C "$tmp" --no-same-owner rtk \
  || die "tar extraction failed"
install -m 0755 "${tmp}/rtk" "${dest}/rtk"

# version-lock assert
hash -r
got="$(rtk --version 2>&1 | head -1)"   # → "rtk 0.42.4"
printf '%s' "$got" | grep -qF -- "${AGENTLINUX_PINNED_VERSION}" \
  || die "rtk: pinned=${AGENTLINUX_PINNED_VERSION} but --version: ${got}"
echo "rtk: installed at ${dest}/rtk (${got})"
echo "rtk: OPTIONAL — to wire rtk into Claude Code, run:  rtk init -g"
```

### Symmetric uninstall (revert hook first, then binary, then config/cache)
```bash
# Source: verified live — `rtk init --uninstall` exists; config/cache survive it.
if command -v rtk >/dev/null 2>&1; then
  rtk init --uninstall -g --auto-patch >/dev/null 2>&1 || true   # claude (+ opencode/gemini if used)
fi
rm -f  "${AGENTLINUX_AGENT_HOME}/.local/bin/rtk"
rm -rf "${AGENTLINUX_AGENT_HOME}/.config/rtk" \
       "${AGENTLINUX_AGENT_HOME}/.local/share/rtk"
rm -f  "${AGENTLINUX_AGENT_HOME}/.claude/settings.json.bak"   # rtk's own backup residue
hash -r
command -v rtk >/dev/null 2>&1 && { echo "rtk uninstall: still on PATH" >&2; exit 1; } || true
echo "rtk: uninstall complete"
```

### Schema delta (the only CLI-surface change)
```json
// plugin/catalog/schema.json — $defs/agent/properties/source_kind
"source_kind": { "type": "string", "enum": ["npm", "script", "binary"] }
```
```ts
// plugin/cli/src/types.ts
source_kind: "npm" | "script" | "binary";
```
```json
// plugin/catalog/catalog.json — new entry (no preserve_paths: rtk owns no user state we keep)
{
  "id": "rtk",
  "display_name": "RTK (Rust Token Killer)",
  "description": "Token-optimizing CLI proxy that filters/summarizes command output before it reaches the LLM context. Optional `rtk init` wires a Claude Code hook (opt-in).",
  "homepage": "https://github.com/rtk-ai/rtk",
  "license": "MIT",
  "source_kind": "binary",
  "pinned_version": "0.42.4",
  "install_recipe_path": "install.sh",
  "uninstall_recipe_path": "uninstall.sh",
  "post_install_verify": "command -v rtk && rtk --version",
  "tags": ["token", "workflow", "devops"]
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `cargo install rtk` | Pinned GitHub release binary from `rtk-ai/rtk` | n/a (collision avoidance) | crates.io `rtk` = "Rust Type Kit" — wrong tool; release-binary is the only correct path |
| Per-recipe duplicated curl/verify | Shared `plugin/catalog/lib/prebuilt-binary.sh` | This phase (ENABLE-01) | Phases 29–33 add a tool with only a catalog entry + thin recipe |

**Deprecated/outdated:** none relevant — rtk 0.42.x is current (latest 0.43.0;
we pin one minor behind per ADR-011 curation).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A shared `plugin/catalog/lib/prebuilt-binary.sh` is the preferred reuse vehicle (vs. inlining in rtk's recipe then extracting at phase 29) | Standard Stack / Pattern 3 | LOW — if the planner prefers inline-now-extract-later, the schema/recipe/verify logic is unchanged; only file organization differs. Both satisfy CAT-03. |
| A2 | OPS-01 minimal op for rtk = a local offline proxy command (e.g. `rtk ls <dir>` or `rtk gain`), no credential | Validation Architecture | LOW — Appendix C explicitly lists rtk as "no credential (offline/local ops)"; exact subcommand is the planner's choice. |
| A3 | rtk's `--opencode`/`--gemini`/`--codex` init variants need symmetric `--uninstall` flags only if the install opted into them; default opt-in covers claude only | Runtime State Inventory | LOW — post-install instruction defaults to `rtk init -g` (claude); defensive uninstall can run the common flags. Verified `--uninstall` accepts the same mode flags. |

## Open Questions (RESOLVED)

1. **Shared helper vs. inline-then-extract**
   - What we know: `cp -R "$CATALOG_SRC"/.` stages any new `lib/` subdir with no provisioner edit; a sourced (non-`+x`) helper works.
   - What's unclear: whether the planner wants the shared lib built in Phase 28 or deferred to Phase 29's "second consumer" extraction.
   - Recommendation: build `lib/prebuilt-binary.sh` now — CONTEXT explicitly wants phase 29 to be "catalog-entry + recipe change with no further CLI source edits."

2. **Which agents the opt-in instruction advertises**
   - What we know: `rtk init` supports claude (default), opencode, gemini, codex, cursor, etc.
   - What's unclear: whether AgentLinux should advertise wiring into *every installed* coding agent (WIRE-01 spirit) or just Claude Code.
   - Recommendation: Phase 28 advertises `rtk init -g` (claude) only; cross-agent wiring is WIRE-01 territory and out of this phase's scope. Defensive uninstall still reverts whatever the user ran.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `curl` | download asset + checksums | ✓ (repo's existing primitive) | system | — |
| `sha256sum` | verification | ✓ (GNU coreutils, preinstalled) | system | — |
| `tar` + gzip | extract | ✓ (GNU tar, preinstalled) | system | — |
| `uname`, `head`, `od` | arch detect + magic check | ✓ (coreutils) | system | — |
| network to `github.com` release CDN | fetch the asset at install time | ✓ at install time; bats harness has network (npm cluster tests pull from registry) | — | none — a true offline install of a remote binary is impossible; the test must run where the npm-cluster tests already run |
| GitHub release `rtk-ai/rtk@v0.42.4` | the binary itself | ✓ | 0.42.4 | none (pin is the contract) |

**No missing dependencies.** No new package installs required by ENABLE-01.

## Validation Architecture

> `workflow.nyquist_validation: true` in `.planning/config.json` → section included.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bats-core (behavior suite under `tests/bats/`) |
| Config file | none — runner is `tests/docker/run.sh <image>` / `tests/qemu/boot.sh` |
| Quick run command | `./tests/docker/run.sh ubuntu-24.04` (single file: pass a filter, or run the new `57-*.bats` once added) |
| Full suite command | `./tests/docker/run.sh ubuntu-24.04` (Docker matrix) + QEMU before release |
| CLI unit tests | `cd plugin/cli && pnpm test` (node:test) — covers the `types.ts`/schema enum change |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ENABLE-01 | install fetches pinned release, verifies checksum BEFORE extract, lands binary in `~/.local/bin`, no root, no `/usr/local` shim | integration (bats) | `./tests/docker/run.sh ubuntu-24.04` (new `57-catalog-binary.bats`) | ❌ Wave 0 |
| ENABLE-01 | `remove` deletes binary + `~/.config/rtk` + `~/.local/share/rtk`; idempotent second remove | integration (bats) | same file | ❌ Wave 0 |
| ENABLE-01 | tampered/mismatched checksum aborts BEFORE extract (negative test — seed a bad checksums.txt via a local file:// or asset-name swap) | integration (bats) | same file | ❌ Wave 0 |
| WORK-02 | `rtk --version` reports the pin `0.42.4` | integration (bats) | same file | ❌ Wave 0 |
| WORK-02 | opt-in: install does NOT mutate `~/.claude`; after manual `rtk init -g` the hook exists; `remove` reverts it (no orphan hook) | integration (bats) | same file | ❌ Wave 0 |
| WORK-02 (schema) | catalog validates with `source_kind: "binary"`; `types.ts` union compiles | unit (node:test) | `cd plugin/cli && pnpm test` | ⚠️ extend existing schema/loader tests |
| OPS-01 | real offline op (e.g. `rtk ls <tmpdir>` or `rtk gain`) runs as the agent user and produces sensible output | integration (bats) | same file | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `cd plugin/cli && pnpm test` (fast; covers schema/types) + shellcheck/pre-commit on the recipes.
- **Per wave merge:** `./tests/docker/run.sh ubuntu-24.04` running `57-catalog-binary.bats`.
- **Phase gate:** full Docker matrix green + the OPS-01 smoke run-and-passed at least once (no credential needed — recorded in SUMMARY per the TST-07/OPS-01 phase-close gate). QEMU before any release.

### Wave 0 Gaps
- [ ] `tests/bats/57-catalog-binary.bats` — ENABLE-01 + WORK-02 + OPS-01 lifecycle; model on `tests/bats/53-catalog-npm-cluster.bats` (jq-derived pin from the provisioned catalog, six-invocation-mode PATH discipline, `__fail` four-line diagnostics, `assert_no_eacces_in_log`).
- [ ] Negative checksum test fixture — simplest deterministic approach: install once (real), then a second recipe path that points at a deliberately-wrong asset name / corrupted local file and asserts non-zero exit + "verification failed" + binary NOT replaced. Keep network use to the one real download; do the tamper check on a local copy to stay green in Docker.
- [ ] Extend `plugin/cli/test/` schema/loader unit test to assert `source_kind: "binary"` validates and a binary entry round-trips through `loadCatalog`.
- [ ] No framework install needed — bats + node:test already present.

## Security Domain

> `security_enforcement` absent in config → treated as enabled.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | rtk needs no credential (offline tool) |
| V3 Session Management | no | — |
| V4 Access Control | yes | Install is agent-owned (`~/.local/bin`, `~/.config/rtk`); no root, no `/usr/local` shim — enforces the project's privilege contract |
| V5 Input Validation | yes | Asset name is from a fixed enum (`case "$(uname -m)"`); checksums.txt line selected by exact `grep -E "  <asset>$"`; reject unknown arch |
| V6 Cryptography | yes | `sha256sum -c` for integrity — NEVER hand-roll a hash compare; verify BEFORE extract |
| V10/V14 (Supply chain / config) | yes | Pinned tag (ADR-011); gzip magic guard against 404-as-HTML; `trap rm -rf` tmpdir; `--no-same-owner` on extract |

### Known Threat Patterns for {prebuilt-binary install over the network}
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Tampered/MITM'd release asset | Tampering | `sha256sum -c` against the release `checksums.txt` BEFORE extract; abort on mismatch |
| 404/redirect HTML body written to the tarball path | Tampering / DoS | `curl -fsSL` (mandatory `-f`) + gzip magic-byte (`1f8b`) precheck |
| Wrong-arch or wrong-tool binary (rtk vs crates.io "Rust Type Kit") | Spoofing | Fixed asset enum + version-lock assert (`rtk --version` contains pin); never `cargo install` |
| Forged owner/permissions inside tarball | Elevation | `tar --no-same-owner`; `install -m 0755` sets explicit mode |
| Orphaned Claude Code hook after remove | Tampering (broken tool integration) | Revert via built-in `rtk init --uninstall` BEFORE deleting the binary |
| Secret leakage | Information disclosure | N/A — rtk takes no secret; recipe bakes nothing (CAT-02 / secret-free contract upheld) |
| `checksums.txt` itself substituted | Tampering | Residual risk: both asset and checksum come from the same GitHub release over TLS; pin + TLS are the trust anchors. (A future hardening could pin the checksums.txt digest, but that's out of ENABLE-01 scope.) |

## Sources

### Primary (HIGH confidence)
- `gh release view v0.42.4 --repo rtk-ai/rtk --json tagName,assets` — full asset list, tag, download counts (live, 2026-06-30)
- `https://github.com/rtk-ai/rtk/releases/download/v0.42.4/checksums.txt` — verified the two-space `<sha256>␣␣<filename>` format (live fetch)
- `tar -tzvf rtk-x86_64-unknown-linux-musl.tar.gz` — single top-level `rtk` file, no nesting (live)
- Executed the extracted binary: `rtk --version` → `rtk 0.42.4`; `rtk --help`; `rtk init --help` (`--uninstall`, `--dry-run`, `--opencode`, `--gemini`, `--codex` flags); `rtk config --help`
- Live filesystem inspection: `rtk init -g --auto-patch` writes `~/.claude/{RTK.md,CLAUDE.md,settings.json}` + `~/.config/rtk/filters.toml` + `~/.local/share/rtk/.hook_warn_last`; `rtk config --create` writes `~/.config/rtk/config.toml`; `rtk init --uninstall -g` reverts `~/.claude/*` (leaves `settings.json` scaffold + `.bak`) but NOT `~/.config/rtk` / `~/.local/share/rtk`
- Codebase: `plugin/cli/src/runner.ts` (env contract, unchanged), `plugin/cli/src/commands/upgrade.ts:120-160` (non-npm sentinel path), `plugin/cli/src/catalog/{loader.ts,schema.ts}` (ajv pipeline), `plugin/cli/src/types.ts` (CatalogEntry union), `plugin/catalog/schema.json` (source_kind enum), `plugin/catalog/catalog.json` (entry shape), `plugin/catalog/agents/ccusage/{install,uninstall}.sh` + `playwright-cli/install.sh` (recipe baselines), `packaging/curl-installer/install.sh:150-205` (verify-before-extract + gzip magic), `plugin/provisioner/50-registry-cli.sh:97-101` (`cp -R "$CATALOG_SRC"/.` whole-tree staging), `tests/bats/53-catalog-npm-cluster.bats` (lifecycle test shape)
- `.planning/REQUIREMENTS.md` (ENABLE-01, WORK-02, OPS-01, Appendix A pin, Appendix C "no credential"), `.planning/phases/28-rtk/28-CONTEXT.md`
- Project skills: `.claude/skills/catalog-schema/SKILL.md` (CAT-03 "no CLI source edits"), `.claude/skills/behavior-test-contract/SKILL.md` (TST-07, six invocation modes, no-EACCES)

### Secondary (MEDIUM confidence)
- (none — all claims grounded in primary tool output)

### Tertiary (LOW confidence)
- (none)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools are preinstalled coreutils; rtk pin verified by running the binary.
- Architecture: HIGH — verified `runner.ts`/`upgrade.ts`/provisioner need no change by reading the source.
- Pitfalls: HIGH — checksum format, tarball layout, and `rtk init --uninstall` residue all observed live, not assumed.
- Security: HIGH — mirrors the repo's own audited curl-installer discipline.

**Research date:** 2026-06-30
**Valid until:** ~2026-07-30 (stable; the pin is fixed at 0.42.4 regardless of upstream movement — re-verify only if the planner bumps the pin).
