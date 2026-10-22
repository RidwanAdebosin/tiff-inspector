(* HTTP/1.1 connection handling on top of cohttp's parser.

   We drive the connection loop ourselves (instead of Cohttp_eio.Server.run)
   to control what happens when a handler answers without consuming the
   request body (e.g. 413, 429): the connection is then closed with a
   "lingering close" — shut down our sending side and drain a bounded amount
   of input — so clients reliably receive the response instead of a reset,
   and the leftover body is never parsed as a new request. *)

module Req_io = Cohttp.Request.Private.Make (Cohttp_eio.Private.IO)
module Resp_io = Cohttp.Response.Private.Make (Cohttp_eio.Private.IO)

exception Body_too_large

type request = {
  meth : Http.Method.t;
  path : string;
  headers : Http.Header.t;
  peer : string;  (** Peer IP address *)
  body : Eio.Flow.source_ty Eio.Resource.t;
}

type response = {
  status : Http.Status.t;
  headers : (string * string) list;
  body : string;
  close : bool;  (** Force closing the connection after this response *)
}

let response ?(headers = []) ?(close = false) status body =
  { status; headers; body; close }

(* --- Request body as an Eio source with a byte limit ---------------------- *)

module Body = struct
  type t = {
    read_chunk : unit -> Cohttp.Transfer.chunk;
    mutable buf : string;
    mutable pos : int;
    mutable total : int;
    limit : int;
    mutable finished : bool;
    mutable before_first_read : (unit -> unit) option;
  }

  let rec fill t =
    if t.finished then raise End_of_file;
    let data =
      match t.read_chunk () with
      | Cohttp.Transfer.Done ->
          t.finished <- true;
          raise End_of_file
      | Chunk s -> s
      | Final_chunk s ->
          t.finished <- true;
          s
    in
    t.total <- t.total + String.length data;
    if t.total > t.limit then raise Body_too_large;
    if data = "" then fill t
    else (
      t.buf <- data;
      t.pos <- 0)

  let single_read t dst =
    (match t.before_first_read with
    | Some f ->
        t.before_first_read <- None;
        f ()
    | None -> ());
    if t.pos >= String.length t.buf then fill t;
    let n = min (Cstruct.length dst) (String.length t.buf - t.pos) in
    Cstruct.blit_from_string t.buf t.pos dst 0 n;
    t.pos <- t.pos + n;
    n

  let read_methods = []
end

let body_handler = Eio.Flow.Pi.source (module Body)

let wants_continue (req : Http.Request.t) =
  req.version = `HTTP_1_1
  &&
  match Http.Header.get req.headers "expect" with
  | Some v -> String.lowercase_ascii (String.trim v) = "100-continue"
  | None -> false

let make_body ~limit (req : Http.Request.t) ic oc =
  let state =
    match Http.Request.has_body req with
    | `No ->
        {
          Body.read_chunk = (fun () -> Cohttp.Transfer.Done);
          buf = "";
          pos = 0;
          total = 0;
          limit;
          finished = true;
          before_first_read = None;
        }
    | `Yes | `Unknown ->
        let reader = Req_io.make_body_reader req ic in
        {
          Body.read_chunk = (fun () -> Req_io.read_body_chunk reader);
          buf = "";
          pos = 0;
          total = 0;
          limit;
          finished = false;
          before_first_read =
            (if wants_continue req then
               Some
                 (fun () ->
                   Eio.Buf_write.string oc "HTTP/1.1 100 Continue\r\n\r\n";
                   Eio.Buf_write.flush oc)
             else None);
        }
  in
  ( (Eio.Resource.T (state, body_handler) :> Eio.Flow.source_ty Eio.Resource.t),
    state )

(* --- Writing responses ----------------------------------------------------- *)

let write_response oc ~(meth : Http.Method.t) ~keep_alive (r : response) =
  let headers =
    Http.Header.of_list
      (("connection", if keep_alive then "keep-alive" else "close") :: r.headers)
  in
  let resp =
    Cohttp.Response.make ~status:r.status ~headers
      ~encoding:(Fixed (Int64.of_int (String.length r.body)))
      ()
  in
  Resp_io.write_header resp oc;
  if meth <> `HEAD then Eio.Buf_write.string oc r.body;
  Eio.Buf_write.flush oc

(* --- Logging -------------------------------------------------------------- *)

let clean_path p =
  let p = if String.length p > 200 then String.sub p 0 200 ^ "..." else p in
  String.map
    (fun c -> if Char.code c < 0x20 || Char.code c = 0x7f then '?' else c)
    p

let log_request ~meth ~path ~status ~start =
  Printf.eprintf "%s %s %d %.1fms\n%!"
    (Http.Method.to_string meth)
    (clean_path path)
    (Http.Status.to_int status)
    ((Unix.gettimeofday () -. start) *. 1000.)

(* --- Connection loop ------------------------------------------------------ *)

let idle_timeout = 30.
let max_header_buffer = 64 * 1024
let linger_timeout = 2.
let linger_max_bytes = 4 * 1024 * 1024

let peer_ip = function
  | `Tcp (ip, _) -> Fmt.str "%a" Eio.Net.Ipaddr.pp ip
  | `Unix _ -> "unix"

let lingering_close ~clock flow ic =
  (try Eio.Flow.shutdown flow `Send with Eio.Io _ -> ());
  let drain () =
    let rec go n =
      if n < linger_max_bytes then (
        Eio.Buf_read.ensure ic 1;
        let k = Eio.Buf_read.buffered_bytes ic in
        Eio.Buf_read.consume ic k;
        go (n + k))
    in
    try go 0
    with End_of_file | Eio.Io _ | Eio.Buf_read.Buffer_limit_exceeded -> ()
  in
  ignore (Eio.Time.with_timeout clock linger_timeout (fun () -> Ok (drain ())))

let bad_request_body =
  {|{"schema_version":"1.0","ok":false,"error":{"code":"invalid_request","message":"Malformed HTTP request"}}|}

let handle ~clock ~body_limit ~(handler : request -> response) flow peer =
  let ic =
    Eio.Buf_read.of_flow ~initial_size:0x4000 ~max_size:max_header_buffer flow
  in
  let peer = peer_ip peer in
  let linger =
    Eio.Buf_write.with_flow flow @@ fun oc ->
    let reject status =
      write_response oc ~meth:`POST ~keep_alive:false
        (response status bad_request_body
           ~headers:[ ("content-type", "application/json") ]);
      true
    in
    let rec loop () =
      match
        Eio.Time.with_timeout clock idle_timeout (fun () -> Ok (Req_io.read ic))
      with
      | Error `Timeout | Ok `Eof -> false
      | exception End_of_file -> false
      | exception Eio.Buf_read.Buffer_limit_exceeded ->
          reject `Request_header_fields_too_large
      | Ok (`Invalid _) -> reject `Bad_request
      | Ok (`Ok req) ->
          let start = Unix.gettimeofday () in
          let body, state = make_body ~limit:body_limit req ic oc in
          let path = Uri.path (Uri.of_string (Http.Request.resource req)) in
          let r =
            handler { meth = req.meth; path; headers = req.headers; peer; body }
          in
          let finished = state.finished in
          let keep_alive =
            Http.Request.is_keep_alive req && finished && not r.close
          in
          write_response oc ~meth:req.meth ~keep_alive r;
          log_request ~meth:req.meth ~path ~status:r.status ~start;
          if keep_alive then loop () else not finished
    in
    loop ()
  in
  if linger then lingering_close ~clock flow ic
