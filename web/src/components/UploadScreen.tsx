import { useRef, useState } from "react";
import { ACCEPTED_EXTENSIONS, MAX_UPLOAD_BYTES } from "../lib/constants";
import { formatBytes } from "../lib/format";
import type { InspectionState } from "../state/inspection";
import { DropZone } from "./DropZone";
import { UploadStatus } from "./UploadStatus";

type UploadScreenProps = {
  state: InspectionState;
  busy: boolean;
  onFile: (file: File) => void;
  onRetry: () => void;
  onCancel: () => void;
};

export function UploadScreen({ state, busy, onFile, onRetry, onCancel }: UploadScreenProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [dropNote, setDropNote] = useState<string | null>(null);

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div className="space-y-2">
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">TIFF Inspector</h1>
        <p className="text-zinc-700 dark:text-zinc-300">
          Inspect the structure of a TIFF file: image file directories, tags, storage layout, samples and planes.
          Metadata only — pixels are not decoded.
        </p>
      </div>

      <DropZone inputRef={inputRef} disabled={busy} onFile={onFile} onNote={setDropNote} />

      <UploadStatus
        state={state}
        note={dropNote}
        onRetry={onRetry}
        onCancel={onCancel}
        onChooseAnother={() => inputRef.current?.click()}
      />

      <dl className="grid gap-3 text-sm sm:grid-cols-2">
        <div>
          <dt className="font-medium">Supported formats</dt>
          <dd className="text-zinc-600 dark:text-zinc-400">
            Classic TIFF and BigTIFF, little- or big-endian (
            {ACCEPTED_EXTENSIONS.map((ext, i) => (
              <span key={ext}>
                {i > 0 && ", "}
                <span className="font-mono">{ext}</span>
              </span>
            ))}
            )
          </dd>
        </div>
        <div>
          <dt className="font-medium">Maximum file size</dt>
          <dd className="text-zinc-600 dark:text-zinc-400">{formatBytes(MAX_UPLOAD_BYTES)}</dd>
        </div>
      </dl>

      <p className="text-sm text-zinc-600 dark:text-zinc-400">
        Files are processed temporarily and deleted after inspection; nothing is stored.
      </p>
    </div>
  );
}
