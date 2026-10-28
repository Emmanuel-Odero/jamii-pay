mod alerts;
mod backups;
mod card_topup;
mod cash_out;
mod contacts;
mod escrow;
mod fx;
mod groups;
mod handles;
mod health;
mod messages;
mod mpesa;
mod recovery;
mod send_to_mpesa;
mod wallets;
mod ws;

use axum::Router;
use tower_http::cors::{Any, CorsLayer};

use crate::state::AppState;

pub fn router(state: AppState) -> Router {
    // Permissive for local dev (the Flutter web target runs on a different
    // origin/port than this server) — tighten to specific origins before
    // any non-local deployment.
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    Router::new()
        .merge(health::router())
        .merge(handles::router())
        .merge(fx::router())
        .merge(wallets::router())
        .merge(recovery::router())
        .merge(cash_out::router())
        .merge(card_topup::router())
        .merge(contacts::router())
        .merge(groups::router())
        .merge(escrow::router())
        .merge(alerts::router())
        .merge(backups::router())
        .merge(messages::router())
        .merge(mpesa::router())
        .merge(send_to_mpesa::router())
        .merge(ws::router())
        .merge(crate::ledger::router())
        .merge(crate::push::router())
        .layer(cors)
        .with_state(state)
}
