use axum::{
    extract::{Path, State},
    routing::{delete, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/wallets/:id/contacts", post(create_contact).get(list_contacts))
        .route("/wallets/:id/contacts/:contact_id", delete(delete_contact))
}

#[derive(Deserialize)]
struct CreateContactRequest {
    name: String,
    /// `"handle" | "phone" | "email"` — matches the prototype's live
    /// kind-detection on the Add-contact form. The client detects which
    /// kind was typed (`@` → email, `/^[+\d\s]+$/` → phone, else handle)
    /// and sends it explicitly rather than the server re-guessing.
    contact_kind: String,
    contact_value: String,
}

#[derive(Serialize)]
struct ContactResponse {
    id: Uuid,
    name: String,
    contact_kind: String,
    contact_value: String,
    /// Non-null ⇔ "ON JAMII" in the prototype's chip — a real payment
    /// name that resolved to an actual wallet, not just a plausible one.
    on_jamii: bool,
    /// The resolved wallet, when `on_jamii` — lets the client open a chat
    /// (`routes/messages.rs`), which only works between two real wallets.
    linked_wallet_id: Option<Uuid>,
}

async fn create_contact(
    State(state): State<AppState>,
    Path(owner_wallet_id): Path<Uuid>,
    Json(req): Json<CreateContactRequest>,
) -> ApiResult<Json<ContactResponse>> {
    let name = req.name.trim().to_string();
    if name.is_empty() || name.len() > 28 {
        return Err(ApiError::BadRequest(
            "name must be 1-28 characters".to_string(),
        ));
    }

    let value = req.contact_value.trim().to_string();
    if value.is_empty() {
        return Err(ApiError::BadRequest(
            "payment ID, phone, or email is required".to_string(),
        ));
    }

    let (linked_wallet_id, normalized_value) = match req.contact_kind.as_str() {
        "handle" => {
            let full_handle = value.to_lowercase();
            let wallet_id: Uuid = sqlx::query_scalar("select wallet_id from handles where full_handle = $1")
                .bind(&full_handle)
                .fetch_optional(&state.db)
                .await?
                .ok_or(ApiError::NotFound("no wallet with that payment name"))?;
            (Some(wallet_id), full_handle)
        }
        "phone" => {
            let digit_count = value.chars().filter(|c| c.is_ascii_digit()).count();
            if digit_count < 9 || !value.chars().all(|c| c.is_ascii_digit() || c == '+' || c.is_whitespace()) {
                return Err(ApiError::BadRequest("not a valid phone number".to_string()));
            }
            (None, value)
        }
        "email" => {
            if !value.contains('@') {
                return Err(ApiError::BadRequest("not a valid email".to_string()));
            }
            (None, value)
        }
        other => return Err(ApiError::BadRequest(format!("unknown contact kind: {other}"))),
    };

    let id: Uuid = sqlx::query_scalar(
        "insert into contacts (owner_wallet_id, name, contact_kind, contact_value, linked_wallet_id)
         values ($1, $2, $3, $4, $5) returning id",
    )
    .bind(owner_wallet_id)
    .bind(&name)
    .bind(&req.contact_kind)
    .bind(&normalized_value)
    .bind(linked_wallet_id)
    .fetch_one(&state.db)
    .await?;

    Ok(Json(ContactResponse {
        id,
        name,
        contact_kind: req.contact_kind,
        contact_value: normalized_value,
        on_jamii: linked_wallet_id.is_some(),
        linked_wallet_id,
    }))
}

async fn list_contacts(
    State(state): State<AppState>,
    Path(owner_wallet_id): Path<Uuid>,
) -> ApiResult<Json<Vec<ContactResponse>>> {
    let rows: Vec<(Uuid, String, String, String, Option<Uuid>)> = sqlx::query_as(
        "select id, name, contact_kind, contact_value, linked_wallet_id
         from contacts where owner_wallet_id = $1 order by name asc",
    )
    .bind(owner_wallet_id)
    .fetch_all(&state.db)
    .await?;

    Ok(Json(
        rows.into_iter()
            .map(|(id, name, contact_kind, contact_value, linked_wallet_id)| ContactResponse {
                id,
                name,
                contact_kind,
                contact_value,
                on_jamii: linked_wallet_id.is_some(),
                linked_wallet_id,
            })
            .collect(),
    ))
}

async fn delete_contact(
    State(state): State<AppState>,
    Path((owner_wallet_id, contact_id)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<serde_json::Value>> {
    let deleted = sqlx::query("delete from contacts where id = $1 and owner_wallet_id = $2")
        .bind(contact_id)
        .bind(owner_wallet_id)
        .execute(&state.db)
        .await?
        .rows_affected();

    if deleted == 0 {
        return Err(ApiError::NotFound("contact not found"));
    }

    Ok(Json(serde_json::json!({"ok": true})))
}
