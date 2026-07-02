// plugin/cli/test/runner.test.ts — dispatchRecipe env-injection + canonical PATH.
// Uses DI (dispatcher param) rather than node:test mock.module because Node
// 20.20.1 (executor host) does not expose mock.module (undefined on t.mock).
// Target runtime Node 22 LTS will support it; DI keeps tests portable across
// both Node 20 dev and Node 22 production without any flag toggles.

import assert from "node:assert/strict";
import { afterEach, beforeEach, describe, test } from "node:test";
import { AGENT_PATH, dispatchRecipe } from "../src/runner.js";
import type { CatalogEntry } from "../src/types.js";

type DispatcherArgs = [string, string[], { env: Record<string, string> }];

function makeCapturingDispatcher() {
  const calls: DispatcherArgs[] = [];
  const impl = async (user: string, argv: string[], opts: { env: Record<string, string> }) => {
    calls.push([user, argv, opts]);
    return { exitCode: 0, stdout: "ok", stderr: "" };
  };
  return { impl, calls };
}

const ENTRY: CatalogEntry = {
  id: "test",
  display_name: "T",
  description: ".",
  source_kind: "script",
  pinned_version: "1.0.0",
  install_recipe_path: "install.sh",
  uninstall_recipe_path: "uninstall.sh",
};

describe("dispatchRecipe", () => {
  let cap: ReturnType<typeof makeCapturingDispatcher>;
  beforeEach(() => {
    cap = makeCapturingDispatcher();
  });

  test("spawns asUser('agent', ['bash', <recipe>]) via injected dispatcher", async () => {
    await dispatchRecipe(
      {
        entry: ENTRY,
        recipePath: "/opt/agentlinux/catalog/0.3.0/agents/test/install.sh",
        version: "1.0.0",
        catalogDir: "/opt/agentlinux/catalog/0.3.0",
      },
      cap.impl,
    );
    assert.equal(cap.calls.length, 1);
    const [user, argv] = cap.calls[0];
    assert.equal(user, "agent");
    assert.deepEqual(argv, ["bash", "/opt/agentlinux/catalog/0.3.0/agents/test/install.sh"]);
  });

  test("injects AGENTLINUX_PINNED_VERSION + CATALOG_DIR + SOURCE_KIND from inputs", async () => {
    await dispatchRecipe(
      {
        entry: ENTRY,
        recipePath: "/x",
        version: "2.3.4",
        catalogDir: "/opt/agentlinux/catalog/0.3.0",
      },
      cap.impl,
    );
    const env = cap.calls[0][2].env;
    assert.equal(env.AGENTLINUX_PINNED_VERSION, "2.3.4");
    assert.equal(env.AGENTLINUX_CATALOG_DIR, "/opt/agentlinux/catalog/0.3.0");
    assert.equal(env.AGENTLINUX_SOURCE_KIND, "script");
    assert.equal(env.AGENTLINUX_AGENT_HOME, "/home/agent");
    assert.equal(env.AGENTLINUX_INSTALL_LOG, "/var/log/agentlinux-install.log");
  });

  test("PATH is the canonical /etc/agentlinux.env literal (Pitfall 5 mitigation)", async () => {
    await dispatchRecipe(
      { entry: ENTRY, recipePath: "/x", version: "1.0.0", catalogDir: "/y" },
      cap.impl,
    );
    const env = cap.calls[0][2].env;
    // Byte-identical to plugin/provisioner/40-path-wiring.sh line 146.
    assert.equal(
      env.PATH,
      "/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin",
    );
    assert.equal(env.PATH, AGENT_PATH);
    assert.equal(env.NPM_CONFIG_PREFIX, "/home/agent/.npm-global");
    assert.equal(env.HOME, "/home/agent");
    assert.equal(env.LANG, "C.UTF-8");
    assert.equal(env.LC_ALL, "C.UTF-8");
  });

  test("extraEnv can append AND override base env", async () => {
    await dispatchRecipe(
      {
        entry: ENTRY,
        recipePath: "/x",
        version: "1.0.0",
        catalogDir: "/y",
        extraEnv: { CUSTOM_VAR: "hello", LANG: "en_US.UTF-8" },
      },
      cap.impl,
    );
    const env = cap.calls[0][2].env;
    assert.equal(env.CUSTOM_VAR, "hello");
    assert.equal(env.LANG, "en_US.UTF-8"); // extraEnv overrides base C.UTF-8
    // Canonical PATH still intact — extraEnv doesn't blow it away.
    assert.equal(env.PATH, AGENT_PATH);
  });

  test("returns the exitCode/stdout/stderr from asUser unchanged", async () => {
    const erroring = async () => ({ exitCode: 3, stdout: "out", stderr: "err" });
    const result = await dispatchRecipe(
      { entry: ENTRY, recipePath: "/x", version: "1.0.0", catalogDir: "/y" },
      erroring,
    );
    assert.deepEqual(result, { exitCode: 3, stdout: "out", stderr: "err" });
  });
});

// AL-50 AC4 / AL-59 catalog-side gap: dispatchRecipe must run recipes AS the
// configured install user (AGENTLINUX_USER), not the hardcoded `agent`, and
// derive HOME/PATH/NPM_CONFIG_PREFIX from that user's home.
describe("dispatchRecipe — configured install user (AL-50 AC4)", () => {
  let cap: ReturnType<typeof makeCapturingDispatcher>;
  let origUserEnv: string | undefined;
  beforeEach(() => {
    cap = makeCapturingDispatcher();
    origUserEnv = process.env.AGENTLINUX_USER;
  });
  afterEach(() => {
    // biome-ignore lint/performance/noDelete: delete is required for process.env
    if (origUserEnv === undefined) delete process.env.AGENTLINUX_USER;
    else process.env.AGENTLINUX_USER = origUserEnv;
  });

  test("AGENTLINUX_USER=claude → dispatches as claude with /home/claude env", async () => {
    process.env.AGENTLINUX_USER = "claude";
    await dispatchRecipe(
      { entry: ENTRY, recipePath: "/opt/.../install.sh", version: "1.0.0", catalogDir: "/c" },
      cap.impl,
    );
    const [user, , opts] = cap.calls[0];
    assert.equal(user, "claude"); // the dispatch user, NOT "agent"
    assert.equal(opts.env.HOME, "/home/claude");
    assert.equal(opts.env.AGENTLINUX_AGENT_HOME, "/home/claude");
    assert.equal(opts.env.NPM_CONFIG_PREFIX, "/home/claude/.npm-global");
    assert.equal(
      opts.env.PATH,
      "/home/claude/.npm-global/bin:/home/claude/.local/bin:/usr/local/bin:/usr/bin:/bin",
    );
  });

  test("explicit AGENTLINUX_USER=agent → byte-identical to the default", async () => {
    process.env.AGENTLINUX_USER = "agent";
    await dispatchRecipe(
      { entry: ENTRY, recipePath: "/x", version: "1.0.0", catalogDir: "/y" },
      cap.impl,
    );
    const [user, , opts] = cap.calls[0];
    assert.equal(user, "agent");
    assert.equal(opts.env.PATH, AGENT_PATH);
    assert.equal(opts.env.HOME, "/home/agent");
    assert.equal(opts.env.NPM_CONFIG_PREFIX, "/home/agent/.npm-global");
  });

  test("malformed AGENTLINUX_USER falls back to agent (T-AL50-06 defense-in-depth)", async () => {
    process.env.AGENTLINUX_USER = "root; rm -rf /"; // fails POSIX charset
    await dispatchRecipe(
      { entry: ENTRY, recipePath: "/x", version: "1.0.0", catalogDir: "/y" },
      cap.impl,
    );
    assert.equal(cap.calls[0][0], "agent");
    assert.equal(cap.calls[0][2].env.HOME, "/home/agent");
  });
});
