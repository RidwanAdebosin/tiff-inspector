#!/bin/sh
# Build the browser playground bundle and place it where the web app serves it.
# Usage: scripts/build-playground.sh [output-file]
set -eu
cd "$(dirname "$0")/.."
out="${1:-web/public/playground/toplevel.js}"
dune build --profile release playground/top.bc.js
mkdir -p "$(dirname "$out")"
cp _build/default/playground/top.bc.js "$out"
chmod u+w "$out"
# The server serves the .gz sibling to clients that accept gzip.
gzip -k -9 -f "$out"
echo "wrote $out ($(wc -c < "$out" | tr -d ' ') bytes, $(wc -c < "$out.gz" | tr -d ' ') gzipped)"
