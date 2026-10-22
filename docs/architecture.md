# Architecture

TIFF Inspector turns a TIFF file's binary structure into a report that people
and programs can read. It has three parts: an OCaml inspection core, a CLI and
HTTP API that are thin adapters around it, and a React frontend.

```
                 ┌───────────────────────── OCaml ─────────────────────────┐
  tiff file ───► │  tiff_inspector (src/core)                              │
                 │   Source → Inspect → Report (model) → Json / Text       │
                 │        ▲ walks IFDs with geocaml/ocaml-tiff (vendored)  │
                 └────────┼─────────────────────────────────────────────────┘
                          │ linked by
          ┌───────────────┴──────────────┐
   src/cli: tiff-inspector          src/server: tiff-inspector-server
   (cmdliner, exit codes)           (cohttp-eio, uploads, rate limits)
          ▲                                   │ spawns one worker per upload
          └──── `inspect --format json` ◄─────┘ (timeout + memory limit)
                                              ▲
                                     web/ (React + TS + Vite + Tailwind)
                                     POST /api/v1/inspections
```

## Principles

1. **One inspection core.** The CLI and the API produce byte-identical JSON,
   because the API runs the CLI.
2. **Never present inferred values as facts.** Every interpreted property is a
   `Field.t` with a status: `present`, `default` (tag absent, TIFF spec
   default applied), `absent`, `unsupported`, or `error`.
3. **Fail per field, not per file.** A problem with one tag becomes a
   directory warning. Only header and IFD-structure failures are fatal.
4. **Process isolation for untrusted input.** The server never parses in
   process.

## Core library (`src/core`)

| Module | Responsibility |
|---|---|
| `Source` | A file with a known size. All reads are bounds-checked before allocating (`Out_of_bounds`). |
| `Problem` | Stable error codes (fatal) and warnings (non-fatal, stable `code` strings). |
| `Field` | Value + provenance status. |
| `Tag_registry` | Tag names, field types, coded values (snake_case JSON names and human labels). |
| `Guard` | Runs an ocaml-tiff call and maps its exceptions (`Not_found`, `Failure`, `Invalid_argument`, `End_of_file`, …) to typed problems. |
| `Decode` | Decodes entry values: inline (re-encoded from what ocaml-tiff parsed) or at an offset (bounded read), capped at a value limit. |
| `Inspect` | Header check, per-IFD preflight, IFD walk, field interpretation, layout and plane derivation, cross-checks against ocaml-tiff accessors. |
| `Report` | The public model, mirroring the JSON Schema. No ocaml-tiff types leak out. |
| `Json`, `Text` | Renderers. |

### How ocaml-tiff is used

ocaml-tiff parses the header (`Ifd.read_header`) and every IFD (`Ifd.v`),
including strip offsets and byte counts. The inspector then:

- decodes tag values itself from the entries ocaml-tiff parsed. This is needed
  because ocaml-tiff only treats `count = 1` values as inline, so multi-value
  inline tags such as `BitsPerSample = [8, 8]` would otherwise be misread;
- cross-checks width, height, samples per pixel, bits per sample, compression,
  planar configuration and sample format against ocaml-tiff's accessors. A
  disagreement or an exception becomes a `library_mismatch` or `library_error`
  warning. This is how parser bugs surface as reproducible diagnostics.

The vendored copy (`vendor/ocaml-tiff`, pinned at upstream commit `e26425d`)
carries a small patch, `vendor/ocaml-tiff-inspector.patch`, intended for
upstream:

- entry introspection: `entry_tag_id`, `entry_field_type`, `entry_count`,
  `entry_location`, `header`, `next_ifd_offset`;
- `Ifd.sample_format` reads values stored at an offset instead of raising
  (the offset-based SampleFormat bug).

### Preflight

ocaml-tiff allocates buffers sized from counts in the file before it reads
them. Before calling `Ifd.v`, the inspector therefore checks:

- that the IFD offset lies inside the file;
- that the entry table fits in the file;
- that every entry has a known field type;
- that `StripOffsets` and `StripByteCounts` (which ocaml-tiff reads eagerly)
  declare no more values than the file could hold.

### Limits

`Inspect.default_limits`: 1024 IFDs; 64 values per tag in the tag table (ASCII
up to 4096 bytes); 256 layout offsets listed; 1024 samples. Anything cut is
marked `truncated`.

## Report schema

`schema/inspection-report.v1.json` is the source of truth. The OCaml encoder
is pinned by golden files (`test/golden`), and the TypeScript types in
`web/src/api/types.ts` are generated from the schema. The schema version is
`1.0`: additive changes bump the minor version, breaking changes create v2
(and `/api/v2`).

## CLI (`src/cli`)

See [cli.md](cli.md). Exit codes: `0` success, `1` inspection failed, `2`
invalid arguments.

## API server (`src/server`)

See [`src/server/README.md`](../src/server/README.md) for flags. For each
upload the server:

1. Applies a per-IP token-bucket rate limit (behind a proxy: the last
   `X-Forwarded-For` hop, validated as an IP).
2. Validates body framing (decimal `Content-Length` or exactly
   `Transfer-Encoding: chunked`, never both, 411 when neither) and enforces
   the size limit (default 25 MiB) from `Content-Length` and while reading.
3. Under an upload-concurrency cap with idle and total timeouts, parses
   multipart, writes the `file` part to a random name in a private (0700)
   temp directory, and checks the TIFF signature.
4. Takes a worker slot and spawns `tiff-inspector inspect --format json`
   under a timeout (10 s) and an address-space limit; the slot is released as
   soon as the worker exits.
5. Maps the result to HTTP: 200, 415 `not_a_tiff`, 422 inspection failures
   and timeouts, 500 internal; the outcome is logged.
6. Replaces `file.name` with the sanitised client filename and deletes the
   temp file in all cases.

On SIGTERM it stops accepting, drains in-flight requests (health answers
503) and exits.

## Frontend (`web/`)

React + TypeScript + Vite + Tailwind. The upload flow is an explicit state
machine. The results view renders every field through one component that
shows its provenance status, and "Download JSON" exports the exact server
response. See [`web/README.md`](../web/README.md).

## Playground (`playground/`)

The OCaml toplevel compiled to JavaScript with js_of_ocaml, linked with the
vendored `tiff` library, the inspector core and two helper modules (`Test`,
`Sample`). `top.ml` exposes `ocamlPlayground` to JavaScript; code is parsed
like `#use` (no `;;` needed) and each definition runs on its own, stopping at
the first error. `web/public/playground/worker.js` hosts it in a web worker
so a runaway loop can be killed and the page's content-security policy stays
strict. `check.cjs` drives the real bundle under Node as part of `dune test`.

The static server serves a precompressed `.gz` sibling when the client
accepts gzip (the 6 MB bundle is 1.3 MB on the wire) and answers
`If-None-Match` with 304, so returning visitors re-download nothing.

## Testing

| Layer | Where |
|---|---|
| Fixtures (independent stdlib-only Python writer, verified with libtiff) | `scripts/gen-fixtures`, `test/fixtures` |
| Expected properties and error categories per fixture | `test/unit/test_inspect.ml` |
| Malformed input: 200 random corruptions per fixture must not raise | `test/unit/test_inspect.ml` |
| Golden text + JSON output per fixture | `test/golden` |
| Server multipart unit tests + HTTP smoke test | `test/server` |
| Frontend unit/component tests | `web/src` (vitest) |
