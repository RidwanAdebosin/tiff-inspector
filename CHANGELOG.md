# Changelog

## 0.1.0 (unreleased)

- CLI `tiff-inspector inspect` with text and JSON (schema v1) output and
  documented exit codes.
- Inspection core: classic TIFF and BigTIFF, IFD chains with loop detection,
  strips and tiles, per-sample bits and formats, value provenance
  (`present`/`default`/`absent`/`unsupported`/`error`), tag table with decoded
  values, bounds checks and preflight against crafted counts.
- Cross-checks against ocaml-tiff accessors (`library_mismatch` and
  `library_error` warnings).
- Vendored ocaml-tiff (`e26425d`) with an upstream-bound patch: entry
  introspection, and offset-stored SampleFormat.
- HTTP API (`tiff-inspector-server`) with process-isolated inspection, size
  and rate limits, and temporary uploads.
- React web app: upload, overview, IFD navigation, searchable tag table,
  samples and planes, JSON export.
- 21 regression fixtures generated independently of the parser.
- Fixed: BigTIFF entries with several BYTE/SHORT/LONG values stored inline
  (for example BitsPerSample=[8,8,8] as written by GDAL) were reported as
  unreadable; values are now decoded from the entry's value field directly
  (fixture `bigtiff_rgb_inline.tif`).
- Fixed: classic TIFF offsets of 2 GiB and above (first IFD, next IFD and
  tag values) were sign-extended and reported as lying outside the file.
- Fixed: inspecting a directory with tens of thousands of strips took
  seconds (quadratic bounds check).
- CLI: `--ifd N` now also applies to `--format json`; `--max-ifds 0` is a
  usage error (exit 2) instead of a malformed-file failure.
