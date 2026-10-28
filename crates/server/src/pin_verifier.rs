//! Wallet-PIN verification with an upgrade path.
//!
//! - **v1 (current):** `bcrypt(sha256(pin))`. The client's pre-hash is
//!   unsalted, so v1's offline resistance rests entirely on bcrypt + the
//!   server never leaking the hash column. Acceptable behind the release
//!   throttle, not a forever home.
//! - **v2 (reserved):** OPAQUE verifier (`pin_verifier` column,
//!   `pin_version = 2`). With OPAQUE the server holds a verifier that
//!   cannot be dictionary-attacked offline at all, and online guesses are
//!   the throttle's problem. The PAKE handshake itself is future work —
//!   but this module already dual-verifies, so enabling it is per-wallet
//!   with zero downtime: set the verifier, flip the version, v1 hash
//!   stays as fallback until first successful v2 login, then is cleared.
//!
//! Both `wallets::verify_pin` and the backup release oracle verify through
//! [`verify_wallet_pin`] — one function, one throttle semantic.

/// Returns true iff `presented_pin_hash` (the client's presentation value)
/// authenticates against the stored verifier. `stored_v2` is
/// `Some(verifier)` only for wallets migrated to v2.
pub fn verify_wallet_pin(
    stored_bcrypt_v1: &str,
    stored_v2: Option<&str>,
    presented_pin_hash: &str,
) -> bool {
    if let Some(verifier) = stored_v2 {
        if verify_v2(verifier, presented_pin_hash) {
            return true;
        }
        // Fall through to v1: lets a wallet mid-migration (verifier set,
        // client not yet upgraded) still authenticate — until the v1 hash
        // is cleared post-migration. No silent downgrade: v2 success never
        // consults v1.
    }
    bcrypt::verify(presented_pin_hash, stored_bcrypt_v1).unwrap_or(false)
}

/// v2 verifier check. Format: `opaque-v1$<base64>`; until the OPAQUE
/// handshake ships, no verifier validates — unknown formats fail closed
/// (never open). This is load-bearing: a permissive stub here would be a
/// backdoor, so the stub is a deny.
fn verify_v2(verifier: &str, _presented: &str) -> bool {
    if !verifier.starts_with("opaque-v1$") {
        return false;
    }
    // OPAQUE handshake not yet implemented — fail closed.
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn v1_bcrypt_verifies() {
        let presented = "deadbeef";
        let stored = bcrypt::hash(presented, bcrypt::DEFAULT_COST).unwrap();
        assert!(verify_wallet_pin(&stored, None, presented));
        assert!(!verify_wallet_pin(&stored, None, "wrong"));
    }

    #[test]
    fn unknown_v2_verifier_fails_closed_not_open() {
        let presented = "deadbeef";
        let stored = bcrypt::hash(presented, bcrypt::DEFAULT_COST).unwrap();
        // Garbage v2 verifier + correct v1 secret: v1 fallback still
        // honest during migration...
        assert!(verify_wallet_pin(&stored, Some("garbage"), presented));
        // ...but v2 alone never authenticates until OPAQUE ships.
        assert!(!verify_wallet_pin("unusable", Some("opaque-v1$AAAA"), presented));
    }
}
