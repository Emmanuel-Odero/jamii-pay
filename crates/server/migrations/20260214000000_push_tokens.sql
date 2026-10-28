-- Remote-push device tokens (Apple Push Notification service).
--
-- One row per (wallet, device token): a wallet with two iPhones gets two
-- rows and both buzz. Tokens are opaque to the server — unguessable
-- 64-hex device identifiers, useless without Apple's keys. Stale tokens
-- (app reinstall generates a new one; APNs answers 410 Gone for dead
-- ones) are pruned on send failure and may be re-registered freely —
-- upsert, never error, on register.
create table if not exists push_tokens (
    wallet_id uuid not null references wallets(id) on delete cascade,
    token text not null,
    platform text not null default 'ios' check (platform in ('ios', 'android')),
    created_at timestamptz not null default now(),
    last_used_at timestamptz not null default now(),
    primary key (wallet_id, token)
);

create index if not exists idx_push_tokens_wallet_id on push_tokens(wallet_id);
