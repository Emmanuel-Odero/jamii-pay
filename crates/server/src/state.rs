use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Instant;

use opaque_ke::{ServerLogin, ServerSetup};
use sqlx::postgres::{PgPool, PgPoolOptions};
use tokio::sync::broadcast;
use uuid::Uuid;
use wallet_core::opaque::JamiipayCs;

use crate::seal::Sealer;

/// Pending OPAQUE logins live at most this long. Expiry bounds the map
/// and forces a fresh login for a stale restore attempt — a captured
/// login-start transcript cannot be parked indefinitely.
const OPAQUE_LOGIN_TTL_SECS: u64 = 600;

/// Per-wallet broadcast channels for live balance push — see
/// `routes::ws::wallet_ws` (the client side) and
/// `AppState::notify_balance_change` (every mutation site calls this
/// after committing). One channel per wallet, created lazily on first
/// subscribe or first notify; `broadcast::Sender` is cheap to hold even
/// with zero subscribers (a send with none just returns an `Err` we
/// ignore — see `notify_balance_change`).
#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    /// Envelope sealer for backup shares. Built once at boot from
    /// `BACKUP_SEAL_KEY` (or ephemeral for local dev) — see `seal.rs`.
    pub sealer: Arc<Sealer>,
    /// Remote-push sender (APNs). Built once at boot; unprovisioned (no
    /// `APNS_*` env) means silent no-op sends — see `push.rs`.
    pub push: crate::push::PushSender,
    /// In-flight OPAQUE server logins, keyed by the `login_id` handed to
    /// the client. Never persisted: a restart drops pending logins and the
    /// client simply starts a new one. Restart-safe because nothing
    /// committed depends on them.
    opaque_logins: Arc<Mutex<HashMap<Uuid, (ServerLogin<JamiipayCs>, Instant)>>>,
    balance_channels: Arc<Mutex<HashMap<Uuid, broadcast::Sender<String>>>>,
}

impl AppState {
    pub async fn connect(database_url: &str) -> anyhow::Result<Self> {
        let db = PgPoolOptions::new()
            .max_connections(10)
            .connect(database_url)
            .await?;

        sqlx::migrate!("./migrations").run(&db).await?;

        let sealer = Sealer::from_env().map_err(|e| anyhow::anyhow!(e.to_string()))?;

        Ok(Self {
            db,
            sealer: Arc::new(sealer),
            push: crate::push::PushSender::from_env(),
            opaque_logins: Arc::new(Mutex::new(HashMap::new())),
            balance_channels: Arc::new(Mutex::new(HashMap::new())),
        })
    }

    /// Loads the OPAQUE ServerSetup, creating and persisting it on first
    /// boot. The setup is the server's long-term OPAQUE identity: rotating
    /// it invalidates every stored password file, so it is versioned by
    /// row (`opaque_setup`), never overwritten.
    pub async fn opaque_setup(&self) -> anyhow::Result<ServerSetup<JamiipayCs>> {
        if let Some(bytes) = sqlx::query_scalar::<_, Vec<u8>>(
            "select value from server_secrets where name = 'opaque_setup'",
        )
        .fetch_optional(&self.db)
        .await?
        {
            let setup = ServerSetup::<JamiipayCs>::deserialize(&bytes)
                .map_err(|_| anyhow::anyhow!("stored OPAQUE setup is corrupt"))?;
            return Ok(setup);
        }
        let mut rng = rand::rngs::OsRng;
        let setup = ServerSetup::<JamiipayCs>::new(&mut rng);
        sqlx::query(
            "insert into server_secrets (name, value) values ('opaque_setup', $1)
             on conflict (name) do nothing",
        )
        .bind(setup.serialize().to_vec())
        .execute(&self.db)
        .await?;
        // A concurrent boot may have won the race — re-read to converge.
        let bytes = sqlx::query_scalar::<_, Vec<u8>>(
            "select value from server_secrets where name = 'opaque_setup'",
        )
        .fetch_one(&self.db)
        .await?;
        ServerSetup::<JamiipayCs>::deserialize(&bytes)
            .map_err(|_| anyhow::anyhow!("stored OPAQUE setup is corrupt"))
    }

    /// Holds a pending login for its TTL. Prunes expired entries on every
    /// insert so abandoned attempts cannot grow the map.
    pub fn opaque_login_insert(&self, login: ServerLogin<JamiipayCs>) -> Uuid {
        let id = Uuid::new_v4();
        if let Ok(mut map) = self.opaque_logins.lock() {
            let now = Instant::now();
            map.retain(|_, (_, at)| now.duration_since(*at).as_secs() < OPAQUE_LOGIN_TTL_SECS);
            map.insert(id, (login, now));
        }
        id
    }

    pub fn opaque_login_take(&self, id: &Uuid) -> Option<ServerLogin<JamiipayCs>> {
        let mut map = self.opaque_logins.lock().ok()?;
        let (login, at) = map.remove(id)?;
        if at.elapsed().as_secs() >= OPAQUE_LOGIN_TTL_SECS {
            return None;
        }
        Some(login)
    }

    /// Called by `routes::ws::wallet_ws` when a client connects — every
    /// subscriber for a given wallet shares the same underlying channel.
    pub fn subscribe_balance(&self, wallet_id: Uuid) -> broadcast::Receiver<String> {
        let mut channels = self.balance_channels.lock().unwrap();
        channels.entry(wallet_id).or_insert_with(|| broadcast::channel(16).0).subscribe()
    }

    /// Fetches this wallet's current balances and pushes them to every
    /// connected client. Called after every commit that touches
    /// `everyday_balance_cents`/`savings_balance_cents` — see
    /// `routes/wallets.rs`, `routes/cash_out.rs`, `routes/groups.rs`,
    /// `routes/mpesa.rs`. A no-op (not an error) when nobody's listening.
    pub async fn notify_balance_change(&self, wallet_id: Uuid) {
        let row = match sqlx::query_as::<_, (i64, i64)>(
            "select everyday_balance_cents, savings_balance_cents from wallets where id = $1",
        )
        .bind(wallet_id)
        .fetch_optional(&self.db)
        .await
        {
            Ok(Some(row)) => row,
            Ok(None) => return,
            Err(e) => {
                tracing::warn!(error = %e, %wallet_id, "could not load balance for push notify");
                return;
            }
        };

        let payload = serde_json::json!({
            "type": "balance",
            "everyday_balance_usd_cents": row.0,
            "savings_balance_usd_cents": row.1,
        })
        .to_string();

        let sender = {
            let channels = self.balance_channels.lock().unwrap();
            channels.get(&wallet_id).cloned()
        };
        if let Some(sender) = sender {
            let _ = sender.send(payload); // Err just means nobody's connected right now
        }
    }
}
