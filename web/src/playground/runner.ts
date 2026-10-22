import type { FromWorker, RunResult, SampleFile, ToWorker } from "./protocol";

export type RunnerStatus = "loading" | "ready" | "running" | "failed";

export type Runner = {
  /** Resolves with the OCaml version once the toplevel is loaded. */
  ready(): Promise<string>;
  run(code: string): Promise<RunResult>;
  dispose(): void;
};

export class TimeoutError extends Error {
  constructor(ms: number) {
    super(
      `Stopped after ${Math.round(ms / 1000)} s: the code did not finish. The toplevel was restarted.`,
    );
    this.name = "TimeoutError";
  }
}

export type RunnerOptions = {
  workerUrl: string;
  bundleUrl: string;
  /** Sample files, already fetched. */
  samples: SampleFile[];
  timeoutMs?: number;
};

/**
 * Runs code in a dedicated worker. A run that exceeds the timeout kills the
 * worker (the only way to stop JavaScript that never yields) and starts a
 * fresh one, so the next run works but loses earlier definitions.
 */
export function createRunner(opts: RunnerOptions): Runner {
  const timeoutMs = opts.timeoutMs ?? 10_000;
  let worker: Worker | null = null;
  let readyPromise: Promise<string> = Promise.reject(new Error("not started"));
  readyPromise.catch(() => {});
  let nextId = 1;
  let pending: {
    id: number;
    resolve: (r: RunResult) => void;
    reject: (e: Error) => void;
    timer: number;
  } | null = null;

  const failPending = (err: Error) => {
    if (!pending) return;
    clearTimeout(pending.timer);
    pending.reject(err);
    pending = null;
  };

  const start = () => {
    worker?.terminate();
    const w = new Worker(opts.workerUrl);
    worker = w;
    readyPromise = new Promise<string>((resolve, reject) => {
      w.onmessage = (e: MessageEvent<FromWorker>) => {
        const msg = e.data;
        if (msg.type === "ready") resolve(msg.version);
        else if (msg.type === "fatal") {
          reject(new Error(msg.message));
          failPending(new Error(msg.message));
        } else if (msg.type === "result" && pending && msg.id === pending.id) {
          clearTimeout(pending.timer);
          const { resolve: done } = pending;
          pending = null;
          done({
            chunks: msg.chunks,
            locations: msg.locations,
            passed: msg.passed,
            failed: msg.failed,
          });
        }
      };
      w.onerror = (e) => {
        const err = new Error(e.message || "The playground worker crashed");
        reject(err);
        failPending(err);
      };
      const init: ToWorker = {
        type: "init",
        bundle: opts.bundleUrl,
        samples: opts.samples,
      };
      w.postMessage(init);
    });
    readyPromise.catch(() => {});
  };

  start();

  return {
    ready: () => readyPromise,
    async run(code) {
      if (pending) throw new Error("A run is already in progress");
      await readyPromise;
      const w = worker!;
      return new Promise<RunResult>((resolve, reject) => {
        const id = nextId++;
        const timer = window.setTimeout(() => {
          pending = null;
          start();
          reject(new TimeoutError(timeoutMs));
        }, timeoutMs);
        pending = { id, resolve, reject, timer };
        const msg: ToWorker = { type: "run", id, code };
        w.postMessage(msg);
      });
    },
    dispose() {
      failPending(new Error("disposed"));
      worker?.terminate();
      worker = null;
    },
  };
}

/** Fetches every sample so the worker can register them before the first run. */
export async function fetchSamples(
  base: string,
  names: string[],
): Promise<SampleFile[]> {
  return Promise.all(
    names.map(async (name) => {
      const res = await fetch(`${base}playground/samples/${name}`);
      if (!res.ok)
        throw new Error(`Could not load sample ${name} (${res.status})`);
      return { name, bytes: await res.arrayBuffer() };
    }),
  );
}
