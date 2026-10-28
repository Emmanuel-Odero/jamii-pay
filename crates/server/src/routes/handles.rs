use axum::{extract::Query, extract::State, routing::get, Json, Router};
use serde::{Deserialize, Serialize};

use crate::error::{ApiError, ApiResult};
use crate::handle::{compute_check_digit, is_valid_base};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new().route("/handles/availability", get(check_availability))
}

#[derive(Deserialize)]
struct AvailabilityQuery {
    base: String,
}

#[derive(Serialize)]
struct AvailabilityResponse {
    available: bool,
    full_handle: Option<String>,
    check_digit: Option<char>,
    suggestions: Vec<String>,
}

async fn check_availability(
    State(state): State<AppState>,
    Query(query): Query<AvailabilityQuery>,
) -> ApiResult<Json<AvailabilityResponse>> {
    let base = query.base.trim().to_lowercase();
    if !is_valid_base(&base) {
        return Err(ApiError::BadRequest(
            "handle must be 3-20 lowercase letters/digits".to_string(),
        ));
    }

    let check_digit = compute_check_digit(&base);
    let full_handle = format!("{base}{check_digit}");

    let taken: Option<i64> = sqlx::query_scalar("select 1::bigint from handles where full_handle = $1")
        .bind(&full_handle)
        .fetch_optional(&state.db)
        .await?;

    if taken.is_some() {
        // Matches the mockup's suggestion pattern: base + a short suffix,
        // each re-run through the same check-digit function.
        let suggestions = (1..=3)
            .map(|i| {
                let candidate_base = format!("{base}{i}");
                let digit = compute_check_digit(&candidate_base);
                format!("{candidate_base}{digit}")
            })
            .collect();

        return Ok(Json(AvailabilityResponse {
            available: false,
            full_handle: None,
            check_digit: None,
            suggestions,
        }));
    }

    Ok(Json(AvailabilityResponse {
        available: true,
        full_handle: Some(full_handle),
        check_digit: Some(check_digit),
        suggestions: vec![],
    }))
}
