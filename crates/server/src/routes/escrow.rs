use axum::{
    extract::{Path, State},
    response::Html,
    routing::{get, post},
    Json, Router,
};
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

/// Same mock rate/spread as Cash-out — a claimed escrow settles exactly
/// like a cash-out, just triggered by the recipient instead of the
/// sender. See `routes/cash_out.rs`'s doc comment for why these are
/// constants rather than fetched from anywhere.
const USD_KES_RATE: f64 = 129.25;
const CASHOUT_SPREAD: f64 = 0.008;

const CLAIM_WINDOW_HOURS: i64 = 72;

/// Higher than `create_transfer`'s $0.04 flat fee — matches the
/// prototype's fee-transparency requirement exactly (registered
/// recipient: $0.04, unregistered: $0.09), reflecting the extra cost of
/// holding funds in escrow. Charged to the sender on top of the amount
/// the recipient actually claims, same debit-more/credit-exact pattern
/// as `create_transfer`.
const ESCROW_FLAT_FEE_USD_CENTS: i64 = 9;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/wallets/:id/escrow", post(create_escrow).get(list_escrow))
        .route("/wallets/:id/escrow/:claim_id/cancel", post(cancel_escrow))
        .route("/claim/:code", get(claim_page))
        .route("/claim/:code/claim", post(settle_claim))
}

fn hash_code(code: &str) -> String {
    hex::encode(Sha256::digest(code.as_bytes()))
}

fn generate_code() -> String {
    // Short enough to type/read off an SMS, matching the prototype's
    // `claim.jamiipay.com/k4m2`-style link — borrows entropy from a real
    // UUIDv4 rather than pulling in a new RNG dependency.
    hex::encode(&Uuid::new_v4().as_bytes()[0..4])
}

#[derive(Deserialize)]
struct CreateEscrowRequest {
    recipient_addr: String,
    recipient_kind: String,
    amount_usd_cents: i64,
}

#[derive(Serialize)]
struct EscrowResponse {
    id: Uuid,
    recipient_addr: String,
    recipient_kind: String,
    amount_usd_cents: i64,
    status: String,
    expires_at: DateTime<Utc>,
    /// Only ever present in the response to [`create_escrow`] — nothing
    /// else can reconstruct the raw code from `claim_code_hash`.
    claim_code: Option<String>,
    /// Present only on the create response — `list_escrow`/`cancel_escrow`
    /// have no reason to repeat it since it never changes for a claim.
    fee_usd_cents: Option<i64>,
}

async fn create_escrow(
    State(state): State<AppState>,
    Path(sender_id): Path<Uuid>,
    Json(req): Json<CreateEscrowRequest>,
) -> ApiResult<Json<EscrowResponse>> {
    if req.amount_usd_cents <= 0 {
        return Err(ApiError::BadRequest("amount must be positive".to_string()));
    }
    if !["phone", "email"].contains(&req.recipient_kind.as_str()) {
        return Err(ApiError::BadRequest("recipient_kind must be phone or email".to_string()));
    }

    let total_debit = req.amount_usd_cents + ESCROW_FLAT_FEE_USD_CENTS;

    let mut tx = state.db.begin().await?;

    let sender_balance: i64 = sqlx::query_scalar("select everyday_balance_cents from wallets where id = $1 for update")
        .bind(sender_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or(ApiError::NotFound("wallet not found"))?;
    if sender_balance < total_debit {
        return Err(ApiError::BadRequest("insufficient everyday balance for amount + fee".to_string()));
    }

    sqlx::query("update wallets set everyday_balance_cents = everyday_balance_cents - $2 where id = $1")
        .bind(sender_id)
        .bind(total_debit)
        .execute(&mut *tx)
        .await?;

    let code = generate_code();
    let expires_at = Utc::now() + Duration::hours(CLAIM_WINDOW_HOURS);

    let claim_id: Uuid = sqlx::query_scalar(
        "insert into claims
            (wallet_id, claim_code_hash, amount_minor_units, currency,
             recipient_addr, recipient_kind, expires_at, status)
         values ($1, $2, $3, 'USD', $4, $5, $6, 'pending')
         returning id",
    )
    .bind(sender_id)
    .bind(hash_code(&code))
    .bind(req.amount_usd_cents)
    .bind(&req.recipient_addr)
    .bind(&req.recipient_kind)
    .bind(expires_at)
    .fetch_one(&mut *tx)
    .await?;

    // Also record the debit as a real transaction so it shows up in
    // Activity like every other spend — "Held for {addr}" mirrors the
    // prototype's exact wording for this state.
    sqlx::query(
        "insert into transactions (wallet_id, direction, counterparty_name, amount_usd_cents, kind, status)
         values ($1, 'out', $2, $3, 'transfer', 'pending')",
    )
    .bind(sender_id)
    .bind(format!("Held for {}", req.recipient_addr))
    .bind(total_debit)
    .execute(&mut *tx)
    .await?;

    crate::ledger::record(&mut tx, sender_id, "out", total_debit, "escrow", None, Some(claim_id))
        .await?;

    tx.commit().await?;

    Ok(Json(EscrowResponse {
        id: claim_id,
        recipient_addr: req.recipient_addr,
        recipient_kind: req.recipient_kind,
        amount_usd_cents: req.amount_usd_cents,
        status: "pending".to_string(),
        expires_at,
        claim_code: Some(code),
        fee_usd_cents: Some(ESCROW_FLAT_FEE_USD_CENTS),
    }))
}

/// Lazily expires anything past its window — refunds the sender and
/// flips `status` — rather than running a background sweep (flagged as a
/// real follow-up for production; fine for now since this only needs to
/// be correct by the next time anyone looks at it).
async fn expire_stale(db: &sqlx::PgPool, wallet_id: Uuid) -> ApiResult<()> {
    let stale: Vec<(Uuid, i64)> = sqlx::query_as(
        "select id, amount_minor_units from claims
         where wallet_id = $1 and status = 'pending' and expires_at < now()",
    )
    .bind(wallet_id)
    .fetch_all(db)
    .await?;

    for (claim_id, amount) in stale {
        let mut tx = db.begin().await?;
        sqlx::query("update claims set status = 'expired' where id = $1")
            .bind(claim_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("update wallets set everyday_balance_cents = everyday_balance_cents + $2 where id = $1")
            .bind(wallet_id)
            .bind(amount + ESCROW_FLAT_FEE_USD_CENTS)
            .execute(&mut *tx)
            .await?;
        crate::ledger::record(
            &mut tx,
            wallet_id,
            "in",
            amount + ESCROW_FLAT_FEE_USD_CENTS,
            "escrow",
            None,
            Some(claim_id),
        )
        .await?;
        tx.commit().await?;
    }
    Ok(())
}

async fn list_escrow(State(state): State<AppState>, Path(wallet_id): Path<Uuid>) -> ApiResult<Json<Vec<EscrowResponse>>> {
    expire_stale(&state.db, wallet_id).await?;

    let rows = sqlx::query(
        "select id, recipient_addr, recipient_kind, amount_minor_units, status, expires_at
         from claims where wallet_id = $1 and status = 'pending' order by created_at desc",
    )
    .bind(wallet_id)
    .fetch_all(&state.db)
    .await?;

    Ok(Json(
        rows.into_iter()
            .map(|r| EscrowResponse {
                id: r.get("id"),
                recipient_addr: r.get("recipient_addr"),
                recipient_kind: r.get("recipient_kind"),
                amount_usd_cents: r.get("amount_minor_units"),
                status: r.get("status"),
                expires_at: r.get("expires_at"),
                claim_code: None,
                fee_usd_cents: None,
            })
            .collect(),
    ))
}

async fn cancel_escrow(
    State(state): State<AppState>,
    Path((wallet_id, claim_id)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<serde_json::Value>> {
    let mut tx = state.db.begin().await?;

    let amount: i64 = sqlx::query_scalar(
        "update claims set status = 'cancelled'
         where id = $1 and wallet_id = $2 and status = 'pending'
         returning amount_minor_units",
    )
    .bind(claim_id)
    .bind(wallet_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(ApiError::NotFound("no pending claim with that id"))?;

    sqlx::query("update wallets set everyday_balance_cents = everyday_balance_cents + $2 where id = $1")
        .bind(wallet_id)
        .bind(amount + ESCROW_FLAT_FEE_USD_CENTS)
        .execute(&mut *tx)
        .await?;

    crate::ledger::record(
        &mut tx,
        wallet_id,
        "in",
        amount + ESCROW_FLAT_FEE_USD_CENTS,
        "escrow",
        None,
        Some(claim_id),
    )
    .await?;

    tx.commit().await?;
    Ok(Json(serde_json::json!({"ok": true})))
}

struct ClaimRow {
    id: Uuid,
    wallet_id: Uuid,
    amount_minor_units: i64,
    recipient_addr: String,
    status: String,
    expires_at: DateTime<Utc>,
}

async fn find_claim(db: &sqlx::PgPool, code: &str) -> ApiResult<ClaimRow> {
    let row = sqlx::query(
        "select id, wallet_id, amount_minor_units, recipient_addr, status, expires_at
         from claims where claim_code_hash = $1",
    )
    .bind(hash_code(code))
    .fetch_optional(db)
    .await?
    .ok_or(ApiError::NotFound("claim not found"))?;

    let mut claim = ClaimRow {
        id: row.try_get("id")?,
        wallet_id: row.try_get("wallet_id")?,
        amount_minor_units: row.try_get("amount_minor_units")?,
        recipient_addr: row.try_get("recipient_addr")?,
        status: row.try_get("status")?,
        expires_at: row.try_get("expires_at")?,
    };

    if claim.status == "pending" && claim.expires_at < Utc::now() {
        expire_stale(db, claim.wallet_id).await?;
        claim.status = "expired".to_string();
    }

    Ok(claim)
}

/// The recipient-facing web page — no app install needed, matching the
/// prototype's `claim.jamiipay.com/<code>` mini-browser mock. Server-
/// rendered HTML, not a Flutter screen — the whole point is that whoever
/// opens this link has nothing installed.
async fn claim_page(State(state): State<AppState>, Path(code): Path<String>) -> ApiResult<Html<String>> {
    let claim = find_claim(&state.db, &code).await?;

    let body = match claim.status.as_str() {
        "pending" => format!(
            r#"<h1>You have money waiting</h1>
            <p>${:.2} was sent to you. Confirm your number to collect it.</p>
            <p>Sending to: {}</p>
            <form method="post" action="/claim/{code}/claim">
              <label>Your M-Pesa number<input name="mpesa_number" placeholder="+254 7xx xxx xxx" required></label>
              <button type="submit">Send to M-Pesa</button>
            </form>
            <p><small>No app, no password, no account. Confirming the number you were sent to is enough.</small></p>"#,
            claim.amount_minor_units as f64 / 100.0,
            claim.recipient_addr,
        ),
        "claimed" => "<h1>Already claimed</h1><p>This money has already been sent.</p>".to_string(),
        "expired" => "<h1>This link has expired</h1><p>The money was returned to the sender.</p>".to_string(),
        _ => "<h1>This claim was cancelled</h1>".to_string(),
    };

    Ok(Html(claim_page_shell(&body)))
}

#[derive(Deserialize)]
struct SettleClaimForm {
    mpesa_number: String,
}

async fn settle_claim(
    State(state): State<AppState>,
    Path(code): Path<String>,
    axum::Form(form): axum::Form<SettleClaimForm>,
) -> ApiResult<Html<String>> {
    let claim = find_claim(&state.db, &code).await?;
    if claim.status != "pending" {
        return Ok(Html(claim_page_shell(&format!("<h1>This claim is {}</h1>", claim.status))));
    }

    let effective_rate = USD_KES_RATE * (1.0 - CASHOUT_SPREAD);
    let amount_kes = (claim.amount_minor_units as f64 / 100.0) * effective_rate;

    let mut tx = state.db.begin().await?;
    sqlx::query("update claims set status = 'claimed', claimed_at = now() where id = $1")
        .bind(claim.id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("update transactions set status = 'settled' where wallet_id = $1 and counterparty_name = $2 and status = 'pending'")
        .bind(claim.wallet_id)
        .bind(format!("Held for {}", claim.recipient_addr))
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    Ok(Html(claim_page_shell(&format!(
        r#"<h1>On its way</h1><p>KSh {amount_kes:.0} is being sent to {}. It usually arrives within a minute.</p>"#,
        form.mpesa_number,
    ))))
}

fn claim_page_shell(body: &str) -> String {
    format!(
        r#"<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>JamiiPay — Claim your money</title>
<style>
  body {{ font-family: -apple-system, sans-serif; background: #0B1224; color: #EEF3FB; max-width: 420px; margin: 40px auto; padding: 0 20px; }}
  h1 {{ font-size: 22px; }}
  form {{ margin-top: 16px; }}
  label {{ display: block; font-size: 13px; color: #A4B3CE; margin-bottom: 6px; }}
  input {{ width: 100%; padding: 10px; border-radius: 8px; border: 1px solid #2B3B5C; background: #15213B; color: #EEF3FB; box-sizing: border-box; }}
  button {{ margin-top: 12px; width: 100%; padding: 12px; border-radius: 10px; border: none; background: #2F80ED; color: white; font-weight: 700; font-size: 14px; }}
</style></head>
<body>{body}</body></html>"#
    )
}
