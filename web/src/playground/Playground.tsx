import { Play } from "lucide-react";
import { useCallback, useEffect, useId, useRef, useState } from "react";
import { card, mono, muted, primaryButton } from "../components/styles";
import { Editor } from "./Editor";
import { EXAMPLES } from "./examples";
import { applyPageIcon } from "./pageIcon";
import { Output } from "./Output";
import { problems as toProblems, type Chunk, type Problem } from "./protocol";
import {
  createRunner,
  fetchSamples,
  TimeoutError,
  type Runner,
  type RunnerStatus,
} from "./runner";
import { SAMPLES } from "./samples";

const BASE = import.meta.env.BASE_URL;
const RUN_TIMEOUT_MS = 10_000;

const REFERENCE: { call: string; about: string }[] = [
  {
    call: 'Sample.reader "gray8.tif"',
    about: "a Tiff.File.ro for Tiff.from_file",
  },
  {
    call: 'Sample.source "gray8.tif"',
    about: "a Tiff_inspector.Source.t for Inspect.run",
  },
  {
    call: 'Sample.inspect "gray8.tif"',
    about: "the inspector's report, as a result",
  },
  {
    call: 'Sample.inspect_json "gray8.tif"',
    about: "prints the report as JSON",
  },
  { call: "Sample.names ()", about: "every bundled file" },
  { call: 'Test.check "name" bool', about: "one assertion" },
  {
    call: 'Test.int "name" ~expected:3 actual',
    about: "also Test.string, Test.bool",
  },
];

/** One short line for the status area after a run. */
function summary(problemCount: number, passed: number, failed: number): string {
  if (problemCount > 0) {
    return problemCount === 1
      ? "One thing to fix. It's underlined in the editor; hover it to see why."
      : `${problemCount} things to fix. They're underlined in the editor; hover each to see why.`;
  }
  if (failed > 0)
    return failed === 1
      ? "One check didn't pass yet. The FAIL line says which."
      : `${failed} checks didn't pass yet. The FAIL lines say which.`;
  if (passed > 0)
    return passed === 1 ? "Your check passed." : `All ${passed} checks passed.`;
  return "Ran without any problems.";
}

function checksBadge(counts: { passed: number; failed: number }): string {
  const total = counts.passed + counts.failed;
  if (counts.failed === 0)
    return total === 1 ? "1 check passed" : `All ${total} checks passed`;
  return `${counts.passed} of ${total} checks passed`;
}

export default function Playground() {
  const [exampleId, setExampleId] = useState(EXAMPLES[0].id);
  const [code, setCode] = useState(EXAMPLES[0].code);
  const [chunks, setChunks] = useState<Chunk[]>([]);
  const [problems, setProblems] = useState<Problem[]>([]);
  const [counts, setCounts] = useState<{
    passed: number;
    failed: number;
  } | null>(null);
  const [status, setStatus] = useState<RunnerStatus>("loading");
  const [detail, setDetail] = useState(
    "Getting OCaml ready… this takes a few seconds the first time.",
  );
  const runner = useRef<Runner | null>(null);
  const selectId = useId();

  // The OCaml camel in the tab while this page is open.
  useEffect(
    () =>
      applyPageIcon({
        title: "OCaml playground · TIFF Inspector",
        svg: `${BASE}playground/ocaml-icon.svg`,
        png: `${BASE}playground/ocaml-icon-32.png`,
      }),
    [],
  );

  useEffect(() => {
    let cancelled = false;
    let r: Runner | null = null;
    fetchSamples(
      BASE,
      SAMPLES.map((s) => s.name),
    )
      .then((samples) => {
        if (cancelled) return;
        r = createRunner({
          workerUrl: `${BASE}playground/worker.js`,
          bundleUrl: `${BASE}playground/toplevel.js`,
          samples,
          timeoutMs: RUN_TIMEOUT_MS,
        });
        runner.current = r;
        return r.ready();
      })
      .then((version) => {
        if (cancelled || version === undefined) return;
        setStatus("ready");
        setDetail(`Ready. OCaml ${version}`);
      })
      .catch((err: unknown) => {
        if (cancelled) return;
        setStatus("failed");
        setDetail(
          `The playground couldn't start. Reloading the page usually fixes it. (${err instanceof Error ? err.message : String(err)})`,
        );
      });
    return () => {
      cancelled = true;
      r?.dispose();
    };
  }, []);

  const run = useCallback(() => {
    const r = runner.current;
    if (!r || status !== "ready") return;
    setStatus("running");
    setDetail("Running…");
    r.run(code)
      .then((result) => {
        setChunks(result.chunks);
        const found = toProblems(result);
        setProblems(found);
        setCounts(
          result.passed + result.failed > 0
            ? { passed: result.passed, failed: result.failed }
            : null,
        );
        setStatus("ready");
        setDetail(summary(found.length, result.passed, result.failed));
      })
      .catch(async (err: unknown) => {
        const message = err instanceof Error ? err.message : String(err);
        setChunks([{ kind: "stderr", text: message + "\n" }]);
        setProblems([]);
        setCounts(null);
        if (err instanceof TimeoutError) {
          try {
            await r.ready();
            setStatus("ready");
            setDetail("Stopped that one. Ready when you are.");
          } catch (e) {
            setStatus("failed");
            setDetail(
              `The playground couldn't restart. Reloading the page usually fixes it. (${e instanceof Error ? e.message : String(e)})`,
            );
          }
        } else {
          setStatus("failed");
          setDetail(
            `Something went wrong while running. Reloading the page usually fixes it. (${message})`,
          );
        }
      });
  }, [status, code]);

  const pickExample = (id: string) => {
    const ex = EXAMPLES.find((e) => e.id === id);
    if (!ex) return;
    setExampleId(id);
    setCode(ex.code);
    setProblems([]);
  };

  return (
    <div className="space-y-6">
      <div className="flex items-start gap-3">
        <img
          src={`${BASE}playground/ocaml-icon.svg`}
          alt=""
          className="mt-0.5 h-8 w-auto"
        />
        <div>
          <h1 className="text-2xl font-semibold">OCaml playground</h1>
          <p className={`mt-1 text-sm ${muted}`}>
            Write OCaml and run it in your browser. The standard library, the
            tiff library and the inspector core are loaded, with a few sample
            files. Nothing is uploaded.
          </p>
        </div>
      </div>

      <ol
        className={`flex flex-wrap gap-x-6 gap-y-1 text-sm ${muted}`}
        aria-label="How it works"
      >
        <li>1. Pick an example, or write your own.</li>
        <li>2. Press Run.</li>
        <li>3. Read the output. Red means something to fix.</li>
      </ol>

      <div className="flex flex-wrap items-center gap-3">
        <label htmlFor={selectId} className="text-sm font-medium">
          Example
        </label>
        <select
          id={selectId}
          value={exampleId}
          onChange={(e) => pickExample(e.target.value)}
          className="rounded-md border border-stone-300 bg-white px-2 py-1.5 text-sm dark:border-stone-700 dark:bg-stone-900"
        >
          {EXAMPLES.map((e) => (
            <option key={e.id} value={e.id}>
              {e.title}
            </option>
          ))}
        </select>
        <button
          type="button"
          className={primaryButton}
          onClick={run}
          disabled={status !== "ready"}
        >
          <Play aria-hidden className="size-4" />
          {status === "running" ? "Running…" : "Run"}
        </button>
        <span
          className={`text-sm ${status === "failed" ? "text-red-700 dark:text-red-300" : muted}`}
          role="status"
        >
          {detail}
        </span>
        <span className={`ml-auto hidden text-xs sm:inline ${muted}`}>
          Ctrl/Cmd+Enter runs
        </span>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <section aria-label="Code" className={`${card} overflow-hidden`}>
          <Editor
            value={code}
            onChange={setCode}
            onRun={run}
            problems={problems}
            label="OCaml code"
          />
        </section>
        <section
          aria-labelledby="playground-output"
          className={`${card} flex min-h-[20rem] flex-col`}
        >
          <div className="flex items-center justify-between gap-2 border-b border-stone-200 px-3 py-2 dark:border-stone-800">
            <h2 id="playground-output" className="text-sm font-semibold">
              Output
            </h2>
            <span className="flex flex-wrap items-center gap-2">
              {problems.length > 0 && (
                <span className="rounded-full bg-red-100 px-2 py-0.5 text-xs font-medium text-red-800 dark:bg-red-950 dark:text-red-200">
                  {problems.length === 1
                    ? "1 problem"
                    : `${problems.length} problems`}
                </span>
              )}
              {counts && (
                <span
                  className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                    counts.failed > 0
                      ? "bg-red-100 text-red-800 dark:bg-red-950 dark:text-red-200"
                      : "bg-green-100 text-green-800 dark:bg-green-950 dark:text-green-200"
                  }`}
                >
                  {checksBadge(counts)}
                </span>
              )}
            </span>
          </div>
          <div className="flex-1 overflow-auto">
            <Output
              chunks={chunks}
              placeholder="Nothing here yet. Press Run, or Ctrl/Cmd+Enter, and your output will show up."
            />
          </div>
        </section>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <section aria-labelledby="playground-samples" className={`${card} p-4`}>
          <h2 id="playground-samples" className="text-sm font-semibold">
            Sample files
          </h2>
          <ul className="mt-2 space-y-1 text-sm">
            {SAMPLES.map((s) => (
              <li key={s.name} className="flex gap-2">
                <code className={mono}>{s.name}</code>
                <span className={muted}>{s.about}</span>
              </li>
            ))}
          </ul>
        </section>
        <section
          aria-labelledby="playground-reference"
          className={`${card} p-4`}
        >
          <h2 id="playground-reference" className="text-sm font-semibold">
            Things you can call
          </h2>
          <ul className="mt-2 space-y-1 text-sm">
            {REFERENCE.map((r) => (
              <li key={r.call} className="flex flex-wrap gap-x-2">
                <code className={mono}>{r.call}</code>
                <span className={muted}>{r.about}</span>
              </li>
            ))}
          </ul>
          <p className={`mt-3 text-xs ${muted}`}>
            A run that takes longer than {RUN_TIMEOUT_MS / 1000} seconds is
            stopped and the toplevel restarts, which clears earlier definitions.
          </p>
        </section>
      </div>

      <p className={`text-xs ${muted}`}>
        The camel is the{" "}
        <a
          href="https://ocaml.org/logo"
          className="underline underline-offset-2"
        >
          OCaml logo
        </a>
        , used with thanks to the OCaml project.
      </p>
    </div>
  );
}
