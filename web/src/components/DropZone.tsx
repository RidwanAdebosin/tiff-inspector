import { useRef, useState, type DragEvent, type RefObject } from "react";
import { Upload } from "lucide-react";
import { ACCEPTED_EXTENSIONS } from "../lib/constants";
import { primaryButton } from "./styles";

const DROP_NOTES = {
  extraFilesIgnored: "Only the first file was inspected",
  noFile: "Drop a .tif or .tiff file",
} as const;

type DropZoneProps = {
  inputRef: RefObject<HTMLInputElement | null>;
  disabled: boolean;
  onFile: (file: File) => void;
  /** Feedback about the last drop/selection (null clears a previous note). */
  onNote?: (note: string | null) => void;
};

const INPUT_ACCEPT = [...ACCEPTED_EXTENSIONS, "image/tiff"].join(",");

export function DropZone({ inputRef, disabled, onFile, onNote }: DropZoneProps) {
  const [dragging, setDragging] = useState(false);
  // dragenter/dragleave fire for every child element crossed; the highlight
  // only ends when the nesting depth returns to zero.
  const depthRef = useRef(0);

  const endDrag = () => {
    depthRef.current = 0;
    setDragging(false);
  };
  const onDragEnter = (e: DragEvent) => {
    e.preventDefault();
    depthRef.current += 1;
    if (!disabled) setDragging(true);
  };
  const onDragLeave = () => {
    depthRef.current = Math.max(0, depthRef.current - 1);
    if (depthRef.current === 0) setDragging(false);
  };
  const onDragOver = (e: DragEvent) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = disabled ? "none" : "copy";
  };
  const onDrop = (e: DragEvent) => {
    e.preventDefault();
    endDrag();
    if (disabled) return;
    const files = e.dataTransfer.files;
    const file = files[0];
    if (!file) {
      onNote?.(DROP_NOTES.noFile);
      return;
    }
    onNote?.(files.length > 1 ? DROP_NOTES.extraFilesIgnored : null);
    onFile(file);
  };

  return (
    <div
      onDragEnter={onDragEnter}
      onDragLeave={onDragLeave}
      onDragOver={onDragOver}
      onDragEnd={endDrag}
      onDrop={onDrop}
      data-dragging={dragging || undefined}
      className="flex flex-col items-center gap-3 rounded-lg border-2 border-dashed border-zinc-300 bg-white px-4 py-10 text-center transition-colors data-dragging:border-blue-600 data-dragging:bg-blue-50 dark:border-zinc-700 dark:bg-zinc-900 dark:data-dragging:border-blue-400 dark:data-dragging:bg-blue-950"
    >
      <Upload aria-hidden className="size-6 text-zinc-500 dark:text-zinc-400" />
      <button type="button" className={primaryButton} disabled={disabled} onClick={() => inputRef.current?.click()}>
        Choose a TIFF file
      </button>
      <p className="text-sm text-zinc-600 dark:text-zinc-400">or drag and drop it here</p>
      <input
        ref={inputRef}
        type="file"
        accept={INPUT_ACCEPT}
        aria-label="TIFF file"
        tabIndex={-1}
        className="sr-only"
        disabled={disabled}
        onChange={(e) => {
          const file = e.target.files?.[0];
          e.target.value = "";
          if (file) {
            onNote?.(null);
            onFile(file);
          }
        }}
      />
    </div>
  );
}
