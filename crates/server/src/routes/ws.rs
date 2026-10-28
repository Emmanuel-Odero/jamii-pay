//! Live balance push — `GET /wallets/:id/ws` upgrades to a WebSocket and
//! streams `{"type":"balance","everyday_balance_usd_cents":...,
//! "savings_balance_usd_cents":...}` every time this wallet's balance
//! actually changes (see `AppState::notify_balance_change`, called from
//! every mutation site after its transaction commits). An initial
//! snapshot is sent immediately on connect so the client never has to
//! wait for the *next* change to know the current balance.

use axum::{
    extract::ws::{Message, WebSocket, WebSocketUpgrade},
    extract::{Path, State},
    response::Response,
    routing::get,
    Router,
};
use sqlx::Row;
use uuid::Uuid;

use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new().route("/wallets/:id/ws", get(upgrade))
}

async fn upgrade(State(state): State<AppState>, Path(wallet_id): Path<Uuid>, ws: WebSocketUpgrade) -> Response {
    ws.on_upgrade(move |socket| handle_socket(socket, state, wallet_id))
}

async fn handle_socket(mut socket: WebSocket, state: AppState, wallet_id: Uuid) {
    let mut rx = state.subscribe_balance(wallet_id);

    // Snapshot on connect — see the module doc comment.
    match sqlx::query("select everyday_balance_cents, savings_balance_cents from wallets where id = $1")
        .bind(wallet_id)
        .fetch_optional(&state.db)
        .await
    {
        Ok(Some(row)) => {
            let everyday: i64 = row.get("everyday_balance_cents");
            let savings: i64 = row.get("savings_balance_cents");
            let snapshot = serde_json::json!({
                "type": "balance",
                "everyday_balance_usd_cents": everyday,
                "savings_balance_usd_cents": savings,
            })
            .to_string();
            if socket.send(Message::Text(snapshot)).await.is_err() {
                return;
            }
        }
        Ok(None) => return, // wallet doesn't exist — nothing to stream
        Err(e) => {
            tracing::warn!(error = %e, %wallet_id, "could not load wallet for ws snapshot");
            return;
        }
    }

    loop {
        tokio::select! {
            update = rx.recv() => {
                match update {
                    Ok(text) => {
                        if socket.send(Message::Text(text)).await.is_err() {
                            break;
                        }
                    }
                    // Lagged — a burst of updates outran a slow client.
                    // Nothing to do but keep going; the client already
                    // has a recent-enough balance and the next update
                    // (or a fresh connect) will catch it up.
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
                }
            }
            incoming = socket.recv() => {
                match incoming {
                    Some(Ok(Message::Close(_))) | None => break,
                    Some(Ok(_)) => {} // this channel is server→client only
                    Some(Err(_)) => break,
                }
            }
        }
    }
}
