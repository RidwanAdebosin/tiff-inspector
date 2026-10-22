# Contributing

Thanks for helping make TIFF files easier to understand.

## Getting started

You need [opam](https://opam.ocaml.org/doc/Install.html) with OCaml ≥ 5.1,
Node ≥ 20, and Python 3 (only for regenerating fixtures).

```sh
# once: an OCaml switch and the project's dependencies
opam switch create . 5.1.1 --deps-only --with-test   # or reuse an existing ≥ 5.1 switch
eval "$(opam env)"                                    # in every new shell, or dune is not found
opam install . --deps-only --with-test
dune build
```

Try the CLI on a fixture:

```sh
dune exec -- tiff-inspector inspect test/fixtures/gray8.tif
```

Run the web app. It needs two terminals:

```sh
# terminal 1: the API on 127.0.0.1:8080
eval "$(opam env)"
dune exec -- tiff-inspector-server --port 8080

# terminal 2: the UI on http://localhost:5173 (proxies /api to the API)
cd web && npm ci && npm run dev
```

Check it works: `curl localhost:8080/api/v1/health` returns
`{ "status": "ok" }`. Then open http://localhost:5173 and upload any file from
`test/fixtures/`. If uploads end in "Network error", the API is not running.

Before opening a PR, run the checks CI runs (listed under "Development" in the
[README](README.md#development)). [web/README.md](web/README.md) covers the
frontend in depth, and [src/server/README.md](src/server/README.md) covers the
API flags and isolation model.

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
