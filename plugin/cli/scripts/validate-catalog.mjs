#!/usr/bin/env node
// plugin/cli/scripts/validate-catalog.mjs — Phase 4 ajv-driven pre-commit wrapper.
// Replaces the Phase 1 zero-dep scaffold; invoked by .pre-commit-config.yaml
// on plugin/catalog/ changes. Pattern ref: 04-RESEARCH §Example 2 lines 1296-1337.
//
// Keeps a graceful early-exit if catalog.json does not yet exist (Wave 1 hasn't
// shipped it — Plan 04-02). Dynamic import of ajv/ajv-formats means the script
// is runnable even before `pnpm install` completes, yielding a clearer error
// than a top-level import failure.
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SCHEMA = join(HERE, "..", "..", "catalog", "schema.json");
const CATALOG = join(HERE, "..", "..", "catalog", "catalog.json");
const PRESERVE_SCHEMA = join(HERE, "..", "..", "catalog", "preserve_paths.schema.json");
const CATALOG_DIR = join(HERE, "..", "..", "catalog");

if (!existsSync(SCHEMA)) {
  console.error(`catalog-schema-validate: missing schema at ${SCHEMA}`);
  process.exit(1);
}

if (!existsSync(CATALOG)) {
  console.log("catalog-schema-validate: no catalog.json yet (Wave 1 skeleton) — skipping");
  process.exit(0);
}

let Ajv2020;
let addFormats;
try {
  ({ default: Ajv2020 } = await import("ajv/dist/2020.js"));
  ({ default: addFormats } = await import("ajv-formats"));
} catch (err) {
  console.error(
    "catalog-schema-validate: ajv not installed — run `pnpm install` in plugin/cli/ first",
  );
  console.error(`  reason: ${err?.message ?? err}`);
  process.exit(1);
}

// strictRequired:false mirrors plugin/cli/src/catalog/schema.ts — the
// allOf/then `required` clause references `npm_package_name` defined on
// the parent $defs/agent; Ajv 2020's strict mode flags this false-positive.
const ajv = new Ajv2020({ allErrors: true, strict: true, strictRequired: false });
addFormats(ajv);
const validate = ajv.compile(JSON.parse(readFileSync(SCHEMA, "utf8")));
const catalog = JSON.parse(readFileSync(CATALOG, "utf8"));

if (!validate(catalog)) {
  console.error("catalog-schema-validate: FAILED");
  for (const err of validate.errors ?? []) {
    console.error(
      `  • ${err.instancePath || "(root)"}: ${err.message} ${JSON.stringify(err.params)}`,
    );
  }
  process.exit(1);
}

// Plan 14-03: validate sibling preserve_paths.json for each agent that
// declares preserve_paths_file. Schema-level: shape must match
// preserve_paths.schema.json (preserve_paths array of strings starting with
// '~/'). Loader-level (T-14-04): also reject '..' path traversal here so
// pre-commit catches malformed catalogs before they ship.
let validatePreserve = null;
if (existsSync(PRESERVE_SCHEMA)) {
  validatePreserve = ajv.compile(JSON.parse(readFileSync(PRESERVE_SCHEMA, "utf8")));
}

let preserveErrors = 0;
let preserveChecked = 0;
for (const agent of catalog.agents) {
  if (!agent.preserve_paths_file) continue;
  const agentDir = join(CATALOG_DIR, "agents", agent.id);
  const preservePath = join(agentDir, agent.preserve_paths_file);
  if (!existsSync(preservePath)) {
    console.error(
      `catalog-schema-validate: agent '${agent.id}' declares preserve_paths_file='${agent.preserve_paths_file}' but ${preservePath} is missing`,
    );
    preserveErrors++;
    continue;
  }
  let preserved;
  try {
    preserved = JSON.parse(readFileSync(preservePath, "utf8"));
  } catch (err) {
    console.error(
      `catalog-schema-validate: agent '${agent.id}' preserve_paths.json is not valid JSON: ${err?.message ?? err}`,
    );
    preserveErrors++;
    continue;
  }
  if (validatePreserve && !validatePreserve(preserved)) {
    console.error(`catalog-schema-validate: agent '${agent.id}' preserve_paths.json FAILED schema`);
    for (const err of validatePreserve.errors ?? []) {
      console.error(
        `  • ${err.instancePath || "(root)"}: ${err.message} ${JSON.stringify(err.params)}`,
      );
    }
    preserveErrors++;
    continue;
  }
  // T-14-04 mitigation: reject `..` path traversal AND absolute paths even
  // when the schema's pattern would allow `~/foo/../etc`. Mirror the
  // normalize-and-check logic from plugin/cli/src/catalog/loader.ts so the
  // pre-commit gate catches drift before it ships.
  for (let i = 0; i < preserved.preserve_paths.length; i++) {
    const raw = preserved.preserve_paths[i];
    if (typeof raw !== "string" || !raw.startsWith("~/")) {
      console.error(
        `catalog-schema-validate: agent '${agent.id}' preserve_paths[${i}] must start with '~/': ${raw}`,
      );
      preserveErrors++;
      continue;
    }
    const stripped = raw.slice(2).replace(/\/+$/, "");
    if (stripped.length === 0) {
      console.error(
        `catalog-schema-validate: agent '${agent.id}' preserve_paths[${i}] empty after stripping '~/': ${raw}`,
      );
      preserveErrors++;
      continue;
    }
    const norm = normalize(stripped);
    if (norm.startsWith("/") || norm.split("/").some((s) => s === "..")) {
      console.error(
        `catalog-schema-validate: agent '${agent.id}' preserve_paths[${i}] forbidden traversal/absolute: ${raw} (normalized: ${norm})`,
      );
      preserveErrors++;
    }
  }
  preserveChecked++;
}

if (preserveErrors > 0) {
  console.error(`catalog-schema-validate: ${preserveErrors} preserve_paths.json errors — FAILED`);
  process.exit(1);
}

console.log(
  `catalog-schema-validate: ${catalog.agents.length} entries OK (${preserveChecked} preserve_paths.json validated)`,
);
