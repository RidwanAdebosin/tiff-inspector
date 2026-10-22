(* Runs one inspection in a separate process and maps its result to an HTTP
   status and a schema-v1 JSON document.

   The worker is [tiff-inspector inspect --format json FILE], started through
   /bin/sh so a virtual memory limit can be applied with [ulimit -v] before
   [exec]. On systems where [ulimit -v] is unsupported (macOS) the limit is
   silently skipped; the wall-clock timeout always applies. *)

module I = Tiff_inspector

type outcome =
  | Exited of int * string  (** Exit code and captured stdout *)
  | Signaled of int
  | Timed_out
  | Output_too_large
  | Spawn_failed

(* One worker run with what is worth logging about it *)
type result = {
  outcome : outcome;
  duration : float;  (** seconds *)
  output_bytes : int;  (** stdout captured so far *)
  stderr_tail : string;  (** last [max_stderr_bytes] of stderr *)
}

(* A schema-v1 report is far smaller than this given the core's own limits *)
let max_output_bytes = 8 * 1024 * 1024
let max_stderr_bytes = 4096

let script ~memory_limit_mb =
  Printf.sprintf
    "ulimit -c 0 2>/dev/null; ulimit -v %d 2>/dev/null; exec \"$0\" inspect \
     --format json \"$1\""
    (memory_limit_mb * 1024)

let executable p =
  try
    Unix.access p [ Unix.X_OK ];
    (Unix.stat p).st_kind = S_REG
  with Unix.Unix_error _ -> false

(* Keep the last [max_stderr_bytes] of a flow in [buf] *)
let read_tail flow buf =
  let chunk = Cstruct.create 4096 in
  let rec go () =
    match Eio.Flow.single_read flow chunk with
    | n ->
        Buffer.add_string buf (Cstruct.to_string (Cstruct.sub chunk 0 n));
        if Buffer.length buf > 2 * max_stderr_bytes then (
          let s = Buffer.contents buf in
          Buffer.clear buf;
          Buffer.add_string buf
            (String.sub s (String.length s - max_stderr_bytes) max_stderr_bytes));
        go ()
    | exception End_of_file -> ()
  in
  try go () with Eio.Io _ -> ()

let run ~fs ~mgr ~clock ~bin ~timeout ~memory_limit_mb path =
  let start = Unix.gettimeofday () in
  let err = Buffer.create 1024 in
  let output_bytes = ref 0 in
  let outcome =
    Eio.Switch.run @@ fun sw ->
    let devnull_in = Eio.Path.open_in ~sw Eio.Path.(fs / "/dev/null") in
    let r, w = Eio.Process.pipe ~sw mgr in
    let er, ew = Eio.Process.pipe ~sw mgr in
    let env =
      Eio.Process.Env.of_bindings [ ("PATH", "/usr/bin:/bin"); ("LC_ALL", "C") ]
    in
    match
      Eio.Process.spawn ~sw mgr ~stdin:devnull_in ~stdout:w ~stderr:ew ~env
        ~executable:"/bin/sh"
        [ "sh"; "-c"; script ~memory_limit_mb; bin; path ]
    with
    | exception Eio.Io _ -> Spawn_failed
    | p -> (
        Eio.Flow.close w;
        Eio.Flow.close ew;
        let read_out () =
          let ic = Eio.Buf_read.of_flow ~max_size:max_output_bytes r in
          try
            let out = Eio.Buf_read.take_all ic in
            output_bytes := String.length out;
            Ok out
          with Eio.Buf_read.Buffer_limit_exceeded ->
            output_bytes := Eio.Buf_read.buffered_bytes ic;
            Eio.Process.signal p Sys.sigkill;
            Error `Too_large
        in
        match
          Eio.Time.with_timeout clock timeout (fun () ->
              Ok
                (Eio.Fiber.pair read_out (fun () ->
                     Eio.Fiber.pair
                       (fun () -> read_tail er err)
                       (fun () -> Eio.Process.await p))))
        with
        | Error `Timeout ->
            Eio.Process.signal p Sys.sigkill;
            ignore (Eio.Process.await p);
            Timed_out
        | Ok (Error `Too_large, _) -> Output_too_large
        | Ok (_, ((), `Signaled s)) -> Signaled s
        | Ok (Ok out, ((), `Exited n)) -> Exited (n, out))
  in
  let tail = Buffer.contents err in
  let tail =
    if String.length tail > max_stderr_bytes then
      String.sub tail (String.length tail - max_stderr_bytes) max_stderr_bytes
    else tail
  in
  {
    outcome;
    duration = Unix.gettimeofday () -. start;
    output_bytes = !output_bytes;
    stderr_tail = tail;
  }

(* --- Mapping results to responses ------------------------------------------ *)

let failure ?file code message =
  I.Json.failure { failed_file = file; error = { code; message } }

let replace_all ~sub ~by s =
  if sub = "" then s
  else
    let sl = String.length sub and len = String.length s in
    let b = Buffer.create len in
    let rec go i =
      if i > len - sl then Buffer.add_string b (String.sub s i (len - i))
      else if String.sub s i sl = sub then (
        Buffer.add_string b by;
        go (i + sl))
      else (
        Buffer.add_char b s.[i];
        go (i + 1))
    in
    go 0;
    Buffer.contents b

(* Rewrite the worker's JSON for the client: the file name becomes the
   sanitised client filename and any mention of the temporary path (in
   messages, notes, ...) is replaced too. *)
let rewrite ~tmp_path ~name (json : Yojson.Safe.t) =
  let tmp_dir = Filename.dirname tmp_path
  and tmp_base = Filename.basename tmp_path in
  let scrub s =
    s
    |> replace_all ~sub:tmp_path ~by:name
    |> replace_all ~sub:tmp_base ~by:name
    |> replace_all ~sub:tmp_dir ~by:""
  in
  let rec walk : Yojson.Safe.t -> Yojson.Safe.t = function
    | `String s -> `String (scrub s)
    | `List l -> `List (List.map walk l)
    | `Assoc l -> `Assoc (List.map (fun (k, v) -> (k, walk v)) l)
    | j -> j
  in
  match walk json with
  | `Assoc fields ->
      `Assoc
        (List.map
           (function
             | "file", `Assoc f ->
                 ( "file",
                   `Assoc
                     (List.map
                        (function
                          | "name", _ -> ("name", `String name) | kv -> kv)
                        f) )
             | kv -> kv)
           fields)
  | j -> j

let status_of_code = function
  | I.Problem.Not_a_tiff -> `Unsupported_media_type
  | Internal -> `Internal_server_error
  | Invalid_request -> `Bad_request
  | File_too_large -> `Request_entity_too_large
  | Rate_limited -> `Too_many_requests
  | _ -> `Unprocessable_entity

let internal () =
  ( `Internal_server_error,
    failure I.Problem.Internal "Inspection failed unexpectedly" )

let limit_exceeded ~name ~size =
  ( `Unprocessable_entity,
    failure ~file:(name, Some size) I.Problem.Limit_exceeded
      "Inspection exceeded the time or memory limit" )

let interpret ~tmp_path ~name ~size outcome : Http.Status.t * Yojson.Safe.t =
  match outcome with
  | Timed_out | Signaled _ -> limit_exceeded ~name ~size
  | Output_too_large | Spawn_failed -> internal ()
  | Exited (code, out) -> (
      match Yojson.Safe.from_string out with
      | exception Yojson.Json_error _ -> internal ()
      | json -> (
          let json = rewrite ~tmp_path ~name json in
          let open Yojson.Safe.Util in
          let ok =
            try member "ok" json |> to_bool_option with Type_error _ -> None
          in
          match (code, ok) with
          | 0, Some true -> (`OK, json)
          | 1, Some false -> (
              let err_code =
                try json |> member "error" |> member "code" |> to_string_option
                with Type_error _ -> None
              in
              match Option.bind err_code I.Problem.code_of_string with
              | Some c -> (status_of_code c, json)
              | None -> internal ())
          | _ -> internal ()))

(* --- Logging --------------------------------------------------------------- *)

(* Short description of a run for the request log line *)
let summary r =
  let what =
    match r.outcome with
    | Exited (n, _) -> Printf.sprintf "exit=%d" n
    | Signaled s -> Printf.sprintf "signal=%d" s
    | Timed_out -> "timeout"
    | Output_too_large -> "output_too_large"
    | Spawn_failed -> "spawn_failed"
  in
  Printf.sprintf "worker=%s %.0fms out=%dB" what (r.duration *. 1000.)
    r.output_bytes

(* Worker stderr for the log, on failures only: one line, control characters
   replaced, and the temporary path scrubbed so no path is ever logged. *)
let stderr_for_log ~tmp_path r =
  match r.outcome with
  | Exited (0, _) -> None
  | _ when r.stderr_tail = "" -> None
  | _ ->
      let s =
        r.stderr_tail
        |> replace_all ~sub:tmp_path ~by:"<upload>"
        |> replace_all ~sub:(Filename.basename tmp_path) ~by:"<upload>"
        |> replace_all ~sub:(Filename.dirname tmp_path) ~by:"<tmpdir>"
        |> String.map (fun c ->
            if Char.code c < 0x20 || Char.code c = 0x7f then ' ' else c)
      in
      Some (String.trim s)
