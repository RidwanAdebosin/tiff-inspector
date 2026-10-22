import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import type { EnumField, IntField, IntListField } from "../api/types";
import { FieldValue } from "./FieldValue";

describe("FieldValue", () => {
  it("present: plain value, no badge", () => {
    const field: IntField = { status: "present", value: 2048, note: null };
    const { container } = render(<FieldValue field={field} unit="px" />);
    expect(container).toHaveTextContent("2,048 px");
    expect(
      screen.queryByText(/spec default|not present|unsupported|error/),
    ).toBeNull();
  });

  it("present enum: name and code", () => {
    const field: EnumField = {
      status: "present",
      value: { code: 2, name: "RGB", label: "RGB" },
      note: null,
    };
    render(<FieldValue field={field} />);
    expect(screen.getByText("RGB (2)")).toBeInTheDocument();
  });

  it("unknown enum name: 'Unknown (code N)'", () => {
    const field: EnumField = {
      status: "present",
      value: { code: 5, name: null, label: null },
      note: null,
    };
    render(<FieldValue field={field} />);
    expect(screen.getByText("Unknown (code 5)")).toBeInTheDocument();
  });

  it("default: value plus a 'spec default' badge and explanatory note", () => {
    const field: EnumField = {
      status: "default",
      value: { code: 1, name: "top_left", label: "Top-left" },
      note: "TIFF 6.0 default.",
    };
    render(<FieldValue field={field} />);
    expect(screen.getByText("Top-left (1)")).toBeInTheDocument();
    const badge = screen.getByText("spec default");
    expect(badge).toHaveAttribute("title", "TIFF 6.0 default.");
    expect(screen.getByText("TIFF 6.0 default.")).toBeInTheDocument();
  });

  it("default without a note still explains the value is not from the file", () => {
    const field: IntField = { status: "default", value: 1, note: null };
    render(<FieldValue field={field} />);
    expect(screen.getByText("spec default")).toBeInTheDocument();
    expect(
      screen.getByText(/not a value read from the file/),
    ).toBeInTheDocument();
  });

  it("absent: muted 'not present' and no value", () => {
    const field: IntField = { status: "absent", value: null, note: null };
    const { container } = render(<FieldValue field={field} />);
    expect(screen.getByText("not present")).toBeInTheDocument();
    expect(container.querySelector("[data-status=absent]")).not.toBeNull();
  });

  it("unsupported: badge and note", () => {
    const field: IntListField = {
      status: "unsupported",
      value: null,
      note: "Uses field type 13 (IFD).",
    };
    render(<FieldValue field={field} />);
    expect(screen.getByText("unsupported")).toBeInTheDocument();
    expect(screen.getByText("Uses field type 13 (IFD).")).toBeInTheDocument();
  });

  it("error: badge and note", () => {
    const field: IntField = {
      status: "error",
      value: null,
      note: "Offset beyond end of file.",
    };
    render(<FieldValue field={field} />);
    expect(screen.getByText("error")).toBeInTheDocument();
    expect(screen.getByText("Offset beyond end of file.")).toBeInTheDocument();
  });
});
