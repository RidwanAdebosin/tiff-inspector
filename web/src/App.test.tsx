import { act, fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import App from "./App";
import type { InspectionResult, UploadCallbacks } from "./api/client";
import { successBody, successReport } from "./test/fixtures/successReport";

type Pending = {
  callbacks: UploadCallbacks;
  resolve: (r: InspectionResult) => void;
  abort: ReturnType<typeof vi.fn>;
};
const pending: Pending[] = [];

vi.mock("./api/client", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./api/client")>();
  return {
    ...actual,
    uploadInspection: vi.fn((_file: File, callbacks: UploadCallbacks = {}) => {
      let resolve!: (r: InspectionResult) => void;
      const promise = new Promise<InspectionResult>((r) => (resolve = r));
      // Like the real client: abort settles the promise as cancelled.
      const abort = vi.fn(() => resolve({ ok: false, cancelled: true }));
      pending.push({ callbacks, resolve, abort });
      return { promise, abort };
    }),
  };
});

const tiff = (name = "survey-mosaic.tif") =>
  new File([new Uint8Array([0x49, 0x49, 0x2a, 0x00, 8, 0, 0, 0])], name);
const input = () => screen.getByLabelText("TIFF file") as HTMLInputElement;
const dropZone = () =>
  screen.getByRole("button", { name: "Choose a TIFF file" }).parentElement!;

/** Select a file and wait until the (mocked) upload has started. */
async function startUpload(file = tiff()) {
  await userEvent.upload(input(), file);
  await vi.waitFor(() => expect(pending).toHaveLength(1));
  return pending[0]!;
}

beforeEach(() => {
  pending.length = 0;
});

afterEach(() => {
  vi.useRealTimers();
});

describe("App inspection flow", () => {
  it("shows upload info, then progress, parsing and results", async () => {
    const user = userEvent.setup();
    render(<App />);
    expect(
      screen.getByRole("heading", { name: "See what's inside a TIFF" }),
    ).toBeInTheDocument();
    expect(screen.getByText(/^25 MB/)).toBeInTheDocument();
    expect(
      screen.getByText(/deleted as soon as the report is built/),
    ).toBeInTheDocument();

    await user.upload(input(), tiff());
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    await vi.waitFor(() =>
      expect(screen.getByRole("status")).toHaveTextContent(
        "Uploading “survey-mosaic.tif”",
      ),
    );
    expect(
      screen.getByRole("button", { name: "Choose a TIFF file" }),
    ).toBeDisabled();

    act(() => pending[0]!.callbacks.onProgress?.(4, 8));
    expect(
      screen.getByRole("progressbar", { name: "Upload progress" }),
    ).toHaveAttribute("value", "50");
    expect(screen.getByText("50% · 4 B of 8 B")).toBeInTheDocument();

    act(() => pending[0]!.callbacks.onUploaded?.());
    expect(screen.getByRole("status")).toHaveTextContent(
      "Reading the structure",
    );

    await act(async () =>
      pending[0]!.resolve({
        ok: true,
        report: successReport,
        rawBody: successBody,
      }),
    );
    expect(
      screen.getByRole("heading", { level: 1, name: "survey-mosaic.tif" }),
    ).toBeInTheDocument();

    await user.click(
      screen.getByRole("button", { name: "Inspect another file" }),
    );
    expect(
      screen.getByRole("heading", { name: "See what's inside a TIFF" }),
    ).toBeInTheDocument();
  });

  it("inspects a bundled sample when one is picked", async () => {
    const fetchMock = vi.fn(
      async () =>
        new Response(new Uint8Array([0x49, 0x49, 0x2a, 0x00, 8, 0, 0, 0]), {
          status: 200,
        }),
    );
    vi.stubGlobal("fetch", fetchMock);
    try {
      render(<App />);
      await userEvent.click(
        screen.getByRole("button", { name: "a small grayscale image" }),
      );
      await vi.waitFor(() => expect(pending).toHaveLength(1));
      expect(fetchMock).toHaveBeenCalledWith("/playground/samples/gray8.tif");
      const uploaded = vi
        .mocked((await import("./api/client")).uploadInspection)
        .mock.calls.at(-1)![0];
      expect(uploaded.name).toBe("gray8.tif");
      await vi.waitFor(() =>
        expect(screen.getByRole("status")).toHaveTextContent(
          "Uploading “gray8.tif”",
        ),
      );
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it("explains when a sample cannot be fetched", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(null, { status: 404 })),
    );
    try {
      render(<App />);
      await userEvent.click(
        screen.getByRole("button", { name: "a broken file" }),
      );
      await vi.waitFor(() =>
        expect(screen.getByRole("status")).toHaveTextContent(
          "Couldn't fetch bad_magic.tif",
        ),
      );
      expect(pending).toHaveLength(0);
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it("offers a skip link to the main content", () => {
    render(<App />);
    const skip = screen.getByRole("link", { name: "Skip to content" });
    expect(skip).toHaveAttribute("href", "#main");
    expect(screen.getByRole("main")).toHaveAttribute("id", "main");
  });

  it("lists the BigTIFF extensions under supported formats", () => {
    render(<App />);
    const formats = screen.getByText("Supported formats").nextElementSibling!;
    expect(formats).toHaveTextContent(".tif, .tiff, .btf, .tf8");
    expect(input()).toHaveAttribute(
      "accept",
      ".tif,.tiff,.btf,.tf8,image/tiff",
    );
  });

  it("shows an indeterminate bar when the upload length is not computable", async () => {
    render(<App />);
    const req = await startUpload();
    act(() => req.callbacks.onProgress?.(12 * 1024, 0));
    const bar = screen.getByRole("progressbar", { name: "Upload progress" });
    expect(bar).not.toHaveAttribute("value");
    expect(screen.getByText("12 KB sent")).toBeInTheDocument();
    expect(screen.queryByText(/of 0 B/)).toBeNull();

    // Once the length is known the determinate bar comes back.
    act(() => req.callbacks.onProgress?.(12 * 1024, 24 * 1024));
    expect(
      screen.getByRole("progressbar", { name: "Upload progress" }),
    ).toHaveAttribute("value", "50");
  });

  it("rejects invalid files on the client without uploading", async () => {
    render(<App />);
    await userEvent.upload(input(), new File(["\x89PNG"], "fake.tif"), {
      applyAccept: false,
    });
    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("That doesn't look like a TIFF file");
    expect(alert).toHaveTextContent(/start with a TIFF signature/);
    expect(screen.queryByRole("button", { name: "Retry" })).toBeNull();
    expect(
      screen.getByRole("button", { name: "Choose another file" }),
    ).toBeInTheDocument();
    expect(pending).toHaveLength(0);
  });

  it("ignores a second file while an inspection is in flight", async () => {
    render(<App />);
    await userEvent.upload(input(), tiff());
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    // The input is disabled while busy; simulate a drop-like second selection anyway.
    await act(async () => {
      Object.defineProperty(input(), "files", {
        value: [tiff("second.tif")],
        configurable: true,
      });
      input().disabled = false;
      input().dispatchEvent(new Event("change", { bubbles: true }));
    });
    await new Promise((r) => setTimeout(r, 10));
    expect(pending).toHaveLength(1);
  });

  describe("cancel", () => {
    it("aborts the upload, returns to idle and ignores the request's late result", async () => {
      const user = userEvent.setup();
      render(<App />);
      const req = await startUpload();
      act(() => req.callbacks.onProgress?.(4, 8));
      expect(screen.getByRole("status")).toHaveTextContent("Uploading");

      await user.click(screen.getByRole("button", { name: "Cancel" }));
      expect(req.abort).toHaveBeenCalledTimes(1);
      expect(screen.getByRole("status")).toBeEmptyDOMElement();
      expect(screen.queryByRole("progressbar")).toBeNull();
      expect(screen.queryByRole("alert")).toBeNull();
      expect(
        screen.getByRole("button", { name: "Choose a TIFF file" }),
      ).toBeEnabled();

      // Whatever the aborted request does afterwards must not change the view.
      act(() => req.callbacks.onUploaded?.());
      await act(async () =>
        req.resolve({ ok: true, report: successReport, rawBody: successBody }),
      );
      await act(async () =>
        req.resolve({ ok: false, error: { kind: "server", message: "late" } }),
      );
      expect(screen.getByRole("status")).toBeEmptyDOMElement();
      expect(screen.queryByRole("alert")).toBeNull();
      expect(
        screen.getByRole("heading", { name: "See what's inside a TIFF" }),
      ).toBeInTheDocument();
    });

    it("is offered while parsing and a new file can be chosen afterwards", async () => {
      const user = userEvent.setup();
      render(<App />);
      const req = await startUpload();
      act(() => req.callbacks.onUploaded?.());
      expect(screen.getByRole("status")).toHaveTextContent(
        "Reading the structure",
      );

      await user.click(screen.getByRole("button", { name: "Cancel" }));
      expect(req.abort).toHaveBeenCalledTimes(1);

      await user.upload(input(), tiff("second.tif"));
      await vi.waitFor(() => expect(pending).toHaveLength(2));
      await vi.waitFor(() =>
        expect(screen.getByRole("status")).toHaveTextContent(
          "Uploading “second.tif”",
        ),
      );
    });
  });

  it("offers retry for network errors and re-uploads the same file", async () => {
    const user = userEvent.setup();
    render(<App />);
    await user.upload(input(), tiff());
    await vi.waitFor(() => expect(pending).toHaveLength(1));
    await act(async () =>
      pending[0]!.resolve({
        ok: false,
        error: {
          kind: "network",
          message: "Could not reach the inspection service.",
        },
      }),
    );

    expect(screen.getByRole("alert")).toHaveTextContent(
      "We couldn't reach the server",
    );
    await user.click(screen.getByRole("button", { name: "Retry" }));
    await vi.waitFor(() => expect(pending).toHaveLength(2));
    await act(async () =>
      pending[1]!.resolve({
        ok: true,
        report: successReport,
        rawBody: successBody,
      }),
    );
    expect(
      screen.getByRole("button", { name: "Download JSON" }),
    ).toBeInTheDocument();
  });

  it.each([
    ["malformed", "This file looks damaged or cut short", false],
    [
      "unsupported_feature",
      "This TIFF uses something we can't read yet",
      false,
    ],
    [
      "limit_exceeded",
      "This file is bigger than we can inspect right now",
      true,
    ],
    ["oversized", "This file is too large to upload", false],
    ["rate_limited", "Let's take a short breather", true],
    ["server", "Something went wrong on our side", true],
  ] as const)(
    "shows %s errors with the right actions",
    async (kind, title, retry) => {
      render(<App />);
      await userEvent.upload(input(), tiff());
      await vi.waitFor(() => expect(pending).toHaveLength(1));
      await act(async () =>
        pending[0]!.resolve({
          ok: false,
          error: { kind, message: "details from server", status: 422 },
        }),
      );
      const alert = screen.getByRole("alert");
      expect(alert).toHaveTextContent(title);
      expect(alert).toHaveTextContent("details from server");
      expect(screen.queryByRole("button", { name: "Retry" }) !== null).toBe(
        retry,
      );
    },
  );

  it("holds Retry back for Retry-After seconds, counting down", async () => {
    render(<App />);
    const req = await startUpload();
    vi.useFakeTimers();
    await act(async () =>
      req.resolve({
        ok: false,
        error: {
          kind: "rate_limited",
          code: "rate_limited",
          status: 429,
          message: "slow down",
          retryAfterSeconds: 2,
        },
      }),
    );

    const retry = () => screen.getByRole("button", { name: /Retry/ });
    expect(retry()).toHaveTextContent("Retry in 2 s");
    expect(retry()).toBeDisabled();

    act(() => vi.advanceTimersByTime(1000));
    expect(retry()).toHaveTextContent("Retry in 1 s");
    expect(retry()).toBeDisabled();

    act(() => vi.advanceTimersByTime(1000));
    expect(retry()).toHaveTextContent("Retry");
    expect(retry()).toBeEnabled();
    expect(
      screen.getByRole("button", { name: "Choose another file" }),
    ).toBeEnabled();
  });

  it("offers Retry immediately when a 429 has no Retry-After", async () => {
    render(<App />);
    const req = await startUpload();
    await act(async () =>
      req.resolve({
        ok: false,
        error: { kind: "rate_limited", status: 429, message: "slow down" },
      }),
    );
    expect(screen.getByRole("button", { name: "Retry" })).toBeEnabled();
  });

  describe("drop feedback", () => {
    it("inspects the first of several dropped files and says so in the live region", async () => {
      render(<App />);
      fireEvent.drop(dropZone(), {
        dataTransfer: { files: [tiff("first.tif"), tiff("second.tif")] },
      });
      await vi.waitFor(() => expect(pending).toHaveLength(1));
      const status = screen.getByRole("status");
      expect(status).toHaveTextContent("Only the first file was inspected");
      await vi.waitFor(() =>
        expect(status).toHaveTextContent("Uploading “first.tif”"),
      );
    });

    it("asks for a TIFF when something that is not a file is dropped", async () => {
      render(<App />);
      fireEvent.drop(dropZone(), {
        dataTransfer: { files: [], types: ["text/plain"] },
      });
      expect(screen.getByRole("status")).toHaveTextContent(
        "Drop a .tif or .tiff file",
      );
      await new Promise((r) => setTimeout(r, 10));
      expect(pending).toHaveLength(0);

      // Choosing a file afterwards clears the note.
      await userEvent.upload(input(), tiff());
      await vi.waitFor(() => expect(pending).toHaveLength(1));
      expect(screen.getByRole("status")).not.toHaveTextContent(
        "Drop a .tif or .tiff file",
      );
    });
  });
});
