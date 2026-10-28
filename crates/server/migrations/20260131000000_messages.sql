-- Backs the 66-character chat feature — see `routes/messages.rs`. Capped
-- hard at the DB layer (not just client-side validation) because this is
-- a payments app, not a social app: messages are meant to be read in a
-- glance, not composed at length. Direct (contact-to-contact) chat only
-- works between two real wallets — an off-Jamii contact has nothing to
-- receive a message with, same duality as escrow/groups elsewhere.
create table if not exists messages (
    id uuid primary key default gen_random_uuid(),
    conversation_kind text not null check (conversation_kind in ('direct', 'group')),
    group_id uuid references groups(id),
    -- Direct chats only: always stored as (least(a,b), greatest(a,b)) so
    -- both participants' queries converge on the same row set regardless
    -- of who sent a given message.
    wallet_a_id uuid references wallets(id),
    wallet_b_id uuid references wallets(id),
    sender_wallet_id uuid not null references wallets(id),
    body text not null check (char_length(body) between 1 and 66),
    reply_to_id uuid references messages(id),
    pinned boolean not null default false,
    created_at timestamptz not null default now()
);

create index if not exists idx_messages_group on messages(group_id, created_at);
create index if not exists idx_messages_direct on messages(wallet_a_id, wallet_b_id, created_at);
