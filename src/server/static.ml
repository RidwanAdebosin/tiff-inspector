(* Serving the built web app from a directory.

   Request paths are percent-decoded and split into segments; any "." / ".."
   segment, dot-file, backslash or NUL is rejected, and only regular files
   (not symlinks) are served, so nothing outside the root can be reached.
   Unknown paths fall back to index.html so client-side routing works. *)

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

let regular_file p =
  match Unix.lstat p with
  | { Unix.st_kind = S_REG; _ } -> true
  | _ -> false
  | exception Unix.Unix_error _ -> false

let max_static_bytes = 64 * 1024 * 1024

let read_file p =
  try
    In_channel.with_open_bin p (fun ic ->
        if In_channel.length ic > Int64.of_int max_static_bytes then None
        else Some (In_channel.input_all ic))
  with Sys_error _ -> None

(* Returns [(file_path, body)] to serve, if any. *)
let resolve ~root path =
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
  Option.bind file (fun p -> Option.map (fun body -> (p, body)) (read_file p))

let headers file =
  let ct = content_type file in
  let is_html = String.starts_with ~prefix:"text/html" ct in
  [ ("content-type", ct) ]
  @
  if is_html then
    [ ("content-security-policy", csp); ("cache-control", "no-cache") ]
  else [ ("cache-control", "public, max-age=3600") ]
