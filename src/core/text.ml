(* Human-readable report rendering (FR-CLI-02) *)

open Report

let pp_enum ppf (e : enum) =
  match e.label with
  | Some l -> Fmt.pf ppf "%s (%d)" l e.code
  | None -> Fmt.pf ppf "Unknown (code %d)" e.code

(* Renders a field, marking anything not read directly from a tag *)
let pp_field pp ppf (f : _ Field.t) =
  let note ppf = function Some n -> Fmt.pf ppf " - %s" n | None -> () in
  match (f.status, f.value) with
  | Present, Some v -> pp ppf v
  | Default, Some v -> Fmt.pf ppf "%a (default, tag absent)" pp v
  | Absent, _ -> Fmt.pf ppf "unknown (tag absent)%a" note f.note
  | Unsupported, _ -> Fmt.pf ppf "unsupported%a" note f.note
  | Error, _ -> Fmt.pf ppf "error%a" note f.note
  | (Present | Default), None -> Fmt.string ppf "unknown"

let int_list = Fmt.(list ~sep:(any ", ") int)
let enum_list = Fmt.(list ~sep:(any ", ") pp_enum)

let pp_size ppf n =
  if n < 1024 then Fmt.pf ppf "%d bytes" n
  else if n < 1024 * 1024 then
    Fmt.pf ppf "%d bytes (%.1f KiB)" n (float n /. 1024.)
  else Fmt.pf ppf "%d bytes (%.1f MiB)" n (float n /. 1048576.)

let section ppf title =
  Fmt.pf ppf "@,%s@,%s@," title (String.make (String.length title) '-')

let row ppf label pp v = Fmt.pf ppf "%s: %a@," label pp v

let pp_tag_value ppf = function
  | Integers l -> int_list ppf l
  | Floats l -> Fmt.(list ~sep:(any ", ") float) ppf l
  | Rationals l ->
      Fmt.(list ~sep:(any ", ") (pair ~sep:(any "/") int int)) ppf l
  | Ascii s -> Fmt.pf ppf "%S" s

let short s = if String.length s > 60 then String.sub s 0 57 ^ "..." else s

let pp_tags ppf tags =
  Fmt.pf ppf "%-8s %-28s %-10s %8s  %s@," "ID" "Name" "Type" "Count" "Value";
  List.iter
    (fun (t : tag) ->
      let value =
        match (t.value, t.value_status) with
        | Some v, Decoded -> short (Fmt.str "%a" pp_tag_value v)
        | Some v, _ ->
            short
              (Fmt.str "%a (%s)" pp_tag_value v
                 (Option.value ~default:"" t.note))
        | None, _ -> Fmt.str "<%s>" (Option.value ~default:"unreadable" t.note)
      in
      Fmt.pf ppf "%-8d %-28s %-10s %8d  %s@," t.id
        (Option.value ~default:"(unknown)" t.name)
        (Option.value
           ~default:(string_of_int t.field_type.code)
           t.field_type.name)
        t.count value)
    tags

let pp_warning ppf (w : Problem.warning) =
  Fmt.pf ppf "- [%s] %s@," w.w_code w.w_message

let pp_directory ~tags ~multi ppf (d : directory) =
  if multi then
    Fmt.pf ppf "@,=== Directory %d (offset %d, %d entries) ===@," d.index
      d.offset d.entry_count;
  section ppf "Image";
  row ppf "Width" (pp_field Fmt.int) d.width;
  row ppf "Height" (pp_field Fmt.int) d.height;
  section ppf "Samples";
  row ppf "Samples per pixel" (pp_field Fmt.int) d.samples_per_pixel;
  row ppf "Sample format" (pp_field enum_list) d.sample_format;
  row ppf "Bits per sample" (pp_field int_list) d.bits_per_sample;
  section ppf "Storage";
  row ppf "Photometric interpretation" (pp_field pp_enum)
    d.photometric_interpretation;
  row ppf "Planar configuration" (pp_field pp_enum) d.planar_configuration;
  row ppf "Compression" (pp_field pp_enum) d.compression;
  row ppf "Predictor" (pp_field pp_enum) d.predictor;
  let l = d.layout in
  (match l.kind with
  | Strips ->
      Option.iter (row ppf "Rows per strip" (pp_field Fmt.int)) l.rows_per_strip;
      row ppf "Strips" Fmt.int l.chunk_count
  | Tiles ->
      Option.iter (row ppf "Tile width" (pp_field Fmt.int)) l.tile_width;
      Option.iter (row ppf "Tile height" (pp_field Fmt.int)) l.tile_height;
      row ppf "Tiles" Fmt.int l.chunk_count
  | Unknown_layout -> row ppf "Layout" Fmt.string "unknown");
  Option.iter (row ppf "Image data" pp_size) l.total_bytes;
  section ppf "Planes";
  (match d.planes with
  | [] -> Fmt.pf ppf "Not determinable@,"
  | planes ->
      List.iter
        (fun (p : plane) ->
          Fmt.pf ppf "Plane %d: %dx%d, samples [%a], bits [%a]@," p.index
            p.width p.height int_list p.samples int_list p.bits_per_sample)
        planes);
  section ppf "Other";
  row ppf "Orientation" (pp_field pp_enum) d.orientation;
  row ppf "X resolution" (pp_field Fmt.float) d.resolution.x;
  row ppf "Y resolution" (pp_field Fmt.float) d.resolution.y;
  row ppf "Resolution unit" (pp_field pp_enum) d.resolution.unit;
  row ppf "Pixel decoding (ocaml-tiff)" Fmt.string
    (match d.pixel_decoding with
    | { library_support = Supported; _ } -> "supported (not attempted)"
    | { library_support = Unsupported; reason } ->
        "unsupported: " ^ Option.value ~default:"" reason
    | { library_support = Unknown; reason } ->
        "unknown: " ^ Option.value ~default:"" reason);
  if tags then (
    section ppf "Tags";
    pp_tags ppf d.tags);
  if d.warnings <> [] then (
    section ppf "Warnings";
    List.iter (pp_warning ppf) d.warnings)

let pp_report ?(tags = false) ?only ppf (r : t) =
  Fmt.pf ppf "@[<v>TIFF INSPECTOR@,==============@,@,";
  row ppf "File" Fmt.string r.file.name;
  row ppf "File size" pp_size r.file.size_bytes;
  row ppf "Byte order" Fmt.string
    (match r.file.byte_order with
    | Little_endian -> "Little-endian"
    | Big_endian -> "Big-endian");
  row ppf "Format" Fmt.string
    (match r.file.format with
    | Classic_tiff -> "Classic TIFF"
    | Bigtiff -> "BigTIFF");
  row ppf "Image directories" Fmt.int r.ifd_count;
  let dirs =
    match only with
    | None -> r.directories
    | Some i -> List.filter (fun (d : directory) -> d.index = i) r.directories
  in
  let multi = r.ifd_count > 1 || only <> None in
  List.iter (pp_directory ~tags ~multi ppf) dirs;
  if r.warnings <> [] then (
    section ppf "File warnings";
    List.iter (pp_warning ppf) r.warnings);
  Fmt.pf ppf "@]"

let report ?tags ?only r = Fmt.str "%a@." (pp_report ?tags ?only) r

let failure (f : failure) =
  Fmt.str "tiff-inspector: %s: %s"
    (Problem.describe f.error.code)
    f.error.message
