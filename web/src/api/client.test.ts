import { afterEach, describe, expect, it, vi } from "vitest";
import { successBody } from "../test/fixtures/successReport";
import { interpretResponse, parseRetryAfter, uploadInspection, type InspectionError, type InspectionResult } from "./client";
import type { ErrorCode } from "./types";

const failure = (code: ErrorCode, message = `server says ${code}`) =>
  JSON.stringify({
    schema_version: "1.0",
    ok: false,
    tool: { name: "tiff-inspector", version: "0.1.0" },
    file: { name: "a.tif", size_bytes: 10 },
    error: { code, message },
  });

/** Narrow a result to its error, failing the test for success or cancellation. */
const errorOf = (r: InspectionResult): InspectionError => {
  if (r.ok || r.cancelled) throw new Error(`expected an error result, got ${JSON.stringify(r)}`);
  return r.error;
};

describe("interpretResponse", () => {
  it("returns the report and the exact raw body on 200", () => {
    const r = interpretResponse(200, successBody);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.rawBody).toBe(successBody);
      expect(r.report.directories).toHaveLength(2);
    }
  });

  it.each<[number, ErrorCode, string]>([
    [400, "invalid_request", "invalid_file"],
    [413, "file_too_large", "oversized"],
    [415, "not_a_tiff", "invalid_file"],
    [422, "truncated", "malformed"],
    [422, "malformed", "malformed"],
    [422, "unsupported_feature", "unsupported_feature"],
    [422, "limit_exceeded", "limit_exceeded"],
    [429, "rate_limited", "rate_limited"],
    [500, "internal", "server"],
  ])("HTTP %i with code %s → %s, keeping the server message", (status, code, kind) => {
    const r = interpretResponse(status, failure(code));
    expect(r).toEqual({ ok: false, error: { kind, code, status, message: `server says ${code}` } });
  });

  it("keeps limit_exceeded distinct from unsupported_feature", () => {
    const limit = errorOf(interpretResponse(422, failure("limit_exceeded")));
    const unsupported = errorOf(interpretResponse(422, failure("unsupported_feature")));
    expect(limit.kind).toBe("limit_exceeded");
    expect(limit.kind).not.toBe(unsupported.kind);
  });

  it.each([
    [413, "oversized"],
    [415, "invalid_file"],
    [422, "malformed"],
    [429, "rate_limited"],
    [500, "server"],
    [502, "network"],
    [504, "network"],
  ])("non-JSON body with HTTP %i → %s", (status, kind) => {
    const e = errorOf(interpretResponse(status, "<html>Bad Gateway</html>"));
    expect(e.kind).toBe(kind);
    expect(e.code).toBeUndefined();
    expect(e.message.length).toBeGreaterThan(0);
  });

  it("status 0 (connection failed) is a network error", () => {
    expect(errorOf(interpretResponse(0, "")).kind).toBe("network");
  });

  it("200 with an unexpected body is a server error", () => {
    expect(interpretResponse(200, "not json")).toMatchObject({ ok: false, error: { kind: "server" } });
    expect(interpretResponse(200, failure("internal"))).toMatchObject({ ok: false, error: { kind: "server" } });
    expect(interpretResponse(200, JSON.stringify({ ok: true }))).toMatchObject({ ok: false, error: { kind: "server" } });
  });

  it("falls back to status when a FailureReport has an unknown code", () => {
    const body = failure("internal").replace('"internal"', '"brand_new_code"');
    expect(errorOf(interpretResponse(422, body)).kind).toBe("malformed");
  });

  describe("Retry-After", () => {
    it("is carried as retryAfterSeconds on a 429 FailureReport", () => {
      const e = errorOf(interpretResponse(429, failure("rate_limited"), "5"));
      expect(e).toEqual({ kind: "rate_limited", code: "rate_limited", status: 429, message: "server says rate_limited", retryAfterSeconds: 5 });
    });

    it("is carried on a non-JSON 429 too", () => {
      expect(errorOf(interpretResponse(429, "busy", "12")).retryAfterSeconds).toBe(12);
    });

    it("is absent when the header is missing, empty or garbage", () => {
      expect(errorOf(interpretResponse(429, failure("rate_limited")))).not.toHaveProperty("retryAfterSeconds");
      expect(errorOf(interpretResponse(429, failure("rate_limited"), null))).not.toHaveProperty("retryAfterSeconds");
      expect(errorOf(interpretResponse(429, failure("rate_limited"), ""))).not.toHaveProperty("retryAfterSeconds");
      expect(errorOf(interpretResponse(429, failure("rate_limited"), "soon"))).not.toHaveProperty("retryAfterSeconds");
    });
  });
});

describe("parseRetryAfter", () => {
  it("parses delay-seconds", () => {
    expect(parseRetryAfter("5")).toBe(5);
    expect(parseRetryAfter(" 30 ")).toBe(30);
    expect(parseRetryAfter("0")).toBe(0);
  });

  it("parses an HTTP-date relative to now, never negative", () => {
    const now = Date.parse("Wed, 21 Oct 2026 07:28:00 GMT");
    expect(parseRetryAfter("Wed, 21 Oct 2026 07:28:10 GMT", now)).toBe(10);
    expect(parseRetryAfter("Wed, 21 Oct 2026 07:27:00 GMT", now)).toBe(0);
  });

  it("returns undefined for missing or invalid values", () => {
    expect(parseRetryAfter(null)).toBeUndefined();
    expect(parseRetryAfter(undefined)).toBeUndefined();
    expect(parseRetryAfter("")).toBeUndefined();
    expect(parseRetryAfter("-5")).toBeUndefined();
    expect(parseRetryAfter("later")).toBeUndefined();
  });
});

describe("uploadInspection", () => {
  class FakeXHR {
    static last: FakeXHR;
    method = "";
    url = "";
    body: FormData | null = null;
    headers: Record<string, string> = {};
    responseHeaders: Record<string, string> = {};
    status = 0;
    responseText = "";
    responseType = "";
    timeout = 0;
    abortCalls = 0;
    upload: { onprogress?: (e: { loaded: number; total: number; lengthComputable: boolean }) => void; onload?: () => void } = {};
    onload?: () => void;
    onerror?: () => void;
    ontimeout?: () => void;
    onabort?: () => void;
    constructor() {
      FakeXHR.last = this;
    }
    open(method: string, url: string) {
      this.method = method;
      this.url = url;
    }
    setRequestHeader(k: string, v: string) {
      this.headers[k] = v;
    }
    getResponseHeader(name: string): string | null {
      return this.responseHeaders[name.toLowerCase()] ?? null;
    }
    send(body: FormData) {
      this.body = body;
    }
    abort() {
      this.abortCalls += 1;
      this.onabort?.();
    }
  }

  const start = (callbacks = {}) => {
    vi.stubGlobal("XMLHttpRequest", FakeXHR);
    const handle = uploadInspection(new File(["II*\0"], "a.tif"), callbacks);
    return { ...handle, xhr: FakeXHR.last };
  };

  afterEach(() => vi.unstubAllGlobals());

  it("posts multipart field `file` and reports progress, upload completion and the response", async () => {
    const onProgress = vi.fn();
    const onUploaded = vi.fn();
    const { promise, xhr } = start({ onProgress, onUploaded });

    expect(xhr.method).toBe("POST");
    expect(xhr.url).toBe("/api/v1/inspections");
    expect((xhr.body!.get("file") as File).name).toBe("a.tif");

    xhr.upload.onprogress?.({ loaded: 2, total: 4, lengthComputable: true });
    xhr.upload.onload?.();
    expect(onProgress).toHaveBeenCalledWith(2, 4);
    expect(onUploaded).toHaveBeenCalled();

    xhr.status = 415;
    xhr.responseText = failure("not_a_tiff");
    xhr.onload?.();
    expect(await promise).toMatchObject({ ok: false, error: { kind: "invalid_file", code: "not_a_tiff", status: 415 } });
  });

  it("reports total 0 when the request length is not computable", () => {
    const onProgress = vi.fn();
    const { xhr } = start({ onProgress });
    xhr.upload.onprogress?.({ loaded: 2, total: 4, lengthComputable: false });
    expect(onProgress).toHaveBeenCalledWith(2, 0);
  });

  it("sets the upload timeout to the server's total upload limit (300 s)", () => {
    expect(start().xhr.timeout).toBe(300_000);
  });

  it("maps transport errors and timeouts to network errors", async () => {
    const a = start();
    a.xhr.onerror?.();
    expect(await a.promise).toMatchObject({ ok: false, error: { kind: "network" } });

    const b = start();
    b.xhr.ontimeout?.();
    expect(await b.promise).toMatchObject({ ok: false, error: { kind: "network" } });
  });

  it("reads Retry-After from a 429 response", async () => {
    const { promise, xhr } = start();
    xhr.status = 429;
    xhr.responseText = failure("rate_limited");
    xhr.responseHeaders["retry-after"] = "5";
    xhr.onload?.();
    expect(await promise).toMatchObject({ ok: false, error: { kind: "rate_limited", retryAfterSeconds: 5 } });
  });

  it("abort resolves cancelled and swallows any later load, error or progress", async () => {
    const onProgress = vi.fn();
    const onUploaded = vi.fn();
    const { promise, abort, xhr } = start({ onProgress, onUploaded });
    abort();
    expect(xhr.abortCalls).toBe(1);
    expect(await promise).toEqual({ ok: false, cancelled: true });

    // Late events after the abort must not surface as success/error or progress.
    xhr.status = 200;
    xhr.responseText = successBody;
    xhr.onload?.();
    xhr.onerror?.();
    xhr.ontimeout?.();
    xhr.upload.onprogress?.({ loaded: 9, total: 9, lengthComputable: true });
    xhr.upload.onload?.();
    expect(await promise).toEqual({ ok: false, cancelled: true });
    expect(onProgress).not.toHaveBeenCalled();
    expect(onUploaded).not.toHaveBeenCalled();

    // Aborting twice is a no-op.
    abort();
    expect(xhr.abortCalls).toBe(1);
  });

  it("a load that completed before abort still wins", async () => {
    const { promise, abort, xhr } = start();
    xhr.status = 200;
    xhr.responseText = successBody;
    xhr.onload?.();
    abort();
    expect(await promise).toMatchObject({ ok: true });
  });
});
