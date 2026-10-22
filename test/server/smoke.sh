#!/bin/sh
# End-to-end smoke test for tiff-inspector-server.
#
# Usage: test/server/smoke.sh [SERVER_BIN [INSPECTOR_BIN]]
#
# Builds nothing: by default it uses the binaries from `dune build`
# (_build/install/default/bin). Requires curl.

set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
SERVER=${1:-$ROOT/_build/install/default/bin/tiff-inspector-server}
INSPECTOR=${2:-$ROOT/_build/install/default/bin/tiff-inspector}
FIX=$ROOT/test/fixtures

for b in "$SERVER" "$INSPECTOR"; do
  if [ ! -x "$b" ]; then
    echo "smoke: missing executable $b (run 'dune build' first)" >&2
    exit 2
  fi
done
command -v curl >/dev/null || { echo "smoke: curl is required" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tiff-smoke.XXXXXX")
mkdir -p "$WORK/tmp"
SERVER_TMP_BASE=$(cd "$WORK/tmp" && pwd -P)
BODIES=$WORK/all_bodies
: >"$BODIES"
PASS=0
FAIL=0
SERVER_PID=

cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

ok() { PASS=$((PASS + 1)); echo "  ok   $1"; }
ko() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }
check() { # name expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else ko "$1 (expected '$2', got '$3')"; fi
}
check_grep() { # name regex file
  if grep -Eq "$2" "$3"; then ok "$1"; else ko "$1 (no match for $2)"; fi
}

# start_server LOGNAME ARGS... : sets PORT, SERVER_PID, SERVER_TMP, LOG.
# WORKER_BIN overrides the inspector binary given to the server.
WORKER_BIN=
start_server() {
  log=$WORK/$1.log
  LOG=$log
  shift
  TMPDIR=$SERVER_TMP_BASE "$SERVER" --port 0 --inspector-bin "${WORKER_BIN:-$INSPECTOR}" "$@" 2>"$log" &
  SERVER_PID=$!
  PORT=
  i=0
  while [ $i -lt 100 ]; do
    PORT=$(sed -n 's|.*listening on http://[^ ]*:\([0-9][0-9]*\) .*|\1|p' "$log")
    [ -n "$PORT" ] && break
    sleep 0.1
    i=$((i + 1))
  done
  if [ -z "$PORT" ]; then
    echo "smoke: server did not start" >&2
    cat "$log" >&2
    exit 1
  fi
  SERVER_TMP=$SERVER_TMP_BASE/tiff-inspector-$(id -u)-$PORT
  BASE=http://127.0.0.1:$PORT
}

stop_server() {
  kill "$SERVER_PID" 2>/dev/null
  wait "$SERVER_PID" 2>/dev/null
  SERVER_PID=
}

N=0
# req ARGS... : performs a curl request, prints the status code, saves the
# body to $WORK/last (and appends it to $BODIES).
req() {
  N=$((N + 1))
  code=$(curl -s -o "$WORK/last" -D "$WORK/last_headers" -w '%{http_code}' "$@")
  cat "$WORK/last" >>"$BODIES"
  echo "$code"
}

echo "== main server (--max-upload-bytes 4096)"
start_server main --max-upload-bytes 4096

check "health 200" 200 "$(req "$BASE/api/v1/health")"
check_grep "health status ok" '"status": *"ok"' "$WORK/last"
check_grep "health version" '"version": *"[0-9]' "$WORK/last"
check_grep "health schema_version" '"schema_version": *"1' "$WORK/last"
check_grep "health workers_busy" '"workers_busy": *0' "$WORK/last"
check_grep "health checks" '"worker": *"ok"' "$WORK/last"
check_grep "nosniff header" '^x-content-type-options: nosniff' "$WORK/last_headers"
check_grep "referrer-policy header" '^referrer-policy: no-referrer' "$WORK/last_headers"
check_grep "x-frame-options header" '^x-frame-options: DENY' "$WORK/last_headers"
check_grep "permissions-policy header" '^permissions-policy: camera=\(\), microphone=\(\), geolocation=\(\)' "$WORK/last_headers"
check_grep "cross-origin-opener-policy header" '^cross-origin-opener-policy: same-origin' "$WORK/last_headers"
if grep -qi '^strict-transport-security' "$WORK/last_headers"; then ko "no HSTS without --hsts"; else ok "no HSTS without --hsts"; fi
check_grep "cache-control header" '^cache-control: no-store' "$WORK/last_headers"

check "version 200" 200 "$(req "$BASE/api/v1/version")"
check_grep "version tool" '"tool": *"tiff-inspector"' "$WORK/last"
check_grep "version schema_version" '"schema_version": *"1' "$WORK/last"
check_grep "version max_upload_bytes" '"max_upload_bytes": *4096' "$WORK/last"
check_grep "version timeout_seconds" '"timeout_seconds": *10' "$WORK/last"
check "version POST 405" 405 "$(req -X POST "$BASE/api/v1/version")"

check "gray8 200" 200 "$(req -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
check_grep "gray8 ok true" '"ok": *true' "$WORK/last"
check_grep "gray8 file.name" '"name": *"gray8.tif"' "$WORK/last"

check "client path stripped from name" 200 \
  "$(req -F "file=@$FIX/gray8.tif;filename=../../etc/evil.tif" "$BASE/api/v1/inspections")"
check_grep "sanitized name" '"name": *"evil.tif"' "$WORK/last"

check "not_a_tiff 415" 415 "$(req -F "file=@$FIX/not_a_tiff.tif" "$BASE/api/v1/inspections")"
check_grep "not_a_tiff code" '"code": *"not_a_tiff"' "$WORK/last"

check "truncated_ifd 422" 422 "$(req -F "file=@$FIX/truncated_ifd.tif" "$BASE/api/v1/inspections")"
check_grep "truncated_ifd code" '"code": *"truncated"' "$WORK/last"
check_grep "truncated_ifd file.name" '"name": *"truncated_ifd.tif"' "$WORK/last"

check "unknown_field_type 422" 422 \
  "$(req -F "file=@$FIX/unknown_field_type.tif" "$BASE/api/v1/inspections")"

# 5000-byte file with a valid TIFF signature: over the 4096-byte limit
{ printf 'II*\000'; head -c 4996 /dev/zero; } >"$WORK/big.tif"
check "5000-byte file 413" 413 "$(req -F "file=@$WORK/big.tif" "$BASE/api/v1/inspections")"
check_grep "413 code" '"code": *"file_too_large"' "$WORK/last"

# Content-Length far above the limit: rejected before reading the body
{ printf 'II*\000'; head -c 300000 /dev/zero; } >"$WORK/huge.tif"
check "huge Content-Length 413" 413 "$(req -F "file=@$WORK/huge.tif" "$BASE/api/v1/inspections")"

# Chunked body over the limit
check "chunked over limit 413" 413 \
  "$(req -H 'Transfer-Encoding: chunked' -F "file=@$WORK/huge.tif" "$BASE/api/v1/inspections")"

check "missing file field 400" 400 "$(req -F "other=value" "$BASE/api/v1/inspections")"
check_grep "400 code" '"code": *"invalid_request"' "$WORK/last"

: >"$WORK/zero.tif"
check "empty file 400" 400 "$(req -F "file=@$WORK/zero.tif" "$BASE/api/v1/inspections")"

check "non-multipart 400" 400 \
  "$(req -H 'Content-Type: image/tiff' --data-binary "@$FIX/gray8.tif" "$BASE/api/v1/inspections")"

# Body framing: no Content-Length and no Transfer-Encoding must not read until
# EOF (answer within 1 s); TE together with CL, and non-decimal CL, are 400
check "POST without Content-Length 411" 411 \
  "$(req -m 1 -X POST -H 'Content-Type: multipart/form-data; boundary=x' "$BASE/api/v1/inspections")"
check "TE with CL 400" 400 \
  "$(req -m 1 -X POST -H 'Transfer-Encoding: chunked' -H 'Content-Length: 5' \
     -H 'Content-Type: multipart/form-data; boundary=x' --data-binary 'hello' "$BASE/api/v1/inspections")"
check "TE gzip,chunked 400" 400 \
  "$(req -m 1 -X POST -H 'Transfer-Encoding: gzip, chunked' \
     -H 'Content-Type: multipart/form-data; boundary=x' "$BASE/api/v1/inspections")"
check "hex Content-Length 400" 400 \
  "$(req -m 1 -X POST -H 'Content-Length: 0x10' -H 'Content-Type: multipart/form-data; boundary=x' "$BASE/api/v1/inspections")"
check "GET with body: health still answers" 200 \
  "$(req -m 1 -X GET -H 'Content-Length: 3' --data-binary 'abc' "$BASE/api/v1/health")"

check "GET inspections 405" 405 "$(req "$BASE/api/v1/inspections")"
check_grep "405 allow header" '^allow: POST' "$WORK/last_headers"
check "unknown route 404" 404 "$(req "$BASE/api/v1/nope")"

# keep-alive: several requests on one connection
check "keep-alive reuse" "200:1 200:0" \
  "$(curl -s -o /dev/null -w '%{http_code}:%{num_connects} ' -F "file=@$FIX/gray8.tif" \
     "$BASE/api/v1/inspections" --next -s -o /dev/null -w '%{http_code}:%{num_connects}' \
     -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"

# chunked upload: trailer consumed so the connection is reused too
check "chunked keep-alive reuse" "200:1 200:0" \
  "$(curl -s -o /dev/null -w '%{http_code}:%{num_connects} ' -H 'Transfer-Encoding: chunked' \
     -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections" --next -s -o /dev/null \
     -w '%{http_code}:%{num_connects}' -H 'Transfer-Encoding: chunked' -F "file=@$FIX/gray8.tif" \
     "$BASE/api/v1/inspections")"
check_grep "worker outcome logged" 'POST /api/v1/inspections 200 [0-9.]+ms worker=exit=0 [0-9]+ms out=[0-9]+B' "$LOG"

if [ -d "$SERVER_TMP" ]; then ok "server temp dir exists"; else ko "server temp dir exists ($SERVER_TMP)"; fi
check "server temp dir empty" "" "$(ls -A "$SERVER_TMP" 2>/dev/null)"
if grep -qF "$SERVER_TMP_BASE" "$BODIES" || grep -q 'upload-[0-9a-f]\{32\}' "$BODIES"; then
  ko "responses do not leak temp paths"
else
  ok "responses do not leak temp paths"
fi
if grep -q 'gray8.tif\|evil' "$WORK/main.log"; then
  ko "log has no client filenames"
else
  ok "log has no client filenames"
fi
stop_server

echo "== rate limit server (--rate-limit 3)"
start_server ratelimit --rate-limit 3
check "rate 1" 200 "$(req -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
check "rate 2" 200 "$(req -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
check "rate 3" 200 "$(req -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
check "rate 4 -> 429" 429 "$(req -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
check_grep "429 code" '"code": *"rate_limited"' "$WORK/last"
check_grep "429 retry-after" '^retry-after: [0-9]+' "$WORK/last_headers"
check "health not rate limited" 200 "$(req "$BASE/api/v1/health")"
check "server temp dir empty" "" "$(ls -A "$SERVER_TMP" 2>/dev/null)"
check "xff ignored without --trust-proxy" 429 \
  "$(req -H 'X-Forwarded-For: 198.51.100.7' -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
stop_server

echo "== proxy server (--trust-proxy --rate-limit 2)"
start_server proxy --trust-proxy --rate-limit 2
# The proxy appends the real client (203.0.113.9) as the last hop; the first
# hops are client-controlled and must not create separate buckets
check "spoofed first hop 1" 200 \
  "$(req -H 'X-Forwarded-For: 10.0.0.1, 203.0.113.9' -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
check "spoofed first hop 2" 200 \
  "$(req -H 'X-Forwarded-For: 10.0.0.2, 203.0.113.9' -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
check "spoofed first hop 3 -> 429" 429 \
  "$(req -H 'X-Forwarded-For: 10.0.0.3, 203.0.113.9' -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
check "spoofed first hop 4 -> 429" 429 \
  "$(req -H 'X-Forwarded-For: 10.0.0.4, 203.0.113.9' -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
check "another client is independent" 200 \
  "$(req -H 'X-Forwarded-For: 203.0.113.10' -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
# Non-IP values never become keys: they share the peer's bucket
check "garbage last hop uses peer bucket 1" 200 \
  "$(req -H 'X-Forwarded-For: <script>1' -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
check "garbage last hop uses peer bucket 2" 200 \
  "$(req -H 'X-Forwarded-For: 1.1.1.1, garbage2' -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
check "garbage last hop uses peer bucket 3 -> 429" 429 \
  "$(req -H 'X-Forwarded-For: localhost' -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
check "no header uses peer bucket -> 429" 429 \
  "$(req -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
stop_server

echo "== stall server (--workers 1 --upload-idle-timeout 2)"
start_server stall --workers 1 --upload-idle-timeout 2
# A client that stops sending mid-upload must not hold the only worker slot
{ printf -- '--x\r\nContent-Disposition: form-data; name="file"; filename="a.tif"\r\n\r\nII*\000partial'; sleep 5; } \
  | curl -s -o /dev/null -w '%{http_code}' -X POST -T - -H 'Content-Type: multipart/form-data; boundary=x' \
      "$BASE/api/v1/inspections" >"$WORK/stalled" &
STALL_PID=$!
sleep 0.5
check "upload while another stalls" 200 "$(req -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
check "second upload while another stalls" 200 "$(req -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
wait $STALL_PID 2>/dev/null
check "stalled upload 400 after idle timeout" 400 "$(cat "$WORK/stalled")"
check_grep "stall logged" 'POST /api/v1/inspections 400 [0-9.]+ms$' "$LOG"
check "server temp dir empty" "" "$(ls -A "$SERVER_TMP" 2>/dev/null)"
stop_server

echo "== health server (worker binary disappears)"
cp "$INSPECTOR" "$WORK/inspector-copy"
chmod 755 "$WORK/inspector-copy"
WORKER_BIN=$WORK/inspector-copy start_server health
check "health 200 with worker" 200 "$(req "$BASE/api/v1/health")"
chmod 644 "$WORK/inspector-copy"
check "health 503 without executable worker" 503 "$(req "$BASE/api/v1/health")"
check_grep "health unavailable" '"status": *"unavailable"' "$WORK/last"
check_grep "health worker check failed" '"worker": *"failed"' "$WORK/last"
check "inspection 500 without worker" 500 "$(req -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
check_grep "worker failure logged" 'worker=exit=12[67] ' "$LOG"
chmod 755 "$WORK/inspector-copy"
check "health 200 again" 200 "$(req "$BASE/api/v1/health")"
stop_server

echo "== timeout server (worker sleeps 30 s, --timeout 1)"
printf '#!/bin/sh\nexec sleep 30\n' >"$WORK/sleep30.sh"
chmod 755 "$WORK/sleep30.sh"
WORKER_BIN=$WORK/sleep30.sh start_server timeout --timeout 1
check "worker timeout 422" 422 "$(req -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"
check_grep "worker timeout code" '"code": *"limit_exceeded"' "$WORK/last"
check_grep "worker timeout logged" 'worker=timeout 1[0-9]{3}ms' "$LOG"
check "server temp dir empty" "" "$(ls -A "$SERVER_TMP" 2>/dev/null)"
stop_server
sleep 0.2
if pgrep -f "$WORK/sleep30.sh" >/dev/null 2>&1; then
  ko "timed-out worker killed"; pkill -f "$WORK/sleep30.sh" 2>/dev/null
else
  ok "timed-out worker killed"
fi

echo "== hsts + static server (--hsts --static-dir)"
mkdir -p "$WORK/static"
printf '<!doctype html><title>t</title>' >"$WORK/static/index.html"
start_server hsts --hsts --static-dir "$WORK/static"
check "index 200" 200 "$(req "$BASE/")"
check_grep "hsts header" '^strict-transport-security: max-age=31536000; includeSubDomains' "$WORK/last_headers"
check_grep "csp frame-ancestors" "^content-security-policy: .*frame-ancestors 'none'" "$WORK/last_headers"
check_grep "csp base-uri" "base-uri 'none'" "$WORK/last_headers"
check_grep "csp object-src" "object-src 'none'" "$WORK/last_headers"
check_grep "csp form-action" "form-action 'self'" "$WORK/last_headers"
check_grep "static x-frame-options" '^x-frame-options: DENY' "$WORK/last_headers"
check "api hsts" 200 "$(req "$BASE/api/v1/health")"
check_grep "api hsts header" '^strict-transport-security:' "$WORK/last_headers"
stop_server

echo "== drain (SIGTERM with an inspection in flight)"
printf '#!/bin/sh\nsleep 2\nexec "%s" "$@"\n' "$INSPECTOR" >"$WORK/slow.sh"
chmod 755 "$WORK/slow.sh"
WORKER_BIN=$WORK/slow.sh start_server drain
curl -s -o /dev/null -w '%{http_code}' -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections" >"$WORK/inflight" &
INFLIGHT_PID=$!
sleep 0.5
kill -TERM "$SERVER_PID"
sleep 0.3
curl -s -m 2 -o /dev/null "$BASE/api/v1/version"
check "new connection refused while draining" 7 "$?"
wait $INFLIGHT_PID 2>/dev/null
check "in-flight request completed" 200 "$(cat "$WORK/inflight")"
wait "$SERVER_PID" 2>/dev/null
check "server exit code" 0 "$?"
SERVER_PID=
check_grep "drain logged" 'draining' "$LOG"
check_grep "stopped drained" 'stopped \(drained\)' "$LOG"
if [ -e "$SERVER_TMP" ]; then ko "temp dir removed on shutdown"; else ok "temp dir removed on shutdown"; fi

echo
echo "smoke: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
