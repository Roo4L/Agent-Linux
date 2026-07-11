// plugin/cli/src/guard/user.ts — CLI-05 EUID guard.
// Pattern ref: 04-RESEARCH §Pattern 8 (lines 866-884).
// Fail-fast when invoked as root or any non-agent user. Uses os.userInfo().username
// (backed by geteuid() under the hood) — intentionally avoids the environment-
// variable lookup of the invoking account because that value is caller-controlled
// and spoofable (04-RESEARCH Anti-Patterns).

import { userInfo } from "node:os";

const AGENT_USER = "agent";

export function guardAgentUser(subcommandName: string): void {
  const invoker = userInfo().username;
  if (invoker !== AGENT_USER) {
    console.error(
      `agentlinux: ${subcommandName} must run as user '${AGENT_USER}' (invoker: '${invoker}')`,
    );
    console.error(`  try: sudo -u ${AGENT_USER} -H agentlinux ${subcommandName}`);
    process.exit(64); // EX_USAGE — matches plugin/bin/agentlinux-install convention
  }
}
