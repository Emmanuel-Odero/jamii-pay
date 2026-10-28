//! Envelope encryption for server-held backup shares (`S2`).
//!
//! Threat model: a bare database dump must not become a share dump. Every
//! `S2` is sealed with XChaCha20-Poly1305 under a key that lives outside
//! the database before it is stored, and unsealed only inside the release
//! oracle after authentication.
//!
//! Key sourcing, in order:
//! 1. `BACKUP_SEAL_KEY` — 64 hex chars (32 bytes). Production.
//! 2. Missing → an ephemeral key is generated and every boot logs a loud
//!    warning. Releases sealed under a previous ephemeral key fail after
//!    restart. This is strictly a local-dev convenience; any non-local
//!    deployment without `BACKUP_SEAL_KEY` refuses to boot (see
//!    [`Sealer::from_env`]).
//!
//! Rotation: set `BACKUP_SEAL_KEY` to the new key and keep the old one in
//! `BACKUP_SEAL_KEY_OLD`. [`Sealer::unseal`] tries primary first, then the
//! old key, and reports which so callers can lazily re-seal. Remove the old
//! key only after every row has been re-sealed (the release path does this
//! automatically on each successful release).
//!
//! KMS path: replace `LocalSealer`'s key handle with an AWS KMS
//! `Encrypt`/`Decrypt` call behind this same trait surface — the wire
//! format (`0x01 || nonce24 || ciphertext`) is untouched, so stored rows
//! migrate by re-seal, same as rotation. Until then this module *is* the
//! sealer; there is no "TODO: encrypt" gap anywhere in the release path.

use chacha20poly1305::{
    aead::{Aead, KeyInit},
    XChaCha20Poly1305, XNonce,
};
use rand::{rngs::OsRng, RngCore};

const VERSION: u8 = 0x01;
const NONCE_LEN: usize = 24;

#[derive(Debug)]
pub enum SealError {
    BadKey(String),
    Seal(String),
    Open(String),
}

impl std::fmt::Display for SealError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SealError::BadKey(m) | SealError::Seal(m) | SealError::Open(m) => write!(f, "{m}"),
        }
    }
}

pub struct Sealer {
    primary: [u8; 32],
    old: Option<[u8; 32]>,
    pub ephemeral: bool,
}

impl Sealer {
    /// Builds the sealer from the environment. Panics when `REQUIRE_SEAL_KEY`
    /// is set (non-local deployments) and no usable key is configured —
    /// booting without a stable seal key would silently brick every
    /// escrowed share on the next restart.
    pub fn from_env() -> Result<Self, SealError> {
        let primary = match std::env::var("BACKUP_SEAL_KEY") {
            Ok(hex) => parse_key(&hex).map_err(SealError::BadKey)?,
            Err(_) => {
                if std::env::var("REQUIRE_SEAL_KEY").is_ok() {
                    return Err(SealError::BadKey(
                        "BACKUP_SEAL_KEY is required (REQUIRE_SEAL_KEY is set)".to_string(),
                    ));
                }
                tracing::warn!(
                    "BACKUP_SEAL_KEY unset — using an EPHEMERAL seal key. \
                     Escrowed shares will NOT survive a restart. \
                     Set BACKUP_SEAL_KEY (and REQUIRE_SEAL_KEY=1 outside local dev)."
                );
                let mut key = [0u8; 32];
                OsRng.fill_bytes(&mut key);
                return Ok(Self { primary: key, old: None, ephemeral: true });
            }
        };
        let old = match std::env::var("BACKUP_SEAL_KEY_OLD") {
            Ok(hex) if !hex.trim().is_empty() => Some(parse_key(&hex).map_err(SealError::BadKey)?),
            _ => None,
        };
        Ok(Self { primary, old, ephemeral: false })
    }

    /// Seals `plaintext` under the primary key. Output is self-described
    /// (`VERSION || nonce || ciphertext`) so future formats can coexist.
    pub fn seal(&self, plaintext: &[u8]) -> Result<Vec<u8>, SealError> {
        seal_with(&self.primary, plaintext)
    }

    /// Unseals, trying the primary key then the rotation key.
    /// Returns `(plaintext, used_old_key)` — callers re-seal under primary
    /// when `used_old_key` is true (lazy rotation).
    pub fn unseal(&self, blob: &[u8]) -> Result<(Vec<u8>, bool), SealError> {
        match open_with(&self.primary, blob) {
            Ok(pt) => Ok((pt, false)),
            Err(_) => match &self.old {
                Some(old) => open_with(old, blob).map(|pt| (pt, true)).map_err(|_| SealError::Open("cannot open sealed share".to_string())),
                None => Err(SealError::Open("cannot open sealed share".to_string())),
            },
        }
    }
}

fn parse_key(hex_str: &str) -> Result<[u8; 32], String> {
    let bytes = hex::decode(hex_str.trim())
        .map_err(|_| "BACKUP_SEAL_KEY must be 64 hex chars".to_string())?;
    bytes.try_into().map_err(|_| "BACKUP_SEAL_KEY must be 64 hex chars".to_string())
}

fn seal_with(key: &[u8; 32], plaintext: &[u8]) -> Result<Vec<u8>, SealError> {
    let cipher = XChaCha20Poly1305::new_from_slice(key).map_err(|e| SealError::Seal(e.to_string()))?;
    let mut nonce_bytes = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut nonce_bytes);
    let ct = cipher
        .encrypt(XNonce::from_slice(&nonce_bytes), plaintext)
        .map_err(|e| SealError::Seal(e.to_string()))?;
    let mut out = Vec::with_capacity(1 + NONCE_LEN + ct.len());
    out.push(VERSION);
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ct);
    Ok(out)
}

fn open_with(key: &[u8; 32], blob: &[u8]) -> Result<Vec<u8>, SealError> {
    if blob.len() < 1 + NONCE_LEN + 16 || blob[0] != VERSION {
        return Err(SealError::Open("cannot open sealed share".to_string()));
    }
    let cipher = XChaCha20Poly1305::new_from_slice(key).map_err(|_| SealError::Open("cannot open sealed share".to_string()))?;
    cipher
        .decrypt(XNonce::from_slice(&blob[1..1 + NONCE_LEN]), &blob[1 + NONCE_LEN..])
        .map_err(|_| SealError::Open("cannot open sealed share".to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_sealer() -> Sealer {
        Sealer { primary: [0x11u8; 32], old: Some([0x22u8; 32]), ephemeral: false }
    }

    #[test]
    fn roundtrips_primary() {
        let s = test_sealer();
        let blob = s.seal(b"0123456789abcdef0123456789abcdef").unwrap();
        let (pt, rotated) = s.unseal(&blob).unwrap();
        assert_eq!(pt, b"0123456789abcdef0123456789abcdef");
        assert!(!rotated);
    }

    #[test]
    fn falls_back_to_old_key_and_flags_rotation() {
        let old_only = Sealer { primary: [0x11u8; 32], old: None, ephemeral: false };
        let blob = seal_with(&[0x22u8; 32], b"share-bytes-32....................").unwrap();
        assert!(old_only.unseal(&blob).is_err());
        let (pt, rotated) = test_sealer().unseal(&blob).unwrap();
        assert!(rotated);
        assert_eq!(&pt, b"share-bytes-32....................");
    }

    #[test]
    fn tampered_blob_fails_closed() {
        let s = test_sealer();
        let mut blob = s.seal(b"0123456789abcdef0123456789abcdef").unwrap();
        let last = blob.len() - 1;
        blob[last] ^= 0x01;
        assert!(s.unseal(&blob).is_err());
        assert!(s.unseal(b"short").is_err());
        assert!(s.unseal(b"\x02garbage-garbage-garbage-garbage!").is_err());
    }

    #[test]
    fn from_env_rejects_bad_keys_and_requires_when_asked() {
        unsafe { std::env::set_var("BACKUP_SEAL_KEY", "not-hex") };
        assert!(Sealer::from_env().is_err());
        unsafe { std::env::set_var("BACKUP_SEAL_KEY", "ab") };
        assert!(Sealer::from_env().is_err());
        unsafe { std::env::remove_var("BACKUP_SEAL_KEY") };
        unsafe { std::env::set_var("REQUIRE_SEAL_KEY", "1") };
        assert!(Sealer::from_env().is_err());
        unsafe { std::env::remove_var("REQUIRE_SEAL_KEY") };
    }
}
