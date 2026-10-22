import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { successReport } from "../test/fixtures/successReport";
import { TagTable } from "./TagTable";

const ifd0 = successReport.directories[0]!;
const ifd1 = successReport.directories[1]!;
const bodyRows = () => screen.getAllByRole("row").slice(1);

describe("TagTable", () => {
  it("lists every tag with decimal and hex IDs", () => {
    render(<TagTable tags={ifd0.tags} directoryIndex={0} />);
    expect(bodyRows()).toHaveLength(ifd0.tags.length);
    expect(screen.getByText("0x0100")).toBeInTheDocument();
    expect(screen.getByText(/Showing 17 of 17 tags/)).toBeInTheDocument();
  });

  it.each([
    ["decimal id", "33550", "ModelPixelScaleTag"],
    ["hex id", "0x0111", "StripOffsets"],
    ["name, case-insensitive", "imagedesc", "ImageDescription"],
    ["value text", "flight line 7", "ImageDescription"],
  ])("searches by %s", async (_label, query, expected) => {
    render(<TagTable tags={ifd0.tags} directoryIndex={0} />);
    await userEvent.type(screen.getByLabelText("Search tags"), query);
    const rows = bodyRows();
    expect(rows).toHaveLength(1);
    expect(within(rows[0]!).getByText(expected)).toBeInTheDocument();
  });

  it("shows an empty state when nothing matches", async () => {
    render(<TagTable tags={ifd0.tags} directoryIndex={0} />);
    await userEvent.type(screen.getByLabelText("Search tags"), "zzzz");
    expect(screen.getByText(/No tags match/)).toBeInTheDocument();
    expect(screen.getByText(/Showing 0 of 17 tags/)).toBeInTheDocument();
  });

  it("finds unknown tags by the word 'unknown' and badges them", async () => {
    render(<TagTable tags={ifd0.tags} directoryIndex={0} />);
    await userEvent.type(screen.getByLabelText("Search tags"), "unknown");
    const rows = bodyRows();
    expect(rows).toHaveLength(1);
    expect(within(rows[0]!).getByText("Unknown")).toBeInTheDocument();
    expect(within(rows[0]!).getByText("65000")).toBeInTheDocument();
  });

  it("collapses long values and expands them on demand", async () => {
    render(<TagTable tags={ifd0.tags} directoryIndex={0} />);
    await userEvent.type(screen.getByLabelText("Search tags"), "StripOffsets");
    const row = bodyRows()[0]!;
    const toggle = within(row).getByRole("button", {
      name: "Show all 64 values",
    });
    expect(toggle).toHaveAttribute("aria-expanded", "false");
    const lastOffset = String(ifd0.layout.offsets.at(-1));
    expect(row).not.toHaveTextContent(lastOffset);

    await userEvent.click(toggle);
    expect(toggle).toHaveAttribute("aria-expanded", "true");
    expect(toggle).toHaveTextContent("Show less");
    expect(row).toHaveTextContent(lastOffset);

    await userEvent.click(toggle);
    expect(row).not.toHaveTextContent(lastOffset);
  });

  it("collapses long ASCII values", async () => {
    render(<TagTable tags={ifd0.tags} directoryIndex={0} />);
    await userEvent.type(screen.getByLabelText("Search tags"), "270");
    const row = bodyRows()[0]!;
    expect(row).not.toHaveTextContent("Processing pipeline v4.2.");
    await userEvent.click(
      within(row).getByRole("button", { name: /Show all \d+ characters/ }),
    );
    expect(row).toHaveTextContent("Processing pipeline v4.2.");
  });

  it("shows value_status and note for truncated values", async () => {
    render(<TagTable tags={ifd0.tags} directoryIndex={0} />);
    await userEvent.type(
      screen.getByLabelText("Search tags"),
      "StripByteCounts",
    );
    const row = bodyRows()[0]!;
    expect(within(row).getByText("truncated")).toBeInTheDocument();
    expect(
      within(row).getByText("64 of 300 values included"),
    ).toBeInTheDocument();
    expect(
      within(row).getByText("Only the first 64 values are included."),
    ).toBeInTheDocument();
  });

  it("renders non-finite floats explicitly", () => {
    render(<TagTable tags={ifd0.tags} directoryIndex={0} />);
    expect(
      screen.getByText("0.25, 0.25, NaN/∞ (non-finite)"),
    ).toBeInTheDocument();
  });

  it("shows unsupported field types with an unknown type name", () => {
    render(<TagTable tags={ifd1.tags} directoryIndex={1} />);
    const row = screen.getByText("50000").closest("tr")!;
    expect(within(row).getByText("Unknown (code 99)")).toBeInTheDocument();
    expect(within(row).getByText("unsupported type")).toBeInTheDocument();
  });
});
