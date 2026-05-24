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
});
