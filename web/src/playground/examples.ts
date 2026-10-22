export type Example = { id: string; title: string; code: string };

export const EXAMPLES: Example[] = [
  {
    id: "hello",
    title: "Hello, OCaml",
    code: `(* Everything runs in your browser. Press Run or Ctrl/Cmd+Enter. *)
let greet name = Printf.sprintf "Hello, %s!" name

let () = print_endline (greet "world")

(* The toplevel prints the type and value of each definition. *)
let squares = List.init 6 (fun i -> i * i)
let total = List.fold_left ( + ) 0 squares
`,
  },
  {
    id: "tests",
    title: "A failing test",
    code: `(* Test.check records an assertion; the totals appear next to the output. *)
let rev_sorted l = List.sort (fun a b -> compare b a) l

let () =
  Test.check "sorts descending" (rev_sorted [ 1; 3; 2 ] = [ 3; 2; 1 ]);
  Test.int "keeps the length" ~expected:3 (List.length (rev_sorted [ 1; 3; 2 ]));
  (* Wrong on purpose. Fix it and run again. *)
  Test.int "sum" ~expected:7 (List.fold_left ( + ) 0 [ 1; 3; 2 ])

(* Also available: Test.string and Test.bool. *)
`,
  },
  {
    id: "tiff",
    title: "Read a TIFF with the tiff library",
    code: `(* Sample.reader gives the tiff library random access to a bundled file.
   Sample.names () lists them. *)
let t = Tiff.from_file (Tiff.as_kind Tiff.Uint8) (Sample.reader "rgb_contig.tif")
let ifd = Tiff.ifd t

let () =
  Printf.printf "%d x %d pixels, %d samples per pixel, bits %s, compression %s\\n"
    (Tiff.Ifd.width ifd) (Tiff.Ifd.height ifd)
    (Tiff.Ifd.samples_per_pixel ifd)
    (String.concat "/" (List.map string_of_int (Tiff.Ifd.bits_per_sample ifd)))
    (Tiff.Ifd.compression_to_string (Tiff.Ifd.compression ifd))

(* Every entry of the first directory: *)
let () = List.iter (Format.printf "%a@." Tiff.Ifd.pp_entry) (Tiff.Ifd.entries ifd)
`,
  },
  {
    id: "inspect",
    title: "List tags with the inspector",
    code: `(* Sample.inspect runs the same parser as the Inspector page. *)
let () =
  match Sample.inspect "multi_ifd.tif" with
  | Error f -> print_endline ("failed: " ^ f.error.message)
  | Ok report ->
      Printf.printf "%d directories\\n" report.ifd_count;
      List.iter
        (fun (d : Tiff_inspector.Report.directory) ->
          Printf.printf "IFD %d at offset %d, %d entries\\n" d.index d.offset d.entry_count;
          List.iter
            (fun (tag : Tiff_inspector.Report.tag) ->
              Printf.printf "  %5d  %s\\n" tag.id (Option.value tag.name ~default:"(unknown)"))
            d.tags)
        report.directories

(* The full report as JSON, exactly what the API returns: *)
(* let () = Sample.inspect_json "gray8.tif" *)
`,
  },
  {
    id: "errors",
    title: "Errors: a bad file and a type error",
    code: `(* The inspector reports problems instead of raising. *)
let () = Sample.inspect_json "bad_magic.tif"

(* Runtime exceptions are shown too. *)
let () = ignore (Sample.get "missing.tif")

(* And a compile error: the editor underlines where it is. *)
let answer : int = "forty-two"
`,
  },
];
