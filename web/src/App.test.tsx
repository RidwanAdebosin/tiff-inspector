import { act, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import App from "./App";
import type { InspectionResult, UploadCallbacks } from "./api/client";
import { successBody, successReport } from "./test/fixtures/successReport";

type Pending = { callbacks: UploadCallbacks; resolve: (r: InspectionResult) => void };
const pending: Pending[] = [];

vi.mock("./api/client", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./api/client")>();
  return {
    ...actual,
    uploadInspection: vi.fn((_file: File, callbacks: UploadCallbacks = {}) => {
      let resolve!: (r: InspectionResult) => void;
      const promise = new Promise<InspectionResult>((r) => (resolve = r));
      pending.push({ callbacks, resolve });
      return { promise, abort: vi.fn() };
    }),
  };
});

const tiff = (name = "survey-mosaic.tif") => new File([new Uint8Array([0x49, 0x49, 0x2a, 0x00, 8, 0, 0, 0])], name);
const input = () => screen.getByLabelText("TIFF file") as HTMLInputElement;

beforeEach(() => {
  pending.length = 0;
});

describe("App inspection flow", () => {
  it("shows upload info, then progress, parsing and results", async () => {
    const user = userEvent.setup();
    render(<App />);
    expect(screen.getByRole("heading", { name: "TIFF Inspector" })).toBeInTheDocument();
    expect(screen.getByText("25 MB")).toBeInTheDocument();
    expect(screen.getByText(/nothing is stored/)).toBeInTheDocument();

    await user.upload(input(), tiff());
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    await vi.waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Uploading “survey-mosaic.tif”"));
    expect(screen.getByRole("button", { name: "Choose a TIFF file" })).toBeDisabled();

    act(() => pending[0]!.callbacks.onProgress?.(4, 8));
    expect(screen.getByRole("progressbar", { name: "Upload progress" })).toHaveAttribute("value", "50");

    act(() => pending[0]!.callbacks.onUploaded?.());
    expect(screen.getByRole("status")).toHaveTextContent("Parsing");

    await act(async () => pending[0]!.resolve({ ok: true, report: successReport, rawBody: successBody }));
    expect(screen.getByRole("heading", { level: 1, name: "survey-mosaic.tif" })).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Inspect another file" }));
    expect(screen.getByRole("heading", { name: "TIFF Inspector" })).toBeInTheDocument();
  });

  it("rejects invalid files on the client without uploading", async () => {
    render(<App />);
    await userEvent.upload(input(), new File(["\x89PNG"], "fake.tif"), { applyAccept: false });
    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Not a valid TIFF file");
    expect(alert).toHaveTextContent(/does not start with a TIFF signature/);
    expect(screen.queryByRole("button", { name: "Retry" })).toBeNull();
    expect(screen.getByRole("button", { name: "Choose another file" })).toBeInTheDocument();
    expect(pending).toHaveLength(0);
  });

  it("ignores a second file while an inspection is in flight", async () => {
    render(<App />);
    await userEvent.upload(input(), tiff());
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    // The input is disabled while busy; simulate a drop-like second selection anyway.
    await act(async () => {
      Object.defineProperty(input(), "files", { value: [tiff("second.tif")], configurable: true });
      input().disabled = false;
      input().dispatchEvent(new Event("change", { bubbles: true }));
    });
    await new Promise((r) => setTimeout(r, 10));
    expect(pending).toHaveLength(1);
  });

  it("offers retry for network errors and re-uploads the same file", async () => {
    const user = userEvent.setup();
    render(<App />);
    await user.upload(input(), tiff());
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    await act(async () => pending[0]!.resolve({ ok: false, error: { kind: "network", message: "Could not reach the inspection service." } }));

    expect(screen.getByRole("alert")).toHaveTextContent("Network error");
    await user.click(screen.getByRole("button", { name: "Retry" }));
    await vi.waitFor(() => expect(pending).toHaveLength(2));
    await act(async () => pending[1]!.resolve({ ok: true, report: successReport, rawBody: successBody }));
    expect(screen.getByRole("button", { name: "Download JSON" })).toBeInTheDocument();
  });

  it.each([
    ["malformed", "Malformed or truncated TIFF", false],
    ["unsupported_feature", "Unsupported TIFF feature", false],
    ["oversized", "File too large", false],
    ["rate_limited", "Too many requests", true],
    ["server", "Server error", true],
  ] as const)("shows %s errors with the right actions", async (kind, title, retry) => {
    render(<App />);
    await userEvent.upload(input(), tiff());
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    await act(async () => pending[0]!.resolve({ ok: false, error: { kind, message: "details from server", status: 422 } }));
    const alert = screen.getByRole("alert");
    expect(alert).toHaveTextContent(title);
    expect(alert).toHaveTextContent("details from server");
    expect(screen.queryByRole("button", { name: "Retry" }) !== null).toBe(retry);
  });
});
