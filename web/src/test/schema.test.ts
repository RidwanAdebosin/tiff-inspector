// @vitest-environment node
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import Ajv2020 from "ajv/dist/2020";
import { describe, expect, it } from "vitest";
import { successBody } from "./fixtures/successReport";

const repoRoot = resolve(__dirname, "../../..");
const schema = JSON.parse(
  readFileSync(join(repoRoot, "schema/inspection-report.v1.json"), "utf8"),
);
const validate = new Ajv2020({ allErrors: true, strict: false }).compile(
  schema,
);

describe("mock fixture", () => {
  it("validates against inspection-report.v1.json", () => {
    const ok = validate(JSON.parse(successBody));
    expect(validate.errors ?? []).toEqual([]);
    expect(ok).toBe(true);
  });
});

describe("schema", () => {
  it("rejects a report with an unknown field status", () => {
    const bad = JSON.parse(successBody);
    bad.directories[0].width.status = "guessed";
    expect(validate(bad)).toBe(false);
  });
});
