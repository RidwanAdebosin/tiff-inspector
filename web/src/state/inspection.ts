import type { ErrorKind, InspectionError } from "../api/client";
import type { ErrorCode, SuccessReport } from "../api/types";

/**
 * Inspection flow:
 *
 *   idle ─select→ validating ─valid→ uploading(progress) ─uploaded→ parsing ─┬→ success(report)
 *                     │                    │                                  └→ error(kind)
 *                     └─invalid→ error     └─response→ success | error
 *
 * From uploading/parsing: `cancel` aborts the request and returns to idle.
 * From error: `retry` (same file, when retryable) or `reset`/`select` (another file).
 * From success: `reset` to inspect another file.
 * `select` is ignored while a request is in flight, preventing duplicate submissions.
 */
export type InspectionState =
  | { phase: "idle" }
  | { phase: "validating"; file: File }
  | { phase: "uploading"; file: File; loaded: number; total: number }
  | { phase: "parsing"; file: File }
  | { phase: "success"; file: File; report: SuccessReport; rawBody: string }
  | {
      phase: "error";
      file: File | null;
      kind: ErrorKind;
      message: string;
      code?: ErrorCode;
      status?: number;
      /** When set (429 `Retry-After`), Retry is held back for this many seconds. */
      retryAfterSeconds?: number;
    };

export type InspectionAction =
  | { type: "select"; file: File }
  | { type: "validation_failed"; message: string }
  | { type: "validation_passed" }
  | { type: "upload_progress"; loaded: number; total: number }
  | { type: "uploaded" }
  | { type: "succeeded"; report: SuccessReport; rawBody: string }
  | { type: "failed"; error: InspectionError }
  | { type: "cancel" }
  | { type: "retry" }
  | { type: "reset" };

export const initialState: InspectionState = { phase: "idle" };

export function isBusy(state: InspectionState): boolean {
  return state.phase === "validating" || state.phase === "uploading" || state.phase === "parsing";
}

/** A request is on the wire (or being parsed) and can be cancelled. */
export function isCancellable(state: InspectionState): boolean {
  return state.phase === "uploading" || state.phase === "parsing";
}

/** Retrying only helps with transient failures; bad files need a different file. */
export function isRetryable(kind: ErrorKind): boolean {
  return kind === "network" || kind === "server" || kind === "rate_limited" || kind === "limit_exceeded";
}

export function inspectionReducer(state: InspectionState, action: InspectionAction): InspectionState {
  switch (action.type) {
    case "select":
      if (isBusy(state)) return state;
      return { phase: "validating", file: action.file };

    case "validation_failed":
      if (state.phase !== "validating") return state;
      return { phase: "error", file: state.file, kind: "invalid_file", message: action.message };

    case "validation_passed":
      if (state.phase !== "validating") return state;
      return { phase: "uploading", file: state.file, loaded: 0, total: state.file.size };

    case "upload_progress":
      if (state.phase !== "uploading") return state;
      return { ...state, loaded: action.loaded, total: action.total };

    case "uploaded":
      if (state.phase !== "uploading") return state;
      return { phase: "parsing", file: state.file };

    case "succeeded":
      if (state.phase !== "uploading" && state.phase !== "parsing") return state;
      return { phase: "success", file: state.file, report: action.report, rawBody: action.rawBody };

    case "failed": {
      if (state.phase !== "uploading" && state.phase !== "parsing") return state;
      const { kind, message, code, status, retryAfterSeconds } = action.error;
      return { phase: "error", file: state.file, kind, message, code, status, retryAfterSeconds };
    }

    case "cancel":
      if (!isCancellable(state)) return state;
      return initialState;

    case "retry":
      if (state.phase !== "error" || state.file === null || !isRetryable(state.kind)) return state;
      return { phase: "validating", file: state.file };

    case "reset":
      if (isBusy(state)) return state;
      return initialState;
  }
}
