//! Password-based encryption for exporting a private key off-device.
//!
//! Two generations:
//!
//! - **v1 (legacy):** the whole private key under a PBKDF2-SHA256-stretched
//!   PIN (100k rounds). Kept for *decrypting* backups users already printed.
//!   A 6-digit PIN under this scheme falls to an offline GPU in minutes,
//!   so v1 must never be produced for new exports.
//! - **v2 (current):** the private key is first split into two random
//!   32-byte shares (`S1 XOR S2 == key`). Only `S1` is PIN-wrapped (with
//!   Argon2id, the OWASP-recommended memory-hard KDF) and embedded in the
//!   QR; `S2` is uploaded to the server release oracle. `S1` alone is
//!   uniformly random — it reveals zero bits of the key no matter how much
//!   compute an attacker spends. Restores complete only via the app +
//!   server together.

use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use argon2::{Argon2, Params};
use pbkdf2::pbkdf2_hmac;
use rand_core::{OsRng, RngCore};
use sha2::Sha256;
use zeroize::Zeroize;

use crate::error::WalletCoreError;

/// v1 iteration count — frozen. Do not raise: v1 backups already printed
/// were derived with this count, and changing it would brick them.
const PBKDF2_ROUNDS_V1: u32 = 100_000;
const SALT_LEN: usize = 16;
const NONCE_LEN: usize = 12;

/// Argon2id params for v2 envelopes: m=19 MiB, t=2, p=1 (OWASP baseline).
/// ~100-200ms on modern phones — imperceptible per export, ~1000x more
/// GPU-resistant per guess than PBKDF2.
fn argon2_v2() -> Argon2<'static> {
    Argon2::new(
        argon2::Algorithm::Argon2id,
        argon2::Version::V0x13,
        Params::new(19 * 1024, 2, 1, Some(32)).expect("fixed v2 params valid"),
    )
}

pub struct EncryptedBlob {
    pub salt: [u8; SALT_LEN],
    pub nonce: [u8; NONCE_LEN],
    pub ciphertext: Vec<u8>,
}

fn derive_key_v1(pin: &str, salt: &[u8]) -> [u8; 32] {
    let mut key = [0u8; 32];
    pbkdf2_hmac::<Sha256>(pin.as_bytes(), salt, PBKDF2_ROUNDS_V1, &mut key);
    key
}

fn derive_key_v2(pin: &str, salt: &[u8; SALT_LEN]) -> Result<[u8; 32], WalletCoreError> {
    let mut key = [0u8; 32];
    argon2_v2()
        .hash_password_into(pin.as_bytes(), salt, &mut key)
        .map_err(|_| WalletCoreError::InvalidKey)?;
    Ok(key)
}

/// Encrypts `plaintext` (the raw 32-byte private key) under a key derived
/// from `pin`. Fresh random salt and nonce every call, so encrypting the
/// same key with the same PIN twice never produces the same ciphertext.
///
/// v1 only — retained for decrypting already-printed backups. New exports
/// must use [`encrypt_share_v2`] on a split share instead.
pub fn encrypt(plaintext: &[u8], pin: &str) -> EncryptedBlob {
    let mut salt = [0u8; SALT_LEN];
    OsRng.fill_bytes(&mut salt);
    let key = derive_key_v1(pin, &salt);

    let mut nonce_bytes = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let cipher = Aes256Gcm::new_from_slice(&key).expect("32-byte key is always valid for AES-256");
    let ciphertext = cipher
        .encrypt(nonce, plaintext)
        .expect("AES-GCM encryption over an in-memory buffer cannot fail");

    EncryptedBlob { salt, nonce: nonce_bytes, ciphertext }
}

/// Wraps one 32-byte split share under an Argon2id-stretched PIN (v2).
/// Fresh random salt + nonce per call — same share + same PIN still
/// encrypts differently every time.
pub fn encrypt_share_v2(share: &[u8; 32], pin: &str) -> Result<EncryptedBlob, WalletCoreError> {
    let mut salt = [0u8; SALT_LEN];
    OsRng.fill_bytes(&mut salt);
    let key = derive_key_v2(pin, &salt)?;

    let mut nonce_bytes = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let cipher = Aes256Gcm::new_from_slice(&key).expect("32-byte key is always valid for AES-256");
    let ciphertext = cipher
        .encrypt(nonce, share.as_slice())
        .expect("AES-GCM encryption over an in-memory buffer cannot fail");

    Ok(EncryptedBlob { salt, nonce: nonce_bytes, ciphertext })
}

/// Unwraps a v2 share envelope. Fails closed (generic error) on wrong PIN
/// or tampering — GCM's tag makes those indistinguishable by design.
pub fn decrypt_share_v2(blob: &EncryptedBlob, pin: &str) -> Result<[u8; 32], WalletCoreError> {
    let key = derive_key_v2(pin, &blob.salt)?;
    let nonce = Nonce::from_slice(&blob.nonce);
    let cipher = Aes256Gcm::new_from_slice(&key).expect("32-byte key is always valid for AES-256");
    let mut pt = cipher
        .decrypt(nonce, blob.ciphertext.as_ref())
        .map_err(|_| WalletCoreError::InvalidKey)?;
    if pt.len() != 32 {
        pt.zeroize();
        return Err(WalletCoreError::InvalidKey);
    }
    let mut share = [0u8; 32];
    share.copy_from_slice(&pt);
    pt.zeroize();
    Ok(share)
}

/// Reverses [`encrypt`] (v1 only). Fails with [`WalletCoreError::InvalidKey`]
/// on a wrong PIN or a corrupted/tampered blob — GCM's authentication tag
/// makes those indistinguishable, which is the point: nothing here should
/// let a caller distinguish "wrong PIN" from "tampered file" by timing or
/// error shape.
pub fn decrypt(blob: &EncryptedBlob, pin: &str) -> Result<Vec<u8>, WalletCoreError> {
    let key = derive_key_v1(pin, &blob.salt);
    let nonce = Nonce::from_slice(&blob.nonce);
    let cipher = Aes256Gcm::new_from_slice(&key).expect("32-byte key is always valid for AES-256");
    cipher
        .decrypt(nonce, blob.ciphertext.as_ref())
        .map_err(|_| WalletCoreError::InvalidKey)
}

/// Splits a 32-byte private key into two random shares with
/// `S1 XOR S2 == key`. Either share alone is uniformly random and reveals
/// nothing about the key (one-time-pad property) — brute-forcing the QR
/// (which holds only an encrypted `S1`) can never yield the key without
/// the server-held `S2`, regardless of compute spent.
pub struct KeySplit {
    pub s1: [u8; 32],
    pub s2: [u8; 32],
}

pub fn split_private_key(key: &[u8; 32]) -> KeySplit {
    let mut s1 = [0u8; 32];
    OsRng.fill_bytes(&mut s1);
    let mut s2 = [0u8; 32];
    for i in 0..32 {
        s2[i] = key[i] ^ s1[i];
    }
    KeySplit { s1, s2 }
}

/// Recombines both shares. The caller must wipe the result as soon as the
/// restore completes — see [`combine_shares_hex`] for the hex boundary
/// that zeroizes intermediates.
pub fn combine_shares(s1: &[u8; 32], s2: &[u8; 32]) -> [u8; 32] {
    let mut key = [0u8; 32];
    for i in 0..32 {
        key[i] = s1[i] ^ s2[i];
    }
    key
}

/// Backup-PIN allowlist. Short numeric PINs are inherently weak, so at
/// minimum the catastrophically guessable ones are refused: trivial length,
/// all-identical digits, full ascending/descending runs, and a blocklist of
/// the most-abused values. Longer alphanumeric passphrases (allowed for v2
/// backups) skip the sequential-digit checks but still hit the blocklist.
pub fn is_backup_pin_allowed(pin: &str) -> bool {
    let len = pin.chars().count();
    if len < 6 || len > 64 {
        return false;
    }
    let lower = pin.to_lowercase();
    const BLOCKED: &[&str] = &[
        "000000", "111111", "123456", "654321", "123123", "121212", "112233",
        "123321", "456789", "987654", "123456789", "password", "qwerty",
        "jamiipay", "letmein", "999999",
    ];
    if BLOCKED.contains(&lower.as_str()) {
        return false;
    }
    let bytes: Vec<char> = pin.chars().collect();
    if bytes.iter().all(|&c| c == bytes[0]) {
        return false;
    }
    if bytes.iter().all(|c| c.is_ascii_digit()) && bytes.len() >= 6 {
        let ascending = bytes.windows(2).all(|w| {
            w[1] as i32 - w[0] as i32 == 1 || (w[0] == '9' && w[1] == '0')
        });
        let descending = bytes.windows(2).all(|w| w[0] as i32 - w[1] as i32 == 1);
        if ascending || descending {
            return false;
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrips_with_correct_pin() {
        let plaintext = b"0123456789abcdef0123456789abcdef";
        let blob = encrypt(plaintext, "483920");
        let decrypted = decrypt(&blob, "483920").unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn rejects_wrong_pin() {
        let blob = encrypt(b"secret-key-bytes", "111111");
        assert!(decrypt(&blob, "222222").is_err());
    }

    #[test]
    fn two_encryptions_of_same_plaintext_differ() {
        let a = encrypt(b"same-plaintext-bytes", "999999");
        let b = encrypt(b"same-plaintext-bytes", "999999");
        assert_ne!(a.ciphertext, b.ciphertext);
    }

    #[test]
    fn split_shares_reveal_nothing_alone_but_combine() {
        let key = [0xA5u8; 32];
        let split = super::split_private_key(&key);
        // Neither share equals the key or each other (overwhelmingly).
        assert_ne!(split.s1, key);
        assert_ne!(split.s2, key);
        assert_eq!(super::combine_shares(&split.s1, &split.s2), key);
    }

    #[test]
    fn v2_share_envelope_roundtrips_and_rejects_wrong_pin() {
        let split = super::split_private_key(&[7u8; 32]);
        let blob = super::encrypt_share_v2(&split.s1, "correct horse 42").unwrap();
        assert_eq!(super::decrypt_share_v2(&blob, "correct horse 42").unwrap(), split.s1);
        assert!(super::decrypt_share_v2(&blob, "wrong pin here").is_err());
    }

    #[test]
    fn pin_blocklist_rejects_trivial_pins() {
        for bad in ["123456", "000000", "111111", "654321", "password", "99999", "abc"] {
            assert!(!super::is_backup_pin_allowed(bad), "{bad} should be rejected");
        }
        assert!(super::is_backup_pin_allowed("483920"));
        assert!(super::is_backup_pin_allowed("correct horse 42"));
    }
}
