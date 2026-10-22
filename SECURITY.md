# Security policy

TIFF Inspector parses untrusted binary files and, in its web deployment,
accepts uploads. Please report vulnerabilities privately through a GitHub
security advisory on this repository, not in public issues. Include a
reproducing file if you can. We aim to respond within 7 days.

In scope:

- crashes, hangs or excessive memory use on crafted files;
- upload handling (size limits, temp-file cleanup, path handling);
- information leaks in API responses.

Deployment guidance: run the server behind HTTPS, keep the default upload
limit (25 MiB) or lower, and set a container memory limit. The worker's
`ulimit -v` is best effort, and not enforced on macOS.
