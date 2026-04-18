#!/usr/bin/env node
// Phase 1 catalog-schema validator: zero-dep structural check.
// Real ajv-based validation arrives with Phase 4 when catalog entries ship.
// TODO Phase 4: swap in ajv once plugin/cli dependencies are bootstrapped.
import { readFileSync, existsSync } from 'node:fs';

const SCHEMA_PATH = 'plugin/catalog/schema.json';
const CATALOG_PATH = 'plugin/catalog/catalog.json';

function fail(msg) {
  console.error(`catalog-schema-validate: ${msg}`);
  process.exit(1);
}

if (!existsSync(SCHEMA_PATH)) fail(`missing schema at ${SCHEMA_PATH}`);
const schema = JSON.parse(readFileSync(SCHEMA_PATH, 'utf8'));
if (!schema.properties?.agents) fail(`schema at ${SCHEMA_PATH} is malformed`);

if (!existsSync(CATALOG_PATH)) {
  console.log('catalog-schema-validate: no catalog.json yet (Phase 1 skeleton) — skipping');
  process.exit(0);
}

const catalog = JSON.parse(readFileSync(CATALOG_PATH, 'utf8'));
if (!catalog.version || !Array.isArray(catalog.agents)) {
  fail(`${CATALOG_PATH} missing version or agents[]`);
}
const namePattern = /^[a-z][a-z0-9-]*$/;
for (const a of catalog.agents) {
  if (!a.name || !namePattern.test(a.name)) {
    fail(`agent name "${a.name}" fails pattern ${namePattern}`);
  }
  if (!a.description) fail(`agent ${a.name}: missing description`);
  if (!a.install) fail(`agent ${a.name}: missing install`);
}
console.log(`catalog-schema-validate: ${catalog.agents.length} entries OK`);
