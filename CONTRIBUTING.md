# Contributing

Thanks for helping make TIFF files easier to understand.

## Reporting a TIFF that inspects wrongly

1. Run `tiff-inspector inspect --format json --debug file.tif` and include the
   output in the issue.
2. If you can share the file, attach it. Better still, reproduce the problem
   with a tiny synthetic file using `scripts/gen-fixtures/gen_fixtures.py`
   (see [test/fixtures/FIXTURES.md](test/fixtures/FIXTURES.md)).
3. `library_mismatch` and `library_error` warnings point at ocaml-tiff. Those
   are good candidates for an upstream fix in
   [geocaml/ocaml-tiff](https://github.com/geocaml/ocaml-tiff).

## Making changes

- Run `dune build @fmt` (ocamlformat 0.29.0) and `dune test` before sending a
  PR. If golden output changes on purpose, run `dune promote` and review the
  diff in `test/golden/`.
- Changing the JSON output means changing
  `schema/inspection-report.v1.json` first. Then regenerate the web types
  (`cd web && npm run gen:types`). Additive changes bump the schema's minor
  version; breaking changes need a new major version.
- New TIFF behaviour needs a fixture plus a property assertion in
  `test/unit/test_inspect.ml`.
- Changes to the vendored library go in `vendor/ocaml-tiff` *and* in
  `vendor/ocaml-tiff-inspector.patch`, and should be proposed upstream.

## Adding a fixture

Follow "Adding a fixture" in `test/fixtures/FIXTURES.md`, then run
`python3 scripts/gen-golden-dune.py && dune test; dune promote`.
