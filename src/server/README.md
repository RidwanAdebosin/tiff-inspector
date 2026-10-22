# tiff-inspector-server

HTTP API for TIFF Inspector (PRD phase P1).

```
dune build
_build/install/default/bin/tiff-inspector-server --port 8080 --static-dir web/dist
```

## Endpoints

| Method & path | Result |
| --- | --- |
| `GET /api/v1/health` | `200 {"status":"ok"}` |
| `POST /api/v1/inspections` | `multipart/form-data` with a `file` field; returns a schema-v1 inspection report (`schema/inspection-report.v1.json`) |
| other `GET`/`HEAD` | the web app from `--static-dir`, falling back to `index.html` (404 JSON when no static dir is set) |

Unknown `/api/*` paths return 404, a wrong method on a known route 405 (with
`Allow`). Every error body is a schema-v1 FailureReport (`ok: false`,
`error.code`, `error.message`) and never contains stack traces, paths or
environment data.

## Flags

Each flag can also be set through the environment variable shown.

| Flag | Env | Default | |
| --- | --- | --- | --- |
| `--host` | `TIFF_INSPECTOR_HOST` | `127.0.0.1` | listen address |
| `--port` | `TIFF_INSPECTOR_PORT` | `8080` | `0` picks a free port (logged at startup) |
| `--max-upload-bytes` | `TIFF_INSPECTOR_MAX_UPLOAD_BYTES` | `26214400` (25 MiB) | file size limit |
| `--timeout` | `TIFF_INSPECTOR_TIMEOUT` | `10` | seconds per inspection |
| `--memory-limit-mb` | `TIFF_INSPECTOR_MEMORY_LIMIT_MB` | `512` | worker virtual memory (`ulimit -v`) |
| `--workers` | `TIFF_INSPECTOR_WORKERS` | `4` | concurrent inspections |
| `--rate-limit` | `TIFF_INSPECTOR_RATE_LIMIT` | `30` | inspections per minute per client IP; `0` disables |
| `--static-dir` | `TIFF_INSPECTOR_STATIC_DIR` | none | built web app |
| `--inspector-bin` | `TIFF_INSPECTOR_INSPECTOR_BIN` | `tiff-inspector` next to the server, else from `PATH` | worker executable |
| `--trust-proxy` | `TIFF_INSPECTOR_TRUST_PROXY` | off | rate-limit on the first `X-Forwarded-For` hop (only behind a proxy you control) |

## Isolation model

The server never parses TIFF data. For each upload it:

1. checks the rate limit (token bucket per IP) and waits up to 5 s for one of
   `--workers` slots (else 429);
2. rejects a `Content-Length` above the limit + 64 KiB multipart overhead
   without reading the body, and enforces the same bound while streaming
   (chunked bodies included);
3. streams the `file` part into a randomly named file (`/dev/urandom`,
   `O_EXCL`, mode 0600) inside a private directory
   `$TMPDIR/tiff-inspector-<uid>-<port>` (mode 0700; stale files are removed at
   startup, the directory is removed on SIGINT/SIGTERM). The client filename
   is never used for paths;
4. checks the TIFF signature (`II*\0`, `MM\0*`, `II+\0`, `MM\0+`) — the
   extension and MIME type are ignored;
5. runs `/bin/sh -c 'ulimit -v <KB>; exec tiff-inspector inspect --format json <tmp>'`
   with a minimal environment, stdin/stderr on `/dev/null`, stdout captured
   (max 32 MiB) and a wall-clock timeout after which the worker is killed with
   SIGKILL;
6. replaces `file.name` (and any mention of the temporary path) with the
   sanitized client filename (basename, no control characters or separators,
   max 255 bytes, fallback `upload.tif`);
7. deletes the temporary file in all cases.

A malformed file can therefore only crash or exhaust its own worker process.

**macOS caveat:** `ulimit -v` is not supported by macOS, so the memory limit
is silently not applied there (the timeout still is). On Linux it limits
virtual address space, which is coarser than resident memory. In production
run the server in a container with a memory limit (e.g. `docker run
--memory=1g`, or a cgroup `MemoryMax=`) sized for `--workers` × the worker
limit, and a pids limit.

## Status codes for `POST /api/v1/inspections`

| Situation | Status | `error.code` |
| --- | --- | --- |
| inspection succeeded (`ok: true`) | 200 | — |
| not multipart, bad boundary, missing/empty `file`, malformed body, upload timeout | 400 | `invalid_request` |
| body or file over the limit | 413 | `file_too_large` |
| no TIFF signature, or worker reports `not_a_tiff` | 415 | `not_a_tiff` |
| worker failed with any other code (`truncated`, `malformed`, …) | 422 | as reported |
| worker timed out or was killed by a signal (e.g. memory) | 422 | `limit_exceeded` |
| rate limit hit, or all worker slots busy for 5 s | 429 (`Retry-After`) | `rate_limited` |
| worker reports `internal`, unparseable output, unexpected exit code | 500 | `internal` |

## Responses

All responses carry `X-Content-Type-Options: nosniff` and
`Referrer-Policy: no-referrer`; API responses `Cache-Control: no-store`; HTML
from the static dir `Content-Security-Policy: default-src 'self'; style-src
'self' 'unsafe-inline'; img-src 'self' data:`. One line per request is logged
to stderr: method, path, status, duration (no file contents or filenames).

## Tests

```
dune test                       # unit tests (test/server/test_server.ml)
dune build && test/server/smoke.sh   # end-to-end with curl
```
