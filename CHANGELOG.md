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
- Server hardening before the first deployment:
  - rate limiting behind a proxy keys on the last `X-Forwarded-For` hop
    (`--trust-proxy`, or `--trust-proxy=cloudflare` for `True-Client-IP` /
    `CF-Connecting-IP`), validated as an IP address with fallback to the
    socket peer, instead of the client-controlled first hop;
  - uploads are received under their own cap (`--max-uploads`, default 32)
    with an idle timeout (`--upload-idle-timeout`, 20 s) and a total timeout
    (`--upload-timeout`, 300 s); a worker slot is only held while the worker
    runs, so stalled clients cannot block inspections;
  - strict body framing: a POST without `Content-Length` or
    `Transfer-Encoding` is 411 instead of reading until EOF; `Content-Length`
    must be decimal, `Transfer-Encoding` exactly `chunked`, and never both
    (400);
  - graceful shutdown: SIGTERM/SIGINT closes the listener, answers health
    with 503 `draining`, and waits up to `--drain-timeout` (15 s) for
    in-flight requests before cleaning the temp dir and exiting;
  - `/api/v1/health` checks that the worker binary is executable and the
    temp dir writable (503 `unavailable` otherwise) and reports `version`,
    `schema_version` and `workers_busy`; new `GET /api/v1/version`;
  - worker outcome (exit code / signal / timeout, duration, output size) on
    the request log line, a bounded tail of worker stderr logged on failure,
    stdout capped at 8 MiB, core dumps disabled (`ulimit -c 0`);
  - `X-Frame-Options`, `Permissions-Policy`, `Cross-Origin-Opener-Policy`,
    stricter CSP (`frame-ancestors`, `base-uri`, `object-src`,
    `form-action`), and `Strict-Transport-Security` behind `--hsts`;
  - chunked uploads keep the connection alive (the multipart trailer is
    consumed after a successful parse).
- React web app: upload, overview, IFD navigation, searchable tag table,
  samples and planes, JSON export.
- 20 regression fixtures generated independently of the parser.
