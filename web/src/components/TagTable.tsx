import { useId, useMemo, useState } from "react";
import { Search } from "lucide-react";
import type { Tag } from "../api/types";
import { formatEnum, formatHex, formatInteger } from "../lib/format";
import { tagMatches } from "../lib/tags";
import { Badge } from "./Badge";
import { Section } from "./Section";
import { TagValueCell } from "./TagValueCell";

const th = "px-3 py-2 font-medium whitespace-nowrap";
const td = "px-3 py-2 align-top";

export function TagTable({ tags, directoryIndex }: { tags: Tag[]; directoryIndex: number }) {
  const [query, setQuery] = useState("");
  const searchId = useId();
  const visible = useMemo(() => tags.filter((t) => tagMatches(t, query)), [tags, query]);

  return (
    <Section title={`Tags (${formatInteger(tags.length)})`}>
      <div className="mb-3 space-y-1">
        <label htmlFor={searchId} className="text-sm font-medium">
          Search tags
        </label>
        <div className="relative max-w-md">
          <Search aria-hidden className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-zinc-500" />
          <input
            id={searchId}
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="ID, hex, name or value"
            className="w-full rounded-md border border-zinc-400 bg-white py-2 pr-3 pl-8 text-sm placeholder:text-zinc-500 dark:border-zinc-600 dark:bg-zinc-950"
          />
        </div>
        <p aria-live="polite" className="text-xs text-zinc-600 dark:text-zinc-400">
          Showing {formatInteger(visible.length)} of {formatInteger(tags.length)} tags
        </p>
      </div>

      <div className="overflow-x-auto rounded-md border border-zinc-200 dark:border-zinc-800">
        <table className="w-full min-w-[40rem] text-left text-sm">
          <caption className="sr-only">Tags in IFD {directoryIndex}</caption>
          <thead className="bg-zinc-50 text-zinc-600 dark:bg-zinc-900 dark:text-zinc-400">
            <tr>
              <th scope="col" className={th}>ID</th>
              <th scope="col" className={th}>Name</th>
              <th scope="col" className={th}>Type</th>
              <th scope="col" className={`${th} text-right`}>Count</th>
              <th scope="col" className={th}>Value</th>
            </tr>
          </thead>
          <tbody>
            {visible.map((tag, i) => (
              <tr key={`${tag.id}-${i}`} className="border-t border-zinc-100 dark:border-zinc-800">
                <td className={`${td} font-mono text-[0.8125rem] whitespace-nowrap`}>
                  {tag.id}
                  <span className="block text-zinc-600 dark:text-zinc-400">{formatHex(tag.id)}</span>
                </td>
                <td className={td}>
                  {tag.known && tag.name ? (
                    <span className="font-medium break-words">{tag.name}</span>
                  ) : (
                    <span className="inline-flex flex-wrap items-center gap-1">
                      <Badge tone="warn">Unknown</Badge>
                      {tag.name && <span className="break-words">{tag.name}</span>}
                    </span>
                  )}
                </td>
                <td className={`${td} font-mono text-[0.8125rem] whitespace-nowrap`}>{formatEnum(tag.field_type)}</td>
                <td className={`${td} text-right font-mono text-[0.8125rem]`}>{formatInteger(tag.count)}</td>
                <td className={`${td} w-1/2`}>
                  <TagValueCell tag={tag} />
                </td>
              </tr>
            ))}
            {visible.length === 0 && (
              <tr>
                <td colSpan={5} className="px-3 py-6 text-center text-zinc-600 dark:text-zinc-400">
                  No tags match “{query}”.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </Section>
  );
}
