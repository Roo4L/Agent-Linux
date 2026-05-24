// plugin/cli/src/state/sentinel.ts — per-agent sentinel read/write.
// Pattern ref: 04-RESEARCH §Pattern 5 (lines 670-770) — per-agent files under
// /opt/agentlinux/state/installed.d/<id>.json; atomic rename (tmp + rename(2))
// on same filesystem per POSIX.
//
// Concurrency model: atomic-rename-only (no flock). The interactive-user
// workflow rarely races two writes on the SAME agent; rename(2) is atomic per
// POSIX, so cross-agent invocations cannot corrupt each other. If Phase 5+
// introduces an automated-loop caller (nightly upgrade cron), re-introduce
// flock(1) around the multi-sentinel scan in listSentinels.
//
// Testability seam: AGENTLINUX_STATE_DIR env var overrides the default
// /opt/agentlinux/state/installed.d path so unit tests can inject a tmp dir
// without needing root to precreate the real path.

import { mkdir, readFile, readdir, rename, unlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { Sentinel } from "../types.js";

const DEFAULT_INSTALLED_DIR = "/opt/agentlinux/state/installed.d";

// Resolve installed-dir lazily on each call so tests that mutate the env var
// after module import still take effect. The overhead is one env lookup.
function installedDir(): string {
  return process.env.AGENTLINUX_STATE_DIR ?? DEFAULT_INSTALLED_DIR;
}

export async function readSentinel(id: string): Promise<Sentinel | null> {
  try {
    const data = await readFile(join(installedDir(), `${id}.json`), "utf8");
    return JSON.parse(data) as Sentinel;
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw err;
  }
}

export async function writeSentinel(entry: Sentinel): Promise<void> {
  const dir = installedDir();
  // mkdir recursive covers (a) first-ever sentinel write before the provisioner
  // has created the dir (Plan 06 ships it at install time), and (b) unit-test
  // tmp dirs that haven't been created. Mode 0755 matches plugin/provisioner
  // defaults.
  await mkdir(dir, { recursive: true, mode: 0o755 });
  const target = join(dir, `${entry.id}.json`);
  const tmp = `${target}.tmp.${process.pid}`;
  await writeFile(tmp, `${JSON.stringify(entry, null, 2)}\n`, { mode: 0o644 });
  await rename(tmp, target); // atomic on same filesystem (POSIX rename(2))
}

export async function deleteSentinel(id: string): Promise<void> {
  try {
    await unlink(join(installedDir(), `${id}.json`));
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code !== "ENOENT") throw err;
    // Idempotent: missing file is not an error.
  }
}

export async function listSentinels(): Promise<Sentinel[]> {
  const dir = installedDir();
  let files: string[];
  try {
    files = await readdir(dir);
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw err;
  }
  const ids = files.filter((f) => f.endsWith(".json")).map((f) => f.replace(/\.json$/, ""));
  const sentinels = await Promise.all(ids.map((id) => readSentinel(id)));
  return sentinels.filter((s): s is Sentinel => s !== null);
}
