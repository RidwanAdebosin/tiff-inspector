import { readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { InspectionReport } from "../api/types";
import { successBody, successReport } from "../test/fixtures/successReport";
import { ResultsView } from "./ResultsView";

const renderResults = (onInspectAnother = vi.fn()) =>
  render(
    <ResultsView
      fileName="survey-mosaic.tif"
      report={successReport}
      rawBody={successBody}
      onInspectAnother={onInspectAnother}
    />,
  );

afterEach(() => vi.restoreAllMocks());

// jsdom's Blob has no .text(); FileReader works.
const readBlob = (b: Blob) =>
  new Promise<string>((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result as string);
    r.onerror = () => reject(r.error);
    r.readAsText(b);
  });

describe("ResultsView overview", () => {
  it("shows file facts, warnings and limitations", () => {
    renderResults();
    expect(screen.getByText("Little-endian (II)")).toBeInTheDocument();
    expect(screen.getByText("Classic TIFF")).toBeInTheDocument();
    expect(screen.getByText("Complete")).toBeInTheDocument();
    expect(screen.getByText(/2,048 bytes after the last referenced data/)).toBeInTheDocument();
    expect(screen.getByText("Pixel data is not decoded in version 1.")).toBeInTheDocument();
  });

  it("warns when the IFD walk did not complete", () => {
    const report = {
      ...successReport,
      ifd_walk: { status: "failed" as const, limit: 1024, error: { code: "truncated" as const, message: "IFD 2 is cut off." } },
    };
    render(<ResultsView fileName="x.tif" report={report} rawBody="{}" onInspectAnother={() => {}} />);
    expect(screen.getByText("Failed part-way")).toBeInTheDocument();
    expect(screen.getByText(/IFD 2 is cut off\./)).toBeInTheDocument();
  });
});

describe("IFD navigation", () => {
  it("lists directories as tabs with index and dimensions", () => {
    renderResults();
    const tabs = screen.getAllByRole("tab");
    expect(tabs).toHaveLength(2);
    expect(tabs[0]).toHaveTextContent("IFD 0");
    expect(tabs[0]).toHaveTextContent("2048 × 1536");
    expect(tabs[1]).toHaveTextContent("256 × 192");
    expect(tabs[0]).toHaveAttribute("aria-selected", "true");
  });

  it("moves between directories with arrow keys, Home and End (roving tabindex)", async () => {
    const user = userEvent.setup();
    renderResults();
    const [first, second] = screen.getAllByRole("tab") as [HTMLElement, HTMLElement];
    expect(first).toHaveAttribute("tabindex", "0");
    expect(second).toHaveAttribute("tabindex", "-1");

    await user.tab();
    await user.tab();
    await user.tab();
    expect(first).toHaveFocus();

    await user.keyboard("{ArrowRight}");
    expect(second).toHaveFocus();
    expect(second).toHaveAttribute("aria-selected", "true");
    expect(second).toHaveAttribute("tabindex", "0");
    const panel = screen.getByRole("tabpanel");
    expect(panel).toHaveAccessibleName(/IFD 1/);
    expect(within(panel).getByText(/Tile count/)).toBeInTheDocument();
    expect(within(panel).getByText("Unknown (code 34712)")).toBeInTheDocument();

    await user.keyboard("{ArrowRight}");
    expect(first).toHaveFocus();
    await user.keyboard("{End}");
    expect(second).toHaveFocus();
    await user.keyboard("{Home}");
    expect(first).toHaveFocus();
    await user.keyboard("{ArrowLeft}");
    expect(second).toHaveFocus();
  });

  it("explains separate planar configuration and lists planes", () => {
    renderResults();
    const panel = screen.getByRole("tabpanel");
    expect(within(panel).getByText(/Separate \(planar\)/)).toBeInTheDocument();
    expect(within(panel).getByText("Plane 2")).toBeInTheDocument();
    expect(within(panel).getByText(/v1|metadata only/i)).toBeInTheDocument();
    expect(within(panel).getByText("truncated list")).toBeInTheDocument();
    expect(within(panel).getByText("mismatch")).toBeInTheDocument();
  });

  it("explains contiguous configuration and marks it as a spec default", async () => {
    renderResults();
    await userEvent.click(screen.getAllByRole("tab")[1]!);
    const panel = screen.getByRole("tabpanel");
    expect(within(panel).getByText(/Contiguous \(“chunky”\)/)).toBeInTheDocument();
    expect(within(panel).getAllByText("spec default").length).toBeGreaterThan(0);
    expect(within(panel).getAllByText("not present")).toHaveLength(2);
  });
});

describe("Download JSON", () => {
  it("exports the exact raw server body as <name>.inspection.json", async () => {
    let blob: Blob | undefined;
    URL.createObjectURL = vi.fn((b: Blob) => {
      blob = b;
      return "blob:mock";
    });
    URL.revokeObjectURL = vi.fn();
    const clicked: HTMLAnchorElement[] = [];
    vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(function (this: HTMLAnchorElement) {
      clicked.push(this);
    });

    renderResults();
    await userEvent.click(screen.getByRole("button", { name: "Download JSON" }));

    expect(clicked).toHaveLength(1);
    expect(clicked[0]!.download).toBe("survey-mosaic.tif.inspection.json");
    expect(blob).toBeDefined();
    expect(await readBlob(blob!)).toBe(successBody);
    expect(blob!.type).toBe("application/json");
  });
});

describe("golden CLI reports", () => {
  const goldenDir = resolve(__dirname, "../../../test/golden");
  let names: string[] = [];
  try {
    names = readdirSync(goldenDir).filter((n) => n.endsWith(".json"));
  } catch {
    names = [];
  }
  const successes = names
    .map((n) => [n, readFileSync(join(goldenDir, n), "utf8")] as const)
    .filter(([, body]) => (JSON.parse(body) as InspectionReport).ok);

  it.skipIf(successes.length === 0).each(successes)("renders %s", async (_name, body) => {
    const report = JSON.parse(body);
    render(<ResultsView fileName={report.file.name} report={report} rawBody={body} onInspectAnother={() => {}} />);
    expect(screen.getByRole("heading", { name: "Overview" })).toBeInTheDocument();
    for (const tab of screen.queryAllByRole("tab")) {
      await userEvent.click(tab);
      expect(screen.getByRole("tabpanel")).toBeInTheDocument();
    }
  });
});
