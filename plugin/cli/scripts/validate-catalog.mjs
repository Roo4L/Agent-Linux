#!/usr/bin/env node
// plugin/cli/scripts/validate-catalog.mjs — ajv-driven pre-commit wrapper,
// invoked by .pre-commit-config.yaml on plugin/catalog/ changes. Dynamic import
// of ajv means a missing dep yields a clear error rather than a top-level crash.
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

// strictRequired:false mirrors schema.ts — the allOf/then `required` clause
// references a parent-scope property, which Ajv strict mode flags as a
// false-positive.
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

// Validate each agent's sibling preserve_paths.json against
// preserve_paths.schema.json, then re-check the loader's traversal rules so
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
  // Reject `..` traversal + absolute paths (the schema pattern alone would
  // allow `~/foo/../etc`). Mirrors loader.ts's normalize-and-check.
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
