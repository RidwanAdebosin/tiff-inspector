import { fireEvent, render, screen } from "@testing-library/react";
import { createRef } from "react";
import { describe, expect, it, vi } from "vitest";
import { DropZone } from "./DropZone";

const file = (name: string) => new File(["II*\0"], name);

function setup(disabled = false) {
  const onFile = vi.fn();
  const onNote = vi.fn();
  render(
    <DropZone
      inputRef={createRef<HTMLInputElement>()}
      disabled={disabled}
      onFile={onFile}
      onNote={onNote}
    />,
  );
  const zone = screen.getByRole("button", {
    name: "Choose a TIFF file",
  }).parentElement!;
  const child = screen.getByText("or drag and drop it here");
  return { zone, child, onFile, onNote };
}

const dragging = (zone: HTMLElement) => zone.hasAttribute("data-dragging");

describe("DropZone highlight", () => {
  it("stays on while the drag crosses child elements (dragenter/dragleave depth)", () => {
    const { zone, child } = setup();
    fireEvent.dragEnter(zone);
    expect(dragging(zone)).toBe(true);

    // Moving over a child: the child fires dragenter (bubbles) and then the zone fires dragleave.
    fireEvent.dragEnter(child);
    fireEvent.dragLeave(zone);
    expect(dragging(zone)).toBe(true);

    // Leaving the child back onto the zone, then leaving the zone entirely.
    fireEvent.dragEnter(zone);
    fireEvent.dragLeave(child);
    expect(dragging(zone)).toBe(true);
    fireEvent.dragLeave(zone);
    expect(dragging(zone)).toBe(false);
  });

  it("ends on drop and on dragend regardless of depth", () => {
    const { zone, child } = setup();
    fireEvent.dragEnter(zone);
    fireEvent.dragEnter(child);
    fireEvent.drop(zone, { dataTransfer: { files: [file("a.tif")] } });
    expect(dragging(zone)).toBe(false);

    fireEvent.dragEnter(zone);
    fireEvent.dragEnter(child);
    fireEvent.dragEnd(zone);
    expect(dragging(zone)).toBe(false);
    // The counter was reset: a single leave is enough afterwards.
    fireEvent.dragEnter(zone);
    fireEvent.dragLeave(zone);
    expect(dragging(zone)).toBe(false);
  });

  it("never lights up while disabled", () => {
    const { zone } = setup(true);
    const dataTransfer = { dropEffect: "copy" };
    fireEvent.dragEnter(zone, { dataTransfer });
    fireEvent.dragOver(zone, { dataTransfer });
    expect(dragging(zone)).toBe(false);
    expect(dataTransfer.dropEffect).toBe("none");
  });
});

describe("DropZone drop feedback", () => {
  it("hands over a single file with no note", () => {
    const { zone, onFile, onNote } = setup();
    fireEvent.drop(zone, { dataTransfer: { files: [file("a.tif")] } });
    expect(onFile).toHaveBeenCalledTimes(1);
    expect((onFile.mock.calls[0]![0] as File).name).toBe("a.tif");
    expect(onNote).toHaveBeenCalledWith(null);
  });

  it("inspects only the first of several files and notes it", () => {
    const { zone, onFile, onNote } = setup();
    fireEvent.drop(zone, {
      dataTransfer: { files: [file("a.tif"), file("b.tif"), file("c.tif")] },
    });
    expect(onFile).toHaveBeenCalledTimes(1);
    expect((onFile.mock.calls[0]![0] as File).name).toBe("a.tif");
    expect(onNote).toHaveBeenCalledWith("Only the first file was inspected");
  });

  it("asks for a TIFF when no file is dropped (text or URL)", () => {
    const { zone, onFile, onNote } = setup();
    fireEvent.drop(zone, {
      dataTransfer: { files: [], types: ["text/uri-list"] },
    });
    expect(onFile).not.toHaveBeenCalled();
    expect(onNote).toHaveBeenCalledWith("Drop a .tif or .tiff file");
  });

  it("ignores drops while disabled", () => {
    const { zone, onFile, onNote } = setup(true);
    fireEvent.drop(zone, {
      dataTransfer: { files: [file("a.tif"), file("b.tif")] },
    });
    expect(onFile).not.toHaveBeenCalled();
    expect(onNote).not.toHaveBeenCalled();
  });

  it("clears the note when a file is picked through the input", () => {
    const { zone, onFile, onNote } = setup();
    fireEvent.drop(zone, {
      dataTransfer: { files: [], types: ["text/plain"] },
    });
    expect(onNote).toHaveBeenLastCalledWith("Drop a .tif or .tiff file");

    const input = screen.getByLabelText("TIFF file") as HTMLInputElement;
    fireEvent.change(input, { target: { files: [file("picked.tif")] } });
    expect(onFile).toHaveBeenCalledTimes(1);
    expect(onNote).toHaveBeenLastCalledWith(null);
  });

  it("accepts the BigTIFF extensions in the file picker", () => {
    setup();
    expect(screen.getByLabelText("TIFF file")).toHaveAttribute(
      "accept",
      ".tif,.tiff,.btf,.tf8,image/tiff",
    );
  });
});
