use axum::{
    extract::{Path, State},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::group_vote::{tally, Choice, MemberVote};
use crate::handle::compute_check_digit;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/groups", post(create_group))
        .route("/wallets/:id/groups", get(list_groups))
        .route("/groups/:id", get(get_group))
        .route("/groups/:id/contribute", post(contribute))
        .route("/groups/:id/withdrawals", post(open_withdrawal))
        .route("/groups/:id/withdrawals/:req_id", get(get_withdrawal))
        .route("/groups/:id/withdrawals/:req_id/vote", post(cast_vote))
        .route("/groups/:id/withdrawals/:req_id/execute", post(execute_withdrawal))
        .route("/groups/:id/proposals/add-member", post(propose_add_member))
        .route("/groups/:id/proposals/remove-member", post(propose_remove_member))
        .route("/groups/:id/invites/:req_id/respond", post(respond_to_invite))
        .route("/wallets/:id/invites", get(list_invites_for_wallet))
        .route("/groups/:id/broadcast", post(broadcast))
}

#[derive(Serialize)]
struct MemberResponse {
    id: Uuid,
    name: String,
    wallet_id: Option<Uuid>,
    is_owner: bool,
    contributed_usd_cents: i64,
    /// This member's normalized voting-power share (0.0-1.0), computed
    /// fresh from the group's `power_scheme` — never stored, so it can't
    /// drift out of sync with contributions.
    power: f64,
}

#[derive(Serialize)]
struct GroupResponse {
    id: Uuid,
    name: String,
    kind: String,
    power_scheme: String,
    pot_usd_cents: i64,
    full_handle: String,
    members: Vec<MemberResponse>,
    /// A vote everyone can see and cast on — `null` while an `add_member`
    /// proposal is still waiting on the invitee to accept (see
    /// `propose_add_member`'s doc comment); it only becomes "open" here
    /// once accepted, which is the "broadcasted to everyone" moment.
    open_withdrawal_request_id: Option<Uuid>,
    /// One line describing the open vote above, if any — lets the client
    /// show "Vote open: Add Yusuf Omar" without a second fetch.
    open_proposal_summary: Option<String>,
    /// Invitees who've accepted but the group hasn't finished voting on
    /// yet — rendered as a "pending approval" row in the member list.
    pending_members: Vec<PendingMemberResponse>,
}

#[derive(Serialize)]
struct PendingMemberResponse {
    request_id: Uuid,
    name: String,
}

struct MemberRow {
    id: Uuid,
    name: String,
    wallet_id: Option<Uuid>,
    is_owner: bool,
    contributed_usd_cents: i64,
    custom_power_bp: Option<i32>,
}

/// Shared power-derivation, used by both the group-detail response and
/// vote tallying — see `group_vote::tally`'s doc comment for why the math
/// itself lives in a pure, separately-tested module.
fn member_powers(power_scheme: &str, members: &[MemberRow]) -> Vec<(Uuid, f64)> {
    let n = members.len().max(1) as f64;
    match power_scheme {
        "contrib" => {
            let total: i64 = members.iter().map(|m| m.contributed_usd_cents).sum();
            if total <= 0 {
                members.iter().map(|m| (m.id, 1.0 / n)).collect()
            } else {
                members
                    .iter()
                    .map(|m| (m.id, m.contributed_usd_cents as f64 / total as f64))
                    .collect()
            }
        }
        "custom" => {
            let total_bp: i32 = members.iter().map(|m| m.custom_power_bp.unwrap_or(0)).sum();
            if total_bp <= 0 {
                members.iter().map(|m| (m.id, 1.0 / n)).collect()
            } else {
                members
                    .iter()
                    .map(|m| (m.id, m.custom_power_bp.unwrap_or(0) as f64 / total_bp as f64))
                    .collect()
            }
        }
        _ => members.iter().map(|m| (m.id, 1.0 / n)).collect(),
    }
}

async fn load_members(db: &sqlx::PgPool, group_id: Uuid) -> ApiResult<Vec<MemberRow>> {
    // `active = true` only — a removed member (see `propose_remove_member`)
    // drops out of the live roster and the voting-power split, but their
    // row (and any past votes referencing it) is never deleted.
    let rows = sqlx::query(
        "select id, contact_name, wallet_id, is_owner, contributed_usd_cents, custom_power_bp
         from group_members where group_id = $1 and active = true order by created_at asc",
    )
    .bind(group_id)
    .fetch_all(db)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| MemberRow {
            id: r.get("id"),
            name: r.get("contact_name"),
            wallet_id: r.get("wallet_id"),
            is_owner: r.get("is_owner"),
            contributed_usd_cents: r.get("contributed_usd_cents"),
            custom_power_bp: r.get("custom_power_bp"),
        })
        .collect())
}

async fn build_group_response(db: &sqlx::PgPool, group_id: Uuid) -> ApiResult<GroupResponse> {
    let row = sqlx::query(
        "select name, kind, power_scheme, pot_usd_cents, full_handle from groups where id = $1",
    )
    .bind(group_id)
    .fetch_optional(db)
    .await?
    .ok_or(ApiError::NotFound("group not found"))?;

    let kind: String = row.try_get("kind")?;
    let power_scheme: String = row.try_get("power_scheme")?;
    let members = load_members(db, group_id).await?;
    let powers = member_powers(&power_scheme, &members);

    // Only counts as "open" (visible/votable by everyone) once any
    // add_member invite has been accepted — see `GroupResponse`'s doc
    // comment and `propose_add_member`.
    let open_row = sqlx::query(
        "select id, action_type, payee_name, target_member_id, new_member_name
         from group_withdrawal_requests
         where group_id = $1 and status = 'open' and (invite_status is null or invite_status = 'accepted')
         limit 1",
    )
    .bind(group_id)
    .fetch_optional(db)
    .await?;

    let mut open_withdrawal_request_id = None;
    let mut open_proposal_summary = None;
    if let Some(row) = open_row {
        let id: Uuid = row.try_get("id")?;
        open_withdrawal_request_id = Some(id);
        let action_type: String = row.try_get("action_type")?;
        open_proposal_summary = Some(match action_type.as_str() {
            "add_member" => {
                let name: Option<String> = row.try_get("new_member_name")?;
                format!("Add {}", name.unwrap_or_else(|| "a new member".to_string()))
            }
            "remove_member" => {
                let target_id: Option<Uuid> = row.try_get("target_member_id")?;
                let name: Option<String> = match target_id {
                    Some(tid) => sqlx::query_scalar("select contact_name from group_members where id = $1").bind(tid).fetch_optional(db).await?,
                    None => None,
                };
                format!("Remove {}", name.unwrap_or_else(|| "a member".to_string()))
            }
            _ => {
                let payee: Option<String> = row.try_get("payee_name")?;
                format!("Withdrawal to {}", payee.unwrap_or_default())
            }
        });
    }

    // Invites that have been accepted but haven't finished the group
    // vote yet — shown as "pending approval" in the member list.
    let pending_rows = sqlx::query(
        "select id as request_id, new_member_name as name from group_withdrawal_requests
         where group_id = $1 and action_type = 'add_member'
           and status = 'open' and invite_status = 'accepted'",
    )
    .bind(group_id)
    .fetch_all(db)
    .await?;
    let pending_members = pending_rows
        .into_iter()
        .map(|r| Ok(PendingMemberResponse { request_id: r.try_get("request_id")?, name: r.try_get("name")? }))
        .collect::<ApiResult<Vec<_>>>()?;

    Ok(GroupResponse {
        id: group_id,
        name: row.try_get("name")?,
        kind,
        power_scheme,
        pot_usd_cents: row.try_get("pot_usd_cents")?,
        full_handle: row.try_get("full_handle")?,
        members: members
            .iter()
            .map(|m| MemberResponse {
                id: m.id,
                name: m.name.clone(),
                wallet_id: m.wallet_id,
                is_owner: m.is_owner,
                contributed_usd_cents: m.contributed_usd_cents,
                power: powers.iter().find(|(id, _)| *id == m.id).map(|(_, p)| *p).unwrap_or(0.0),
            })
            .collect(),
        open_withdrawal_request_id,
        open_proposal_summary,
        pending_members,
    })
}

#[derive(Deserialize)]
struct CreateGroupRequest {
    owner_wallet_id: Uuid,
    name: String,
    kind: String,
    power_scheme: String,
    /// Existing `contacts` rows (see `routes/contacts.rs`) to seed as the
    /// group's founding members alongside the owner — matches the
    /// prototype's "Add members from contacts" step exactly.
    member_contact_ids: Vec<Uuid>,
}

async fn create_group(
    State(state): State<AppState>,
    Json(req): Json<CreateGroupRequest>,
) -> ApiResult<Json<GroupResponse>> {
    let name = req.name.trim().to_string();
    if name.len() < 3 || name.len() > 30 {
        return Err(ApiError::BadRequest("name must be 3-30 characters".to_string()));
    }
    if !["pool", "cast"].contains(&req.kind.as_str()) {
        return Err(ApiError::BadRequest("kind must be 'pool' or 'cast'".to_string()));
    }
    if !["equal", "contrib", "custom"].contains(&req.power_scheme.as_str()) {
        return Err(ApiError::BadRequest("invalid power_scheme".to_string()));
    }

    let mut tx = state.db.begin().await?;

    // A random display handle — groups don't accept inbound transfers by
    // handle lookup (see the migration's own comment), so collisions
    // just need to not violate the unique constraint, not resolve to a
    // real receivable address.
    let base = format!(
        "{}{:04x}",
        name.to_lowercase().chars().filter(|c| c.is_ascii_alphanumeric()).take(10).collect::<String>(),
        rand_u16(),
    );
    let full_handle = format!("{base}{}", compute_check_digit(&base));

    let group_id: Uuid = sqlx::query_scalar(
        "insert into groups (owner_wallet_id, name, kind, power_scheme, full_handle)
         values ($1, $2, $3, $4, $5) returning id",
    )
    .bind(req.owner_wallet_id)
    .bind(&name)
    .bind(&req.kind)
    .bind(&req.power_scheme)
    .bind(&full_handle)
    .fetch_one(&mut *tx)
    .await?;

    let owner_row = sqlx::query(
        "select h.full_handle from wallets w left join handles h on h.wallet_id = w.id where w.id = $1",
    )
    .bind(req.owner_wallet_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(ApiError::NotFound("owner wallet not found"))?;
    let owner_name: Option<String> = owner_row.try_get("full_handle")?;

    sqlx::query(
        "insert into group_members (group_id, wallet_id, contact_name, is_owner) values ($1, $2, $3, true)",
    )
    .bind(group_id)
    .bind(req.owner_wallet_id)
    .bind(owner_name.unwrap_or_else(|| "You".to_string()))
    .execute(&mut *tx)
    .await?;

    for contact_id in &req.member_contact_ids {
        let contact = sqlx::query(
            "select name, linked_wallet_id, contact_kind, contact_value
             from contacts where id = $1 and owner_wallet_id = $2",
        )
        .bind(contact_id)
        .bind(req.owner_wallet_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or(ApiError::NotFound("contact not found"))?;

        let name: String = contact.try_get("name")?;
        let linked_wallet_id: Option<Uuid> = contact.try_get("linked_wallet_id")?;
        let contact_value: String = contact.try_get("contact_value")?;
        let contact_kind: String = contact.try_get("contact_kind")?;
        let addr = if contact_kind == "handle" { None } else { Some(contact_value) };

        sqlx::query(
            "insert into group_members (group_id, wallet_id, contact_name, contact_addr) values ($1, $2, $3, $4)",
        )
        .bind(group_id)
        .bind(linked_wallet_id)
        .bind(&name)
        .bind(addr)
        .execute(&mut *tx)
        .await?;
    }

    tx.commit().await?;

    Ok(Json(build_group_response(&state.db, group_id).await?))
}

fn rand_u16() -> u16 {
    // Avoids adding a new crate dependency for one random suffix — the
    // group's own `id` (a real UUIDv4) already has all the entropy this
    // needs; just borrow four hex digits from it.
    let bytes = Uuid::new_v4().as_bytes()[0..2].try_into().unwrap();
    u16::from_be_bytes(bytes)
}

async fn list_groups(State(state): State<AppState>, Path(wallet_id): Path<Uuid>) -> ApiResult<Json<Vec<GroupResponse>>> {
    let group_ids: Vec<Uuid> = sqlx::query_scalar(
        "select distinct group_id from group_members where wallet_id = $1",
    )
    .bind(wallet_id)
    .fetch_all(&state.db)
    .await?;

    let mut groups = Vec::with_capacity(group_ids.len());
    for id in group_ids {
        groups.push(build_group_response(&state.db, id).await?);
    }
    Ok(Json(groups))
}

async fn get_group(State(state): State<AppState>, Path(group_id): Path<Uuid>) -> ApiResult<Json<GroupResponse>> {
    Ok(Json(build_group_response(&state.db, group_id).await?))
}

#[derive(Deserialize)]
struct ContributeRequest {
    wallet_id: Uuid,
    amount_usd_cents: i64,
}

async fn contribute(
    State(state): State<AppState>,
    Path(group_id): Path<Uuid>,
    Json(req): Json<ContributeRequest>,
) -> ApiResult<Json<GroupResponse>> {
    if req.amount_usd_cents <= 0 {
        return Err(ApiError::BadRequest("amount must be positive".to_string()));
    }

    let mut tx = state.db.begin().await?;

    let member_id: Uuid = sqlx::query_scalar(
        "select id from group_members where group_id = $1 and wallet_id = $2",
    )
    .bind(group_id)
    .bind(req.wallet_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(ApiError::BadRequest("not a member of this group".to_string()))?;

    let balance: i64 = sqlx::query_scalar("select everyday_balance_cents from wallets where id = $1 for update")
        .bind(req.wallet_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or(ApiError::NotFound("wallet not found"))?;
    if balance < req.amount_usd_cents {
        return Err(ApiError::BadRequest("insufficient everyday balance".to_string()));
    }

    sqlx::query("update wallets set everyday_balance_cents = everyday_balance_cents - $2 where id = $1")
        .bind(req.wallet_id)
        .bind(req.amount_usd_cents)
        .execute(&mut *tx)
        .await?;

    sqlx::query("update groups set pot_usd_cents = pot_usd_cents + $2 where id = $1")
        .bind(group_id)
        .bind(req.amount_usd_cents)
        .execute(&mut *tx)
        .await?;

    sqlx::query("update group_members set contributed_usd_cents = contributed_usd_cents + $2 where id = $1")
        .bind(member_id)
        .bind(req.amount_usd_cents)
        .execute(&mut *tx)
        .await?;

    crate::ledger::record(
        &mut tx,
        req.wallet_id,
        "out",
        req.amount_usd_cents,
        "transfer",
        None,
        None,
    )
    .await?;

    tx.commit().await?;
    state.notify_balance_change(req.wallet_id).await;

    Ok(Json(build_group_response(&state.db, group_id).await?))
}

#[derive(Deserialize)]
struct OpenWithdrawalRequest {
    amount_usd_cents: i64,
    payee_name: String,
}

#[derive(Serialize)]
struct WithdrawalResponse {
    id: Uuid,
    /// `withdrawal` | `add_member` | `remove_member` — see the migration
    /// comment on `group_withdrawal_requests.action_type`. The client
    /// branches its vote-screen copy on this; `amount_usd_cents`/
    /// `payee_name` are only populated for `withdrawal`.
    action_type: String,
    amount_usd_cents: Option<i64>,
    payee_name: Option<String>,
    /// Display name for a `remove_member` proposal's target.
    target_member_name: Option<String>,
    /// Display name for an `add_member` proposal's proposed new member.
    new_member_name: Option<String>,
    status: String,
    approve_power: f64,
    withheld_power: f64,
    blocked_by_veto: bool,
    passes_majority: bool,
    /// Only meaningful for `withdrawal` — zero for member-action proposals.
    payout_usd_cents: i64,
    votes: Vec<VoteResponse>,
}

#[derive(Serialize)]
struct VoteResponse {
    member_id: Uuid,
    member_name: String,
    power: f64,
    choice: Option<String>,
}

async fn open_withdrawal(
    State(state): State<AppState>,
    Path(group_id): Path<Uuid>,
    Json(req): Json<OpenWithdrawalRequest>,
) -> ApiResult<Json<WithdrawalResponse>> {
    if req.amount_usd_cents <= 0 {
        return Err(ApiError::BadRequest("amount must be positive".to_string()));
    }

    let pot: i64 = sqlx::query_scalar("select pot_usd_cents from groups where id = $1")
        .bind(group_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(ApiError::NotFound("group not found"))?;
    if req.amount_usd_cents > pot {
        return Err(ApiError::BadRequest("amount exceeds the pot".to_string()));
    }

    assert_no_open_request(&state.db, group_id).await?;

    let payee = req.payee_name.trim().to_string();
    let request_id: Uuid = sqlx::query_scalar(
        "insert into group_withdrawal_requests (group_id, amount_usd_cents, payee_name, action_type)
         values ($1, $2, $3, 'withdrawal') returning id",
    )
    .bind(group_id)
    .bind(req.amount_usd_cents)
    .bind(&payee)
    .fetch_one(&state.db)
    .await?;

    Ok(Json(build_withdrawal_response(&state.db, group_id, request_id).await?))
}

/// Shared by every "open a new group vote" entry point — withdrawal or
/// member-action — since only one vote may be open at a time regardless
/// of what it's about.
async fn assert_no_open_request(db: &sqlx::PgPool, group_id: Uuid) -> ApiResult<()> {
    // A `pending`-invite `add_member` proposal deliberately does NOT
    // count as "open" here — it isn't visible to the group yet, so it
    // shouldn't block someone else from proposing something in the
    // meantime. See `GroupResponse`'s doc comment.
    let existing: Option<Uuid> = sqlx::query_scalar(
        "select id from group_withdrawal_requests
         where group_id = $1 and status = 'open' and (invite_status is null or invite_status = 'accepted')",
    )
    .bind(group_id)
    .fetch_optional(db)
    .await?;
    if existing.is_some() {
        return Err(ApiError::Conflict("a vote is already open for this group"));
    }
    Ok(())
}

#[derive(Deserialize)]
struct ProposeAddMemberRequest {
    /// An existing `contacts` row — kept as a convenience path for
    /// inviting someone already saved, resolved the same way as before.
    contact_id: Option<Uuid>,
    /// Invite by payment handle directly — works for *anyone* on Jamii,
    /// contact or not. Exactly one of `contact_id`/`handle` is expected.
    handle: Option<String>,
}

async fn propose_add_member(
    State(state): State<AppState>,
    Path(group_id): Path<Uuid>,
    Json(req): Json<ProposeAddMemberRequest>,
) -> ApiResult<Json<WithdrawalResponse>> {
    assert_no_open_request(&state.db, group_id).await?;

    // Must resolve to a real wallet — an invite has to be *accepted* by
    // someone before the group votes on it (see this fn's module doc
    // comment), which only an actual Jamii account can do.
    let (wallet_id, name): (Uuid, String) = if let Some(contact_id) = req.contact_id {
        let row = sqlx::query("select name, linked_wallet_id from contacts where id = $1")
            .bind(contact_id)
            .fetch_optional(&state.db)
            .await?
            .ok_or(ApiError::NotFound("contact not found"))?;
        let linked_wallet_id: Option<Uuid> = row.try_get("linked_wallet_id")?;
        let wallet_id = linked_wallet_id.ok_or(ApiError::BadRequest(
            "only on-Jamii contacts can be invited — they need to accept before the group votes".to_string(),
        ))?;
        (wallet_id, row.try_get("name")?)
    } else if let Some(handle) = &req.handle {
        let full_handle = handle.trim().to_lowercase();
        let wallet_id: Uuid = sqlx::query_scalar("select wallet_id from handles where full_handle = $1")
            .bind(&full_handle)
            .fetch_optional(&state.db)
            .await?
            .ok_or(ApiError::NotFound("no wallet with that payment name"))?;
        (wallet_id, full_handle)
    } else {
        return Err(ApiError::BadRequest("contact_id or handle is required".to_string()));
    };

    let already_member: bool =
        sqlx::query_scalar("select exists(select 1 from group_members where group_id = $1 and wallet_id = $2 and active = true)")
            .bind(group_id)
            .bind(wallet_id)
            .fetch_one(&state.db)
            .await?;
    if already_member {
        return Err(ApiError::BadRequest("already a member of this group".to_string()));
    }

    // Sitting invisibly as `invite_status = 'pending'` until the invitee
    // accepts — see `respond_to_invite`. Not yet "open" (no vote to cast
    // yet, nothing to notify the rest of the group about).
    let request_id: Uuid = sqlx::query_scalar(
        "insert into group_withdrawal_requests (group_id, action_type, new_member_contact_id, new_member_wallet_id, new_member_name, invite_status)
         values ($1, 'add_member', $2, $3, $4, 'pending') returning id",
    )
    .bind(group_id)
    .bind(req.contact_id)
    .bind(wallet_id)
    .bind(&name)
    .fetch_one(&state.db)
    .await?;

    Ok(Json(build_withdrawal_response(&state.db, group_id, request_id).await?))
}

#[derive(Deserialize)]
struct RespondToInviteRequest {
    wallet_id: Uuid,
    accept: bool,
}

/// The invitee's own decision — only they can accept or decline (never
/// the proposer, who already made their choice by proposing). Accepting
/// is the moment the proposal becomes visible/votable for everyone else
/// in the group; declining cancels it outright, nobody else ever sees it.
async fn respond_to_invite(
    State(state): State<AppState>,
    Path((group_id, request_id)): Path<(Uuid, Uuid)>,
    Json(req): Json<RespondToInviteRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    let row = sqlx::query(
        "select invite_status, new_member_wallet_id
         from group_withdrawal_requests
         where id = $1 and group_id = $2 and action_type = 'add_member'",
    )
    .bind(request_id)
    .bind(group_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(ApiError::NotFound("invite not found"))?;

    let invite_status: String = row.try_get("invite_status")?;
    let invitee_wallet_id: Option<Uuid> = row.try_get("new_member_wallet_id")?;
    if invitee_wallet_id != Some(req.wallet_id) {
        return Err(ApiError::Unauthorized("only the invited wallet can respond to this invite"));
    }
    if invite_status != "pending" {
        return Err(ApiError::BadRequest(format!("invite is already {invite_status}")));
    }

    if req.accept {
        sqlx::query("update group_withdrawal_requests set invite_status = 'accepted' where id = $1")
            .bind(request_id)
            .execute(&state.db)
            .await?;
    } else {
        sqlx::query("update group_withdrawal_requests set invite_status = 'declined', status = 'cancelled' where id = $1")
            .bind(request_id)
            .execute(&state.db)
            .await?;
    }

    Ok(Json(serde_json::json!({"ok": true})))
}

/// Every pending invite addressed to `wallet_id`, across all their
/// groups — surfaced in `NotificationsScreen`.
#[derive(Serialize)]
struct PendingInviteResponse {
    request_id: Uuid,
    group_id: Uuid,
    group_name: String,
}

async fn list_invites_for_wallet(State(state): State<AppState>, Path(wallet_id): Path<Uuid>) -> ApiResult<Json<Vec<PendingInviteResponse>>> {
    let rows = sqlx::query(
        "select gwr.id as request_id, g.id as group_id, g.name as group_name
         from group_withdrawal_requests gwr
         join groups g on g.id = gwr.group_id
         where gwr.new_member_wallet_id = $1 and gwr.action_type = 'add_member' and gwr.invite_status = 'pending'",
    )
    .bind(wallet_id)
    .fetch_all(&state.db)
    .await?;

    rows.into_iter()
        .map(|r| Ok(PendingInviteResponse { request_id: r.try_get("request_id")?, group_id: r.try_get("group_id")?, group_name: r.try_get("group_name")? }))
        .collect::<ApiResult<Vec<_>>>()
        .map(Json)
}

#[derive(Deserialize)]
struct ProposeRemoveMemberRequest {
    member_id: Uuid,
}

async fn propose_remove_member(
    State(state): State<AppState>,
    Path(group_id): Path<Uuid>,
    Json(req): Json<ProposeRemoveMemberRequest>,
) -> ApiResult<Json<WithdrawalResponse>> {
    assert_no_open_request(&state.db, group_id).await?;

    let is_owner: bool = sqlx::query_scalar(
        "select is_owner from group_members where id = $1 and group_id = $2 and active = true",
    )
    .bind(req.member_id)
    .bind(group_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(ApiError::NotFound("member not found"))?;
    if is_owner {
        return Err(ApiError::BadRequest("the group owner can't be removed".to_string()));
    }

    let request_id: Uuid = sqlx::query_scalar(
        "insert into group_withdrawal_requests (group_id, action_type, target_member_id)
         values ($1, 'remove_member', $2) returning id",
    )
    .bind(group_id)
    .bind(req.member_id)
    .fetch_one(&state.db)
    .await?;

    Ok(Json(build_withdrawal_response(&state.db, group_id, request_id).await?))
}

async fn build_withdrawal_response(db: &sqlx::PgPool, group_id: Uuid, request_id: Uuid) -> ApiResult<WithdrawalResponse> {
    let req_row = sqlx::query(
        "select amount_usd_cents, payee_name, status, action_type, target_member_id, new_member_name
         from group_withdrawal_requests where id = $1",
    )
    .bind(request_id)
    .fetch_optional(db)
    .await?
    .ok_or(ApiError::NotFound("withdrawal request not found"))?;

    let amount_usd_cents: Option<i64> = req_row.try_get("amount_usd_cents")?;
    let payee_name: Option<String> = req_row.try_get("payee_name")?;
    let status: String = req_row.try_get("status")?;
    let action_type: String = req_row.try_get("action_type")?;
    let target_member_id: Option<Uuid> = req_row.try_get("target_member_id")?;
    let new_member_name: Option<String> = req_row.try_get("new_member_name")?;

    // Reads the *raw* row (not `load_members`, which filters
    // `active = true`) so a `remove_member` vote still shows the target's
    // name even after — in the moment it's cast, before execution — they
    // could theoretically already be gone from the live roster.
    let target_member_name: Option<String> = match target_member_id {
        Some(id) => sqlx::query_scalar("select contact_name from group_members where id = $1").bind(id).fetch_optional(db).await?,
        None => None,
    };

    let power_scheme: String = sqlx::query_scalar("select power_scheme from groups where id = $1")
        .bind(group_id)
        .fetch_one(db)
        .await?;
    let members = load_members(db, group_id).await?;
    let powers = member_powers(&power_scheme, &members);

    let cast_votes: Vec<(Uuid, Choice)> = sqlx::query_as(
        "select member_id, choice from group_votes where request_id = $1",
    )
    .bind(request_id)
    .fetch_all(db)
    .await?;

    let member_votes: Vec<MemberVote> = members
        .iter()
        .map(|m| {
            let power = powers.iter().find(|(id, _)| *id == m.id).map(|(_, p)| *p).unwrap_or(0.0);
            let choice = cast_votes.iter().find(|(id, _)| *id == m.id).map(|(_, c)| *c);
            MemberVote { member_id: m.id, power, choice }
        })
        .collect();

    // `payout_usd_cents` is meaningless for a member-action vote — tally
    // against 0 rather than threading an `Option` through the pure math
    // module for a value nothing reads outside the `withdrawal` case.
    let outcome = tally(amount_usd_cents.unwrap_or(0), &member_votes);

    Ok(WithdrawalResponse {
        id: request_id,
        action_type,
        amount_usd_cents,
        payee_name,
        target_member_name,
        new_member_name,
        status,
        approve_power: outcome.approve_power,
        withheld_power: outcome.withheld_power,
        blocked_by_veto: outcome.blocked_by_veto,
        passes_majority: outcome.passes_majority,
        payout_usd_cents: outcome.payout_usd_cents,
        votes: member_votes
            .iter()
            .zip(members.iter())
            .map(|(v, m)| VoteResponse {
                member_id: m.id,
                member_name: m.name.clone(),
                power: v.power,
                choice: v.choice.map(|c| match c {
                    Choice::Approve => "approve".to_string(),
                    Choice::Withhold => "withhold".to_string(),
                    Choice::Veto => "veto".to_string(),
                }),
            })
            .collect(),
    })
}

async fn get_withdrawal(
    State(state): State<AppState>,
    Path((group_id, request_id)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<WithdrawalResponse>> {
    Ok(Json(build_withdrawal_response(&state.db, group_id, request_id).await?))
}

#[derive(Deserialize)]
struct CastVoteRequest {
    member_id: Uuid,
    choice: String,
}

async fn cast_vote(
    State(state): State<AppState>,
    Path((group_id, request_id)): Path<(Uuid, Uuid)>,
    Json(req): Json<CastVoteRequest>,
) -> ApiResult<Json<WithdrawalResponse>> {
    if !["approve", "withhold", "veto"].contains(&req.choice.as_str()) {
        return Err(ApiError::BadRequest("choice must be approve, withhold, or veto".to_string()));
    }

    sqlx::query(
        "insert into group_votes (request_id, member_id, choice) values ($1, $2, $3)
         on conflict (request_id, member_id) do update set choice = excluded.choice, voted_at = now()",
    )
    .bind(request_id)
    .bind(req.member_id)
    .bind(&req.choice)
    .execute(&state.db)
    .await?;

    Ok(Json(build_withdrawal_response(&state.db, group_id, request_id).await?))
}

/// Executes a passing, unblocked request: deducts the payout from the
/// pot and marks the request settled. There's no matching credit leg in
/// `transactions` — `payee_name` is an external, non-Jamii payee (e.g.
/// "Kakuma Water Co." in the prototype's own demo), so there's no
/// receiving wallet to credit; the pot debit itself is the record of the
/// payout (reflected immediately in `GroupResponse.pot_usd_cents`).
async fn execute_withdrawal(
    State(state): State<AppState>,
    Path((group_id, request_id)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<WithdrawalResponse>> {
    let mut tx = state.db.begin().await?;

    let status: String = sqlx::query_scalar("select status from group_withdrawal_requests where id = $1 for update")
        .bind(request_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or(ApiError::NotFound("withdrawal request not found"))?;
    if status != "open" {
        return Err(ApiError::BadRequest(format!("request is already {status}")));
    }

    let response = build_withdrawal_response(&state.db, group_id, request_id).await?;
    if response.blocked_by_veto {
        sqlx::query("update group_withdrawal_requests set status = 'blocked' where id = $1")
            .bind(request_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        return Err(ApiError::BadRequest("blocked by a veto".to_string()));
    }
    if !response.passes_majority {
        return Err(ApiError::BadRequest("majority not yet reached".to_string()));
    }

    // The vote itself is identical for all three action types (same
    // majority/veto tally); only what happens on a passing execute
    // differs.
    match response.action_type.as_str() {
        "withdrawal" => {
            sqlx::query("update groups set pot_usd_cents = pot_usd_cents - $2 where id = $1")
                .bind(group_id)
                .bind(response.payout_usd_cents)
                .execute(&mut *tx)
                .await?;
        }
        "add_member" => {
            let row = sqlx::query("select new_member_wallet_id, new_member_name from group_withdrawal_requests where id = $1")
                .bind(request_id)
                .fetch_one(&mut *tx)
                .await?;
            let wallet_id: Uuid = row.try_get("new_member_wallet_id")?;
            let name: String = row.try_get("new_member_name")?;

            // Always a real wallet by this point (accepting the invite
            // required one) — no `contact_addr` off-Jamii case here,
            // unlike `create_group`'s founding-member seeding.
            sqlx::query("insert into group_members (group_id, wallet_id, contact_name) values ($1, $2, $3)")
                .bind(group_id)
                .bind(wallet_id)
                .bind(&name)
                .execute(&mut *tx)
                .await?;
        }
        "remove_member" => {
            let target_id: Uuid = sqlx::query_scalar(
                "select target_member_id from group_withdrawal_requests where id = $1",
            )
            .bind(request_id)
            .fetch_one(&mut *tx)
            .await?;
            // Soft-delete — see the migration comment on `group_members.active`.
            sqlx::query("update group_members set active = false where id = $1")
                .bind(target_id)
                .execute(&mut *tx)
                .await?;
        }
        other => return Err(ApiError::BadRequest(format!("unknown action_type: {other}"))),
    }

    sqlx::query(
        "update group_withdrawal_requests set status = 'executed', executed_at = now() where id = $1",
    )
    .bind(request_id)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    Ok(Json(build_withdrawal_response(&state.db, group_id, request_id).await?))
}

#[derive(Deserialize)]
struct BroadcastRequest {
    sender_wallet_id: Uuid,
    amount_per_member_usd_cents: i64,
    /// Real wallets only — cast-kind sends go to registered members;
    /// off-Jamii `cast` members aren't reachable this way yet (no escrow
    /// integration for group broadcasts).
    member_wallet_ids: Vec<Uuid>,
}

#[derive(Serialize)]
struct BroadcastResponse {
    sender_everyday_balance_usd_cents: i64,
    recipients: i64,
    total_usd_cents: i64,
}

async fn broadcast(
    State(state): State<AppState>,
    Path(group_id): Path<Uuid>,
    Json(req): Json<BroadcastRequest>,
) -> ApiResult<Json<BroadcastResponse>> {
    if req.amount_per_member_usd_cents <= 0 || req.member_wallet_ids.is_empty() {
        return Err(ApiError::BadRequest("choose at least one recipient and a positive amount".to_string()));
    }

    let group_name: String = sqlx::query_scalar("select name from groups where id = $1")
        .bind(group_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(ApiError::NotFound("group not found"))?;

    let total = req.amount_per_member_usd_cents * req.member_wallet_ids.len() as i64;

    let mut tx = state.db.begin().await?;

    let sender_balance: i64 = sqlx::query_scalar("select everyday_balance_cents from wallets where id = $1 for update")
        .bind(req.sender_wallet_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or(ApiError::NotFound("sender wallet not found"))?;
    if sender_balance < total {
        return Err(ApiError::BadRequest("insufficient everyday balance".to_string()));
    }

    let new_balance: i64 = sqlx::query_scalar(
        "update wallets set everyday_balance_cents = everyday_balance_cents - $2 where id = $1 returning everyday_balance_cents",
    )
    .bind(req.sender_wallet_id)
    .bind(total)
    .fetch_one(&mut *tx)
    .await?;

    sqlx::query(
        "insert into transactions (wallet_id, direction, counterparty_name, amount_usd_cents, kind, status)
         values ($1, 'out', $2, $3, 'transfer', 'settled')",
    )
    .bind(req.sender_wallet_id)
    .bind(format!("Broadcast to {group_name}"))
    .bind(total)
    .execute(&mut *tx)
    .await?;

    crate::ledger::record(&mut tx, req.sender_wallet_id, "out", total, "transfer", None, None)
        .await?;

    for recipient_id in &req.member_wallet_ids {
        sqlx::query("update wallets set everyday_balance_cents = everyday_balance_cents + $2 where id = $1")
            .bind(recipient_id)
            .bind(req.amount_per_member_usd_cents)
            .execute(&mut *tx)
            .await?;

        sqlx::query(
            "insert into transactions (wallet_id, direction, counterparty_name, amount_usd_cents, kind, status)
             values ($1, 'in', $2, $3, 'transfer', 'settled')",
        )
        .bind(recipient_id)
        .bind(format!("From {group_name}"))
        .bind(req.amount_per_member_usd_cents)
        .execute(&mut *tx)
        .await?;

        crate::ledger::record(
            &mut tx,
            *recipient_id,
            "in",
            req.amount_per_member_usd_cents,
            "transfer",
            None,
            None,
        )
        .await?;
    }

    tx.commit().await?;

    state.notify_balance_change(req.sender_wallet_id).await;
    for recipient_id in &req.member_wallet_ids {
        state.notify_balance_change(*recipient_id).await;
        state
            .push
            .notify_wallet(
                &state.db,
                *recipient_id,
                "Money received",
                &format!("{group_name} sent you money — open JamiiPay to see it."),
                "balance",
            )
            .await;
    }

    Ok(Json(BroadcastResponse {
        sender_everyday_balance_usd_cents: new_balance,
        recipients: req.member_wallet_ids.len() as i64,
        total_usd_cents: total,
    }))
}
