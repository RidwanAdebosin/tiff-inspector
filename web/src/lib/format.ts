import type { Enum, FileInfo, TagValue } from "../api/types";

const UNITS = ["KB", "MB", "GB"] as const;

/** Human-readable byte size using binary (1024) multiples, e.g. "25 MB". */
export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 1024) return `${bytes} B`;
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < UNITS.length - 1) {
    value /= 1024;
    unit += 1;
  }
  const rounded =
    value >= 100 || Number.isInteger(value)
      ? Math.round(value)
      : Number(value.toFixed(1));
  return `${rounded} ${UNITS[unit]}`;
}

export function formatInteger(n: number): string {
  return n.toLocaleString("en-US");
}

/** Exact byte count with grouping, e.g. "1,048,576 bytes". */
export function formatExactBytes(n: number): string {
  return `${formatInteger(n)} ${n === 1 ? "byte" : "bytes"}`;
}

/** "0x0100" for 256; at least 4 hex digits, uppercase. */
export function formatHex(n: number): string {
  return `0x${n.toString(16).toUpperCase().padStart(4, "0")}`;
}

/** Coded TIFF value: "RGB (2)", or "Unknown (code 5)" when the name is not recognised. */
export function formatEnum(e: Enum): string {
  const text = e.label ?? e.name;
  return text === null ? `Unknown (code ${e.code})` : `${text} (${e.code})`;
}

export function formatByteOrder(order: FileInfo["byte_order"]): string {
  return order === "little_endian" ? "Little-endian (II)" : "Big-endian (MM)";
}

export function formatTiffFormat(format: FileInfo["format"]): string {
  return format === "bigtiff" ? "BigTIFF" : "Classic TIFF";
}

export function formatNumber(n: number): string {
  if (Number.isInteger(n)) return formatInteger(n);
  return String(Number(n.toPrecision(10)));
}

export function isEnum(v: unknown): v is Enum {
  return (
    typeof v === "object" &&
    v !== null &&
    "code" in v &&
    "name" in v &&
    !Array.isArray(v)
  );
}

/** Render any FieldOf value (integer, number, list, enum, enum list) as text. */
export function formatFieldValue(value: unknown): string {
  if (value === null || value === undefined) return "—";
  if (Array.isArray(value)) return value.map(formatFieldValue).join(", ");
  if (isEnum(value)) return formatEnum(value);
  if (typeof value === "number") return formatNumber(value);
  return String(value);
}

/** Display text for float items the server encodes as null (NaN or ±infinity). */
export const NON_FINITE = "NaN/∞ (non-finite)";

/** Number of displayable items in a tag value (characters for ASCII). */
export function tagValueLength(value: TagValue): number {
  return value.kind === "ascii" ? value.text.length : value.items.length;
}

export function tagValueItems(value: TagValue): string[] {
  switch (value.kind) {
    case "integers":
      return value.items.map((n) => String(n));
    case "floats":
      return value.items.map((n) =>
        n === null ? NON_FINITE : formatNumber(n),
      );
    case "rationals":
      return value.items.map(([num, den]) =>
        den === 0 ? `${num}/0` : `${num}/${den}`,
      );
    case "ascii":
      return [value.text];
  }
}

/** Full single-line text of a tag value, used for display and search. */
export function tagValueToString(value: TagValue | null): string {
  if (value === null) return "";
  if (value.kind === "ascii") return value.text;
  return tagValueItems(value).join(", ");
}
