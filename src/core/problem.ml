(* Fatal errors and non-fatal warnings, shared by the CLI, JSON and HTTP layers *)

type code =
  | File_not_found
  | File_unreadable
  | Not_a_tiff
  | Truncated
  | Malformed
  | Unsupported_feature
  | Pixel_decode_failed
  | Limit_exceeded
  | Internal
  | Invalid_request
  | File_too_large
  | Rate_limited

type error = { code : code; message : string }

type warning = {
  w_code : string;
  w_message : string;
  directory : int option;
  tag : int option;
}

let error code fmt = Fmt.kstr (fun message -> { code; message }) fmt

let warning ?directory ?tag w_code fmt =
  Fmt.kstr (fun w_message -> { w_code; w_message; directory; tag }) fmt

let code_to_string = function
  | File_not_found -> "file_not_found"
  | File_unreadable -> "file_unreadable"
  | Not_a_tiff -> "not_a_tiff"
  | Truncated -> "truncated"
  | Malformed -> "malformed"
  | Unsupported_feature -> "unsupported_feature"
  | Pixel_decode_failed -> "pixel_decode_failed"
  | Limit_exceeded -> "limit_exceeded"
  | Internal -> "internal"
  | Invalid_request -> "invalid_request"
  | File_too_large -> "file_too_large"
  | Rate_limited -> "rate_limited"

let code_of_string = function
  | "file_not_found" -> Some File_not_found
  | "file_unreadable" -> Some File_unreadable
  | "not_a_tiff" -> Some Not_a_tiff
  | "truncated" -> Some Truncated
  | "malformed" -> Some Malformed
  | "unsupported_feature" -> Some Unsupported_feature
  | "pixel_decode_failed" -> Some Pixel_decode_failed
  | "limit_exceeded" -> Some Limit_exceeded
  | "internal" -> Some Internal
  | "invalid_request" -> Some Invalid_request
  | "file_too_large" -> Some File_too_large
  | "rate_limited" -> Some Rate_limited
  | _ -> None

let describe = function
  | File_not_found -> "File not found"
  | File_unreadable -> "File unreadable"
  | Not_a_tiff -> "Not a TIFF file"
  | Truncated -> "Truncated file"
  | Malformed -> "Malformed TIFF"
  | Unsupported_feature -> "Unsupported feature"
  | Pixel_decode_failed -> "Pixel decoding failed"
  | Limit_exceeded -> "Limit exceeded"
  | Internal -> "Internal error"
  | Invalid_request -> "Invalid request"
  | File_too_large -> "File too large"
  | Rate_limited -> "Rate limited"
