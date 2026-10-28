use axum::{
    extract::{Path, State},
    routing::get,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new().route(
        "/wallets/:id/alert-preferences",
        get(get_preferences).put(update_preferences),
    )
}

/// The prototype's own default matrix — see `SCR.alerts`'s static rows.
/// `recovery_started` gets every channel and is never user-editable (see
/// `update_preferences`).
const DEFAULTS: &[(&str, bool, bool, bool)] = &[
    ("money_arrives", true, true, false),
    ("money_sent", false, true, false),
    ("claim_expiring", true, false, true),
    ("group_vote_opened", false, true, false),
    ("recovery_started", true, true, true),
];

/// Called once from `create_wallet` (same transaction) — every wallet
/// gets a full row per event from the moment it exists, so `GET` never
/// has to backfill or guess at unset defaults.
pub async fn seed_defaults(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    wallet_id: Uuid,
) -> Result<(), sqlx::Error> {
    for (event_key, sms, push, email) in DEFAULTS {
        sqlx::query(
            "insert into alert_preferences (wallet_id, event_key, sms, push, email) values ($1, $2, $3, $4, $5)",
        )
        .bind(wallet_id)
        .bind(event_key)
        .bind(sms)
        .bind(push)
        .bind(email)
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}

#[derive(Serialize)]
struct EventPreference {
    event_key: String,
    sms: bool,
    push: bool,
    email: bool,
    /// `true` only for `recovery_started` — the client renders this row
    /// disabled with the prototype's override-copy banner instead of
    /// switches.
    locked: bool,
}

async fn get_preferences(State(state): State<AppState>, Path(wallet_id): Path<Uuid>) -> ApiResult<Json<Vec<EventPreference>>> {
    let rows = sqlx::query(
        "select event_key, sms, push, email from alert_preferences where wallet_id = $1 order by event_key",
    )
    .bind(wallet_id)
    .fetch_all(&state.db)
    .await?;

    if rows.is_empty() {
        return Err(ApiError::NotFound("wallet not found, or has no alert preferences"));
    }

    Ok(Json(
        rows.into_iter()
            .map(|r| {
                let event_key: String = r.get("event_key");
                let locked = event_key == "recovery_started";
                EventPreference {
                    event_key,
                    sms: r.get("sms"),
                    push: r.get("push"),
                    email: r.get("email"),
                    locked,
                }
            })
            .collect(),
    ))
}

#[derive(Deserialize)]
struct UpdatePreferencesRequest {
    preferences: Vec<UpdateOne>,
}

#[derive(Deserialize)]
struct UpdateOne {
    event_key: String,
    sms: bool,
    push: bool,
    email: bool,
}

async fn update_preferences(
    State(state): State<AppState>,
    Path(wallet_id): Path<Uuid>,
    Json(req): Json<UpdatePreferencesRequest>,
) -> ApiResult<Json<Vec<EventPreference>>> {
    for pref in &req.preferences {
        if pref.event_key == "recovery_started" {
            return Err(ApiError::BadRequest(
                "recovery_started alerts can't be changed — they override quiet hours by design".to_string(),
            ));
        }
        if !DEFAULTS.iter().any(|(k, ..)| *k == pref.event_key) {
            return Err(ApiError::BadRequest(format!("unknown event: {}", pref.event_key)));
        }

        sqlx::query(
            "update alert_preferences set sms = $3, push = $4, email = $5
             where wallet_id = $1 and event_key = $2",
        )
        .bind(wallet_id)
        .bind(&pref.event_key)
        .bind(pref.sms)
        .bind(pref.push)
        .bind(pref.email)
        .execute(&state.db)
        .await?;
    }

    get_preferences(State(state), Path(wallet_id)).await
}
