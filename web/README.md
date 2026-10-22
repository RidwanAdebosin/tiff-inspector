# TIFF Inspector web

React 19 + TypeScript + Vite 6 + Tailwind v4 frontend for TIFF Inspector. Upload a
`.tif`/`.tiff` file (max 25 MB), and it shows the inspection report from the OCaml API:
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

If the API server is not running, uploads end in a "Network error" or "Server error"
state with a Retry button.

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
  test/         setup, fixtures/successReport.ts (schema-validated mock), schema test
scripts/        gen-types.mjs, validate-goldens.mjs
```

The inspection flow is an explicit state machine:
`idle → validating → uploading(progress) → parsing → success | error(kind)`.
The error kinds are `invalid_file`, `unsupported_feature`, `malformed`, `oversized`,
`rate_limited`, `network` and `server`. Only `network`, `server` and `rate_limited` offer
Retry. Every error offers "Choose another file". Client-side validation only gives faster
feedback; the server re-checks everything.

The maximum upload size is defined once, in `src/lib/constants.ts` (`MAX_UPLOAD_BYTES`).
