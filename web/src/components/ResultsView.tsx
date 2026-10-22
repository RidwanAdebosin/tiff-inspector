import { useId, useState } from "react";
import { Download, RotateCcw } from "lucide-react";
import type { SuccessReport } from "../api/types";
import { downloadText, reportFileName } from "../lib/download";
import { DirectoryPanel } from "./DirectoryPanel";
import { panelId, tabId } from "../lib/directory";
import { IfdTabs } from "./IfdTabs";
import { ReportOverview } from "./ReportOverview";
import { primaryButton, secondaryButton } from "./styles";

type ResultsViewProps = {
  fileName: string;
  report: SuccessReport;
  /** Exact response body, exported byte-for-byte by "Download JSON". */
  rawBody: string;
  onInspectAnother: () => void;
};

export function ResultsView({ fileName, report, rawBody, onInspectAnother }: ResultsViewProps) {
  const [selected, setSelected] = useState(0);
  const idPrefix = useId();
  const dir = report.directories[selected];

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm text-zinc-600 dark:text-zinc-400">Inspection report</p>
          <h1 className="font-mono text-xl font-semibold break-all sm:text-2xl">{fileName}</h1>
        </div>
        <div className="flex flex-wrap gap-2">
          <button type="button" className={secondaryButton} onClick={() => downloadText(rawBody, reportFileName(fileName))}>
            <Download aria-hidden className="size-4" />
            Download JSON
          </button>
          <button type="button" className={primaryButton} onClick={onInspectAnother}>
            <RotateCcw aria-hidden className="size-4" />
            Inspect another file
          </button>
        </div>
      </div>

      <ReportOverview report={report} />

      <section aria-labelledby={`${idPrefix}-dirs`} className="space-y-4">
        <h2 id={`${idPrefix}-dirs`} className="text-lg font-semibold">
          Directories
        </h2>
        {report.directories.length === 0 ? (
          <p className="text-sm text-zinc-600 dark:text-zinc-400">The report contains no directories.</p>
        ) : (
          <>
            <IfdTabs
              directories={report.directories}
              selected={selected}
              onSelect={setSelected}
              idPrefix={idPrefix}
            />
            {dir && (
              <div role="tabpanel" id={panelId(idPrefix)} aria-labelledby={tabId(idPrefix, selected)} tabIndex={0}>
                <DirectoryPanel dir={dir} />
              </div>
            )}
          </>
        )}
      </section>
    </div>
  );
}
