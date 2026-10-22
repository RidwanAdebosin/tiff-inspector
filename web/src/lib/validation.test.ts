import { describe, expect, it } from "vitest";
import { MAX_UPLOAD_BYTES } from "./constants";
import { hasAcceptedExtension, isTiffSignature, validateFile, validateFileMeta } from "./validation";

const tiffFile = (bytes: number[], name = "image.tif") => new File([new Uint8Array(bytes)], name);

describe("extension", () => {
  it.each(["a.tif", "a.tiff", "A.TIF", "scan.final.TiFf"])("accepts %s", (n) => {
    expect(hasAcceptedExtension(n)).toBe(true);
  });
  it.each(["a.png", "a.tif.zip", "tif", "a.tf"])("rejects %s", (n) => {
    expect(hasAcceptedExtension(n)).toBe(false);
  });
  it("gives a specific message", () => {
    const r = validateFileMeta({ name: "photo.png", size: 10 });
    expect(r).toMatchObject({ ok: false, reason: "extension" });
    if (!r.ok) expect(r.message).toMatch(/not a \.tif or \.tiff file/);
  });
});

describe("size", () => {
  it("accepts exactly the limit", () => {
    expect(validateFileMeta({ name: "a.tif", size: MAX_UPLOAD_BYTES })).toEqual({ ok: true });
  });
  it("rejects one byte over the limit with the limit in the message", () => {
    const r = validateFileMeta({ name: "a.tif", size: MAX_UPLOAD_BYTES + 1 });
    expect(r).toMatchObject({ ok: false, reason: "size" });
    if (!r.ok) expect(r.message).toContain("25 MB");
  });
  it("rejects empty files", () => {
    expect(validateFileMeta({ name: "a.tif", size: 0 })).toMatchObject({ ok: false, reason: "empty" });
  });
});

describe("magic bytes", () => {
  it.each([
    ["II*\\0", [0x49, 0x49, 0x2a, 0x00]],
    ["MM\\0*", [0x4d, 0x4d, 0x00, 0x2a]],
    ["II+\\0", [0x49, 0x49, 0x2b, 0x00]],
    ["MM\\0+", [0x4d, 0x4d, 0x00, 0x2b]],
  ])("accepts %s", async (_label, sig) => {
    expect(isTiffSignature(sig)).toBe(true);
    expect(await validateFile(tiffFile([...sig, 8, 0, 0, 0]))).toEqual({ ok: true });
  });

  it.each([
    ["PNG", [0x89, 0x50, 0x4e, 0x47]],
    ["mixed byte order", [0x49, 0x4d, 0x2a, 0x00]],
    ["wrong version", [0x49, 0x49, 0x2c, 0x00]],
    ["too short", [0x49, 0x49]],
  ])("rejects %s", async (_label, bytes) => {
    const r = await validateFile(tiffFile(bytes));
    expect(r).toMatchObject({ ok: false, reason: "signature" });
    if (!r.ok) expect(r.message).toMatch(/does not start with a TIFF signature/);
  });

  it("checks extension before reading bytes", async () => {
    const r = await validateFile(tiffFile([0x49, 0x49, 0x2a, 0x00], "image.png"));
    expect(r).toMatchObject({ ok: false, reason: "extension" });
  });

  it("checks size before reading bytes", async () => {
    const f = tiffFile([0x49, 0x49, 0x2a, 0x00]);
    Object.defineProperty(f, "size", { value: MAX_UPLOAD_BYTES + 1 });
    expect(await validateFile(f)).toMatchObject({ ok: false, reason: "size" });
  });
});
