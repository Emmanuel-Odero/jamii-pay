use axum::{
    extract::{Path, State},
    routing::post,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::daraja::{self, DarajaB2cConfig};
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new().route("/wallets/:id/cash-out", post(create_cash_out))
}

/// A single global mock exchange rate, matching
/// `designs/jammii-pay-prototype.html`'s `S.rate` default exactly — this
/// app has no real live FX rate feed, so the rate is a constant rather
/// than fetched from anywhere. (The M-Pesa *disbursement* itself is real
/// — see the `daraja::b2c_payment_request` call below — only the
/// USD/KES conversion rate is a stand-in.)
const USD_KES_RATE: f64 = 129.25;

/// The spread disclosed inline on the Cash-out screen ("Our spread ·
/// 0.8% · shown openly", same copy/value as the prototype) — applied to
/// the KES amount shown to the user, not to what's debited in USD: the
/// user always sees and pays exactly the USD amount they typed, and the
/// spread is reflected as a worse KES/$ rate on the receiving end. This
/// mirrors how the prototype computes it (`ksh()` uses the same `S.rate`
/// for both cash-out and everywhere else — the spread is disclosure
/// copy, not a separate deduction — kept identical here rather than
/// inventing a formula no design source specifies).
const CASHOUT_SPREAD: f64 = 0.008;

#[derive(Deserialize)]
struct CashOutRequest {
    mpesa_number: String,
    amount_usd_cents: i64,
    /// Client UUID per review confirmation — dedups double-tap/retry.
    idempotency_key: Option<String>,
}

#[derive(Serialize)]
struct CashOutResponse {
    transaction_id: Uuid,
    everyday_balance_usd_cents: i64,
    amount_kes_minor: i64,
    rate: f64,
}

/// Kenyan phone numbers arrive in several shapes from the UI
/// (`0712345678`, `+254712345678`, `254712345678`) — Daraja only accepts
/// the last of those. Duplicated from `routes/mpesa.rs` rather than
/// shared — both are ~10 lines and pulling them into a shared module
/// isn't worth the indirection for two call sites.
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

/// The Cash-out screen's real backend. Used to just debit the wallet and
/// mark the transaction `'settled'` immediately with no call to
/// Safaricom at all — money left the user's balance but nothing was ever
/// actually sent to the M-Pesa number, which is why neither the sender
/// nor the recipient ever saw a real confirmation. Now: debit happens
/// immediately (same as before — Cash-out is meant to feel instant), but
/// the transaction starts `'pending'` and a real
/// `daraja::b2c_payment_request` is fired; `routes/send_to_mpesa.rs`'s
/// result/timeout callbacks settle it to `'settled'` on success or
/// **refund the debit** and mark it `'failed'` if Safaricom's actual
/// disbursement doesn't go through.
async fn create_cash_out(
    State(state): State<AppState>,
    Path(wallet_id): Path<Uuid>,
    Json(req): Json<CashOutRequest>,
) -> ApiResult<Json<CashOutResponse>> {
    if req.amount_usd_cents <= 0 {
        return Err(ApiError::BadRequest("amount must be positive".to_string()));
    }
    let b2c_config = DarajaB2cConfig::from_env().ok_or(ApiError::BadRequest(
        "Cash-out isn't configured on this server yet — DARAJA_B2C_* env vars are missing. See crates/server/src/daraja.rs.".to_string(),
    ))?;
    let phone = normalize_phone(&req.mpesa_number)?;

    let effective_rate = USD_KES_RATE * (1.0 - CASHOUT_SPREAD);

    // Idempotency: same key returns the original cash-out result.
    if let Some(key) = req.idempotency_key.as_ref().filter(|k| !k.trim().is_empty()) {
        if let Some(row) = sqlx::query(
            "select t.id, w.everyday_balance_cents, t.amount_local_minor, t.fx_rate::text
             from transactions t join wallets w on w.id = t.wallet_id
             where t.wallet_id = $1 and t.idempotency_key = $2 and t.kind = 'cash_out' and t.direction = 'out'",
        )
        .bind(wallet_id)
        .bind(key)
        .fetch_optional(&state.db)
        .await?
        {
            let transaction_id: Uuid = row.try_get("id")?;
            let everyday_balance_usd_cents: i64 = row.try_get("everyday_balance_cents")?;
            let amount_kes_minor: i64 = row.try_get("amount_local_minor")?;
            let rate_text: Option<String> = row.try_get("fx_rate")?;
            let rate: f64 = rate_text.and_then(|s| s.parse().ok()).unwrap_or(effective_rate);
            return Ok(Json(CashOutResponse {
                transaction_id,
                everyday_balance_usd_cents,
                amount_kes_minor,
                rate,
            }));
        }
    }

    let amount_kes_minor = ((req.amount_usd_cents as f64 / 100.0) * effective_rate * 100.0).round() as i64;
    // Daraja only accepts whole-shilling amounts, same constraint as STK
    // Push's `routes/mpesa.rs`.
    let amount_kes = amount_kes_minor / 100;
    if amount_kes < 1 {
        return Err(ApiError::BadRequest("amount too small to convert to a whole shilling".to_string()));
    }

    let mut tx = state.db.begin().await?;

    let sender_balance: i64 = sqlx::query_scalar(
        "select everyday_balance_cents from wallets where id = $1 for update",
    )
    .bind(wallet_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(ApiError::NotFound("wallet not found"))?;

    if sender_balance < req.amount_usd_cents {
        return Err(ApiError::BadRequest(
            "insufficient everyday balance".to_string(),
        ));
    }

    let new_balance: i64 = sqlx::query_scalar(
        "update wallets set everyday_balance_cents = everyday_balance_cents - $2
         where id = $1 returning everyday_balance_cents",
    )
    .bind(wallet_id)
    .bind(req.amount_usd_cents)
    .fetch_one(&mut *tx)
    .await?;

    // 'pending', not 'settled' — this is now an honest reflection of
    // reality: the money has left the wallet, but Safaricom hasn't
    // confirmed the payout landed yet. Shows up in Activity the same way
    // any other pending transaction does.
    let transaction_id: Uuid = sqlx::query_scalar(
        "insert into transactions
            (wallet_id, direction, counterparty_name, amount_usd_cents, amount_local_minor,
             local_currency, fx_rate, kind, status, idempotency_key)
         values ($1, 'out', $2, $3, $4, 'KES', $5::numeric, 'cash_out', 'pending', $6)
         returning id",
    )
    .bind(wallet_id)
    .bind(&phone)
    .bind(req.amount_usd_cents)
    .bind(amount_kes_minor)
    // Bound as text + cast in-query (`$5::numeric`) rather than as f64 —
    // sqlx has no `Encode` for `f64 -> NUMERIC` without the `bigdecimal`/
    // `rust_decimal` crate feature, which nothing else here needs yet.
    .bind(format!("{effective_rate:.6}"))
    .bind(req.idempotency_key.as_ref().filter(|k| !k.trim().is_empty()))
    .fetch_one(&mut *tx)
    .await?;

    // The B2C call itself happens *inside* the transaction, before
    // commit — if Safaricom's API is unreachable or rejects the request
    // outright (bad credentials, invalid shortcode, ...), the whole
    // debit rolls back along with it, so a hard failure here never
    // leaves the wallet debited with nothing to show for it. A soft
    // failure (Safaricom accepts the request but the payout itself later
    // fails) is what the result/timeout callback's refund path handles —
    // this only guards the "never even got queued" case.
    let b2c_result = daraja::b2c_payment_request(&b2c_config, &phone, amount_kes, "JamiiPay cash out")
        .await
        .map_err(|e| ApiError::BadRequest(format!("Could not send the M-Pesa payout: {e}")))?;

    sqlx::query(
        "insert into outbound_mpesa_payments
            (wallet_id, destination_type, destination_identifier, amount_usd_cents, amount_kes_minor,
             conversation_id, transaction_id, idempotency_key)
         values ($1, 'phone', $2, $3, $4, $5, $6, $7)",
    )
    .bind(wallet_id)
    .bind(&phone)
    .bind(req.amount_usd_cents)
    .bind(amount_kes_minor)
    .bind(&b2c_result.conversation_id)
    .bind(transaction_id)
    .bind(req.idempotency_key.as_ref().filter(|k| !k.trim().is_empty()))
    .execute(&mut *tx)
    .await?;

    crate::ledger::record(
        &mut tx,
        wallet_id,
        "out",
        req.amount_usd_cents,
        "cash_out",
        req.idempotency_key.as_deref().filter(|k| !k.trim().is_empty()),
        Some(transaction_id),
    )
    .await?;

    tx.commit().await?;
    state.notify_balance_change(wallet_id).await;

    Ok(Json(CashOutResponse {
        transaction_id,
        everyday_balance_usd_cents: new_balance,
        amount_kes_minor,
        rate: effective_rate,
    }))
}
