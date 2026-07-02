// plugin/cli/test/guard-user.test.ts — CLI-05 EUID guard, configured-user aware.
// guardAgentUser takes an optional `invoker` param (DI seam, defaulting to
// os.userInfo().username) so tests can drive it without module-mocking
// node:os. The guard compares the invoker to the CONFIGURED install user
// (AGENTLINUX_USER env / /etc/agentlinux.env), defaulting to `agent` — AL-50 AC4.

import assert from "node:assert/strict";
import { afterEach, beforeEach, describe, test } from "node:test";
import { guardAgentUser } from "../src/guard/user.js";

// Capture process.exit + console.error around a guard call.
function runGuard(subcommand: string, invoker: string): { exitCodes: number[]; err: string } {
  const origExit = process.exit;
  const origErr = console.error;
  const exitCodes: number[] = [];
  const errLines: string[] = [];
  // biome-ignore lint/suspicious/noExplicitAny: test override of process.exit signature
  (process as any).exit = (code?: number) => {
    exitCodes.push(code ?? 0);
    throw new Error(`__test_exit_${code}__`);
  };
  console.error = (...args: unknown[]) => {
    errLines.push(args.join(" "));
  };
  try {
    guardAgentUser(subcommand, invoker);
  } catch (e) {
    if (!(e instanceof Error) || !/^__test_exit_/.test(e.message)) throw e;
  } finally {
    process.exit = origExit;
    console.error = origErr;
  }
  return { exitCodes, err: errLines.join("\n") };
}

describe("guardAgentUser — default install user (agent)", () => {
  let orig: string | undefined;
  beforeEach(() => {
    orig = process.env.AGENTLINUX_USER;
    process.env.AGENTLINUX_USER = "agent"; // hermetic — highest-precedence source
  });
  afterEach(() => {
    // biome-ignore lint/performance/noDelete: delete is required for process.env
    if (orig === undefined) delete process.env.AGENTLINUX_USER;
    else process.env.AGENTLINUX_USER = orig;
  });

  test("accepts invoker 'agent' (no exit)", () => {
    const { exitCodes } = runGuard("list", "agent");
    assert.deepEqual(exitCodes, []);
  });

  test("rejects a non-agent invoker with exit 64, message names 'agent'", () => {
    const { exitCodes, err } = runGuard("install", "root");
    assert.deepEqual(exitCodes, [64]);
    assert.match(err, /must run as user 'agent'/);
    assert.match(err, /sudo -u agent -H agentlinux install/);
  });
});

describe("guardAgentUser — configured install user (AGENTLINUX_USER=claude)", () => {
  let orig: string | undefined;
  beforeEach(() => {
    orig = process.env.AGENTLINUX_USER;
    process.env.AGENTLINUX_USER = "claude";
  });
  afterEach(() => {
    // biome-ignore lint/performance/noDelete: delete is required for process.env
    if (orig === undefined) delete process.env.AGENTLINUX_USER;
    else process.env.AGENTLINUX_USER = orig;
  });

  test("accepts invoker 'claude' (no exit)", () => {
    const { exitCodes } = runGuard("list", "claude");
    assert.deepEqual(exitCodes, []);
  });

  test("rejects invoker 'agent' with exit 64, message names 'claude'", () => {
    const { exitCodes, err } = runGuard("install", "agent");
    assert.deepEqual(exitCodes, [64]);
    assert.match(err, /must run as user 'claude'/);
    assert.match(err, /sudo -u claude -H agentlinux install/);
  });
});
