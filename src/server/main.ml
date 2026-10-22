(* tiff-inspector-server: HTTP API for TIFF inspection.

   TIFF parsing never happens in this process: each upload is inspected by a
   separate tiff-inspector worker process (see Worker). *)

open Tiff_inspector_server

let is_executable = Worker.executable

let absolute p =
  if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p

let find_inspector = function
  | Some p ->
      if is_executable p then Ok (absolute p)
      else Error ("not an executable: " ^ p)
  | None -> (
      let siblings =
        List.map
          (fun exe ->
            Filename.concat (Filename.dirname (absolute exe)) "tiff-inspector")
          [ Sys.executable_name; Sys.argv.(0) ]
      in
      let path_dirs =
        match Sys.getenv_opt "PATH" with
        | Some p -> String.split_on_char ':' p |> List.filter (( <> ) "")
        | None -> []
      in
      let from_path =
        List.map (fun d -> Filename.concat d "tiff-inspector") path_dirs
      in
      match List.find_opt is_executable (siblings @ from_path) with
      | Some p -> Ok (absolute p)
      | None ->
          Error "cannot find the tiff-inspector executable; use --inspector-bin"
      )

let resolve_static = function
  | None -> Ok None
  | Some d -> (
      match Unix.realpath d with
      | p when Sys.is_directory p -> Ok (Some p)
      | _ -> Error ("not a directory: " ^ d)
      | exception Unix.Unix_error _ -> Error ("not a directory: " ^ d))

let listen_addr net host port =
  match Unix.inet_addr_of_string host with
  | a -> Ok (`Tcp (Eio_unix.Net.Ipaddr.of_unix a, port))
  | exception Failure _ -> (
      match
        Eio.Net.getaddrinfo_stream net host ~service:(string_of_int port)
      with
      | a :: _ -> Ok a
      | [] -> Error ("cannot resolve host " ^ host))

let max_connections = 512

(* Like [Eio.Net.run_server ~stop], but the listening socket is closed as
   soon as [stop] resolves, so new connections are refused during the drain
   instead of waiting in the backlog. Returns once every accepted connection
   has finished. *)
let serve_until ~stop socket handler =
  let on_error = function
    | Eio.Io _ | End_of_file -> ()
    | e -> Printf.eprintf "connection error: %s\n%!" (Printexc.to_string e)
  in
  Eio.Switch.run @@ fun sw ->
  let connections = Eio.Semaphore.make max_connections in
  let rec accept () =
    Eio.Semaphore.acquire connections;
    Eio.Net.accept_fork ~sw ~on_error socket (fun conn addr ->
        Fun.protect
          (fun () -> handler conn addr)
          ~finally:(fun () -> Eio.Semaphore.release connections));
    accept ()
  in
  Eio.Fiber.first accept (fun () -> Eio.Promise.await stop);
  Eio.Net.close socket

let serve (config : Config.t) =
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  match
    (find_inspector config.inspector_bin, resolve_static config.static_dir)
  with
  | Error e, _ | _, Error e ->
      prerr_endline ("tiff-inspector-server: " ^ e);
      1
  | Ok bin, Ok static_dir -> (
      let config = { config with static_dir } in
      Eio_main.run @@ fun env ->
      let net = Eio.Stdenv.net env in
      let clock =
        (Eio.Stdenv.clock env :> float Eio.Time.clock_ty Eio.Resource.t)
      in
      let fs = (Eio.Stdenv.fs env :> Eio.Fs.dir_ty Eio.Path.t) in
      let mgr = Eio.Stdenv.process_mgr env in
      match listen_addr net config.host config.port with
      | Error e ->
          prerr_endline ("tiff-inspector-server: " ^ e);
          1
      | Ok addr ->
          (* Shutdown: the first SIGTERM/SIGINT resolves [stop] (no new
             connections, health 503, in-flight requests finish); after
             [drain_timeout], or on a second signal, everything is cancelled. *)
          let signals = ref 0 in
          let signalled = Eio.Condition.create () in
          let on_signal (_ : int) =
            incr signals;
            Eio.Condition.broadcast signalled
          in
          Sys.set_signal Sys.sigint (Signal_handle on_signal);
          Sys.set_signal Sys.sigterm (Signal_handle on_signal);
          let stop, resolve_stop = Eio.Promise.create () in
          let force, resolve_force = Eio.Promise.create () in
          let tmp_dir = ref None in
          let finish how =
            Option.iter
              (fun d ->
                Tempdir.clean d;
                try Unix.rmdir d with Unix.Unix_error _ -> ())
              !tmp_dir;
            Printf.eprintf "tiff-inspector-server: stopped (%s)\n%!" how;
            0
          in
          Eio.Switch.run @@ fun sw ->
          let socket =
            Eio.Net.listen ~sw ~reuse_addr:true ~backlog:128 net addr
          in
          let port =
            match Eio.Net.listening_addr socket with
            | `Tcp (_, p) -> p
            | `Unix _ -> 0
          in
          let dir = Tempdir.setup ~port in
          tmp_dir := Some dir;
          let ctx =
            {
              Routes.config;
              clock;
              fs;
              bin;
              tmp_dir = dir;
              limiter = Rate_limit.create ~per_minute:config.rate_limit;
              slots = Eio.Semaphore.make config.workers;
              uploads = Eio.Semaphore.make config.max_uploads;
              inspect =
                Worker.run ~fs ~mgr ~clock ~bin ~timeout:config.timeout
                  ~memory_limit_mb:config.memory_limit_mb;
              draining = (fun () -> Eio.Promise.is_resolved stop);
            }
          in
          Printf.eprintf
            "tiff-inspector-server %s listening on http://%s:%d (worker: %s)\n\
             %!"
            Tiff_inspector.Version.v config.host port bin;
          Eio.Fiber.fork_daemon ~sw (fun () ->
              while !signals < 1 do
                Eio.Condition.await_no_mutex signalled
              done;
              Printf.eprintf
                "tiff-inspector-server: draining, up to %gs for in-flight \
                 requests\n\
                 %!"
                config.drain_timeout;
              Eio.Promise.resolve resolve_stop ();
              while !signals < 2 do
                Eio.Condition.await_no_mutex signalled
              done;
              Eio.Promise.resolve resolve_force ();
              `Stop_daemon);
          let how =
            Eio.Fiber.any
              [
                (fun () ->
                  serve_until ~stop socket
                    (Conn.handle ~clock
                       ~body_limit:(Config.max_body_bytes config)
                       ~stop ~handler:(Routes.handler ctx));
                  "drained");
                (fun () ->
                  Eio.Promise.await stop;
                  Eio.Time.sleep clock config.drain_timeout;
                  "drain timeout");
                (fun () ->
                  Eio.Promise.await force;
                  "second signal");
              ]
          in
          finish how)

let cmd =
  let open Cmdliner in
  let doc = "HTTP API for inspecting TIFF files" in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Serves $(b,POST /api/v1/inspections) (multipart field $(b,file)), \
         $(b,GET /api/v1/health) and $(b,GET /api/v1/version). Each upload is \
         inspected by a separate $(b,tiff-inspector) process with a time and \
         memory limit.";
    ]
  in
  Cmd.v
    (Cmd.info "tiff-inspector-server" ~version:Tiff_inspector.Version.v ~doc
       ~man)
    Term.(const serve $ Config.term)

let () = exit (Cmdliner.Cmd.eval' cmd)
