(* Request routing and the inspection endpoint *)

module I = Tiff_inspector

type ctx = {
  config : Config.t;
  clock : float Eio.Time.clock_ty Eio.Resource.t;
  fs : Eio.Fs.dir_ty Eio.Path.t;
  inspect : string -> Worker.result;  (** Runs the worker on a temp file *)
  bin : string;  (** Worker executable, re-checked by the health endpoint *)
  tmp_dir : string;
  limiter : Rate_limit.t;
  slots : Eio.Semaphore.t;  (** Worker slots: held only while a worker runs *)
  uploads : Eio.Semaphore.t;  (** Uploads being received *)
  draining : unit -> bool;  (** Shutdown in progress *)
}

let common_headers (config : Config.t) =
  [
    ("x-content-type-options", "nosniff");
    ("x-frame-options", "DENY");
    ("referrer-policy", "no-referrer");
    ("permissions-policy", "camera=(), microphone=(), geolocation=()");
    ("cross-origin-opener-policy", "same-origin");
  ]
  @
  if config.hsts then
    [ ("strict-transport-security", "max-age=31536000; includeSubDomains") ]
  else []

let json_response ?(headers = []) ?close ?note ctx status json =
  Conn.response ?close ?note status (I.Json.to_string json)
    ~headers:
      (common_headers ctx.config
      @ [ ("content-type", "application/json"); ("cache-control", "no-store") ]
      @ headers)

let error ?headers ?close ?file ctx status code message =
  json_response ?headers ?close ctx status (Worker.failure ?file code message)

(* Time to wait for a free worker slot before answering 429 *)
let slot_wait = 5.

(* Bytes of body drained after the closing multipart delimiter (the chunked
   terminator, a trailing CRLF, an epilogue) so the connection can be reused *)
let max_trailer_bytes = 65536

let client_ip ctx (req : Conn.request) =
  Ip.client_ip ~proxy:ctx.config.trust_proxy ~peer:req.peer req.headers

let busy ctx =
  error ctx `Too_many_requests I.Problem.Rate_limited
    "Server is busy; try again later" ~close:true
    ~headers:[ ("retry-after", "5") ]

(* Run [f] holding a worker slot, waiting up to [slot_wait] for one *)
let with_slot ctx f =
  match
    Eio.Time.with_timeout ctx.clock slot_wait (fun () ->
        Eio.Semaphore.acquire ctx.slots;
        Ok ())
  with
  | Error `Timeout -> busy ctx
  | Ok () -> Fun.protect ~finally:(fun () -> Eio.Semaphore.release ctx.slots) f

(* Run [f] holding an upload slot; never waits for one. The server runs in a
   single domain and does not yield between the check and the acquire. *)
let with_upload_slot ctx f =
  if Eio.Semaphore.get_value ctx.uploads = 0 then Error (busy ctx)
  else (
    Eio.Semaphore.acquire ctx.uploads;
    Fun.protect ~finally:(fun () -> Eio.Semaphore.release ctx.uploads) f)

(* --- Receiving the upload -------------------------------------------------- *)

exception Upload_idle

(* A source that fails with [Upload_idle] when one read delivers nothing for
   [timeout] seconds *)
module Idle_source = struct
  type t = {
    src : Eio.Flow.source_ty Eio.Resource.t;
    clock : float Eio.Time.clock_ty Eio.Resource.t;
    timeout : float;
  }

  let single_read t dst =
    match
      Eio.Time.with_timeout t.clock t.timeout (fun () ->
          Ok (Eio.Flow.single_read t.src dst))
    with
    | Ok n -> n
    | Error `Timeout -> raise Upload_idle

  let read_methods = []
end

let idle_source_ops = Eio.Flow.Pi.source (module Idle_source)

let idle_source ctx src =
  (Eio.Resource.T
     ( {
         Idle_source.src;
         clock = ctx.clock;
         timeout = ctx.config.upload_idle_timeout;
       },
       idle_source_ops )
    :> Eio.Flow.source_ty Eio.Resource.t)

(* Consume what follows the closing delimiter, within a bound. Only when the
   body ends within the bound does the connection stay reusable. *)
let drain_trailer ic =
  let rec go n =
    if n < max_trailer_bytes then (
      Eio.Buf_read.ensure ic 1;
      let k = Eio.Buf_read.buffered_bytes ic in
      Eio.Buf_read.consume ic k;
      go (n + k))
  in
  try go 0 with End_of_file | Conn.Body_too_large -> ()

(* Receive the [file] part of the upload into [tmp] *)
let receive ctx (req : Conn.request) ~boundary tmp :
    (Multipart.file, Conn.response) result =
  let max = ctx.config.max_upload_bytes in
  let received =
    Eio.Switch.run @@ fun sw ->
    let file =
      Eio.Path.open_out ~sw ~follow:false ~create:(`Exclusive 0o600)
        Eio.Path.(ctx.fs / tmp)
    in
    let ic =
      Eio.Buf_read.of_flow ~initial_size:65536 ~max_size:(1024 * 1024)
        (idle_source ctx req.body)
    in
    match
      Eio.Time.with_timeout ctx.clock ctx.config.upload_timeout (fun () ->
          Ok
            (try
               let r =
                 Multipart.parse ~boundary ~max_file_bytes:max ic
                   ~write:(fun s -> Eio.Flow.copy_string s file)
               in
               if Result.is_ok r then drain_trailer ic;
               r
             with Conn.Body_too_large -> Error Multipart.File_too_large))
    with
    | Error `Timeout -> `Timeout
    | Ok r -> `Parsed r
    | exception Upload_idle -> `Idle
  in
  match received with
  | `Timeout ->
      Error
        (error ctx `Bad_request I.Problem.Invalid_request "Upload timed out"
           ~close:true)
  | `Idle ->
      Error
        (error ctx `Bad_request I.Problem.Invalid_request
           "Upload stalled: no data received" ~close:true)
  | `Parsed (Error Multipart.File_too_large) ->
      Error
        (error ctx `Request_entity_too_large I.Problem.File_too_large
           (Printf.sprintf "The uploaded file exceeds the limit of %d bytes" max)
           ~close:true)
  | `Parsed (Error e) ->
      Error
        (error ctx `Bad_request I.Problem.Invalid_request
           (Multipart.error_message e)
           ~close:true)
  | `Parsed (Ok f) -> Ok f

(* --- The inspection endpoint ------------------------------------------------ *)

(* Inspect the received file in [tmp] under a worker slot *)
let inspect ctx ~name ~size tmp =
  with_slot ctx (fun () ->
      let r = ctx.inspect tmp in
      Option.iter
        (fun s -> Printf.eprintf "worker stderr: %s\n%!" s)
        (Worker.stderr_for_log ~tmp_path:tmp r);
      let status, json = Worker.interpret ~tmp_path:tmp ~name ~size r.outcome in
      json_response ctx status json ~note:(Worker.summary r))

let receive_and_inspect ctx (req : Conn.request) ~boundary =
  let tmp = Tempdir.file_in ctx.tmp_dir in
  Fun.protect
    ~finally:(fun () -> try Unix.unlink tmp with Unix.Unix_error _ -> ())
    (fun () ->
      match with_upload_slot ctx (fun () -> receive ctx req ~boundary tmp) with
      | Error response -> response
      | Ok f ->
          let name = Multipart.sanitize_filename f.filename in
          if not (Signature.is_tiff f.head) then
            error ctx `Unsupported_media_type I.Problem.Not_a_tiff
              "The file does not start with a TIFF signature"
              ~file:(name, Some f.size)
          else inspect ctx ~name ~size:f.size tmp)

let inspections ctx (req : Conn.request) =
  match
    Rate_limit.check ctx.limiter ~now:(Unix.gettimeofday ()) (client_ip ctx req)
  with
  | Error retry ->
      error ctx `Too_many_requests I.Problem.Rate_limited
        "Too many requests; try again later" ~close:true
        ~headers:[ ("retry-after", string_of_int retry) ]
  | Ok () -> (
      match req.framing with
      | Framing.Empty ->
          error ctx `Length_required I.Problem.Invalid_request
            "Content-Length or Transfer-Encoding: chunked is required"
            ~close:true
      | Fixed n when n > Config.max_body_bytes ctx.config ->
          error ctx `Request_entity_too_large I.Problem.File_too_large
            (Printf.sprintf "The uploaded file exceeds the limit of %d bytes"
               ctx.config.max_upload_bytes)
            ~close:true
      | Fixed _ | Chunked -> (
          match
            Multipart.boundary_of_content_type
              (Option.value ~default:""
                 (Http.Header.get req.headers "content-type"))
          with
          | Error msg ->
              error ctx `Bad_request I.Problem.Invalid_request msg ~close:true
          | Ok boundary -> receive_and_inspect ctx req ~boundary))

(* --- Health and version ---------------------------------------------------- *)

let writable_dir d =
  try
    Unix.access d [ Unix.W_OK; Unix.X_OK ];
    Sys.is_directory d
  with Unix.Unix_error _ | Sys_error _ -> false

let workers_busy ctx = ctx.config.workers - Eio.Semaphore.get_value ctx.slots

let health ctx =
  let worker_ok = Worker.executable ctx.bin in
  let tmp_ok = writable_dir ctx.tmp_dir in
  let status, text =
    if ctx.draining () then (`Service_unavailable, "draining")
    else if worker_ok && tmp_ok then (`OK, "ok")
    else (`Service_unavailable, "unavailable")
  in
  let check b = `String (if b then "ok" else "failed") in
  json_response ctx status
    (`Assoc
       [
         ("status", `String text);
         ("version", `String I.Version.v);
         ("schema_version", `String I.Report.schema_version);
         ("workers_busy", `Int (workers_busy ctx));
         ( "checks",
           `Assoc [ ("worker", check worker_ok); ("temp_dir", check tmp_ok) ] );
       ])

let version ctx =
  json_response ctx `OK
    (`Assoc
       [
         ("tool", `String "tiff-inspector");
         ("version", `String I.Version.v);
         ("schema_version", `String I.Report.schema_version);
         ( "limits",
           `Assoc
             [
               ("max_upload_bytes", `Int ctx.config.max_upload_bytes);
               ("timeout_seconds", `Float ctx.config.timeout);
             ] );
       ])

(* --- Routing --------------------------------------------------------------- *)

let method_not_allowed ctx allow =
  error ctx `Method_not_allowed I.Problem.Invalid_request "Method not allowed"
    ~headers:[ ("allow", allow) ]

let not_found ctx = error ctx `Not_found I.Problem.Invalid_request "Not found"

let static ctx (req : Conn.request) =
  match (ctx.config.static_dir, req.meth) with
  | Some root, (`GET | `HEAD) -> (
      match Static.resolve ~root req.path with
      | Some (file, body) ->
          Conn.response `OK body
            ~headers:(common_headers ctx.config @ Static.headers file)
      | None -> not_found ctx)
  | Some _, _ -> method_not_allowed ctx "GET, HEAD"
  | None, _ -> not_found ctx

let handle ctx (req : Conn.request) =
  match (req.path, req.meth) with
  | "/api/v1/health", (`GET | `HEAD) -> health ctx
  | "/api/v1/health", _ -> method_not_allowed ctx "GET, HEAD"
  | "/api/v1/version", (`GET | `HEAD) -> version ctx
  | "/api/v1/version", _ -> method_not_allowed ctx "GET, HEAD"
  | "/api/v1/inspections", `POST -> inspections ctx req
  | "/api/v1/inspections", _ -> method_not_allowed ctx "POST"
  | p, _ when p = "/api" || String.starts_with ~prefix:"/api/" p ->
      not_found ctx
  | _ -> static ctx req

(* Never let an exception escape as a stack trace *)
let handler ctx req =
  try handle ctx req with
  | Eio.Cancel.Cancelled _ as e -> raise e
  | e ->
      Printf.eprintf "internal error: %s\n%!" (Printexc.to_string e);
      error ctx `Internal_server_error I.Problem.Internal
        "Internal server error" ~close:true
