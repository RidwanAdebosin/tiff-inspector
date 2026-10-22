/** Name of the exported report for an uploaded file, e.g. `scan.tif.inspection.json`. */
export function reportFileName(originalName: string): string {
  return `${originalName}.inspection.json`;
}

/**
 * Save `text` exactly as given (no re-serialisation) as a file download.
 */
export function downloadText(text: string, filename: string, type = "application/json"): void {
  const blob = new Blob([text], { type });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.rel = "noopener";
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 0);
}
