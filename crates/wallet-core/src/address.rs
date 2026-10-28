//! EVM (Base) address derivation: keccak256(pubkey)[12..32], 0x-prefixed hex.

use k256::ecdsa::VerifyingKey;
use sha3::{Digest, Keccak256};

/// A checksum-free lowercase-hex EVM address. Callers that display an
/// address to a user should apply EIP-55 checksum casing at the UI layer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Address(pub [u8; 20]);

impl Address {
    pub fn from_verifying_key(key: &VerifyingKey) -> Self {
        // Uncompressed public key is 0x04 || X(32) || Y(32); address = last
        // 20 bytes of keccak256(X || Y).
        let uncompressed = key.to_encoded_point(false);
        let pubkey_bytes = &uncompressed.as_bytes()[1..];
        let hash = Keccak256::digest(pubkey_bytes);
        let mut addr = [0u8; 20];
        addr.copy_from_slice(&hash[12..]);
        Self(addr)
    }

    pub fn to_hex(&self) -> String {
        format!("0x{}", hex::encode(self.0))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::keys::PrivateKey;

    #[test]
    fn address_is_20_bytes_hex() {
        let key = PrivateKey::generate();
        let addr = Address::from_verifying_key(&key.verifying_key());
        assert_eq!(addr.to_hex().len(), 42); // "0x" + 40 hex chars
    }
}
