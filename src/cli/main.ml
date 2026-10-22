(* tiff-inspector command line *)

open Cmdliner
module I = Tiff_inspector

type format = Text | Json

let exit_ok = 0
let exit_failed = 1
let exit_usage = 2

let inspect format tags only max_ifds debug path =
  if max_ifds < 1 then (
    Fmt.epr "tiff-inspector: --max-ifds must be at least 1, got %d@." max_ifds;
    exit_usage)
  else
    let limits = { I.Inspect.default_limits with max_ifds } in
    let outcome =
      try I.Inspect.file ~limits path
      with exn ->
        if debug then prerr_endline (Printexc.to_string exn);
        Error
          {
            failed_file = Some (Filename.basename path, None);
            error =
              I.Problem.error Internal "Unexpected error during inspection";
          }
    in
    match outcome with
    | Error f ->
        if format = Json then print_string (I.Json.to_string (I.Json.failure f));
        prerr_endline (I.Text.failure f);
        exit_failed
    | Ok r -> (
        match only with
        | Some i when i < 0 || i >= r.ifd_count ->
            Fmt.epr
              "tiff-inspector: directory %d does not exist (file has %d)@." i
              r.ifd_count;
            exit_usage
        | _ ->
            (match format with
            | Text -> print_string (I.Text.report ~tags ?only r)
            | Json ->
                let r =
                  match only with
                  | None -> r
                  | Some i ->
                      {
                        r with
                        directories =
                          List.filter
                            (fun (d : I.Report.directory) -> d.index = i)
                            r.directories;
                      }
                in
                print_string (I.Json.to_string (I.Json.report r)));
            exit_ok)

let format =
  let doc = "Output format: $(b,text) or $(b,json)." in
  Arg.(
    value
    & opt (enum [ ("text", Text); ("json", Json) ]) Text
    & info [ "f"; "format" ] ~docv:"FORMAT" ~doc)

let tags =
  Arg.(
    value & flag
    & info [ "t"; "tags" ] ~doc:"Include the full tag table (text format).")

let only =
  Arg.(
    value
    & opt (some int) None
    & info [ "ifd" ] ~docv:"N"
        ~doc:
          "Only show directory $(docv). With $(b,--format json) the \
           $(b,directories) array holds only that directory.")

let max_ifds =
  Arg.(
    value
    & opt int I.Inspect.default_limits.max_ifds
    & info [ "max-ifds" ] ~docv:"N"
        ~doc:"Stop after $(docv) directories (at least 1).")

let debug =
  Arg.(
    value & flag
    & info [ "debug" ] ~doc:"Print internal exception details to stderr.")

let path =
  Arg.(
    required
    & pos 0 (some string) None
    & info [] ~docv:"FILE" ~doc:"TIFF file to inspect.")

let exits =
  [
    Cmd.Exit.info exit_ok ~doc:"on successful inspection.";
    Cmd.Exit.info exit_failed ~doc:"when the file could not be inspected.";
    Cmd.Exit.info exit_usage ~doc:"on invalid arguments or options.";
  ]

let inspect_cmd =
  let doc =
    "Inspect a TIFF file's metadata, directories, samples and planes."
  in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Prints a report of the file's header, image directories (IFDs), \
         sample layout, storage and tags. Values not read directly from the \
         file are marked (for example, TIFF spec defaults applied when a tag \
         is absent).";
      `P
        "With $(b,--format json) a report following schema v1 is written to \
         stdout, also on failure ($(b,ok) is false). Diagnostics go to stderr.";
    ]
  in
  Cmd.v
    (Cmd.info "inspect" ~doc ~man ~exits)
    Term.(const inspect $ format $ tags $ only $ max_ifds $ debug $ path)

let cmd =
  let doc = "Inspect TIFF files" in
  Cmd.group
    (Cmd.info "tiff-inspector" ~version:I.Version.v ~doc ~exits)
    [ inspect_cmd ]

let () =
  match Cmd.eval_value cmd with
  | Ok (`Ok code) -> exit code
  | Ok (`Version | `Help) -> exit exit_ok
  | Error (`Parse | `Term) -> exit exit_usage
  | Error `Exn -> exit exit_failed
