(* Decodes the values of IFD entries parsed by ocaml-tiff, reading through the
   bounded source and never more than [max_items] values. *)

module Ifd = Tiff.Ifd

type ctx = {
  source : Source.t;
  endian : Tiff.Endian.endianness;
  bigtiff : bool;
}

let ctx source (header : Ifd.header) =
  {
    source;
    endian = header.byte_order;
    bigtiff = (match header.kind with Bigtiff -> true | Tiff -> false);
  }

type raw = { bytes : Cstruct.t; items : int; truncated : bool }

(* Classic TIFF offsets are unsigned 32-bit values. ocaml-tiff reads them
   with [Int64.of_int32], which sign-extends offsets of 2 GiB and above, so
   every offset it hands us is masked back here before use. *)
let file_offset ctx v =
  if ctx.bigtiff then Int64.to_int v else Int64.to_int v land 0xFFFF_FFFF

(* The value/offset field of an entry ([word], 4 bytes in classic TIFF and 8
   in BigTIFF) holds the values themselves when they fit, otherwise the offset
   of the values. It is read from the file rather than taken from ocaml-tiff,
   which decodes only the first of several inline values. *)
let raw ctx ~max_items ~word entry =
  let field_type = Ifd.entry_field_type entry in
  let count64 = Ifd.entry_count entry in
  match Tag_registry.field_type_size field_type with
  | None -> Error `Unsupported_type
  | Some size -> (
      let inline_cap = if ctx.bigtiff then 8 else 4 in
      let count =
        if Int64.compare count64 (Int64.of_int max_int) > 0 || count64 < 0L then
          max_int
        else Int64.to_int count64
      in
      let items = min count max_items in
      let truncated = items < count in
      if count <= inline_cap / size then
        Ok { bytes = Cstruct.sub word 0 (items * size); items; truncated }
      else
        let offset =
          file_offset ctx
            (if ctx.bigtiff then Tiff.Endian.uint64 ctx.endian word
             else Tiff.Endian.uint32 ctx.endian word |> Int64.of_int32)
        in
        match Source.read ctx.source ~offset ~length:(items * size) with
        | bytes -> Ok { bytes; items; truncated }
        | exception Source.Out_of_bounds _ ->
            Error
              (`Unreadable
                 (Fmt.str "values at offset %d lie outside the file" offset)))

let printable_ascii s =
  let b = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      match c with
      | ' ' .. '~' | '\n' | '\t' -> Buffer.add_char b c
      | c -> Buffer.add_string b (Printf.sprintf "\\x%02x" (Char.code c)))
    s;
  Buffer.contents b

let ascii_of_bytes buf =
  let s = Cstruct.to_string buf in
  (* NUL terminates each string; several strings may be packed together *)
  String.split_on_char '\000' s
  |> List.rev
  |> ( function "" :: rest -> rest | l -> l )
  |> List.rev |> String.concat "\n" |> printable_ascii

let values ctx ~field_type { bytes; items; _ } : Report.tag_value =
  let e = ctx.endian in
  let ints f size = Report.Integers (List.init items (fun i -> f (i * size))) in
  let u32 offset = Tiff.Endian.uint32 ~offset e bytes |> Int32.to_int in
  let u32 offset = u32 offset land 0xFFFF_FFFF in
  let s32 offset = Tiff.Endian.uint32 ~offset e bytes |> Int32.to_int in
  let i64 offset = Tiff.Endian.uint64 ~offset e bytes |> Int64.to_int in
  match field_type with
  | 2 -> Ascii (ascii_of_bytes bytes)
  | 1 | 7 -> ints (fun o -> Cstruct.get_uint8 bytes o) 1
  | 6 -> ints (fun o -> (Cstruct.get_uint8 bytes o lxor 0x80) - 0x80) 1
  | 3 -> ints (fun offset -> Tiff.Endian.uint16 ~offset e bytes) 2
  | 8 -> ints (fun offset -> Tiff.Endian.int16 ~offset e bytes) 2
  | 4 | 13 -> ints u32 4
  | 9 -> ints s32 4
  | 16 | 17 | 18 -> ints i64 8
  | 5 -> Rationals (List.init items (fun i -> (u32 (i * 8), u32 ((i * 8) + 4))))
  | 10 ->
      Rationals (List.init items (fun i -> (s32 (i * 8), s32 ((i * 8) + 4))))
  | 11 ->
      Floats
        (List.init items (fun i -> Tiff.Endian.float32 ~offset:(i * 4) e bytes))
  | 12 ->
      Floats
        (List.init items (fun i -> Tiff.Endian.double ~offset:(i * 8) e bytes))
  | _ -> assert false (* raw has already rejected unknown field types *)

let max_ascii = 4096

let tag ctx ~max_items ~word entry : Report.tag =
  let id = Ifd.entry_tag_id entry in
  let field_type = Ifd.entry_field_type entry in
  let count = Ifd.entry_count entry |> Int64.to_int in
  let max_items = if field_type = 2 then max_ascii else max_items in
  let base =
    {
      Report.id;
      name = Tag_registry.tag_name id;
      field_type =
        {
          code = field_type;
          name = Tag_registry.field_type_name field_type;
          label = Tag_registry.field_type_name field_type;
        };
      count;
      value = None;
      value_status = Decoded;
      note = None;
    }
  in
  match raw ctx ~max_items ~word entry with
  | Ok r ->
      {
        base with
        value = Some (values ctx ~field_type r);
        value_status = (if r.truncated then Truncated else Decoded);
        note =
          (if r.truncated then
             Some (Fmt.str "showing %d of %d values" r.items count)
           else None);
      }
  | Error `Unsupported_type ->
      {
        base with
        value_status = Unsupported_type;
        note = Some (Fmt.str "unknown field type %d" field_type);
      }
  | Error (`Unreadable m) ->
      { base with value_status = Unreadable; note = Some m }

(* Integer values of an entry, for interpreting well-known tags *)
let ints ctx ~max_items ~word entry =
  let field_type = Ifd.entry_field_type entry in
  match raw ctx ~max_items ~word entry with
  | Error `Unsupported_type ->
      Error (Fmt.str "unknown field type %d" field_type)
  | Error (`Unreadable m) -> Error m
  | Ok r -> (
      match values ctx ~field_type r with
      | Integers l -> Ok l
      | _ ->
          Error
            (Fmt.str "expected an integer field type, found %s"
               (Option.value ~default:"unknown"
                  (Tag_registry.field_type_name field_type))))
