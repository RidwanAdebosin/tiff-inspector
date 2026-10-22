(* Unit tests for the HTTP server's pure parts: multipart parsing, filename
   sanitisation, TIFF signature check, rate limiting and worker result mapping *)

open Tiff_inspector_server

(* A flow that returns at most [k] bytes per read, to exercise chunk edges *)
module Trickle = struct
  type t = { s : string; mutable pos : int; k : int }

  let single_read t dst =
    if t.pos >= String.length t.s then raise End_of_file;
    let n = min t.k (min (Cstruct.length dst) (String.length t.s - t.pos)) in
    Cstruct.blit_from_string t.s t.pos dst 0 n;
    t.pos <- t.pos + n;
    n

  let read_methods = []
end

let trickle ~k s =
  let ops = Eio.Flow.Pi.source (module Trickle) in
  Eio.Buf_read.of_flow ~initial_size:16 ~max_size:4096
    (Eio.Resource.T ({ Trickle.s; pos = 0; k }, ops))

let parse ?(k = 0) ?(max_file_bytes = 1_000_000) ~boundary body =
  let buf = Buffer.create 64 in
  let ic = if k = 0 then Eio.Buf_read.of_string body else trickle ~k body in
  let r =
    Multipart.parse ~boundary ~max_file_bytes ~write:(Buffer.add_string buf) ic
  in
  (r, Buffer.contents buf)

let part ?filename ?(ctype = "image/tiff") name content =
  let fn =
    match filename with
    | Some f -> Printf.sprintf "; filename=\"%s\"" f
    | None -> ""
  in
  Printf.sprintf
    "Content-Disposition: form-data; name=\"%s\"%s\r\n\
     Content-Type: %s\r\n\
     \r\n\
     %s"
    name fn ctype content

let body boundary parts =
  String.concat ""
    (List.map (fun p -> "--" ^ boundary ^ "\r\n" ^ p ^ "\r\n") parts)
  ^ "--" ^ boundary ^ "--\r\n"

let tiff = "II*\000\008\000\000\000rest-of-file\r\n--not-the-boundary"

let error_t =
  Alcotest.testable
    (fun ppf e -> Fmt.string ppf (Multipart.error_message e))
    ( = )

let expect_file ?k ~boundary b ~name ~content () =
  match parse ?k ~boundary b with
  | Ok f, written ->
      Alcotest.(check string) "content" content written;
      Alcotest.(check int) "size" (String.length content) f.size;
      Alcotest.(check (option string)) "filename" name f.filename
  | Error e, _ ->
      Alcotest.failf "unexpected error: %s" (Multipart.error_message e)

let expect_error ~boundary b expected =
  match parse ~boundary b with
  | Ok _, _ -> Alcotest.fail "expected an error"
  | Error e, _ -> Alcotest.check error_t "error" expected e

let test_normal () =
  let b = "----WebKitFormBoundary7MA4YWxkTrZu0gW" in
  let data =
    body b
      [
        part "comment" ~ctype:"text/plain" "hello";
        part "file" ~filename:"a.tif" tiff;
      ]
  in
  expect_file ~boundary:b data ~name:(Some "a.tif") ~content:tiff ();
  (* same body delivered a few bytes at a time *)
  List.iter
    (fun k ->
      expect_file ~k ~boundary:b data ~name:(Some "a.tif") ~content:tiff ())
    [ 1; 2; 3; 7; 64 ]

let test_preamble_and_padding () =
  let b = "xyz" in
  let data =
    "This is a preamble\r\n--xyz  \r\n"
    ^ part "file" ~filename:"p.tif" tiff
    ^ "\r\n--xyz--\r\nepilogue"
  in
  expect_file ~boundary:b data ~name:(Some "p.tif") ~content:tiff ()

let test_boundary_like_content () =
  let b = "abc" in
  (* contains "--abc" without the leading CRLF, "\r\n--ab", and "\r\n-" *)
  let content = "II*\000--abc\r\n--ab\r\n-\r\n--abcd?" in
  let content = String.sub content 0 (String.length content - 6) ^ "\r\n--a" in
  let data = body b [ part "file" ~filename:"x.tif" content ] in
  expect_file ~boundary:b data ~name:(Some "x.tif") ~content ();
  expect_file ~k:1 ~boundary:b data ~name:(Some "x.tif") ~content ()

let test_binary_content () =
  let b = "bnd" in
  let content = String.init 5000 (fun i -> Char.chr (i * 7 land 0xff)) in
  let data = body b [ part "file" ~filename:"bin.tif" content ] in
  expect_file ~k:13 ~boundary:b data ~name:(Some "bin.tif") ~content ()

let test_quoted_boundary () =
  let ct = "multipart/form-data; boundary=\"simple; boundary\"" in
  match Multipart.boundary_of_content_type ct with
  | Error e -> Alcotest.fail e
  | Ok b ->
      Alcotest.(check string) "boundary" "simple; boundary" b;
      let data = body b [ part "file" ~filename:"q.tif" tiff ] in
      expect_file ~boundary:b data ~name:(Some "q.tif") ~content:tiff ()

let test_content_type () =
  let ok ct expected =
    Alcotest.(check (result string string))
      ct (Ok expected)
      (Multipart.boundary_of_content_type ct)
  in
  let bad ct =
    Alcotest.(check bool)
      ct true
      (Result.is_error (Multipart.boundary_of_content_type ct))
  in
  ok "multipart/form-data; boundary=abc" "abc";
  ok "Multipart/Form-Data;boundary=abc ; charset=utf-8" "abc";
  ok "multipart/form-data; charset=utf-8; BOUNDARY=\"a\\\"b\"" "a\"b";
  bad "image/tiff";
  bad "multipart/mixed; boundary=abc";
  bad "multipart/form-data";
  bad "multipart/form-data; boundary=";
  bad "";
  bad ("multipart/form-data; boundary=" ^ String.make 71 'a')

let test_missing_file () =
  let b = "abc" in
  expect_error ~boundary:b (body b [ part "other" "x" ]) Multipart.Missing_file;
  expect_error ~boundary:b (body b []) Multipart.Missing_file;
  expect_error ~boundary:b
    (body b [ part "file" ~filename:"e.tif" "" ])
    Multipart.Empty_file

let test_malformed () =
  let b = "abc" in
  let malformed data =
    match parse ~boundary:b data with
    | Error (Multipart.Malformed _), _ -> ()
    | Error e, _ -> Alcotest.failf "wrong error: %s" (Multipart.error_message e)
    | Ok _, _ -> Alcotest.fail "expected Malformed"
  in
  (* no closing delimiter *)
  malformed ("--abc\r\n" ^ part "file" ~filename:"a.tif" tiff);
  (* no boundary at all *)
  malformed "just some bytes";
  (* part without Content-Disposition *)
  malformed "--abc\r\nContent-Type: text/plain\r\n\r\nx\r\n--abc--\r\n";
  (* two file parts *)
  malformed
    (body b
       [
         part "file" ~filename:"a.tif" tiff; part "file" ~filename:"b.tif" tiff;
       ]);
  (* oversized ordinary field *)
  malformed
    (body b
       [
         part "big" (String.make 70000 'x'); part "file" ~filename:"a.tif" tiff;
       ])

let test_too_large () =
  let b = "abc" in
  let data = body b [ part "file" ~filename:"a.tif" (String.make 101 'x') ] in
  (match parse ~max_file_bytes:100 ~boundary:b data with
  | Error Multipart.File_too_large, _ -> ()
  | _ -> Alcotest.fail "expected File_too_large");
  let data = body b [ part "file" ~filename:"a.tif" (String.make 100 'x') ] in
  match parse ~max_file_bytes:100 ~boundary:b data with
  | Ok f, _ -> Alcotest.(check int) "exactly at limit" 100 f.size
  | Error e, _ -> Alcotest.failf "unexpected: %s" (Multipart.error_message e)

let test_disposition_filename () =
  let b = "abc" in
  let data =
    "--abc\r\n\
     Content-Disposition: form-data; name=\"file\"; \
     filename*=UTF-8''caf%C3%A9.tif\r\n\
     \r\n" ^ tiff ^ "\r\n--abc--"
  in
  expect_file ~boundary:b data ~name:(Some "caf\xc3\xa9.tif") ~content:tiff ();
  let data =
    "--abc\r\n\
     content-disposition: form-data; filename=\"we;ird\\\".tif\"; name=file\r\n\
     \r\n" ^ tiff ^ "\r\n--abc--"
  in
  expect_file ~boundary:b data ~name:(Some "we;ird\".tif") ~content:tiff ()

let test_sanitize () =
  let s raw = Multipart.sanitize_filename raw in
  let eq name expected raw = Alcotest.(check string) name expected (s raw) in
  eq "plain" "a.tif" (Some "a.tif");
  eq "none" "upload.tif" None;
  eq "unix path" "passwd" (Some "../../etc/passwd");
  eq "windows path" "x.tif" (Some "C:\\Users\\me\\x.tif");
  eq "control chars" "ab.tif" (Some "a\000\n\r\027b.tif");
  eq "empty" "upload.tif" (Some "");
  eq "dotdot" "upload.tif" (Some "..");
  eq "trailing slash" "upload.tif" (Some "dir/");
  eq "spaces" "my file.tif" (Some "  my file.tif ");
  let long = s (Some (String.make 300 'a')) in
  Alcotest.(check int) "max 255 bytes" 255 (String.length long);
  (* 2-byte UTF-8 chars must not be cut in half *)
  let long =
    s (Some (String.concat "" (List.init 200 (fun _ -> "\xc3\xa9"))))
  in
  Alcotest.(check int) "utf8 boundary" 254 (String.length long)

let test_signature () =
  let t s expected =
    Alcotest.(check bool) (String.escaped s) expected (Signature.is_tiff s)
  in
  t "II*\000" true;
  t "MM\000*rest" true;
  t "II+\000\008\000" true;
  t "MM\000+" true;
  t "II*" false;
  t "" false;
  t "MM*\000" false;
  t "\137PNG" false;
  t "II\000*" false

let test_rate_limit () =
  let rl = Rate_limit.create ~per_minute:3 in
  let ok now k = Result.is_ok (Rate_limit.check rl ~now k) in
  Alcotest.(check (list bool))
    "burst"
    [ true; true; true; false ]
    (List.map (fun _ -> ok 100. "a") [ 1; 2; 3; 4 ]);
  Alcotest.(check bool) "other key" true (ok 100. "b");
  Alcotest.(check bool) "refilled after 20s" true (ok 120.5 "a");
  Alcotest.(check bool) "empty again" false (ok 120.5 "a");
  let off = Rate_limit.create ~per_minute:0 in
  Alcotest.(check bool)
    "disabled" true
    (List.for_all
       (fun _ -> Result.is_ok (Rate_limit.check off ~now:0. "x"))
       (List.init 100 Fun.id))

let status =
  Alcotest.testable (fun ppf s -> Fmt.int ppf (Http.Status.to_int s)) ( = )

let test_interpret () =
  let tmp_path = "/tmp/tiff-inspector-1-2/upload-0123" in
  let run o = Worker.interpret ~tmp_path ~name:"me.tif" ~size:10 o in
  let failure_json code msg =
    Printf.sprintf
      {|{"schema_version":"1.0","ok":false,"tool":{"name":"tiff-inspector","version":"0"},"file":{"name":"upload-0123","size_bytes":10},"error":{"code":"%s","message":"%s"}}|}
      code msg
  in
  let st, json =
    run
      (Worker.Exited
         ( 1,
           failure_json "truncated"
             "cannot read /tmp/tiff-inspector-1-2/upload-0123 at 8" ))
  in
  Alcotest.check status "truncated" `Unprocessable_entity st;
  let s = Yojson.Safe.to_string json in
  Alcotest.(check bool)
    "no temp path" false
    (Option.is_some (Multipart.find_sub s "tiff-inspector-1-2")
    || Option.is_some (Multipart.find_sub s "upload-0123"));
  Alcotest.(check bool)
    "name replaced" true
    (Option.is_some (Multipart.find_sub s {|"name":"me.tif"|}));
  let st, _ = run (Worker.Exited (1, failure_json "not_a_tiff" "x")) in
  Alcotest.check status "not_a_tiff" `Unsupported_media_type st;
  let st, _ = run (Worker.Exited (1, failure_json "internal" "x")) in
  Alcotest.check status "internal" `Internal_server_error st;
  let st, _ = run (Worker.Exited (1, failure_json "bogus_code" "x")) in
  Alcotest.check status "unknown code" `Internal_server_error st;
  let st, _ = run (Worker.Exited (0, "not json")) in
  Alcotest.check status "garbage" `Internal_server_error st;
  let st, _ = run (Worker.Exited (2, failure_json "truncated" "x")) in
  Alcotest.check status "usage exit" `Internal_server_error st;
  let st, json = run Worker.Timed_out in
  Alcotest.check status "timeout" `Unprocessable_entity st;
  Alcotest.(check bool)
    "limit_exceeded" true
    (Option.is_some
       (Multipart.find_sub (Yojson.Safe.to_string json) "limit_exceeded"));
  let st, _ = run (Worker.Signaled 9) in
  Alcotest.check status "signal" `Unprocessable_entity st

let () =
  Alcotest.run "server"
    [
      ( "multipart",
        [
          Alcotest.test_case "normal" `Quick test_normal;
          Alcotest.test_case "preamble and padding" `Quick
            test_preamble_and_padding;
          Alcotest.test_case "boundary-like content" `Quick
            test_boundary_like_content;
          Alcotest.test_case "binary content" `Quick test_binary_content;
          Alcotest.test_case "quoted boundary" `Quick test_quoted_boundary;
          Alcotest.test_case "content type" `Quick test_content_type;
          Alcotest.test_case "missing file" `Quick test_missing_file;
          Alcotest.test_case "malformed" `Quick test_malformed;
          Alcotest.test_case "too large" `Quick test_too_large;
          Alcotest.test_case "disposition filename" `Quick
            test_disposition_filename;
          Alcotest.test_case "sanitize filename" `Quick test_sanitize;
        ] );
      ("signature", [ Alcotest.test_case "tiff magic" `Quick test_signature ]);
      ( "rate_limit",
        [ Alcotest.test_case "token bucket" `Quick test_rate_limit ] );
      ("worker", [ Alcotest.test_case "interpret" `Quick test_interpret ]);
    ]
