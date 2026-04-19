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
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SCHEMA = join(HERE, "..", "..", "catalog", "schema.json");
const CATALOG = join(HERE, "..", "..", "catalog", "catalog.json");

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
console.log(`catalog-schema-validate: ${catalog.agents.length} entries OK`);
