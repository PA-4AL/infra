# Worker Rust (import/export Excel) — build release puis image minimale.
# Contexte de build attendu : le repo worker/ (voir infra/docker-compose.yml).
FROM rust:1.85 AS build
WORKDIR /app
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/target/release/worker /usr/local/bin/worker
ENTRYPOINT ["worker"]
