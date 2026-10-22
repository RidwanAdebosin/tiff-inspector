(* tiff-inspector-server: HTTP API for TIFF inspection.

   TIFF parsing never happens in this process: each upload is inspected by a
   separate tiff-inspector worker process (see Worker). *)

open Tiff_inspector_server

exception Shutdown

let is_executable p =
  try
    Unix.access p [ Unix.X_OK ];
    (Unix.stat p).st_kind = S_REG
  with Unix.Unix_error _ -> false

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
      | Ok addr -> (
          let stop = Eio.Condition.create () in
          let on_signal (_ : int) = Eio.Condition.broadcast stop in
          Sys.set_signal Sys.sigint (Signal_handle on_signal);
          Sys.set_signal Sys.sigterm (Signal_handle on_signal);
          let tmp_dir = ref None in
          try
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
                tmp_dir = dir;
                limiter = Rate_limit.create ~per_minute:config.rate_limit;
                slots = Eio.Semaphore.make config.workers;
                inspect =
                  Worker.run ~fs ~mgr ~clock ~bin ~timeout:config.timeout
                    ~memory_limit_mb:config.memory_limit_mb;
              }
            in
            Printf.eprintf
              "tiff-inspector-server %s listening on http://%s:%d (worker: %s)\n\
               %!"
              Tiff_inspector.Version.v config.host port bin;
            Eio.Fiber.fork ~sw (fun () ->
                Eio.Condition.await_no_mutex stop;
                raise Shutdown);
            Eio.Net.run_server socket ~max_connections:512
              ~on_error:(fun e ->
                match e with
                | Eio.Io _ | End_of_file -> ()
                | e ->
                    Printf.eprintf "connection error: %s\n%!"
                      (Printexc.to_string e))
              (Conn.handle ~clock
                 ~body_limit:(Config.max_body_bytes config)
                 ~handler:(Routes.handler ctx))
          with Shutdown ->
            Option.iter
              (fun d ->
                Tempdir.clean d;
                try Unix.rmdir d with Unix.Unix_error _ -> ())
              !tmp_dir;
            prerr_endline "tiff-inspector-server: stopped";
            0))

let cmd =
  let open Cmdliner in
  let doc = "HTTP API for inspecting TIFF files" in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Serves $(b,POST /api/v1/inspections) (multipart field $(b,file)) and \
         $(b,GET /api/v1/health). Each upload is inspected by a separate \
         $(b,tiff-inspector) process with a time and memory limit.";
    ]
  in
  Cmd.v
    (Cmd.info "tiff-inspector-server" ~version:Tiff_inspector.Version.v ~doc
       ~man)
    Term.(const serve $ Config.term)

let () = exit (Cmdliner.Cmd.eval' cmd)
