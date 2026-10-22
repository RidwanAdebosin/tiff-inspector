import { useId, useState } from "react";
import type { Tag } from "../api/types";
import { formatInteger, tagValueItems, tagValueLength } from "../lib/format";
import { COLLAPSE_CHARS, PREVIEW_ITEMS, isLongValue } from "../lib/tags";
import { Badge, type BadgeTone } from "./Badge";
import { linkButton } from "./styles";

const STATUS: Record<Exclude<Tag["value_status"], "decoded">, { tone: BadgeTone; text: string }> = {
  truncated: { tone: "warn", text: "truncated" },
  unreadable: { tone: "danger", text: "unreadable" },
  unsupported_type: { tone: "warn", text: "unsupported type" },
};

function preview(tag: Tag, expanded: boolean): string {
  const value = tag.value;
  if (value === null) return "";
  if (value.kind === "ascii") {
    return expanded || value.text.length <= COLLAPSE_CHARS ? value.text : `${value.text.slice(0, COLLAPSE_CHARS)}…`;
  }
  const items = tagValueItems(value);
  if (expanded || !isLongValue(tag)) return items.join(", ");
  return `${items.slice(0, PREVIEW_ITEMS).join(", ")}, …`;
}

export function TagValueCell({ tag }: { tag: Tag }) {
  const [expanded, setExpanded] = useState(false);
  const valueId = useId();
  const long = isLongValue(tag);
  const status = tag.value_status === "decoded" ? null : STATUS[tag.value_status];
  const shownCount = tag.value ? tagValueLength(tag.value) : 0;
  const unitWord = tag.value?.kind === "ascii" ? "characters" : "values";

  return (
    <div className="min-w-0 space-y-1">
      {tag.value === null ? (
        <span className="text-zinc-600 italic dark:text-zinc-400">no value</span>
      ) : (
        <span
          id={valueId}
          className={`block font-mono text-[0.8125rem] break-all ${tag.value.kind === "ascii" ? "whitespace-pre-wrap" : ""}`}
        >
          {preview(tag, expanded)}
        </span>
      )}
      {(long || status) && (
        <div className="flex flex-wrap items-center gap-2">
          {status && <Badge tone={status.tone}>{status.text}</Badge>}
          {tag.value_status === "truncated" && tag.value && tag.value.kind !== "ascii" && (
            <span className="text-xs text-zinc-600 dark:text-zinc-400">
              {formatInteger(shownCount)} of {formatInteger(tag.count)} values included
            </span>
          )}
          {long && (
            <button
              type="button"
              className={linkButton}
              aria-expanded={expanded}
              aria-controls={valueId}
              onClick={() => setExpanded((v) => !v)}
            >
              {expanded ? "Show less" : `Show all ${formatInteger(shownCount)} ${unitWord}`}
            </button>
          )}
        </div>
      )}
      {tag.note && <p className="text-xs text-zinc-600 dark:text-zinc-400">{tag.note}</p>}
    </div>
  );
}
