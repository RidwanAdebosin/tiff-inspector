import type { Tag } from "../api/types";
import { formatHex, tagValueLength, tagValueToString } from "./format";

/** Case-insensitive match over decimal ID, hex ID, name, field type and value text. */
export function tagMatches(tag: Tag, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  const haystack = [
    String(tag.id),
    formatHex(tag.id),
    tag.id.toString(16),
    tag.name ?? "unknown",
    tag.field_type.name ?? "",
    tagValueToString(tag.value),
  ]
    .join("\u0000")
    .toLowerCase();
  return haystack.includes(q);
}

/** Item/character thresholds above which a tag value starts collapsed. */
export const COLLAPSE_ITEMS = 16;
export const COLLAPSE_CHARS = 120;
export const PREVIEW_ITEMS = 8;

export function isLongValue(tag: Tag): boolean {
  if (tag.value === null) return false;
  const len = tagValueLength(tag.value);
  return tag.value.kind === "ascii"
    ? len > COLLAPSE_CHARS
    : len > COLLAPSE_ITEMS;
}
