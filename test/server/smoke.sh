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

# start_server LOGNAME ARGS... : sets PORT, SERVER_PID, SERVER_TMP
start_server() {
  log=$WORK/$1.log
  shift
  TMPDIR=$SERVER_TMP_BASE "$SERVER" --port 0 --inspector-bin "$INSPECTOR" "$@" 2>"$log" &
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
check "health body" '{ "status": "ok" }' "$(cat "$WORK/last")"
check_grep "nosniff header" '^x-content-type-options: nosniff' "$WORK/last_headers"
check_grep "referrer-policy header" '^referrer-policy: no-referrer' "$WORK/last_headers"
check_grep "cache-control header" '^cache-control: no-store' "$WORK/last_headers"

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

check "GET inspections 405" 405 "$(req "$BASE/api/v1/inspections")"
check_grep "405 allow header" '^allow: POST' "$WORK/last_headers"
check "unknown route 404" 404 "$(req "$BASE/api/v1/nope")"

# keep-alive: several requests on one connection
check "keep-alive reuse" "200:1 200:0" \
  "$(curl -s -o /dev/null -w '%{http_code}:%{num_connects} ' -F "file=@$FIX/gray8.tif" \
     "$BASE/api/v1/inspections" --next -s -o /dev/null -w '%{http_code}:%{num_connects}' \
     -F "file=@$FIX/gray8.tif" "$BASE/api/v1/inspections")"

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
stop_server

echo
echo "smoke: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
