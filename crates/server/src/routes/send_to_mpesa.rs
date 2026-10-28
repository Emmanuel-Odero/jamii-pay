//! Paying real money out to an M-Pesa number — the B2C half of the app's
//! M-Pesa integration (`routes/mpesa.rs` is the inbound STK Push half).
//! `routes/cash_out.rs` calls [`crate::daraja::b2c_payment_request`]
//! directly and records the attempt in `outbound_mpesa_payments`; this
//! module only owns the two webhook routes Safaricom calls back on —
//! there's no synchronous "did it work" from the initiate call itself,
//! same asynchronous shape as STK Push's `stk_callback`.

use axum::{extract::State, routing::post, Json, Router};
use sqlx::Row;
use uuid::Uuid;

use crate::daraja::B2cCallbackBody;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/mpesa/b2c/result", post(b2c_result))
        .route("/mpesa/b2c/timeout", post(b2c_timeout))
}

/// Safaricom's B2C result webhook — always returns 200 regardless of
/// outcome, per Daraja's integration guide (same posture as
/// `routes/mpesa.rs::stk_callback`: a non-200/malformed ack just makes
/// Safaricom retry the callback repeatedly rather than giving up).
async fn b2c_result(State(state): State<AppState>, Json(body): Json<B2cCallbackBody>) -> Json<serde_json::Value> {
    if let Err(e) = process_result(&state, &body.result).await {
        tracing::error!(error = %e, conversation_id = %body.result.conversation_id, "failed to process M-Pesa B2C result callback");
    }
    Json(serde_json::json!({"ResultCode": 0, "ResultDesc": "Accepted"}))
}

/// Safaricom's B2C *timeout* webhook — fires instead of `b2c_result` if
/// the request sat in Safaricom's queue too long without a definitive
/// outcome. Same payload shape as the result callback (a `Result` with a
/// non-zero `ResultCode`), so it's handled identically: this only exists
/// as a separate route because `DARAJA_B2C_TIMEOUT_URL` is a required,
/// separate field on the B2C request — Safaricom won't accept one URL
/// serving both purposes.
async fn b2c_timeout(State(state): State<AppState>, Json(body): Json<B2cCallbackBody>) -> Json<serde_json::Value> {
    if let Err(e) = process_result(&state, &body.result).await {
        tracing::error!(error = %e, conversation_id = %body.result.conversation_id, "failed to process M-Pesa B2C timeout callback");
    }
    Json(serde_json::json!({"ResultCode": 0, "ResultDesc": "Accepted"}))
}

async fn process_result(state: &AppState, result: &crate::daraja::B2cCallbackResult) -> anyhow::Result<()> {
    let mut tx = state.db.begin().await?;

    // Locked and fetched once up front — the `status = 'pending'` guard
    // on the row lookup (not just the later UPDATEs) is what makes this
    // safe against a timeout callback racing a result callback for the
    // same request: whichever lands second finds no pending row left and
    // is a clean no-op, not a double-settle or a double-refund.
    let row = sqlx::query(
        "select wallet_id, transaction_id, amount_usd_cents from outbound_mpesa_payments
         where conversation_id = $1 and status = 'pending' for update",
    )
    .bind(&result.conversation_id)
    .fetch_optional(&mut *tx)
    .await?;
    let Some(row) = row else {
        // Either already settled by a racing callback (fine, not a bug)
        // or genuinely unknown — either way, nothing to do but log it
        // rather than crash the webhook handler.
        tracing::info!(conversation_id = %result.conversation_id, "no pending outbound_mpesa_payments row (already settled, or unknown)");
        return Ok(());
    };
    let wallet_id: Uuid = row.try_get("wallet_id")?;
    let transaction_id: Option<Uuid> = row.try_get("transaction_id")?;
    let amount_usd_cents: i64 = row.try_get("amount_usd_cents")?;

    if result.result_code == 0 {
        let receipt = result.parameter("TransactionReceipt");
        sqlx::query(
            "update outbound_mpesa_payments set status = 'completed', result_desc = $2, completed_at = now()
             where conversation_id = $1",
        )
        .bind(&result.conversation_id)
        .bind(&result.result_desc)
        .execute(&mut *tx)
        .await?;

        sqlx::query(
            "update transactions set status = 'settled', counterparty_name = coalesce($2, counterparty_name)
             where id = $1",
        )
        .bind(transaction_id)
        .bind(receipt)
        .execute(&mut *tx)
        .await?;
    } else {
        // The disbursement failed or timed out on Safaricom's side — the
        // wallet was already debited optimistically when Cash-out was
        // initiated (see `routes/cash_out.rs`), so that has to be
        // reversed, not just the transaction marked failed, or the money
        // simply vanishes from the user's balance with nothing to show
        // for it.
        sqlx::query("update outbound_mpesa_payments set status = 'failed', result_desc = $2 where conversation_id = $1")
            .bind(&result.conversation_id)
            .bind(&result.result_desc)
            .execute(&mut *tx)
            .await?;

        sqlx::query("update wallets set everyday_balance_cents = everyday_balance_cents + $2 where id = $1")
            .bind(wallet_id)
            .bind(amount_usd_cents)
            .execute(&mut *tx)
            .await?;

        // Reversal of the cash_out debit — same kind, opposite direction,
        // so the ledger nets correctly.
        crate::ledger::record(
            &mut tx,
            wallet_id,
            "in",
            amount_usd_cents,
            "cash_out",
            None,
            transaction_id,
        )
        .await?;

        sqlx::query("update transactions set status = 'failed' where id = $1")
            .bind(transaction_id)
            .execute(&mut *tx)
            .await?;
    }

    tx.commit().await?;
    state.notify_balance_change(wallet_id).await;
    Ok(())
}
