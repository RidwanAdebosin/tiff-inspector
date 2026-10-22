#!/usr/bin/env node
// Generates web/src/api/types.ts from schema/inspection-report.v1.json.
//
//   node scripts/gen-types.mjs           write src/api/types.ts
//   node scripts/gen-types.mjs --check   regenerate into a temp file and fail
//                                        if it differs from src/api/types.ts
//
import { readFile, writeFile, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { compile } from "json-schema-to-typescript";

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(here, "..");
const schemaPath = resolve(webRoot, "../schema/inspection-report.v1.json");
const outPath = resolve(webRoot, "src/api/types.ts");

const BANNER = `/* eslint-disable */
/**
 * GENERATED FILE — DO NOT EDIT.
 *
 * Source: schema/inspection-report.v1.json
 * Regenerate with \`npm run gen:types\`; CI verifies it with \`npm run check:types\`.
 */`;

/**
 * TypeScript names for $defs whose key would shadow a global (e.g. `Error`).
 * Only the emitted type name changes; the shape is untouched.
 */
const RENAMES = { Error: "ReportError" };

/** Give every $def a title so the generator names types after their definition key. */
function titleDefs(schema) {
  for (const [name, def] of Object.entries(schema.$defs ?? {})) {
    if (def && typeof def === "object") def.title = RENAMES[name] ?? def.title ?? name;
  }
  return schema;
}

export async function generate() {
  const raw = JSON.parse(await readFile(schemaPath, "utf8"));
  const schema = titleDefs(raw);
  const ts = await compile(schema, "InspectionReport", {
    bannerComment: BANNER,
    additionalProperties: false,
    unreachableDefinitions: true,
    strictIndexSignatures: true,
    declareExternallyReferenced: true,
    enableConstEnums: false,
    format: true,
    style: { singleQuote: false, semi: true, printWidth: 100 },
    cwd: dirname(schemaPath),
  });
  return ts;
}

async function main() {
  const check = process.argv.includes("--check");
  const ts = await generate();
  if (!check) {
    await writeFile(outPath, ts);
    console.log(`wrote ${outPath}`);
    return;
  }
  const dir = await mkdtemp(join(tmpdir(), "tiff-inspector-types-"));
  try {
    const tmp = join(dir, "types.ts");
    await writeFile(tmp, ts);
    const [fresh, committed] = await Promise.all([
      readFile(tmp, "utf8"),
      readFile(outPath, "utf8").catch(() => ""),
    ]);
    if (fresh !== committed) {
      console.error(
        "src/api/types.ts is out of date with schema/inspection-report.v1.json.\n" +
          "Run `npm run gen:types` and commit the result.",
      );
      process.exitCode = 1;
    } else {
      console.log("src/api/types.ts is up to date.");
    }
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
