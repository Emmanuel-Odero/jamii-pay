//! OPAQUE password-authenticated key exchange (RFC 9807) for split-backup
//! PINs — the single source of truth both crates share (the server depends
//! on `wallet_core`, so the ciphersuite cannot drift between client and
//! server; a mismatch would brick every backup, loudly, at registration).
//!
//! Why OPAQUE instead of "send sha256(pin), bcrypt-verify": the server
//! never sees the PIN *or any deterministic function of it*. Registration
//! uploads a blinded request; the stored password file leaks nothing
//! offline-dictionaryable beyond OPAQUE's own OPRF envelope (Argon2id
//! inside, per the ciphersuite below). Every release attempt is an online
//! login the server throttles, locks, and audit-logs. Replay of a captured
//! `pin_hash` buys nothing — there is no reusable credential on the wire.
//!
//! Passwords here are the per-backup **key PINs** (one password file per
//! `backup_id`). The wallet unlock PIN keeps its existing verify-pin gate
//! at restore time — two independent secrets, two independent failures
//! required before money moves.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine;
use opaque_ke::ciphersuite::CipherSuite;
use opaque_ke::{argon2::Argon2, Ristretto255, TripleDh};
use rand_core::{OsRng, RngCore};

/// Protocol version tag. Stored alongside password files and checked on
/// load — a future ciphersuite migration must mint a new tag, never
/// silently reinterpret old bytes.
pub const OPAQUE_VERSION_TAG: &str = "opaque-v1";

/// The one ciphersuite for all JamiiPay OPAQUE flows.ristretto255 OPRF +
/// Triple-DH key exchange + Argon2id KSF. MUST be identical everywhere;
/// it lives here (not copy-pasted per crate) so it cannot drift.
pub struct JamiipayCs;

impl CipherSuite for JamiipayCs {
    type OprfCs = Ristretto255;
    type KeyExchange = TripleDh<Ristretto255, sha2::Sha512>;
    type Ksf = Argon2<'static>;
}

pub fn b64_encode(bytes: &[u8]) -> String {
    B64.encode(bytes)
}

pub fn b64_decode(s: &str) -> Result<Vec<u8>, crate::error::WalletCoreError> {
    B64.decode(s.trim()).map_err(|_| crate::error::WalletCoreError::InvalidKey)
}

// Client state held in Rust memory between FRB calls (the app holds only
// an opaque `handle`). States never cross the bridge — a compromised Dart
// heap yields handles, not keys. Handles are single-use and consumed on
// finish; the map is best-effort bounded (pruned on insert).
enum ClientState {
    Registration(opaque_ke::ClientRegistration<JamiipayCs>),
    Login(opaque_ke::ClientLogin<JamiipayCs>),
}

struct OpaqueClients {
    inner: Mutex<HashMap<String, ClientState>>,
}

impl OpaqueClients {
    fn global() -> &'static Self {
        static GLOBAL: OnceLock<OpaqueClients> = OnceLock::new();
        GLOBAL.get_or_init(|| OpaqueClients { inner: Mutex::new(HashMap::new()) })
    }

    fn insert(&self, state: ClientState) -> String {
        let mut id_bytes = [0u8; 16];
        OsRng.fill_bytes(&mut id_bytes);
        let handle = hex::encode(id_bytes);
        let mut map = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        // Best-effort bound: a leaked handle per tap is a memory drip.
        if map.len() > 64 {
            map.clear();
        }
        map.insert(handle.clone(), state);
        handle
    }

    fn take(&self, handle: &str) -> Option<ClientState> {
        self.inner.lock().ok()?.remove(handle)
    }
}

fn protocol_err() -> crate::error::WalletCoreError {
    crate::error::WalletCoreError::InvalidKey
}

/// Begins an OPAQUE registration for `password`. Returns JSON
/// `{"handle","request_b64"}` — send `request_b64` to the server's
/// register/start endpoint, then complete with [`client_register_finish`].
pub fn client_register_start(
    password: &str,
) -> Result<(String, Vec<u8>), crate::error::WalletCoreError> {
    let mut rng = OsRng;
    let start = opaque_ke::ClientRegistration::<JamiipayCs>::start(&mut rng, password.as_bytes())
        .map_err(|_| protocol_err())?;
    let request = start.message.serialize().to_vec();
    let handle = OpaqueClients::global().insert(ClientState::Registration(start.state));
    Ok((handle, request))
}

/// Completes registration with the server's `response_b64`. Returns the
/// `upload` bytes for register/finish. The handle is consumed.
pub fn client_register_finish(
    handle: &str,
    response_b64: &str,
    password: &str,
) -> Result<Vec<u8>, crate::error::WalletCoreError> {
    let state = OpaqueClients::global().take(handle).ok_or_else(protocol_err)?;
    let ClientState::Registration(reg) = state else {
        return Err(protocol_err());
    };
    let response_bytes = b64_decode(response_b64)?;
    let response = opaque_ke::RegistrationResponse::<JamiipayCs>::deserialize(&response_bytes)
        .map_err(|_| protocol_err())?;
    let mut rng = OsRng;
    let result = reg
        .finish(
            &mut rng,
            password.as_bytes(),
            response,
            opaque_ke::ClientRegistrationFinishParameters::default(),
        )
        .map_err(|_| protocol_err())?;
    Ok(result.message.serialize().to_vec())
}

/// Begins an OPAQUE login for `password`. Returns JSON
/// `{"handle","request_b64"}` — send `request_b64` to login/start, then
/// complete with [`client_login_finish`]. The client verifies the server's
/// authenticator inside `finish`: a fake server fails here, not later.
pub fn client_login_start(
    password: &str,
) -> Result<(String, Vec<u8>), crate::error::WalletCoreError> {
    let mut rng = OsRng;
    let start = opaque_ke::ClientLogin::<JamiipayCs>::start(&mut rng, password.as_bytes())
        .map_err(|_| protocol_err())?;
    let request = start.message.serialize().to_vec();
    let handle = OpaqueClients::global().insert(ClientState::Login(start.state));
    Ok((handle, request))
}

/// Completes login with the server's `response_b64`. Returns the
/// finalization bytes for login/finish. The handle is consumed. The client
/// session key is deliberately discarded — the server releases `S2` on its
/// own successful verification; no client-held session secret is needed.
pub fn client_login_finish(
    handle: &str,
    response_b64: &str,
    password: &str,
) -> Result<Vec<u8>, crate::error::WalletCoreError> {
    let state = OpaqueClients::global().take(handle).ok_or_else(protocol_err)?;
    let ClientState::Login(login) = state else {
        return Err(protocol_err());
    };
    let response_bytes = b64_decode(response_b64)?;
    let response = opaque_ke::CredentialResponse::<JamiipayCs>::deserialize(&response_bytes)
        .map_err(|_| protocol_err())?;
    let mut rng = OsRng;
    let result = login
        .finish(
            &mut rng,
            password.as_bytes(),
            response,
            opaque_ke::ClientLoginFinishParameters::default(),
        )
        .map_err(|_| protocol_err())?;
    Ok(result.message.serialize().to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Full in-process register → login loop against a local ServerSetup.
    /// Proves client and server halves interoperate (they must — the app
    /// and the server meet only over HTTP in production).
    #[test]
    fn opaque_register_then_login_roundtrip() {
        use opaque_ke::{ServerLogin, ServerLoginParameters, ServerRegistration, ServerSetup};

        let mut rng = OsRng;
        let setup = ServerSetup::<JamiipayCs>::new(&mut rng);
        let password = b"correct horse 42";
        let id = b"backup-id-1";

        // Registration.
        let reg_start = opaque_ke::ClientRegistration::<JamiipayCs>::start(&mut rng, password).unwrap();
        let server_reg_start =
            ServerRegistration::<JamiipayCs>::start(&setup, reg_start.message, id).unwrap();
        let reg_finish = reg_start
            .state
            .finish(
                &mut rng,
                password,
                server_reg_start.message,
                opaque_ke::ClientRegistrationFinishParameters::default(),
            )
            .unwrap();
        let file = ServerRegistration::<JamiipayCs>::finish(reg_finish.message);
        let upload_bytes = file.serialize().to_vec();

        // Login, correct password.
        let login_start = opaque_ke::ClientLogin::<JamiipayCs>::start(&mut rng, password).unwrap();
        let server_login_start = ServerLogin::<JamiipayCs>::start(
            &mut rng,
            &setup,
            Some(file),
            login_start.message,
            id,
            ServerLoginParameters::default(),
        )
        .unwrap();
        let login_finish = login_start
            .state
            .finish(
                &mut rng,
                password,
                server_login_start.message,
                opaque_ke::ClientLoginFinishParameters::default(),
            )
            .unwrap();
        let server_finish = server_login_start
            .state
            .finish(
                login_finish.message,
                ServerLoginParameters::default(),
            )
            .unwrap();
        // Both sides derived the same session key without it crossing.
        assert_eq!(login_finish.session_key, server_finish.session_key);

        // Wrong password fails client-side (server authenticator mismatch).
        let bad_start = opaque_ke::ClientLogin::<JamiipayCs>::start(&mut rng, b"wrong pin here").unwrap();
        let file2 = ServerRegistration::<JamiipayCs>::deserialize(&upload_bytes).unwrap();
        let bad_server = ServerLogin::<JamiipayCs>::start(
            &mut rng,
            &setup,
            Some(file2),
            bad_start.message,
            id,
            ServerLoginParameters::default(),
        )
        .unwrap();
        assert!(bad_start
            .state
            .finish(
                &mut rng,
                b"wrong pin here",
                bad_server.message,
                opaque_ke::ClientLoginFinishParameters::default(),
            )
            .is_err());
    }

    #[test]
    fn handle_store_is_single_use() {
        let (h, _) = client_register_start("some pin 123").unwrap();
        assert!(OpaqueClients::global().take(&h).is_some());
        assert!(OpaqueClients::global().take(&h).is_none());
        assert!(client_register_finish(&h, "AAAA", "some pin 123").is_err());
    }
}
