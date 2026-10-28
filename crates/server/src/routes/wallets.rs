use axum::{
    extract::{Path, State},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::handle::{compute_check_digit, is_valid_base};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/wallets", post(create_wallet))
        .route("/wallets/:id", get(get_wallet))
        .route("/wallets/:id/transactions", get(list_transactions))
        .route("/wallets/:id/transfers", post(create_transfer))
        .route("/wallets/:id/savings/move", post(move_to_savings))
        .route("/wallets/:id/savings/withdraw", post(withdraw_from_savings))
        .route("/wallets/:id/rotate-key", post(rotate_key))
        .route("/wallets/verify-pin", post(verify_pin))
}

#[derive(Deserialize)]
struct CreateWalletRequest {
    /// The EVM address of the smart account, generated client-side by
    /// wallet-core (via flutter_rust_bridge) — the server never sees a
    /// private key.
    evm_address: String,
    handle_base: String,
    /// Guardian types chosen on the onboarding Guardians screen — at least
    /// three, matching "Confirm these three".
    guardians: Vec<String>,
    /// The client's local sha256(pin) (see `security/pin_hash.dart`) — the
    /// server never sees the raw PIN. Rehashed with bcrypt before storage;
    /// see `verify_pin` and the column's migration for why.
    pin_hash: String,
    /// Hardware-bound DeviceVault public key of the creating device, if the
    /// app has one (see `security/device_vault.dart`). Opaque to the
    /// server — future release policy reads it; nothing here trusts it for
    /// authentication today.
    #[serde(default)]
    device_key_pub: Option<String>,
    /// Whether that key is actually hardware-backed (false on simulators /
    /// vault-less builds — reported loudly, never assumed).
    #[serde(default)]
    device_enclave: bool,
}

#[derive(Serialize)]
struct WalletResponse {
    id: Uuid,
    evm_address: String,
    full_handle: String,
    everyday_balance_usd_cents: i64,
    savings_balance_usd_cents: i64,
    guardians: Vec<String>,
}

const VALID_GUARDIAN_TYPES: &[&str] =
    &["device", "printed_code", "institutional", "trusted_person"];

async fn create_wallet(
    State(state): State<AppState>,
    Json(req): Json<CreateWalletRequest>,
) -> ApiResult<Json<WalletResponse>> {
    let base = req.handle_base.trim().to_lowercase();
    if !is_valid_base(&base) {
        return Err(ApiError::BadRequest(
            "handle must be 3-20 lowercase letters/digits".to_string(),
        ));
    }
    if req.guardians.len() < 3 {
        return Err(ApiError::BadRequest(
            "at least three guardians are required".to_string(),
        ));
    }
    for g in &req.guardians {
        if !VALID_GUARDIAN_TYPES.contains(&g.as_str()) {
            return Err(ApiError::BadRequest(format!("unknown guardian type: {g}")));
        }
    }

    let check_digit = compute_check_digit(&base);
    let full_handle = format!("{base}{check_digit}");

    let pin_hash_bcrypt = bcrypt::hash(&req.pin_hash, bcrypt::DEFAULT_COST)
        .map_err(|_| ApiError::BadRequest("could not process pin".to_string()))?;

    let mut tx = state.db.begin().await?;

    let wallet_id: Uuid = sqlx::query_scalar(
        "insert into wallets (owner_user_id, evm_address, pin_hash_bcrypt, device_key_pub, device_enclave) values ($1, $2, $3, $4, $5) returning id",
    )
    // `owner_user_id` is a placeholder until real auth/user records exist —
    // tracked as a self-referencing UUID for now rather than a fake FK.
    .bind(Uuid::new_v4())
    .bind(&req.evm_address)
    .bind(&pin_hash_bcrypt)
    .bind(req.device_key_pub.as_deref().filter(|s| !s.trim().is_empty() && s.len() <= 512))
    .bind(req.device_enclave)
    .fetch_one(&mut *tx)
    .await
    .map_err(|err| match err {
        sqlx::Error::Database(db_err) if db_err.is_unique_violation() => {
            ApiError::Conflict("that address already has a wallet")
        }
        other => other.into(),
    })?;

    sqlx::query("insert into handles (wallet_id, base, check_digit) values ($1, $2, $3)")
        .bind(wallet_id)
        .bind(&base)
        .bind(check_digit.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|err| match err {
            sqlx::Error::Database(db_err) if db_err.is_unique_violation() => {
                ApiError::Conflict("that payment name was just taken")
            }
            other => other.into(),
        })?;

    for guardian_type in &req.guardians {
        sqlx::query("insert into guardians (wallet_id, guardian_type) values ($1, $2)")
            .bind(wallet_id)
            .bind(guardian_type)
            .execute(&mut *tx)
            .await?;
    }

    super::alerts::seed_defaults(&mut tx, wallet_id).await?;

    tx.commit().await?;

    Ok(Json(WalletResponse {
        id: wallet_id,
        evm_address: req.evm_address,
        full_handle,
        everyday_balance_usd_cents: 0,
        savings_balance_usd_cents: 0,
        guardians: req.guardians,
    }))
}

async fn get_wallet(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<WalletResponse>> {
    let row = sqlx::query(
        "select w.evm_address, w.everyday_balance_cents, w.savings_balance_cents, h.full_handle
         from wallets w left join handles h on h.wallet_id = w.id
         where w.id = $1",
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(ApiError::NotFound("wallet not found"))?;

    let guardians: Vec<String> =
        sqlx::query_scalar("select guardian_type from guardians where wallet_id = $1")
            .bind(id)
            .fetch_all(&state.db)
            .await?;

    Ok(Json(WalletResponse {
        id,
        evm_address: row.try_get("evm_address")?,
        full_handle: row
            .try_get::<Option<String>, _>("full_handle")?
            .unwrap_or_default(),
        everyday_balance_usd_cents: row.try_get("everyday_balance_cents")?,
        savings_balance_usd_cents: row.try_get("savings_balance_cents")?,
        guardians,
    }))
}

#[derive(Deserialize)]
struct RotateKeyRequest {
    /// Freshly generated address for the new device key. Authenticated by
    /// `pin_hash` (the wallet unlock PIN), not by the old key — rotation
    /// is for the case where the old key may be compromised, so a
    /// signature from it proves nothing.
    new_evm_address: String,
    /// The client's local wallet-PIN hash (same value `verify-pin`
    /// checks).
    pin_hash: String,
    #[serde(default)]
    device_key_pub: Option<String>,
    #[serde(default)]
    device_enclave: bool,
}

/// Rotates a wallet's device key: replaces `evm_address`, refreshes the
/// device-binding columns, and revokes every backup ever escrowed for the
/// wallet — v1 whole-key QRs printed before the split upgrade included.
/// That last part is the point: rotation is the only true fix for a v1 QR
/// in the wild, because no software can un-print paper.
///
/// Balances, handles, guardians, and recovery history are untouched — only
/// the key and its backups change. On-chain, the caller must separately
/// point the smart account's owner at the new address (RecoveryModule or a
/// fresh owner update); this endpoint rotates the off-chain record and
/// kills the old backups.
async fn rotate_key(
    State(state): State<AppState>,
    Path(wallet_id): Path<Uuid>,
    Json(req): Json<RotateKeyRequest>,
) -> ApiResult<Json<WalletResponse>> {
    let new_address = req.new_evm_address.trim().to_lowercase();
    if new_address.len() != 42
        || !new_address.starts_with("0x")
        || hex::decode(&new_address[2..]).is_err()
    {
        return Err(ApiError::BadRequest("invalid new address".to_string()));
    }

    let mut tx = state.db.begin().await?;
    let row = sqlx::query(
        "select evm_address, pin_hash_bcrypt, pin_version, pin_verifier
         from wallets where id = $1 for update",
    )
    .bind(wallet_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(ApiError::NotFound("wallet not found"))?;

    let old_address: String = row.try_get("evm_address")?;
    if old_address.to_lowercase() == new_address {
        return Err(ApiError::BadRequest("new address matches the current one".to_string()));
    }
    let stored: Option<String> = row.try_get("pin_hash_bcrypt")?;
    let stored = stored
        .ok_or(ApiError::BadRequest("this wallet has no PIN on file to verify against".to_string()))?;
    let version: Option<i32> = row.try_get("pin_version").ok().flatten();
    let verifier: Option<String> = row.try_get("pin_verifier").ok().flatten();
    let v2 = if version.unwrap_or(1) >= 2 { verifier.as_deref() } else { None };
    if !crate::pin_verifier::verify_wallet_pin(&stored, v2, &req.pin_hash) {
        return Err(ApiError::Unauthorized("incorrect PIN"));
    }

    let taken: bool = sqlx::query_scalar("select exists(select 1 from wallets where evm_address = $1)")
        .bind(&new_address)
        .fetch_one(&mut *tx)
        .await?;
    if taken {
        return Err(ApiError::Conflict("that address already has a wallet"));
    }

    let updated: i64 = sqlx::query_scalar(
        "update wallets set evm_address = $2, device_key_pub = $3, device_enclave = $4
         where id = $1 returning 1",
    )
    .bind(wallet_id)
    .bind(&new_address)
    .bind(req.device_key_pub.as_deref().filter(|s| !s.trim().is_empty() && s.len() <= 512))
    .bind(req.device_enclave)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(ApiError::NotFound("wallet not found"))?;
    let _ = updated;

    // Every escrowed share dies with the old key — including v1-era rows.
    sqlx::query("update wallet_backups set revoked = true where wallet_id = $1")
        .bind(wallet_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    sqlx::query(
        "insert into security_audit (wallet_id, backup_id, action, detail)
         values ($1, null, 'key_rotated', $2)",
    )
    .bind(wallet_id)
    .bind(format!("evm {} -> {}", &old_address[..10.min(old_address.len())], &new_address[..10.min(new_address.len())]))
    .execute(&state.db)
    .await?;

    get_wallet(State(state), Path(wallet_id)).await
}

/// Flat fee, matching the copy shown throughout the app (Send screen's fee
/// breakdown, Ask Jamii's "$0.04 flat" comparison) — not a percentage, not
/// computed from anything, because the design never specifies a formula.
const FLAT_FEE_USD_CENTS: i64 = 4;

#[derive(Deserialize)]
struct CreateTransferRequest {
    /// The recipient's full payment name (base + check digit), e.g.
    /// `yusufo22c` — looked up the same way `GET /handles/availability`
    /// and recovery's `full_handle` lookup do.
    recipient_full_handle: String,
    amount_usd_cents: i64,
    /// Client-generated UUID per review-sheet confirmation. Same key +
    /// same sender returns the original result instead of double-sending
    /// (double-tap, retry after timeout). See migration
    /// `20260208000000_idempotency.sql`.
    idempotency_key: Option<String>,
}

#[derive(Serialize)]
struct TransferResponse {
    transaction_id: Uuid,
    fee_usd_cents: i64,
    sender_everyday_balance_usd_cents: i64,
}

/// The Send screen's real backend — previously nothing in `crates/server`
/// could move money between two wallets at all, so "Send" always ended in
/// a "coming soon" snackbar no matter what the user typed. Everyday
/// balance only (matches the design: savings requires the guardian
/// threshold, not a plain send).
async fn create_transfer(
    State(state): State<AppState>,
    Path(sender_id): Path<Uuid>,
    Json(req): Json<CreateTransferRequest>,
) -> ApiResult<Json<TransferResponse>> {
    if req.amount_usd_cents <= 0 {
        return Err(ApiError::BadRequest("amount must be positive".to_string()));
    }

    // Idempotency: same key returns the original result without re-debiting.
    if let Some(key) = req.idempotency_key.as_ref().filter(|k| !k.trim().is_empty()) {
        if let Some(row) = sqlx::query(
            "select id from transactions where wallet_id = $1 and idempotency_key = $2 and kind = 'transfer' and direction = 'out'",
        )
        .bind(sender_id)
        .bind(key)
        .fetch_optional(&state.db)
        .await?
        {
            let transaction_id: Uuid = row.try_get("id")?;
            let balance: i64 = sqlx::query_scalar(
                "select everyday_balance_cents from wallets where id = $1",
            )
            .bind(sender_id)
            .fetch_optional(&state.db)
            .await?
            .ok_or(ApiError::NotFound("wallet not found"))?;
            return Ok(Json(TransferResponse {
                transaction_id,
                fee_usd_cents: FLAT_FEE_USD_CENTS,
                sender_everyday_balance_usd_cents: balance,
            }));
        }
    }

    let recipient_handle = req.recipient_full_handle.trim().to_lowercase();
    let total_debit = req.amount_usd_cents + FLAT_FEE_USD_CENTS;

    let mut tx = state.db.begin().await?;

    let (recipient_wallet_id, sender_full_handle): (Uuid, Option<String>) = sqlx::query_as(
        "select h.wallet_id, (select full_handle from handles where wallet_id = $2) as sender_handle
         from handles h where h.full_handle = $1",
    )
    .bind(&recipient_handle)
    .bind(sender_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(ApiError::NotFound("no wallet with that payment name"))?;
    let sender_full_handle =
        sender_full_handle.ok_or(ApiError::NotFound("sender wallet not found"))?;

    if recipient_wallet_id == sender_id {
        return Err(ApiError::BadRequest("can't send to your own wallet".to_string()));
    }

    let sender_balance: i64 = sqlx::query_scalar(
        "select everyday_balance_cents from wallets where id = $1 for update",
    )
    .bind(sender_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(ApiError::NotFound("wallet not found"))?;

    if sender_balance < total_debit {
        return Err(ApiError::BadRequest(
            "insufficient everyday balance for amount + fee".to_string(),
        ));
    }

    let new_sender_balance: i64 = sqlx::query_scalar(
        "update wallets set everyday_balance_cents = everyday_balance_cents - $2
         where id = $1 returning everyday_balance_cents",
    )
    .bind(sender_id)
    .bind(total_debit)
    .fetch_one(&mut *tx)
    .await?;

    sqlx::query("update wallets set everyday_balance_cents = everyday_balance_cents + $2 where id = $1")
        .bind(recipient_wallet_id)
        .bind(req.amount_usd_cents)
        .execute(&mut *tx)
        .await?;

    let transaction_id: Uuid = sqlx::query_scalar(
        "insert into transactions (wallet_id, direction, counterparty_name, amount_usd_cents, kind, status, idempotency_key)
         values ($1, 'out', $2, $3, 'transfer', 'settled', $4) returning id",
    )
    .bind(sender_id)
    .bind(&recipient_handle)
    .bind(total_debit)
    .bind(req.idempotency_key.as_ref().filter(|k| !k.trim().is_empty()))
    .fetch_one(&mut *tx)
    .await?;

    sqlx::query(
        "insert into transactions (wallet_id, direction, counterparty_name, amount_usd_cents, kind, status)
         values ($1, 'in', $2, $3, 'transfer', 'settled')",
    )
    .bind(recipient_wallet_id)
    .bind(&sender_full_handle)
    .bind(req.amount_usd_cents)
    .execute(&mut *tx)
    .await?;

    // Dual-write: the ledger explains every balance delta, same tx.
    crate::ledger::record(
        &mut tx,
        sender_id,
        "out",
        total_debit,
        "transfer",
        req.idempotency_key.as_deref().filter(|k| !k.trim().is_empty()),
        Some(transaction_id),
    )
    .await?;
    crate::ledger::record(
        &mut tx,
        recipient_wallet_id,
        "in",
        req.amount_usd_cents,
        "transfer",
        None,
        None,
    )
    .await?;

    tx.commit().await?;

    // Both sides see it live — the whole point of a transfer being
    // instant is that neither party should have to pull-to-refresh to
    // find out it landed.
    state.notify_balance_change(sender_id).await;
    state.notify_balance_change(recipient_wallet_id).await;

    // Remote push to the recipient only — the sender is staring at the
    // confirmation screen; buzzing them too would be noise. Best-effort:
    // never fails the transfer.
    state
        .push
        .notify_wallet(
            &state.db,
            recipient_wallet_id,
            "Money received",
            "A payment just arrived — open JamiiPay to see it.",
            "balance",
        )
        .await;

    Ok(Json(TransferResponse {
        transaction_id,
        fee_usd_cents: FLAT_FEE_USD_CENTS,
        sender_everyday_balance_usd_cents: new_sender_balance,
    }))
}

#[derive(Deserialize)]
struct SavingsTransferRequest {
    amount_usd_cents: i64,
}

#[derive(Serialize)]
struct SavingsTransferResponse {
    everyday_balance_usd_cents: i64,
    savings_balance_usd_cents: i64,
}

/// Moving money between a wallet's own two balances — unlike a transfer
/// or a group withdrawal, there's no counterparty and no vote: it's
/// already the owner's money, so a straight, instant debit/credit is the
/// right level of ceremony (guardians exist for account *recovery*, not
/// routine savings access).
async fn move_to_savings(
    State(state): State<AppState>,
    Path(wallet_id): Path<Uuid>,
    Json(req): Json<SavingsTransferRequest>,
) -> ApiResult<Json<SavingsTransferResponse>> {
    // 'out' of the spendable everyday pool — same framing as any other
    // spend in the Activity feed.
    savings_transfer(
        &state,
        wallet_id,
        req.amount_usd_cents,
        "everyday_balance_cents",
        "savings_balance_cents",
        "savings_move",
        "out",
        "To savings",
    )
    .await
}

async fn withdraw_from_savings(
    State(state): State<AppState>,
    Path(wallet_id): Path<Uuid>,
    Json(req): Json<SavingsTransferRequest>,
) -> ApiResult<Json<SavingsTransferResponse>> {
    // 'in' to the spendable everyday pool.
    savings_transfer(
        &state,
        wallet_id,
        req.amount_usd_cents,
        "savings_balance_cents",
        "everyday_balance_cents",
        "savings_withdraw",
        "in",
        "From savings",
    )
    .await
}

/// Shared by both directions — `from_column`/`to_column` are trusted
/// constants supplied by the two callers above, never user input, so
/// interpolating them into the query text is safe.
#[allow(clippy::too_many_arguments)]
async fn savings_transfer(
    state: &AppState,
    wallet_id: Uuid,
    amount_usd_cents: i64,
    from_column: &str,
    to_column: &str,
    kind: &str,
    direction: &str,
    counterparty_name: &str,
) -> ApiResult<Json<SavingsTransferResponse>> {
    if amount_usd_cents <= 0 {
        return Err(ApiError::BadRequest("amount must be positive".to_string()));
    }

    let mut tx = state.db.begin().await?;

    let from_balance: i64 = sqlx::query_scalar(&format!("select {from_column} from wallets where id = $1 for update"))
        .bind(wallet_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or(ApiError::NotFound("wallet not found"))?;
    if from_balance < amount_usd_cents {
        return Err(ApiError::BadRequest("insufficient balance".to_string()));
    }

    sqlx::query(&format!("update wallets set {from_column} = {from_column} - $2 where id = $1"))
        .bind(wallet_id)
        .bind(amount_usd_cents)
        .execute(&mut *tx)
        .await?;
    sqlx::query(&format!("update wallets set {to_column} = {to_column} + $2 where id = $1"))
        .bind(wallet_id)
        .bind(amount_usd_cents)
        .execute(&mut *tx)
        .await?;

    sqlx::query(
        "insert into transactions (wallet_id, direction, counterparty_name, amount_usd_cents, kind, status)
         values ($1, $2, $3, $4, $5, 'settled')",
    )
    .bind(wallet_id)
    .bind(direction)
    .bind(counterparty_name)
    .bind(amount_usd_cents)
    .bind(kind)
    .execute(&mut *tx)
    .await?;

    // Internal move: balanced out+in legs under the same kind — net zero,
    // both sides auditable.
    crate::ledger::record(&mut tx, wallet_id, "out", amount_usd_cents, kind, None, None).await?;
    crate::ledger::record(&mut tx, wallet_id, "in", amount_usd_cents, kind, None, None).await?;

    let (everyday_balance_usd_cents, savings_balance_usd_cents): (i64, i64) =
        sqlx::query_as("select everyday_balance_cents, savings_balance_cents from wallets where id = $1")
            .bind(wallet_id)
            .fetch_one(&mut *tx)
            .await?;

    tx.commit().await?;
    state.notify_balance_change(wallet_id).await;

    Ok(Json(SavingsTransferResponse { everyday_balance_usd_cents, savings_balance_usd_cents }))
}

#[derive(Serialize)]
struct TransactionResponse {
    id: Uuid,
    direction: String,
    counterparty_name: String,
    amount_usd_cents: i64,
    amount_local_minor: Option<i64>,
    local_currency: Option<String>,
    fx_rate: Option<String>,
    kind: String,
    status: String,
    created_at: chrono::DateTime<chrono::Utc>,
}

async fn list_transactions(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<TransactionResponse>>> {
    let rows = sqlx::query_as::<
        _,
        (
            Uuid,
            String,
            String,
            i64,
            Option<i64>,
            Option<String>,
            Option<String>,
            String,
            String,
            chrono::DateTime<chrono::Utc>,
        ),
    >(
        "select id, direction, counterparty_name, amount_usd_cents, amount_local_minor,
                local_currency, fx_rate::text, kind, status, created_at
         from transactions where wallet_id = $1 order by created_at desc limit 100",
    )
    .bind(id)
    .fetch_all(&state.db)
    .await?;

    Ok(Json(
        rows.into_iter()
            .map(
                |(
                    id,
                    direction,
                    counterparty_name,
                    amount_usd_cents,
                    amount_local_minor,
                    local_currency,
                    fx_rate,
                    kind,
                    status,
                    created_at,
                )| {
                    TransactionResponse {
                        id,
                        direction,
                        counterparty_name,
                        amount_usd_cents,
                        amount_local_minor,
                        local_currency,
                        fx_rate,
                        kind,
                        status,
                        created_at,
                    }
                },
            )
            .collect(),
    ))
}

#[derive(Deserialize)]
struct VerifyPinRequest {
    evm_address: String,
    /// The client's local sha256(pin) — see `CreateWalletRequest::pin_hash`.
    pin_hash: String,
}

#[derive(Serialize)]
struct VerifyPinResponse {
    id: Uuid,
    full_handle: String,
}

/// The second factor in "restore from wallet key": a device that has just
/// decrypted a wallet's exported private key locally still has to prove
/// it's the wallet's actual owner (not just whoever obtained the QR code
/// and its encryption PIN) before the app treats it as a real session.
/// Looked up by `evm_address` — re-derived client-side from the decrypted
/// key — rather than by handle, so this never needs the handle typed in.
async fn verify_pin(
    State(state): State<AppState>,
    Json(req): Json<VerifyPinRequest>,
) -> ApiResult<Json<VerifyPinResponse>> {
    let row = sqlx::query(
        "select w.id, w.pin_hash_bcrypt, w.pin_version, w.pin_verifier, h.full_handle
         from wallets w left join handles h on h.wallet_id = w.id
         where w.evm_address = $1",
    )
    .bind(&req.evm_address)
    .fetch_optional(&state.db)
    .await?
    .ok_or(ApiError::NotFound("no wallet with that address"))?;

    let stored_hash: Option<String> = row.try_get("pin_hash_bcrypt")?;
    let stored_hash = stored_hash.ok_or(ApiError::BadRequest(
        "this wallet has no PIN on file to verify against".to_string(),
    ))?;

    // Dual-verifier (v1 bcrypt today, OPAQUE v2 when migrated) — see
    // `pin_verifier.rs`. One function, shared with the backup oracle.
    let pin_version: Option<i32> = row.try_get("pin_version").ok().flatten();
    let pin_verifier: Option<String> = row.try_get("pin_verifier").ok().flatten();
    let v2 = if pin_version.unwrap_or(1) >= 2 { pin_verifier.as_deref() } else { None };
    if !crate::pin_verifier::verify_wallet_pin(&stored_hash, v2, &req.pin_hash) {
        return Err(ApiError::Unauthorized("incorrect PIN"));
    }

    Ok(Json(VerifyPinResponse {
        id: row.try_get("id")?,
        full_handle: row
            .try_get::<Option<String>, _>("full_handle")?
            .unwrap_or_default(),
    }))
}
