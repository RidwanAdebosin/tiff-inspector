(* Client address selection for rate limiting.

   Behind a reverse proxy the socket peer is always the proxy, so the client
   address has to come from headers. Everything in those headers up to the
   hop the trusted proxy itself appended is client-controlled, hence only the
   LAST X-Forwarded-For hop is used, and only when it is a syntactically valid
   IP address: anything else falls back to the peer address so that arbitrary
   client strings never become rate-limit keys. *)

type proxy =
  | Off  (** Use the socket peer *)
  | Xff  (** Last X-Forwarded-For hop *)
  | Cloudflare
      (** True-Client-IP / CF-Connecting-IP, then the last X-Forwarded-For hop
      *)

let is_digit c = c >= '0' && c <= '9'
let is_hex c = is_digit c || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')

let ipv4 s =
  match String.split_on_char '.' s with
  | [ _; _; _; _ ] as octets ->
      List.for_all
        (fun o ->
          let n = String.length o in
          n >= 1 && n <= 3 && String.for_all is_digit o
          && int_of_string o <= 255)
        octets
  | _ -> false

(* Index of the first "::", if any *)
let double_colon s =
  let len = String.length s in
  let rec go i =
    if i + 1 >= len then None
    else if s.[i] = ':' && s.[i + 1] = ':' then Some i
    else go (i + 1)
  in
  go 0

let ipv6 s =
  let group g =
    let n = String.length g in
    n >= 1 && n <= 4 && String.for_all is_hex g
  in
  (* Number of 16-bit groups in a colon-separated list, or [None] if invalid.
     An embedded IPv4 address may end the list and counts for two groups. *)
  let groups ~v4_tail part =
    if part = "" then Some 0
    else
      let rec go acc = function
        | [] -> Some acc
        | [ last ] when v4_tail && String.contains last '.' ->
            if ipv4 last then Some (acc + 2) else None
        | g :: rest -> if group g then go (acc + 1) rest else None
      in
      go 0 (String.split_on_char ':' part)
  in
  match double_colon s with
  | None -> groups ~v4_tail:true s = Some 8
  | Some i -> (
      let left = String.sub s 0 i
      and right = String.sub s (i + 2) (String.length s - i - 2) in
      match double_colon right with
      | Some _ -> false
      | None -> (
          match (groups ~v4_tail:false left, groups ~v4_tail:true right) with
          | Some a, Some b -> a + b <= 7
          | _ -> false))

let max_len = 64

(* [Some canonical] if [s] is an IPv4 or IPv6 address (optionally in
   brackets), [None] otherwise. *)
let parse s =
  let s = String.trim s in
  let len = String.length s in
  let s =
    if len >= 2 && s.[0] = '[' && s.[len - 1] = ']' then String.sub s 1 (len - 2)
    else s
  in
  if s = "" || String.length s > max_len then None
  else if ipv4 s then Some s
  else if ipv6 s then Some (String.lowercase_ascii s)
  else None

let last_forwarded_for headers =
  match Http.Header.get_multi headers "x-forwarded-for" with
  | [] -> None
  | values -> (
      match List.rev (String.split_on_char ',' (String.concat "," values)) with
      | last :: _ -> parse last
      | [] -> None)

let client_ip ~proxy ~peer headers =
  let header n = Option.bind (Http.Header.get headers n) parse in
  let or_peer = Option.value ~default:peer in
  match proxy with
  | Off -> peer
  | Xff -> or_peer (last_forwarded_for headers)
  | Cloudflare -> (
      match header "true-client-ip" with
      | Some ip -> ip
      | None -> (
          match header "cf-connecting-ip" with
          | Some ip -> ip
          | None -> or_peer (last_forwarded_for headers)))

let proxy_to_string = function
  | Off -> "off"
  | Xff -> "xff"
  | Cloudflare -> "cloudflare"

let proxy_of_string s =
  match String.lowercase_ascii (String.trim s) with
  | "" | "false" | "off" | "no" | "0" -> Ok Off
  | "true" | "on" | "yes" | "1" | "xff" -> Ok Xff
  | "cloudflare" | "cf" -> Ok Cloudflare
  | _ -> Error ("unknown --trust-proxy mode: " ^ s)
