import { FileSearch } from "lucide-react";
import { useEffect, useRef } from "react";
import { ResultsView } from "./components/ResultsView";
import { UploadScreen } from "./components/UploadScreen";
import { useInspection } from "./state/useInspection";

function App() {
  const { state, busy, select, retry, cancel, reset } = useInspection();
  const mainRef = useRef<HTMLElement>(null);
  const showingResults = state.phase === "success";

  // Move focus to the new view when switching between upload and results.
  const firstRender = useRef(true);
  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false;
      return;
    }
    mainRef.current?.focus();
  }, [showingResults]);

  return (
    <div className="flex min-h-screen flex-col">
      <header className="border-b border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-900">
        <div className="mx-auto flex max-w-6xl items-center gap-2 px-4 py-3">
          <FileSearch aria-hidden className="size-5" />
          <span className="font-semibold">TIFF Inspector</span>
        </div>
      </header>
      <main ref={mainRef} tabIndex={-1} className="mx-auto w-full max-w-6xl flex-1 px-4 py-8 focus:outline-none">
        {state.phase === "success" ? (
          <ResultsView
            fileName={state.file.name}
            report={state.report}
            rawBody={state.rawBody}
            onInspectAnother={reset}
          />
        ) : (
          <UploadScreen state={state} busy={busy} onFile={select} onRetry={retry} onCancel={cancel} />
        )}
      </main>
    </div>
  );
}

export default App;
