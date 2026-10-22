import { useRef, useState } from "react";
import { ACCEPTED_EXTENSIONS, MAX_UPLOAD_BYTES } from "../lib/constants";
import { formatBytes } from "../lib/format";
import type { InspectionState } from "../state/inspection";
import { DropZone } from "./DropZone";
import { mono, muted } from "./styles";
import { UploadStatus } from "./UploadStatus";

type UploadScreenProps = {
  state: InspectionState;
  busy: boolean;
  onFile: (file: File) => void;
  onRetry: () => void;
  onCancel: () => void;
};

/** Bundled fixtures (served with the playground) for a one-click first report. */
const TRY_SAMPLES: { name: string; label: string }[] = [
  { name: "gray8.tif", label: "a small grayscale image" },
  { name: "rgb_contig.tif", label: "RGB in two strips" },
  { name: "multi_ifd.tif", label: "three directories" },
  { name: "bad_magic.tif", label: "a broken file" },
];

const BASE = import.meta.env.BASE_URL;

export function UploadScreen({
  state,
  busy,
  onFile,
  onRetry,
  onCancel,
}: UploadScreenProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [dropNote, setDropNote] = useState<string | null>(null);
  const [fetching, setFetching] = useState<string | null>(null);

  const trySample = async (name: string) => {
    setFetching(name);
    setDropNote(`Fetching ${name}…`);
    try {
      const res = await fetch(`${BASE}playground/samples/${name}`);
      if (!res.ok) throw new Error(String(res.status));
      const bytes = await res.arrayBuffer();
      setDropNote(null);
      onFile(new File([bytes], name, { type: "image/tiff" }));
    } catch {
      setDropNote(
        `Couldn't fetch ${name}. Check your connection and try again.`,
      );
    } finally {
      setFetching(null);
    }
  };

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div className="space-y-2">
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">
          See what's inside a TIFF
        </h1>
        <p className="text-stone-700 dark:text-stone-300">
          Drop in a file to get its directories, tags and storage layout, with
          anything odd pointed out. Metadata only: pixels are never decoded, and
          the file is deleted as soon as the report is built.
        </p>
      </div>

      <DropZone
        inputRef={inputRef}
        disabled={busy}
        onFile={onFile}
        onNote={setDropNote}
      />

      <p className="text-sm">
        <span className={muted}>No TIFF to hand? Try one of ours: </span>
        {TRY_SAMPLES.map((s, i) => (
          <span key={s.name}>
            {i > 0 && <span className={muted}>, </span>}
            <button
              type="button"
              disabled={busy || fetching !== null}
              onClick={() => void trySample(s.name)}
              className="font-medium text-blue-700 underline-offset-2 hover:underline disabled:cursor-not-allowed disabled:opacity-60 dark:text-blue-300"
            >
              {s.label}
            </button>
          </span>
        ))}
        <span className={muted}>.</span>
      </p>

      <UploadStatus
        state={state}
        note={dropNote}
        onRetry={onRetry}
        onCancel={onCancel}
        onChooseAnother={() => inputRef.current?.click()}
      />

      <dl className="grid gap-x-6 gap-y-2 text-sm sm:grid-cols-[auto_1fr]">
        <dt className="font-medium">Supported formats</dt>
        <dd className={muted}>
          Classic TIFF and BigTIFF, either byte order (
          {ACCEPTED_EXTENSIONS.map((ext, i) => (
            <span key={ext}>
              {i > 0 && ", "}
              <span className={mono}>{ext}</span>
            </span>
          ))}
          )
        </dd>
        <dt className="font-medium">Maximum file size</dt>
        <dd className={muted}>
          {formatBytes(MAX_UPLOAD_BYTES)} here. The command-line tool has no
          limit.
        </dd>
        <dt className="font-medium">Curious how it works?</dt>
        <dd className={muted}>
          The parser is OCaml. You can run it yourself in the{" "}
          <a
            href="/playground"
            className="font-medium text-blue-700 underline-offset-2 hover:underline dark:text-blue-300"
          >
            playground
          </a>
          .
        </dd>
      </dl>
    </div>
  );
}
