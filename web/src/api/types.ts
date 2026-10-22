/* eslint-disable */
/**
 * GENERATED FILE — DO NOT EDIT.
 *
 * Source: schema/inspection-report.v1.json
 * Regenerate with `npm run gen:types`; CI verifies it with `npm run check:types`.
 */

/**
 * Output of `tiff-inspector inspect --format json` and of POST /api/v1/inspections. Version 1.x; additive changes bump the minor version, breaking changes create v2.
 */
export type InspectionReport = SuccessReport | FailureReport;
export type ErrorCode =
  | "file_not_found"
  | "file_unreadable"
  | "not_a_tiff"
  | "truncated"
  | "malformed"
  | "unsupported_feature"
  | "pixel_decode_failed"
  | "limit_exceeded"
  | "internal"
  | "invalid_request"
  | "file_too_large"
  | "rate_limited";
/**
 * present: read from a tag. default: tag absent, TIFF spec default applied. absent: tag absent, no default. unsupported: present but cannot be interpreted. error: reading failed.
 */
export type FieldStatus = "present" | "default" | "absent" | "unsupported" | "error";
export type TagValue =
  | {
      kind: "integers";
      items: number[];
    }
  | {
      kind: "floats";
      /**
       * Non-finite values (NaN, infinity) are null.
       */
      items: (number | null)[];
    }
  | {
      kind: "rationals";
      items: [number, number][];
    }
  | {
      kind: "ascii";
      text: string;
    };

export interface SuccessReport {
  schema_version: "1.0";
  ok: true;
  tool: Tool;
  file: FileInfo;
  ifd_count: number;
  ifd_walk: IfdWalk;
  directories: Directory[];
  warnings: Problem[];
  limitations: string[];
}
export interface Tool {
  name: "tiff-inspector";
  version: string;
}
export interface FileInfo {
  name: string;
  size_bytes: number;
  byte_order: "little_endian" | "big_endian";
  format: "classic_tiff" | "bigtiff";
  first_ifd_offset: number;
}
export interface IfdWalk {
  status: "complete" | "truncated_at_limit" | "failed";
  limit: number;
  error: ReportError | null;
}
export interface ReportError {
  code: ErrorCode;
  message: string;
}
export interface Directory {
  index: number;
  offset: number;
  entry_count: number;
  width: IntField;
  height: IntField;
  samples_per_pixel: IntField;
  bits_per_sample: IntListField;
  /**
   * One entry per sample.
   */
  sample_format: EnumListField;
  photometric_interpretation: EnumField;
  planar_configuration: EnumField;
  compression: EnumField;
  predictor: EnumField;
  orientation: EnumField;
  resolution: {
    x: NumberField;
    y: NumberField;
    unit: EnumField;
  };
  layout: Layout;
  planes: Plane[];
  pixel_decoding: PixelDecoding;
  tags: Tag[];
  warnings: Problem[];
}
export interface IntField {
  status: FieldStatus;
  value: number | null;
  note: string | null;
}
export interface IntListField {
  status: FieldStatus;
  value: number[] | null;
  note: string | null;
}
export interface EnumListField {
  status: FieldStatus;
  value: Enum[] | null;
  note: string | null;
}
/**
 * A coded TIFF value. `name` (stable snake_case) and `label` (human-readable) are null when the code is not recognised.
 */
export interface Enum {
  code: number;
  name: string | null;
  label: string | null;
}
export interface EnumField {
  status: FieldStatus;
  value: Enum | null;
  note: string | null;
}
export interface NumberField {
  status: FieldStatus;
  value: number | null;
  note: string | null;
}
export interface Layout {
  kind: "strips" | "tiles" | "unknown";
  rows_per_strip: IntField | null;
  tile_width: IntField | null;
  tile_height: IntField | null;
  /**
   * Number of strips or tiles listed in the file.
   */
  chunk_count: number;
  /**
   * Derived from dimensions; null when not determinable.
   */
  expected_chunk_count: number | null;
  offsets: number[];
  byte_counts: number[];
  total_bytes: number | null;
  /**
   * True when offsets/byte_counts were cut to the inline value limit.
   */
  truncated: boolean;
}
export interface Plane {
  index: number;
  width: number;
  height: number;
  /**
   * Sample indices stored in this plane.
   */
  samples: number[];
  bits_per_sample: number[];
}
export interface PixelDecoding {
  /**
   * Version 1 never decodes pixels.
   */
  status: "not_attempted";
  /**
   * Static assessment of whether ocaml-tiff's decoder handles this directory.
   */
  library_support: "supported" | "unsupported" | "unknown";
  reason: string | null;
}
export interface Tag {
  id: number;
  name: string | null;
  /**
   * Whether the tag ID is in tiff-inspector's registry.
   */
  known: boolean;
  field_type: Enum;
  count: number;
  value: TagValue | null;
  value_status: "decoded" | "truncated" | "unreadable" | "unsupported_type";
  note: string | null;
}
/**
 * A non-fatal warning. `code` is a stable snake_case identifier; `message` is for humans.
 */
export interface Problem {
  code: string;
  message: string;
  directory: number | null;
  tag: number | null;
}
export interface FailureReport {
  schema_version: "1.0";
  ok: false;
  tool: Tool;
  /**
   * Whatever is known about the file; null when it could not be opened.
   */
  file: {
    name: string;
    size_bytes: number | null;
  } | null;
  error: ReportError;
}
