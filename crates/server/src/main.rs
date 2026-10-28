//! JamiiPay backend. Axum HTTP API + SQLx/Postgres, built on top of
//! wallet-core for anything that touches key material or signing.

mod daraja;
mod error;
mod group_vote;
mod handle;
mod ledger;
mod pin_verifier;
mod push;
mod routes;
mod seal;
mod state;

use std::net::SocketAddr;

use tracing_subscriber::EnvFilter;

use crate::state::AppState;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://jamiipay:jamiipay@localhost:5432/jamiipay".to_string());

    let state = AppState::connect(&database_url).await?;
    let app = routes::router(state);

    let addr: SocketAddr = std::env::var("BIND_ADDR")
        .unwrap_or_else(|_| "0.0.0.0:8080".to_string())
        .parse()?;

    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!(%addr, "jamiipay-server listening");
    axum::serve(listener, app).await?;

    Ok(())
}
