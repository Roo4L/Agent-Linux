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

import { execFile } from "node:child_process";
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
  const sudoArgs = ["-u", user, "-H", "-E", "--", ...argv];
  try {
    const { stdout, stderr } = await pexecFile("sudo", sudoArgs, {
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
