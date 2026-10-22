import { useState, type DragEvent, type RefObject } from "react";
import { Upload } from "lucide-react";
import { primaryButton } from "./styles";

type DropZoneProps = {
  inputRef: RefObject<HTMLInputElement | null>;
  disabled: boolean;
  onFile: (file: File) => void;
};

export function DropZone({ inputRef, disabled, onFile }: DropZoneProps) {
  const [dragging, setDragging] = useState(false);

  const onDragOver = (e: DragEvent) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = disabled ? "none" : "copy";
    if (!disabled) setDragging(true);
  };
  const onDrop = (e: DragEvent) => {
    e.preventDefault();
    setDragging(false);
    const file = e.dataTransfer.files[0];
    if (!disabled && file) onFile(file);
  };

  return (
    <div
      onDragOver={onDragOver}
      onDragLeave={() => setDragging(false)}
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
        accept=".tif,.tiff,image/tiff"
        aria-label="TIFF file"
        tabIndex={-1}
        className="sr-only"
        disabled={disabled}
        onChange={(e) => {
          const file = e.target.files?.[0];
          e.target.value = "";
          if (file) onFile(file);
        }}
      />
    </div>
  );
}
