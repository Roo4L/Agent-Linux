// plugin/cli/test/npm_ls.test.ts — queryGlobalNpm / queryNpmViewLatest dispatch
// as the CONFIGURED install user (AL-50 AC4 / AL-59), not a hardcoded `agent`.
// Regression guard: `agentlinux upgrade` probes npm globals via these functions;
// hardcoding "agent" breaks the upgrade flow on a `--user=NAME` host with no
// `agent` user (`sudo: unknown user: agent`). DI (dispatcher param) mirrors
// runner.test.ts — no sudo runs under `pnpm test`.

import assert from "node:assert/strict";
import { afterEach, beforeEach, describe, test } from "node:test";
import { AGENT_PATH } from "../src/runner.js";
import type { CatalogEntry } from "../src/types.js";
import { queryGlobalNpm, queryNpmViewLatest } from "../src/upgrade/npm_ls.js";

type DispatcherArgs = [string, string[], { env: Record<string, string>; timeout?: number }];

function makeCapturingDispatcher(stdout: string) {
  const calls: DispatcherArgs[] = [];
  const impl = async (
    user: string,
    argv: string[],
    opts: { env: Record<string, string>; timeout?: number },
  ) => {
    calls.push([user, argv, opts]);
    return { exitCode: 0, stdout, stderr: "" };
  };
  return { impl, calls };
}

const NPM_ENTRY: CatalogEntry = {
  id: "gsd",
  display_name: "GSD",
  description: ".",
  source_kind: "npm",
  npm_package_name: "@opengsd/gsd-core",
  pinned_version: "1.0.0",
  install_recipe_path: "install.sh",
  uninstall_recipe_path: "uninstall.sh",
};

// Save/restore the env var so resolveInstallUser() is hermetic across tests.
let savedUser: string | undefined;
beforeEach(() => {
  savedUser = process.env.AGENTLINUX_USER;
  // Default-user cases rely on the var being unset (and /etc/agentlinux.env
  // absent on the test host) so resolveInstallUser() falls back to `agent`.
  // biome-ignore lint/performance/noDelete: must fully unset, not set to ""
  delete process.env.AGENTLINUX_USER;
});
afterEach(() => {
  if (savedUser === undefined) {
    // biome-ignore lint/performance/noDelete: restore to truly-unset state
    delete process.env.AGENTLINUX_USER;
  } else {
    process.env.AGENTLINUX_USER = savedUser;
  }
});

describe("queryGlobalNpm install-user dispatch", () => {
  test("defaults to 'agent' with byte-identical /home/agent env", async () => {
    const cap = makeCapturingDispatcher('{"dependencies":{}}');
    await queryGlobalNpm(cap.impl);
    assert.equal(cap.calls.length, 1);
    const [user, argv, opts] = cap.calls[0];
    assert.equal(user, "agent");
    assert.deepEqual(argv, ["npm", "ls", "-g", "--json", "--depth=0"]);
    assert.equal(opts.env.HOME, "/home/agent");
    assert.equal(opts.env.NPM_CONFIG_PREFIX, "/home/agent/.npm-global");
    // Byte-identical to the canonical PATH the installer writes for `agent`.
    assert.equal(opts.env.PATH, AGENT_PATH);
  });

  test("honors AGENTLINUX_USER=claude (dispatch + /home/claude env)", async () => {
    process.env.AGENTLINUX_USER = "claude";
    const cap = makeCapturingDispatcher('{"dependencies":{}}');
    await queryGlobalNpm(cap.impl);
    const [user, , opts] = cap.calls[0];
    assert.equal(user, "claude");
    assert.equal(opts.env.HOME, "/home/claude");
    assert.equal(opts.env.NPM_CONFIG_PREFIX, "/home/claude/.npm-global");
    assert.equal(
      opts.env.PATH,
      "/home/claude/.npm-global/bin:/home/claude/.local/bin:/usr/local/bin:/usr/bin:/bin",
    );
  });
});

describe("queryNpmViewLatest install-user dispatch", () => {
  test("honors AGENTLINUX_USER=claude", async () => {
    process.env.AGENTLINUX_USER = "claude";
    const cap = makeCapturingDispatcher('["1.0.0"]');
    await queryNpmViewLatest(NPM_ENTRY, cap.impl);
    const [user, argv, opts] = cap.calls[0];
    assert.equal(user, "claude");
    assert.deepEqual(argv, ["npm", "view", "@opengsd/gsd-core", "versions", "--json"]);
    assert.equal(opts.env.HOME, "/home/claude");
  });
});
