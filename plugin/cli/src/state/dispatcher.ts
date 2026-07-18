// plugin/cli/src/state/dispatcher.ts — asUser() spawn helper.
// Mirrors plugin/lib/as_user.sh in TypeScript: `sudo -u <user> -H -E -- <argv...>`
// The three load-bearing flags are byte-for-byte identical to the bash keystone:
//   -H  force HOME=target-user-home (required for ~/.npmrc lookups, Phase 3)
//   -E  preserve env (subject to secure_path in sudoers; Pitfall 5)
//   --  end sudo option parsing; user-controlled args can never be reparsed
//
// Uses execFile (array argv) NOT exec (shell string). Prevents shell injection
// via catalog-entry `id` values (04-RESEARCH Anti-Patterns — "Shell injection
// in <name> arg"). PATH is set explicitly by the caller to match
// /etc/agentlinux.env — see Pitfall 5 for why `sudo -E` alone does not preserve
// PATH on Ubuntu (secure_path overrides).
//
// Plan 04-07 Rule 1 auto-fix — invoker==target short-circuit:
//   The CLI's CLI-05 guard (guard/user.ts) REFUSES to run unless invoker is
//   the `agent` user. Every call site in install/remove/upgrade/pin then
//   dispatches the recipe via asUser('agent', ...) — which on a default
//   Ubuntu host requires agent→agent sudo. Ubuntu ships `agent` without
//   any sudoers entry and CONTEXT.md locks "zero sudoers drop-in", so
//   agent→agent sudo fails with "agent is not in the sudoers file."
//
//   The invariant the caller wants is "run this argv as user X" — when
//   process.getuid() already IS X, the sudo hop is unnecessary and
//   actively broken. Short-circuit to direct execFile in that case.
//   The sudo path still fires when called from a different invoker
//   (root during provisioner tests, or future automation that spawns
//   the CLI as a non-agent orchestrator).

import { execFile, spawn } from "node:child_process";
import { userInfo } from "node:os";
import { promisify } from "node:util";

const pexecFile = promisify(execFile);

export interface AsUserResult {
  exitCode: number;
  stdout: string;
  stderr: string;
  // True only when the streaming path teed the child's output to this process's
  // stdout/stderr AS IT RAN. Callers use it to avoid re-printing the captured
  // string a second time (it is already on screen). The buffered path leaves it
  // unset, so buffered callers keep their existing "print stdout after exit"
  // behavior — including the DI test dispatchers, which never stream.
  streamed?: boolean;
}

export interface AsUserOpts {
  env: Record<string, string>;
  cwd?: string;
  timeout?: number;
  stdio?: "inherit" | "pipe";
  // #2 (dogfood): when true, spawn the child and tee its stdout/stderr to this
  // process live (so a minute-long install streams its recipe log instead of
  // looking frozen) while still capturing the bytes into the returned strings.
  // Left unset by buffered callers (the version classifier, `npm ls`/`npm view`
  // probes) that need the captured string but no live echo.
  stream?: boolean;
}

export async function asUser(
  user: string,
  argv: string[],
  opts: AsUserOpts,
): Promise<AsUserResult> {
  // Short-circuit: when invoker === target, run the argv directly rather than
  // sudo-to-self (which requires a sudoers entry CONTEXT.md forbids). The
  // guard above in guard/user.ts has already ensured invoker is the expected
  // agent user; we're just honoring the "run as user X" contract when we're
  // already X.
  const invoker = userInfo().username;
  const [command, ...rest] =
    invoker === user ? argv : ["sudo", "-u", user, "-H", "-E", "--", ...argv];

  // Streaming path: tee live for long recipes (install/remove). Mirrors the
  // buffered path's "return the shape, never throw" contract so callers handle
  // non-zero exits identically whether or not they streamed.
  if (opts.stream) {
    return spawnTee(command, rest, opts);
  }

  try {
    const { stdout, stderr } = await pexecFile(command, rest, {
      env: opts.env,
      cwd: opts.cwd,
      timeout: opts.timeout,
      maxBuffer: 10 * 1024 * 1024, // 10 MiB — tolerant of `npm view versions --json`
    });
    return { exitCode: 0, stdout, stderr };
  } catch (err) {
    // execFile promise rejects with {code, stdout, stderr, killed, signal} on
    // non-zero exit. Return the shape rather than throw so callers decide how
    // to surface the failure (install recipe may legitimately fail → bubble
    // to user; classifier uses `npm ls` which exits 1 on missing dep → not a
    // failure from the classifier's POV).
    const e = err as NodeJS.ErrnoException & {
      code?: number | string;
      stdout?: string;
      stderr?: string;
    };
    const rawCode = e.code;
    const exitCode = typeof rawCode === "number" ? rawCode : Number(rawCode) || 1;
    return {
      exitCode,
      stdout: e.stdout ?? "",
      stderr: e.stderr ?? "",
    };
  }
}

// Streaming exec: spawn with piped stdio, forward each chunk to this process's
// stdout/stderr as it arrives, AND accumulate the bytes so the returned
// {stdout,stderr} match the buffered contract. Resolves (never rejects) with the
// captured shape on any exit — including a spawn failure (ENOENT), which has no
// exit code and maps to 1, mirroring the execFile catch above. `streamed: true`
// tells callers the output is already on screen (don't re-print it).
function spawnTee(command: string, rest: string[], opts: AsUserOpts): Promise<AsUserResult> {
  return new Promise((resolve) => {
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    const child = spawn(command, rest, {
      env: opts.env,
      cwd: opts.cwd,
      stdio: ["ignore", "pipe", "pipe"],
    });
    // On timeout, SIGTERM then escalate to SIGKILL after a short grace: the
    // Promise settles only on 'close', so a recipe that ignores SIGTERM would
    // otherwise hang the CLI forever despite timedOut being set.
    let timer: NodeJS.Timeout | undefined;
    let killTimer: NodeJS.Timeout | undefined;
    const clearTimers = () => {
      if (timer) clearTimeout(timer);
      if (killTimer) clearTimeout(killTimer);
    };
    if (opts.timeout && opts.timeout > 0) {
      timer = setTimeout(() => {
        timedOut = true;
        child.kill("SIGTERM");
        killTimer = setTimeout(() => child.kill("SIGKILL"), 2000);
      }, opts.timeout);
    }

    // stdout/stderr are non-null under stdio ["ignore","pipe","pipe"]; the `?.`
    // just satisfies the Readable|null type without an assertion.
    child.stdout?.on("data", (chunk: Buffer) => {
      stdout += chunk.toString();
      process.stdout.write(chunk);
    });
    child.stderr?.on("data", (chunk: Buffer) => {
      stderr += chunk.toString();
      process.stderr.write(chunk);
    });
    child.on("error", (err) => {
      clearTimers();
      // Spawn failure (no exit code) — return the shape, don't throw. Promise
      // resolve is idempotent, so a following 'close' is a harmless no-op.
      resolve({
        exitCode: 1,
        stdout,
        stderr: `${stderr}${(err as Error).message}`,
        streamed: true,
      });
    });
    child.on("close", (code, signal) => {
      clearTimers();
      // 124 mirrors GNU timeout's convention; a signal-kill with no code → 1.
      const exitCode = timedOut ? 124 : (code ?? (signal ? 1 : 0));
      resolve({ exitCode, stdout, stderr, streamed: true });
    });
  });
}
