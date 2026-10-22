/** Maximum upload size accepted by the API (25 MiB). The server enforces it too. */
export const MAX_UPLOAD_BYTES = 25 * 1024 * 1024;

export const ACCEPTED_EXTENSIONS = [".tif", ".tiff"] as const;

export const INSPECTIONS_ENDPOINT = "/api/v1/inspections";
export const HEALTH_ENDPOINT = "/api/v1/health";
