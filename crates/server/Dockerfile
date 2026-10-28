# Build context is the repo root (see docker/docker-compose.yml) — the
# server crate depends on wallet-core via a workspace path dependency, so
# both crates (and the shared Cargo.lock) need to be in the build context.

FROM rust:1-bookworm AS builder
WORKDIR /build

# Cache dependency compilation separately from source changes: copy only
# the manifests first, build with dummy source, then overwrite with the
# real source and rebuild (cargo only recompiles what changed).
COPY Cargo.toml Cargo.lock ./
COPY crates/wallet-core/Cargo.toml crates/wallet-core/Cargo.toml
COPY crates/server/Cargo.toml crates/server/Cargo.toml
RUN mkdir -p crates/wallet-core/src crates/server/src \
    && echo "fn main() {}" > crates/server/src/main.rs \
    && echo "" > crates/wallet-core/src/lib.rs \
    && cargo build --release -p server \
    && rm -rf crates/wallet-core/src crates/server/src

COPY crates/wallet-core crates/wallet-core
COPY crates/server crates/server
# Migrations are embedded into the binary at compile time by
# `sqlx::migrate!` (crates/server/src/state.rs) — nothing extra to copy
# into the runtime image for them.
RUN touch crates/wallet-core/src/lib.rs crates/server/src/main.rs \
    && cargo build --release -p server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/target/release/jamiipay-server /usr/local/bin/jamiipay-server

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/jamiipay-server"]
