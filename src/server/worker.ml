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

let max_output_bytes = 32 * 1024 * 1024

let script ~memory_limit_mb =
  Printf.sprintf
    "ulimit -v %d 2>/dev/null; exec \"$0\" inspect --format json \"$1\""
    (memory_limit_mb * 1024)

let run ~fs ~mgr ~clock ~bin ~timeout ~memory_limit_mb path =
  Eio.Switch.run @@ fun sw ->
  let devnull_out =
    Eio.Path.open_out ~sw ~create:`Never Eio.Path.(fs / "/dev/null")
  in
  let devnull_in = Eio.Path.open_in ~sw Eio.Path.(fs / "/dev/null") in
  let r, w = Eio.Process.pipe ~sw mgr in
  let env =
    Eio.Process.Env.of_bindings [ ("PATH", "/usr/bin:/bin"); ("LC_ALL", "C") ]
  in
  match
    Eio.Process.spawn ~sw mgr ~stdin:devnull_in ~stdout:w ~stderr:devnull_out
      ~env ~executable:"/bin/sh"
      [ "sh"; "-c"; script ~memory_limit_mb; bin; path ]
  with
  | exception Eio.Io _ -> Spawn_failed
  | p -> (
      Eio.Flow.close w;
      let read_out () =
        try Ok Eio.Buf_read.(take_all (of_flow ~max_size:max_output_bytes r))
        with Eio.Buf_read.Buffer_limit_exceeded ->
          Eio.Process.signal p Sys.sigkill;
          Error `Too_large
      in
      match
        Eio.Time.with_timeout clock timeout (fun () ->
            Ok (Eio.Fiber.pair read_out (fun () -> Eio.Process.await p)))
      with
      | Error `Timeout ->
          Eio.Process.signal p Sys.sigkill;
          ignore (Eio.Process.await p);
          Timed_out
      | Ok (Error `Too_large, _) -> Output_too_large
      | Ok (_, `Signaled s) -> Signaled s
      | Ok (Ok out, `Exited n) -> Exited (n, out))

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
