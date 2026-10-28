//! Receiving money via M-Pesa STK Push — prompts the payer's phone from
//! this app, they enter their M-Pesa PIN, and once Safaricom confirms it
//! (asynchronously, via `stk_callback`) the wallet's everyday balance is
//! credited in USD at the same fixed rate `routes/cash_out.rs` uses for
//! the reverse direction. See `crate::daraja`'s doc comment for the two
//! things that have to be configured before this can do anything real:
//! actual Daraja credentials, and a publicly reachable callback URL.

use axum::{
    extract::{Path, State},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::daraja::{self, DarajaConfig};
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

/// Same mock rate `cash_out.rs` uses — see that module's doc comment for
/// why this is a constant rather than a live FX fetch.
const USD_KES_RATE: f64 = 129.25;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/wallets/:id/mpesa/stk-push", post(initiate_stk_push))
        .route("/wallets/:id/mpesa/deposits/:checkout_request_id", get(get_deposit_status))
        .route("/mpesa/callback", post(stk_callback))
}

#[derive(Deserialize)]
struct StkPushRequest {
    /// `2547XXXXXXXX` or `07XXXXXXXX`/`+254...` — normalized below.
    phone: String,
    amount_usd_cents: i64,
    /// Client-generated UUID per review confirmation — same key returns
    /// the original checkout instead of double-pushing.
    idempotency_key: Option<String>,
}

#[derive(Serialize)]
struct StkPushResponse {
    checkout_request_id: String,
    amount_kes: f64,
}

/// Kenyan phone numbers arrive in several shapes from the UI
/// (`0712345678`, `+254712345678`, `254712345678`) — Daraja only accepts
/// the last of those.
fn normalize_phone(raw: &str) -> Result<String, ApiError> {
    let digits: String = raw.chars().filter(|c| c.is_ascii_digit()).collect();
    let normalized = if let Some(rest) = digits.strip_prefix("254") {
        format!("254{rest}")
    } else if let Some(rest) = digits.strip_prefix('0') {
        format!("254{rest}")
    } else {
        digits
    };
    if normalized.len() != 12 || !normalized.starts_with("254") {
        return Err(ApiError::BadRequest("not a valid Kenyan phone number".to_string()));
    }
    Ok(normalized)
}

async fn initiate_stk_push(
    State(state): State<AppState>,
    Path(wallet_id): Path<Uuid>,
    Json(req): Json<StkPushRequest>,
) -> ApiResult<Json<StkPushResponse>> {
    if req.amount_usd_cents <= 0 {
        return Err(ApiError::BadRequest("amount must be positive".to_string()));
    }
    let config = DarajaConfig::from_env().ok_or(ApiError::BadRequest(
        "M-Pesa isn't configured on this server yet — DARAJA_* env vars are missing. See crates/server/src/daraja.rs.".to_string(),
    ))?;
    let phone = normalize_phone(&req.phone)?;

    // Idempotency: return the in-flight/completed checkout for this key.
    if let Some(key) = req.idempotency_key.as_ref().filter(|k| !k.trim().is_empty()) {
        if let Some(row) = sqlx::query(
            "select checkout_request_id, amount_kes_minor from mpesa_deposits where wallet_id = $1 and idempotency_key = $2",
        )
        .bind(wallet_id)
        .bind(key)
        .fetch_optional(&state.db)
        .await?
        {
            let checkout_request_id: String = row.try_get("checkout_request_id")?;
            let amount_kes_minor: i64 = row.try_get("amount_kes_minor")?;
            return Ok(Json(StkPushResponse {
                checkout_request_id,
                amount_kes: amount_kes_minor as f64 / 100.0,
            }));
        }
    }

    // Daraja only accepts whole-shilling amounts.
    let amount_kes = ((req.amount_usd_cents as f64 / 100.0) * USD_KES_RATE).round() as i64;
    if amount_kes < 1 {
        return Err(ApiError::BadRequest("amount too small to convert to a whole shilling".to_string()));
    }

    let handle: Option<String> = sqlx::query_scalar("select full_handle from handles where wallet_id = $1")
        .bind(wallet_id)
        .fetch_optional(&state.db)
        .await?;
    let account_reference = handle.unwrap_or_else(|| "JamiiPay".to_string());

    let result = daraja::stk_push(&config, &phone, amount_kes, &account_reference)
        .await
        .map_err(|e| ApiError::BadRequest(format!("Could not start the M-Pesa prompt: {e}")))?;

    sqlx::query(
        "insert into mpesa_deposits (wallet_id, checkout_request_id, merchant_request_id, phone, amount_kes_minor, amount_usd_cents, idempotency_key)
         values ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(wallet_id)
    .bind(&result.checkout_request_id)
    .bind(&result.merchant_request_id)
    .bind(&phone)
    .bind(amount_kes * 100)
    .bind(req.amount_usd_cents)
    .bind(req.idempotency_key.as_ref().filter(|k| !k.trim().is_empty()))
    .execute(&state.db)
    .await?;

    Ok(Json(StkPushResponse { checkout_request_id: result.checkout_request_id, amount_kes: amount_kes as f64 }))
}

#[derive(Serialize)]
struct DepositStatusResponse {
    status: String, // pending | completed | failed
    result_desc: Option<String>,
    everyday_balance_usd_cents: Option<i64>,
}

/// The client polls this after `initiate_stk_push` — STK Push is
/// asynchronous (the person has to actually enter their PIN on their
/// phone), so there's nothing else to wait on synchronously.
async fn get_deposit_status(
    State(state): State<AppState>,
    Path((wallet_id, checkout_request_id)): Path<(Uuid, String)>,
) -> ApiResult<Json<DepositStatusResponse>> {
    let row = sqlx::query("select status, result_desc from mpesa_deposits where wallet_id = $1 and checkout_request_id = $2")
        .bind(wallet_id)
        .bind(&checkout_request_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(ApiError::NotFound("deposit not found"))?;

    let status: String = row.try_get("status")?;
    let everyday_balance_usd_cents = if status == "completed" {
        sqlx::query_scalar("select everyday_balance_cents from wallets where id = $1").bind(wallet_id).fetch_optional(&state.db).await?
    } else {
        None
    };

    Ok(Json(DepositStatusResponse { status, result_desc: row.try_get("result_desc")?, everyday_balance_usd_cents }))
}

/// Safaricom's webhook — see `daraja::StkCallbackBody`. Always returns
/// 200 with `{"ResultCode": 0}` regardless of outcome, per Daraja's own
/// integration guide (a non-200/malformed ack makes Safaricom retry the
/// callback repeatedly).
async fn stk_callback(State(state): State<AppState>, Json(body): Json<daraja::StkCallbackBody>) -> Json<serde_json::Value> {
    let callback = body.body.stk_callback;
    if let Err(e) = process_callback(&state, &callback).await {
        tracing::error!(error = %e, checkout_request_id = %callback.checkout_request_id, "failed to process M-Pesa callback");
    }
    Json(serde_json::json!({"ResultCode": 0, "ResultDesc": "Accepted"}))
}

async fn process_callback(state: &AppState, callback: &daraja::StkCallback) -> anyhow::Result<()> {
    let mut tx = state.db.begin().await?;

    let row = sqlx::query("select wallet_id, amount_usd_cents from mpesa_deposits where checkout_request_id = $1 for update")
        .bind(&callback.checkout_request_id)
        .fetch_optional(&mut *tx)
        .await?;
    let Some(row) = row else {
        anyhow::bail!("no mpesa_deposits row for checkout_request_id {}", callback.checkout_request_id);
    };
    let wallet_id: Uuid = row.try_get("wallet_id")?;
    let amount_usd_cents: i64 = row.try_get("amount_usd_cents")?;

    if callback.result_code == 0 {
        sqlx::query(
            "update mpesa_deposits set status = 'completed', mpesa_receipt = $2, result_desc = $3, completed_at = now()
             where checkout_request_id = $1",
        )
        .bind(&callback.checkout_request_id)
        .bind(callback.mpesa_receipt())
        .bind(&callback.result_desc)
        .execute(&mut *tx)
        .await?;

        sqlx::query("update wallets set everyday_balance_cents = everyday_balance_cents + $2 where id = $1")
            .bind(wallet_id)
            .bind(amount_usd_cents)
            .execute(&mut *tx)
            .await?;

        sqlx::query(
            "insert into transactions (wallet_id, direction, counterparty_name, amount_usd_cents, kind, status)
             values ($1, 'in', 'M-Pesa', $2, 'mpesa_deposit', 'settled')",
        )
        .bind(wallet_id)
        .bind(amount_usd_cents)
        .execute(&mut *tx)
        .await?;

        crate::ledger::record(
            &mut tx,
            wallet_id,
            "in",
            amount_usd_cents,
            "mpesa_deposit",
            Some(&callback.checkout_request_id),
            None,
        )
        .await?;
    } else {
        sqlx::query("update mpesa_deposits set status = 'failed', result_desc = $2 where checkout_request_id = $1")
            .bind(&callback.checkout_request_id)
            .bind(&callback.result_desc)
            .execute(&mut *tx)
            .await?;
    }

    tx.commit().await?;
    if callback.result_code == 0 {
        state.notify_balance_change(wallet_id).await;
        state
            .push
            .notify_wallet(
                &state.db,
                wallet_id,
                "Money received",
                "Your M-Pesa top-up just landed — open JamiiPay to see it.",
                "balance",
            )
            .await;
    }
    Ok(())
}
