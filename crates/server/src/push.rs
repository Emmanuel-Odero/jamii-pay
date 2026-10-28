//! Remote push (Apple Push Notification service) — the path that reaches a
//! phone with the app fully closed and the screen locked, where local
//! notifications cannot go (iOS suspends the app's timers and sockets
//! within ~30s of backgrounding; after force-quit nothing on-device runs
//! at all).
//!
//! Design rules:
//! - **Best-effort, never load-bearing.** Every send error is a
//!   `tracing::warn`, never an `Err` to the money/message handler. A push
//!   outage must not move, delay, or roll back a single cent.
//! - **No credentials on the wire that replay.** Device tokens are
//!   unguessable per-install identifiers, useless without Apple's APNs
//!   keys. Stale tokens (reinstalls) are pruned on APNs 410 Gone.
//! - **Unconfigured = silent, not broken.** Without `APNS_*` env (needs an
//!   Apple Developer APNs Auth Key — see below), all sends are skipped
//!   with one warn at boot. Everything else works exactly as before.
//!
//! Setup (one time, Apple Developer account holder):
//! 1. developer.apple.com → Certificates, Identifiers & Profiles → Keys →
//!    create key with Apple Push Notifications Service → note Key ID,
//!    download the `.p8` (once — Apple never shows it again).
//! 2. Set env: `APNS_TEAM_ID` (10-char Team ID), `APNS_KEY_ID`,
//!    `APNS_KEY_P8` (PEM contents) or `APNS_KEY_P8_FILE` (path),
//!    `APNS_BUNDLE_ID` (default `com.jamiipay.jamiipay`),
//!    `APNS_SANDBOX=1` for dev builds / `0` for TestFlight+release
//!    (Apple runs separate sandbox/production push environments; a dev
//!    token on the production endpoint fails, loudly logged).
//! 3. The app registers its token on every launch (see
//!    `PushService` on the Dart side + `DeviceVaultPlugin` push methods).

use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use axum::{
    extract::{Path, State},
    routing::{delete, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/wallets/:id/push-tokens", post(register_token))
        .route("/wallets/:id/push-tokens/:token", delete(unregister_token))
}

/// APNs provider token (JWT, ES256): `iss` = Team ID, signed by the Auth
/// Key, refreshed every 55 minutes (Apple's cap is 60).
struct ProviderToken {
    jwt: String,
    expires_at: SystemTime,
}

pub struct ApnsConfig {
    team_id: String,
    key_id: String,
    key_pem: Vec<u8>,
    bundle_id: String,
    sandbox: bool,
    token: Mutex<Option<ProviderToken>>,
}

impl ApnsConfig {
    /// Reads config from the environment. Returns `None` (push disabled)
    /// when the APNs key is absent — the normal state for local dev until
    /// the Apple key is provisioned.
    pub fn from_env() -> Option<Self> {
        let key_pem = std::env::var("APNS_KEY_P8_FILE")
            .ok()
            .and_then(|p| std::fs::read(p).ok())
            .or_else(|| std::env::var("APNS_KEY_P8").ok().map(|s| s.into_bytes()))?;
        if key_pem.is_empty() {
            return None;
        }
        Some(Self {
            team_id: std::env::var("APNS_TEAM_ID").ok()?,
            key_id: std::env::var("APNS_KEY_ID").ok()?,
            key_pem,
            bundle_id: std::env::var("APNS_BUNDLE_ID")
                .unwrap_or_else(|_| "com.jamiipay.jamiipay".to_string()),
            sandbox: std::env::var("APNS_SANDBOX").map(|v| v != "0").unwrap_or(true),
            token: Mutex::new(None),
        })
    }

    fn endpoint(&self) -> &'static str {
        if self.sandbox {
            "https://api.sandbox.push.apple.com"
        } else {
            "https://api.push.apple.com"
        }
    }

    /// Returns a valid provider JWT, minting + caching per Apple's rules.
    /// Lock is never held across IO — minting happens outside it.
    fn provider_jwt(&self) -> Result<String, String> {
        if let Ok(guard) = self.token.lock() {
            if let Some(t) = guard.as_ref() {
                if SystemTime::now() + Duration::from_secs(60) < t.expires_at {
                    return Ok(t.jwt.clone());
                }
            }
        }
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|e| e.to_string())?
            .as_secs();
        let mut header = jsonwebtoken::Header::new(jsonwebtoken::Algorithm::ES256);
        header.kid = Some(self.key_id.clone());
        let claims = serde_json::json!({ "iss": self.team_id, "iat": now });
        let key = jsonwebtoken::EncodingKey::from_ec_pem(&self.key_pem)
            .map_err(|e| format!("bad APNs key: {e}"))?;
        let jwt =
            jsonwebtoken::encode(&header, &claims, &key).map_err(|e| format!("JWT mint failed: {e}"))?;
        let expires_at = SystemTime::now() + Duration::from_secs(55 * 60);
        if let Ok(mut guard) = self.token.lock() {
            *guard = Some(ProviderToken { jwt: jwt.clone(), expires_at });
        }
        Ok(jwt)
    }
}

#[derive(Deserialize)]
struct RegisterTokenRequest {
    token: String,
    #[serde(default = "default_platform")]
    platform: String,
}

fn default_platform() -> String {
    "ios".to_string()
}

/// Registers (or refreshes) a device token. Upsert-always: reinstalls mint
/// new tokens and the old row simply lingers until APNs 410-prunes it.
async fn register_token(
    State(state): State<AppState>,
    Path(wallet_id): Path<Uuid>,
    Json(req): Json<RegisterTokenRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    let token = req.token.trim().to_lowercase();
    if token.len() != 64 || hex::decode(&token).is_err() {
        return Err(ApiError::BadRequest("invalid device token".to_string()));
    }
    if req.platform != "ios" && req.platform != "android" {
        return Err(ApiError::BadRequest("unknown platform".to_string()));
    }
    sqlx::query("select id from wallets where id = $1")
        .bind(wallet_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(ApiError::NotFound("no wallet with that id"))?;
    sqlx::query(
        "insert into push_tokens (wallet_id, token, platform, last_used_at)
         values ($1, $2, $3, now())
         on conflict (wallet_id, token) do update
         set platform = excluded.platform, last_used_at = now()",
    )
    .bind(wallet_id)
    .bind(&token)
    .bind(&req.platform)
    .execute(&state.db)
    .await?;
    Ok(Json(serde_json::json!({"ok": true})))
}

async fn unregister_token(
    State(state): State<AppState>,
    Path((wallet_id, token)): Path<(Uuid, String)>,
) -> ApiResult<Json<serde_json::Value>> {
    sqlx::query("delete from push_tokens where wallet_id = $1 and token = $2")
        .bind(wallet_id)
        .bind(token.trim().to_lowercase())
        .execute(&state.db)
        .await?;
    Ok(Json(serde_json::json!({"ok": true})))
}

/// Send outcome: delivered, and whether Apple says the token is dead
/// (410 Gone → prune; reinstalls are the common case).
struct SendOutcome {
    delivered: bool,
    dead_token: bool,
}

impl SendOutcome {
    fn failed() -> Self {
        Self { delivered: false, dead_token: false }
    }
}

/// Sends one APNs push. Every failure is a logged `SendOutcome::failed`,
/// never an error — callers (money/message handlers) must not move, delay,
/// or roll back on push.
async fn send_apns(
    http: &reqwest::Client,
    config: &ApnsConfig,
    token: &str,
    title: &str,
    body: &str,
    badge: i32,
    kind: &str,
    wallet_id: Uuid,
) -> SendOutcome {
    let jwt = match config.provider_jwt() {
        Ok(jwt) => jwt,
        Err(e) => {
            tracing::warn!(error = %e, "APNs JWT mint failed");
            return SendOutcome::failed();
        }
    };
    let payload = serde_json::json!({
        "aps": {
            "alert": { "title": title, "body": body },
            "sound": "default",
            "badge": badge,
        },
        "type": kind,
        "wallet_id": wallet_id.to_string(),
    });
    let res = http
        .post(format!("{}/3/device/{token}", config.endpoint()))
        .bearer_auth(jwt)
        .header("apns-topic", &config.bundle_id)
        .header("apns-push-type", "alert")
        .header("apns-priority", "10")
        .json(&payload)
        .send()
        .await;
    match res {
        Err(e) => {
            tracing::warn!(error = %e, kind, "APNs transport failed");
            SendOutcome::failed()
        }
        Ok(resp) => {
            let status = resp.status();
            if status.is_success() {
                return SendOutcome { delivered: true, dead_token: false };
            }
            // 410 = token dead (reinstall); 400/403 = config/token wrong —
            // both logged with Apple's reason for operability.
            let reason = resp.text().await.unwrap_or_default();
            tracing::warn!(%status, reason = %reason.chars().take(200).collect::<String>(), kind, "APNs rejected push");
            SendOutcome {
                delivered: false,
                dead_token: status.as_u16() == 410,
            }
        }
    }
}

/// Cached sender: config + HTTP client built once at boot, shared by every
/// trigger. `None` inside means push was never provisioned (no `APNS_*`
/// env) — sends become silent no-ops and everything else works as before.
#[derive(Clone)]
pub struct PushSender {
    inner: Option<Arc<PushInner>>,
}

struct PushInner {
    config: ApnsConfig,
    http: reqwest::Client,
}

impl PushSender {
    pub fn from_env() -> Self {
        let inner = ApnsConfig::from_env().map(|config| {
            if config.sandbox {
                tracing::info!("APNs configured (SANDBOX — dev builds only)");
            } else {
                tracing::info!("APNs configured (PRODUCTION)");
            }
            Arc::new(PushInner {
                config,
                http: reqwest::Client::builder()
                    .timeout(std::time::Duration::from_secs(10))
                    .build()
                    .unwrap_or_else(|_| reqwest::Client::new()),
            })
        });
        if inner.is_none() {
            tracing::warn!(
                "APNs not provisioned (no APNS_KEY_P8*) — remote push disabled, local notifications only. See push.rs header for setup."
            );
        }
        Self { inner }
    }

    /// Best-effort fan-out to every registered device of a wallet. Computes
    /// a badge (pending escrow claims + pending group invites, floors at 1
    /// so a delivered banner always shows *something*), sends, prunes dead
    /// tokens. Never fails callers — push must not move, delay, or roll
    /// back anything.
    pub async fn notify_wallet(
        &self,
        db: &sqlx::PgPool,
        wallet_id: Uuid,
        title: &str,
        body: &str,
        kind: &str,
    ) {
        let inner = match &self.inner {
            Some(inner) => inner,
            None => return, // push not provisioned — local notifications only
        };
        let tokens: Vec<(String, String)> = match sqlx::query_as(
            "select token, platform from push_tokens where wallet_id = $1",
        )
        .bind(wallet_id)
        .fetch_all(db)
        .await
        {
            Ok(rows) => rows,
            Err(e) => {
                tracing::warn!(error = %e, "push token lookup failed");
                return;
            }
        };
        if tokens.is_empty() {
            return;
        }
        let badge = badge_for(db, wallet_id).await;
        for (token, platform) in tokens {
            if platform != "ios" {
                // Android needs a Firebase project + FCM v1 sender —
                // tracked as the documented follow-up; iOS ships first
                // (this fleet is iPhones). Warned, not silently dropped.
                tracing::warn!(platform = %platform, "no sender for platform yet");
                continue;
            }
            let outcome =
                send_apns(&inner.http, &inner.config, &token, title, body, badge, kind, wallet_id)
                    .await;
            if outcome.dead_token {
                // Reinstalls are the common case, not attacks.
                prune_token(db, wallet_id, &token).await;
            }
            if outcome.delivered {
                let _ = sqlx::query(
                    "update push_tokens set last_used_at = now() where wallet_id = $1 and token = $2",
                )
                .bind(wallet_id)
                .bind(&token)
                .execute(db)
                .await;
            }
        }
    }
}

/// Icon-badge numerator: pending escrow claims + pending group invites.
/// Floors at 1 — a push that arrives with badge 0 would clear a badge the
/// user hasn't seen yet.
async fn badge_for(db: &sqlx::PgPool, wallet_id: Uuid) -> i32 {
    let claims: i64 = sqlx::query_scalar(
        "select count(*) from claims where wallet_id = $1 and status = 'pending'",
    )
    .bind(wallet_id)
    .fetch_one(db)
    .await
    .unwrap_or(0);
    let invites: i64 = sqlx::query_scalar(
        "select count(*) from group_withdrawal_requests
         where new_member_wallet_id = $1 and action_type = 'add_member' and invite_status = 'pending'",
    )
    .bind(wallet_id)
    .fetch_one(db)
    .await
    .unwrap_or(0);
    (claims + invites).max(1).min(999) as i32
}

/// Prunes a dead token. Called when APNs answers 410 Gone (reinstalls are
/// the common case).
pub async fn prune_token(db: &sqlx::PgPool, wallet_id: Uuid, token: &str) {
    let _ = sqlx::query("delete from push_tokens where wallet_id = $1 and token = $2")
        .bind(wallet_id)
        .bind(token)
        .execute(db)
        .await;
}
