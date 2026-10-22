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
echo "wrote $out ($(wc -c < "$out" | tr -d ' ') bytes)"
