import type { Directory } from "../api/types";

/** "1024 × 768" for tab labels; "?" for a dimension that was not read from the file. */
export function directoryDimensions(dir: Directory): string {
  const dim = (f: Directory["width"]) =>
    (f.status === "present" || f.status === "default") && f.value !== null
      ? String(f.value)
      : "?";
  return `${dim(dir.width)} × ${dim(dir.height)}`;
}

/** PlanarConfiguration code: 1 = contiguous (chunky), 2 = separate (planar), null = unknown. */
export function planarCode(dir: Directory): number | null {
  const v = dir.planar_configuration.value;
  return dir.planar_configuration.status === "absent" || v === null
    ? null
    : v.code;
}

/** Element IDs linking the IFD tabs to their tab panel. */
export const tabId = (prefix: string, i: number) => `${prefix}-tab-${i}`;
export const panelId = (prefix: string) => `${prefix}-panel`;
