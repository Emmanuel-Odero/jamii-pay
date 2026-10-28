//! Append-only ledger: the source of truth money moves are recorded in.
//!
//! History: balances lived (and still live, as a cached projection) in
//! mutable `wallets` columns. Every handler below used to mutate those
//! columns and write a display-oriented `transactions` row. That is
//! backwards for money: the ledger is now written in the same database
//! transaction as every balance mutation, so a crash or bug can never
//! leave a balance moved with no record, or a record with no balance
//! moved. Failing to write the ledger row aborts the whole money move —
//! fail closed, always.
//!
//! Invariant (checked by `GET /wallets/:id/ledger/check` and the future
//! reconciliation job): per wallet,
//! `SUM(in) − SUM(out) == everyday_balance_cents + savings_balance_cents
//! − opening_adjustment`, where pre-ledger history is captured once as a
//! single `adjustment` row per wallet (see `backfill_opening_balances`,
//! run once at cutover). Internal moves (savings) record balanced out+in
//! legs under the same kind, netting to zero while keeping both sides
//! auditable.

use axum::{
    extract::{Path, State},
    routing::get,
    Json, Router,
};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new().route("/wallets/:id/ledger/check", get(check_ledger))
}

/// Records one balance mutation in the caller's transaction. Must be
/// called with every `update wallets set *_balance_cents` — same `tx`,
/// before commit. `ref_id` links to the originating row (transaction,
/// claim, deposit) for reconciliation.
pub async fn record(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    wallet_id: Uuid,
    direction: &str,
    amount_usd_cents: i64,
    kind: &str,
    idempotency_key: Option<&str>,
    ref_id: Option<Uuid>,
) -> Result<(), sqlx::Error> {
    debug_assert!(direction == "in" || direction == "out");
    debug_assert!(amount_usd_cents > 0);
    sqlx::query(
        "insert into ledger_entries
            (wallet_id, direction, amount_usd_cents, kind, idempotency_key, ref_id)
         values ($1, $2, $3, $4, nullif($5, ''), $6)",
    )
    .bind(wallet_id)
    .bind(direction)
    .bind(amount_usd_cents)
    .bind(kind)
    .bind(idempotency_key.filter(|k| !k.trim().is_empty()))
    .bind(ref_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

#[derive(Serialize)]
struct LedgerCheck {
    wallet_id: Uuid,
    ledger_net_cents: i64,
    columns_total_cents: i64,
    /// True when the ledger exactly explains the cached columns. False
    /// means a pre-ledger mutation slipped past dual-write (or the opening
    /// backfill never ran) — investigate, do not "fix" by adjusting.
    matches: bool,
}

/// Reconciliation probe: compares the ledger's net against the cached
/// balance columns. Read-only; the scheduled reconciliation job will call
/// this per wallet and page on mismatch.
async fn check_ledger(
    State(state): State<AppState>,
    Path(wallet_id): Path<Uuid>,
) -> ApiResult<Json<LedgerCheck>> {
    let net: Option<i64> = sqlx::query_scalar(
        "select coalesce(sum(case when direction = 'in' then amount_usd_cents
                                  else -amount_usd_cents end), 0)
         from ledger_entries where wallet_id = $1",
    )
    .bind(wallet_id)
    .fetch_optional(&state.db)
    .await?
    .flatten();
    let cols: Option<(i64, i64)> = sqlx::query_as(
        "select everyday_balance_cents, savings_balance_cents from wallets where id = $1",
    )
    .bind(wallet_id)
    .fetch_optional(&state.db)
    .await?;
    let (everyday, savings) = cols.ok_or(ApiError::NotFound("wallet not found"))?;
    let net = net.unwrap_or(0);
    let total = everyday + savings;
    Ok(Json(LedgerCheck {
        wallet_id,
        ledger_net_cents: net,
        columns_total_cents: total,
        matches: net == total,
    }))
}
