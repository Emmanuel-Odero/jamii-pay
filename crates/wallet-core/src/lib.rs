//! wallet-core: the only place in the codebase allowed to touch a private key.
//!
//! Shared, byte-for-byte, between the Rust backend and the Flutter app via
//! flutter_rust_bridge. Solidity, TypeScript, and Dart never see raw key
//! material — they call into this crate (directly in Rust, or across the
//! bridge from Dart) and get back addresses, signatures, and transaction
//! payloads.

mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */

pub mod address;
pub mod api;
pub mod encryption;
pub mod error;
pub mod keys;
pub mod opaque;
pub mod signing;

pub use error::WalletCoreError;

/// Re-exported so downstream crates (server) and the FRB bridge pin the same
/// curve implementation the whole system relies on.
pub use k256;
