# Test secrets

AgentLinux's behavior-test suite mostly runs without secrets — the installer,
agent user, runtime, and registry CLI are all observable from local Ubuntu
state alone. A small number of tests (today: AL-54 interactive Claude Code)
need a live sandbox API key. This doc is the project owner's 60-second
answer to "where do test secrets live, how does one reach a bats test, and
how does a new one get added without leaking."

## The problem

The naive way to give a bats test a sandbox key is to drop the value into a
fixture file or pass it as a CLI argument. Both leak. A fixture commits to
git the first time someone forgets to run `git status`; a CLI argument
lands in every other process's `ps` output for the lifetime of the docker
invocation. Six months later the leak is invisible to a reviewer scanning
the diff — the secret looks like just another test parameter.

The class of tests that need real secrets is small but growing. Without a
single documented path from `.env.local` through Docker into bats (and a
parallel path from GitHub Actions repo secrets into the QEMU release-gate),
each new ticket reinvents the wiring. One of those reinventions will get
the leak path wrong. The cost of that mistake — revoking and rotating a
sandbox key, scrubbing logs, writing a post-mortem — vastly exceeds the
cost of a documented contract.

## What AgentLinux does

AgentLinux defines a four-layer local pipeline and a parallel CI pipeline,
both routing the same named variable from its source to a bats `@test`.

The local pipeline (developer machine):

1. The developer writes their private values into `.env.local` at the repo
   root. The filename is matched by `.env.*` in `.gitignore`, and SEC-05
   gitleaks (pre-commit + full-history) catches anything that slips past.
2. `.env.local.example` is the committed template — commented placeholder
   rows, one per supported variable. New developers copy it to `.env.local`
   and fill in real values.
3. `tests/docker/run.sh` sources `.env.local` (if present) at startup, then
   iterates a small `SECRET_ALLOWLIST` bash array at the top of the file.
   Only allowlisted variables that are set and non-empty in the host env
   are forwarded to the bats container, via `docker run -e VAR` (no
   `=value` — Docker reads the value from the daemon's view of the calling
   shell's env, which keeps the secret out of every other process's `ps`
   output).
4. Inside the container, `tests/bats/helpers/secrets.bash` exposes
   `require_secret <VAR>`. The helper checks the named variable via
   `${!var_name-}` indirect expansion: if it's unset or empty, the test
   yellow-skips with a pointer to this doc; if it's set, the test runs
   through normally.

The CI pipeline (GitHub Actions):

- Per-PR Docker CI (`test.yml`) does NOT receive the sandbox key. Every
  per-PR run sees the secret as unset, every `require_secret` skips yellow,
  the suite stays green. PR authors can't exfiltrate the secret via a
  malicious test because the per-PR jobs never see it.
- Release-gate (`nightly-qemu.yml`) reads `secrets.ANTHROPIC_API_KEY` from
  the repo Actions secrets and exposes it on the boot-step `env:` block
  (step-level, not job-level — narrower blast radius). The release-gate
  is slow and network-bound by design; it is the right place for the live
  key. The boot.sh-to-VM ssh forwarding (the last hop into the QEMU
  guest's bats process) is AL-54's responsibility; AL-53 ships the
  workflow-env half of the wire.

The result: the same `@test` runs green-with-skips on every PR and
green-with-the-key-exercised on every nightly release-gate, with one
canonical place to declare each variable's name and one canonical helper
to consume it.

## Value vs the naive approach

1. **Skip yellow, never red.** Per-PR CI never blocks on a missing sandbox
   key — green stays green. Developers without a `.env.local` see the same
   skip TAP line locally, with a pointer to this doc.
2. **Explicit allowlist beats blanket forward.** A two-row bash array in
   `tests/docker/run.sh` is grep-able in PR review and trivially auditable.
   The blanket dotenv-file approach is opaque and forwards anything that
   happens to be exported in the calling shell.
3. **One place for the secret's name.** `.env.local.example`, the
   allowlist, the workflow `env:` block, and `require_secret` all reference
   the same variable identifier. Adding a new secret is four lockstep
   edits, documented in the worked example below.
4. **Sandbox keys are rotation-friendly.** A live sandbox key with a
   90-day rotation cost is cheap insurance against silent staleness.
   Documenting the procedure means future-you doesn't relearn it under
   pressure.
5. **Leak response is a runbook, not a panic.** The leak-response section
   below is a three-step procedure: revoke, rotate, post-mortem. Knowing
   the runbook exists is most of its value — the rest is the discipline
   to follow it without skipping the post-mortem.

## Related

- `tests/bats/helpers/secrets.bash` — the `require_secret` helper.
- `tests/bats/00-secrets-smoke.bats` — convention example, shows the
  end-to-end flow with a no-real-secret marker (`FOO=bar`). The `00-`
  filename prefix makes it the first test discovered in any bats run.
- `tests/docker/run.sh` — the `SECRET_ALLOWLIST` lives at the top of this
  file; extend in lockstep with `.env.local.example`.
- `.github/workflows/nightly-qemu.yml` — release-gate workflow that
  receives the secret from the repo Actions secrets.
- `.env.local.example` — committed template; commented placeholders only.
- ADR-014 (SEC-05) — full-history gitleaks secret-scanning gate; defence
  in depth alongside the `.gitignore` rule for `.env.*`.

## Worked example

### Add a new test secret (end-to-end checklist)

Four lockstep edits, plus the GitHub Actions secret-store step:

1. **`.env.local.example`** — add a commented row with a one-line comment
   pointing at the ticket the secret unblocks:

   ```
   # NEW_TOKEN — describe purpose; ticket reference here.
   # NEW_TOKEN=
   ```

2. **`tests/docker/run.sh`** — append the variable name to the
   `SECRET_ALLOWLIST` bash array with the requirement ID it supports:

   ```bash
   SECRET_ALLOWLIST=(
     ANTHROPIC_API_KEY  # AL-54 interactive Claude Code tests
     FOO                # AL-53 convention smoke
     NEW_TOKEN          # NEW-XX feature description
   )
   ```

3. **`.github/workflows/nightly-qemu.yml`** — extend the release-gate
   step's `env:` block (step-level, not job-level):

   ```yaml
   env:
     ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
     NEW_TOKEN: ${{ secrets.NEW_TOKEN }}
   ```

4. **GitHub Actions repo secret** — Settings → Secrets and variables →
   Actions → New repository secret. Name matches step 3.

5. **bats test** — reference the variable from the test body via
   `require_secret`:

   ```bash
   @test "NEW-XX: feature description" {
     require_secret NEW_TOKEN
     # ... test body uses $NEW_TOKEN ...
   }
   ```

Do not edit `.github/workflows/test.yml`. Per-PR CI never receives release-
gate secrets; `require_secret` skips yellow there, which is the desired
behavior.

### Sandbox key rotation (90 days)

A 90-day rotation cadence is the default for sandbox keys held in CI. The
procedure is five steps:

1. Generate a new sandbox key in the Anthropic console.
2. Update the GitHub repo secret in Settings → Secrets and variables →
   Actions (overwrite the existing entry; do not create a duplicate).
3. Update the developer's local `.env.local` out of band.
4. Trigger the release-gate workflow (`workflow_dispatch` on
   `nightly-qemu`) and wait for a green run with the new key.
5. Revoke the old key in the Anthropic console once the green run lands.

No calendar reminder is automated under AL-53 (single developer, single
key today — avoid-ceremony rule). If the secret count grows, a future
ticket can land a reminder mechanism.

### Leak response

If a secret value lands somewhere it shouldn't — committed to git,
echoed to a log, screen-shared in a recording — the response is three
steps, in order:

1. **Revoke** the leaked key immediately in the Anthropic console. Do
   this before anything else; the leaked value is hostile until revoked.
2. **Rotate.** Provision a new key, update the GitHub repo secret and
   the developer's local `.env.local`, and cycle the release-gate
   workflow to confirm green.
3. **Post-mortem.** Capture the leak path (git history? installer log
   output? screen-share recording?) in `docs/decisions/` or
   `docs/audits/v0.X.Y/` depending on severity, and cross-link from the
   next release notes. The post-mortem is mandatory even if the leak
   window was short — the leak path is more valuable to fix than the
   key itself.
