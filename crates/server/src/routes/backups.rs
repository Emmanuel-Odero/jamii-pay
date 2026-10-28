use axum::{
    extract::{Path, State},
    routing::post,
    Json, Router,
};
use chrono::{DateTime, Utc};
use opaque_ke::{
    CredentialFinalization, CredentialRequest, RegistrationRequest, RegistrationUpload,
    ServerLogin, ServerLoginParameters,
};
use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;
use wallet_core::opaque::{b64_decode, b64_encode, JamiipayCs, OPAQUE_VERSION_TAG};

use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

/// Release-oracle throttle: failed wallet-PIN attempts before `S2`
/// releases lock. Small enough to kill PIN guessing (6-digit space needs
/// far more), large enough to survive honest typos.
const MAX_RELEASE_ATTEMPTS: i32 = 5;
/// Lock duration once the throttle exhausts. Mirrors the recovery
/// 48-hour safety window (`recovery.rs::RECOVERY_WAIT`) so a guessing
/// attack and a hostile recovery face the same wall.
const LOCK_HOURS: i64 = 48;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/wallets/:id/backups", post(store_backup))
        .route("/backups/:id/release", post(release_backup))
        .route("/backups/:id/revoke", post(revoke_backup))
        .route(
            "/wallets/:id/backups/opaque/register/start",
            post(opaque_register_start),
        )
        .route(
            "/wallets/:id/backups/opaque/register/finish",
            post(opaque_register_finish),
        )
        .route("/backups/:id/opaque/login/start", post(opaque_login_start))
        .route(
            "/backups/:id/opaque/login/finish",
            post(opaque_login_finish),
        )
}

#[derive(Deserialize)]
struct StoreBackupRequest {
    backup_id: String,
    /// Server share `S2` hex. Validated as 64 hex chars (32 bytes) —
    /// anything else is a client bug, rejected before storage.
    s2_hex: String,
}

#[derive(Serialize)]
struct StoreBackupResponse {
    backup_id: String,
    version: i32,
}

/// Escrows the server share at export time. Called once per backup, before
/// the QR is ever shown — if this fails, the app must not display a QR
/// whose other half was never escrowed.
///
/// `S2` is envelope-sealed before storage (see `seal.rs`): a database dump
/// alone never yields a share. Upserts so OPAQUE registration (which runs
/// first and creates the row with the password file) and this call compose
/// in either order — but a row owned by a *different* wallet is a hard
/// conflict, never an overwrite.
async fn store_backup(
    State(state): State<AppState>,
    Path(wallet_id): Path<Uuid>,
    Json(req): Json<StoreBackupRequest>,
) -> ApiResult<Json<StoreBackupResponse>> {
    if req.backup_id.trim().is_empty() || req.backup_id.len() > 64 {
        return Err(ApiError::BadRequest("invalid backup id".to_string()));
    }
    let s2 = req.s2_hex.trim().to_lowercase();
    let s2_bytes = hex::decode(&s2).map_err(|_| ApiError::BadRequest("invalid share".to_string()))?;
    if s2_bytes.len() != 32 {
        return Err(ApiError::BadRequest("invalid share".to_string()));
    }
    // Wallet must exist — never escrow shares for unknown wallets.
    sqlx::query("select id from wallets where id = $1")
        .bind(wallet_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(ApiError::NotFound("no wallet with that id"))?;

    let sealed = state
        .sealer
        .seal(&s2_bytes)
        .map_err(|e| ApiError::Internal(anyhow::anyhow!(e.to_string())))?;

    // A row owned by a *different* wallet is a hard conflict, never an
    // overwrite — backup ids are unguessable, so a collision means a bug
    // or an attack, both worth failing loudly over.
    if let Some(owner) = sqlx::query_scalar::<_, Uuid>(
        "select wallet_id from wallet_backups where backup_id = $1",
    )
    .bind(&req.backup_id)
    .fetch_optional(&state.db)
    .await?
    {
        if owner != wallet_id {
            return Err(ApiError::Conflict(
                "backup id already registered to another wallet",
            ));
        }
    }

    sqlx::query(
        "insert into wallet_backups (backup_id, wallet_id, s2_sealed_hex, version)
         values ($1, $2, $3, 2)
         on conflict (backup_id) do update
         set s2_sealed_hex = excluded.s2_sealed_hex, version = 2",
    )
    .bind(&req.backup_id)
    .bind(wallet_id)
    .bind(hex::encode(&sealed))
    .execute(&state.db)
    .await?;

    audit(&state, wallet_id, Some(&req.backup_id), "share_stored", "").await?;

    Ok(Json(StoreBackupResponse { backup_id: req.backup_id, version: 2 }))
}

#[derive(Deserialize)]
struct ReleaseRequest {
    /// The client's local wallet-PIN hash (same value `verify-pin`
    /// checks) — proves app-level ownership before `S2` leaves the server.
    pin_hash: String,
}

#[derive(Serialize)]
struct ReleaseResponse {
    s2_hex: String,
}

/// Releases `S2` after verifying wallet-PIN knowledge. Rate-limited in the
/// database under row lock: 5 failures lock releases for 48h and the denial
/// is audit-logged (guardians feed off `security_audit` the same way they
/// feed off `recovery_requests`). Generic 401 on wrong PIN — never reveals
/// whether the backup id exists separately from whether the PIN matched.
///
/// Legacy path: only for backups with no OPAQUE password file (predating
/// the PAKE migration). Backups carrying a file must use the OPAQUE login
/// endpoints — the PIN hash is never accepted for them.
async fn release_backup(
    State(state): State<AppState>,
    Path(backup_id): Path<String>,
    Json(req): Json<ReleaseRequest>,
) -> ApiResult<Json<ReleaseResponse>> {
    let mut tx = state.db.begin().await?;

    let row = sqlx::query(
        "select id, wallet_id, s2_sealed_hex, opaque_file, failed_attempts, locked_until, revoked
         from wallet_backups where backup_id = $1 for update",
    )
    .bind(&backup_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(ApiError::Unauthorized("incorrect PIN"))?;

    let wallet_id: Uuid = row.try_get("wallet_id")?;
    let revoked: bool = row.try_get("revoked")?;
    if revoked {
        tx.commit().await?;
        audit(&state, wallet_id, Some(&backup_id), "release_denied", "revoked").await?;
        return Err(ApiError::Gone("this backup was revoked"));
    }

    let has_file: bool = row.try_get::<Option<Vec<u8>>, _>("opaque_file")?.is_some();
    if has_file {
        tx.commit().await?;
        return Err(ApiError::Conflict("this backup uses OPAQUE login"));
    }

    let locked_until: Option<DateTime<Utc>> = row.try_get("locked_until")?;
    if locked_until.map(|t| t > Utc::now()).unwrap_or(false) {
        tx.commit().await?;
        audit(&state, wallet_id, Some(&backup_id), "release_denied", "locked").await?;
        return Err(ApiError::Locked("too many attempts — try again later"));
    }

    // Same secret as `wallets::verify_pin`, dual-verified (v1 bcrypt
    // today, OPAQUE v2 when migrated) — see `pin_verifier.rs`. The release
    // oracle and the restore gate share one function, so a thief needs the
    // wallet PIN, not just the QR's key PIN.
    let (stored, v2): (Option<String>, Option<String>) = {
        let r = sqlx::query(
            "select pin_hash_bcrypt, pin_version, pin_verifier from wallets where id = $1",
        )
        .bind(wallet_id)
        .fetch_optional(&mut *tx)
        .await?;
        match r {
            None => (None, None),
            Some(r) => {
                let version: Option<i32> = r.try_get("pin_version").ok().flatten();
                let verifier: Option<String> = r.try_get("pin_verifier").ok().flatten();
                let v2 = if version.unwrap_or(1) >= 2 { verifier } else { None };
                (r.try_get("pin_hash_bcrypt").ok().flatten(), v2)
            }
        }
    };
    let stored = stored.ok_or(ApiError::Unauthorized("incorrect PIN"))?;
    let matches =
        crate::pin_verifier::verify_wallet_pin(&stored, v2.as_deref(), &req.pin_hash);
    if !matches {
        let attempts: i32 = row.try_get("failed_attempts")?;
        let attempts = attempts + 1;
        if attempts >= MAX_RELEASE_ATTEMPTS {
            let locked = Utc::now() + chrono::Duration::hours(LOCK_HOURS);
            sqlx::query(
                "update wallet_backups set failed_attempts = $2, locked_until = $3
                 where backup_id = $1",
            )
            .bind(&backup_id)
            .bind(attempts)
            .bind(locked)
            .execute(&mut *tx)
            .await?;
            tx.commit().await?;
            audit(&state, wallet_id, Some(&backup_id), "backup_locked", "throttle exhausted").await?;
            return Err(ApiError::Locked("too many attempts — try again later"));
        }
        sqlx::query(
            "update wallet_backups set failed_attempts = $2 where backup_id = $1",
        )
        .bind(&backup_id)
        .bind(attempts)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        audit(&state, wallet_id, Some(&backup_id), "release_denied", "wrong pin").await?;
        return Err(ApiError::Unauthorized("incorrect PIN"));
    }

    sqlx::query(
        "update wallet_backups set failed_attempts = 0 where backup_id = $1",
    )
    .bind(&backup_id)
    .execute(&mut *tx)
    .await?;

    // Unseal inside the oracle, after authentication — the share is never
    // readable from the database alone. Lazy re-seal on rotation keys.
    let sealed_hex: String = row.try_get("s2_sealed_hex")?;
    let sealed = hex::decode(&sealed_hex).map_err(|_| ApiError::Internal(anyhow::anyhow!("stored share is corrupt")))?;
    let (s2_bytes, rotated) = state
        .sealer
        .unseal(&sealed)
        .map_err(|_| ApiError::Internal(anyhow::anyhow!("stored share is corrupt")))?;
    if rotated {
        let resealed = state
            .sealer
            .seal(&s2_bytes)
            .map_err(|e| ApiError::Internal(anyhow::anyhow!(e.to_string())))?;
        sqlx::query("update wallet_backups set s2_sealed_hex = $2 where backup_id = $1")
            .bind(&backup_id)
            .bind(hex::encode(&resealed))
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;

    // NOTE: when the KMS backend lands (see `seal.rs`), unseal here is the
    // single call site that changes — same path, same throttle, same audit.
    audit(&state, wallet_id, Some(&backup_id), "share_released", "").await?;

    Ok(Json(ReleaseResponse { s2_hex: hex::encode(&s2_bytes) }))
}

#[derive(Serialize)]
struct RevokeResponse {
    revoked: bool,
}

/// Revokes a backup (lost print, old v1 rotation, device handover). Releases
/// after this return 410; the key itself is unaffected — pair with key
/// rotation when the v1 whole-key QR may be out in the world.
async fn revoke_backup(
    State(state): State<AppState>,
    Path(backup_id): Path<String>,
) -> ApiResult<Json<RevokeResponse>> {
    let row = sqlx::query("select wallet_id from wallet_backups where backup_id = $1")
        .bind(&backup_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(ApiError::NotFound("backup not found"))?;
    let wallet_id: Uuid = row.try_get("wallet_id")?;
    sqlx::query("update wallet_backups set revoked = true where backup_id = $1")
        .bind(&backup_id)
        .execute(&state.db)
        .await?;
    audit(&state, wallet_id, Some(&backup_id), "backup_revoked", "").await?;
    Ok(Json(RevokeResponse { revoked: true }))
}

// --- OPAQUE password-authenticated release (RFC 9807) -----------------------
// The per-backup key PIN is the OPAQUE password. The server holds a
// password *file*, never the PIN or any deterministic function of it:
// registration uploads a blinded request, login proves knowledge online.
// Every login attempt runs the same throttle/lock/audit as the legacy
// release path. Backups without a file keep the legacy path until rotated.

/// Tag prefix on stored password files — a future ciphersuite migration
/// mints a new tag and refuses old bytes, never reinterprets them.
const OPAQUE_FILE_TAG: &[u8] = b"opaque-v1:";

fn bad_request(msg: &str) -> ApiError {
    ApiError::BadRequest(msg.to_string())
}

fn check_backup_id(id: &str) -> ApiResult<()> {
    if id.trim().is_empty() || id.len() > 64 {
        return Err(bad_request("invalid backup id"));
    }
    Ok(())
}

/// Loads the backup row's throttle state under lock. Shared by login/start
/// (read-only gate) and login/finish (counting gate). Denials audit-log
/// through the pool *before* returning — the row lock releases when the
/// caller's transaction rolls back on the returned error, so no commit is
/// needed (or possible) here. Unknown ids answer 401, never 404: existence
/// and PIN-correctness stay indistinguishable. Returns `(wallet_id,
/// s2_sealed_hex, failed_attempts)`.
async fn gate_backup(
    state: &AppState,
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    backup_id: &str,
) -> ApiResult<(Uuid, String, i32)> {
    let row = sqlx::query(
        "select wallet_id, s2_sealed_hex, failed_attempts, locked_until, revoked
         from wallet_backups where backup_id = $1 for update",
    )
    .bind(backup_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or(ApiError::Unauthorized("incorrect PIN"))?;
    let wallet_id: Uuid = row.try_get("wallet_id")?;
    if row.try_get::<bool, _>("revoked")? {
        audit(state, wallet_id, Some(backup_id), "release_denied", "revoked").await?;
        return Err(ApiError::Gone("this backup was revoked"));
    }
    let locked_until: Option<DateTime<Utc>> = row.try_get("locked_until")?;
    if locked_until.map(|t| t > Utc::now()).unwrap_or(false) {
        audit(state, wallet_id, Some(backup_id), "release_denied", "locked").await?;
        return Err(ApiError::Locked("too many attempts — try again later"));
    }
    Ok((wallet_id, row.try_get("s2_sealed_hex")?, row.try_get("failed_attempts")?))
}

async fn deny_and_count(
    state: &AppState,
    backup_id: &str,
    wallet_id: Uuid,
    attempts: i32,
) -> ApiError {
    let attempts = attempts + 1;
    if attempts >= MAX_RELEASE_ATTEMPTS {
        let locked = Utc::now() + chrono::Duration::hours(LOCK_HOURS);
        let _ = sqlx::query(
            "update wallet_backups set failed_attempts = $2, locked_until = $3
             where backup_id = $1",
        )
        .bind(backup_id)
        .bind(attempts)
        .bind(locked)
        .execute(&state.db)
        .await;
        let _ = audit(state, wallet_id, Some(backup_id), "backup_locked", "throttle exhausted").await;
        return ApiError::Locked("too many attempts — try again later");
    }
    let _ = sqlx::query("update wallet_backups set failed_attempts = $2 where backup_id = $1")
        .bind(backup_id)
        .bind(attempts)
        .execute(&state.db)
        .await;
    let _ = audit(state, wallet_id, Some(backup_id), "release_denied", "opaque login failed").await;
    ApiError::Unauthorized("incorrect PIN")
}

#[derive(Deserialize)]
struct OpaqueRegisterStartRequest {
    backup_id: String,
    request_b64: String,
}

#[derive(Serialize)]
struct OpaqueRegisterStartResponse {
    response_b64: String,
}

/// OPAQUE registration step 1: blinds nothing, learns nothing — turns the
/// client's blinded request into a response. Stores no state; safe to
/// retry. Requires the wallet to exist so random wallets cannot be
/// probed for password files.
async fn opaque_register_start(
    State(state): State<AppState>,
    Path(wallet_id): Path<Uuid>,
    Json(req): Json<OpaqueRegisterStartRequest>,
) -> ApiResult<Json<OpaqueRegisterStartResponse>> {
    check_backup_id(&req.backup_id)?;
    sqlx::query("select id from wallets where id = $1")
        .bind(wallet_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(ApiError::NotFound("no wallet with that id"))?;

    let setup = state.opaque_setup().await.map_err(ApiError::Internal)?;
    let request_bytes =
        b64_decode(&req.request_b64).map_err(|_| bad_request("invalid request"))?;
    let request = RegistrationRequest::<JamiipayCs>::deserialize(&request_bytes)
        .map_err(|_| bad_request("invalid request"))?;
    let result = opaque_ke::ServerRegistration::<JamiipayCs>::start(
        &setup,
        request,
        req.backup_id.as_bytes(),
    )
    .map_err(|_| bad_request("invalid request"))?;
    Ok(Json(OpaqueRegisterStartResponse {
        response_b64: b64_encode(&result.message.serialize().to_vec()),
    }))
}

#[derive(Deserialize)]
struct OpaqueRegisterFinishRequest {
    backup_id: String,
    upload_b64: String,
}

/// OPAQUE registration step 2: stores the password file. Upserts the
/// backup row (registration runs before `store_backup` at export) with the
/// same cross-wallet conflict rule — a file for another wallet's id is
/// rejected, never overwritten.
async fn opaque_register_finish(
    State(state): State<AppState>,
    Path(wallet_id): Path<Uuid>,
    Json(req): Json<OpaqueRegisterFinishRequest>,
) -> ApiResult<Json<StoreBackupResponse>> {
    check_backup_id(&req.backup_id)?;
    sqlx::query("select id from wallets where id = $1")
        .bind(wallet_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(ApiError::NotFound("no wallet with that id"))?;

    let upload_bytes =
        b64_decode(&req.upload_b64).map_err(|_| bad_request("invalid upload"))?;
    let upload = RegistrationUpload::<JamiipayCs>::deserialize(&upload_bytes)
        .map_err(|_| bad_request("invalid upload"))?;
    let file = opaque_ke::ServerRegistration::<JamiipayCs>::finish(upload);
    let mut stored = OPAQUE_FILE_TAG.to_vec();
    stored.extend_from_slice(&file.serialize().to_vec());

    if let Some(owner) = sqlx::query_scalar::<_, Uuid>(
        "select wallet_id from wallet_backups where backup_id = $1",
    )
    .bind(&req.backup_id)
    .fetch_optional(&state.db)
    .await?
    {
        if owner != wallet_id {
            return Err(ApiError::Conflict(
                "backup id already registered to another wallet",
            ));
        }
    }
    sqlx::query(
        "insert into wallet_backups (backup_id, wallet_id, s2_sealed_hex, opaque_file, version)
         values ($1, $2, '', $3, 2)
         on conflict (backup_id) do update set opaque_file = excluded.opaque_file, version = 2",
    )
    .bind(&req.backup_id)
    .bind(wallet_id)
    .bind(&stored)
    .execute(&state.db)
    .await?;

    Ok(Json(StoreBackupResponse { backup_id: req.backup_id, version: 2 }))
}

#[derive(Deserialize)]
struct OpaqueLoginStartRequest {
    request_b64: String,
}

#[derive(Serialize)]
struct OpaqueLoginStartResponse {
    login_id: String,
    response_b64: String,
}

/// OPAQUE login step 1: gates on revoked/locked state, then opens a
/// pending login (10-minute TTL, in memory only). Backups without a
/// password file get 404 so the app falls back to the legacy release path.
/// Attempt counting happens at finish, not here — start is blinded and
/// reveals nothing guessable.
async fn opaque_login_start(
    State(state): State<AppState>,
    Path(backup_id): Path<String>,
    Json(req): Json<OpaqueLoginStartRequest>,
) -> ApiResult<Json<OpaqueLoginStartResponse>> {
    let mut tx = state.db.begin().await?;
    gate_backup(&state, &mut tx, &backup_id).await?;
    let file_row = sqlx::query("select opaque_file from wallet_backups where backup_id = $1")
        .bind(&backup_id)
        .fetch_one(&mut *tx)
        .await?;
    tx.commit().await?;

    let file_bytes: Option<Vec<u8>> = file_row.try_get("opaque_file")?;
    let file_bytes = file_bytes.filter(|b| !b.is_empty()).ok_or(ApiError::NotFound(
        "backup has no OPAQUE file",
    ))?;
    let file = deserialize_file(&file_bytes)?;

    let setup = state.opaque_setup().await.map_err(ApiError::Internal)?;
    let request_bytes =
        b64_decode(&req.request_b64).map_err(|_| bad_request("invalid request"))?;
    let request = CredentialRequest::<JamiipayCs>::deserialize(&request_bytes)
        .map_err(|_| bad_request("invalid request"))?;
    let mut rng = OsRng;
    let result = ServerLogin::<JamiipayCs>::start(
        &mut rng,
        &setup,
        Some(file),
        request,
        backup_id.as_bytes(),
        ServerLoginParameters::default(),
    )
    .map_err(|_| bad_request("invalid request"))?;
    let login_id = state.opaque_login_insert(result.state);
    Ok(Json(OpaqueLoginStartResponse {
        login_id: login_id.to_string(),
        response_b64: b64_encode(&result.message.serialize().to_vec()),
    }))
}

fn deserialize_file(
    bytes: &[u8],
) -> ApiResult<opaque_ke::ServerRegistration<JamiipayCs>> {
    if !bytes.starts_with(OPAQUE_FILE_TAG) {
        return Err(ApiError::Internal(anyhow::anyhow!(
            "stored password file has unknown version"
        )));
    }
    opaque_ke::ServerRegistration::<JamiipayCs>::deserialize(&bytes[OPAQUE_FILE_TAG.len()..])
        .map_err(|_| ApiError::Internal(anyhow::anyhow!("stored password file is corrupt")))
}

#[derive(Deserialize)]
struct OpaqueLoginFinishRequest {
    login_id: String,
    finalization_b64: String,
}

/// OPAQUE login step 2: verifies the client's finalization. Success
/// releases + unseals `S2` (same lazy re-seal as the legacy path) and
/// resets the throttle; failure counts exactly like a wrong PIN. Errors
/// stay generic (401) — login success and failure are indistinguishable
/// to anyone without the PIN.
async fn opaque_login_finish(
    State(state): State<AppState>,
    Path(backup_id): Path<String>,
    Json(req): Json<OpaqueLoginFinishRequest>,
) -> ApiResult<Json<ReleaseResponse>> {
    let login_id =
        Uuid::parse_str(&req.login_id).map_err(|_| bad_request("invalid login"))?;
    let pending = state
        .opaque_login_take(&login_id)
        .ok_or(ApiError::Unauthorized("incorrect PIN"))?;    let final_bytes = b64_decode(&req.finalization_b64)
        .map_err(|_| ApiError::Unauthorized("incorrect PIN"))?;
    let finalization = CredentialFinalization::<JamiipayCs>::deserialize(&final_bytes)
        .map_err(|_| ApiError::Unauthorized("incorrect PIN"))?;

    let mut tx = state.db.begin().await?;
    let (wallet_id, _, attempts) = match gate_backup(&state, &mut tx, &backup_id).await {
        Ok(v) => v,
        Err(e) => return Err(e),
    };

    if pending
        .finish(finalization, ServerLoginParameters::default())
        .is_err()
    {
        tx.commit().await?;
        return Err(deny_and_count(&state, &backup_id, wallet_id, attempts).await);
    }

    let row = sqlx::query("select s2_sealed_hex from wallet_backups where backup_id = $1")
        .bind(&backup_id)
        .fetch_one(&mut *tx)
        .await?;
    let sealed_hex: String = row.try_get("s2_sealed_hex")?;
    if sealed_hex.is_empty() {
        tx.commit().await?;
        return Err(ApiError::Conflict("backup incomplete — re-export"));
    }
    let sealed = hex::decode(&sealed_hex).map_err(|_| ApiError::Internal(anyhow::anyhow!("stored share is corrupt")))?;
    let (s2_bytes, rotated) = state
        .sealer
        .unseal(&sealed)
        .map_err(|_| ApiError::Internal(anyhow::anyhow!("stored share is corrupt")))?;
    sqlx::query("update wallet_backups set failed_attempts = 0 where backup_id = $1")
        .bind(&backup_id)
        .execute(&mut *tx)
        .await?;
    if rotated {
        let resealed = state
            .sealer
            .seal(&s2_bytes)
            .map_err(|e| ApiError::Internal(anyhow::anyhow!(e.to_string())))?;
        sqlx::query("update wallet_backups set s2_sealed_hex = $2 where backup_id = $1")
            .bind(&backup_id)
            .bind(hex::encode(&resealed))
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    audit(&state, wallet_id, Some(&backup_id), "share_released", OPAQUE_VERSION_TAG).await?;

    Ok(Json(ReleaseResponse { s2_hex: hex::encode(&s2_bytes) }))
}

async fn audit(
    state: &AppState,
    wallet_id: Uuid,
    backup_id: Option<&str>,
    action: &str,
    detail: &str,
) -> Result<(), ApiError> {
    sqlx::query(
        "insert into security_audit (wallet_id, backup_id, action, detail)
         values ($1, $2, $3, $4)",
    )
    .bind(wallet_id)
    .bind(backup_id)
    .bind(action)
    .bind(detail)
    .execute(&state.db)
    .await?;
    Ok(())
}
