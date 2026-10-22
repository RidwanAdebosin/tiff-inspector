(* Expected properties of each fixture (see test/fixtures/FIXTURES.md) *)

open Tiff_inspector
open Report

let fixture name = Filename.concat "../fixtures" name

let inspect name =
  match Tiff_inspector_unix.file (fixture name) with
  | Ok r -> r
  | Error f -> Alcotest.failf "%s failed: %s" name f.error.message

let fails name =
  match Tiff_inspector_unix.file (fixture name) with
  | Ok _ -> Alcotest.failf "%s unexpectedly succeeded" name
  | Error f -> f.error.code

let dir ?(i = 0) name = List.nth (inspect name).directories i
let status = Alcotest.testable (Fmt.of_to_string Field.status_to_string) ( = )
let code = Alcotest.testable (Fmt.of_to_string Problem.code_to_string) ( = )

let check_field name pp_t ~expect_status ~expect (f : _ Field.t) =
  Alcotest.check status (name ^ " status") expect_status f.status;
  Alcotest.(check (option pp_t)) (name ^ " value") expect f.value

let codes (l : enum list Field.t) =
  Option.map (List.map (fun e -> e.code)) l.value

let enum_code (f : enum Field.t) = Option.map (fun e -> e.code) f.value

let warning_codes (d : directory) =
  List.map (fun w -> w.Problem.w_code) d.warnings

let gray8 () =
  let r = inspect "gray8.tif" in
  Alcotest.(check int) "ifd count" 1 r.ifd_count;
  Alcotest.(check bool) "little endian" true (r.file.byte_order = Little_endian);
  Alcotest.(check bool) "classic" true (r.file.format = Classic_tiff);
  let d = List.hd r.directories in
  check_field "width" Alcotest.int ~expect_status:Present ~expect:(Some 16)
    d.width;
  check_field "height" Alcotest.int ~expect_status:Present ~expect:(Some 8)
    d.height;
  (* SampleFormat and PlanarConfiguration are absent: spec defaults, labelled *)
  Alcotest.check status "sample format defaulted" Default d.sample_format.status;
  Alcotest.(check (option (list int)))
    "sample format" (Some [ 1 ]) (codes d.sample_format);
  Alcotest.check status "planar defaulted" Default d.planar_configuration.status;
  check_field "x resolution" (Alcotest.float 0.) ~expect_status:Present
    ~expect:(Some 72.) d.resolution.x;
  Alcotest.(check (list string)) "no warnings" [] (warning_codes d);
  let desc = List.find (fun (t : tag) -> t.id = 270) d.tags in
  Alcotest.(check bool)
    "description" true
    (desc.value = Some (Ascii "gray8 fixture"))

let rgb_contig () =
  let d = dir "rgb_contig.tif" in
  Alcotest.(check (option (list int)))
    "bits"
    (Some [ 8; 8; 8 ])
    d.bits_per_sample.value;
  Alcotest.(check (option int))
    "planar" (Some 1)
    (enum_code d.planar_configuration);
  Alcotest.(check int) "strips" 2 d.layout.chunk_count;
  Alcotest.(check (option int))
    "expected strips" (Some 2) d.layout.expected_chunk_count;
  Alcotest.(check int) "one interleaved plane" 1 (List.length d.planes);
  Alcotest.(check (list int))
    "plane samples" [ 0; 1; 2 ] (List.hd d.planes).samples

let rgb_planar () =
  let r = inspect "rgb_planar.tif" in
  let d = List.hd r.directories in
  Alcotest.(check bool) "big endian" true (r.file.byte_order = Big_endian);
  Alcotest.(check (option int))
    "photometric" (Some 2)
    (enum_code d.photometric_interpretation);
  Alcotest.(check (option int))
    "separate" (Some 2)
    (enum_code d.planar_configuration);
  Alcotest.(check int) "3 planes" 3 (List.length d.planes);
  Alcotest.(check int) "3 strips" 3 d.layout.chunk_count;
  Alcotest.(check (option int))
    "expected strips" (Some 3) d.layout.expected_chunk_count;
  Alcotest.(check (list string)) "no warnings" [] (warning_codes d)

(* Regression: SampleFormat with several values is stored at an offset *)
let sampleformat_offset () =
  let d = dir "float32_sampleformat_offset.tif" in
  Alcotest.check status "present" Present d.sample_format.status;
  Alcotest.(check (option (list int)))
    "ieee float"
    (Some [ 3; 3; 3 ])
    (codes d.sample_format);
  Alcotest.(check (list string)) "library agrees" [] (warning_codes d);
  Alcotest.(check bool)
    "decodable" true
    (d.pixel_decoding.library_support = Supported)

let multi_ifd () =
  let r = inspect "multi_ifd.tif" in
  Alcotest.(check int) "3 ifds" 3 r.ifd_count;
  Alcotest.(check bool) "complete" true (r.ifd_walk.status = Complete);
  let dims =
    List.map (fun d -> (d.width.value, d.height.value)) r.directories
  in
  Alcotest.(check (list (pair (option int) (option int))))
    "dimensions"
    [ (Some 8, Some 8); (Some 4, Some 4); (Some 2, Some 2) ]
    dims

let deflate () =
  let d = dir "deflate.tif" in
  Alcotest.(check (option int))
    "adobe deflate" (Some 8) (enum_code d.compression)

let bigtiff () =
  let r = inspect "bigtiff.tif" in
  let d = List.hd r.directories in
  Alcotest.(check bool) "bigtiff" true (r.file.format = Bigtiff);
  Alcotest.(check (option (list int)))
    "16 bit" (Some [ 16 ]) d.bits_per_sample.value;
  Alcotest.(check (option int)) "total bytes" (Some 128) d.layout.total_bytes

let tiled () =
  let d = dir "tiled.tif" in
  Alcotest.(check bool) "tiles" true (d.layout.kind = Tiles);
  Alcotest.(check int) "4 tiles" 4 d.layout.chunk_count;
  Alcotest.(check (option int))
    "expected" (Some 4) d.layout.expected_chunk_count;
  Alcotest.(check (option int)) "1024 bytes" (Some 1024) d.layout.total_bytes

(* Regression: two SHORTs stored inline in the value field. ocaml-tiff's own
   accessor misreads them; the inspector must decode them and say so. *)
let gray_alpha () =
  let d = dir "gray_alpha.tif" in
  Alcotest.(check (option (list int)))
    "bits"
    (Some [ 8; 8 ])
    d.bits_per_sample.value;
  Alcotest.(check (list string))
    "library error surfaced" [ "library_error" ] (warning_codes d)

(* Regression: three SHORTs stored inline in BigTIFF's 8-byte value field.
   ocaml-tiff keeps only the first; the inspector must decode all three. *)
let bigtiff_rgb_inline () =
  let r = inspect "bigtiff_rgb_inline.tif" in
  let d = List.hd r.directories in
  Alcotest.(check bool) "bigtiff" true (r.file.format = Bigtiff);
  check_field "bits"
    Alcotest.(list int)
    ~expect_status:Present
    ~expect:(Some [ 8; 8; 8 ])
    d.bits_per_sample;
  Alcotest.check status "sample format present" Present d.sample_format.status;
  Alcotest.(check (option (list int)))
    "sample format"
    (Some [ 1; 1; 1 ])
    (codes d.sample_format);
  Alcotest.(check (list int))
    "plane bits" [ 8; 8; 8 ] (List.hd d.planes).bits_per_sample;
  Alcotest.(check bool)
    "decodable" true
    (d.pixel_decoding.library_support = Supported);
  Alcotest.(check (list string))
    "no unreadable tags" []
    (List.filter (( = ) "unreadable_tag_value") (warning_codes d));
  List.iter
    (fun (t : tag) ->
      Alcotest.(check bool)
        (Fmt.str "tag %d decoded" t.id)
        true (t.value_status = Decoded))
    d.tags

let unknown_tag () =
  let d = dir "unknown_tag.tif" in
  let t = List.find (fun (t : tag) -> t.id = 65001) d.tags in
  Alcotest.(check bool) "unknown" true (t.name = None);
  Alcotest.(check bool) "truncated" true (t.value_status = Truncated);
  Alcotest.(check int) "count" 100 t.count;
  (match t.value with
  | Some (Integers l) -> Alcotest.(check int) "64 shown" 64 (List.length l)
  | _ -> Alcotest.fail "expected integers");
  let t = List.find (fun (t : tag) -> t.id = 65000) d.tags in
  Alcotest.(check bool) "ascii" true (t.value = Some (Ascii "hello private tag"))

let strip_out_of_bounds () =
  let d = dir "strip_out_of_bounds.tif" in
  Alcotest.(check (list string))
    "warning" [ "chunk_out_of_bounds" ] (warning_codes d)

let ifd_loop () =
  let r = inspect "ifd_loop.tif" in
  Alcotest.(check int) "1 ifd" 1 r.ifd_count;
  Alcotest.(check bool) "failed walk" true (r.ifd_walk.status = Failed);
  Alcotest.(check (list string))
    "warning" [ "ifd_walk_failed" ]
    (List.map (fun w -> w.Problem.w_code) r.warnings)

let malformed () =
  List.iter
    (fun (name, expected) -> Alcotest.check code name expected (fails name))
    [
      ("empty.tif", Problem.Not_a_tiff);
      ("not_a_tiff.tif", Not_a_tiff);
      ("bad_magic.tif", Not_a_tiff);
      ("truncated_header.tif", Truncated);
      ("ifd_offset_out_of_range.tif", Malformed);
      ("truncated_ifd.tif", Truncated);
      ("unknown_field_type.tif", Unsupported_feature);
      ("huge_strip_count.tif", Malformed);
      ("does_not_exist.tif", File_not_found);
    ]

let directory_path () =
  Alcotest.check code "directory" File_unreadable (fails ".")

(* Random corruptions of every fixture must never raise or hang *)
let mutations () =
  let files =
    Sys.readdir "../fixtures" |> Array.to_list
    |> List.filter (fun f -> Filename.check_suffix f ".tif")
  in
  let rng = Random.State.make [| 42 |] in
  let read f = In_channel.with_open_bin (fixture f) In_channel.input_all in
  List.iter
    (fun f ->
      let original = read f in
      for _ = 1 to 200 do
        let b = Bytes.of_string original in
        let n = Bytes.length b in
        if n > 0 then
          for _ = 1 to 1 + Random.State.int rng 4 do
            Bytes.set b (Random.State.int rng n)
              (Char.chr (Random.State.int rng 256))
          done;
        let s = Bytes.to_string b in
        let s =
          if n > 0 && Random.State.bool rng then
            String.sub s 0 (Random.State.int rng n)
          else s
        in
        match Inspect.run (Source.of_string ~name:f s) with
        | Ok r -> ignore (Json.to_string (Json.report r))
        | Error e -> ignore (Json.to_string (Json.failure e))
        | exception exn ->
            Alcotest.failf "%s mutation raised %s" f (Printexc.to_string exn)
      done)
    files

(* {2 Classic TIFF offsets of 2 GiB and above} *)

let header kind =
  { Tiff.Ifd.kind; byte_order = Tiff.Endian.Little; offset = Optint.Int63.zero }

let ctx kind = Decode.ctx (Source.of_string ~name:"x" "") (header kind)

(* ocaml-tiff sign-extends classic offsets; the helper must undo that and
   leave BigTIFF offsets alone *)
let offset_mask () =
  let classic = ctx Tiff and big = ctx Bigtiff in
  Alcotest.(check int)
    "classic >= 2 GiB" 0xFFFF_FFF0
    (Decode.file_offset classic (Int64.of_int32 (-16l)));
  Alcotest.(check int)
    "classic 2 GiB" 0x8000_0000
    (Decode.file_offset classic (Int64.of_int32 Int32.min_int));
  Alcotest.(check int) "classic small" 8 (Decode.file_offset classic 8L);
  Alcotest.(check int)
    "bigtiff beyond 4 GiB" 0x1_0000_0000
    (Decode.file_offset big 0x1_0000_0000L)

(* A little-endian classic IFD: entries are (tag, type, count, value word) *)
let classic_ifd entries ~next =
  let b = Buffer.create 256 in
  Buffer.add_uint16_le b (List.length entries);
  List.iter
    (fun (tag, typ, count, value) ->
      Buffer.add_uint16_le b tag;
      Buffer.add_uint16_le b typ;
      Buffer.add_int32_le b (Int32.of_int count);
      Buffer.add_int32_le b (Int32.of_int value))
    entries;
  Buffer.add_int32_le b (Int32.of_int next);
  Buffer.contents b

let classic_header ~first_ifd =
  let b = Buffer.create 8 in
  Buffer.add_string b "II";
  Buffer.add_uint16_le b 42;
  Buffer.add_int32_le b (Int32.of_int first_ifd);
  Buffer.contents b

(* A 4x4 gray8 image whose single strip and IFD both lie above 2 GiB, in a
   sparse temporary file. Skipped when the file cannot be created quickly. *)
let sparse_beyond_2gib () =
  let strip = 0x8000_0000 and ifd = 0x8000_0010 in
  let short = 3 and long = 4 in
  let dir =
    classic_ifd ~next:0
      [
        (256, short, 1, 4);
        (257, short, 1, 4);
        (258, short, 1, 8);
        (259, short, 1, 1);
        (262, short, 1, 1);
        (273, long, 1, strip);
        (277, short, 1, 1);
        (278, short, 1, 4);
        (279, long, 1, 16);
      ]
  in
  let path = Filename.temp_file "tiff-inspector-sparse" ".tif" in
  Fun.protect
    ~finally:(fun () -> try Sys.remove path with Sys_error _ -> ())
    (fun () ->
      let t0 = Unix.gettimeofday () in
      let written =
        match Unix.openfile path [ O_WRONLY; O_TRUNC ] 0o600 with
        | exception Unix.Unix_error _ -> false
        | fd -> (
            let write s =
              if
                Unix.write_substring fd s 0 (String.length s) <> String.length s
              then failwith "short write"
            in
            match
              Fun.protect
                ~finally:(fun () -> Unix.close fd)
                (fun () ->
                  write (classic_header ~first_ifd:ifd);
                  ignore (Unix.lseek fd strip SEEK_SET);
                  write (String.make 16 'U');
                  write dir)
            with
            | () -> true
            | exception (Unix.Unix_error _ | Failure _) -> false)
      in
      if (not written) || Unix.gettimeofday () -. t0 > 2. then Alcotest.skip ()
      else
        match Tiff_inspector_unix.file path with
        | Error f -> Alcotest.failf "sparse file failed: %s" f.error.message
        | Ok r ->
            Alcotest.(check int) "first ifd" ifd r.file.first_ifd_offset;
            Alcotest.(check int)
              "size"
              (ifd + String.length dir)
              r.file.size_bytes;
            Alcotest.(check int) "1 ifd" 1 r.ifd_count;
            Alcotest.(check bool) "complete" true (r.ifd_walk.status = Complete);
            let d = List.hd r.directories in
            Alcotest.(check int) "ifd offset" ifd d.offset;
            Alcotest.(check (list int))
              "strip offset" [ strip ] d.layout.offsets;
            Alcotest.(check (option int)) "bytes" (Some 16) d.layout.total_bytes;
            Alcotest.(check (list string)) "no warnings" [] (warning_codes d);
            Alcotest.(check (list string))
              "no file warnings" []
              (List.map (fun w -> w.Problem.w_code) r.warnings))

(* {2 Many strips} *)

(* A 1 x n gray8 image with one row per strip: the bounds check over the
   offset and byte-count lists must stay linear *)
let many_strips () =
  let n = 50_000 in
  let data_offset = 8 in
  let ifd = data_offset + n in
  let entries = 9 in
  let offsets_at = ifd + 2 + (entries * 12) + 4 in
  let counts_at = offsets_at + (4 * n) in
  let short = 3 and long = 4 in
  let b = Buffer.create (counts_at + (4 * n)) in
  Buffer.add_string b (classic_header ~first_ifd:ifd);
  Buffer.add_string b (String.make n 'x');
  Buffer.add_string b
    (classic_ifd ~next:0
       [
         (256, short, 1, 1);
         (257, short, 1, n);
         (258, short, 1, 8);
         (259, short, 1, 1);
         (262, short, 1, 1);
         (273, long, n, offsets_at);
         (277, short, 1, 1);
         (278, short, 1, 1);
         (279, long, n, counts_at);
       ]);
  for i = 0 to n - 1 do
    Buffer.add_int32_le b (Int32.of_int (data_offset + i))
  done;
  for _ = 1 to n do
    Buffer.add_int32_le b 1l
  done;
  let src = Source.of_string ~name:"many_strips.tif" (Buffer.contents b) in
  let t0 = Unix.gettimeofday () in
  let r =
    match Inspect.run src with
    | Ok r -> r
    | Error f -> Alcotest.failf "many strips failed: %s" f.error.message
  in
  let elapsed = Unix.gettimeofday () -. t0 in
  let d = List.hd r.directories in
  Alcotest.(check int) "strips" n d.layout.chunk_count;
  Alcotest.(check (option int))
    "expected" (Some n) d.layout.expected_chunk_count;
  Alcotest.(check (option int)) "total bytes" (Some n) d.layout.total_bytes;
  Alcotest.(check bool) "layout truncated" true d.layout.truncated;
  Alcotest.(check (list string)) "no warnings" [] (warning_codes d);
  if elapsed >= 1. then
    Alcotest.failf "inspecting %d strips took %.2f s (limit 1 s)" n elapsed

let json_roundtrip () =
  let json = Json.report (inspect "multi_ifd.tif") |> Json.to_string in
  let parsed = Yojson.Safe.from_string json in
  let open Yojson.Safe.Util in
  Alcotest.(check string)
    "schema" "1.0"
    (parsed |> member "schema_version" |> to_string);
  Alcotest.(check int)
    "dirs" 3
    (parsed |> member "directories" |> to_list |> List.length);
  let sf =
    parsed |> member "directories" |> index 0 |> member "sample_format"
  in
  Alcotest.(check string) "status" "default" (sf |> member "status" |> to_string)

let () =
  Alcotest.run "tiff-inspector"
    [
      ( "fixtures",
        [
          Alcotest.test_case "gray8" `Quick gray8;
          Alcotest.test_case "rgb contiguous" `Quick rgb_contig;
          Alcotest.test_case "rgb planar" `Quick rgb_planar;
          Alcotest.test_case "offset SampleFormat" `Quick sampleformat_offset;
          Alcotest.test_case "multiple IFDs" `Quick multi_ifd;
          Alcotest.test_case "deflate" `Quick deflate;
          Alcotest.test_case "bigtiff" `Quick bigtiff;
          Alcotest.test_case "tiled" `Quick tiled;
          Alcotest.test_case "inline multi-value tag" `Quick gray_alpha;
          Alcotest.test_case "bigtiff inline multi-value tags" `Quick
            bigtiff_rgb_inline;
          Alcotest.test_case "unknown tags" `Quick unknown_tag;
        ] );
      ( "malformed",
        [
          Alcotest.test_case "strip out of bounds" `Quick strip_out_of_bounds;
          Alcotest.test_case "IFD loop" `Quick ifd_loop;
          Alcotest.test_case "error categories" `Quick malformed;
          Alcotest.test_case "directory path" `Quick directory_path;
          Alcotest.test_case "random mutations" `Slow mutations;
        ] );
      ( "offsets",
        [
          Alcotest.test_case "classic offsets are unsigned" `Quick offset_mask;
          Alcotest.test_case "sparse file beyond 2 GiB" `Quick
            sparse_beyond_2gib;
        ] );
      ("layout", [ Alcotest.test_case "50000 strips" `Quick many_strips ]);
      ("json", [ Alcotest.test_case "round trip" `Quick json_roundtrip ]);
    ]
