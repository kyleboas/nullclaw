# syntax=docker/dockerfile:1

# ── Stage 1: Build ────────────────────────────────────────────
FROM alpine:3.21 AS builder

RUN apk add --no-cache zig sqlite-dev musl-dev

WORKDIR /app

# Copy build files to /app (NOT /app/src), so `zig build` can find build.zig
COPY build.zig build.zig.zon ./
COPY src/ src/

# Alpine sqlite is typically in /usr/include and /usr/lib
RUN zig build -Doptimize=ReleaseSmall -Dsqlite-include=/usr/include -Dsqlite-lib=/usr/lib

# ── Stage 2: Config Prep ─────────────────────────────────────
FROM busybox:1.37 AS permissions

RUN mkdir -p /nullclaw-data/.nullclaw /nullclaw-data/workspace

RUN cat > /nullclaw-data/.nullclaw/config.json << 'EOF'
{
  "api_key": "",
  "default_provider": "openrouter",
  "default_model": "anthropic/claude-sonnet-4",
  "default_temperature": 0.7,
  "gateway": {
    "port": 3000,
    "host": "[::]",
    "allow_public_bind": true
  }
}
EOF

RUN chown -R 65534:65534 /nullclaw-data

# ── Stage 3: Production Runtime (Distroless) ─────────────────
FROM gcr.io/distroless/cc-debian13:nonroot AS release

COPY --from=builder /app/zig-out/bin/nullclaw /usr/local/bin/nullclaw
COPY --from=permissions /nullclaw-data /nullclaw-data

ENV NULLCLAW_WORKSPACE=/nullclaw-data/workspace
ENV HOME=/nullclaw-data
ENV NULLCLAW_GATEWAY_PORT=3000

WORKDIR /nullclaw-data
USER 65534:65534
EXPOSE 3000
ENTRYPOINT ["nullclaw"]
CMD ["gateway", "--port", "3000", "--host", "[::]"]