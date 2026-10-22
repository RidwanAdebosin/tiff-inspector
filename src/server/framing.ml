(* Request body framing (RFC 9112 §6).

   Decided once per request from the headers, strictly: a request with
   neither Content-Length nor Transfer-Encoding has an empty body (it is never
   read until EOF), Transfer-Encoding must be exactly [chunked], and the two
   headers never appear together or more than once. Anything else is a 400,
   which closes the request-smuggling / desync class (TE.CL, CL.CL,
   "Content-Length: 0x10"). Content-Length must be plain decimal digits. *)

type t = Empty | Fixed of int | Chunked

let digits s = s <> "" && String.for_all (fun c -> c >= '0' && c <= '9') s

(* OCaml ints hold any 18-digit decimal *)
let max_digits = 18

let of_headers headers =
  let te = Http.Header.get_multi headers "transfer-encoding"
  and cl = Http.Header.get_multi headers "content-length" in
  match (te, cl) with
  | _ :: _, _ :: _ -> Error "Transfer-Encoding with Content-Length"
  | [ "chunked" ], [] -> Ok Chunked
  | [ _ ], [] -> Error "Unsupported Transfer-Encoding"
  | _ :: _, [] -> Error "Multiple Transfer-Encoding headers"
  | [], [] -> Ok Empty
  | [], [ n ] ->
      if digits n && String.length n <= max_digits then
        Ok (Fixed (int_of_string n))
      else Error "Invalid Content-Length"
  | [], _ -> Error "Multiple Content-Length headers"

let to_string = function
  | Empty -> "empty"
  | Fixed n -> Printf.sprintf "fixed %d" n
  | Chunked -> "chunked"
