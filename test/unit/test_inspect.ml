(* Expected properties of each fixture (see test/fixtures/FIXTURES.md) *)

open Tiff_inspector
open Report

let fixture name = Filename.concat "../fixtures" name

let inspect name =
  match Inspect.file (fixture name) with
  | Ok r -> r
  | Error f -> Alcotest.failf "%s failed: %s" name f.error.message

let fails name =
  match Inspect.file (fixture name) with
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
      ("json", [ Alcotest.test_case "round trip" `Quick json_roundtrip ]);
    ]
