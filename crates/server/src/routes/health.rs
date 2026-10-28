use axum::{extract::State, routing::get, Json, Router};
use serde::Serialize;

use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/health", get(health))
        .route("/health/db", get(health_db))
}

#[derive(Serialize)]
struct Health {
    status: &'static str,
}

async fn health() -> Json<Health> {
    Json(Health { status: "ok" })
}

async fn health_db(State(state): State<AppState>) -> Json<Health> {
    match sqlx::query("select 1").fetch_one(&state.db).await {
        Ok(_) => Json(Health { status: "ok" }),
        Err(_) => Json(Health {
            status: "db_unreachable",
        }),
    }
}
