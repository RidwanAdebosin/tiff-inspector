import type { ReactNode } from "react";

export type KeyValueItem = { label: string; value: ReactNode };

/** Label/value pairs as a definition list; two columns from small screens up. */
export function KeyValueList({ items }: { items: KeyValueItem[] }) {
  return (
    <dl className="divide-y divide-zinc-100 text-sm dark:divide-zinc-800">
      {items.map((item) => (
        <div key={item.label} className="grid gap-1 py-2 sm:grid-cols-[minmax(10rem,14rem)_1fr] sm:gap-4">
          <dt className="text-zinc-600 dark:text-zinc-400">{item.label}</dt>
          <dd className="min-w-0 break-words">{item.value}</dd>
        </div>
      ))}
    </dl>
  );
}
