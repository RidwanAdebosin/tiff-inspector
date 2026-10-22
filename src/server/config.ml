(* Server configuration: command line flags with TIFF_INSPECTOR_* fallbacks *)

open Cmdliner

type t = {
  host : string;
  port : int;
  max_upload_bytes : int;
  timeout : float;
  memory_limit_mb : int;
  workers : int;
  max_uploads : int;
  upload_idle_timeout : float;
  upload_timeout : float;
  drain_timeout : float;
  rate_limit : int;
  static_dir : string option;
  inspector_bin : string option;
  trust_proxy : Ip.proxy;
  hsts : bool;
}

(* Extra bytes allowed on top of the file limit for multipart framing and
   other small form fields. *)
let multipart_overhead = 65536
let max_body_bytes t = t.max_upload_bytes + multipart_overhead
let env name = Cmd.Env.info ("TIFF_INSPECTOR_" ^ name)

let host =
  Arg.(
    value & opt string "127.0.0.1"
    & info [ "host" ] ~env:(env "HOST") ~docv:"ADDR"
        ~doc:"Address to listen on.")

let port =
  Arg.(
    value & opt int 8080
    & info [ "port" ] ~env:(env "PORT") ~docv:"PORT"
        ~doc:
          "Port to listen on (0 picks a free port; the actual port is logged).")

let max_upload_bytes =
  Arg.(
    value & opt int 26214400
    & info [ "max-upload-bytes" ] ~env:(env "MAX_UPLOAD_BYTES") ~docv:"BYTES"
        ~doc:"Maximum size of an uploaded file.")

let timeout =
  Arg.(
    value & opt float 10.
    & info [ "timeout" ] ~env:(env "TIMEOUT") ~docv:"SECONDS"
        ~doc:"Wall-clock limit for one inspection worker.")

let memory_limit_mb =
  Arg.(
    value & opt int 512
    & info [ "memory-limit-mb" ] ~env:(env "MEMORY_LIMIT_MB") ~docv:"MB"
        ~doc:
          "Virtual memory limit for one inspection worker (ulimit -v; not \
           enforced on macOS).")

let workers =
  Arg.(
    value & opt int 4
    & info [ "workers" ] ~env:(env "WORKERS") ~docv:"N"
        ~doc:
          "Maximum number of concurrent inspection workers. A worker slot is \
           only held while the worker runs, not while the upload is received.")

let max_uploads =
  Arg.(
    value & opt int 32
    & info [ "max-uploads" ] ~env:(env "MAX_UPLOADS") ~docv:"N"
        ~doc:
          "Maximum number of uploads being received at the same time (more are \
           answered 429).")

let upload_idle_timeout =
  Arg.(
    value & opt float 20.
    & info [ "upload-idle-timeout" ]
        ~env:(env "UPLOAD_IDLE_TIMEOUT")
        ~docv:"SECONDS"
        ~doc:
          "An upload that sends no bytes for this long is rejected (400) so \
           stalled clients cannot pin resources.")

let upload_timeout =
  Arg.(
    value & opt float 300.
    & info [ "upload-timeout" ] ~env:(env "UPLOAD_TIMEOUT") ~docv:"SECONDS"
        ~doc:"Total time allowed for receiving one upload.")

let drain_timeout =
  Arg.(
    value & opt float 15.
    & info [ "drain-timeout" ] ~env:(env "DRAIN_TIMEOUT") ~docv:"SECONDS"
        ~doc:
          "On SIGTERM/SIGINT, stop accepting connections and wait up to this \
           long for in-flight requests before exiting (a second signal exits \
           at once).")

let rate_limit =
  Arg.(
    value & opt int 30
    & info [ "rate-limit" ] ~env:(env "RATE_LIMIT") ~docv:"N"
        ~doc:"Inspection requests per minute per client IP (0 disables).")

let static_dir =
  Arg.(
    value
    & opt (some string) None
    & info [ "static-dir" ] ~env:(env "STATIC_DIR") ~docv:"DIR"
        ~doc:"Serve the built web app from $(docv).")

let inspector_bin =
  Arg.(
    value
    & opt (some string) None
    & info [ "inspector-bin" ] ~env:(env "INSPECTOR_BIN") ~docv:"PATH"
        ~doc:
          "The tiff-inspector CLI used as worker (default: next to this \
           executable, else from PATH).")

let proxy_conv =
  let parse s = Result.map_error (fun m -> `Msg m) (Ip.proxy_of_string s) in
  let print ppf p = Format.pp_print_string ppf (Ip.proxy_to_string p) in
  Arg.conv (parse, print)

let trust_proxy =
  Arg.(
    value
    & opt ~vopt:Ip.Xff proxy_conv Ip.Off
    & info [ "trust-proxy" ] ~env:(env "TRUST_PROXY") ~docv:"MODE"
        ~doc:
          "Take the client address for rate limiting from proxy headers \
           instead of the socket peer. Only enable behind a proxy you control. \
           $(docv) is $(b,xff) (the default when no value is given, or \
           $(b,true)): the last $(b,X-Forwarded-For) hop, i.e. the one the \
           proxy appended; or $(b,cloudflare): $(b,True-Client-IP) or \
           $(b,CF-Connecting-IP) when present, else the last \
           $(b,X-Forwarded-For) hop (only safe when the proxy overwrites those \
           headers). A value that is not an IP address falls back to the peer. \
           $(b,off) disables.")

let hsts =
  Arg.(
    value & flag
    & info [ "hsts" ] ~env:(env "HSTS")
        ~doc:
          "Send $(b,Strict-Transport-Security: max-age=31536000; \
           includeSubDomains). Only when every client reaches the service over \
           HTTPS (e.g. through a TLS-terminating proxy).")

let validate t =
  if t.port < 0 || t.port > 65535 then
    Error "--port must be between 0 and 65535"
  else if t.max_upload_bytes < 1 then
    Error "--max-upload-bytes must be positive"
  else if not (t.timeout > 0.) then Error "--timeout must be positive"
  else if t.memory_limit_mb < 1 then Error "--memory-limit-mb must be positive"
  else if t.workers < 1 then Error "--workers must be at least 1"
  else if t.max_uploads < 1 then Error "--max-uploads must be at least 1"
  else if not (t.upload_idle_timeout > 0.) then
    Error "--upload-idle-timeout must be positive"
  else if not (t.upload_timeout > 0.) then
    Error "--upload-timeout must be positive"
  else if not (t.drain_timeout >= 0.) then
    Error "--drain-timeout must not be negative"
  else Ok t

let term =
  let make host port max_upload_bytes timeout memory_limit_mb workers
      max_uploads upload_idle_timeout upload_timeout drain_timeout rate_limit
      static_dir inspector_bin trust_proxy hsts =
    validate
      {
        host;
        port;
        max_upload_bytes;
        timeout;
        memory_limit_mb;
        workers;
        max_uploads;
        upload_idle_timeout;
        upload_timeout;
        drain_timeout;
        rate_limit;
        static_dir;
        inspector_bin;
        trust_proxy;
        hsts;
      }
  in
  Term.(
    term_result' ~usage:true
      (const make $ host $ port $ max_upload_bytes $ timeout $ memory_limit_mb
     $ workers $ max_uploads $ upload_idle_timeout $ upload_timeout
     $ drain_timeout $ rate_limit $ static_dir $ inspector_bin $ trust_proxy
     $ hsts))
