import type { Chunk } from "./protocol";
import { mono } from "../components/styles";

type OutputProps = {
  chunks: Chunk[];
  placeholder: string;
};

const kindClass: Record<Chunk["kind"], string> = {
  stdout: "text-stone-900 dark:text-stone-100",
  stderr: "text-red-700 dark:text-red-300",
  answer: "text-stone-500 dark:text-stone-400",
};

/** The toplevel's output, in order: the program's prints, errors and the toplevel's answers.
    Not a live region: the status line summarises each run for screen readers. */
export function Output({ chunks, placeholder }: OutputProps) {
  if (chunks.length === 0) {
    return (
      <p className="p-3 text-sm text-stone-500 dark:text-stone-400">
        {placeholder}
      </p>
    );
  }
  return (
    <pre className={`${mono} overflow-auto p-3 whitespace-pre-wrap`}>
      {chunks.map((c, i) => (
        <span key={i} className={kindClass[c.kind]} data-kind={c.kind}>
          {c.text}
        </span>
      ))}
    </pre>
  );
}
