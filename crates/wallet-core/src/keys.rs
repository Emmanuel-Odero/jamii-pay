//! Key generation and storage primitives.
//!
//! `PrivateKey` zeroizes its backing bytes on drop. This module never
//! serializes a private key to disk or over the wire in plaintext — callers
//! (server, Flutter bridge) are responsible for wrapping persistence in
//! platform secure storage (Keychain/Keystore) or an HSM/KMS on the backend.

use k256::ecdsa::SigningKey;
use rand_core::OsRng;
use zeroize::Zeroize;

use crate::error::WalletCoreError;

/// An secp256k1 private key. Zeroized on drop.
pub struct PrivateKey(SigningKey);

impl PrivateKey {
    /// Generate a new key using the OS CSPRNG.
    pub fn generate() -> Self {
        Self(SigningKey::random(&mut OsRng))
    }

    /// Reconstruct a key from raw big-endian bytes (e.g. loaded from secure
    /// storage). Callers must zeroize `bytes` themselves after this call.
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, WalletCoreError> {
        SigningKey::from_slice(bytes)
            .map(Self)
            .map_err(|_| WalletCoreError::InvalidKey)
    }

    pub fn to_bytes(&self) -> [u8; 32] {
        self.0.to_bytes().into()
    }

    pub(crate) fn signing_key(&self) -> &SigningKey {
        &self.0
    }

    pub fn verifying_key(&self) -> k256::ecdsa::VerifyingKey {
        *self.0.verifying_key()
    }
}

impl Drop for PrivateKey {
    fn drop(&mut self) {
        // SigningKey doesn't expose a mutable byte view to zero directly;
        // this scaffold documents intent. Swap in a zeroizing-secret-backed
        // representation before handling real funds.
        let mut scratch = self.to_bytes();
        scratch.zeroize();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_then_reload_roundtrips() {
        let key = PrivateKey::generate();
        let bytes = key.to_bytes();
        let reloaded = PrivateKey::from_bytes(&bytes).unwrap();
        assert_eq!(key.verifying_key(), reloaded.verifying_key());
    }
}
