# TIFF Inspector web

React 19 + TypeScript + Vite 6 + Tailwind v4 frontend for TIFF Inspector. Upload a
`.tif`/`.tiff` (or BigTIFF `.btf`/`.tf8`) file (max 25 MB), and it shows the inspection
report from the OCaml API:
overview, image file directories (IFDs), image properties, storage layout, samples and
planes, pixel-decoding support and a searchable tag table. It also has a "Download JSON"
export.

## Development

1. Start the OCaml API server on `127.0.0.1:8080` (see the repository root README).
   It must serve `POST /api/v1/inspections` and `GET /api/v1/health`.
2. Start the frontend:

   ```sh
   cd web
   npm install
   npm run dev
   ```

   Vite proxies `/api/*` to `http://127.0.0.1:8080` (see `vite.config.ts`). In production
   the built `dist/` is served from the same origin as the API, so no proxy is needed.

If the API server is not running, uploads end in a "We couldn't reach the server" state
with a Retry button. The sample links under the drop zone fetch fixtures from
`public/playground/samples/` and send them through the same validate-and-upload path.

## Playground

`/playground` runs OCaml in the browser. It needs `public/playground/toplevel.js`,
which is built from the OCaml sources and not committed:

```sh
(cd .. && scripts/build-playground.sh)
```

Without it the page loads but reports that the bundle is missing.
`public/playground/worker.js` hosts the toplevel in a web worker, and
`src/playground/` holds the page, the editor and the worker client.
`public/playground/` also holds the sample TIFFs (copies of `../test/fixtures`,
served to both pages) and the OCaml camel used as the site icon.

## Scripts

| Script                     | What it does                                                                        |
| -------------------------- | ----------------------------------------------------------------------------------- |
| `npm run dev`              | Vite dev server with the `/api` proxy                                               |
| `npm run build`            | `tsc -b && vite build` → `dist/`                                                    |
| `npm run preview`          | Serve the production build locally                                                  |
| `npm run typecheck`        | `tsc -b` (app + config)                                                             |
| `npm run lint`             | ESLint (flat config, typescript-eslint, react-hooks), zero warnings allowed         |
| `npm test`                 | Vitest + Testing Library (jsdom), single run                                        |
| `npm run test:watch`       | Vitest in watch mode                                                                |
| `npm run gen:types`        | Regenerate `src/api/types.ts` from the JSON Schema                                  |
| `npm run check:types`      | Fail if `src/api/types.ts` is out of date with the schema (for CI)                  |
| `npm run validate:goldens` | Validate every `../test/golden/*.json` CLI report against the schema (Ajv 2020)     |

CI should run:

```sh
npm ci && npm run typecheck && npm run lint && npm test && npm run build && npm run check:types && npm run validate:goldens
```

## Report types are generated from the schema

`../schema/inspection-report.v1.json` is the single source of truth for the report shape.
`src/api/types.ts` is **generated**. Do not edit it by hand.

```sh
# after changing schema/inspection-report.v1.json
npm run gen:types     # rewrites src/api/types.ts
npm run check:types   # what CI runs; exits 1 if the committed file is stale
```

`scripts/gen-types.mjs` runs `json-schema-to-typescript` and makes two schema-preserving
adjustments first:

- **FieldOf inlining:** typed fields are declared as `{ "$ref": "#/$defs/FieldOf",
  "properties": { "value": … } }`. The generator ignores keywords next to a `$ref`, so the
  script merges `FieldOf` into each of these defs (`IntField`, `EnumField`, …). Each def's
  own `value` type replaces FieldOf's untyped `value`.
- **Naming:** each `$defs` key becomes its type name. `Error` is emitted as `ReportError`
  so it does not shadow the global `Error`.

## Layout

```
src/
  api/          types.ts (generated), client.ts (XHR upload + HTTP/body → error-kind mapping)
  state/        inspection.ts (state-machine reducer), useInspection.ts (drives it)
  lib/          validation (extension/size/magic bytes), formatting, tag search, download
  components/   UI; FieldValue renders every FieldOf value (present/default/absent/…)
  playground/   Playground page, CodeMirror editor, worker client (runner.ts), protocol
  test/         setup, fixtures/successReport.ts (schema-validated mock), schema test
scripts/        gen-types.mjs, validate-goldens.mjs
```

The inspection flow is an explicit state machine:
`idle → validating → uploading(progress) → parsing → success | error(kind)`.
`cancel` aborts an in-flight request (`uploading | parsing → idle`); an aborted request
never produces a late success or error.

The error kinds are:

| Kind                  | Source                                                     | Retry |
| --------------------- | ---------------------------------------------------------- | ----- |
| `invalid_file`        | client validation, 400/415 `invalid_request`/`not_a_tiff`  | no    |
| `unsupported_feature` | 422 `unsupported_feature`                                  | no    |
| `limit_exceeded`      | 422 `limit_exceeded` (worker hit the time or memory cap)   | yes   |
| `malformed`           | 422 `truncated`/`malformed`/`file_unreadable`/…            | no    |
| `oversized`           | 413 `file_too_large`                                       | no    |
| `rate_limited`        | 429 `rate_limited`; honours `Retry-After` (seconds)        | yes   |
| `network`             | connection failed, upload timeout (300 s), 502/503/504 page | yes   |
| `server`              | 500 `internal`, or an unreadable 2xx body                  | yes   |

`limit_exceeded` is retryable because the cap is per inspection and the server may
succeed when less loaded. For `rate_limited` with `Retry-After`, the Retry button reads
"Retry in N s" and is disabled until the delay elapses. Every error offers "Choose another
file". Client-side validation only gives faster feedback; the server re-checks everything.

The maximum upload size, the accepted extensions and the upload timeout are defined once,
in `src/lib/constants.ts` (`MAX_UPLOAD_BYTES`, `ACCEPTED_EXTENSIONS`, `UPLOAD_TIMEOUT_MS`).
