/** Maximum upload size accepted by the API (25 MiB). The server enforces it too. */
export const MAX_UPLOAD_BYTES = 25 * 1024 * 1024;

/** `.btf` and `.tf8` are BigTIFF extensions; the server checks the signature, not the name. */
export const ACCEPTED_EXTENSIONS = [".tif", ".tiff", ".btf", ".tf8"] as const;

/**
 * Upper bound on one upload request, from first byte sent to the response
 * (the server's own total upload timeout). A hung connection surfaces as a
 * network error after this instead of spinning forever.
 */
export const UPLOAD_TIMEOUT_MS = 300_000;

export const INSPECTIONS_ENDPOINT = "/api/v1/inspections";
export const HEALTH_ENDPOINT = "/api/v1/health";
