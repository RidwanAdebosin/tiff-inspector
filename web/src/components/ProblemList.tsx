import { TriangleAlert } from "lucide-react";
import type { Problem } from "../api/types";
import { formatHex } from "../lib/format";

function location(p: Problem): string | null {
  const parts: string[] = [];
  if (p.directory !== null) parts.push(`IFD ${p.directory}`);
  if (p.tag !== null) parts.push(`tag ${p.tag} (${formatHex(p.tag)})`);
  return parts.length ? parts.join(", ") : null;
}

export function ProblemList({ problems, emptyText }: { problems: Problem[]; emptyText?: string }) {
  if (problems.length === 0) {
    return emptyText ? <p className="text-sm text-zinc-600 dark:text-zinc-400">{emptyText}</p> : null;
  }
  return (
    <ul className="space-y-2">
      {problems.map((p, i) => {
        const where = location(p);
        return (
          <li
            key={`${p.code}-${i}`}
            className="flex gap-2 rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-950 dark:border-amber-900 dark:bg-amber-950 dark:text-amber-100"
          >
            <TriangleAlert aria-hidden className="mt-0.5 size-4 shrink-0" />
            <div className="min-w-0">
              <p className="break-words">{p.message}</p>
              <p className="mt-1 font-mono text-xs">
                {p.code}
                {where && <> · {where}</>}
              </p>
            </div>
          </li>
        );
      })}
    </ul>
  );
}
