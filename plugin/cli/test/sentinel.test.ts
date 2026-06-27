// plugin/cli/test/sentinel.test.ts — per-agent sentinel roundtrip + atomicity.
// Uses AGENTLINUX_STATE_DIR env override to inject a tmp dir (unit-test seam).
// Covers: read missing → null, write+read roundtrip, atomic write (no .tmp.*
// residue), delete idempotent on missing, listSentinels returns full set.

import assert from "node:assert/strict";
import { mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, beforeEach, describe, test } from "node:test";
import type { Sentinel } from "../src/types.js";

// The env var MUST be set BEFORE importing sentinel.ts so the module observes
// the override on first load. sentinel.ts resolves the dir lazily per-call, so
// later mutations also take effect — but setting it up-front avoids surprises.
const TMP_ROOT_PROMISE = mkdtemp(join(tmpdir(), "al-sentinel-"));
let TMP_ROOT: string;

before(async () => {
  TMP_ROOT = await TMP_ROOT_PROMISE;
  process.env.AGENTLINUX_STATE_DIR = join(TMP_ROOT, "installed.d");
});

after(async () => {
  await rm(TMP_ROOT, { recursive: true, force: true });
});

// Dynamic import so the AGENTLINUX_STATE_DIR env var is set before the module
// body runs — belt-and-braces because sentinel.ts resolves per-call anyway.
const { readSentinel, writeSentinel, deleteSentinel, listSentinels } = await import(
  "../src/state/sentinel.js"
);

const baseSentinel: Sentinel = {
  id: "foo",
  version: "1.0.0",
  source: "curated",
  sticky: false,
  installed_at: "2026-04-19T00:00:00.000Z",
};

describe("sentinel roundtrip + atomicity", () => {
  beforeEach(async () => {
    const dir = process.env.AGENTLINUX_STATE_DIR ?? "";
    await rm(dir, { recursive: true, force: true });
  });

  test("readSentinel returns null when dir missing", async () => {
    assert.equal(await readSentinel("nothing"), null);
  });

  test("readSentinel returns null when file missing", async () => {
    await writeSentinel(baseSentinel); // creates dir
    assert.equal(await readSentinel("nothing"), null);
  });

  test("writeSentinel + readSentinel roundtrip preserves every field", async () => {
    await writeSentinel(baseSentinel);
    const got = await readSentinel("foo");
    assert.deepEqual(got, baseSentinel);
  });

  test("writeSentinel is atomic — no .tmp.<pid> residue on success", async () => {
    await writeSentinel(baseSentinel);
    const dir = process.env.AGENTLINUX_STATE_DIR ?? "";
    const files = await readdir(dir);
    assert.equal(
      files.filter((f) => f.includes(".tmp.")).length,
      0,
      `leftover tmp files: ${files.join(", ")}`,
    );
    assert.ok(files.includes("foo.json"));
  });

  test("deleteSentinel is idempotent on missing file", async () => {
    await assert.doesNotReject(deleteSentinel("nothing"));
  });

  test("deleteSentinel removes existing sentinel", async () => {
    await writeSentinel(baseSentinel);
    assert.notEqual(await readSentinel("foo"), null);
    await deleteSentinel("foo");
    assert.equal(await readSentinel("foo"), null);
  });

  test("listSentinels returns empty array when dir missing", async () => {
    assert.deepEqual(await listSentinels(), []);
  });

  test("listSentinels returns all sentinels in installed.d/", async () => {
    await writeSentinel(baseSentinel);
    await writeSentinel({ ...baseSentinel, id: "bar", version: "2.0.0" });
    const list = await listSentinels();
    assert.equal(list.length, 2);
    const ids = list.map((s) => s.id).sort();
    assert.deepEqual(ids, ["bar", "foo"]);
  });

  // Plan 13-02: widened Sentinel type accepts the REUSE-03 discriminator shape
  // (status: "reused" + binary_path + detected_source + reused_at +
  // compatibility_window_at_reuse). Legacy sentinels (no status field) still
  // pass roundtrip because the discriminator is optional.
  test("widened Sentinel accepts reused status with binary_path + reused_at fields (REUSE-03)", async () => {
    const reusedSentinel: Sentinel = {
      ...baseSentinel,
      id: "claude-code",
      version: "2.1.98",
      source: "curated",
      sticky: false,
      installed_at: "2026-05-16T00:00:00.000Z",
      status: "reused",
      binary_path: "/home/agent/.local/bin/claude",
      detected_source: "pre-existing",
      reused_at: "2026-05-16T00:00:00.000Z",
      compatibility_window_at_reuse: ">=2.0.0 <3.0.0",
    };
    await writeSentinel(reusedSentinel);
    const got = await readSentinel("claude-code");
    assert.deepEqual(got, reusedSentinel);
    assert.equal(got?.status, "reused");
    assert.equal(got?.binary_path, "/home/agent/.local/bin/claude");
    assert.equal(got?.compatibility_window_at_reuse, ">=2.0.0 <3.0.0");
  });

  // Plan 14-03 (REMEDIATE-04): broken-after-remediate is the terminal state
  // reached when uninstall.sh succeeded but the follow-up install.sh failed.
  // The sentinel is forensic — list.ts renders it with the half-uninstalled
  // suffix; install.ts writes it from the REMEDIATE branch's catch site.
  // Roundtrip preserves the new status union value + the remediated_at +
  // remediate_failure_reason fields.
  test("widened Sentinel accepts broken-after-remediate status with remediated_at + remediate_failure_reason fields (REMEDIATE-04)", async () => {
    const brokenSentinel: Sentinel = {
      ...baseSentinel,
      id: "claude-code",
      version: "2.1.98",
      source: "curated",
      sticky: false,
      installed_at: "2026-05-24T00:00:00.000Z",
      status: "broken-after-remediate",
      remediated_at: "2026-05-24T00:00:00.000Z",
      remediate_failure_reason: "install-failed-post-uninstall",
    };
    await writeSentinel(brokenSentinel);
    const got = await readSentinel("claude-code");
    assert.deepEqual(got, brokenSentinel);
    assert.equal(got?.status, "broken-after-remediate");
    assert.equal(got?.remediated_at, "2026-05-24T00:00:00.000Z");
    assert.equal(got?.remediate_failure_reason, "install-failed-post-uninstall");
  });

  // Plan 15-01 (D-15-02): Sentinel.status union widens to include
  // "reused-with-warning" + new optional decline_reason field. Written by the
  // bash entrypoint's TTY prompt loop on decline; read by list.ts /
  // upgrade.ts so subsequent CLI invocations surface the operator's choice.
  // Three decline_reason tokens are valid: chown-declined,
  // sudoers-drift-declined, reinstall-broken-declined (one per state-
  // overwriting action class).
  test("U5 (D-15-02): roundtrip status='reused-with-warning' + decline_reason='chown-declined' preserves both fields", async () => {
    const declined: Sentinel = {
      ...baseSentinel,
      id: "npm-prefix",
      version: "0.0.0",
      status: "reused-with-warning",
      decline_reason: "chown-declined",
    };
    await writeSentinel(declined);
    const got = await readSentinel("npm-prefix");
    assert.deepEqual(got, declined);
    assert.equal(got?.status, "reused-with-warning");
    assert.equal(got?.decline_reason, "chown-declined");
  });

  test("U6 (D-15-02): roundtrip status='reused-with-warning' + decline_reason='sudoers-drift-declined'", async () => {
    const declined: Sentinel = {
      ...baseSentinel,
      id: "sudoers",
      version: "0.0.0",
      status: "reused-with-warning",
      decline_reason: "sudoers-drift-declined",
    };
    await writeSentinel(declined);
    const got = await readSentinel("sudoers");
    assert.equal(got?.status, "reused-with-warning");
    assert.equal(got?.decline_reason, "sudoers-drift-declined");
  });

  test("U7 (D-15-02): roundtrip status='reused-with-warning' + decline_reason='reinstall-broken-declined'", async () => {
    const declined: Sentinel = {
      ...baseSentinel,
      id: "claude-code",
      version: "2.1.98",
      status: "reused-with-warning",
      decline_reason: "reinstall-broken-declined",
    };
    await writeSentinel(declined);
    const got = await readSentinel("claude-code");
    assert.equal(got?.status, "reused-with-warning");
    assert.equal(got?.decline_reason, "reinstall-broken-declined");
  });
});
