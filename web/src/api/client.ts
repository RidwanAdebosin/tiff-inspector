import { INSPECTIONS_ENDPOINT } from "../lib/constants";
import type { ErrorCode, FailureReport, SuccessReport } from "./types";

/** UI-level error categories; each maps to a distinct message and set of actions. */
export type ErrorKind =
  | "invalid_file"
  | "unsupported_feature"
  | "malformed"
  | "oversized"
  | "rate_limited"
  | "network"
  | "server";

export type InspectionError = {
  kind: ErrorKind;
  message: string;
  /** Server error code when the response carried a FailureReport. */
  code?: ErrorCode;
  /** HTTP status, when a response was received. */
  status?: number;
};

export type InspectionResult =
  | { ok: true; report: SuccessReport; rawBody: string }
  | { ok: false; error: InspectionError };

const CODE_TO_KIND: Record<ErrorCode, ErrorKind> = {
  not_a_tiff: "invalid_file",
  invalid_request: "invalid_file",
  file_too_large: "oversized",
  unsupported_feature: "unsupported_feature",
  limit_exceeded: "unsupported_feature",
  truncated: "malformed",
  malformed: "malformed",
  file_unreadable: "malformed",
  pixel_decode_failed: "malformed",
  rate_limited: "rate_limited",
  internal: "server",
  file_not_found: "server",
};

const DEFAULT_MESSAGES: Record<ErrorKind, string> = {
  invalid_file: "The file is not a TIFF that can be inspected.",
  unsupported_feature: "The file uses a TIFF feature this version cannot inspect.",
  malformed: "The file is truncated or malformed and could not be inspected.",
  oversized: "The file is larger than the maximum upload size.",
  rate_limited: "Too many inspections in a short time. Wait a moment and try again.",
  network: "Could not reach the inspection service. Check your connection and try again.",
  server: "The inspection service failed unexpectedly. Try again later.",
};

export function defaultMessage(kind: ErrorKind): string {
  return DEFAULT_MESSAGES[kind];
}

function parseJson(text: string): unknown {
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return undefined;
  }
}

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function isFailureReport(v: unknown): v is FailureReport {
  return (
    isObject(v) &&
    v.ok === false &&
    isObject(v.error) &&
    typeof v.error.code === "string" &&
    typeof v.error.message === "string"
  );
}

function isSuccessReport(v: unknown): v is SuccessReport {
  return (
    isObject(v) &&
    v.ok === true &&
    typeof v.schema_version === "string" &&
    v.schema_version.startsWith("1.") &&
    isObject(v.file) &&
    Array.isArray(v.directories)
  );
}

function kindFromStatus(status: number, isJson: boolean): ErrorKind {
  if (status === 0) return "network";
  if (status === 413) return "oversized";
  if (status === 429) return "rate_limited";
  if (!isJson && (status === 502 || status === 503 || status === 504)) return "network";
  if (status === 415 || status === 400) return "invalid_file";
  if (status === 422) return "malformed";
  return "server";
}

/**
 * Map an HTTP response (status + raw body text) to a result. Pure, so it can
 * be unit-tested without XHR. Non-JSON bodies (e.g. proxy error pages) are
 * classified by status alone.
 */
export function interpretResponse(status: number, body: string): InspectionResult {
  const json = parseJson(body);

  if (status >= 200 && status < 300) {
    if (isSuccessReport(json)) return { ok: true, report: json, rawBody: body };
    return {
      ok: false,
      error: { kind: "server", status, message: "The server returned a response this page does not understand." },
    };
  }

  if (isFailureReport(json)) {
    const code = json.error.code;
    const kind = CODE_TO_KIND[code] ?? kindFromStatus(status, true);
    return { ok: false, error: { kind, code, status, message: json.error.message || defaultMessage(kind) } };
  }

  const kind = kindFromStatus(status, json !== undefined);
  return { ok: false, error: { kind, status, message: defaultMessage(kind) } };
}

export type UploadCallbacks = {
  /** Upload progress in bytes; `total` may be 0 if not computable. */
  onProgress?: (loaded: number, total: number) => void;
  /** All request bytes have been sent; the server is now parsing. */
  onUploaded?: () => void;
};

export type UploadHandle = {
  promise: Promise<InspectionResult>;
  abort: () => void;
};

/**
 * POST the file as multipart/form-data (single field `file`). Uses XHR rather
 * than fetch so upload progress can be reported.
 */
export function uploadInspection(file: File, callbacks: UploadCallbacks = {}): UploadHandle {
  const xhr = new XMLHttpRequest();
  const promise = new Promise<InspectionResult>((resolve) => {
    xhr.open("POST", INSPECTIONS_ENDPOINT);
    xhr.responseType = "text";
    xhr.setRequestHeader("Accept", "application/json");

    xhr.upload.onprogress = (e) => callbacks.onProgress?.(e.loaded, e.lengthComputable ? e.total : 0);
    xhr.upload.onload = () => callbacks.onUploaded?.();

    xhr.onload = () => resolve(interpretResponse(xhr.status, xhr.responseText));
    xhr.onerror = () => resolve(interpretResponse(0, ""));
    xhr.ontimeout = () => resolve(interpretResponse(0, ""));
    xhr.onabort = () =>
      resolve({ ok: false, error: { kind: "network", message: "The upload was cancelled." } });

    const form = new FormData();
    form.append("file", file, file.name);
    xhr.send(form);
  });
  return { promise, abort: () => xhr.abort() };
}
