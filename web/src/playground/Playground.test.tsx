import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { RunResult } from "./protocol";

const mocks = vi.hoisted(() => ({
  run: vi.fn<(code: string) => Promise<RunResult>>(),
  ready: vi.fn<() => Promise<string>>(),
  dispose: vi.fn(),
}));

vi.mock("./runner", () => ({
  fetchSamples: vi.fn(async () => []),
  createRunner: vi.fn(() => ({
    ready: mocks.ready,
    run: mocks.run,
    dispose: mocks.dispose,
  })),
  TimeoutError: class TimeoutError extends Error {},
}));

// CodeMirror needs layout APIs jsdom lacks; a textarea keeps the tests about the page.
vi.mock("./Editor", () => ({
  Editor: ({
    value,
    onChange,
    label,
  }: {
    value: string;
    onChange: (v: string) => void;
    label: string;
  }) => (
    <textarea
      aria-label={label}
      value={value}
      onChange={(e) => onChange(e.target.value)}
    />
  ),
}));

import Playground from "./Playground";
import { EXAMPLES } from "./examples";

const ok = (over: Partial<RunResult> = {}): RunResult => ({
  chunks: [],
  locations: [],
  passed: 0,
  failed: 0,
  ...over,
});

describe("Playground", () => {
  beforeEach(() => {
    mocks.run.mockReset();
    mocks.ready.mockReset().mockResolvedValue("5.4.1");
  });

  it("loads the first example and reports the toplevel version", async () => {
    render(<Playground />);
    expect(screen.getByLabelText("OCaml code")).toHaveValue(EXAMPLES[0].code);
    expect(screen.getByRole("button", { name: /run/i })).toBeDisabled();
    await waitFor(() =>
      expect(screen.getByRole("status")).toHaveTextContent(
        "Ready. OCaml 5.4.1",
      ),
    );
    expect(screen.getByRole("button", { name: /run/i })).toBeEnabled();
  });

  it("runs the code and shows output, errors and test totals", async () => {
    mocks.run.mockResolvedValue(
      ok({
        chunks: [
          { kind: "stdout", text: "PASS a\nFAIL b\n" },
          { kind: "stderr", text: "Line 1, characters 4-6:\nError: boom\n" },
          { kind: "answer", text: "- : unit = ()\n" },
        ],
        locations: [{ loc: "1:4:1:6", chunkIndex: 1 }],
        passed: 1,
        failed: 1,
      }),
    );
    const user = userEvent.setup();
    render(<Playground />);
    await waitFor(() =>
      expect(screen.getByRole("button", { name: /run/i })).toBeEnabled(),
    );
    await user.click(screen.getByRole("button", { name: /run/i }));
    await waitFor(() =>
      expect(screen.getByText("1 of 2 checks passed")).toBeInTheDocument(),
    );
    expect(screen.getByText("1 problem")).toBeInTheDocument();
    expect(mocks.run).toHaveBeenCalledWith(EXAMPLES[0].code);
    expect(screen.getByText(/Error: boom/)).toHaveAttribute(
      "data-kind",
      "stderr",
    );
    expect(screen.getByText(/- : unit = \(\)/)).toHaveAttribute(
      "data-kind",
      "answer",
    );
    expect(screen.getByRole("status")).toHaveTextContent("One thing to fix");
  });

  it("shows the OCaml camel in the tab while open, then restores the previous icon", () => {
    const original = document.createElement("link");
    original.rel = "icon";
    original.href = "/old.ico";
    document.head.append(original);
    document.title = "Before";
    const { unmount } = render(<Playground />);
    const icons = Array.from(
      document.head.querySelectorAll<HTMLLinkElement>('link[rel="icon"]'),
    );
    expect(icons.map((l) => l.getAttribute("href"))).toEqual([
      "/playground/ocaml-icon.svg",
      "/playground/ocaml-icon-32.png",
    ]);
    expect(document.title).toBe("OCaml playground · TIFF Inspector");
    unmount();
    expect(
      Array.from(document.head.querySelectorAll('link[rel="icon"]')),
    ).toEqual([original]);
    expect(document.title).toBe("Before");
    original.remove();
  });

  it("celebrates when every check passes and nothing is wrong", async () => {
    mocks.run.mockResolvedValue(
      ok({
        chunks: [{ kind: "stdout", text: "PASS a\nPASS b\n" }],
        passed: 2,
        failed: 0,
      }),
    );
    const user = userEvent.setup();
    render(<Playground />);
    await waitFor(() =>
      expect(screen.getByRole("button", { name: /run/i })).toBeEnabled(),
    );
    await user.click(screen.getByRole("button", { name: /run/i }));
    await waitFor(() =>
      expect(screen.getByText("All 2 checks passed")).toBeInTheDocument(),
    );
    expect(screen.getByRole("status")).toHaveTextContent(
      "All 2 checks passed.",
    );
    expect(screen.queryByText(/problem/)).toBeNull();
  });

  it("switches examples", async () => {
    const user = userEvent.setup();
    render(<Playground />);
    await user.selectOptions(screen.getByLabelText("Example"), EXAMPLES[1].id);
    expect(screen.getByLabelText("OCaml code")).toHaveValue(EXAMPLES[1].code);
  });

  it("explains when the toplevel cannot be loaded", async () => {
    mocks.ready.mockRejectedValue(
      new Error("Could not load /playground/toplevel.js: 404"),
    );
    render(<Playground />);
    await waitFor(() =>
      expect(screen.getByRole("status")).toHaveTextContent(
        "Could not load /playground/toplevel.js",
      ),
    );
    expect(screen.getByRole("button", { name: /run/i })).toBeDisabled();
  });
});
