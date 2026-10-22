(* Serving the built web app from a directory.

   Request paths are percent-decoded and split into segments; any "." / ".."
   segment, dot-file, backslash or NUL is rejected, and only regular files
   (not symlinks) are served, so nothing outside the root can be reached.
   Unknown paths fall back to index.html so client-side routing works.

   A sibling [<file>.gz] is served instead when the client accepts gzip (the
   Docker build precompresses the web app, including the 6 MB playground
   bundle). Every response carries an ETag so repeat visits revalidate with a
   304 instead of downloading again. *)

let content_types =
  [
    ("html", "text/html; charset=utf-8");
    ("htm", "text/html; charset=utf-8");
    ("js", "text/javascript; charset=utf-8");
    ("mjs", "text/javascript; charset=utf-8");
    ("css", "text/css; charset=utf-8");
    ("json", "application/json");
    ("map", "application/json");
    ("webmanifest", "application/manifest+json");
    ("svg", "image/svg+xml");
    ("png", "image/png");
    ("jpg", "image/jpeg");
    ("jpeg", "image/jpeg");
    ("gif", "image/gif");
    ("webp", "image/webp");
    ("ico", "image/x-icon");
    ("tif", "image/tiff");
    ("tiff", "image/tiff");
    ("woff", "font/woff");
    ("woff2", "font/woff2");
    ("ttf", "font/ttf");
    ("otf", "font/otf");
    ("txt", "text/plain; charset=utf-8");
    ("wasm", "application/wasm");
  ]

let content_type path =
  let ext =
    match String.rindex_opt path '.' with
    | Some i ->
        String.lowercase_ascii
          (String.sub path (i + 1) (String.length path - i - 1))
    | None -> ""
  in
  Option.value ~default:"application/octet-stream"
    (List.assoc_opt ext content_types)

let csp =
  "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; \
   frame-ancestors 'none'; base-uri 'none'; object-src 'none'; form-action \
   'self'"

(* Safe relative segments for a URL path, or [None] if it must be refused. *)
let segments path =
  let decoded = Uri.pct_decode path in
  if String.contains decoded '\000' || String.contains decoded '\\' then None
  else
    let segs =
      List.filter (fun s -> s <> "") (String.split_on_char '/' decoded)
    in
    if List.exists (fun s -> s.[0] = '.') segs then None else Some segs

let stat_regular p =
  match Unix.lstat p with
  | { Unix.st_kind = S_REG; _ } as st -> Some st
  | _ -> None
  | exception Unix.Unix_error _ -> None

let regular_file p = Option.is_some (stat_regular p)
let max_static_bytes = 64 * 1024 * 1024

let read_file p =
  try
    In_channel.with_open_bin p (fun ic ->
        if In_channel.length ic > Int64.of_int max_static_bytes then None
        else Some (In_channel.input_all ic))
  with Sys_error _ -> None

type file = {
  path : string;  (** The logical file, used for the content type *)
  body : string;  (** Possibly the gzip-compressed sibling *)
  encoding : string option;  (** [Some "gzip"] when [body] is compressed *)
  etag : string;
}

(* Strong ETag from the served file's size and mtime. The compressed and
   plain siblings differ in both, so each representation gets its own tag. *)
let etag (st : Unix.stats) =
  Printf.sprintf "\"%x-%x\"" st.st_size (int_of_float st.st_mtime)

(* Does an Accept-Encoding value allow gzip? Handles "gzip;q=0". *)
let accepts_gzip = function
  | None -> false
  | Some v ->
      List.exists
        (fun item ->
          match List.map String.trim (String.split_on_char ';' item) with
          | name :: params ->
              String.lowercase_ascii name = "gzip"
              && not
                   (List.exists
                      (fun p ->
                        match String.split_on_char '=' p with
                        | [ "q"; q ] -> (
                            match float_of_string_opt (String.trim q) with
                            | Some f -> f <= 0.
                            | None -> false)
                        | _ -> false)
                      params)
          | [] -> false)
        (String.split_on_char ',' v)

(* Does an If-None-Match value cover [etag]? *)
let not_modified ~if_none_match etag =
  match if_none_match with
  | None -> false
  | Some v ->
      v = "*"
      || List.exists
           (fun t ->
             let t = String.trim t in
             t = etag || t = "W/" ^ etag)
           (String.split_on_char ',' v)

(* The file to serve for a request path, if any. *)
let resolve ?(accept_gzip = false) ~root path : file option =
  let index = Filename.concat root "index.html" in
  let candidate =
    match segments path with
    | None -> None
    | Some [] -> Some index
    | Some segs ->
        let p = List.fold_left Filename.concat root segs in
        if regular_file p then Some p
        else
          let dir_index = Filename.concat p "index.html" in
          if regular_file dir_index then Some dir_index else None
  in
  let file =
    match candidate with
    | Some p -> Some p
    | None -> if regular_file index then Some index else None
  in
  Option.bind file (fun p ->
      let gz = p ^ ".gz" in
      let source, encoding =
        match if accept_gzip then stat_regular gz else None with
        | Some st -> ((gz, st), Some "gzip")
        | None -> (
            match stat_regular p with
            | Some st -> ((p, st), None)
            | None -> ((p, Unix.stat p), None))
      in
      let src, st = source in
      Option.map
        (fun body -> { path = p; body; encoding; etag = etag st })
        (read_file src))

let headers (f : file) =
  let ct = content_type f.path in
  let is_html = String.starts_with ~prefix:"text/html" ct in
  [ ("content-type", ct); ("etag", f.etag); ("vary", "accept-encoding") ]
  @ (match f.encoding with Some e -> [ ("content-encoding", e) ] | None -> [])
  @
  if is_html then
    [ ("content-security-policy", csp); ("cache-control", "no-cache") ]
  else [ ("cache-control", "public, max-age=3600") ]
