(* Sample TIFF files bundled with the playground.

   The web page registers each file's bytes before running any code. *)

let table : (string, string) Hashtbl.t = Hashtbl.create 8
let register name data = Hashtbl.replace table name data

let names () =
  List.sort compare (Hashtbl.fold (fun k _ acc -> k :: acc) table [])

let get name =
  match Hashtbl.find_opt table name with
  | Some s -> s
  | None ->
      invalid_arg
        (Printf.sprintf "Sample.get: no sample named %S (see Sample.names ())"
           name)

(* The sample as an inspector source, for [Inspect.run]. *)
let source name = Tiff_inspector.Source.of_string ~name (get name)

(* The sample as a reader, for [Tiff.from_file]. *)
let reader name : Tiff.File.ro = (source name).ro

(* Inspect a sample and return its report. *)
let inspect ?limits name = Tiff_inspector.Inspect.run ?limits (source name)

(* Inspect a sample and print the report as JSON. *)
let inspect_json ?limits name =
  print_endline
    (Yojson.Safe.pretty_to_string
       (Tiff_inspector.Json.outcome (inspect ?limits name)))
