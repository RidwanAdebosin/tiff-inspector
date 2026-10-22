(* Entry point of the browser playground.

   Exposes [ocamlPlayground] to JavaScript with:
   - [setSink (kind, text) => void]: receives output chunks in order. Kinds
     are "stdout", "stderr", "answer" (toplevel responses) and "location"
     ("line:col:endLine:endCol" of the last error).
   - [registerSample (name, bytes)]: makes a TIFF available as [Sample.get].
   - [execute code]: runs code, returns {passed, failed} from [Test]. *)

open Js_of_ocaml
module Top = Js_of_ocaml_toplevel.JsooTop

let sink : (string -> string -> unit) ref = ref (fun _ _ -> ())
let emit kind text = if text <> "" then !sink kind text

let answer_formatter =
  Format.make_formatter
    (fun s off len ->
      (* Anything printed by the code itself comes before the answer. *)
      flush stdout;
      flush stderr;
      emit "answer" (String.sub s off len))
    (fun () -> ())

let highlight_location (loc : Location.t) =
  let open Lexing in
  let s = loc.loc_start and e = loc.loc_end in
  emit "location"
    (Printf.sprintf "%d:%d:%d:%d" s.pos_lnum (s.pos_cnum - s.pos_bol) e.pos_lnum
       (e.pos_cnum - e.pos_bol))

let execute (code : Js.js_string Js.t) =
  Test.reset ();
  (try Top.execute true ~highlight_location answer_formatter (Js.to_string code)
   with exn -> emit "stderr" ("Fatal error: " ^ Printexc.to_string exn ^ "\n"));
  Format.pp_print_flush answer_formatter ();
  Format.pp_print_flush Format.err_formatter ();
  flush stdout;
  flush stderr;
  let passed, failed = Test.counts () in
  Js.Unsafe.obj
    [|
      ("passed", Js.Unsafe.inject passed); ("failed", Js.Unsafe.inject failed);
    |]

let set_sink (f : (Js.js_string Js.t -> Js.js_string Js.t -> unit) Js.callback)
    =
  sink :=
    fun kind text ->
      Js.Unsafe.fun_call f
        [|
          Js.Unsafe.inject (Js.string kind); Js.Unsafe.inject (Js.string text);
        |]

let register_sample (name : Js.js_string Js.t)
    (bytes : Typed_array.uint8Array Js.t) =
  Sample.register (Js.to_string name) (Typed_array.String.of_uint8Array bytes)

let () =
  Top.initialize ();
  Sys_js.set_channel_flusher stdout (emit "stdout");
  Sys_js.set_channel_flusher stderr (emit "stderr");
  Js.export "ocamlPlayground"
    (Js.Unsafe.obj
       [|
         ("setSink", Js.Unsafe.inject (Js.wrap_callback set_sink));
         ("registerSample", Js.Unsafe.inject (Js.wrap_callback register_sample));
         ("execute", Js.Unsafe.inject (Js.wrap_callback execute));
         ("version", Js.Unsafe.inject (Js.string Sys.ocaml_version));
       |])
