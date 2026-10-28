# JamiiPay

A monorepo split along four deliberate language boundaries:

| Language   | Where                                              | Why it's there |
|------------|-----------------------------------------------------|----------------|
| Rust       | `crates/wallet-core`, `crates/server`               | Memory safety on the code path where bugs mean lost money. One language across server and client crypto. |
| Dart       | `app/` — Flutter, Android/iOS/web dashboard          | One mobile codebase; `flutter_rust_bridge` binds cleanly to the Rust core. |
| Solidity   | `contracts/` — smart account + ERC-7579 recovery on Base | No alternative on EVM. Kept deliberately small — configuring audited modules, not writing them. |
| TypeScript | `web/marketing`, `web/claim`                         | The claim page must load on a cheap phone's browser with no install — rules out a Flutter web bundle. |

Supporting: SQL (PostgreSQL via SQLx, compile-time query checking once the
schema stabilizes), TOML/YAML/Bash for build and CI.

## Layout

```
crates/wallet-core/   key generation, address derivation, signing — the only
                      place allowed to touch a private key
crates/server/        Axum + SQLx backend, depends on wallet-core
app/                  Flutter app (Android/iOS/web dashboard)
contracts/            Foundry project: smart account config + RecoveryModule
web/marketing/        jamiipay.com marketing site (Vite + TS)
web/claim/            no-install browser claim page (Vite + TS, no framework)
docker/               local simulator: Postgres + Anvil Base fork
```

## Getting started

```sh
# Rust (backend + wallet-core)
cargo build --workspace
cargo test --workspace

# Local simulator (Postgres + Base fork via Anvil)
cd docker && cp .env.example .env && docker compose up -d

# Run the backend against it
cd crates/server && cp .env.example .env && cargo run

# Contracts (see contracts/README.md — Foundry isn't installed by default)
cd contracts && forge build && forge test

# Claim page / marketing site
cd web/claim && npm install && npm run dev
cd web/marketing && npm install && npm run dev

# Flutter app (see app/README.md — Flutter isn't installed by default)
cd app && flutter create --org com.jamiipay --platforms android,ios,web . && flutter run
```

## Status

This is the initial skeleton: it compiles/builds and CI is wired for every
layer, but the actual product logic (claim flow, guardian recovery
signature validation, smart account deployment wiring) is still to be
built. See per-directory READMEs for what's stubbed vs. real.
