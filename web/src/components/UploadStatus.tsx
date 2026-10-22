import { AlertCircle, LoaderCircle } from "lucide-react";
import { useEffect, useState } from "react";
import type { ErrorKind } from "../api/client";
import { isRetryable, type InspectionState } from "../state/inspection";
import { formatBytes } from "../lib/format";
import { primaryButton, secondaryButton } from "./styles";

const ERROR_TITLES: Record<ErrorKind, string> = {
  invalid_file: "That doesn't look like a TIFF file",
  unsupported_feature: "This TIFF uses something we can't read yet",
  limit_exceeded: "This file is bigger than we can inspect right now",
  malformed: "This file looks damaged or cut short",
  oversized: "This file is too large to upload",
  rate_limited: "Let's take a short breather",
  network: "We couldn't reach the server",
  server: "Something went wrong on our side",
};

type UploadStatusProps = {
  state: InspectionState;
  /** Short note about the last drop (e.g. extra files ignored); read out with the phase. */
  note?: string | null;
  onRetry: () => void;
  onCancel: () => void;
  onChooseAnother: () => void;
};

/** Live status for the in-flight and failed phases of an inspection. */
export function UploadStatus({
  state,
  note,
  onRetry,
  onCancel,
  onChooseAnother,
}: UploadStatusProps) {
  return (
    <>
      {/* Always mounted so screen readers announce phase changes. */}
      <div role="status" aria-live="polite" className="space-y-2">
        {note && (
          <p className="text-sm text-stone-600 dark:text-stone-400">{note}</p>
        )}
        {state.phase === "validating" && (
          <Busy text={`Taking a quick look at “${state.file.name}”…`} />
        )}
        {state.phase === "uploading" && (
          <Busy text={`Uploading “${state.file.name}”…`} />
        )}
        {state.phase === "parsing" && (
          <Busy
            text={`Reading the structure of “${state.file.name}”… this usually takes a moment.`}
          />
        )}
      </div>
      {/* Progress numbers stay outside the live region to avoid flooding announcements. */}
      {state.phase === "uploading" && (
        <Progress
          loaded={state.loaded}
          total={state.total}
          onCancel={onCancel}
        />
      )}
      {state.phase === "parsing" && <CancelButton onCancel={onCancel} />}
      {state.phase === "error" && (
        <ErrorPanel
          state={state}
          onRetry={onRetry}
          onChooseAnother={onChooseAnother}
        />
      )}
    </>
  );
}

function Busy({ text }: { text: string }) {
  return (
    <p className="flex items-center gap-2 text-sm">
      <LoaderCircle
        aria-hidden
        className="size-4 animate-spin motion-reduce:animate-none"
      />
      {text}
    </p>
  );
}

function CancelButton({ onCancel }: { onCancel: () => void }) {
  return (
    <button type="button" className={secondaryButton} onClick={onCancel}>
      Cancel
    </button>
  );
}

const progressBar =
  "h-2 w-full overflow-hidden rounded-full [&::-moz-progress-bar]:bg-stone-900 [&::-webkit-progress-bar]:bg-stone-200 [&::-webkit-progress-value]:bg-stone-900 dark:[&::-moz-progress-bar]:bg-stone-100 dark:[&::-webkit-progress-bar]:bg-stone-800 dark:[&::-webkit-progress-value]:bg-stone-100";

/** `total` of 0 means the browser could not compute the request length: show an indeterminate bar. */
function Progress({
  loaded,
  total,
  onCancel,
}: {
  loaded: number;
  total: number;
  onCancel: () => void;
}) {
  const known = total > 0;
  const pct = known
    ? Math.min(100, Math.round((loaded / total) * 100))
    : undefined;
  return (
    <div className="space-y-2">
      <p className="font-mono text-xs text-stone-600 dark:text-stone-400">
        {known
          ? `${pct}% · ${formatBytes(loaded)} of ${formatBytes(total)}`
          : `${formatBytes(loaded)} sent`}
      </p>
      <div className="flex items-center gap-3">
        {known ? (
          <progress
            aria-label="Upload progress"
            value={pct}
            max={100}
            className={progressBar}
          />
        ) : (
          <progress aria-label="Upload progress" className={progressBar} />
        )}
        <CancelButton onCancel={onCancel} />
      </div>
    </div>
  );
}

/** Counts down whole seconds from `seconds` to 0, once per mount. */
function useCountdown(seconds: number): number {
  const [remaining, setRemaining] = useState(Math.max(0, Math.ceil(seconds)));
  useEffect(() => {
    if (remaining <= 0) return;
    const id = setTimeout(() => setRemaining((r) => Math.max(0, r - 1)), 1000);
    return () => clearTimeout(id);
  }, [remaining]);
  return remaining;
}

type ErrorState = Extract<InspectionState, { phase: "error" }>;

function ErrorPanel({
  state,
  onRetry,
  onChooseAnother,
}: { state: ErrorState } & Pick<
  UploadStatusProps,
  "onRetry" | "onChooseAnother"
>) {
  const canRetry = state.file !== null && isRetryable(state.kind);
  // The panel remounts for every new error (errors are always separated by a
  // busy phase), so the countdown starts fresh each time.
  const waitSeconds = useCountdown(state.retryAfterSeconds ?? 0);
  return (
    <div
      role="alert"
      className="rounded-xl border border-red-200 bg-red-50 p-4 text-red-900 dark:border-red-900 dark:bg-red-950 dark:text-red-100"
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
              <button
                type="button"
                className={primaryButton}
                disabled={waitSeconds > 0}
                onClick={onRetry}
              >
                {waitSeconds > 0 ? `Retry in ${waitSeconds} s` : "Retry"}
              </button>
            )}
            <button
              type="button"
              className={secondaryButton}
              onClick={onChooseAnother}
            >
              Choose another file
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
