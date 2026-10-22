(* A small streaming multipart/form-data parser (RFC 7578 / RFC 2046).

   It reads from an [Eio.Buf_read.t], extracts the single form field named
   "file" and hands its content to a [write] callback chunk by chunk, so the
   upload never has to be held in memory. Other fields are read and discarded
   within a small byte budget. *)

type error = Malformed of string | Missing_file | Empty_file | File_too_large

exception Fail of error

let fail e = raise (Fail e)
let malformed fmt = Printf.ksprintf (fun m -> fail (Malformed m)) fmt

type file = {
  filename : string option;  (** Raw client filename, unsanitised *)
  content_type : string option;
  size : int;
  head : string;  (** First (up to) 8 bytes of the content *)
}

(* --- Header parameter parsing ------------------------------------------- *)

let is_space c = c = ' ' || c = '\t'
let lowercase = String.lowercase_ascii

(* Parses ["value; k1=v1; k2=\"quoted;v2\""] into the leading value and the
   parameter list. Keys are lowercased; values keep their case. Quoted strings
   support backslash escapes. *)
let parse_params s =
  let len = String.length s in
  let rec skip_ws i =
    if i < len && is_space s.[i] then skip_ws (i + 1) else i
  in
  let rec token_end i stop =
    if i < len && not (List.mem s.[i] stop) then token_end (i + 1) stop else i
  in
  let first_end = token_end 0 [ ';' ] in
  let first = String.trim (String.sub s 0 first_end) in
  let rec params i acc =
    let i = skip_ws i in
    if i >= len then List.rev acc
    else if s.[i] = ';' then params (i + 1) acc
    else
      let k_end = token_end i [ '='; ';' ] in
      let key = lowercase (String.trim (String.sub s i (k_end - i))) in
      if k_end >= len || s.[k_end] = ';' then params k_end ((key, "") :: acc)
      else
        let v_start = skip_ws (k_end + 1) in
        if v_start < len && s.[v_start] = '"' then
          let b = Buffer.create 32 in
          let rec quoted j =
            if j >= len then j (* unterminated: take what we have *)
            else
              match s.[j] with
              | '"' -> j + 1
              | '\\' when j + 1 < len ->
                  Buffer.add_char b s.[j + 1];
                  quoted (j + 2)
              | c ->
                  Buffer.add_char b c;
                  quoted (j + 1)
          in
          let next = quoted (v_start + 1) in
          params (token_end next [ ';' ]) ((key, Buffer.contents b) :: acc)
        else
          let v_end = token_end v_start [ ';' ] in
          let v = String.trim (String.sub s v_start (v_end - v_start)) in
          params v_end ((key, v) :: acc)
  in
  (first, params first_end [])

let valid_boundary b =
  let len = String.length b in
  len >= 1 && len <= 70
  && String.for_all (fun c -> Char.code c >= 0x20 && Char.code c < 0x7f) b
  && b.[len - 1] <> ' '

let boundary_of_content_type ct =
  let media, params = parse_params ct in
  if lowercase media <> "multipart/form-data" then
    Error "Content-Type must be multipart/form-data"
  else
    match List.assoc_opt "boundary" params with
    | None | Some "" -> Error "Missing multipart boundary"
    | Some b when not (valid_boundary b) -> Error "Invalid multipart boundary"
    | Some b -> Ok b

(* --- Filename handling ---------------------------------------------------- *)

let percent_decode s =
  let len = String.length s in
  let b = Buffer.create len in
  let hex c =
    match c with
    | '0' .. '9' -> Some (Char.code c - 48)
    | 'a' .. 'f' -> Some (Char.code c - 87)
    | 'A' .. 'F' -> Some (Char.code c - 55)
    | _ -> None
  in
  let rec go i =
    if i >= len then ()
    else if s.[i] = '%' && i + 2 < len then (
      match (hex s.[i + 1], hex s.[i + 2]) with
      | Some h, Some l ->
          Buffer.add_char b (Char.chr ((h * 16) + l));
          go (i + 3)
      | _ ->
          Buffer.add_char b '%';
          go (i + 1))
    else (
      Buffer.add_char b s.[i];
      go (i + 1))
  in
  go 0;
  Buffer.contents b

(* RFC 5987 ext-value: charset'lang'pct-encoded *)
let decode_ext_value v =
  match String.index_opt v '\'' with
  | None -> None
  | Some i -> (
      match String.index_from_opt v (i + 1) '\'' with
      | None -> None
      | Some j ->
          Some (percent_decode (String.sub v (j + 1) (String.length v - j - 1)))
      )

let default_filename = "upload.tif"
let max_filename_bytes = 255

(* Truncate to at most [n] bytes without splitting a UTF-8 sequence. *)
let truncate_utf8 s n =
  if String.length s <= n then s
  else
    let rec back i =
      if i > 0 && Char.code s.[i] land 0xC0 = 0x80 then back (i - 1) else i
    in
    String.sub s 0 (back n)

let sanitize_filename = function
  | None -> default_filename
  | Some raw ->
      (* basename: keep what follows the last separator of either kind *)
      let last_sep =
        max
          (Option.value ~default:(-1) (String.rindex_opt raw '/'))
          (Option.value ~default:(-1) (String.rindex_opt raw '\\'))
      in
      let base =
        String.sub raw (last_sep + 1) (String.length raw - last_sep - 1)
      in
      let b = Buffer.create (String.length base) in
      String.iter
        (fun c ->
          let code = Char.code c in
          if code < 0x20 || code = 0x7f || c = '/' || c = '\\' then ()
          else Buffer.add_char b c)
        base;
      let name =
        String.trim (truncate_utf8 (Buffer.contents b) max_filename_bytes)
      in
      if name = "" || name = "." || name = ".." then default_filename else name

(* --- Streaming body parser ----------------------------------------------- *)

module R = Eio.Buf_read

let find_sub hay needle =
  let hl = String.length hay and nl = String.length needle in
  let rec at i j = j >= nl || (hay.[i + j] = needle.[j] && at i (j + 1)) in
  let rec go i =
    if i + nl > hl then None
    else if hay.[i] = needle.[0] && at i 1 then Some i
    else go (i + 1)
  in
  if nl = 0 then Some 0 else go 0

(* Pass bytes to [emit] until [delim] is found; consume the delimiter too.
   Raises [End_of_file] if the input ends first. *)
let scan_until ic delim ~emit =
  let dlen = String.length delim in
  let rec loop () =
    let s = Cstruct.to_string (R.peek ic) in
    match find_sub s delim with
    | Some i ->
        if i > 0 then emit (String.sub s 0 i);
        R.consume ic (i + dlen)
    | None ->
        let safe = String.length s - (dlen - 1) in
        if safe > 0 then (
          emit (String.sub s 0 safe);
          R.consume ic safe);
        R.ensure ic (R.buffered_bytes ic + 1);
        loop ()
  in
  loop ()

let max_header_lines = 32
let max_header_bytes = 8192

let read_part_headers ic =
  let rec go n bytes acc =
    if n > max_header_lines || bytes > max_header_bytes then
      malformed "Too many part headers";
    let line = R.line ic in
    if line = "" then List.rev acc
    else
      match String.index_opt line ':' with
      | None -> malformed "Invalid part header"
      | Some i ->
          let name = lowercase (String.trim (String.sub line 0 i)) in
          let value =
            String.trim (String.sub line (i + 1) (String.length line - i - 1))
          in
          go (n + 1) (bytes + String.length line) ((name, value) :: acc)
  in
  go 0 0 []

(* After a delimiter: "--" ends the body, otherwise the rest of the line must
   be (transport padding) whitespace. Returns [true] when more parts follow. *)
let after_delimiter ic =
  R.ensure ic 2;
  let s = Cstruct.to_string (Cstruct.sub (R.peek ic) 0 2) in
  if s = "--" then false
  else
    let rest = R.line ic in
    if String.trim rest <> "" then malformed "Invalid multipart delimiter line";
    true

let parse ~boundary ~max_file_bytes ?(max_other_bytes = 65536) ~write ic =
  let dash_boundary = "--" ^ boundary in
  let delim = "\r\n" ^ dash_boundary in
  let file = ref None in
  let other_bytes = ref 0 in
  let run () =
    (* Preamble: the body normally starts with the dash-boundary directly. *)
    R.ensure ic (String.length dash_boundary);
    let start =
      Cstruct.to_string
        (Cstruct.sub (R.peek ic) 0 (String.length dash_boundary))
    in
    if start = dash_boundary then R.consume ic (String.length dash_boundary)
    else scan_until ic delim ~emit:(fun _ -> ());
    let more = ref (after_delimiter ic) in
    while !more do
      let headers = read_part_headers ic in
      let disposition =
        match List.assoc_opt "content-disposition" headers with
        | None -> malformed "Part without Content-Disposition"
        | Some d -> d
      in
      let kind, params = parse_params disposition in
      if lowercase kind <> "form-data" then malformed "Part is not form-data";
      let is_file = List.assoc_opt "name" params = Some "file" in
      if is_file then (
        if Option.is_some !file then malformed "Multiple file parts";
        let filename =
          match List.assoc_opt "filename" params with
          | Some f -> Some f
          | None ->
              Option.bind (List.assoc_opt "filename*" params) decode_ext_value
        in
        let size = ref 0 in
        let head = Buffer.create 8 in
        scan_until ic delim ~emit:(fun chunk ->
            let n = String.length chunk in
            if !size + n > max_file_bytes then fail File_too_large;
            if Buffer.length head < 8 then
              Buffer.add_string head
                (String.sub chunk 0 (min n (8 - Buffer.length head)));
            size := !size + n;
            write chunk);
        file :=
          Some
            {
              filename;
              content_type = List.assoc_opt "content-type" headers;
              size = !size;
              head = Buffer.contents head;
            })
      else
        scan_until ic delim ~emit:(fun chunk ->
            other_bytes := !other_bytes + String.length chunk;
            if !other_bytes > max_other_bytes then
              malformed "Form field too large");
      more := after_delimiter ic
    done;
    match !file with
    | None -> fail Missing_file
    | Some f when f.size = 0 -> fail Empty_file
    | Some f -> f
  in
  match run () with
  | f -> Ok f
  | exception Fail e -> Error e
  | exception End_of_file ->
      Error (Malformed "Unexpected end of multipart body")
  | exception R.Buffer_limit_exceeded ->
      Error (Malformed "Multipart line too long")

let error_message = function
  | Malformed m -> m
  | Missing_file -> "Missing form field \"file\""
  | Empty_file -> "The uploaded file is empty"
  | File_too_large -> "The uploaded file exceeds the size limit"
