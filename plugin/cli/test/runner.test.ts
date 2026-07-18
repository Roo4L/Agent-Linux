// plugin/cli/test/runner.test.ts — dispatchRecipe env-injection + canonical PATH.
// Uses DI (dispatcher param) rather than node:test mock.module because Node
// 20.20.1 (executor host) does not expose mock.module (undefined on t.mock).
// Target runtime Node 22 LTS will support it; DI keeps tests portable across
// both Node 20 dev and Node 22 production without any flag toggles.

import assert from "node:assert/strict";
import { beforeEach, describe, test } from "node:test";
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

  test("#2: threads the stream flag through to the dispatcher opts (default false)", async () => {
    let seen: { env: Record<string, string>; stream?: boolean } | undefined;
    const spy = async (
      _u: string,
      _a: string[],
      opts: { env: Record<string, string>; stream?: boolean },
    ) => {
      seen = opts;
      return { exitCode: 0, stdout: "", stderr: "" };
    };
    await dispatchRecipe(
      { entry: ENTRY, recipePath: "/x", version: "1.0.0", catalogDir: "/y", stream: true },
      spy,
    );
    assert.equal(seen?.stream, true);

    await dispatchRecipe(
      { entry: ENTRY, recipePath: "/x", version: "1.0.0", catalogDir: "/y" },
      spy,
    );
    assert.equal(seen?.stream, false, "unset stream defaults to false");
  });
});
