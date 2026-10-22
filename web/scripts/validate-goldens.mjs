#!/usr/bin/env node
// Validates every ../test/golden/*.json report against schema/inspection-report.v1.json.
// Exits non-zero if any file is invalid JSON or fails schema validation.

import { readFile, readdir } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "../..");
const schemaPath = join(repoRoot, "schema/inspection-report.v1.json");
const goldenDir = join(repoRoot, "test/golden");

const schema = JSON.parse(await readFile(schemaPath, "utf8"));
const ajv = new Ajv2020({
  allErrors: true,
  strict: true,
  // The FieldOf-derived defs use `$ref` + `properties` without `type: "object"`;
  // that is valid JSON Schema, so report it instead of refusing to compile.
  strictTypes: "log",
  allowUnionTypes: true,
});
addFormats(ajv);
const validate = ajv.compile(schema);

const files = (await readdir(goldenDir)).filter((f) => f.endsWith(".json")).sort();
if (files.length === 0) {
  console.error(`No golden files found in ${goldenDir}`);
  process.exit(1);
}

let failures = 0;
for (const name of files) {
  let data;
  try {
    data = JSON.parse(await readFile(join(goldenDir, name), "utf8"));
  } catch (err) {
    failures += 1;
    console.error(`FAIL ${name}: invalid JSON (${err.message})`);
    continue;
  }
  if (validate(data)) {
    console.log(`ok   ${name} (${data.ok ? "success" : `failure: ${data.error?.code}`})`);
  } else {
    failures += 1;
    console.error(`FAIL ${name}`);
    for (const e of validate.errors ?? []) console.error(`     ${e.instancePath || "/"} ${e.message}`);
  }
}

console.log(`\n${files.length - failures}/${files.length} golden reports valid.`);
if (failures > 0) process.exit(1);
