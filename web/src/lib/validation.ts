import { ACCEPTED_EXTENSIONS, MAX_UPLOAD_BYTES } from "./constants";
import { formatBytes } from "./format";

/**
 * Client-side checks exist only to give fast, specific feedback.
 * The server re-validates everything.
 */
export type ValidationFailure = {
  ok: false;
  reason: "extension" | "empty" | "size" | "signature" | "unreadable";
  message: string;
};

export type ValidationResult = { ok: true } | ValidationFailure;

/** `II*\0`, `MM\0*` (classic TIFF) and `II+\0`, `MM\0+` (BigTIFF). */
const SIGNATURES: readonly (readonly number[])[] = [
  [0x49, 0x49, 0x2a, 0x00],
  [0x4d, 0x4d, 0x00, 0x2a],
  [0x49, 0x49, 0x2b, 0x00],
  [0x4d, 0x4d, 0x00, 0x2b],
];

/** "a, b or c" for user-facing lists of the accepted extensions. */
export function formatAcceptedExtensions(): string {
  const exts = [...ACCEPTED_EXTENSIONS];
  const last = exts.pop();
  return `${exts.join(", ")} or ${last}`;
}

export function hasAcceptedExtension(name: string): boolean {
  const lower = name.toLowerCase();
  return ACCEPTED_EXTENSIONS.some((ext) => lower.endsWith(ext));
}

export function isTiffSignature(bytes: ArrayLike<number>): boolean {
  if (bytes.length < 4) return false;
  return SIGNATURES.some((sig) => sig.every((b, i) => bytes[i] === b));
}

export function validateFileMeta(
  file: Pick<File, "name" | "size">,
): ValidationResult {
  if (!hasAcceptedExtension(file.name)) {
    return {
      ok: false,
      reason: "extension",
      message: `“${file.name}” isn't a ${formatAcceptedExtensions()} file. Pick a TIFF and we'll take it from there.`,
    };
  }
  if (file.size === 0) {
    return {
      ok: false,
      reason: "empty",
      message: `“${file.name}” is empty (0 bytes), so there's nothing to inspect yet.`,
    };
  }
  if (file.size > MAX_UPLOAD_BYTES) {
    return {
      ok: false,
      reason: "size",
      message: `“${file.name}” is ${formatBytes(file.size)}, and uploads here are limited to ${formatBytes(MAX_UPLOAD_BYTES)}. The command-line tool handles any size.`,
    };
  }
  return { ok: true };
}

async function readHeader(blob: Blob): Promise<Uint8Array> {
  const head = blob.slice(0, 4);
  if (typeof head.arrayBuffer === "function") {
    return new Uint8Array(await head.arrayBuffer());
  }
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(new Uint8Array(reader.result as ArrayBuffer));
    reader.onerror = () => reject(reader.error ?? new Error("read failed"));
    reader.readAsArrayBuffer(head);
  });
}

export async function validateFile(file: File): Promise<ValidationResult> {
  const meta = validateFileMeta(file);
  if (!meta.ok) return meta;

  let header: Uint8Array;
  try {
    header = await readHeader(file);
  } catch {
    return {
      ok: false,
      reason: "unreadable",
      message: `Your browser couldn't read “${file.name}”. Try choosing it again.`,
    };
  }
  if (!isTiffSignature(header)) {
    return {
      ok: false,
      reason: "signature",
      message: `“${file.name}” has a TIFF name, but its contents don't start with a TIFF signature. It may be another format that was renamed; try the original file.`,
    };
  }
  return { ok: true };
}
