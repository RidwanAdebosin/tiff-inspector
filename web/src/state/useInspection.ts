import { useCallback, useEffect, useReducer, useRef } from "react";
import { uploadInspection } from "../api/client";
import { validateFile } from "../lib/validation";
import {
  initialState,
  inspectionReducer,
  isBusy,
  isCancellable,
  isRetryable,
  type InspectionAction,
} from "./inspection";

/**
 * Drives the inspection state machine: validation, then upload, then the
 * server response. A ref guard ensures only one inspection runs at a time
 * (the reducer also ignores `select` while busy).
 */
export function useInspection() {
  const [state, dispatch] = useReducer(inspectionReducer, initialState);
  const runningRef = useRef(false);
  const mountedRef = useRef(true);
  const abortRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      abortRef.current?.();
    };
  }, []);

  const run = useCallback(async (file: File, start: InspectionAction) => {
    if (runningRef.current) return;
    runningRef.current = true;
    const send = (action: InspectionAction) => {
      if (mountedRef.current) dispatch(action);
    };
    try {
      send(start);
      const validation = await validateFile(file);
      if (!validation.ok) {
        send({ type: "validation_failed", message: validation.message });
        return;
      }
      send({ type: "validation_passed" });

      const handle = uploadInspection(file, {
        onProgress: (loaded, total) => send({ type: "upload_progress", loaded, total }),
        onUploaded: () => send({ type: "uploaded" }),
      });
      abortRef.current = handle.abort;
      const outcome = await handle.promise;
      abortRef.current = null;
      // A cancelled request has already been taken back to idle by `cancel`.
      if (outcome.ok) send({ type: "succeeded", report: outcome.report, rawBody: outcome.rawBody });
      else if (!outcome.cancelled) send({ type: "failed", error: outcome.error });
    } finally {
      runningRef.current = false;
    }
  }, []);

  const select = useCallback((file: File) => void run(file, { type: "select", file }), [run]);

  const retry = useCallback(() => {
    if (state.phase !== "error" || state.file === null || !isRetryable(state.kind)) return;
    void run(state.file, { type: "retry" });
  }, [state, run]);

  const cancel = useCallback(() => {
    if (!isCancellable(state)) return;
    abortRef.current?.();
    abortRef.current = null;
    dispatch({ type: "cancel" });
  }, [state]);

  const reset = useCallback(() => dispatch({ type: "reset" }), []);

  return { state, busy: isBusy(state), select, retry, cancel, reset };
}
