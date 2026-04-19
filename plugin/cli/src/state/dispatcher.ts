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

import { execFile } from "node:child_process";
import { userInfo } from "node:os";
import { promisify } from "node:util";

const pexecFile = promisify(execFile);

export interface AsUserResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

export interface AsUserOpts {
  env: Record<string, string>;
  cwd?: string;
  timeout?: number;
  stdio?: "inherit" | "pipe";
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
  const [command, ...rest] = invoker === user ? argv : ["sudo", "-u", user, "-H", "-E", "--", ...argv];
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
