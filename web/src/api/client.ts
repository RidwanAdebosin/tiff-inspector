import { INSPECTIONS_ENDPOINT, UPLOAD_TIMEOUT_MS } from "../lib/constants";
import type { ErrorCode, FailureReport, SuccessReport } from "./types";

/** UI-level error categories; each maps to a distinct message and set of actions. */
export type ErrorKind =
  | "invalid_file"
  | "unsupported_feature"
  | "limit_exceeded"
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
  /** Seconds to wait before retrying, from a `Retry-After` header (429). */
  retryAfterSeconds?: number;
};

export type InspectionResult =
  | { ok: true; report: SuccessReport; rawBody: string }
  | { ok: false; cancelled: true }
  | { ok: false; cancelled?: false; error: InspectionError };

const CODE_TO_KIND: Record<ErrorCode, ErrorKind> = {
  not_a_tiff: "invalid_file",
  invalid_request: "invalid_file",
  file_too_large: "oversized",
  unsupported_feature: "unsupported_feature",
  limit_exceeded: "limit_exceeded",
  truncated: "malformed",
  malformed: "malformed",
  file_unreadable: "malformed",
  pixel_decode_failed: "malformed",
  rate_limited: "rate_limited",
  internal: "server",
  file_not_found: "server",
};

const DEFAULT_MESSAGES: Record<ErrorKind, string> = {
  invalid_file:
    "We couldn't find a TIFF structure in it. If it was renamed from another format, try the original.",
  unsupported_feature:
    "It uses a TIFF feature this version can't inspect yet, so the report would be incomplete.",
  limit_exceeded:
    "It needs more memory or time than this free service allows. A smaller file will work, and the command-line tool has no limit.",
  malformed:
    "It's cut off or its structure is broken, so we couldn't read it all the way through. If you have another copy, try that one.",
  oversized:
    "Uploads here are limited to 25 MB. The command-line tool handles files of any size.",
  rate_limited:
    "You've sent a lot of files in a short time. Give it a moment and try again.",
  network: "Check your connection and try again. Your file is still selected.",
  server: "That's on us, not your file. Please try again in a moment.",
};

export function defaultMessage(kind: ErrorKind): string {
  return DEFAULT_MESSAGES[kind];
}

/**
 * Parse a `Retry-After` header value: delay-seconds, or an HTTP-date, into
 * whole seconds from now (never negative). Unparseable values give undefined.
 */
export function parseRetryAfter(
  value: string | null | undefined,
  now = Date.now(),
): number | undefined {
  if (value === null || value === undefined) return undefined;
  const text = value.trim();
  if (/^\d+$/.test(text)) return Number(text);
  // HTTP-dates start with a weekday name; anything else (e.g. "-5") is not a date.
  if (!/^[A-Za-z]/.test(text)) return undefined;
  const date = Date.parse(text);
  if (Number.isNaN(date)) return undefined;
  return Math.max(0, Math.ceil((date - now) / 1000));
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
  if (!isJson && (status === 502 || status === 503 || status === 504))
    return "network";
  if (status === 415 || status === 400) return "invalid_file";
  if (status === 422) return "malformed";
  return "server";
}

/**
 * Map an HTTP response (status + raw body text + optional `Retry-After`
 * header) to a result. Pure, so it can be unit-tested without XHR. Non-JSON
 * bodies (e.g. proxy error pages) are classified by status alone.
 */
export function interpretResponse(
  status: number,
  body: string,
  retryAfter?: string | null,
): InspectionResult {
  const json = parseJson(body);

  if (status >= 200 && status < 300) {
    if (isSuccessReport(json)) return { ok: true, report: json, rawBody: body };
    return {
      ok: false,
      error: {
        kind: "server",
        status,
        message:
          "The server returned a response this page does not understand.",
      },
    };
  }

  const error = isFailureReport(json)
    ? errorFromReport(json, status)
    : errorFromStatus(status, json !== undefined);
  const retryAfterSeconds = parseRetryAfter(retryAfter);
  if (retryAfterSeconds !== undefined)
    error.retryAfterSeconds = retryAfterSeconds;
  return { ok: false, error };
}

function errorFromReport(
  report: FailureReport,
  status: number,
): InspectionError {
  const code = report.error.code;
  const kind = CODE_TO_KIND[code] ?? kindFromStatus(status, true);
  return {
    kind,
    code,
    status,
    message: report.error.message || defaultMessage(kind),
  };
}

function errorFromStatus(status: number, isJson: boolean): InspectionError {
  const kind = kindFromStatus(status, isJson);
  return { kind, status, message: defaultMessage(kind) };
}

export type UploadCallbacks = {
  /** Upload progress in bytes; `total` may be 0 if not computable. */
  onProgress?: (loaded: number, total: number) => void;
  /** All request bytes have been sent; the server is now parsing. */
  onUploaded?: () => void;
};

export type UploadHandle = {
  promise: Promise<InspectionResult>;
  /** Cancel the request. The promise resolves `{ ok: false, cancelled: true }` and nothing else fires. */
  abort: () => void;
};

/**
 * POST the file as multipart/form-data (single field `file`). Uses XHR rather
 * than fetch so upload progress can be reported.
 */
export function uploadInspection(
  file: File,
  callbacks: UploadCallbacks = {},
): UploadHandle {
  const xhr = new XMLHttpRequest();
  let aborted = false;
  const promise = new Promise<InspectionResult>((resolve) => {
    xhr.open("POST", INSPECTIONS_ENDPOINT);
    xhr.responseType = "text";
    xhr.timeout = UPLOAD_TIMEOUT_MS;
    xhr.setRequestHeader("Accept", "application/json");

    // Once aborted, no late success/error may surface; only the cancelled result does.
    const settle = (result: () => InspectionResult) => {
      if (!aborted) resolve(result());
    };

    xhr.upload.onprogress = (e) => {
      if (!aborted)
        callbacks.onProgress?.(e.loaded, e.lengthComputable ? e.total : 0);
    };
    xhr.upload.onload = () => {
      if (!aborted) callbacks.onUploaded?.();
    };

    xhr.onload = () =>
      settle(() =>
        interpretResponse(
          xhr.status,
          xhr.responseText,
          xhr.getResponseHeader("retry-after"),
        ),
      );
    xhr.onerror = () => settle(() => interpretResponse(0, ""));
    xhr.ontimeout = () => settle(() => interpretResponse(0, ""));
    xhr.onabort = () => resolve({ ok: false, cancelled: true });

    const form = new FormData();
    form.append("file", file, file.name);
    xhr.send(form);
  });
  const abort = () => {
    if (aborted) return;
    aborted = true;
    xhr.abort();
  };
  return { promise, abort };
}
