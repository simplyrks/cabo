# ── Build stage ────────────────────────────────────────────────────────────────
FROM dart:stable AS build

WORKDIR /app

# Copy the shared package first (server depends on it via path reference)
COPY shared/ shared/

# Copy the server source
COPY server/ server/

# Resolve dependencies and compile to a self-contained native binary
WORKDIR /app/server
RUN dart pub get
RUN dart compile exe bin/main.dart -o /app/server-bin

# ── Runtime stage ───────────────────────────────────────────────────────────────
# dart:stable includes the minimal runtime needed for compiled executables
FROM debian:bookworm-slim

COPY --from=build /app/server-bin /server-bin

# Cloud platforms route external HTTPS/WSS → internal HTTP/WS on this port
EXPOSE 8080

CMD ["/server-bin"]
