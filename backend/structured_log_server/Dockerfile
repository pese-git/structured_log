# Build context is the repository root, not this directory: the server is
# built against the workspace copy of `structured_log` rather than the
# published one, so an image always contains what the tree contains.
#
#   docker build -f backend/structured_log_server/Dockerfile .

FROM dart:3.12 AS build

WORKDIR /workspace

# The core package first, so a change in the server does not invalidate the
# layer that resolved its dependencies.
COPY emb/structured_log/ emb/structured_log/
COPY backend/structured_log_server/pubspec.yaml backend/structured_log_server/

WORKDIR /workspace/backend/structured_log_server

# Same override CI writes, for the same reason: without it pub takes the
# published structured_log and a breaking change in the workspace copy would
# ship unnoticed.
RUN printf 'dependency_overrides:\n  structured_log:\n    path: ../../emb/structured_log\n' \
    > pubspec_overrides.yaml \
  && dart pub get

COPY backend/structured_log_server/ ./

# Restore the override: the COPY above brought the package's own files over it.
RUN printf 'dependency_overrides:\n  structured_log:\n    path: ../../emb/structured_log\n' \
    > pubspec_overrides.yaml \
  && dart pub get --offline

# *.g.dart and *.freezed.dart are not committed, so the package does not
# compile until this runs.
RUN dart run build_runner build --delete-conflicting-outputs

RUN dart compile exe bin/server.dart -o /server

# Not `scratch`, which the Dart images otherwise suggest: drift talks to
# libsqlite3 through dart:ffi, and that shared library has to exist in the
# runtime image.
FROM debian:bookworm-slim

# libsqlite3 because drift reaches it through dart:ffi; curl so the container
# can answer a real health check against /healthz rather than merely proving
# the binary starts.
RUN apt-get update \
  && apt-get install --no-install-recommends -y \
       libsqlite3-0 ca-certificates curl \
  && rm -rf /var/lib/apt/lists/* \
# The package ships libsqlite3.so.0; the unversioned name the FFI loader asks
# for comes with libsqlite3-dev, which is headers and a compiler's worth of
# dependencies for one symlink. Made here instead, for whichever architecture
# this is being built on.
  && ln -s "$(find /usr/lib -name 'libsqlite3.so.0' -print -quit)" \
       /usr/lib/libsqlite3.so

COPY --from=build /server /usr/local/bin/structured-log-server

# Runs unprivileged: a server that writes a database has no reason to be root.
RUN useradd --system --uid 10001 --home /nonexistent structured-log

# The directory is created and handed over *in the image*, before VOLUME.
# Docker seeds a fresh named volume from the image's path and keeps its
# ownership; without this the volume arrives owned by root and the server
# cannot create its database file.
RUN mkdir -p /data && chown 10001:10001 /data

# The database lives on that volume; the image itself stays stateless.
VOLUME /data
ENV STRUCTURED_LOG_DB_PATH=/data/logs.db

USER 10001

EXPOSE 8080

ENTRYPOINT ["structured-log-server"]
CMD ["serve"]
