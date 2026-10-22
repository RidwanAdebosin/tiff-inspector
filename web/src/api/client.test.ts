import { describe, expect, it, vi } from "vitest";
import { successBody } from "../test/fixtures/successReport";
import { interpretResponse, uploadInspection } from "./client";
import type { ErrorCode } from "./types";

const failure = (code: ErrorCode, message = `server says ${code}`) =>
  JSON.stringify({
    schema_version: "1.0",
    ok: false,
    tool: { name: "tiff-inspector", version: "0.1.0" },
    file: { name: "a.tif", size_bytes: 10 },
    error: { code, message },
  });

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
    [422, "limit_exceeded", "unsupported_feature"],
    [429, "rate_limited", "rate_limited"],
    [500, "internal", "server"],
  ])("HTTP %i with code %s → %s, keeping the server message", (status, code, kind) => {
    const r = interpretResponse(status, failure(code));
    expect(r).toEqual({ ok: false, error: { kind, code, status, message: `server says ${code}` } });
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
    const r = interpretResponse(status, "<html>Bad Gateway</html>");
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.error.kind).toBe(kind);
      expect(r.error.code).toBeUndefined();
      expect(r.error.message.length).toBeGreaterThan(0);
    }
  });

  it("status 0 (connection failed) is a network error", () => {
    const r = interpretResponse(0, "");
    expect(!r.ok && r.error.kind).toBe("network");
  });

  it("200 with an unexpected body is a server error", () => {
    expect(interpretResponse(200, "not json")).toMatchObject({ ok: false, error: { kind: "server" } });
    expect(interpretResponse(200, failure("internal"))).toMatchObject({ ok: false, error: { kind: "server" } });
    expect(interpretResponse(200, JSON.stringify({ ok: true }))).toMatchObject({ ok: false, error: { kind: "server" } });
  });

  it("falls back to status when a FailureReport has an unknown code", () => {
    const body = failure("internal").replace('"internal"', '"brand_new_code"');
    const r = interpretResponse(422, body);
    expect(!r.ok && r.error.kind).toBe("malformed");
  });
});

describe("uploadInspection", () => {
  class FakeXHR {
    static last: FakeXHR;
    method = "";
    url = "";
    body: FormData | null = null;
    headers: Record<string, string> = {};
    status = 0;
    responseText = "";
    responseType = "";
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
    send(body: FormData) {
      this.body = body;
    }
    abort() {
      this.onabort?.();
    }
  }

  it("posts multipart field `file` and reports progress, upload completion and the response", async () => {
    vi.stubGlobal("XMLHttpRequest", FakeXHR);
    const onProgress = vi.fn();
    const onUploaded = vi.fn();
    const file = new File(["II*\0"], "a.tif");
    const { promise } = uploadInspection(file, { onProgress, onUploaded });
    const xhr = FakeXHR.last;

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
    vi.unstubAllGlobals();
  });

  it("maps transport errors to network errors", async () => {
    vi.stubGlobal("XMLHttpRequest", FakeXHR);
    const { promise } = uploadInspection(new File(["x"], "a.tif"));
    FakeXHR.last.onerror?.();
    expect(await promise).toMatchObject({ ok: false, error: { kind: "network" } });
    vi.unstubAllGlobals();
  });
});
