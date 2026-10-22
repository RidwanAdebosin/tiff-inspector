(* Encodes reports as JSON following schema/inspection-report.v1.json *)

open Report

type json = Yojson.Safe.t

let opt f = function Some v -> f v | None -> `Null
let str s = `String s
let int i = `Int i
let float f = if Float.is_finite f then `Float f else `Null
let list f l = `List (List.map f l)

let tool =
  `Assoc [ ("name", `String "tiff-inspector"); ("version", `String Version.v) ]

let field f (x : _ Field.t) =
  `Assoc
    [
      ("status", `String (Field.status_to_string x.status));
      ("value", opt f x.value);
      ("note", opt str x.note);
    ]

let enum (e : enum) =
  `Assoc
    [
      ("code", `Int e.code); ("name", opt str e.name); ("label", opt str e.label);
    ]

let error (e : Problem.error) =
  `Assoc
    [
      ("code", `String (Problem.code_to_string e.code));
      ("message", `String e.message);
    ]

let warning (w : Problem.warning) =
  `Assoc
    [
      ("code", `String w.w_code);
      ("message", `String w.w_message);
      ("directory", opt int w.directory);
      ("tag", opt int w.tag);
    ]

let tag_value = function
  | Integers l -> `Assoc [ ("kind", `String "integers"); ("items", list int l) ]
  | Floats l -> `Assoc [ ("kind", `String "floats"); ("items", list float l) ]
  | Rationals l ->
      `Assoc
        [
          ("kind", `String "rationals");
          ("items", list (fun (n, d) -> `List [ `Int n; `Int d ]) l);
        ]
  | Ascii s -> `Assoc [ ("kind", `String "ascii"); ("text", `String s) ]

let value_status = function
  | Decoded -> "decoded"
  | Truncated -> "truncated"
  | Unreadable -> "unreadable"
  | Unsupported_type -> "unsupported_type"

let tag (t : tag) =
  `Assoc
    [
      ("id", `Int t.id);
      ("name", opt str t.name);
      ("known", `Bool (Option.is_some t.name));
      ("field_type", enum t.field_type);
      ("count", `Int t.count);
      ("value", opt tag_value t.value);
      ("value_status", `String (value_status t.value_status));
      ("note", opt str t.note);
    ]

let layout (l : layout) =
  `Assoc
    [
      ( "kind",
        `String
          (match l.kind with
          | Strips -> "strips"
          | Tiles -> "tiles"
          | Unknown_layout -> "unknown") );
      ("rows_per_strip", opt (field int) l.rows_per_strip);
      ("tile_width", opt (field int) l.tile_width);
      ("tile_height", opt (field int) l.tile_height);
      ("chunk_count", `Int l.chunk_count);
      ("expected_chunk_count", opt int l.expected_chunk_count);
      ("offsets", list int l.offsets);
      ("byte_counts", list int l.byte_counts);
      ("total_bytes", opt int l.total_bytes);
      ("truncated", `Bool l.truncated);
    ]

let plane (p : plane) =
  `Assoc
    [
      ("index", `Int p.index);
      ("width", `Int p.width);
      ("height", `Int p.height);
      ("samples", list int p.samples);
      ("bits_per_sample", list int p.bits_per_sample);
    ]

let pixel_decoding (p : pixel_decoding) =
  `Assoc
    [
      ("status", `String "not_attempted");
      ( "library_support",
        `String
          (match p.library_support with
          | Supported -> "supported"
          | Unsupported -> "unsupported"
          | Unknown -> "unknown") );
      ("reason", opt str p.reason);
    ]

let directory (d : directory) =
  `Assoc
    [
      ("index", `Int d.index);
      ("offset", `Int d.offset);
      ("entry_count", `Int d.entry_count);
      ("width", field int d.width);
      ("height", field int d.height);
      ("samples_per_pixel", field int d.samples_per_pixel);
      ("bits_per_sample", field (list int) d.bits_per_sample);
      ("sample_format", field (list enum) d.sample_format);
      ("photometric_interpretation", field enum d.photometric_interpretation);
      ("planar_configuration", field enum d.planar_configuration);
      ("compression", field enum d.compression);
      ("predictor", field enum d.predictor);
      ("orientation", field enum d.orientation);
      ( "resolution",
        `Assoc
          [
            ("x", field float d.resolution.x);
            ("y", field float d.resolution.y);
            ("unit", field enum d.resolution.unit);
          ] );
      ("layout", layout d.layout);
      ("planes", list plane d.planes);
      ("pixel_decoding", pixel_decoding d.pixel_decoding);
      ("tags", list tag d.tags);
      ("warnings", list warning d.warnings);
    ]

let report (r : t) : json =
  `Assoc
    [
      ("schema_version", `String schema_version);
      ("ok", `Bool true);
      ("tool", tool);
      ( "file",
        `Assoc
          [
            ("name", `String r.file.name);
            ("size_bytes", `Int r.file.size_bytes);
            ( "byte_order",
              `String
                (match r.file.byte_order with
                | Little_endian -> "little_endian"
                | Big_endian -> "big_endian") );
            ( "format",
              `String
                (match r.file.format with
                | Classic_tiff -> "classic_tiff"
                | Bigtiff -> "bigtiff") );
            ("first_ifd_offset", `Int r.file.first_ifd_offset);
          ] );
      ("ifd_count", `Int r.ifd_count);
      ( "ifd_walk",
        `Assoc
          [
            ( "status",
              `String
                (match r.ifd_walk.status with
                | Complete -> "complete"
                | Truncated_at_limit -> "truncated_at_limit"
                | Failed -> "failed") );
            ("limit", `Int r.ifd_walk.limit);
            ("error", opt error r.ifd_walk.error);
          ] );
      ("directories", list directory r.directories);
      ("warnings", list warning r.warnings);
      ("limitations", list str r.limitations);
    ]

let failure (f : failure) : json =
  `Assoc
    [
      ("schema_version", `String schema_version);
      ("ok", `Bool false);
      ("tool", tool);
      ( "file",
        opt
          (fun (name, size) ->
            `Assoc [ ("name", `String name); ("size_bytes", opt int size) ])
          f.failed_file );
      ("error", error f.error);
    ]

let outcome = function Ok r -> report r | Error f -> failure f
let to_string json = Yojson.Safe.pretty_to_string ~std:true json ^ "\n"
