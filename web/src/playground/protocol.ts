/** Messages exchanged with public/playground/worker.js, and helpers for its output. */

export type ChunkKind = "stdout" | "stderr" | "answer";

export type Chunk = { kind: ChunkKind; text: string };

/** 1-based line, 0-based column, as reported by the OCaml compiler. */
export type SourceLocation = { line: number; col: number; endLine: number; endCol: number };

export type RunResult = {
  chunks: Chunk[];
  /** Compiler locations, each paired with the index of the chunk holding its message. */
  locations: { loc: string; chunkIndex: number }[];
  passed: number;
  failed: number;
};

export type SampleFile = { name: string; bytes: ArrayBuffer };

export type ToWorker =
  | { type: "init"; bundle: string; samples: SampleFile[] }
  | { type: "run"; id: number; code: string };

export type FromWorker =
  | { type: "ready"; version: string }
  | ({ type: "result"; id: number } & RunResult)
  | { type: "fatal"; message: string };

/** Parses "line:col:endLine:endCol" as sent by the toplevel. */
export function parseLocation(text: string): SourceLocation | null {
  const m = /^(\d+):(\d+):(\d+):(\d+)$/.exec(text.trim());
  if (!m) return null;
  const [line, col, endLine, endCol] = m.slice(1).map(Number);
  if (line < 1 || endLine < line) return null;
  return { line, col, endLine, endCol };
}

export type Problem = SourceLocation & { message: string };

/** Pairs each compiler location with the error text printed right after it. */
export function problems(result: Pick<RunResult, "chunks" | "locations">): Problem[] {
  const out: Problem[] = [];
  for (const { loc, chunkIndex } of result.locations) {
    const parsed = parseLocation(loc);
    if (!parsed) continue;
    const chunk = result.chunks[chunkIndex];
    const raw = chunk && chunk.kind === "stderr" ? chunk.text : "";
    // Drop the "Line N, characters A-B:" header; the editor shows the range.
    const message = raw.replace(/^Line \d+, characters \d+-\d+:\s*/, "").trim() || "Error";
    out.push({ ...parsed, message });
  }
  return out;
}
