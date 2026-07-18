# Phase 48: hermes-agent — Summary

**Status:** (pending Docker verify) — 2026-07-14
**Requirements:** ASST-02 (reuses ENABLE-04; + OPS-01 real-op gate)
**Jira:** AL-95

## What shipped

- **hermes-agent catalog entry** (`source_kind: script`, pin `2026.6.19`, MIT, `requires_secret:
  true`) + recipe pair — the second AI-assistant daemon, **reusing the Phase 47 ENABLE-04
  helper** (`plugin/catalog/lib/daemon-lifecycle.sh`) verbatim for the Gateway lifecycle.
- **Install** via the OFFICIAL Nous Research installer, hardened: download-then-run (never a
  blind `curl | bash`) over pinned TLS, `--commit <SHA> --non-interactive` — pins the code to
  an **immutable commit** and skips the API-key/gateway user-input stages so NOTHING secret is
  baked. As a non-root install it lands `hermes` in `~/.local/bin` + the checkout in
  `~/.hermes` — no /usr/local shim. Gateway brought up via ENABLE-04 (systemd-user, QEMU-gated).
- **Surgical CAT-04 remove**: `~/.hermes` mixes the code checkout with user data, so remove
  strips only the checkout (`~/.hermes/hermes-agent`) + the launcher and leaves the user's
  `.env`/`config.yaml`/`SOUL.md`/`memories`/`sessions` in place; `--purge` wipes the rest.
- `tests/bats/68-catalog-hermes-agent.bats` (3 @tests): Docker install → version-lock →
  OPS-01 `hermes doctor` real op → surgical CAT-04 remove; a self-gating QEMU systemd Gateway
  lifecycle test; offline entry shape.
- `docs/internals/catalog.md` "Per-user daemons" section extended with the second consumer +
  its download-then-run/commit-pin install posture; roster line updated.

## Source + supply-chain (de-risk before build)

- **Official = `NousResearch/hermes-agent`** (MIT, LICENSE + pyproject verified at the pinned
  commit). The npm `hermes-agent` (wyrtensi) is an unofficial bridge — NOT used.
- The `install.sh` is fetched live over HTTPS (no script checksum) — the realistic bar for an
  official third-party installer. **Mitigations** (maintainer chose "build it, pin-to-commit"):
  download-then-run over pinned TLS; pin the CODE to immutable commit
  `2bd1977d8fad185c9b4be47884f7e87f1add0ce3` (the peeled `v2026.6.19` tag, resolved via
  `git ls-remote`) — a re-pointed tag cannot change what installs; no-root, agent-owned dirs.
- **Container-verified before writing the recipe:** installer runs clean as the agent user
  (RC 0), `hermes` → `~/.local/bin/hermes` (no shim), `hermes --version` →
  `Hermes Agent v0.17.0 (2026.6.19) … local 2bd1977d` (version-lock on `2026.6.19` holds +
  confirms the pinned commit), state dir `~/.hermes`, gateway surface
  `hermes gateway {run,start,stop,status,install,uninstall}` (`run` = foreground, Docker-friendly).

## Review loop

8 reviewers (catalog-auditor, security-engineer, bash-engineer, qa-engineer,
behavior-coverage-auditor, ai-deslop, fact-checker, external-audience-auditor). No
CRITICAL/HIGH on the recipes; catalog / security / bash / fact-checker / external-audience /
behavior-coverage all clean/GREEN. Actionable findings fixed:
- **security (supply-chain hardening)** — version-lock now binds the pinned **commit SHA**
  (`hermes --version` prints `local 2bd1977d`), not just the calendar version, closing the
  gap where a tampered bootstrap installs a different commit reporting the same version.
- **catalog LOW** — the recipe now `export HERMES_HOME="${AGENTLINUX_AGENT_HOME}/.hermes"`
  so install and uninstall share one source of truth (no silent orphan if an upstream
  default changes).
- **qa HIGH** — the CAT-04 preserve proof now seeds a **test-controlled sentinel** under
  `~/.hermes` before remove and asserts its exact content survives (no longer coupled to an
  installer-created `.env` side-effect; `.env` kept as corroboration).
- **qa MED** — the OPS-01 `hermes doctor` op now asserts non-empty output + no EACCES, not
  just exit 0, so a silent stub cannot pass vacuously.
- **qa LOW** — `_scrub_hermes` now `loginctl disable-linger` for QEMU @test 2 determinism.
- **ai-deslop LOW** — trimmed the pasted `--version` sample in the version-lock comment.
Final: Docker 3/3 green on the fixed code.
