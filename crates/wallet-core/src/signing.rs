//! Transaction/message signing. Produces recoverable ECDSA signatures in the
//! (r, s, v) form Ethereum-family chains (including Base) expect.

use k256::ecdsa::{signature::hazmat::PrehashSigner, RecoveryId, Signature};

use crate::error::WalletCoreError;
use crate::keys::PrivateKey;

pub struct RecoverableSignature {
    pub r: [u8; 32],
    pub s: [u8; 32],
    pub v: u8,
}

/// Sign a pre-hashed 32-byte digest (e.g. keccak256 of an RLP-encoded or
/// EIP-712/UserOperation payload built by the server/app layer). This crate
/// deliberately does not encode transactions itself — that keeps it stable
/// while chain-side encoding evolves in the `server` crate.
pub fn sign_prehash(
    key: &PrivateKey,
    digest: &[u8; 32],
) -> Result<RecoverableSignature, WalletCoreError> {
    let (signature, recid): (Signature, RecoveryId) = key
        .signing_key()
        .sign_prehash(digest)
        .map_err(|e| WalletCoreError::SigningFailed(e.to_string()))?;

    let bytes = signature.to_bytes();
    let mut r = [0u8; 32];
    let mut s = [0u8; 32];
    r.copy_from_slice(&bytes[..32]);
    s.copy_from_slice(&bytes[32..]);

    Ok(RecoverableSignature {
        r,
        s,
        v: recid.to_byte(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha3::{Digest, Keccak256};

    #[test]
    fn signs_a_digest() {
        let key = PrivateKey::generate();
        let digest: [u8; 32] = Keccak256::digest(b"jamiipay test message").into();
        let sig = sign_prehash(&key, &digest).unwrap();
        assert!(sig.v == 0 || sig.v == 1);
    }
}
