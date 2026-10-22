(* Walks the IFD chain with ocaml-tiff and builds the inspection report *)

module Ifd = Tiff.Ifd

type limits = {
  max_ifds : int;
  max_tag_values : int;  (** Values shown per tag in the tag table *)
  max_layout_values : int;  (** Offsets/byte counts listed per directory *)
  max_samples : int;
}

let default_limits =
  {
    max_ifds = 1024;
    max_tag_values = 64;
    max_layout_values = 256;
    max_samples = 1024;
  }

let limitations =
  [
    "Pixel data is not decoded in schema v1; pixel_decoding.library_support is \
     a static assessment of ocaml-tiff's decoder.";
    "Only the main IFD chain is followed; SubIFDs, EXIF and GPS directories \
     are not traversed.";
    "A directory containing an entry with an unknown field type cannot be \
     parsed by ocaml-tiff.";
    "Tag values are shown up to a fixed limit (ASCII up to 4096 bytes); longer \
     values are marked truncated.";
  ]

let tag_width = 256
let tag_height = 257
let tag_bits = 258
let tag_compression = 259
let tag_photometric = 262
let tag_strip_offsets = 273
let tag_orientation = 274
let tag_spp = 277
let tag_rows_per_strip = 278
let tag_strip_byte_counts = 279
let tag_x_res = 282
let tag_y_res = 283
let tag_planar = 284
let tag_res_unit = 296
let tag_predictor = 317
let tag_tile_width = 322
let tag_tile_height = 323
let tag_tile_offsets = 324
let tag_tile_byte_counts = 325
let tag_sample_format = 339

(* {1 Header} *)

let signatures = [ "II*\000"; "MM\000*"; "II+\000"; "MM\000+" ]

let check_signature (src : Source.t) =
  let n = min src.size 4 in
  let prefix = Cstruct.to_string (Source.read src ~offset:0 ~length:n) in
  if src.size = 0 then Error (Problem.error Not_a_tiff "The file is empty")
  else if
    List.exists (fun s -> String.starts_with ~prefix s) signatures && n = 4
  then Ok ()
  else if List.exists (fun s -> String.starts_with ~prefix s) signatures then
    Error (Problem.error Truncated "The file ends inside the TIFF header")
  else
    Error
      (Problem.error Not_a_tiff
         "The file does not start with a TIFF signature (II*, MM*, or BigTIFF \
          II+/MM+)")

let read_header (src : Source.t) =
  match check_signature src with
  | Error e -> Error e
  | Ok () -> (
      match Guard.run (fun () -> Ifd.read_header src.ro) with
      | Ok h -> Ok h
      | Error { code = Malformed; message } ->
          Error (Problem.error Not_a_tiff "%s" message)
      | Error e -> Error e)

(* {1 Preflight}

   ocaml-tiff allocates buffers from counts found in the file before reading
   them, and parses every entry eagerly. Check the parts it reads eagerly so a
   crafted file is rejected before it can trigger a huge allocation.

   Returns the raw value/offset field of every entry, in entry order, which
   [Decode] uses instead of ocaml-tiff's decoded inline values. *)

let preflight (src : Source.t) (header : Ifd.header) offset =
  let bigtiff = match header.kind with Bigtiff -> true | Tiff -> false in
  let count_size, entry_size, next_size =
    if bigtiff then (8, 20, 8) else (2, 12, 4)
  in
  let word_size = if bigtiff then 8 else 4 in
  let e = header.byte_order in
  let fail code fmt =
    Fmt.kstr (fun m -> Error (Problem.error code "%s" m)) fmt
  in
  if offset < 8 || offset >= src.size then
    fail Malformed "IFD offset %d points outside the file (%d bytes)" offset
      src.size
  else if offset > src.size - count_size then
    fail Truncated "The file ends inside the IFD at offset %d" offset
  else
    let buf = Source.read src ~offset ~length:count_size in
    let count =
      if bigtiff then Tiff.Endian.uint64 e buf |> Int64.to_int
      else Tiff.Endian.uint16 e buf
    in
    let table = (count * entry_size) + next_size in
    if count < 0 || count > 65535 || table > src.size - offset - count_size then
      fail Truncated
        "IFD at offset %d declares %d entries, which do not fit in the file"
        offset count
    else
      let entries =
        Source.read src ~offset:(offset + count_size)
          ~length:(count * entry_size)
      in
      let words =
        Array.init count (fun i ->
            Cstruct.sub entries ((i * entry_size) + 4 + word_size) word_size)
      in
      let rec check i =
        if i = count then Ok words
        else
          let base = i * entry_size in
          let tag = Tiff.Endian.uint16 ~offset:base e entries in
          let ftype = Tiff.Endian.uint16 ~offset:(base + 2) e entries in
          let n =
            if bigtiff then
              Tiff.Endian.uint64 ~offset:(base + 4) e entries |> Int64.to_int
            else
              Tiff.Endian.uint32 ~offset:(base + 4) e entries
              |> Int32.to_int |> ( land ) 0xFFFF_FFFF
          in
          match Tag_registry.field_type_size ftype with
          | None ->
              fail Unsupported_feature
                "Tag %d uses unknown field type %d; ocaml-tiff cannot parse \
                 this directory"
                tag ftype
          | Some size
            when (tag = tag_strip_offsets || tag = tag_strip_byte_counts)
                 && (n < 0 || n > src.size / size) ->
              fail Malformed
                "Tag %d declares %d values, more than the file could contain"
                tag n
          | Some _ -> check (i + 1)
      in
      check 0

(* {1 Field interpretation} *)

type dir_ctx = {
  ctx : Decode.ctx;
  ifd : Ifd.t;
  entries : (Ifd.entry * Cstruct.t) list;
      (** Each entry with its raw value/offset field, from [preflight] *)
  index : int;
  limits : limits;
  mutable warnings : Problem.warning list;
}

let find d id = List.find_opt (fun (e, _) -> Ifd.entry_tag_id e = id) d.entries

let warn d ?tag code fmt =
  Fmt.kstr
    (fun m ->
      d.warnings <-
        Problem.warning ~directory:d.index ?tag code "%s" m :: d.warnings)
    fmt

let ints d ?(max = 1) id =
  match find d id with
  | None -> None
  | Some (entry, word) -> Some (Decode.ints d.ctx ~max_items:max ~word entry)

let int_field ?default d id =
  match ints d id with
  | None -> (
      match default with Some v -> Field.default v | None -> Field.absent ())
  | Some (Ok (v :: _)) -> Field.present v
  | Some (Ok []) -> Field.error "tag has no values"
  | Some (Error m) -> Field.unsupported m

let enum_field ?default d table id =
  Field.map (Report.enum table) (int_field ?default d id)

(* A per-sample list: SampleFormat and BitsPerSample have one value per sample *)
let per_sample_field d id ~spp ~default ~name =
  match ints d ~max:d.limits.max_samples id with
  | None -> (
      match (spp, default) with
      | Some n, Some v when n <= d.limits.max_samples ->
          Field.default (List.init n (fun _ -> v))
      | _ -> Field.absent ())
  | Some (Error m) -> Field.unsupported m
  | Some (Ok []) -> Field.error "tag has no values"
  | Some (Ok l) ->
      (match spp with
      | Some n when n <> List.length l ->
          warn d ~tag:id "sample_count_mismatch"
            "%s has %d values but SamplesPerPixel is %d" name (List.length l) n
      | _ -> ());
      Field.present l

let rational_field d id =
  match find d id with
  | None -> Field.absent ()
  | Some (entry, word) -> (
      match Decode.raw d.ctx ~max_items:1 ~word entry with
      | Error `Unsupported_type -> Field.unsupported "unknown field type"
      | Error (`Unreadable m) -> Field.error m
      | Ok r -> (
          match
            Decode.values d.ctx ~field_type:(Ifd.entry_field_type entry) r
          with
          | Rationals ((_, 0) :: _) -> Field.unsupported "zero denominator"
          | Rationals ((n, den) :: _) ->
              Field.present (float_of_int n /. float_of_int den)
          | Floats (f :: _) -> Field.present f
          | Integers (i :: _) -> Field.present (float_of_int i)
          | _ -> Field.unsupported "expected a rational value"))

(* Compares a value we interpreted with ocaml-tiff's own accessor *)
let crosscheck d ~what ~pp ours lib =
  match (ours.Field.status, ours.value) with
  | Present, Some v -> (
      match Guard.run lib with
      | Ok l when l = v -> ()
      | Ok l ->
          warn d "library_mismatch"
            "ocaml-tiff reports %s = %a, the file says %a" what pp l pp v
      | Error e ->
          warn d "library_error" "ocaml-tiff could not read %s: %s" what
            e.Problem.message)
  | _ -> ()

(* {1 Storage layout} *)

let layout d ~width ~height ~spp ~planar : Report.layout =
  let planes = match planar with Some 2 -> spp | _ -> Some 1 in
  let div_up a b = (a + b - 1) / b in
  let list id =
    match find d id with
    | None -> None
    | Some (entry, word) -> (
        let total = Ifd.entry_count entry |> Int64.to_int in
        match Decode.ints d.ctx ~max_items:total ~word entry with
        | Ok l -> Some (Ok l)
        | Error m ->
            warn d ~tag:id "unreadable_layout" "%s" m;
            Some (Error total))
  in
  let mk kind ~rows ~tw ~th ~expected offsets counts : Report.layout =
    let resolved = function Some (Ok l) -> l | _ -> [] in
    let offs = resolved offsets and cnts = resolved counts in
    let chunk_count =
      match offsets with
      | Some (Ok l) -> List.length l
      | Some (Error n) -> n
      | None -> 0
    in
    (match expected with
    | Some e when e <> chunk_count ->
        warn d "chunk_count_mismatch"
          "Expected %d %s from the image dimensions, the file lists %d" e
          (if kind = Report.Tiles then "tiles" else "strips")
          chunk_count
    | _ -> ());
    let n_offs = List.length offs and n_cnts = List.length cnts in
    if n_cnts <> n_offs then
      warn d "offset_count_mismatch" "%d offsets but %d byte counts" n_offs
        n_cnts;
    (* Pairs up to the shorter list, in linear time *)
    let rec zip acc offs cnts =
      match (offs, cnts) with
      | o :: offs, c :: cnts -> zip ((o, c) :: acc) offs cnts
      | _ -> List.rev acc
    in
    let out_of_bounds =
      zip [] offs cnts
      |> List.filter (fun (o, c) -> o < 0 || c < 0 || o > d.ctx.source.size - c)
    in
    (match out_of_bounds with
    | [] -> ()
    | (o, c) :: _ ->
        warn d "chunk_out_of_bounds"
          "%d data chunk(s) extend past the end of the file (first: offset %d, \
           %d bytes; file is %d bytes)"
          (List.length out_of_bounds)
          o c d.ctx.source.size);
    let take l = List.filteri (fun i _ -> i < d.limits.max_layout_values) l in
    {
      kind;
      rows_per_strip = rows;
      tile_width = tw;
      tile_height = th;
      chunk_count;
      expected_chunk_count = expected;
      offsets = take offs;
      byte_counts = take cnts;
      total_bytes =
        (match counts with
        | Some (Ok l) -> Some (List.fold_left ( + ) 0 l)
        | _ -> None);
      truncated =
        n_offs > d.limits.max_layout_values
        || n_cnts > d.limits.max_layout_values;
    }
  in
  let has id = Option.is_some (find d id) in
  if has tag_tile_offsets || has tag_tile_width then
    let tw = int_field d tag_tile_width and th = int_field d tag_tile_height in
    let expected =
      match (width, height, tw.value, th.value, planes) with
      | Some w, Some h, Some tw, Some th, Some p when tw > 0 && th > 0 ->
          Some (p * div_up w tw * div_up h th)
      | _ -> None
    in
    mk Tiles ~rows:None ~tw:(Some tw) ~th:(Some th) ~expected
      (list tag_tile_offsets)
      (list tag_tile_byte_counts)
  else if has tag_strip_offsets then
    let rows =
      match int_field d tag_rows_per_strip with
      | { status = Absent; _ } ->
          {
            (Field.default 0xFFFF_FFFF) with
            note = Some "spec default 2^32-1: the whole image is one strip";
          }
      | f -> f
    in
    let expected =
      match (height, rows.value, planes) with
      | Some h, Some r, Some p when r > 0 ->
          Some (p * div_up h (min r (max h 1)))
      | _ -> None
    in
    mk Strips ~rows:(Some rows) ~tw:None ~th:None ~expected
      (list tag_strip_offsets)
      (list tag_strip_byte_counts)
  else (
    warn d "no_image_data" "Neither strip nor tile offsets are present";
    {
      kind = Unknown_layout;
      rows_per_strip = None;
      tile_width = None;
      tile_height = None;
      chunk_count = 0;
      expected_chunk_count = None;
      offsets = [];
      byte_counts = [];
      total_bytes = None;
      truncated = false;
    })

(* {1 Planes and decoder support} *)

let planes ~width ~height ~spp ~planar ~bits : Report.plane list =
  match (width, height, spp, planar) with
  | Some width, Some height, Some spp, Some planar when spp <= 1024 -> (
      let bits_of i =
        match bits with Some l -> List.nth_opt l i | None -> None
      in
      let all = List.init spp Fun.id in
      match planar with
      | 2 ->
          List.map
            (fun i ->
              {
                Report.index = i;
                width;
                height;
                samples = [ i ];
                bits_per_sample = Option.to_list (bits_of i);
              })
            all
      | 1 ->
          [
            {
              index = 0;
              width;
              height;
              samples = all;
              bits_per_sample = List.filter_map bits_of all;
            };
          ]
      | _ -> [])
  | _ -> []

let pixel_support ~layout ~compression ~predictor ~planar ~bits ~formats :
    Report.pixel_decoding =
  match (compression, predictor, planar, bits, formats) with
  | Some c, Some p, Some planar, Some bits, Some formats ->
      let reasons =
        List.concat
          [
            (if planar = 1 || planar = 2 then []
             else [ "unknown planar configuration" ]);
            (match (layout, c) with
            | Report.Strips, (1 | 5 | 8 | 32946) | Tiles, 1 -> []
            | Tiles, _ -> [ "compressed tiles are not decoded" ]
            | _ -> [ Fmt.str "compression %d is not supported" c ]);
            (if p = 1 || p = 2 then [] else [ Fmt.str "predictor %d" p ]);
            (if List.for_all (fun b -> List.mem b [ 8; 16; 32; 64 ]) bits then
               []
             else [ "bit depths other than 8/16/32/64 are not supported" ]);
            (match List.sort_uniq compare formats with
            | [] | [ _ ] -> []
            | _ ->
                [
                  "mixed sample formats: ocaml-tiff exposes one SampleFormat \
                   per directory";
                ]);
            (if layout = Unknown_layout then [ "no image data" ] else []);
          ]
      in
      if reasons = [] then { library_support = Supported; reason = None }
      else
        {
          library_support = Unsupported;
          reason = Some (String.concat "; " reasons);
        }
  | _ ->
      {
        library_support = Unknown;
        reason = Some "required fields could not be determined";
      }

(* {1 Directories} *)

let directory ~limits ctx ~index ~offset ~words ifd : Report.directory =
  let entries = List.mapi (fun i e -> (e, words.(i))) (Ifd.entries ifd) in
  let d = { ctx; ifd; entries; index; limits; warnings = [] } in
  let width = int_field d tag_width and height = int_field d tag_height in
  List.iter
    (fun (f, name) ->
      if f.Field.status = Absent then
        warn d "missing_required_tag" "%s is required but missing" name)
    [ (width, "ImageWidth"); (height, "ImageLength") ];
  let spp = int_field ~default:1 d tag_spp in
  let bits =
    per_sample_field d tag_bits ~spp:spp.value ~default:(Some 1)
      ~name:"BitsPerSample"
  in
  let formats =
    per_sample_field d tag_sample_format ~spp:spp.value ~default:(Some 1)
      ~name:"SampleFormat"
  in
  (match formats.value with
  | Some l when List.length (List.sort_uniq compare l) > 1 ->
      warn d ~tag:tag_sample_format "mixed_sample_formats"
        "Samples use different formats; ocaml-tiff reports a single format per \
         directory"
  | _ -> ());
  let compression =
    enum_field ~default:1 d Tag_registry.compression tag_compression
  in
  let planar = enum_field ~default:1 d Tag_registry.planar tag_planar in
  let predictor =
    enum_field ~default:1 d Tag_registry.predictor tag_predictor
  in
  let photometric = enum_field d Tag_registry.photometric tag_photometric in
  let int = Fmt.int and code (e : Report.enum) = e.code in
  crosscheck d ~what:"ImageWidth" ~pp:int width (fun () -> Ifd.width ifd);
  crosscheck d ~what:"ImageLength" ~pp:int height (fun () -> Ifd.height ifd);
  crosscheck d ~what:"SamplesPerPixel" ~pp:int spp (fun () ->
      Ifd.samples_per_pixel ifd);
  crosscheck d ~what:"BitsPerSample"
    ~pp:Fmt.(Dump.list int)
    bits
    (fun () -> Ifd.bits_per_sample ifd);
  crosscheck d ~what:"Compression" ~pp:int (Field.map code compression)
    (fun () -> Ifd.compression ifd |> Ifd.compression_to_int);
  crosscheck d ~what:"PlanarConfiguration" ~pp:int (Field.map code planar)
    (fun () -> Ifd.planar_configuration ifd |> Ifd.planar_configuration_to_int);
  (match formats.value with
  | Some (first :: _) ->
      crosscheck d ~what:"SampleFormat" ~pp:int
        (Field.map (fun _ -> first) formats)
        (fun () -> Ifd.sample_format ifd |> Ifd.sample_format_to_int)
  | _ -> ());
  let layout =
    layout d ~width:width.value ~height:height.value ~spp:spp.value
      ~planar:(Option.map code planar.value)
  in
  let planar_code = Option.map code planar.value in
  let tags =
    List.map
      (fun (e, word) -> Decode.tag ctx ~max_items:limits.max_tag_values ~word e)
      entries
  in
  List.iter
    (fun (t : Report.tag) ->
      match t.value_status with
      | Unreadable ->
          warn d ~tag:t.id "unreadable_tag_value" "Value of tag %d: %s" t.id
            (Option.value ~default:"unreadable" t.note)
      | _ -> ())
    tags;
  {
    index;
    offset;
    entry_count = List.length tags;
    width;
    height;
    samples_per_pixel = spp;
    bits_per_sample = bits;
    sample_format =
      Field.map (List.map (Report.enum Tag_registry.sample_format)) formats;
    photometric_interpretation = photometric;
    planar_configuration = planar;
    compression;
    predictor;
    orientation =
      enum_field ~default:1 d Tag_registry.orientation tag_orientation;
    resolution =
      {
        x = rational_field d tag_x_res;
        y = rational_field d tag_y_res;
        unit = enum_field ~default:2 d Tag_registry.resolution_unit tag_res_unit;
      };
    layout;
    planes =
      planes ~width:width.value ~height:height.value ~spp:spp.value
        ~planar:planar_code ~bits:bits.value;
    pixel_decoding =
      pixel_support ~layout:layout.kind
        ~compression:(Option.map code compression.value)
        ~predictor:(Option.map code predictor.value)
        ~planar:planar_code ~bits:bits.value ~formats:formats.value;
    tags;
    warnings = List.rev d.warnings;
  }

(* {1 IFD chain} *)

let file_offset ctx (o : Optint.Int63.t) =
  Decode.file_offset ctx (Optint.Int63.to_int64 o)

let walk ~limits (ctx : Decode.ctx) header =
  let src = ctx.source in
  let rec go index offset visited acc =
    if index >= limits.max_ifds then
      (List.rev acc, Report.Truncated_at_limit, None)
    else
      let parsed =
        match preflight src header offset with
        | Error e -> Error e
        | Ok words ->
            Guard.run (fun () ->
                ( Ifd.v ~file_offset:(Optint.Int63.of_int offset) header src.ro,
                  words ))
      in
      match parsed with
      | Error e -> (List.rev acc, Report.Failed, Some e)
      | Ok (ifd, words) -> (
          let dir =
            Guard.run (fun () ->
                directory ~limits ctx ~index ~offset ~words ifd)
          in
          match dir with
          | Error e -> (List.rev acc, Failed, Some e)
          | Ok dir -> (
              let acc = dir :: acc in
              let next = Ifd.next_ifd_offset ifd |> file_offset ctx in
              match next with
              | 0 -> (List.rev acc, Complete, None)
              | next when List.mem next visited ->
                  ( List.rev acc,
                    Failed,
                    Some
                      (Problem.error Malformed
                         "IFD %d points back to offset %d, forming a loop" index
                         next) )
              | next -> go (index + 1) next (next :: visited) acc))
  in
  let first = file_offset ctx header.offset in
  go 0 first [ first ] []

let run ?(limits = default_limits) (src : Source.t) :
    (Report.t, Report.failure) result =
  let fail error =
    Error { Report.failed_file = Some (src.name, Some src.size); error }
  in
  match read_header src with
  | Error e -> fail e
  | Ok header -> (
      let ctx = Decode.ctx src header in
      match walk ~limits ctx header with
      | [], _, Some e -> fail e
      | [], _, None ->
          fail (Problem.error Malformed "The file contains no directories")
      | directories, status, error ->
          let warnings =
            match (status, error) with
            | Failed, Some e ->
                [
                  Problem.warning "ifd_walk_failed"
                    "Stopped after %d director%s: %s" (List.length directories)
                    (if List.length directories = 1 then "y" else "ies")
                    e.message;
                ]
            | Truncated_at_limit, _ ->
                [
                  Problem.warning "ifd_limit_reached"
                    "Stopped after %d directories (limit)" limits.max_ifds;
                ]
            | _ -> []
          in
          Ok
            {
              file =
                {
                  name = src.name;
                  size_bytes = src.size;
                  byte_order =
                    (match header.byte_order with
                    | Little -> Little_endian
                    | Big -> Big_endian);
                  format =
                    (match header.kind with
                    | Tiff -> Classic_tiff
                    | Bigtiff -> Bigtiff);
                  first_ifd_offset = file_offset ctx header.offset;
                };
              ifd_count = List.length directories;
              ifd_walk = { status; limit = limits.max_ifds; error };
              directories;
              warnings;
              limitations;
            })

let file ?limits path =
  match Source.with_file path (run ?limits) with
  | Ok r -> r
  | Error error ->
      Error { failed_file = Some (Filename.basename path, None); error }
