(* Per-key token bucket. [rate] requests per minute, with a burst of [rate].
   A rate of 0 or less disables limiting. Not thread-safe: the server runs a
   single Eio domain and never yields inside these functions. *)

type bucket = { mutable tokens : float; mutable last : float }

type t = {
  capacity : float;
  per_second : float;
  table : (string, bucket) Hashtbl.t;
  mutable last_prune : float;
}

let create ~per_minute =
  let capacity = float_of_int (max 0 per_minute) in
  {
    capacity;
    per_second = capacity /. 60.;
    table = Hashtbl.create 64;
    last_prune = 0.;
  }

(* Forget buckets that have refilled completely: they are indistinguishable
   from new ones. Bounds memory under many distinct clients. *)
let prune t ~now =
  if now -. t.last_prune > 60. then (
    t.last_prune <- now;
    Hashtbl.filter_map_inplace
      (fun _ b ->
        if b.tokens +. ((now -. b.last) *. t.per_second) >= t.capacity then None
        else Some b)
      t.table)

(* [Ok ()] if the request may proceed, [Error retry_after_seconds] otherwise. *)
let check t ~now key =
  if t.capacity <= 0. then Ok ()
  else (
    prune t ~now;
    let b =
      match Hashtbl.find_opt t.table key with
      | Some b -> b
      | None ->
          let b = { tokens = t.capacity; last = now } in
          Hashtbl.replace t.table key b;
          b
    in
    b.tokens <-
      Float.min t.capacity (b.tokens +. ((now -. b.last) *. t.per_second));
    b.last <- now;
    if b.tokens >= 1. then (
      b.tokens <- b.tokens -. 1.;
      Ok ())
    else
      Error
        (max 1 (int_of_float (Float.ceil ((1. -. b.tokens) /. t.per_second)))))
