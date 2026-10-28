//! flutter_rust_bridge surface. This is the *only* module the Flutter app
//! calls into — everything else in this crate is plain Rust, also used
//! directly (unbridged) by the `server` crate.
//!
//! Deliberately narrow for now: onboarding needs a real key + address, and
//! nothing the app currently talks to (`crates/server`'s HTTP API) needs a
//! client-signed payload yet. Add `sign_prehash`-backed bridge functions
//! here when a flow actually needs one, rather than exposing signing
//! up front.

use crate::address::Address;
use crate::encryption::{self, EncryptedBlob};
use crate::keys::PrivateKey;

/// Freshly generated key material for a new wallet. `private_key_hex` must
/// be handed straight to platform secure storage (Keychain/Keystore) by the
/// caller and never logged, cached in plain memory longer than necessary,
/// or sent anywhere but device-local storage.
pub struct WalletKeyMaterial {
    pub private_key_hex: String,
    pub address_hex: String,
}

/// Generate a new secp256k1 key and derive its Base/EVM address. Called
/// once, during onboarding, to produce the `evm_address` that
/// `POST /wallets` expects.
#[flutter_rust_bridge::frb(sync)]
pub fn generate_wallet() -> WalletKeyMaterial {
    let key = PrivateKey::generate();
    let address = Address::from_verifying_key(&key.verifying_key());
    WalletKeyMaterial {
        private_key_hex: hex::encode(key.to_bytes()),
        address_hex: address.to_hex(),
    }
}

/// Re-derives an address from a private key already held in secure
/// storage — used by the "restore from wallet key" flow, which only has
/// the key after decrypting an [`EncryptedKeyBackup`], not a fresh
/// [`WalletKeyMaterial`].
#[flutter_rust_bridge::frb(sync)]
pub fn address_from_private_key(private_key_hex: String) -> Result<String, String> {
    let bytes = hex::decode(&private_key_hex).map_err(|_| "not valid hex".to_string())?;
    let key = PrivateKey::from_bytes(&bytes).map_err(|_| "not a valid private key".to_string())?;
    Ok(Address::from_verifying_key(&key.verifying_key()).to_hex())
}

/// A private key encrypted under a PIN, ready to be embedded in a QR code
/// (see the app's "Download wallet key" screen) or handed back to
/// [`decrypt_wallet_key`] during a "restore from wallet key" import. Every
/// field is plain hex so the whole struct round-trips through a small JSON
/// blob for the QR payload.
pub struct EncryptedKeyBackup {
    pub address_hex: String,
    pub salt_hex: String,
    pub nonce_hex: String,
    pub ciphertext_hex: String,
}

/// Encrypts `private_key_hex` under `pin` (AES-256-GCM, PBKDF2-stretched
/// key — see `encryption.rs`). `address_hex` is carried along unencrypted
/// purely so the QR payload and the on-screen backup card can show which
/// wallet a given code belongs to; it reveals nothing a blockchain
/// explorer wouldn't.
///
/// **Legacy (v1): retained for decrypting already-printed backups only.**
/// New exports must use [`create_split_backup`] — v1 embeds the whole key
/// under a short PIN and falls to offline brute force in minutes.
#[flutter_rust_bridge::frb(sync)]
pub fn encrypt_wallet_key(private_key_hex: String, address_hex: String, pin: String) -> Result<EncryptedKeyBackup, String> {
    let bytes = hex::decode(&private_key_hex).map_err(|_| "not valid hex".to_string())?;
    let blob = encryption::encrypt(&bytes, &pin);
    Ok(EncryptedKeyBackup {
        address_hex,
        salt_hex: hex::encode(blob.salt),
        nonce_hex: hex::encode(blob.nonce),
        ciphertext_hex: hex::encode(blob.ciphertext),
    })
}

/// Reverses [`encrypt_wallet_key`]. Returns the same generic error for a
/// wrong PIN or a corrupted/tampered backup — see [`encryption::decrypt`]'s
/// doc comment for why that's deliberate.
#[flutter_rust_bridge::frb(sync)]
pub fn decrypt_wallet_key(backup: EncryptedKeyBackup, pin: String) -> Result<String, String> {
    let salt: [u8; 16] = hex::decode(&backup.salt_hex)
        .map_err(|_| "corrupted backup".to_string())?
        .try_into()
        .map_err(|_| "corrupted backup".to_string())?;
    let nonce: [u8; 12] = hex::decode(&backup.nonce_hex)
        .map_err(|_| "corrupted backup".to_string())?
        .try_into()
        .map_err(|_| "corrupted backup".to_string())?;
    let ciphertext = hex::decode(&backup.ciphertext_hex).map_err(|_| "corrupted backup".to_string())?;

    let blob = EncryptedBlob { salt, nonce, ciphertext };
    let plaintext = encryption::decrypt(&blob, &pin).map_err(|_| "incorrect PIN, or the file is corrupted".to_string())?;
    Ok(hex::encode(plaintext))
}

/// Whether `pin` is acceptable as a backup PIN. Enforced in Rust (not just
/// the UI) so every caller — app, tests, future platforms — gets the same
/// blocklist. See `encryption::is_backup_pin_allowed`.
#[flutter_rust_bridge::frb(sync)]
pub fn is_backup_pin_allowed(pin: String) -> bool {
    encryption::is_backup_pin_allowed(&pin)
}

/// Creates a v2 split backup. The private key is split into two random
/// shares: `S1` is Argon2id-wrapped under `pin` and returned inside
/// `qr_payload` (the only thing ever embedded in the QR image), while `S2`
/// must be uploaded to the server release oracle before the QR is shown.
///
/// Returns a JSON string (primitive-typed for a stable bridge surface):
/// `{"backup_id","qr_payload","s2_hex","address_hex"}`, where `qr_payload`
/// is itself the v2 envelope JSON the QR encodes:
/// `{"v":2,"id","addr","s","n","c"}`.
///
/// `S1` alone is uniformly random: brute-forcing the QR's PIN yields
/// nothing usable without the server-held `S2`. Restores complete only via
/// the app + server together (`decrypt_backup_share` then
/// `combine_backup_shares` after the release oracle returns `S2`).
#[flutter_rust_bridge::frb(sync)]
pub fn create_split_backup(
    private_key_hex: String,
    address_hex: String,
    pin: String,
) -> Result<String, String> {
    if !encryption::is_backup_pin_allowed(&pin) {
        return Err("that PIN is too easy to guess — choose a less predictable one".to_string());
    }
    let key_bytes = hex::decode(&private_key_hex).map_err(|_| "not valid hex".to_string())?;
    let key: [u8; 32] = key_bytes.try_into().map_err(|_| "not a valid private key".to_string())?;
    // Must be a real secp256k1 key, not 32 arbitrary bytes.
    PrivateKey::from_bytes(&key).map_err(|_| "not a valid private key".to_string())?;

    let split = encryption::split_private_key(&key);
    let blob = encryption::encrypt_share_v2(&split.s1, &pin).map_err(|_| "encryption failed".to_string())?;
    let backup_id = uuid::Uuid::new_v4().to_string();
    let qr_payload = serde_json::json!({
        "v": 2,
        "id": backup_id,
        "addr": address_hex,
        "s": hex::encode(blob.salt),
        "n": hex::encode(blob.nonce),
        "c": hex::encode(blob.ciphertext),
    })
    .to_string();
    let out = serde_json::json!({
        "backup_id": backup_id,
        "qr_payload": qr_payload,
        "s2_hex": hex::encode(split.s2),
        "address_hex": address_hex,
    })
    .to_string();
    Ok(out)
}

/// Decrypts the QR-side share of a v2 backup. Returns `s1_hex` — random
/// bytes, useless without the server-held `s2_hex`. Fails closed on wrong
/// PIN or tampering.
#[flutter_rust_bridge::frb(sync)]
pub fn decrypt_backup_share(
    salt_hex: String,
    nonce_hex: String,
    ciphertext_hex: String,
    pin: String,
) -> Result<String, String> {
    let salt: [u8; 16] = hex::decode(&salt_hex)
        .map_err(|_| "corrupted backup".to_string())?
        .try_into()
        .map_err(|_| "corrupted backup".to_string())?;
    let nonce: [u8; 12] = hex::decode(&nonce_hex)
        .map_err(|_| "corrupted backup".to_string())?
        .try_into()
        .map_err(|_| "corrupted backup".to_string())?;
    let ciphertext = hex::decode(&ciphertext_hex).map_err(|_| "corrupted backup".to_string())?;
    let blob = EncryptedBlob { salt, nonce, ciphertext };
    let s1 = encryption::decrypt_share_v2(&blob, &pin)
        .map_err(|_| "incorrect PIN, or the file is corrupted".to_string())?;
    Ok(hex::encode(s1))
}

/// Recombines both v2 shares into the private key hex. Call only with the
/// server-released `s2` in hand, in app memory, immediately before restore —
/// then wipe.
#[flutter_rust_bridge::frb(sync)]
pub fn combine_backup_shares(s1_hex: String, s2_hex: String) -> Result<String, String> {
    let s1 = hex::decode(&s1_hex).map_err(|_| "corrupted backup".to_string())?;
    let s2 = hex::decode(&s2_hex).map_err(|_| "corrupted backup".to_string())?;
    let s1: [u8; 32] = s1.try_into().map_err(|_| "corrupted backup".to_string())?;
    let s2: [u8; 32] = s2.try_into().map_err(|_| "corrupted backup".to_string())?;
    let key = encryption::combine_shares(&s1, &s2);
    // Must still be a valid key — catches corrupted/mismatched shares
    // before anything is persisted.
    PrivateKey::from_bytes(&key).map_err(|_| "corrupted backup".to_string())?;
    Ok(hex::encode(key))
}

// --- OPAQUE password-authenticated key exchange (RFC 9807) -----------------
// The per-backup key PIN is the OPAQUE password (one password file per
// `backup_id`, see `opaque.rs`). Client state lives in Rust memory between
// calls; the app holds only single-use handles. All messages cross as
// base64 inside small JSON envelopes (primitive-typed bridge surface).

/// Begins OPAQUE registration. Returns
/// `{"handle","request_b64"}` — POST `request_b64` to register/start.
#[flutter_rust_bridge::frb(sync)]
pub fn opaque_register_start(pin: String) -> Result<String, String> {
    let (handle, request) =
        crate::opaque::client_register_start(&pin).map_err(|_| "registration failed".to_string())?;
    Ok(serde_json::json!({
        "handle": handle,
        "request_b64": crate::opaque::b64_encode(&request),
    })
    .to_string())
}

/// Completes OPAQUE registration with the server's `response_b64`. Returns
/// `{"upload_b64"}` for register/finish. The handle is consumed.
#[flutter_rust_bridge::frb(sync)]
pub fn opaque_register_finish(handle: String, response_b64: String, pin: String) -> Result<String, String> {
    let upload = crate::opaque::client_register_finish(&handle, &response_b64, &pin)
        .map_err(|_| "registration failed".to_string())?;
    Ok(serde_json::json!({ "upload_b64": crate::opaque::b64_encode(&upload) }).to_string())
}

/// Begins an OPAQUE login. Returns `{"handle","request_b64"}` — POST
/// `request_b64` to login/start. The client authenticates the server
/// inside `finish`: a fake server fails there, never later.
#[flutter_rust_bridge::frb(sync)]
pub fn opaque_login_start(pin: String) -> Result<String, String> {
    let (handle, request) =
        crate::opaque::client_login_start(&pin).map_err(|_| "login failed".to_string())?;
    Ok(serde_json::json!({
        "handle": handle,
        "request_b64": crate::opaque::b64_encode(&request),
    })
    .to_string())
}

/// Completes an OPAQUE login with the server's `response_b64`. Returns
/// `{"finalization_b64"}` for login/finish. The handle is consumed.
#[flutter_rust_bridge::frb(sync)]
pub fn opaque_login_finish(handle: String, response_b64: String, pin: String) -> Result<String, String> {
    let finalization = crate::opaque::client_login_finish(&handle, &response_b64, &pin)
        .map_err(|_| "incorrect PIN, or the file is corrupted".to_string())?;
    Ok(serde_json::json!({ "finalization_b64": crate::opaque::b64_encode(&finalization) })
        .to_string())
}

#[cfg(test)]
mod restore_from_key_tests {
    //! Exercises the exact call sequence `RestoreFromKeyScreen` makes
    //! (see `app/lib/src/onboarding/restore_from_key_flow.dart`):
    //! generate → encrypt (export) → decrypt (import) → re-derive address
    //! → confirm it matches the original wallet. The Dart side is thin
    //! wiring over these same four functions, so a green test here is
    //! strong evidence the whole "upload the key, unlock it" flow is
    //! cryptographically sound end to end.
    use super::*;

    #[test]
    fn full_export_then_restore_roundtrip_recovers_the_same_address() {
        let original = generate_wallet();

        let backup = encrypt_wallet_key(original.private_key_hex.clone(), original.address_hex.clone(), "483920".to_string())
            .expect("encryption should succeed for a freshly generated key");

        // The QR payload only ever carries `backup`'s four hex fields
        // (see `WalletKeyBackupCodec` on the Dart side) — nothing else
        // from `original` crosses that boundary in the real flow.
        let recovered_private_key_hex =
            decrypt_wallet_key(backup, "483920".to_string()).expect("decryption with the correct PIN should succeed");
        assert_eq!(recovered_private_key_hex, original.private_key_hex);

        let recovered_address =
            address_from_private_key(recovered_private_key_hex).expect("a decrypted key should re-derive a valid address");
        assert_eq!(recovered_address, original.address_hex);
    }

    #[test]
    fn restoring_with_the_wrong_key_pin_fails_closed() {
        let original = generate_wallet();
        let backup = encrypt_wallet_key(original.private_key_hex, original.address_hex, "111111".to_string()).unwrap();

        let result = decrypt_wallet_key(backup, "222222".to_string());
        assert!(result.is_err(), "a wrong key PIN must never recover the private key");
    }
}
