(* Private directory for uploads, and random file names inside it.

   The directory is [<system tmp>/tiff-inspector-<uid>-<port>] with mode 0700.
   Its name is stable so files left behind by a crashed instance are removed
   at the next start; including the port keeps two instances apart. *)

let random_hex n =
  let bytes =
    try
      In_channel.with_open_bin "/dev/urandom" (fun ic ->
          really_input_string ic n)
    with Sys_error _ | End_of_file ->
      (* Should not happen on a Unix system; fall back to the PRNG. *)
      let st = Random.State.make_self_init () in
      String.init n (fun _ -> Char.chr (Random.State.int st 256))
  in
  String.concat ""
    (List.init n (fun i -> Printf.sprintf "%02x" (Char.code bytes.[i])))

let clean dir =
  Array.iter
    (fun f ->
      let p = Filename.concat dir f in
      match Unix.lstat p with
      | { Unix.st_kind = S_DIR; _ } -> ()
      | _ -> ( try Unix.unlink p with Unix.Unix_error _ -> ())
      | exception Unix.Unix_error _ -> ())
    (try Sys.readdir dir with Sys_error _ -> [||])

let setup ~port =
  let base = Unix.realpath (Filename.get_temp_dir_name ()) in
  let dir =
    Filename.concat base
      (Printf.sprintf "tiff-inspector-%d-%d" (Unix.getuid ()) port)
  in
  (try Unix.mkdir dir 0o700 with Unix.Unix_error (EEXIST, _, _) -> ());
  let st = Unix.lstat dir in
  if st.st_kind <> S_DIR then failwith (dir ^ " exists and is not a directory");
  if st.st_uid <> Unix.getuid () then
    failwith (dir ^ " is owned by another user");
  Unix.chmod dir 0o700;
  clean dir;
  dir

let file_in dir = Filename.concat dir ("upload-" ^ random_hex 16)
