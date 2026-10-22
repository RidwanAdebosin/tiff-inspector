(* Request routing and the inspection endpoint *)

module I = Tiff_inspector

type ctx = {
  config : Config.t;
  clock : float Eio.Time.clock_ty Eio.Resource.t;
  fs : Eio.Fs.dir_ty Eio.Path.t;
  inspect : string -> Worker.outcome;  (** Runs the worker on a temp file *)
  tmp_dir : string;
  limiter : Rate_limit.t;
  slots : Eio.Semaphore.t;
}

let common_headers =
  [ ("x-content-type-options", "nosniff"); ("referrer-policy", "no-referrer") ]

let json_response ?(headers = []) ?close status json =
  Conn.response ?close status (I.Json.to_string json)
    ~headers:
      (common_headers
      @ [ ("content-type", "application/json"); ("cache-control", "no-store") ]
      @ headers)

let error ?headers ?close ?file status code message =
  json_response ?headers ?close status (Worker.failure ?file code message)

(* Time to wait for a free worker slot before answering 429 *)
let slot_wait = 5.

(* Upper bound on receiving one upload *)
let upload_timeout = 120.

let client_ip ctx (req : Conn.request) =
  if ctx.config.trust_proxy then
    match Http.Header.get req.headers "x-forwarded-for" with
    | Some v -> (
        match String.trim (List.hd (String.split_on_char ',' v)) with
        | "" -> req.peer
        | ip -> ip)
    | None -> req.peer
  else req.peer

let content_length (req : Conn.request) =
  match Http.Header.get req.headers "content-length" with
  | None -> Ok None
  | Some v -> (
      match int_of_string_opt (String.trim v) with
      | Some n when n >= 0 -> Ok (Some n)
      | _ -> Error ())

let with_slot ctx f =
  match
    Eio.Time.with_timeout ctx.clock slot_wait (fun () ->
        Eio.Semaphore.acquire ctx.slots;
        Ok ())
  with
  | Error `Timeout ->
      error `Too_many_requests I.Problem.Rate_limited
        "Server is busy; try again later" ~close:true
        ~headers:[ ("retry-after", "5") ]
  | Ok () -> Fun.protect ~finally:(fun () -> Eio.Semaphore.release ctx.slots) f

(* Receive the upload into [tmp] and inspect it *)
let receive_and_inspect ctx (req : Conn.request) ~boundary tmp =
  let max = ctx.config.max_upload_bytes in
  let received =
    Eio.Switch.run @@ fun sw ->
    let file =
      Eio.Path.open_out ~sw ~follow:false ~create:(`Exclusive 0o600)
        Eio.Path.(ctx.fs / tmp)
    in
    let ic =
      Eio.Buf_read.of_flow ~initial_size:65536 ~max_size:(1024 * 1024) req.body
    in
    Eio.Time.with_timeout ctx.clock upload_timeout (fun () ->
        Ok
          (try
             Multipart.parse ~boundary ~max_file_bytes:max ic ~write:(fun s ->
                 Eio.Flow.copy_string s file)
           with Conn.Body_too_large -> Error Multipart.File_too_large))
  in
  match received with
  | Error `Timeout ->
      error `Bad_request I.Problem.Invalid_request "Upload timed out"
        ~close:true
  | Ok (Error Multipart.File_too_large) ->
      error `Request_entity_too_large I.Problem.File_too_large
        (Printf.sprintf "The uploaded file exceeds the limit of %d bytes" max)
        ~close:true
  | Ok (Error e) ->
      error `Bad_request I.Problem.Invalid_request
        (Multipart.error_message e)
        ~close:true
  | Ok (Ok f) ->
      let name = Multipart.sanitize_filename f.filename in
      if not (Signature.is_tiff f.head) then
        error `Unsupported_media_type I.Problem.Not_a_tiff
          "The file does not start with a TIFF signature"
          ~file:(name, Some f.size)
      else
        let status, json =
          Worker.interpret ~tmp_path:tmp ~name ~size:f.size (ctx.inspect tmp)
        in
        json_response status json

let inspections ctx (req : Conn.request) =
  match
    Rate_limit.check ctx.limiter ~now:(Unix.gettimeofday ()) (client_ip ctx req)
  with
  | Error retry ->
      error `Too_many_requests I.Problem.Rate_limited
        "Too many requests; try again later" ~close:true
        ~headers:[ ("retry-after", string_of_int retry) ]
  | Ok () -> (
      match
        Multipart.boundary_of_content_type
          (Option.value ~default:""
             (Http.Header.get req.headers "content-type"))
      with
      | Error msg ->
          error `Bad_request I.Problem.Invalid_request msg ~close:true
      | Ok boundary -> (
          match content_length req with
          | Error () ->
              error `Bad_request I.Problem.Invalid_request
                "Invalid Content-Length" ~close:true
          | Ok (Some n) when n > Config.max_body_bytes ctx.config ->
              error `Request_entity_too_large I.Problem.File_too_large
                (Printf.sprintf
                   "The uploaded file exceeds the limit of %d bytes"
                   ctx.config.max_upload_bytes)
                ~close:true
          | Ok _ ->
              with_slot ctx (fun () ->
                  let tmp = Tempdir.file_in ctx.tmp_dir in
                  Fun.protect
                    ~finally:(fun () ->
                      try Unix.unlink tmp with Unix.Unix_error _ -> ())
                    (fun () -> receive_and_inspect ctx req ~boundary tmp))))

let health = json_response `OK (`Assoc [ ("status", `String "ok") ])

let method_not_allowed allow =
  error `Method_not_allowed I.Problem.Invalid_request "Method not allowed"
    ~headers:[ ("allow", allow) ]

let not_found () = error `Not_found I.Problem.Invalid_request "Not found"

let static ctx (req : Conn.request) =
  match (ctx.config.static_dir, req.meth) with
  | Some root, (`GET | `HEAD) -> (
      match Static.resolve ~root req.path with
      | Some (file, body) ->
          Conn.response `OK body ~headers:(common_headers @ Static.headers file)
      | None -> not_found ())
  | Some _, _ -> method_not_allowed "GET, HEAD"
  | None, _ -> not_found ()

let handle ctx (req : Conn.request) =
  match (req.path, req.meth) with
  | "/api/v1/health", (`GET | `HEAD) -> health
  | "/api/v1/health", _ -> method_not_allowed "GET, HEAD"
  | "/api/v1/inspections", `POST -> inspections ctx req
  | "/api/v1/inspections", _ -> method_not_allowed "POST"
  | p, _ when p = "/api" || String.starts_with ~prefix:"/api/" p -> not_found ()
  | _ -> static ctx req

(* Never let an exception escape as a stack trace *)
let handler ctx req =
  try handle ctx req with
  | Eio.Cancel.Cancelled _ as e -> raise e
  | e ->
      Printf.eprintf "internal error: %s\n%!" (Printexc.to_string e);
      error `Internal_server_error I.Problem.Internal "Internal server error"
        ~close:true
