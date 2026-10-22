import type { SuccessReport } from "../api/types";
import { formatByteOrder, formatBytes, formatExactBytes, formatHex, formatInteger, formatTiffFormat } from "../lib/format";
import { Badge } from "./Badge";
import { KeyValueList } from "./KeyValueList";
import { ProblemList } from "./ProblemList";
import { Section } from "./Section";

const WALK_TEXT: Record<SuccessReport["ifd_walk"]["status"], string> = {
  complete: "Complete",
  truncated_at_limit: "Stopped at the directory limit",
  failed: "Failed part-way",
};

export function ReportOverview({ report }: { report: SuccessReport }) {
  const { file, ifd_walk: walk } = report;
  return (
    <Section title="Overview" level={2}>
      <KeyValueList
        items={[
          { label: "File name", value: <span className="font-mono break-all">{file.name}</span> },
          {
            label: "Size",
            value: (
              <>
                {formatBytes(file.size_bytes)}{" "}
                <span className="text-zinc-600 dark:text-zinc-400">({formatExactBytes(file.size_bytes)})</span>
              </>
            ),
          },
          { label: "Byte order", value: formatByteOrder(file.byte_order) },
          { label: "Format", value: formatTiffFormat(file.format) },
          {
            label: "First IFD offset",
            value: (
              <span className="font-mono">
                {formatInteger(file.first_ifd_offset)} ({formatHex(file.first_ifd_offset)})
              </span>
            ),
          },
          { label: "IFD count", value: formatInteger(report.ifd_count) },
          {
            label: "IFD walk",
            value:
              walk.status === "complete" ? (
                <Badge tone="success">{WALK_TEXT.complete}</Badge>
              ) : (
                <span className="space-y-1">
                  <Badge tone="warn">{WALK_TEXT[walk.status]}</Badge>
                  <span className="block text-sm">
                    Not every directory may be listed (limit: {formatInteger(walk.limit)} IFDs).
                    {walk.error && (
                      <>
                        {" "}
                        {walk.error.message} <span className="font-mono text-xs">({walk.error.code})</span>
                      </>
                    )}
                  </span>
                </span>
              ),
          },
          { label: "Inspected by", value: <span className="font-mono">{`${report.tool.name} ${report.tool.version}`}</span> },
        ]}
      />

      <div className="mt-4 space-y-2">
        <h3 className="text-sm font-semibold">File warnings</h3>
        <ProblemList problems={report.warnings} emptyText="No file-level warnings." />
      </div>

      {report.limitations.length > 0 && (
        <div className="mt-4 space-y-2">
          <h3 className="text-sm font-semibold">Limitations of this inspection</h3>
          <ul className="list-disc space-y-1 pl-5 text-sm text-zinc-700 dark:text-zinc-300">
            {report.limitations.map((l) => (
              <li key={l}>{l}</li>
            ))}
          </ul>
        </div>
      )}
    </Section>
  );
}
