(* Converts exceptions raised by ocaml-tiff into typed problems *)

let starts_with ~prefix s = String.starts_with ~prefix s

let classify = function
  | Source.Out_of_bounds { offset; length; size } ->
      Problem.error Truncated
        "Read of %d bytes at offset %d goes past the end of the file (%d bytes)"
        length offset size
  | End_of_file -> Problem.error Truncated "Unexpected end of file"
  | Out_of_memory | Stack_overflow ->
      Problem.error Limit_exceeded "Inspection exceeded memory limits"
  | Invalid_argument m when starts_with ~prefix:"Field kind" m ->
      Problem.error Unsupported_feature "Unknown TIFF field type (%s)" m
  | Invalid_argument m | Failure m -> Problem.error Malformed "%s" m
  | Not_found -> Problem.error Malformed "A required tag is missing"
  | exn -> Problem.error Internal "%s" (Printexc.to_string exn)

let run f = try Ok (f ()) with exn -> Error (classify exn)
