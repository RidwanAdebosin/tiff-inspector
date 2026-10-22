import { AlertCircle, LoaderCircle } from "lucide-react";
import type { ErrorKind } from "../api/client";
import { isRetryable, type InspectionState } from "../state/inspection";
import { formatBytes } from "../lib/format";
import { primaryButton, secondaryButton } from "./styles";

const ERROR_TITLES: Record<ErrorKind, string> = {
  invalid_file: "Not a valid TIFF file",
  unsupported_feature: "Unsupported TIFF feature",
  malformed: "Malformed or truncated TIFF",
  oversized: "File too large",
  rate_limited: "Too many requests",
  network: "Network error",
  server: "Server error",
};

type UploadStatusProps = {
  state: InspectionState;
  onRetry: () => void;
  onChooseAnother: () => void;
};

/** Live status for the in-flight and failed phases of an inspection. */
export function UploadStatus({ state, onRetry, onChooseAnother }: UploadStatusProps) {
  return (
    <>
      {/* Always mounted so screen readers announce phase changes. */}
      <div role="status" aria-live="polite">
        {state.phase === "validating" && <Busy text={`Checking “${state.file.name}”…`} />}
        {state.phase === "uploading" && <Busy text={`Uploading “${state.file.name}”…`} />}
        {state.phase === "parsing" && (
          <Busy text={`Parsing “${state.file.name}”… the server is reading the TIFF structure.`} />
        )}
      </div>
      {/* Progress numbers stay outside the live region to avoid flooding announcements. */}
      {state.phase === "uploading" && <Progress loaded={state.loaded} total={state.total} />}
      {state.phase === "error" && <ErrorPanel state={state} onRetry={onRetry} onChooseAnother={onChooseAnother} />}
    </>
  );
}

function Busy({ text }: { text: string }) {
  return (
    <p className="flex items-center gap-2 text-sm">
      <LoaderCircle aria-hidden className="size-4 animate-spin motion-reduce:animate-none" />
      {text}
    </p>
  );
}

function Progress({ loaded, total }: { loaded: number; total: number }) {
  const pct = total > 0 ? Math.min(100, Math.round((loaded / total) * 100)) : 0;
  return (
    <div className="space-y-2">
      <p className="font-mono text-xs text-zinc-600 dark:text-zinc-400">
        {pct}% · {formatBytes(loaded)} of {formatBytes(total)}
      </p>
      <progress
        aria-label="Upload progress"
        value={pct}
        max={100}
        className="h-2 w-full overflow-hidden rounded-full [&::-moz-progress-bar]:bg-zinc-900 [&::-webkit-progress-bar]:bg-zinc-200 [&::-webkit-progress-value]:bg-zinc-900 dark:[&::-moz-progress-bar]:bg-zinc-100 dark:[&::-webkit-progress-bar]:bg-zinc-800 dark:[&::-webkit-progress-value]:bg-zinc-100"
      />
    </div>
  );
}

type ErrorState = Extract<InspectionState, { phase: "error" }>;

function ErrorPanel({ state, onRetry, onChooseAnother }: { state: ErrorState } & Omit<UploadStatusProps, "state">) {
  const canRetry = state.file !== null && isRetryable(state.kind);
  return (
    <div
      role="alert"
      className="rounded-lg border border-red-200 bg-red-50 p-4 text-red-900 dark:border-red-900 dark:bg-red-950 dark:text-red-100"
    >
      <div className="flex gap-3">
        <AlertCircle aria-hidden className="mt-0.5 size-5 shrink-0" />
        <div className="min-w-0 space-y-2">
          <p className="font-semibold">{ERROR_TITLES[state.kind]}</p>
          <p className="text-sm break-words">{state.message}</p>
          {(state.code || state.status) && (
            <p className="font-mono text-xs">
              {state.code && <>code: {state.code}</>}
              {state.code && state.status ? " · " : ""}
              {state.status ? <>HTTP {state.status}</> : null}
            </p>
          )}
          <div className="flex flex-wrap gap-2 pt-1">
            {canRetry && (
              <button type="button" className={primaryButton} onClick={onRetry}>
                Retry
              </button>
            )}
            <button type="button" className={secondaryButton} onClick={onChooseAnother}>
              Choose another file
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
