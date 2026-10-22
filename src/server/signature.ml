(* TIFF magic number check on the first bytes of an upload. The extension and
   client-supplied MIME type are never trusted. *)

let signatures = [ "II*\000"; "MM\000*"; "II+\000"; "MM\000+" ]

let is_tiff head =
  String.length head >= 4 && List.mem (String.sub head 0 4) signatures
