import type { FieldStatus } from "../api/types";
import { formatFieldValue } from "../lib/format";
import { Badge } from "./Badge";

/** Structural shape shared by every FieldOf-derived type (IntField, EnumField, …). */
export type AnyField = {
  status: FieldStatus;
  value: unknown;
  note: string | null;
};

type FieldValueProps<F extends AnyField> = {
  field: F;
  /** Custom text for the value; defaults to formatFieldValue (handles numbers, lists, enums). */
  format?: (value: NonNullable<F["value"]>) => string;
  unit?: string;
};

const DEFAULT_NOTE =
  "Tag not present in the file; this is the TIFF specification default, not a value read from the file.";

function Note({ text }: { text: string | null }) {
  if (!text) return null;
  return (
    <span className="text-xs text-stone-600 dark:text-stone-400">{text}</span>
  );
}

/**
 * Renders any FieldOf value. Only `present` values are shown as plain facts;
 * every other status is labelled so inferred or missing values are never
 * mistaken for data read from the file.
 */
export function FieldValue<F extends AnyField>({
  field,
  format,
  unit,
}: FieldValueProps<F>) {
  const { status, value, note } = field;
  const text =
    value === null || value === undefined
      ? null
      : format
        ? format(value as NonNullable<F["value"]>)
        : formatFieldValue(value);
  const rendered = text !== null && (
    <span className="font-mono text-[0.8125rem]">
      {text}
      {unit && (
        <span className="text-stone-600 dark:text-stone-400"> {unit}</span>
      )}
    </span>
  );

  return (
    <span
      data-status={status}
      className="inline-flex flex-wrap items-baseline gap-x-2 gap-y-1"
    >
      {status === "present" && (
        <>
          {rendered || (
            <span className="text-stone-600 italic dark:text-stone-400">
              no value
            </span>
          )}
          <Note text={note} />
        </>
      )}
      {status === "default" && (
        <>
          {rendered}
          <Badge tone="info" title={note ?? DEFAULT_NOTE}>
            spec default
          </Badge>
          <Note text={note ?? DEFAULT_NOTE} />
        </>
      )}
      {status === "absent" && (
        <>
          <span className="text-stone-600 italic dark:text-stone-400">
            not present
          </span>
          <Note text={note} />
        </>
      )}
      {status === "unsupported" && (
        <>
          <Badge tone="warn">unsupported</Badge>
          {rendered}
          <Note text={note} />
        </>
      )}
      {status === "error" && (
        <>
          <Badge tone="danger">error</Badge>
          {rendered}
          <Note text={note ?? "The value could not be read."} />
        </>
      )}
    </span>
  );
}
