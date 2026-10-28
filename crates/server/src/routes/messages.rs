//! 66-character chat — groups and direct (contact-to-contact) messaging.
//! Deliberately no websocket/live-push infra yet: the client polls
//! `GET .../messages` on a short interval (see `ChatScreen`), which is
//! "live enough" for a payments app's quick nudges without standing up
//! a new transport. Swap in a push channel later without changing this
//! module's shape if latency ever actually matters.

use axum::{
    extract::{Path, Query, State},
    routing::post,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/groups/:id/messages", post(send_group_message).get(list_group_messages))
        .route("/wallets/:id/messages/direct/:other_id", post(send_direct_message).get(list_direct_messages))
        .route("/messages/:id/pin", post(set_pinned))
        .route("/wallets/:id/conversations", axum::routing::get(list_conversations))
}

/// One conversation thread — a direct chat partner or a group with at
/// least one message. Backs the inbox's Contacts/Spam split:
/// `is_contact` is `None` for a group thread (the split only applies to
/// direct messages — a group is never "spam", you were invited into it
/// by name), `Some(false)` for a direct sender who isn't in this
/// wallet's Contacts yet — exactly the case the client routes to Spam.
#[derive(Serialize)]
struct ConversationResponse {
    kind: String, // "direct" | "group"
    id: Uuid,     // other wallet's id (direct) or the group's id
    name: String,
    last_message: String,
    last_message_at: chrono::DateTime<chrono::Utc>,
    /// Who sent [`last_message`] — the client uses this to tell "someone
    /// just messaged me" (worth a notification) apart from "I just sent
    /// this myself" (not).
    last_message_sender_wallet_id: Uuid,
    is_contact: Option<bool>,
}

async fn list_conversations(State(state): State<AppState>, Path(wallet_id): Path<Uuid>) -> ApiResult<Json<Vec<ConversationResponse>>> {
    let direct_rows = sqlx::query(
        "select distinct on (other_wallet_id) other_wallet_id, body, created_at, sender_wallet_id from (
            select case when wallet_a_id = $1 then wallet_b_id else wallet_a_id end as other_wallet_id, body, created_at, sender_wallet_id
            from messages where conversation_kind = 'direct' and (wallet_a_id = $1 or wallet_b_id = $1)
         ) t
         order by other_wallet_id, created_at desc",
    )
    .bind(wallet_id)
    .fetch_all(&state.db)
    .await?;

    let mut out = Vec::with_capacity(direct_rows.len());
    for row in direct_rows {
        let other_wallet_id: Uuid = row.try_get("other_wallet_id")?;
        let name: Option<String> = sqlx::query_scalar(
            "select h.full_handle from wallets w left join handles h on h.wallet_id = w.id where w.id = $1",
        )
        .bind(other_wallet_id)
        .fetch_optional(&state.db)
        .await?;
        let is_contact: bool =
            sqlx::query_scalar("select exists(select 1 from contacts where owner_wallet_id = $1 and linked_wallet_id = $2)")
                .bind(wallet_id)
                .bind(other_wallet_id)
                .fetch_one(&state.db)
                .await?;
        out.push(ConversationResponse {
            kind: "direct".to_string(),
            id: other_wallet_id,
            name: name.unwrap_or_else(|| "Unknown".to_string()),
            last_message: row.try_get("body")?,
            last_message_at: row.try_get("created_at")?,
            last_message_sender_wallet_id: row.try_get("sender_wallet_id")?,
            is_contact: Some(is_contact),
        });
    }

    let group_rows = sqlx::query(
        "select g.id as group_id, g.name as group_name, m.body, m.created_at, m.sender_wallet_id
         from group_members gm
         join groups g on g.id = gm.group_id
         join lateral (
             select body, created_at, sender_wallet_id from messages where group_id = g.id order by created_at desc limit 1
         ) m on true
         where gm.wallet_id = $1 and gm.active = true",
    )
    .bind(wallet_id)
    .fetch_all(&state.db)
    .await?;
    for row in group_rows {
        out.push(ConversationResponse {
            kind: "group".to_string(),
            id: row.try_get("group_id")?,
            name: row.try_get("group_name")?,
            last_message: row.try_get("body")?,
            last_message_at: row.try_get("created_at")?,
            last_message_sender_wallet_id: row.try_get("sender_wallet_id")?,
            is_contact: None,
        });
    }

    out.sort_by(|a, b| b.last_message_at.cmp(&a.last_message_at));
    Ok(Json(out))
}

fn validate_body(body: &str) -> ApiResult<String> {
    let trimmed = body.trim().to_string();
    if trimmed.is_empty() {
        return Err(ApiError::BadRequest("message can't be empty".to_string()));
    }
    if trimmed.chars().count() > 66 {
        return Err(ApiError::BadRequest("messages are capped at 66 characters".to_string()));
    }
    Ok(trimmed)
}

#[derive(Serialize)]
struct MessageResponse {
    id: Uuid,
    sender_wallet_id: Uuid,
    sender_name: String,
    body: String,
    reply_to_id: Option<Uuid>,
    /// A short "replying to" preview — `None` when [`reply_to_id`] is
    /// `None`, so the client never has to fetch the parent separately.
    reply_to_preview: Option<String>,
    pinned: bool,
    created_at: chrono::DateTime<chrono::Utc>,
}

async fn resolve_reply_preview(db: &sqlx::PgPool, reply_to_id: Option<Uuid>) -> ApiResult<Option<String>> {
    let Some(id) = reply_to_id else { return Ok(None) };
    let body: Option<String> = sqlx::query_scalar("select body from messages where id = $1").bind(id).fetch_optional(db).await?;
    Ok(body)
}

#[derive(Deserialize)]
struct SendMessageRequest {
    sender_wallet_id: Uuid,
    body: String,
    reply_to_id: Option<Uuid>,
}

async fn send_group_message(
    State(state): State<AppState>,
    Path(group_id): Path<Uuid>,
    Json(req): Json<SendMessageRequest>,
) -> ApiResult<Json<MessageResponse>> {
    let body = validate_body(&req.body)?;

    let sender_name: String = sqlx::query_scalar(
        "select contact_name from group_members where group_id = $1 and wallet_id = $2 and active = true",
    )
    .bind(group_id)
    .bind(req.sender_wallet_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(ApiError::BadRequest("not an active member of this group".to_string()))?;

    let row = sqlx::query(
        "insert into messages (conversation_kind, group_id, sender_wallet_id, body, reply_to_id)
         values ('group', $1, $2, $3, $4)
         returning id, pinned, created_at",
    )
    .bind(group_id)
    .bind(req.sender_wallet_id)
    .bind(&body)
    .bind(req.reply_to_id)
    .fetch_one(&state.db)
    .await?;

    // Remote push to every other active member. Best-effort — a push
    // outage must never fail a sent message.
    let group_name: Option<String> =
        sqlx::query_scalar("select name from groups where id = $1")
            .bind(group_id)
            .fetch_optional(&state.db)
            .await?
            .flatten();
    let member_ids: Vec<Uuid> = sqlx::query_scalar(
        "select wallet_id from group_members where group_id = $1 and active = true and wallet_id != $2",
    )
    .bind(group_id)
    .bind(req.sender_wallet_id)
    .fetch_all(&state.db)
    .await?;
    let preview: String = body.chars().take(80).collect();
    for member_id in member_ids {
        state
            .push
            .notify_wallet(
                &state.db,
                member_id,
                &group_name.clone().unwrap_or_else(|| "New group message".to_string()),
                &format!("{sender_name}: {preview}"),
                "message",
            )
            .await;
    }

    Ok(Json(MessageResponse {
        id: row.try_get("id")?,
        sender_wallet_id: req.sender_wallet_id,
        sender_name,
        body,
        reply_to_id: req.reply_to_id,
        reply_to_preview: resolve_reply_preview(&state.db, req.reply_to_id).await?,
        pinned: row.try_get("pinned")?,
        created_at: row.try_get("created_at")?,
    }))
}

#[derive(Deserialize)]
struct ListMessagesQuery {
    /// Unused by the group route today (kept for a future "mark read"
    /// feature) but required so the client always sends it consistently
    /// with the direct-chat route.
    #[allow(dead_code)]
    wallet_id: Option<Uuid>,
}

async fn list_group_messages(
    State(state): State<AppState>,
    Path(group_id): Path<Uuid>,
    Query(_query): Query<ListMessagesQuery>,
) -> ApiResult<Json<Vec<MessageResponse>>> {
    let rows = sqlx::query(
        "select m.id, m.sender_wallet_id, m.body, m.reply_to_id, m.pinned, m.created_at,
                coalesce(gm.contact_name, 'Former member') as sender_name
         from messages m
         left join group_members gm on gm.group_id = m.group_id and gm.wallet_id = m.sender_wallet_id
         where m.group_id = $1
         order by m.created_at asc",
    )
    .bind(group_id)
    .fetch_all(&state.db)
    .await?;

    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        let reply_to_id: Option<Uuid> = row.try_get("reply_to_id")?;
        out.push(MessageResponse {
            id: row.try_get("id")?,
            sender_wallet_id: row.try_get("sender_wallet_id")?,
            sender_name: row.try_get("sender_name")?,
            body: row.try_get("body")?,
            reply_to_id,
            reply_to_preview: resolve_reply_preview(&state.db, reply_to_id).await?,
            pinned: row.try_get("pinned")?,
            created_at: row.try_get("created_at")?,
        });
    }
    Ok(Json(out))
}

async fn send_direct_message(
    State(state): State<AppState>,
    Path((wallet_id, other_id)): Path<(Uuid, Uuid)>,
    Json(req): Json<SendMessageRequest>,
) -> ApiResult<Json<MessageResponse>> {
    let body = validate_body(&req.body)?;
    if req.sender_wallet_id != wallet_id {
        return Err(ApiError::BadRequest("sender_wallet_id must match the URL".to_string()));
    }

    let (wallet_a, wallet_b) = if wallet_id < other_id { (wallet_id, other_id) } else { (other_id, wallet_id) };

    let sender_name: String = sqlx::query_scalar(
        "select h.full_handle from wallets w left join handles h on h.wallet_id = w.id where w.id = $1",
    )
    .bind(wallet_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(ApiError::NotFound("sender wallet not found"))?;

    let row = sqlx::query(
        "insert into messages (conversation_kind, wallet_a_id, wallet_b_id, sender_wallet_id, body, reply_to_id)
         values ('direct', $1, $2, $3, $4, $5)
         returning id, pinned, created_at",
    )
    .bind(wallet_a)
    .bind(wallet_b)
    .bind(wallet_id)
    .bind(&body)
    .bind(req.reply_to_id)
    .fetch_one(&state.db)
    .await?;

    // The other party may have the app fully closed — this is exactly the
    // case local notifications cannot cover.
    let preview: String = body.chars().take(80).collect();
    state
        .push
        .notify_wallet(
            &state.db,
            other_id,
            &format!("New message from {sender_name}"),
            &preview,
            "message",
        )
        .await;

    Ok(Json(MessageResponse {
        id: row.try_get("id")?,
        sender_wallet_id: wallet_id,
        sender_name,
        body,
        reply_to_id: req.reply_to_id,
        reply_to_preview: resolve_reply_preview(&state.db, req.reply_to_id).await?,
        pinned: row.try_get("pinned")?,
        created_at: row.try_get("created_at")?,
    }))
}

async fn list_direct_messages(
    State(state): State<AppState>,
    Path((wallet_id, other_id)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<Vec<MessageResponse>>> {
    let (wallet_a, wallet_b) = if wallet_id < other_id { (wallet_id, other_id) } else { (other_id, wallet_id) };

    let rows = sqlx::query(
        "select m.id, m.sender_wallet_id, m.body, m.reply_to_id, m.pinned, m.created_at,
                coalesce(h.full_handle, 'Unknown') as sender_name
         from messages m
         left join handles h on h.wallet_id = m.sender_wallet_id
         where m.wallet_a_id = $1 and m.wallet_b_id = $2
         order by m.created_at asc",
    )
    .bind(wallet_a)
    .bind(wallet_b)
    .fetch_all(&state.db)
    .await?;

    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        let reply_to_id: Option<Uuid> = row.try_get("reply_to_id")?;
        out.push(MessageResponse {
            id: row.try_get("id")?,
            sender_wallet_id: row.try_get("sender_wallet_id")?,
            sender_name: row.try_get("sender_name")?,
            body: row.try_get("body")?,
            reply_to_id,
            reply_to_preview: resolve_reply_preview(&state.db, reply_to_id).await?,
            pinned: row.try_get("pinned")?,
            created_at: row.try_get("created_at")?,
        });
    }
    Ok(Json(out))
}

#[derive(Deserialize)]
struct SetPinnedRequest {
    pinned: bool,
}

async fn set_pinned(
    State(state): State<AppState>,
    Path(message_id): Path<Uuid>,
    Json(req): Json<SetPinnedRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    let updated = sqlx::query("update messages set pinned = $2 where id = $1")
        .bind(message_id)
        .bind(req.pinned)
        .execute(&state.db)
        .await?
        .rows_affected();
    if updated == 0 {
        return Err(ApiError::NotFound("message not found"));
    }
    Ok(Json(serde_json::json!({"ok": true})))
}
