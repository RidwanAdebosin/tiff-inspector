(* The public inspection model. It mirrors schema/inspection-report.v1.json and
   never exposes ocaml-tiff types. *)

let schema_version = "1.0"

type enum = {
  code : int;
  name : string option;  (** Stable snake_case name, [None] if unrecognised *)
  label : string option;  (** Human-readable label, not serialised *)
}

let enum table code =
  {
    code;
    name = Tag_registry.name table code;
    label = Tag_registry.label table code;
  }

type tag_value =
  | Integers of int list
  | Floats of float list
  | Rationals of (int * int) list
  | Ascii of string

type value_status = Decoded | Truncated | Unreadable | Unsupported_type

type tag = {
  id : int;
  name : string option;
  field_type : enum;
  count : int;
  value : tag_value option;
  value_status : value_status;
  note : string option;
}

type layout_kind = Strips | Tiles | Unknown_layout

type layout = {
  kind : layout_kind;
  rows_per_strip : int Field.t option;
  tile_width : int Field.t option;
  tile_height : int Field.t option;
  chunk_count : int;
  expected_chunk_count : int option;
  offsets : int list;
  byte_counts : int list;
  total_bytes : int option;
  truncated : bool;
}

type plane = {
  index : int;
  width : int;
  height : int;
  samples : int list;
  bits_per_sample : int list;
}

type library_support = Supported | Unsupported | Unknown

type pixel_decoding = {
  library_support : library_support;
  reason : string option;
}

type resolution = { x : float Field.t; y : float Field.t; unit : enum Field.t }

type directory = {
  index : int;
  offset : int;
  entry_count : int;
  width : int Field.t;
  height : int Field.t;
  samples_per_pixel : int Field.t;
  bits_per_sample : int list Field.t;
  sample_format : enum list Field.t;
  photometric_interpretation : enum Field.t;
  planar_configuration : enum Field.t;
  compression : enum Field.t;
  predictor : enum Field.t;
  orientation : enum Field.t;
  resolution : resolution;
  layout : layout;
  planes : plane list;
  pixel_decoding : pixel_decoding;
  tags : tag list;
  warnings : Problem.warning list;
}

type byte_order = Little_endian | Big_endian
type format = Classic_tiff | Bigtiff

type file_info = {
  name : string;
  size_bytes : int;
  byte_order : byte_order;
  format : format;
  first_ifd_offset : int;
}

type walk_status = Complete | Truncated_at_limit | Failed

type ifd_walk = {
  status : walk_status;
  limit : int;
  error : Problem.error option;
}

type t = {
  file : file_info;
  ifd_count : int;
  ifd_walk : ifd_walk;
  directories : directory list;
  warnings : Problem.warning list;
  limitations : string list;
}

type failure = {
  failed_file : (string * int option) option;
  error : Problem.error;
}
