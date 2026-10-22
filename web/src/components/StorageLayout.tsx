import type { Layout } from "../api/types";
import { formatExactBytes, formatHex, formatInteger } from "../lib/format";
import { Badge } from "./Badge";
import { FieldValue } from "./FieldValue";
import { KeyValueList, type KeyValueItem } from "./KeyValueList";
import { Section } from "./Section";

const KIND_LABEL: Record<Layout["kind"], string> = { strips: "Strips", tiles: "Tiles", unknown: "Unknown" };

function ChunkCount({ layout }: { layout: Layout }) {
  const { chunk_count: listed, expected_chunk_count: expected } = layout;
  return (
    <span className="inline-flex flex-wrap items-baseline gap-2">
      <span className="font-mono text-[0.8125rem]">
        {formatInteger(listed)} listed
        {expected !== null && <> / {formatInteger(expected)} expected</>}
      </span>
      {expected === null && <span className="text-xs text-zinc-600 dark:text-zinc-400">expected count not determinable</span>}
      {expected !== null && listed !== expected && <Badge tone="warn">mismatch</Badge>}
    </span>
  );
}

function ChunkTable({ layout }: { layout: Layout }) {
  const unit = layout.kind === "tiles" ? "Tile" : "Strip";
  const rows = Math.max(layout.offsets.length, layout.byte_counts.length);
  return (
    <details className="mt-3 rounded-md border border-zinc-200 dark:border-zinc-800">
      <summary className="cursor-pointer px-3 py-2 text-sm font-medium">
        {unit} offsets and byte counts ({formatInteger(rows)} shown
        {layout.truncated && <> of {formatInteger(layout.chunk_count)}</>})
      </summary>
      <div className="max-h-80 overflow-auto border-t border-zinc-200 dark:border-zinc-800">
        <table className="w-full text-left text-sm">
          <thead className="sticky top-0 bg-zinc-50 dark:bg-zinc-900">
            <tr className="text-zinc-600 dark:text-zinc-400">
              <th scope="col" className="px-3 py-1.5 font-medium">#</th>
              <th scope="col" className="px-3 py-1.5 font-medium">Offset</th>
              <th scope="col" className="px-3 py-1.5 font-medium">Byte count</th>
            </tr>
          </thead>
          <tbody className="font-mono text-[0.8125rem]">
            {Array.from({ length: rows }, (_, i) => {
              const off = layout.offsets[i];
              const len = layout.byte_counts[i];
              return (
                <tr key={i} className="border-t border-zinc-100 dark:border-zinc-800">
                  <td className="px-3 py-1">{i}</td>
                  <td className="px-3 py-1">{off === undefined ? "—" : `${formatInteger(off)} (${formatHex(off)})`}</td>
                  <td className="px-3 py-1">{len === undefined ? "—" : formatInteger(len)}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </details>
  );
}

export function StorageLayout({ layout }: { layout: Layout }) {
  const items: KeyValueItem[] = [{ label: "Organisation", value: KIND_LABEL[layout.kind] }];
  if (layout.rows_per_strip) items.push({ label: "Rows per strip", value: <FieldValue field={layout.rows_per_strip} /> });
  if (layout.tile_width) items.push({ label: "Tile width", value: <FieldValue field={layout.tile_width} unit="px" /> });
  if (layout.tile_height) items.push({ label: "Tile height", value: <FieldValue field={layout.tile_height} unit="px" /> });
  items.push(
    { label: layout.kind === "tiles" ? "Tile count" : "Strip count", value: <ChunkCount layout={layout} /> },
    {
      label: "Total stored bytes",
      value:
        layout.total_bytes === null ? (
          <span className="text-zinc-600 italic dark:text-zinc-400">unknown</span>
        ) : (
          <span className="font-mono text-[0.8125rem]">{formatExactBytes(layout.total_bytes)}</span>
        ),
    },
  );

  return (
    <Section
      title="Storage layout"
      actions={
        layout.truncated ? (
          <Badge tone="warn" title="Offsets and byte counts were cut to the inline value limit.">
            truncated list
          </Badge>
        ) : undefined
      }
    >
      <KeyValueList items={items} />
      {layout.truncated && (
        <p className="mt-2 text-sm text-zinc-700 dark:text-zinc-300">
          Offsets and byte counts were cut to the inline value limit; only the first entries are listed.
        </p>
      )}
      {(layout.offsets.length > 0 || layout.byte_counts.length > 0) && <ChunkTable layout={layout} />}
    </Section>
  );
}
