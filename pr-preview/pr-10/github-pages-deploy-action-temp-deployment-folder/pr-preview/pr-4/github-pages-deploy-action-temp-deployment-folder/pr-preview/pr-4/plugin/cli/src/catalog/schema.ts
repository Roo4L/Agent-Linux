// plugin/cli/src/catalog/schema.ts — Ajv 2020-12 singleton + compiled validator.
// Pattern ref: 04-RESEARCH §Pattern 9 (lines 958-986) + Pitfall 1 (ajv/dist/2020.js
// explicit extension for NodeNext ESM resolution).
// Contracts: CAT-03 (schema authoritative), CAT-04 (pinned_version required).
//
// Import shape: ajv is CJS under the hood; under `module: NodeNext` with
// `esModuleInterop: true`, the namespace-import form is the most portable
// across TypeScript versions — TS 5.x sometimes refuses the default-import
// shape on the 2020 subpath despite `export default`. `.js` extension is
// load-bearing for NodeNext runtime resolution (Pitfall 1).

import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { ErrorObject, ValidateFunction } from "ajv";
import * as AjvFormatsModule from "ajv-formats";
import * as AjvModule from "ajv/dist/2020.js";

// CJS interop: the default export is the class under esModuleInterop. Support
// both the `.default` shape (NodeNext runtime) and direct namespace access
// (some bundlers hoist the default). Same defensive trick for ajv-formats.
// biome-ignore lint/suspicious/noExplicitAny: CJS interop bridge
const Ajv2020: any = (AjvModule as any).default ?? (AjvModule as any).Ajv2020 ?? AjvModule;
// biome-ignore lint/suspicious/noExplicitAny: CJS interop bridge
const addFormats: any = (AjvFormatsModule as any).default ?? AjvFormatsModule;

import { access } from "node:fs/promises";

const HERE = dirname(fileURLToPath(import.meta.url));

// Schema-path resolution must cover three layouts:
//   1. Production ship under /opt/agentlinux/cli/<ver>/dist/catalog/schema.js
//      → walks ../../../catalog/schema.json only if the catalog is staged
//      next to the CLI; the provisioner-level layout actually has
//      /opt/agentlinux/catalog/<ver>/schema.json (separate subtree).
//   2. Repo dev build at plugin/cli/dist/catalog/schema.js
//      → ../../../catalog/schema.json == plugin/catalog/schema.json.
//   3. Repo test build at plugin/cli/dist-test/src/catalog/schema.js
//      → ../../../../catalog/schema.json == plugin/catalog/schema.json.
//
// Resolution order:
//   a. AGENTLINUX_CATALOG_DIR env var (same seam loader.ts uses),
//   b. production default: /opt/agentlinux/catalog/<AGENTLINUX_VERSION>/schema.json
//      (matches loader.ts's defaultCatalogDir — the 50-registry-cli.sh provisioner
//      stages schema.json there alongside catalog.json at install time),
//   c. walk up from HERE looking for plugin/catalog/schema.json (dev/test only),
//   d. fail with a clear diagnostic enumerating the searched paths.
//
// Plan 04-07 Rule 1 auto-fix: without the production-default candidate, any CLI
// path that calls loadCatalog({validate:true}) (install/remove/upgrade/pin)
// exits non-zero on a freshly-installed system — the schema.json the
// provisioner staged at /opt/agentlinux/catalog/<ver>/ was never checked
// because the walk-up pattern looked for `catalog/schema.json` (singular
// parent) under the CLI tree at /opt/agentlinux/cli/<ver>/dist/, which is
// not where the provisioner puts it. The provisioner's actual layout places
// the catalog in a SEPARATE subtree at /opt/agentlinux/catalog/<ver>/,
// mirrored by loader.ts's defaultCatalogDir(). Mirror it here so both
// resolvers default to the same path.
async function resolveSchemaPath(): Promise<string> {
  const envDir = process.env.AGENTLINUX_CATALOG_DIR;
  const candidates: string[] = [];
  if (envDir) candidates.push(join(envDir, "schema.json"));
  // Production default — matches loader.ts's defaultCatalogDir().
  const ver = process.env.AGENTLINUX_VERSION ?? "0.3.0";
  candidates.push(`/opt/agentlinux/catalog/${ver}/schema.json`);
  // Walk up 6 levels; covers dist/ dist-test/src/ src/ and a couple spare
  // for dev/test layouts.
  for (let depth = 2; depth <= 6; depth++) {
    const up = Array(depth).fill("..");
    candidates.push(join(HERE, ...up, "catalog", "schema.json"));
    candidates.push(join(HERE, ...up, "plugin", "catalog", "schema.json"));
  }
  for (const p of candidates) {
    try {
      await access(p);
      return p;
    } catch {
      // next
    }
  }
  throw new Error(
    `agentlinux: unable to locate catalog schema.json; set AGENTLINUX_CATALOG_DIR. Searched:\n${candidates.map((c) => `  - ${c}`).join("\n")}`,
  );
}

let cached: ValidateFunction | null = null;

export async function getValidator(): Promise<ValidateFunction> {
  if (cached) return cached;
  const schemaPath = await resolveSchemaPath();
  const schema = JSON.parse(await readFile(schemaPath, "utf8"));
  // strictRequired:false — Ajv 2020 strict mode complains when an `allOf[].then`
  // clause names a required property that's declared only in the parent scope
  // (our `npm_package_name` is defined once on the `agent` properties; we don't
  // want to duplicate it inside the `then` clause just to satisfy strict mode).
  // Other strict checks (unknown keywords, strict types) stay on.
  const ajv = new Ajv2020({ allErrors: true, strict: true, strictRequired: false });
  addFormats(ajv);
  const compiled: ValidateFunction = ajv.compile(schema);
  cached = compiled;
  return compiled;
}

export function formatErrors(errors: ErrorObject[] | null | undefined): string {
  if (!errors || errors.length === 0) return "(no errors)";
  return errors
    .map((e) => `  • ${e.instancePath || "(root)"}: ${e.message} ${JSON.stringify(e.params)}`)
    .join("\n");
}
