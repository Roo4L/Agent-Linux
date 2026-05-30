# Test infrastructure: interactive CLI driving

AgentLinux's behavior-test suite drives most CLIs non-interactively —
binary-with-flag, observe exit code, grep output. A small number of
behaviors only show up under a real interactive session: a connected TTY,
a raw-mode keyboard, a background loop the CLI runs while idle.

## The problem

The naive way to give a bats test a TTY-driven CLI is `sleep 90 | claude`
or `(claude & PID=$!; sleep 90; kill $PID)`. Two problems. First,
Bun-based CLIs that use Ink for their TUI require a genuine
pseudo-terminal pair, not a pipe — Ink's raw-mode keyboard handler fails
with `setRawMode is not a function` on a pipe stdin and the test wedges
before the prompt is ever drawn. Second, the kill-after-sleep race
condition fights any background loop the CLI runs on its natural
cadence: an auto-updater that fires every N seconds, telemetry that
batches on a timer, MCP polling that holds the event loop open. A
`sleep 90 && kill` can land between two ticks and miss what the test is
supposed to observe.

There's a third subtle trap. The naive way to authenticate the spawned
CLI is to drive its login prompt with a here-string of the API key. The
secret lands in the bash process's argv and in every other process's
`ps` output for the lifetime of the pipe — the exact leak path the
test-secrets pipeline goes to lengths to avoid. The login-prompt UX is
also upstream-controlled and reworded between releases, so any
expect-driven prompt-parsing helper is brittle by construction.

## What AgentLinux does

Interactive bats tests need a real pty plus a wait that keeps the pty
attached while CLI background loops fire. AgentLinux uses `expect` —
the canonical Tcl-based pty driver — to own the terminal pair. A single
standalone `.exp` script lives under `tests/bats/helpers/expect/`; a
thin bash wrapper at `tests/bats/helpers/interactive.bash` exposes one
function to bats tests via `load 'helpers/interactive'`:

- `claude_idle_for <seconds>` — holds an interactive `claude` session
  for N seconds doing nothing, then exits cleanly via Ctrl-D. The wait
  happens INSIDE expect, keeping the pty attached for the full window
  so the CLI's background loops fire on their natural cadence.

Auth needs no helper. `claude` reads `ANTHROPIC_API_KEY` from its
environment when no stored credentials exist, so the test forwards the
variable across the sudo boundary via
`sudo --preserve-env=ANTHROPIC_API_KEY -u agent -H expect ...` and
lets the spawned CLI authenticate itself. No prompt parsing, no
upstream-UX brittleness, no secret in argv.

The `.exp` script enforces two defence-in-depth invariants:

1. **`log_user 0` at script entry** — suppresses expect's default echo
   of the spawned process's stdout to the script's own stdout, which is
   what bats captures as `$output`. Without this, the spawned CLI's
   banner and prompt land in bats `$output` and from there in CI logs.
2. **Wait inside expect with an early-eof arm** — `set timeout
   $idle_seconds; expect { eof { exit 1 } timeout { } }`. If the
   spawned CLI crashes mid-idle, the test fails loud (exit 1) rather
   than masking the crash with a clean Ctrl-D teardown that races
   against an already-closed pty.

The QEMU release-gate substrate completes the secret pipeline's last
hop: the host runner's `ssh -o SendEnv=ANTHROPIC_API_KEY` and the
guest's `/etc/ssh/sshd_config.d/10-agentlinux-test-acceptenv.conf`
drop-in carry the key from the workflow's step-level env into the
in-guest bats process. The Docker per-PR substrate skips yellow on
the same tests via `require_secret` (the key is never provisioned
for per-PR CI by design).

## Value vs the naive approach

1. **The pty pair is real.** Bun/Ink raw-mode TTY checks pass; the CLI
   draws its prompt and runs its background loops the same way it does
   for a human at a terminal. No `setRawMode is not a function` errors;
   no test that passes in Docker but fails in QEMU because of subtle
   differences in pipe vs pty handling.
2. **The wait happens inside expect.** Background loops (auto-updater,
   telemetry, MCP polling) see a live terminal for the full idle window
   and fire on their natural cadence. A bash-side `sleep && kill` would
   race against any of those loops.
3. **No prompt parsing.** Env-var auth sidesteps the upstream login UX
   entirely — no `.exp` regex to break on the next CLI release.

## Related

- [Test secrets](test-secrets.md) — where `ANTHROPIC_API_KEY` lives, how
  it reaches the bats container / VM, and how to add a new secret.
- `tests/bats/helpers/interactive.bash` — the bash wrapper API.
- `tests/bats/helpers/expect/claude-idle.exp` — the standalone expect
  script.
- `tests/bats/51-cc-no-autoupdate.bats` — first consumer; observes the
  Claude Code background auto-updater's behavior across a 90s idle
  window (with and without the `DISABLE_AUTOUPDATER` stamp).
- [Claude Code](claude-code.md) — the agent these helpers drive today.

## Worked example

### Add a new `.exp` script (end-to-end checklist)

1. **Check whether you need expect at all.** Most CLIs accept a `-p` /
   `--prompt` / `--non-interactive` flag that runs against stdin or
   argv without a pty. If the behavior you want to observe is a single
   prompt-response round-trip and the CLI offers a non-interactive
   flag, use it — no expect, no `.exp` script, no pty wrangling. Expect
   is only worth its weight when you need a real TTY AND a long-lived
   session.

2. **Decide the auth path.** If the CLI accepts an env-var credential
   (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.), forward it via
   `sudo --preserve-env=VAR` and let the CLI authenticate itself. Only
   resort to expect-driven `/login` prompt parsing if the CLI has no
   env-var auth path — it is brittle by construction (upstream reworks
   the prompt copy without warning).

3. **Write the standalone `.exp` script under
   `tests/bats/helpers/expect/`** — start with `claude-idle.exp` as a
   template. Two mandatory invariants:
   - `log_user 0` at the top.
   - Every `expect` has explicit `timeout` and `eof` arms that exit
     with a distinct non-zero code and a stderr diagnostic.

4. **Add a thin wrapper to `tests/bats/helpers/interactive.bash`** —
   one bash function that resolves the `.exp` path and calls
   `sudo --preserve-env=VAR -u agent -H expect "${__interactive_expect_dir}/<name>.exp"`.
   The explicit `--preserve-env=VAR` is the only correct form for the
   support matrix (22.04 / 24.04 / 26.04): plain `-E` is silently
   dropped by Ubuntu's default sudoers (env_reset + restrictive
   env_keep that excludes most API-key var names).

5. **Document the new helper in this file's `## What AgentLinux does`
   bullet list** so the project owner can find it in 60 seconds.

6. **Reference the new helper from a bats test** — call from a `@test`
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
   bats captures as `$output`. CI logs end up with whatever the CLI
   printed during the run.

3. **Check the CLI is actually getting a TTY** — `tty` inside the
   spawned shell (or whatever introspection the CLI exposes) confirms
   the pty pair is attached. A failure here means `expect`'s `spawn`
   itself is the wrong shape for this CLI.

4. **Check the env var actually crossed sudo** — `sudo
   --preserve-env=VAR -u agent -H env | grep VAR` confirms the
   variable made it through. If empty, the wrapper used `-E` (silently
   dropped) instead of the explicit `--preserve-env=VAR` form.

5. **Bounded timeouts everywhere** — every `expect` needs an explicit
   `timeout { puts stderr "..."; exit 1 }` arm AND an `eof { puts
   stderr "..."; exit 1 }` arm. The expect default `timeout 10` is too
   short for idle-observation tests (use the idle window itself) and
   the default eof behavior is to silently fall through.
