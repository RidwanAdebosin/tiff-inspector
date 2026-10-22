import type { Directory } from "../api/types";
import { formatHex, formatInteger } from "../lib/format";
import { ImageProperties } from "./ImageProperties";
import { PixelDecodingInfo } from "./PixelDecodingInfo";
import { ProblemList } from "./ProblemList";
import { SamplesPlanes } from "./SamplesPlanes";
import { Section } from "./Section";
import { StorageLayout } from "./StorageLayout";
import { TagTable } from "./TagTable";

export function DirectoryPanel({ dir }: { dir: Directory }) {
  return (
    <div className="space-y-4">
      <p className="text-sm text-stone-600 dark:text-stone-400">
        IFD {dir.index} at offset{" "}
        <span className="font-mono">
          {formatInteger(dir.offset)} ({formatHex(dir.offset)})
        </span>{" "}
        · {formatInteger(dir.entry_count)} entries
      </p>
      {dir.warnings.length > 0 && (
        <Section title="Directory warnings">
          <ProblemList problems={dir.warnings} />
        </Section>
      )}
      <div className="grid gap-4 lg:grid-cols-2">
        <ImageProperties dir={dir} />
        <div className="space-y-4">
          <StorageLayout layout={dir.layout} />
          <SamplesPlanes dir={dir} />
          <PixelDecodingInfo decoding={dir.pixel_decoding} />
        </div>
      </div>
      <TagTable key={dir.index} tags={dir.tags} directoryIndex={dir.index} />
    </div>
  );
}
