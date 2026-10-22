(* A tiny test helper for the playground.

   [check] prints one PASS or FAIL line per assertion; the playground shows
   the totals after each run. *)

let passed = ref 0
let failed = ref 0

let reset () =
  passed := 0;
  failed := 0

let counts () = (!passed, !failed)

let check name ok =
  if ok then incr passed else incr failed;
  Printf.printf "%s %s\n%!" (if ok then "PASS" else "FAIL") name

let equal pp name ~expected actual =
  if expected = actual then check name true
  else (
    check name false;
    Printf.printf "  expected %s, got %s\n%!" (pp expected) (pp actual))

let int = equal string_of_int
let string = equal (Printf.sprintf "%S")
let bool = equal string_of_bool
