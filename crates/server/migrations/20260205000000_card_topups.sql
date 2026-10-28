-- Card top-up via Stripe Checkout (credit/debit/prepaid/virtual — Stripe
-- doesn't distinguish, so no special-casing is needed here). See
-- `routes/card_topup.rs`. Like `mpesa_deposits`, this is asynchronous:
-- creating a Checkout Session only gets you a URL to send the person to;
-- the actual result arrives later via Stripe's webhook once they
-- complete (or abandon) payment on Stripe's own hosted page.
create table if not exists card_topups (
    id uuid primary key default gen_random_uuid(),
    wallet_id uuid not null references wallets(id),
    stripe_session_id text not null unique,
    amount_usd_cents bigint not null,
    status text not null default 'pending' check (status in ('pending', 'completed', 'failed')),
    created_at timestamptz not null default now(),
    completed_at timestamptz
);

create index if not exists idx_card_topups_wallet_id on card_topups(wallet_id);

alter table transactions drop constraint if exists transactions_kind_check;
alter table transactions add constraint transactions_kind_check
    check (kind in ('transfer', 'cash_out', 'bill_pay', 'airtime', 'savings_move', 'savings_withdraw', 'mpesa_deposit', 'card_topup'));
