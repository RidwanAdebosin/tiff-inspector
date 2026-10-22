import type { Chunk } from "./protocol";
import { mono } from "../components/styles";

type OutputProps = {
  chunks: Chunk[];
  placeholder: string;
};

const kindClass: Record<Chunk["kind"], string> = {
  stdout: "text-zinc-900 dark:text-zinc-100",
  stderr: "text-red-700 dark:text-red-300",
  answer: "text-zinc-500 dark:text-zinc-400",
};

/** The toplevel's output, in order: the program's prints, errors and the toplevel's answers. */
export function Output({ chunks, placeholder }: OutputProps) {
  if (chunks.length === 0) {
    return <p className="p-3 text-sm text-zinc-500 dark:text-zinc-400">{placeholder}</p>;
  }
  return (
    <pre className={`${mono} overflow-auto p-3 whitespace-pre-wrap`} aria-live="polite">
      {chunks.map((c, i) => (
        <span key={i} className={kindClass[c.kind]} data-kind={c.kind}>
          {c.text}
        </span>
      ))}
    </pre>
  );
}
