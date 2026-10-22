(* Opening TIFF files from the filesystem.

   Everything that touches [Unix] lives here so that the core library stays
   portable (it is also compiled to JavaScript for the web playground). *)

open Tiff_inspector

let with_file path f =
  let name = Filename.basename path in
  match Unix.openfile path [ Unix.O_RDONLY; Unix.O_CLOEXEC ] 0 with
  | exception Unix.Unix_error (Unix.ENOENT, _, _) ->
      Error (Problem.error File_not_found "No such file: %s" name)
  | exception Unix.Unix_error (err, _, _) ->
      Error
        (Problem.error File_unreadable "Cannot open %s: %s" name
           (Unix.error_message err))
  | fd ->
      Fun.protect
        ~finally:(fun () -> Unix.close fd)
        (fun () ->
          match Unix.fstat fd with
          | { Unix.st_kind = Unix.S_REG; st_size; _ } ->
              Ok (f (Source.v ~name ~size:st_size (Tiff_unix.of_fd fd)))
          | _ ->
              Error
                (Problem.error File_unreadable "%s is not a regular file" name)
          | exception Unix.Unix_error (err, _, _) ->
              Error
                (Problem.error File_unreadable "Cannot read %s: %s" name
                   (Unix.error_message err)))

(* Inspect the file at [path]. *)
let file ?limits path : (Report.t, Report.failure) result =
  match with_file path (Inspect.run ?limits) with
  | Ok r -> r
  | Error error ->
      Error { failed_file = Some (Filename.basename path, None); error }
