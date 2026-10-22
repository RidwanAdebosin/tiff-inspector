import { FileSearch } from "lucide-react";
import { Suspense, lazy, useEffect, useRef } from "react";
import { ResultsView } from "./components/ResultsView";
import { UploadScreen } from "./components/UploadScreen";
import { useInspection } from "./state/useInspection";

const Playground = lazy(() => import("./playground/Playground"));

type Page = "inspector" | "playground";

function currentPage(): Page {
  const path = window.location.pathname.replace(/\/+$/, "");
  return path === "/playground" ? "playground" : "inspector";
}

const navLink =
  "rounded px-2 py-1 text-sm font-medium hover:bg-stone-100 dark:hover:bg-stone-800";
const navActive = "bg-stone-100 dark:bg-stone-800";

function Inspector({
  mainRef,
}: {
  mainRef: React.RefObject<HTMLElement | null>;
}) {
  const { state, busy, select, retry, cancel, reset } = useInspection();
  const showingResults = state.phase === "success";

  // Move focus to the new view when switching between upload and results.
  const firstRender = useRef(true);
  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false;
      return;
    }
    mainRef.current?.focus();
  }, [showingResults, mainRef]);

  return state.phase === "success" ? (
    <ResultsView
      fileName={state.file.name}
      report={state.report}
      rawBody={state.rawBody}
      onInspectAnother={reset}
    />
  ) : (
    <UploadScreen
      state={state}
      busy={busy}
      onFile={select}
      onRetry={retry}
      onCancel={cancel}
    />
  );
}

function App() {
  const page = currentPage();
  const mainRef = useRef<HTMLElement>(null);

  return (
    <div className="flex min-h-screen flex-col">
      <header className="border-b border-stone-200 bg-white dark:border-stone-800 dark:bg-stone-900">
        <div className="mx-auto flex max-w-6xl items-center gap-2 px-4 py-3">
          <FileSearch aria-hidden className="size-5" />
          <span className="font-semibold">TIFF Inspector</span>
          <nav aria-label="Pages" className="ml-auto flex gap-1">
            <a
              href="/"
              className={`${navLink} ${page === "inspector" ? navActive : ""}`}
              aria-current={page === "inspector" ? "page" : undefined}
            >
              Inspector
            </a>
            <a
              href="/playground"
              className={`${navLink} ${page === "playground" ? navActive : ""}`}
              aria-current={page === "playground" ? "page" : undefined}
            >
              Playground
            </a>
          </nav>
        </div>
      </header>
      <main
        ref={mainRef}
        tabIndex={-1}
        className="mx-auto w-full max-w-6xl flex-1 px-4 py-8 focus:outline-none"
      >
        {page === "playground" ? (
          <Suspense
            fallback={
              <p className="text-sm text-stone-600 dark:text-stone-400">
                Loading the playground…
              </p>
            }
          >
            <Playground />
          </Suspense>
        ) : (
          <Inspector mainRef={mainRef} />
        )}
      </main>
    </div>
  );
}

export default App;
