// plugin/cli/src/guard/user.ts — CLI-05 EUID guard, configured-user aware.
// Pattern ref: 04-RESEARCH §Pattern 8 (lines 866-884).
// Fail-fast when the invoker is not the CONFIGURED install user. The expected
// user is resolved from AGENTLINUX_USER (env / /etc/agentlinux.env), defaulting
// to `agent` (AL-50 AC4) — so a `--user=claude` install gates on `claude`. The
// INVOKER is os.userInfo().username (backed by geteuid()), intentionally NOT a
// caller-controlled env var (04-RESEARCH Anti-Patterns); it is exposed as an
// optional param purely as a test DI seam.

import { userInfo } from "node:os";
import { resolveInstallUser } from "../runner.js";

export function guardAgentUser(
  subcommandName: string,
  invoker: string = userInfo().username,
): void {
  const installUser = resolveInstallUser();
  if (invoker !== installUser) {
    console.error(
      `agentlinux: ${subcommandName} must run as user '${installUser}' (invoker: '${invoker}')`,
    );
    console.error(`  try: sudo -u ${installUser} -H agentlinux ${subcommandName}`);
    process.exit(64); // EX_USAGE — matches plugin/bin/agentlinux-install convention
  }
}
