# TIFF Inspector

Inspect TIFF metadata, directories, samples and planes, from the command line
or in the browser, without writing a parser. Built in OCaml on
[geocaml/ocaml-tiff](https://github.com/geocaml/ocaml-tiff).

```
$ tiff-inspector inspect rgb_planar.tif
TIFF INSPECTOR
==============

File: rgb_planar.tif
File size: 486 bytes
Byte order: Big-endian
Format: Classic TIFF
Image directories: 1

Image
-----
Width: 10
Height: 10

Samples
-------
Samples per pixel: 3
Sample format: Unsigned integer (1), Unsigned integer (1), Unsigned integer (1)
Bits per sample: 8, 8, 8

Storage
-------
Photometric interpretation: RGB (2)
Planar configuration: Separate (2)
Compression: None (1)
Predictor: None (1) (default, tag absent)
...
```

Values that do not come directly from the file are marked, never guessed:
`(default, tag absent)`, `unknown (tag absent)`, `unsupported`.

## Install and build

Requirements: OCaml ≥ 5.1 with opam, and Node ≥ 20 for the web app.

```sh
opam install . --deps-only --with-test
dune build
dune install            # optional: puts tiff-inspector on your PATH
```

ocaml-tiff is vendored in `vendor/ocaml-tiff` (pinned upstream commit + a
small patch, see [docs/architecture.md](docs/architecture.md)), so it does not
need to be installed separately.

## CLI

```sh
dune exec -- tiff-inspector inspect image.tif
dune exec -- tiff-inspector inspect image.tif --tags          # full tag table
dune exec -- tiff-inspector inspect image.tif --format json   # schema v1 JSON
```

Exit codes: `0` success, `1` inspection failed, `2` invalid arguments. Full
reference: [docs/cli.md](docs/cli.md).

## Web app

```sh
dune build
dune exec -- tiff-inspector-server --port 8080   # API on :8080
cd web && npm ci && npm run dev                  # UI on :5173, proxies /api
```

Production: `cd web && npm run build`, then
`tiff-inspector-server --static-dir web/dist` serves the UI and the API from
one origin. Uploads are written to a private temp directory, inspected in a
separate process with time and memory limits, and deleted straight away.
Nothing is stored. See [src/server/README.md](src/server/README.md).

API: `POST /api/v1/inspections` (multipart field `file`) → inspection report;
`GET /api/v1/health` → `{"status":"ok"}`.

## JSON output

Defined by [schema/inspection-report.v1.json](schema/inspection-report.v1.json).
Each interpreted value carries its provenance:

```json
"sample_format": {
  "status": "present",
  "value": [{ "code": 3, "name": "ieee_float" }, { "code": 3, "name": "ieee_float" }, { "code": 3, "name": "ieee_float" }],
  "note": null
}
```

`status` is one of `present`, `default`, `absent`, `unsupported`, `error`.

## What it supports

See [docs/supported-features.md](docs/supported-features.md). In short:
classic TIFF and BigTIFF, both byte orders, IFD chains, strips and tiles, all
tags listed with decoded values, and per-sample bits and formats. Pixel data
is not decoded in v1.

## Development

```sh
dune build @fmt          # formatting (ocamlformat 0.29.0)
dune test                # unit, mutation, golden and server tests
dune promote             # accept changed golden output after review
python3 scripts/gen-fixtures/gen_fixtures.py test/fixtures --verify
test/server/smoke.sh     # end-to-end HTTP checks
cd web && npm run typecheck && npm run lint && npm test && npm run build
```

CI runs the same commands (`.github/workflows/ci.yml`). See
[CONTRIBUTING.md](CONTRIBUTING.md) and the
[fixture guide](test/fixtures/FIXTURES.md).

## License

MIT. ocaml-tiff is MIT-licensed by the geocaml developers
(`vendor/ocaml-tiff/LICENSE`).
