# Test infrastructure: interactive CLI driving

AgentLinux's behavior-test suite drives most CLIs non-interactively —
binary-with-flag, observe exit code, grep output. A small number of
behaviors only show up under a real interactive session: a connected TTY,
a raw-mode keyboard, a background loop the CLI runs while idle. This doc
is the project owner's 60-second answer to "how does a bats test sit at
a CLI prompt, type into it, and observe what the CLI does over time."

## The problem

The naive way to give a bats test a TTY-driven CLI is to pipe a here-string
into the CLI's stdin: `claude /login <<<"$ANTHROPIC_API_KEY"`. Two problems.
First, Bun-based CLIs that use Ink for their TUI require a genuine
pseudo-terminal pair, not a pipe — Ink's raw-mode keyboard handler fails
with `setRawMode is not a function` on a pipe stdin and the test wedges
or errors out before the prompt is ever drawn. Second, the secret value
lands in the bash process's argv and in every other process's `ps` output
for the lifetime of the pipe — the same leak path that the test-secrets
pipeline goes to lengths to avoid.

A live REPL idle session has the same constraints, plus one more: the
CLI's background loops (auto-updater, telemetry, MCP polling) only fire
when the process believes it's attached to a real terminal. A bash
`sleep 90 && kill $pid` race-conditions against any of those background
loops and can miss what the test is supposed to observe.

## What AgentLinux does

AgentLinux uses `expect` — the canonical Tcl-based pty driver — to own
the terminal pair on behalf of each interactive bats test. Standalone
`.exp` scripts live under `tests/bats/helpers/expect/` and do the actual
spawn / send / expect work; a thin bash wrapper at
`tests/bats/helpers/interactive.bash` exposes three functions to bats
tests via `load 'helpers/interactive'`:

- `claude_login` — drives `claude /login` non-interactively using
  `ANTHROPIC_API_KEY` from the environment. Called once per bats file
  from `setup_file` (auth state persists in `~agent/.claude/` for the
  file's subsequent tests).
- `claude_idle_for <seconds>` — holds an interactive `claude` session
  for N seconds doing nothing, then exits cleanly via Ctrl-D. Used to
  give CLI background loops time to fire on their natural cadence.
- `claude_interactive_run <prompt>` — reserved name for a future
  prompt-round-trip helper; not yet implemented (no consumer today; the
  wrapper errors loudly when called so a future contributor doesn't
  silently get a no-op).

The `.exp` scripts share three defence-in-depth invariants:

1. **`log_user 0` at script entry** — suppresses expect's default echo of
   the spawned process's stdout to the script's own stdout, which is what
   bats captures as `$output`. Without this, the spawned CLI's banner,
   prompt, and the typed API key all land in bats `$output` and from
   there in CI logs.
2. **Secrets read from environment, never argv** — `claude-login.exp`
   reads `$env(ANTHROPIC_API_KEY)`. The bash wrapper passes the value
   via the subprocess env (`sudo -E`), so the key never appears in any
   process's argv or `/proc/<pid>/cmdline`.
3. **Tolerant `-re` prompt matching with bounded timeouts** — the
   upstream CLI's prompt wording is not part of this project's contract
   and shifts between releases. The `.exp` scripts match a small family
   of plausible prompts via regex, with a 30-second per-prompt timeout
   that exits 1 (loud) rather than hanging the bats run silently.

The QEMU release-gate substrate completes the secret pipeline's last
hop: the host runner's `ssh -o SendEnv=ANTHROPIC_API_KEY` and the
guest's `/etc/ssh/sshd_config.d/10-agentlinux-test-acceptenv.conf`
drop-in carry the key from the workflow's step-level env into the
in-guest bats process. The Docker per-PR substrate skips yellow on
the same tests via `require_secret` (the key is never provisioned
for per-PR CI by design).

## Value vs the naive approach

1. **The pty pair is real.** Bun/Ink raw-mode TTY checks pass; the CLI
   draws its prompt and accepts typed input the same way it does for a
   human at a terminal. No here-string fragility; no `setRawMode is not
   a function` errors; no test that passes in Docker but fails in QEMU
   because of subtle differences in pipe vs pty handling.
2. **The secret never crosses argv.** The test-secrets pipeline lands
   the value in the bats process's env; this helper forwards it into
   the spawned CLI's env via the subprocess hop. No `ps` exposure, no
   `/proc/<pid>/cmdline` exposure, no risk of a replay attack against
   a leaked argv.
3. **Background loops fire on their natural cadence.** `claude_idle_for`
   sleeps INSIDE expect, keeping the pty attached. The CLI's auto-updater,
   telemetry, and MCP polling all see a live terminal for the full idle
   window — which is what behavioral tests that exercise those loops need.

## Related

- [Test secrets](test-secrets.md) — where `ANTHROPIC_API_KEY` lives, how
  it reaches the bats container / VM, and how to add a new secret.
- `tests/bats/helpers/interactive.bash` — the bash wrapper API.
- `tests/bats/helpers/expect/claude-login.exp` and
  `helpers/expect/claude-idle.exp` — the standalone expect scripts.
- `tests/bats/51-cc-no-autoupdate.bats` — first consumer; observes the
  Claude Code background auto-updater's behavior across a 90s idle
  window (with and without the `DISABLE_AUTOUPDATER` stamp).
- [Claude Code](claude-code.md) — the agent these helpers drive today.

## Worked example

### Add a new `.exp` script (end-to-end checklist)

1. **Decide the prompt contract.** Run the CLI by hand under `script -q
   /dev/null` (or directly in a terminal) and capture the prompt
   sequence verbatim. Note the variability — most CLIs reword their
   prompts across releases.

2. **Write the standalone `.exp` script under
   `tests/bats/helpers/expect/`** — start with one of the existing
   files as a template. Three mandatory invariants:
   - `log_user 0` at the top.
   - Read secrets from `$env(VAR)`, never from `$argv`.
   - Tolerant `-re` regex for every `expect`, with a
     `timeout { puts stderr "..."; exit 1 }` arm.

3. **Add a thin wrapper to `tests/bats/helpers/interactive.bash`** —
   one bash function that resolves the `.exp` path and calls
   `sudo -E -u agent -H expect "${__interactive_expect_dir}/<name>.exp"`
   (use `-E` to forward env vars across the sudo boundary; the tighter
   `--preserve-env=VAR` is not portable across the full Ubuntu sudo
   matrix).

4. **Document the new helper in this file's `## What AgentLinux does`
   bullet list** so the project owner can find it in 60 seconds.

5. **Reference the new helper from a bats test** — call from a `@test`
   body, wrap in `run`, assert via `assert_exit_zero` + `__fail`. Never
   echo the secret value on failure; print `<set>` / `<unset>` /
   `<wrong-length>` per the test-secrets template-hygiene rule.

### Debugging pty issues

If a `.exp` script hangs or times out:

1. **Run with `expect -d` locally** — verbose tracing of every send /
   expect step. Do NOT commit the `-d` flag; verbose mode logs the
   script's internal state, including spawned-process stdout that
   `log_user 0` was meant to suppress.

2. **Check `log_user` is 0** — a `log_user 1` (the expect default) leaks
   the spawned CLI's full stdout to the bash wrapper's stdout, which
   bats captures as `$output`. CI logs end up with the secret.

3. **Check the prompt regex is tolerant enough** — CLIs reword prompts
   between releases. A `-re {Please enter your API key:}` exact match
   becomes silently invalid the moment upstream changes the wording.
   Prefer character-class fragments (`-re {[Aa]pi[ _-]?[Kk]ey}`) that
   survive minor rewordings.

4. **Check the CLI is actually getting a TTY** — `tty` inside the
   spawned shell (or whatever introspection the CLI exposes) confirms
   the pty pair is attached. A failure here means `expect`'s `spawn`
   itself is the wrong shape for this CLI.

5. **Bounded timeouts everywhere** — every `expect` needs an explicit
   `timeout { puts stderr "..."; exit 1 }` arm. The expect default is
   10 seconds; CLIs with cold-cache auth can take longer (the login
   helper sets a 30s budget for that reason).
