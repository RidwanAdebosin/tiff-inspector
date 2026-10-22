(* A value together with where it came from, so inferred values are never
   presented as facts *)

type status = Present | Default | Absent | Unsupported | Error
type 'a t = { status : status; value : 'a option; note : string option }

let present v = { status = Present; value = Some v; note = None }
let default ?note v = { status = Default; value = Some v; note }
let absent ?note () = { status = Absent; value = None; note }
let unsupported note = { status = Unsupported; value = None; note = Some note }
let error note = { status = Error; value = None; note = Some note }
let value t = t.value
let map f t = { t with value = Option.map f t.value }

let status_to_string = function
  | Present -> "present"
  | Default -> "default"
  | Absent -> "absent"
  | Unsupported -> "unsupported"
  | Error -> "error"
