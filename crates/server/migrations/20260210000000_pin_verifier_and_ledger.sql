-- PIN verifier upgrade + append-only ledger foundation.
--
-- 1. `pin_version` / `pin_verifier`: v1 is bcrypt(sha256(pin)) (see
--    20260125000000_wallet_pin_hash.sql). v2 reserves a column for the
--    OPAQUE verifier once the PAKE migration ships — the server already
--    dual-verifies (`pin_verifier.rs`: v2 if present, else v1), so the
--    cutover is per-wallet with zero downtime. The client's unsalted
--    sha256 pre-hash is never relied on for offline resistance; it is
--    only the presentation value the server re-checks.
alter table wallets
    add column if not exists pin_version integer not null default 1,
    add column if not exists pin_verifier text;

-- 2. Ledger foundation (append-only). Balances today are mutable columns
--    (`wallet_flows.sql`) — the migration comment there already requires a
--    real double-entry ledger before handling actual money. This table is
--    that ledger's future source of truth: every money move must insert
--    here first, balances derived, never updated in place. No behavior
--    changes yet — writers cut over route by route, then the columns
--    become a cached projection with a reconciliation job.
create table if not exists ledger_entries (
    id uuid primary key default gen_random_uuid(),
    wallet_id uuid not null references wallets(id),
    direction text not null check (direction in ('in', 'out')),
    amount_usd_cents bigint not null check (amount_usd_cents > 0),
    kind text not null check (
        kind in ('transfer', 'cash_out', 'bill_pay', 'airtime',
                 'mpesa_deposit', 'card_topup', 'savings_move',
                 'savings_withdraw', 'escrow', 'adjustment')
    ),
    -- Idempotency key of the originating operation (see
    -- 20260208000000_idempotency.sql) — same key, same entry, no doubles.
    idempotency_key text,
    -- Opaque reference to the originating row (transaction / deposit /
    -- payout id) for reconciliation.
    ref_id uuid,
    created_at timestamptz not null default now()
);

create index if not exists idx_ledger_wallet_created
    on ledger_entries(wallet_id, created_at desc);
create unique index if not exists idx_ledger_idempotency
    on ledger_entries(wallet_id, idempotency_key)
    where idempotency_key is not null;
