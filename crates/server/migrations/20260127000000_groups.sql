-- Backs Groups/Chamas (see `designs/jammii-pay-prototype.html`'s
-- `groups`/`groupNew`/`groupDetail`/`groupVote`/`broadcastSend` screens).
-- A group is not a wallet — it never receives real deposits from outside
-- the app, only via `contribute` from members who already have wallets —
-- so `full_handle` here is a display identifier only, generated the same
-- way wallet handles are but stored on this table rather than the shared
-- `handles` table (which is FK'd to `wallets`, not groups).

create table if not exists groups (
    id uuid primary key default gen_random_uuid(),
    owner_wallet_id uuid not null references wallets(id),
    name text not null,
    kind text not null check (kind in ('pool', 'cast')),
    power_scheme text not null check (power_scheme in ('equal', 'contrib', 'custom')),
    pot_usd_cents bigint not null default 0,
    full_handle text not null unique,
    created_at timestamptz not null default now()
);

create index if not exists idx_groups_owner_wallet_id on groups(owner_wallet_id);

-- A member is either on Jamii (`wallet_id` set, resolved the same way
-- `contacts.linked_wallet_id` is) or not (`contact_addr` set instead) —
-- the same on/off-Jamii duality as Contacts. `custom_power_bp` (basis
-- points, 0-10000) is only meaningful when the owning group's
-- `power_scheme = 'custom'`.
create table if not exists group_members (
    id uuid primary key default gen_random_uuid(),
    group_id uuid not null references groups(id),
    wallet_id uuid references wallets(id),
    contact_name text not null,
    contact_addr text,
    is_owner boolean not null default false,
    contributed_usd_cents bigint not null default 0,
    custom_power_bp integer,
    created_at timestamptz not null default now()
);

create index if not exists idx_group_members_group_id on group_members(group_id);

create table if not exists group_withdrawal_requests (
    id uuid primary key default gen_random_uuid(),
    group_id uuid not null references groups(id),
    amount_usd_cents bigint not null,
    payee_name text not null,
    status text not null default 'open' check (
        status in ('open', 'passed', 'blocked', 'executed', 'cancelled')
    ),
    created_at timestamptz not null default now(),
    executed_at timestamptz
);

create index if not exists idx_group_withdrawal_requests_group_id on group_withdrawal_requests(group_id);

create table if not exists group_votes (
    id uuid primary key default gen_random_uuid(),
    request_id uuid not null references group_withdrawal_requests(id),
    member_id uuid not null references group_members(id),
    choice text not null check (choice in ('approve', 'withhold', 'veto')),
    voted_at timestamptz not null default now(),
    unique (request_id, member_id)
);
