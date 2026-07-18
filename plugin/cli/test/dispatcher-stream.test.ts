// plugin/cli/test/dispatcher-stream.test.ts — asUser() streaming path (#2 dogfood).
// Exercises the real spawn-tee: invoker===target short-circuit runs the argv
// directly (no sudo), so we drive `bash -c` as the current user and assert the
// output is BOTH teed live to process.stdout/stderr AND captured in the result.

import assert from "node:assert/strict";
import { userInfo } from "node:os";
import { describe, test } from "node:test";
import { asUser } from "../src/state/dispatcher.js";

// invoker === target → asUser runs argv directly (no `sudo -u`), so these tests
// need no privileges and are host-portable.
const SELF = userInfo().username;
const ENV = { ...process.env } as Record<string, string>;

// Swap process.stdout/stderr.write for capturing shims; returns the buffers +
// a restore fn. Keeps the real TTY quiet during the test.
function captureProcessStreams() {
  const out: string[] = [];
  const err: string[] = [];
  const origOut = process.stdout.write.bind(process.stdout);
  const origErr = process.stderr.write.bind(process.stderr);
  // biome-ignore lint/suspicious/noExplicitAny: test shim of the write() overloads
  (process.stdout as any).write = (c: unknown) => {
    out.push(String(c));
    return true;
  };
  // biome-ignore lint/suspicious/noExplicitAny: test shim of the write() overloads
  (process.stderr as any).write = (c: unknown) => {
    err.push(String(c));
    return true;
  };
  return {
    out,
    err,
    restore: () => {
      process.stdout.write = origOut;
      process.stderr.write = origErr;
    },
  };
}

describe("asUser — streaming (#2)", () => {
  test("stream:true tees stdout+stderr live AND captures them; streamed=true", async () => {
    const cap = captureProcessStreams();
    let result: Awaited<ReturnType<typeof asUser>>;
    try {
      result = await asUser(SELF, ["bash", "-c", "echo out-line; echo err-line >&2"], {
        env: ENV,
        stream: true,
      });
    } finally {
      cap.restore();
    }
    assert.equal(result.exitCode, 0);
    assert.equal(result.streamed, true);
    assert.match(result.stdout, /out-line/);
    assert.match(result.stderr, /err-line/);
    // ...and the same bytes were teed to the console as they arrived.
    assert.match(cap.out.join(""), /out-line/);
    assert.match(cap.err.join(""), /err-line/);
  });

  test("stream:true propagates a non-zero exit code without throwing", async () => {
    const cap = captureProcessStreams();
    let result: Awaited<ReturnType<typeof asUser>>;
    try {
      result = await asUser(SELF, ["bash", "-c", "echo hi; exit 7"], { env: ENV, stream: true });
    } finally {
      cap.restore();
    }
    assert.equal(result.exitCode, 7);
    assert.equal(result.streamed, true);
    assert.match(result.stdout, /hi/);
  });

  test("buffered (no stream) still captures output; streamed stays unset", async () => {
    const result = await asUser(SELF, ["bash", "-c", "echo buffered"], { env: ENV });
    assert.equal(result.exitCode, 0);
    assert.match(result.stdout, /buffered/);
    assert.ok(!result.streamed, "buffered path must not claim streamed");
  });

  test("stream:true takes the sudo branch when invoker !== target and returns the shape (no throw)", async () => {
    // A target user that differs from the invoker forces the
    // ["sudo","-u",user,"-H","-E","--",...] branch. Using a user that cannot
    // exist makes the outcome deterministic regardless of the host's sudoers
    // (NOPASSWD or not): sudo errors on the unknown user → non-zero exit, and the
    // streaming path must surface that as a returned shape, never a throw.
    const cap = captureProcessStreams();
    let result: Awaited<ReturnType<typeof asUser>>;
    try {
      result = await asUser("no-such-user-agentlinux-xyzzy", ["bash", "-c", "echo x"], {
        env: ENV,
        stream: true,
      });
    } finally {
      cap.restore();
    }
    assert.notEqual(result.exitCode, 0, "unknown sudo target must fail non-zero");
    assert.equal(result.streamed, true);
  });

  test("stream:true maps a spawn failure (ENOENT) to exitCode 1 without throwing", async () => {
    const cap = captureProcessStreams();
    let result: Awaited<ReturnType<typeof asUser>>;
    try {
      // invoker === target → runs argv directly; the binary does not exist.
      result = await asUser(SELF, ["/no/such/binary/agentlinux-xyzzy"], { env: ENV, stream: true });
    } finally {
      cap.restore();
    }
    assert.equal(result.exitCode, 1, "ENOENT maps to 1 (mirrors the execFile catch)");
    assert.equal(result.streamed, true);
  });

  test("stream:true enforces --timeout via SIGTERM, mapping to exitCode 124", async () => {
    const cap = captureProcessStreams();
    let result: Awaited<ReturnType<typeof asUser>>;
    try {
      result = await asUser(SELF, ["bash", "-c", "sleep 5"], {
        env: ENV,
        stream: true,
        timeout: 300,
      });
    } finally {
      cap.restore();
    }
    assert.equal(result.exitCode, 124, "timed-out child maps to 124 (GNU timeout convention)");
    assert.equal(result.streamed, true);
  });
});
