# tiff-inspector-server

HTTP API for TIFF Inspector (PRD phase P1).

```
dune build
_build/install/default/bin/tiff-inspector-server --port 8080 --static-dir web/dist
```

## Endpoints

| Method & path | Result |
| --- | --- |
| `GET /api/v1/health` | `200 {"status":"ok", ...}` when the worker binary is executable and the temp dir writable; `503 {"status":"unavailable", ...}` otherwise and `503 {"status":"draining", ...}` while shutting down. Also carries `version`, `schema_version`, `workers_busy` and `checks: {worker, temp_dir}` |
| `GET /api/v1/version` | `{"tool":"tiff-inspector","version":...,"schema_version":...,"limits":{"max_upload_bytes":...,"timeout_seconds":...}}` |
| `POST /api/v1/inspections` | `multipart/form-data` with a `file` field; returns a schema-v1 inspection report (`schema/inspection-report.v1.json`) |
| other `GET`/`HEAD` | the web app from `--static-dir`, falling back to `index.html` (404 JSON when no static dir is set); `ETag` with 304 on `If-None-Match`, and `<file>.gz` served with `Content-Encoding: gzip` when present and accepted |

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
| `--timeout` | `TIFF_INSPECTOR_TIMEOUT` | `10` | seconds per inspection worker |
| `--memory-limit-mb` | `TIFF_INSPECTOR_MEMORY_LIMIT_MB` | `512` | worker virtual memory (`ulimit -v`) |
| `--workers` | `TIFF_INSPECTOR_WORKERS` | `4` | concurrent inspection workers; a slot is held only while the worker runs |
| `--max-uploads` | `TIFF_INSPECTOR_MAX_UPLOADS` | `32` | uploads being received at the same time (more get 429) |
| `--upload-idle-timeout` | `TIFF_INSPECTOR_UPLOAD_IDLE_TIMEOUT` | `20` | seconds without receiving any byte before an upload is rejected (400) |
| `--upload-timeout` | `TIFF_INSPECTOR_UPLOAD_TIMEOUT` | `300` | seconds for receiving one whole upload (400) |
| `--drain-timeout` | `TIFF_INSPECTOR_DRAIN_TIMEOUT` | `15` | seconds to wait for in-flight requests after SIGTERM/SIGINT |
| `--rate-limit` | `TIFF_INSPECTOR_RATE_LIMIT` | `30` | inspections per minute per client IP; `0` disables |
| `--static-dir` | `TIFF_INSPECTOR_STATIC_DIR` | none | built web app |
| `--inspector-bin` | `TIFF_INSPECTOR_INSPECTOR_BIN` | `tiff-inspector` next to the server, else from `PATH` | worker executable |
| `--trust-proxy[=MODE]` | `TIFF_INSPECTOR_TRUST_PROXY` | `off` | client address from proxy headers; see below |
| `--hsts` | `TIFF_INSPECTOR_HSTS` | off | send `Strict-Transport-Security` (only when all clients use HTTPS) |

### `--trust-proxy`

Only enable behind a proxy you control. Everything a client puts in
`X-Forwarded-For` before the hop the proxy appends is attacker-controlled, so
the server never uses the first hop.

- `xff` (bare `--trust-proxy`, or env `true`): the **last** `X-Forwarded-For`
  hop, the one appended by the proxy in front of the server. This is the
  setting for Render.
- `cloudflare`: `True-Client-IP`, else `CF-Connecting-IP`, else the last
  `X-Forwarded-For` hop. Only safe when the proxy overwrites those two
  headers (Cloudflare does; Render does not, so a client could set them).
- `off`: the socket peer.

The chosen value must parse as an IPv4 or IPv6 address (canonicalised); any
other string falls back to the socket peer, so client-supplied text never
becomes a rate-limit key.

## Isolation model

The server never parses TIFF data. For each upload it:

1. checks the rate limit (token bucket per client IP);
2. validates the body framing before reading anything: `Content-Length`
   must be plain decimal digits, `Transfer-Encoding` exactly `chunked`, never
   both (400); a POST with neither is 411 (a request without either never
   has its body read until EOF). A `Content-Length` above the limit + 64 KiB
   multipart overhead is a 413 without reading the body, and the same bound
   is enforced while streaming (chunked bodies included);
3. takes one of `--max-uploads` upload slots (else 429, no waiting) and
   streams the `file` part into a randomly named file (`/dev/urandom`,
   `O_EXCL`, mode 0600) inside a private directory
   `$TMPDIR/tiff-inspector-<uid>-<port>` (mode 0700; stale files are removed at
   startup, the directory on shutdown). Receiving is bounded by
   `--upload-idle-timeout` (no byte for that long: 400) and
   `--upload-timeout` (total: 400). The client filename is never used for
   paths. After the closing delimiter up to 64 KiB of trailer (the chunked
   terminator) is consumed so the connection stays reusable;
4. releases the upload slot and checks the TIFF signature (`II*\0`, `MM\0*`,
   `II+\0`, `MM\0+`) — the extension and MIME type are ignored;
5. waits up to 5 s for one of `--workers` worker slots (else 429), then runs
   `/bin/sh -c 'ulimit -c 0; ulimit -v <KB>; exec tiff-inspector inspect --format json <tmp>'`
   with a minimal environment, stdin on `/dev/null`, stdout captured (max
   8 MiB), the last 4 KiB of stderr captured, and a wall-clock timeout after
   which the worker is killed with SIGKILL. A stalled or slow upload
   therefore never occupies a worker slot;
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

## Shutdown

On SIGTERM or SIGINT the server stops accepting (the listening socket is
closed, so new connections are refused at once), closes idle keep-alive
connections, answers `/api/v1/health` with 503 `draining` on connections
still open, and lets requests in flight finish for up to `--drain-timeout`
seconds. Then (or at once on a second signal) remaining connections and
workers are killed, the temp dir is removed and the process exits 0.
Render's grace period is about 30 s, so the default of 15 s fits.

## Status codes for `POST /api/v1/inspections`

| Situation | Status | `error.code` |
| --- | --- | --- |
| inspection succeeded (`ok: true`) | 200 | — |
| not multipart, bad boundary, missing/empty `file`, malformed body, upload idle or total timeout | 400 | `invalid_request` |
| `Content-Length` not decimal, `Transfer-Encoding` other than `chunked`, or both headers | 400 | `invalid_request` |
| neither `Content-Length` nor `Transfer-Encoding` | 411 | `invalid_request` |
| body or file over the limit | 413 | `file_too_large` |
| no TIFF signature, or worker reports `not_a_tiff` | 415 | `not_a_tiff` |
| worker failed with any other code (`truncated`, `malformed`, …) | 422 | as reported |
| worker timed out or was killed by a signal (e.g. memory) | 422 | `limit_exceeded` |
| rate limit hit, all upload slots taken, or all worker slots busy for 5 s | 429 (`Retry-After`) | `rate_limited` |
| worker reports `internal`, unparseable output, unexpected exit code | 500 | `internal` |

## Responses and logging

All responses carry `X-Content-Type-Options: nosniff`, `X-Frame-Options:
DENY`, `Referrer-Policy: no-referrer`, `Permissions-Policy: camera=(),
microphone=(), geolocation=()` and `Cross-Origin-Opener-Policy: same-origin`;
with `--hsts` also `Strict-Transport-Security: max-age=31536000;
includeSubDomains`. API responses carry `Cache-Control: no-store`; HTML from
the static dir `Content-Security-Policy: default-src 'self'; style-src 'self'
'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'; base-uri
'none'; object-src 'none'; form-action 'self'`. Other static files are
cacheable for an hour (`public, max-age=3600`) and revalidate by `ETag`; every
static response carries `Vary: Accept-Encoding`.

One line per request is logged to stderr: method, path, status, duration,
and for inspections the worker outcome (`worker=exit=0 12ms out=7680B`,
`worker=timeout ...`, `worker=signal=9 ...`, `worker=spawn_failed ...`). When
a worker does not exit 0, the tail of its stderr is logged on a separate
`worker stderr:` line with the temporary path scrubbed. No file contents,
client filenames or paths are ever logged.

## Tests

```
dune test                       # unit tests (test/server/test_server.ml)
dune build && test/server/smoke.sh   # end-to-end with curl
```
