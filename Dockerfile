# syntax=docker/dockerfile:1

# ── Stage 1: Build (Debian/glibc) ─────────────────────────────
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils \
    build-essential \
    pkg-config \
    libsqlite3-dev \
  && rm -rf /var/lib/apt/lists/*

# Install Zig 0.15.2 (required by build.zig.zon)
ARG ZIG_VERSION=0.15.2
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) ZIG_ARCH="x86_64" ;; \
      arm64) ZIG_ARCH="aarch64" ;; \
      *) echo "Unsupported TARGETARCH=${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz; \
    mkdir -p /opt; \
    tar -xJf /tmp/zig.tar.xz -C /opt; \
    ln -sf "/opt/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}/zig" /usr/local/bin/zig; \
    zig version

WORKDIR /app
COPY build.zig build.zig.zon ./
COPY src/ src/

RUN zig build -Doptimize=ReleaseSmall

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

# Distroless does not include SQLite; copy the runtime library from the builder.
# Wildcard covers both amd64 (x86_64-linux-gnu) and arm64 (aarch64-linux-gnu).
COPY --from=builder /usr/lib/*-linux-gnu/libsqlite3.so.0* /usr/lib/
ENV LD_LIBRARY_PATH=/usr/lib

COPY --from=permissions /nullclaw-data /nullclaw-data

ENV NULLCLAW_WORKSPACE=/nullclaw-data/workspace
ENV HOME=/nullclaw-data
ENV NULLCLAW_GATEWAY_PORT=3000

WORKDIR /nullclaw-data
USER 65534:65534
EXPOSE 3000
ENTRYPOINT ["nullclaw"]
CMD ["gateway", "--port", "3000", "--host", "[::]"]