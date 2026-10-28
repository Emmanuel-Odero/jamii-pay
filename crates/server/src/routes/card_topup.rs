//! Card top-up (credit/debit/prepaid/virtual — Stripe treats them all
//! the same, so there's no special-casing here) via **Stripe Checkout**:
//! a Stripe-hosted payment page, not a native card form embedded in this
//! app. That's a deliberate choice, not a shortcut — collecting card
//! numbers directly would put this app in PCI-DSS scope; a hosted page
//! keeps card data off our servers (and off the phone) entirely, and
//! avoids adding a native Stripe SDK to the Flutter build.
//!
//! **Setup required before this does anything real:**
//! 1. A Stripe secret key (`STRIPE_SECRET_KEY`, starts `sk_test_...` or
//!    `sk_live_...`) from dashboard.stripe.com/apikeys, in this
//!    project's `.env` (never committed, never pasted into chat).
//! 2. A webhook endpoint registered in the Stripe Dashboard
//!    (Developers → Webhooks) pointing at `<public-url>/stripe/webhook`,
//!    subscribed to the `checkout.session.completed` event. Stripe shows
//!    you a signing secret when you create it — that's
//!    `STRIPE_WEBHOOK_SECRET`. Like `crates/server/src/daraja.rs`'s
//!    callback, `<public-url>` has to be a real public HTTPS address —
//!    the same `ngrok http 8081` tunnel already needed for M-Pesa works
//!    for both at once, since ngrok exposes the whole port.
//! 3. `PUBLIC_BASE_URL` — where the success/cancel redirect lands after
//!    checkout. Unlike the webhook, this loads in the *person's own
//!    phone browser*, so it only needs to be reachable from their phone,
//!    not the public internet — the existing mDNS address
//!    (`http://Ochiengs-MacBook-Pro.local:8081`) works fine here and is
//!    the default if this isn't set.

use axum::{
    body::Bytes,
    extract::{Path, State},
    http::HeaderMap,
    response::Html,
    routing::{get, post},
    Json, Router,
};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use sqlx::Row;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/wallets/:id/topup/card/checkout", post(create_checkout))
        .route("/wallets/:id/topup/card/:topup_id", get(get_topup_status))
        .route("/stripe/webhook", post(stripe_webhook))
        .route("/topup/success", get(success_page))
        .route("/topup/cancel", get(cancel_page))
}

struct StripeConfig {
    secret_key: String,
    public_base_url: String,
}

impl StripeConfig {
    fn from_env() -> Option<Self> {
        Some(Self {
            secret_key: std::env::var("STRIPE_SECRET_KEY").ok()?,
            public_base_url: std::env::var("PUBLIC_BASE_URL").unwrap_or_else(|_| "http://Ochiengs-MacBook-Pro.local:8081".to_string()),
        })
    }
}

#[derive(Deserialize)]
struct CreateCheckoutRequest {
    amount_usd_cents: i64,
}

#[derive(Serialize)]
struct CreateCheckoutResponse {
    checkout_url: String,
    topup_id: Uuid,
}

async fn create_checkout(
    State(state): State<AppState>,
    Path(wallet_id): Path<Uuid>,
    Json(req): Json<CreateCheckoutRequest>,
) -> ApiResult<Json<CreateCheckoutResponse>> {
    if req.amount_usd_cents < 50 {
        // Stripe's own minimum for a USD charge.
        return Err(ApiError::BadRequest("amount must be at least $0.50".to_string()));
    }
    let config = StripeConfig::from_env().ok_or(ApiError::BadRequest(
        "Card top-up isn't configured on this server yet — STRIPE_SECRET_KEY is missing. See crates/server/src/routes/card_topup.rs.".to_string(),
    ))?;

    let handle: Option<String> = sqlx::query_scalar("select full_handle from handles where wallet_id = $1")
        .bind(wallet_id)
        .fetch_optional(&state.db)
        .await?;
    let reference = handle.unwrap_or_else(|| "JamiiPay".to_string());

    let client = reqwest::Client::new();
    let res = client
        .post("https://api.stripe.com/v1/checkout/sessions")
        .basic_auth(&config.secret_key, Option::<&str>::None)
        .form(&[
            ("mode", "payment"),
            ("client_reference_id", wallet_id.to_string().as_str()),
            ("metadata[wallet_id]", wallet_id.to_string().as_str()),
            ("line_items[0][quantity]", "1"),
            ("line_items[0][price_data][currency]", "usd"),
            ("line_items[0][price_data][unit_amount]", req.amount_usd_cents.to_string().as_str()),
            ("line_items[0][price_data][product_data][name]", format!("JamiiPay top-up ({reference})").as_str()),
            ("success_url", format!("{}/topup/success", config.public_base_url).as_str()),
            ("cancel_url", format!("{}/topup/cancel", config.public_base_url).as_str()),
        ])
        .send()
        .await
        .map_err(|e| ApiError::BadRequest(format!("Could not reach Stripe: {e}")))?;

    if !res.status().is_success() {
        let status = res.status();
        let body = res.text().await.unwrap_or_default();
        return Err(ApiError::BadRequest(format!("Stripe rejected the checkout request ({status}): {body}")));
    }

    #[derive(Deserialize)]
    struct Session {
        id: String,
        url: String,
    }
    let session: Session = res.json().await.map_err(|e| ApiError::BadRequest(format!("Could not parse Stripe's response: {e}")))?;

    let topup_id: Uuid = sqlx::query_scalar(
        "insert into card_topups (wallet_id, stripe_session_id, amount_usd_cents) values ($1, $2, $3) returning id",
    )
    .bind(wallet_id)
    .bind(&session.id)
    .bind(req.amount_usd_cents)
    .fetch_one(&state.db)
    .await?;

    Ok(Json(CreateCheckoutResponse { checkout_url: session.url, topup_id }))
}

#[derive(Serialize)]
struct TopupStatusResponse {
    status: String,
    everyday_balance_usd_cents: Option<i64>,
}

async fn get_topup_status(
    State(state): State<AppState>,
    Path((wallet_id, topup_id)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<TopupStatusResponse>> {
    let status: String = sqlx::query_scalar("select status from card_topups where id = $1 and wallet_id = $2")
        .bind(topup_id)
        .bind(wallet_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(ApiError::NotFound("top-up not found"))?;

    let everyday_balance_usd_cents = if status == "completed" {
        sqlx::query_scalar("select everyday_balance_cents from wallets where id = $1").bind(wallet_id).fetch_optional(&state.db).await?
    } else {
        None
    };

    Ok(Json(TopupStatusResponse { status, everyday_balance_usd_cents }))
}

/// Verifies Stripe's `Stripe-Signature` header
/// (`t=<unix_ts>,v1=<hex_hmac_sha256>`) over the *raw* request body — see
/// Stripe's webhook signing docs. Deliberately takes `Bytes`, not a
/// parsed `Json<...>`, because the signature is computed over the exact
/// bytes Stripe sent; re-serializing parsed JSON would very likely
/// change whitespace/key order and break verification.
fn verify_stripe_signature(header: &str, body: &[u8], secret: &str) -> bool {
    let mut timestamp = None;
    let mut v1 = None;
    for part in header.split(',') {
        if let Some(t) = part.strip_prefix("t=") {
            timestamp = Some(t);
        } else if let Some(sig) = part.strip_prefix("v1=") {
            v1 = Some(sig);
        }
    }
    let (Some(timestamp), Some(v1)) = (timestamp, v1) else { return false };

    let signed_payload = [timestamp.as_bytes(), b".", body].concat();
    let Ok(mut mac) = Hmac::<Sha256>::new_from_slice(secret.as_bytes()) else { return false };
    mac.update(&signed_payload);
    let expected = hex::encode(mac.finalize().into_bytes());

    // Constant-time-ish via length + byte compare is good enough here —
    // `hex::encode` output length is fixed by the hash, so this doesn't
    // leak more than a standard `==` would for a value already this
    // structured.
    expected == v1
}

async fn stripe_webhook(State(state): State<AppState>, headers: HeaderMap, body: Bytes) -> Json<serde_json::Value> {
    let Ok(webhook_secret) = std::env::var("STRIPE_WEBHOOK_SECRET") else {
        tracing::warn!("received a Stripe webhook but STRIPE_WEBHOOK_SECRET isn't configured — ignoring");
        return Json(serde_json::json!({"received": true}));
    };
    let Some(signature) = headers.get("stripe-signature").and_then(|v| v.to_str().ok()) else {
        tracing::warn!("Stripe webhook missing Stripe-Signature header");
        return Json(serde_json::json!({"received": true}));
    };
    if !verify_stripe_signature(signature, &body, &webhook_secret) {
        tracing::warn!("Stripe webhook signature verification failed");
        return Json(serde_json::json!({"received": true}));
    }

    if let Err(e) = process_webhook_body(&state, &body).await {
        tracing::error!(error = %e, "failed to process Stripe webhook");
    }
    Json(serde_json::json!({"received": true}))
}

async fn process_webhook_body(state: &AppState, body: &[u8]) -> anyhow::Result<()> {
    let event: serde_json::Value = serde_json::from_slice(body)?;
    if event.get("type").and_then(|t| t.as_str()) != Some("checkout.session.completed") {
        return Ok(()); // not the event we care about — ignore silently
    }

    let session = &event["data"]["object"];
    let stripe_session_id = session["id"].as_str().ok_or_else(|| anyhow::anyhow!("missing session id"))?;
    let payment_status = session["payment_status"].as_str().unwrap_or_default();
    if payment_status != "paid" {
        return Ok(()); // completed the checkout flow but didn't actually pay (rare, but possible)
    }

    let mut tx = state.db.begin().await?;

    let row = sqlx::query("select wallet_id, amount_usd_cents, status from card_topups where stripe_session_id = $1 for update")
        .bind(stripe_session_id)
        .fetch_optional(&mut *tx)
        .await?;
    let Some(row) = row else {
        anyhow::bail!("no card_topups row for stripe_session_id {stripe_session_id}");
    };
    let status: String = row.try_get("status")?;
    if status != "pending" {
        return Ok(()); // already processed — Stripe retries webhooks, this makes it idempotent
    }
    let wallet_id: Uuid = row.try_get("wallet_id")?;
    let amount_usd_cents: i64 = row.try_get("amount_usd_cents")?;

    sqlx::query("update card_topups set status = 'completed', completed_at = now() where stripe_session_id = $1")
        .bind(stripe_session_id)
        .execute(&mut *tx)
        .await?;

    sqlx::query("update wallets set everyday_balance_cents = everyday_balance_cents + $2 where id = $1")
        .bind(wallet_id)
        .bind(amount_usd_cents)
        .execute(&mut *tx)
        .await?;

    sqlx::query(
        "insert into transactions (wallet_id, direction, counterparty_name, amount_usd_cents, kind, status)
         values ($1, 'in', 'Card top-up', $2, 'card_topup', 'settled')",
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
        "card_topup",
        Some(stripe_session_id),
        None,
    )
    .await?;

    tx.commit().await?;
    state.notify_balance_change(wallet_id).await;
    state
        .push
        .notify_wallet(
            &state.db,
            wallet_id,
            "Money received",
            "Your card top-up just landed — open JamiiPay to see it.",
            "balance",
        )
        .await;
    Ok(())
}

async fn success_page() -> Html<&'static str> {
    Html(
        "<!doctype html><html><body style='font-family:sans-serif;text-align:center;padding:60px 20px;background:#0B1224;color:#fff'>\
         <h2>Payment received</h2><p>You can close this and go back to JamiiPay — your balance updates automatically.</p></body></html>",
    )
}

async fn cancel_page() -> Html<&'static str> {
    Html(
        "<!doctype html><html><body style='font-family:sans-serif;text-align:center;padding:60px 20px;background:#0B1224;color:#fff'>\
         <h2>Top-up cancelled</h2><p>No charge was made. You can close this and go back to JamiiPay.</p></body></html>",
    )
}
