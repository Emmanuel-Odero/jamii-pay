use axum::{
    extract::{Path, State},
    routing::{get, post},
    Json, Router,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

const RECOVERY_WAIT: chrono::Duration = chrono::Duration::hours(48);

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/recovery", post(start_recovery))
        .route("/recovery/:id", get(get_recovery))
        .route("/recovery/:id/approvals", post(approve_recovery))
        .route("/recovery/:id/cancel", post(cancel_recovery))
        .route("/wallets/:id/recovery", get(list_recovery))
}

#[derive(Serialize)]
struct RecoverySummary {
    id: Uuid,
    status: String,
    started_at: DateTime<Utc>,
}

/// Feeds the Notifications screen's "recovery started" entries (see
/// `notifications_screen.dart`) — a real, if minimal, list rather than
/// the fake/coming-soon state the bell icon used to lead nowhere from at
/// all.
async fn list_recovery(State(state): State<AppState>, Path(wallet_id): Path<Uuid>) -> ApiResult<Json<Vec<RecoverySummary>>> {
    let rows = sqlx::query(
        "select id, status, started_at from recovery_requests where wallet_id = $1 order by started_at desc limit 20",
    )
    .bind(wallet_id)
    .fetch_all(&state.db)
    .await?;

    Ok(Json(
        rows.into_iter()
            .map(|r| RecoverySummary {
                id: r.get("id"),
                status: r.get("status"),
                started_at: r.get("started_at"),
            })
            .collect(),
    ))
}

#[derive(Deserialize)]
struct StartRecoveryRequest {
    full_handle: String,
    reported_stolen: bool,
}

#[derive(Serialize)]
struct RecoveryResponse {
    id: Uuid,
    status: String,
    threshold: i32,
    approvals: Vec<String>,
    /// The wallet's configured guardian types — the recovering party may
    /// have no local session (a lost/stolen phone, by definition, has none)
    /// so the client can't source this from anywhere else.
    guardians: Vec<String>,
    started_at: DateTime<Utc>,
    wait_completes_at: Option<DateTime<Utc>>,
}

async fn wallet_guardians(db: &sqlx::PgPool, wallet_id: Uuid) -> Result<Vec<String>, sqlx::Error> {
    sqlx::query_scalar("select guardian_type from guardians where wallet_id = $1")
        .bind(wallet_id)
        .fetch_all(db)
        .await
}

/// Recovery R1 → creates the request. Reachable with only a payment name —
/// no session, no existing login on this device, matching "a recovery flow
/// behind a sign-in wall is not a recovery flow".
async fn start_recovery(
    State(state): State<AppState>,
    Json(req): Json<StartRecoveryRequest>,
) -> ApiResult<Json<RecoveryResponse>> {
    let wallet_id: Uuid =
        sqlx::query_scalar("select wallet_id from handles where full_handle = $1")
            .bind(req.full_handle.trim().to_lowercase())
            .fetch_optional(&state.db)
            .await?
            .ok_or(ApiError::NotFound("no wallet with that payment name"))?;

    let row = sqlx::query(
        "insert into recovery_requests (wallet_id, reported_stolen) values ($1, $2)
         returning id, status, threshold, started_at, wait_completes_at",
    )
    .bind(wallet_id)
    .bind(req.reported_stolen)
    .fetch_one(&state.db)
    .await?;

    let guardians = wallet_guardians(&state.db, wallet_id).await?;

    // Every device on this wallet buzzes — including one the real owner
    // still holds. A recovery the owner didn't start is an attack until
    // proven otherwise; the veto screen is one tap away.
    state
        .push
        .notify_wallet(
            &state.db,
            wallet_id,
            "Recovery started on your wallet",
            "Someone began recovering this wallet. If that wasn't you, open JamiiPay to stop it.",
            "recovery",
        )
        .await;

    Ok(Json(RecoveryResponse {
        id: row.try_get("id")?,
        status: row.try_get("status")?,
        threshold: row.try_get("threshold")?,
        approvals: vec![],
        guardians,
        started_at: row.try_get("started_at")?,
        wait_completes_at: row.try_get("wait_completes_at")?,
    }))
}

async fn get_recovery(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<RecoveryResponse>> {
    let row = sqlx::query(
        "select id, wallet_id, status, threshold, started_at, wait_completes_at
         from recovery_requests where id = $1",
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(ApiError::NotFound("recovery request not found"))?;

    let approvals: Vec<String> = sqlx::query_scalar(
        "select g.guardian_type from recovery_approvals ra
         join guardians g on g.id = ra.guardian_id
         where ra.recovery_request_id = $1",
    )
    .bind(id)
    .fetch_all(&state.db)
    .await?;

    let wallet_id: Uuid = row.try_get("wallet_id")?;
    let guardians = wallet_guardians(&state.db, wallet_id).await?;

    Ok(Json(RecoveryResponse {
        id: row.try_get("id")?,
        status: row.try_get("status")?,
        threshold: row.try_get("threshold")?,
        approvals,
        guardians,
        started_at: row.try_get("started_at")?,
        wait_completes_at: row.try_get("wait_completes_at")?,
    }))
}

#[derive(Deserialize)]
struct ApproveRequest {
    guardian_type: String,
}

/// Recovery R2 — one guardian approving. Once `threshold` approvals are
/// recorded, flips the request to `waiting` and starts the 48-hour clock
/// (R3); every device on the account should be notified here (R4) once a
/// notification channel actually exists — not implemented yet, see
/// `[[recovery_veto_screen.dart]]` for what that notification should show.
async fn approve_recovery(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Json(req): Json<ApproveRequest>,
) -> ApiResult<Json<RecoveryResponse>> {
    let mut tx = state.db.begin().await?;

    let wallet_id: Uuid =
        sqlx::query_scalar("select wallet_id from recovery_requests where id = $1 for update")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await?
            .ok_or(ApiError::NotFound("recovery request not found"))?;

    let guardian_id: Uuid =
        sqlx::query_scalar("select id from guardians where wallet_id = $1 and guardian_type = $2")
            .bind(wallet_id)
            .bind(&req.guardian_type)
            .fetch_optional(&mut *tx)
            .await?
            .ok_or(ApiError::BadRequest(
                "that guardian isn't configured on this wallet".to_string(),
            ))?;

    sqlx::query(
        "insert into recovery_approvals (recovery_request_id, guardian_id) values ($1, $2)
         on conflict do nothing",
    )
    .bind(id)
    .bind(guardian_id)
    .execute(&mut *tx)
    .await?;

    let approval_count: i64 = sqlx::query_scalar(
        "select count(*) from recovery_approvals where recovery_request_id = $1",
    )
    .bind(id)
    .fetch_one(&mut *tx)
    .await?;

    let threshold: i32 =
        sqlx::query_scalar("select threshold from recovery_requests where id = $1")
            .bind(id)
            .fetch_one(&mut *tx)
            .await?;

    if approval_count >= threshold as i64 {
        let wait_completes_at = Utc::now() + RECOVERY_WAIT;
        sqlx::query(
            "update recovery_requests set status = 'waiting', wait_completes_at = $2
             where id = $1 and status = 'pending_approvals'",
        )
        .bind(id)
        .bind(wait_completes_at)
        .execute(&mut *tx)
        .await?;
    }

    tx.commit().await?;

    get_recovery(State(state), Path(id)).await
}

/// Recovery R4's action — the real owner stopping a recovery they didn't
/// start. Also used for the recovering party's own "This wasn't me"
/// cancel path in R3, which maps to the same state transition.
async fn cancel_recovery(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<RecoveryResponse>> {
    sqlx::query(
        "update recovery_requests set status = 'cancelled', cancelled_at = now()
         where id = $1 and status != 'completed'",
    )
    .bind(id)
    .execute(&state.db)
    .await?;

    get_recovery(State(state), Path(id)).await
}
