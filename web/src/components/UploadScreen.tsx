import { FolderTree, Layers, Lock, MessageCircleWarning } from "lucide-react";
import { useRef, useState, type ReactNode } from "react";
import { ACCEPTED_EXTENSIONS, MAX_UPLOAD_BYTES } from "../lib/constants";
import { formatBytes } from "../lib/format";
import type { InspectionState } from "../state/inspection";
import { DropZone } from "./DropZone";
import { card, muted } from "./styles";
import { UploadStatus } from "./UploadStatus";

type UploadScreenProps = {
  state: InspectionState;
  busy: boolean;
  onFile: (file: File) => void;
  onRetry: () => void;
  onCancel: () => void;
};

function Promise_({
  icon,
  title,
  children,
}: {
  icon: ReactNode;
  title: string;
  children: ReactNode;
}) {
  return (
    <li className={`${card} flex gap-3 p-4`}>
      <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300">
        {icon}
      </span>
      <div className="min-w-0">
        <p className="font-medium">{title}</p>
        <p className={`mt-0.5 text-sm ${muted}`}>{children}</p>
      </div>
    </li>
  );
}

export function UploadScreen({
  state,
  busy,
  onFile,
  onRetry,
  onCancel,
}: UploadScreenProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [dropNote, setDropNote] = useState<string | null>(null);

  return (
    <div className="mx-auto max-w-2xl space-y-8">
      <div className="space-y-3">
        <p className="text-sm font-medium text-amber-800 dark:text-amber-300">
          Welcome
        </p>
        <h1 className="text-3xl font-semibold tracking-tight sm:text-4xl">
          Let's look inside your TIFF.
        </h1>
        <p className="text-lg text-stone-700 dark:text-stone-300">
          Drop in a file and you'll get a clear picture of what's in it: its
          directories, tags, how the pixels are stored, and anything that looks
          off. No account, no setup.
        </p>
      </div>

      <DropZone
        inputRef={inputRef}
        disabled={busy}
        onFile={onFile}
        onNote={setDropNote}
      />

      <UploadStatus
        state={state}
        note={dropNote}
        onRetry={onRetry}
        onCancel={onCancel}
        onChooseAnother={() => inputRef.current?.click()}
      />

      <ul className="grid gap-3 sm:grid-cols-2" aria-label="What you'll see">
        <Promise_
          icon={<FolderTree aria-hidden className="size-4" />}
          title="Every directory and tag"
        >
          Each image directory, with its tags decoded and named, so nothing
          stays a mystery number.
        </Promise_>
        <Promise_
          icon={<Layers aria-hidden className="size-4" />}
          title="How the pixels are stored"
        >
          Strips or tiles, samples, bit depths and byte counts, cross-checked
          against the file size.
        </Promise_>
        <Promise_
          icon={<MessageCircleWarning aria-hidden className="size-4" />}
          title="Problems, explained"
        >
          Truncated data, odd values and unsupported features are called out in
          plain words, not just codes.
        </Promise_>
        <Promise_
          icon={<Lock aria-hidden className="size-4" />}
          title="Your file stays yours"
        >
          It's only used to build the report, then deleted straight away. We
          never keep a copy.
        </Promise_>
      </ul>

      <dl className="grid gap-3 text-sm sm:grid-cols-2">
        <div>
          <dt className="font-medium">Supported formats</dt>
          <dd className={muted}>
            Classic TIFF and BigTIFF, either byte order (
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
          <dd className={muted}>
            {formatBytes(MAX_UPLOAD_BYTES)} here. The command-line tool has no
            limit.
          </dd>
        </div>
      </dl>

      <p className={`text-sm ${muted}`}>
        Curious how the parser works? Try it yourself in the{" "}
        <a
          href="/playground"
          className="font-medium text-blue-700 underline-offset-2 hover:underline dark:text-blue-300"
        >
          OCaml playground
        </a>
        .
      </p>
    </div>
  );
}
