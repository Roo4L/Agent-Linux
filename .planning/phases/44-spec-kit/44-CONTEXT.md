# Phase 44: spec-kit (+ ENABLE-03 Python+uv bootstrap) — Context

**Gathered:** 2026-07-14
**Status:** Ready for planning
**Mode:** Autonomous discuss (research-backed; source auto-GO)

<domain>
## Phase Boundary

Make **GitHub Spec Kit** installable + removable via the catalog, AND deliver the
**ENABLE-03 Python+uv bootstrap** capability so a per-user `uv` can install a
Python-based agent tool with no root, no `/usr/local` shim, and a symmetric remove.

Source decision: **Auto-GO** — GitHub Spec Kit is an official first-party GitHub
project, MIT-licensed, free, actively maintained (v0.12.14 shipped 2026-07-13).
Per the locked source-selection policy a free official first-party tool needs no
maintainer review. No paywall/credential dimension (offline/local dev tool).
</domain>

<decisions>
## Implementation Decisions (research-verified before building)

### D1 — Install mechanic is a **git-tag** `uv tool install`, NOT a PyPI version pin
The roadmap's `specify-cli@0.11.9` is BOTH stale and the wrong shape. Spec Kit's
official install (verified against the upstream README) is:

```
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@<tag>
```

`specify-cli` on PyPI is not the canonical distribution channel; the repo installs
from the git tag. **Verified end-to-end by a real smoke** (uv 0.11.28 → `uv tool
install ... @v0.12.11 --python 3.12` → `specify --version` → `specify 0.12.11` →
`uv tool uninstall specify-cli` clean). CLI binary is `specify`.

### D2 — Pin spec-kit to **v0.12.11** (git tag)
Latest is v0.12.14 but the tool churns fast (4 releases on 2026-07-13). v0.12.11
(2026-07-10) is the tag GitHub's own README cites as the example, has had days to
settle, and installed cleanly in the smoke. `pinned_version` = `0.12.11`.

### D3 — ENABLE-03 reuses ENABLE-01 for the uv binary; **`source_kind: "script"`**
No new schema enum. The CLI runs `script`/`binary`/`mcp` recipes identically
(per-kind logic is npm-only), so a `script` entry whose `install.sh` bootstraps uv
fully delivers "the catalog supports Python+uv entries." The uv **binary** is
fetched via the existing `al_pb_install` (checksum-verify-before-extract) helper —
uv ships static musl tarballs + a combined `sha256.sum`, a clean ENABLE-01 fit.

### D4 — New shared helper `plugin/catalog/lib/uv-bootstrap.sh`
Consistent with the ENABLE-01 (`prebuilt-binary.sh`) / ENABLE-02
(`mcp-register.sh`) precedent, and the **named future consumer** is the Phase 49
ENABLE-07 growth-kit template (a contributor adding a uv tool reuses this, never
re-derives uv bootstrapping). API:
- `al_uv_ensure <uv_pin>` — idempotent. If `uv` already on PATH → **reuse it**
  (never clobber a user's uv). If absent → install pinned uv (musl) to
  `~/.local/bin` via `al_pb_install` and drop a **managed marker** so uninstall
  knows AgentLinux owns it.
- `al_uv_tool_install <pkg> <git_url> <tag> <python>` — `uv tool install --force`
  (idempotent) from the git ref, `--python <ver>` so uv fetches a managed CPython
  (the host has no guaranteed Python 3.11+).
- `al_uv_tool_uninstall <pkg>` — guarded `uv tool uninstall`.
- `al_uv_remove_if_managed_and_unused` — only if WE installed uv (marker present)
  AND `uv tool list` is empty: remove the uv binary + `~/.local/share/uv` +
  `~/.cache/uv` + marker. Never removes a user-brought uv.

### D5 — uv pinned to **0.11.28** (bootstrap), static **musl** for both arches
Latest uv (2026-07-07), portable static build (safe across Ubuntu + AlmaLinux
targets). Tags are NOT v-prefixed (`0.11.28`). `uv --version` → `uv 0.11.28 (...)`,
so `al_pb_assert_version` substring-matches the pin.

### D6 — Project `.specify/` is user-owned; remove NEVER touches it
`specify init` writes a project-local `.specify/`. That is the user's work product,
outside AgentLinux's tool footprint. `uninstall.sh` removes only the uv tool (+ the
managed uv), never any `.specify/`.
</decisions>

<specifics>
## Deliverables
- `plugin/catalog/lib/uv-bootstrap.sh` (ENABLE-03 helper)
- `plugin/catalog/agents/spec-kit/{install,uninstall}.sh`
- `plugin/catalog/catalog.json` — spec-kit entry (script kind, pin 0.12.11, MIT)
- `tests/bats/66-catalog-spec-kit.bats` — ENABLE-03 lifecycle + WORK-03 real-op + entry-shape
- `docs/internals/catalog.md` — spec-kit roster + ENABLE-03 uv section
</specifics>

<deferred>
## Deferred
- No second uv tool ships this milestone (spec-kit is the sole consumer); the
  helper is deliberately minimal. `agentlinux upgrade` version reconciliation stays
  npm-only — spec-kit is git-tag pinned and upgraded by re-install.
</deferred>
