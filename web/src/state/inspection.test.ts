import { describe, expect, it } from "vitest";
import { successReport, successBody } from "../test/fixtures/successReport";
import {
  initialState,
  inspectionReducer as reduce,
  isBusy,
  isCancellable,
  isRetryable,
  type InspectionState,
} from "./inspection";

const file = new File(["x"], "a.tif");
const other = new File(["y"], "b.tif");

const validating: InspectionState = { phase: "validating", file };
const uploading: InspectionState = {
  phase: "uploading",
  file,
  loaded: 0,
  total: 1,
};
const parsing: InspectionState = { phase: "parsing", file };
const errorOf = (kind: "network" | "invalid_file"): InspectionState => ({
  phase: "error",
  file,
  kind,
  message: "m",
});

describe("inspectionReducer", () => {
  it("runs the happy path idle → validating → uploading → parsing → success", () => {
    let s = reduce(initialState, { type: "select", file });
    expect(s).toEqual(validating);
    s = reduce(s, { type: "validation_passed" });
    expect(s).toEqual({
      phase: "uploading",
      file,
      loaded: 0,
      total: file.size,
    });
    s = reduce(s, { type: "upload_progress", loaded: 1, total: 1 });
    expect(s).toMatchObject({ phase: "uploading", loaded: 1, total: 1 });
    s = reduce(s, { type: "uploaded" });
    expect(s).toEqual(parsing);
    s = reduce(s, {
      type: "succeeded",
      report: successReport,
      rawBody: successBody,
    });
    expect(s).toEqual({
      phase: "success",
      file,
      report: successReport,
      rawBody: successBody,
    });
  });

  it("keeps a non-computable (0) upload total so the UI can show an indeterminate bar", () => {
    expect(
      reduce(uploading, { type: "upload_progress", loaded: 5, total: 0 }),
    ).toMatchObject({ loaded: 5, total: 0 });
  });

  it("validation failure becomes an invalid_file error", () => {
    expect(
      reduce(validating, { type: "validation_failed", message: "bad" }),
    ).toEqual({
      phase: "error",
      file,
      kind: "invalid_file",
      message: "bad",
    });
  });

  it("server failure keeps kind, code and status", () => {
    const s = reduce(parsing, {
      type: "failed",
      error: {
        kind: "malformed",
        code: "truncated",
        status: 422,
        message: "cut",
      },
    });
    expect(s).toEqual({
      phase: "error",
      file,
      kind: "malformed",
      code: "truncated",
      status: 422,
      message: "cut",
    });
  });

  it("server failure carries retryAfterSeconds", () => {
    const s = reduce(parsing, {
      type: "failed",
      error: {
        kind: "rate_limited",
        code: "rate_limited",
        status: 429,
        message: "slow down",
        retryAfterSeconds: 7,
      },
    });
    expect(s).toMatchObject({
      phase: "error",
      kind: "rate_limited",
      retryAfterSeconds: 7,
    });
  });

  it("a response may arrive straight from uploading", () => {
    expect(
      reduce(uploading, {
        type: "succeeded",
        report: successReport,
        rawBody: "{}",
      }).phase,
    ).toBe("success");
  });

  it.each([validating, uploading, parsing])(
    "ignores select and reset while $phase (no duplicate submissions)",
    (s) => {
      expect(isBusy(s)).toBe(true);
      expect(reduce(s, { type: "select", file: other })).toBe(s);
      expect(reduce(s, { type: "reset" })).toBe(s);
    },
  );

  it("ignores out-of-phase events", () => {
    expect(reduce(initialState, { type: "uploaded" })).toBe(initialState);
    expect(
      reduce(initialState, {
        type: "succeeded",
        report: successReport,
        rawBody: "",
      }),
    ).toBe(initialState);
    expect(
      reduce(parsing, { type: "upload_progress", loaded: 1, total: 1 }),
    ).toBe(parsing);
    expect(reduce(uploading, { type: "validation_passed" })).toBe(uploading);
  });

  describe("cancel", () => {
    it.each([uploading, parsing])("returns to idle from $phase", (s) => {
      expect(isCancellable(s)).toBe(true);
      expect(reduce(s, { type: "cancel" })).toEqual(initialState);
    });

    it.each([initialState, validating, errorOf("network")])(
      "is ignored while $phase",
      (s) => {
        expect(isCancellable(s)).toBe(false);
        expect(reduce(s, { type: "cancel" })).toBe(s);
      },
    );

    it("drops a late response from the cancelled request", () => {
      const idle = reduce(uploading, { type: "cancel" });
      expect(
        reduce(idle, { type: "succeeded", report: successReport, rawBody: "" }),
      ).toBe(idle);
      expect(
        reduce(idle, {
          type: "failed",
          error: { kind: "server", message: "late" },
        }),
      ).toBe(idle);
      expect(reduce(idle, { type: "uploaded" })).toBe(idle);
    });

    it("allows selecting a new file right after cancelling", () => {
      const idle = reduce(parsing, { type: "cancel" });
      expect(reduce(idle, { type: "select", file: other })).toEqual({
        phase: "validating",
        file: other,
      });
    });
  });

  it("retry re-validates the same file only for retryable errors", () => {
    expect(reduce(errorOf("network"), { type: "retry" })).toEqual(validating);
    const invalid = errorOf("invalid_file");
    expect(reduce(invalid, { type: "retry" })).toBe(invalid);
  });

  it("limit_exceeded is retryable; unsupported_feature is not", () => {
    expect(isRetryable("limit_exceeded")).toBe(true);
    expect(isRetryable("unsupported_feature")).toBe(false);
  });

  it("allows choosing another file from error and success", () => {
    expect(
      reduce(errorOf("invalid_file"), { type: "select", file: other }),
    ).toEqual({ phase: "validating", file: other });
    const success: InspectionState = {
      phase: "success",
      file,
      report: successReport,
      rawBody: "",
    };
    expect(reduce(success, { type: "reset" })).toEqual(initialState);
    expect(reduce(success, { type: "select", file: other })).toEqual({
      phase: "validating",
      file: other,
    });
  });
});
