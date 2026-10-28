//! Live FX quote — single source of truth for USD/KES used by every
//! money review sheet (Send, Scan-Pay, Cash-out, Broadcast).
//!
//! Previously the rate lived as scattered `static const 129.25` copies in
//! Flutter (`cash_out_screen.dart`, `mpesa_receive_screen.dart`) labeled
//! "Rate today" while static, plus a second copy in `cash_out.rs` and
//! `mpesa.rs`. This endpoint serves the same constants today (no live feed
//! yet) but with an `updated_at` timestamp and spread breakdown so clients
//! can show "updated Xm ago", freeze the quote at confirm time, and print
//! the exact rate on every receipt. Swap `USD_KES_RATE` for a real feed
//! later without changing the API shape.

use axum::{routing::get, Json, Router};
use chrono::Utc;
use serde::Serialize;

use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new().route("/fx/rate", get(get_rate))
}

/// Must match `cash_out.rs::USD_KES_RATE` and `mpesa.rs::USD_KES_RATE`.
const USD_KES_RATE: f64 = 129.25;
const CASHOUT_SPREAD: f64 = 0.008;
const HANDLE_FEE_USD_CENTS: i64 = 4;
const ESCROW_FEE_USD_CENTS: i64 = 9;

#[derive(Serialize)]
struct FxRateResponse {
    rate: f64,
    spread: f64,
    effective_cashout_rate: f64,
    handle_fee_usd_cents: i64,
    escrow_fee_usd_cents: i64,
    updated_at: String,
}

async fn get_rate() -> Json<FxRateResponse> {
    Json(FxRateResponse {
        rate: USD_KES_RATE,
        spread: CASHOUT_SPREAD,
        effective_cashout_rate: USD_KES_RATE * (1.0 - CASHOUT_SPREAD),
        handle_fee_usd_cents: HANDLE_FEE_USD_CENTS,
        escrow_fee_usd_cents: ESCROW_FEE_USD_CENTS,
        updated_at: Utc::now().to_rfc3339(),
    })
}
