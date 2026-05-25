// plugin/cli/test/list.test.ts — listCmd text + JSON rendering + test_only filter.
// Uses AGENTLINUX_CATALOG_DIR + AGENTLINUX_STATE_DIR env seams to stage a
// minimal catalog under a tmp dir; captures console.log via reassignment.

import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, beforeEach, describe, test } from "node:test";
import type { Sentinel } from "../src/types.js";

let TMP: string;
let CATALOG_DIR: string;
let STATE_DIR: string;

const CATALOG = {
  version: "0.3.0",
  agents: [
    {
      id: "real-agent",
      display_name: "Real",
      description: "real-fixture",
      source_kind: "script",
      pinned_version: "1.0.0",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
    },
    {
      id: "test-dummy",
      display_name: "Test Dummy",
      description: "test-fixture",
      source_kind: "script",
      pinned_version: "0.0.1",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
      test_only: true,
    },
  ],
};

before(async () => {
  TMP = await mkdtemp(join(tmpdir(), "al-list-"));
  CATALOG_DIR = join(TMP, "catalog");
  STATE_DIR = join(TMP, "state/installed.d");
  await mkdir(CATALOG_DIR, { recursive: true });
  await writeFile(join(CATALOG_DIR, "catalog.json"), JSON.stringify(CATALOG));
  process.env.AGENTLINUX_CATALOG_DIR = CATALOG_DIR;
  process.env.AGENTLINUX_STATE_DIR = STATE_DIR;
});

after(async () => {
  await rm(TMP, { recursive: true, force: true });
  // `delete` is the only way to unset an env var; biome's unsafe fix would
  // coerce assignments to the literal string "undefined" (Node.js stringifies
  // everything in process.env), contaminating sibling tests.
  // biome-ignore lint/performance/noDelete: delete is semantically required for process.env
  delete process.env.AGENTLINUX_CATALOG_DIR;
  // biome-ignore lint/performance/noDelete: delete is semantically required for process.env
  delete process.env.AGENTLINUX_STATE_DIR;
});

// Dynamic imports so env vars are set before module body observes defaults.
const { listCmd } = await import("../src/commands/list.js");
const { writeSentinel, deleteSentinel } = await import("../src/state/sentinel.js");

// console.log capture helper — swaps the method with a buffer-appending fn,
// returns a restore callback + getter.
function captureStdout() {
  const lines: string[] = [];
  const original = console.log;
  console.log = (...args: unknown[]) => {
    lines.push(args.map((a) => (typeof a === "string" ? a : String(a))).join(" "));
  };
  return {
    lines,
    restore: () => {
      console.log = original;
    },
  };
}

describe("listCmd — text + JSON + test_only filter", () => {
  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
  });

  test("text table defaults to hiding test_only entries", async () => {
    const cap = captureStdout();
    try {
      await listCmd({});
    } finally {
      cap.restore();
    }
    const joined = cap.lines.join("\n");
    assert.match(joined, /^NAME\s+STATUS\s+CURATED\s+INSTALLED\s+DESCRIPTION/);
    assert.match(joined, /real-agent/);
    assert.doesNotMatch(joined, /test-dummy/);
  });

  test("--include-test reveals test-only entries", async () => {
    const cap = captureStdout();
    try {
      await listCmd({ includeTest: true });
    } finally {
      cap.restore();
    }
    const joined = cap.lines.join("\n");
    assert.match(joined, /real-agent/);
    assert.match(joined, /test-dummy/);
  });

  test("all-not-installed when state dir is empty", async () => {
    const cap = captureStdout();
    try {
      await listCmd({ includeTest: true });
    } finally {
      cap.restore();
    }
    // All data rows (after header) show status not-installed
    const dataRows = cap.lines.slice(1);
    for (const line of dataRows) {
      assert.match(line, /not-installed/);
    }
  });

  test("synced status when sentinel version matches pinned_version", async () => {
    const synced: Sentinel = {
      id: "real-agent",
      version: "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-04-19T00:00:00.000Z",
    };
    await writeSentinel(synced);
    try {
      const cap = captureStdout();
      try {
        await listCmd({});
      } finally {
        cap.restore();
      }
      const realRow = cap.lines.find((l) => l.startsWith("real-agent"));
      assert.ok(realRow, "real-agent row present");
      assert.match(realRow ?? "", /synced/);
      assert.match(realRow ?? "", /1\.0\.0/);
    } finally {
      await deleteSentinel("real-agent");
    }
  });

  test("--json emits a valid JSON array parseable by JSON.parse", async () => {
    const cap = captureStdout();
    try {
      await listCmd({ json: true, includeTest: true });
    } finally {
      cap.restore();
    }
    const out = cap.lines.join("\n");
    const parsed = JSON.parse(out);
    assert.ok(Array.isArray(parsed));
    assert.equal(parsed.length, 2);
    const ids = parsed.map((r: { id: string }) => r.id).sort();
    assert.deepEqual(ids, ["real-agent", "test-dummy"]);
    for (const row of parsed) {
      assert.ok("status" in row);
      assert.ok("curated" in row);
      assert.ok("installed" in row);
    }
  });

  test("--json without --include-test omits test_only entries", async () => {
    const cap = captureStdout();
    try {
      await listCmd({ json: true });
    } finally {
      cap.restore();
    }
    const parsed = JSON.parse(cap.lines.join("\n"));
    assert.equal(parsed.length, 1);
    assert.equal(parsed[0].id, "real-agent");
  });

  // Plan 13-02: AGGRESSIVE-ownership disclosure suffix on the INSTALLED column.
  // CONTEXT.md Area 2 Q2 binding: ` (reused — managed by agentlinux upgrade/remove)`.
  test("REUSE-03: reused sentinel renders the (reused — managed) suffix in text output", async () => {
    const reusedSentinel: Sentinel = {
      id: "real-agent",
      version: "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-05-16T00:00:00.000Z",
      status: "reused",
      binary_path: "/home/agent/.local/bin/real",
      detected_source: "pre-existing",
      reused_at: "2026-05-16T00:00:00.000Z",
      compatibility_window_at_reuse: ">=1.0.0 <2.0.0",
    };
    await writeSentinel(reusedSentinel);
    try {
      const cap = captureStdout();
      try {
        await listCmd({});
      } finally {
        cap.restore();
      }
      const joined = cap.lines.join("\n");
      // Em-dash + parenthesized form — bats greps the literal string too.
      assert.match(joined, /\(reused — managed by agentlinux upgrade\/remove\)/);
      // The suffix lives in the INSTALLED column of the real-agent row.
      const realRow = cap.lines.find((l) => l.startsWith("real-agent"));
      assert.ok(realRow);
      assert.match(realRow ?? "", /reused — managed/);
    } finally {
      await deleteSentinel("real-agent");
    }
  });

  test("REUSE-03: --json includes sentinel_status field for reused entries", async () => {
    const reusedSentinel: Sentinel = {
      id: "real-agent",
      version: "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-05-16T00:00:00.000Z",
      status: "reused",
      binary_path: "/home/agent/.local/bin/real",
      detected_source: "pre-existing",
      reused_at: "2026-05-16T00:00:00.000Z",
      compatibility_window_at_reuse: ">=1.0.0 <2.0.0",
    };
    await writeSentinel(reusedSentinel);
    try {
      const cap = captureStdout();
      try {
        await listCmd({ json: true });
      } finally {
        cap.restore();
      }
      const parsed = JSON.parse(cap.lines.join("\n"));
      const row = parsed.find((r: { id: string }) => r.id === "real-agent");
      assert.ok(row);
      assert.equal(row.reused, true);
      assert.equal(row.sentinel_status, "reused");
      // JSON output does NOT carry the text suffix in the installed field.
      assert.equal(row.installed, "1.0.0");
    } finally {
      await deleteSentinel("real-agent");
    }
  });

  test("REUSE-03: status:installed sentinels do NOT get the reused suffix", async () => {
    await writeSentinel({
      id: "real-agent",
      version: "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-05-16T00:00:00.000Z",
      status: "installed",
    });
    try {
      const cap = captureStdout();
      try {
        await listCmd({});
      } finally {
        cap.restore();
      }
      const joined = cap.lines.join("\n");
      assert.doesNotMatch(joined, /reused — managed/);
    } finally {
      await deleteSentinel("real-agent");
    }
  });

  // Plan 14-03 (REMEDIATE-04): broken-after-remediate sentinel renders with
  // the half-uninstalled-manual-recovery suffix in the INSTALLED column. The
  // suffix takes precedence over the reused suffix (mutually exclusive
  // states). Binding wording matches install.ts's writeSentinel callsite +
  // bats Test 53.
  test("REMEDIATE-04: broken-after-remediate sentinel renders the half-uninstalled suffix in text output", async () => {
    const brokenSentinel: Sentinel = {
      id: "real-agent",
      version: "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-05-24T00:00:00.000Z",
      status: "broken-after-remediate",
      remediated_at: "2026-05-24T00:00:00.000Z",
      remediate_failure_reason: "install-failed-post-uninstall",
    };
    await writeSentinel(brokenSentinel);
    try {
      const cap = captureStdout();
      try {
        await listCmd({});
      } finally {
        cap.restore();
      }
      const joined = cap.lines.join("\n");
      // Binding wording — bats Test 53 greps the same literal string.
      assert.match(joined, /\(broken — half-uninstalled, manual recovery needed\)/);
      const realRow = cap.lines.find((l) => l.startsWith("real-agent"));
      assert.ok(realRow);
      assert.match(realRow ?? "", /broken — half-uninstalled/);
      // Reused suffix must NOT also appear (mutually exclusive states).
      assert.doesNotMatch(realRow ?? "", /reused — managed/);
    } finally {
      await deleteSentinel("real-agent");
    }
  });

  test("REMEDIATE-04: --json includes sentinel_status=broken-after-remediate for tooling", async () => {
    const brokenSentinel: Sentinel = {
      id: "real-agent",
      version: "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-05-24T00:00:00.000Z",
      status: "broken-after-remediate",
      remediated_at: "2026-05-24T00:00:00.000Z",
      remediate_failure_reason: "install-failed-post-uninstall",
    };
    await writeSentinel(brokenSentinel);
    try {
      const cap = captureStdout();
      try {
        await listCmd({ json: true });
      } finally {
        cap.restore();
      }
      const parsed = JSON.parse(cap.lines.join("\n"));
      const row = parsed.find((r: { id: string }) => r.id === "real-agent");
      assert.ok(row);
      assert.equal(row.sentinel_status, "broken-after-remediate");
      // JSON output does NOT carry the text suffix in the installed field
      // (matches the REUSE-03 JSON-vs-text convention).
      assert.equal(row.installed, "1.0.0");
      // reused flag is false (reused implies status === 'reused', not
      // 'broken-after-remediate').
      assert.equal(row.reused, false);
    } finally {
      await deleteSentinel("real-agent");
    }
  });
});
