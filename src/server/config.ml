(* Server configuration: command line flags with TIFF_INSPECTOR_* fallbacks *)

open Cmdliner

type t = {
  host : string;
  port : int;
  max_upload_bytes : int;
  timeout : float;
  memory_limit_mb : int;
  workers : int;
  rate_limit : int;
  static_dir : string option;
  inspector_bin : string option;
  trust_proxy : bool;
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
        ~doc:"Maximum number of concurrent inspections.")

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

let trust_proxy =
  Arg.(
    value & flag
    & info [ "trust-proxy" ] ~env:(env "TRUST_PROXY")
        ~doc:
          "Use the first X-Forwarded-For hop as client address for rate \
           limiting.")

let validate t =
  if t.port < 0 || t.port > 65535 then
    Error "--port must be between 0 and 65535"
  else if t.max_upload_bytes < 1 then
    Error "--max-upload-bytes must be positive"
  else if not (t.timeout > 0.) then Error "--timeout must be positive"
  else if t.memory_limit_mb < 1 then Error "--memory-limit-mb must be positive"
  else if t.workers < 1 then Error "--workers must be at least 1"
  else Ok t

let term =
  let make host port max_upload_bytes timeout memory_limit_mb workers rate_limit
      static_dir inspector_bin trust_proxy =
    validate
      {
        host;
        port;
        max_upload_bytes;
        timeout;
        memory_limit_mb;
        workers;
        rate_limit;
        static_dir;
        inspector_bin;
        trust_proxy;
      }
  in
  Term.(
    term_result' ~usage:true
      (const make $ host $ port $ max_upload_bytes $ timeout $ memory_limit_mb
     $ workers $ rate_limit $ static_dir $ inspector_bin $ trust_proxy))
