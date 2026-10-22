# One image serving the web app and the API from the same origin.
# Build: docker build -t tiff-inspector .
# Run:   docker run --rm -p 8080:8080 --memory=512m tiff-inspector

# --- OCaml binaries -----------------------------------------------------------
FROM ocaml/opam:debian-12-ocaml-5.4 AS ocaml
WORKDIR /home/opam/src
COPY --chown=opam:opam tiff-inspector.opam ./
RUN opam install . --deps-only --yes
COPY --chown=opam:opam . .
RUN opam exec -- dune build @install --profile release \
 && mkdir -p /home/opam/out \
 && cp _build/install/default/bin/tiff-inspector \
       _build/install/default/bin/tiff-inspector-server /home/opam/out/

# --- Web app ------------------------------------------------------------------
FROM node:22-slim AS web
WORKDIR /src/web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web/ ./
COPY schema/ /src/schema/
RUN npm run build

# --- Runtime ------------------------------------------------------------------
FROM debian:12-slim
RUN useradd --system --no-create-home --shell /usr/sbin/nologin app
# The server finds the worker binary next to itself.
COPY --from=ocaml /home/opam/out/ /app/bin/
COPY --from=web /src/web/dist/ /app/web/
ENV TIFF_INSPECTOR_HOST=0.0.0.0 \
    TIFF_INSPECTOR_STATIC_DIR=/app/web \
    EIO_BACKEND=posix
USER app
EXPOSE 8080
# Hosts like Render pass the port in $PORT.
CMD ["/bin/sh", "-c", "exec /app/bin/tiff-inspector-server --port \"${PORT:-8080}\""]
