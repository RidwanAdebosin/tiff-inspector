(* A TIFF file opened for inspection, with reads bounded by the file size *)

exception Out_of_bounds of { offset : int; length : int; size : int }

type t = { name : string; size : int; ro : Tiff.File.ro }

let bounded ~size (ro : Tiff.File.ro) : Tiff.File.ro =
 fun ~file_offset bufs ->
  let offset = Optint.Int63.to_int file_offset in
  let length = List.fold_left (fun acc b -> acc + Cstruct.length b) 0 bufs in
  if offset < 0 || length < 0 || offset > size - length then
    raise (Out_of_bounds { offset; length; size })
  else ro ~file_offset bufs

let v ~name ~size ro = { name; size; ro = bounded ~size ro }

let of_string ~name s =
  let ro ~file_offset bufs =
    let _ : int =
      List.fold_left
        (fun off buf ->
          let len = Cstruct.length buf in
          Cstruct.blit_from_string s off buf 0 len;
          off + len)
        (Optint.Int63.to_int file_offset)
        bufs
    in
    ()
  in
  v ~name ~size:(String.length s) ro

let read t ~offset ~length =
  if offset < 0 || length < 0 || offset > t.size - length then
    raise (Out_of_bounds { offset; length; size = t.size });
  let buf = Cstruct.create length in
  t.ro ~file_offset:(Optint.Int63.of_int offset) [ buf ];
  buf

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
              Ok (f (v ~name ~size:st_size (Tiff_unix.of_fd fd)))
          | _ ->
              Error
                (Problem.error File_unreadable "%s is not a regular file" name)
          | exception Unix.Unix_error (err, _, _) ->
              Error
                (Problem.error File_unreadable "Cannot read %s: %s" name
                   (Unix.error_message err)))
