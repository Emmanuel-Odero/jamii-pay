-- Receiving money via M-Pesa STK Push (Daraja API) — see
-- `routes/mpesa.rs`. STK Push is asynchronous: the initiate call only
-- returns a `checkout_request_id`; Safaricom later POSTs the real
-- result to our callback URL once the person enters their M-Pesa PIN
-- (or cancels/times out), which is what actually credits the wallet.
create table if not exists mpesa_deposits (
    id uuid primary key default gen_random_uuid(),
    wallet_id uuid not null references wallets(id),
    checkout_request_id text not null unique,
    merchant_request_id text not null,
    phone text not null,
    amount_kes_minor bigint not null,
    amount_usd_cents bigint not null,
    status text not null default 'pending' check (status in ('pending', 'completed', 'failed')),
    mpesa_receipt text,
    result_desc text,
    created_at timestamptz not null default now(),
    completed_at timestamptz
);

create index if not exists idx_mpesa_deposits_wallet_id on mpesa_deposits(wallet_id);

alter table transactions drop constraint if exists transactions_kind_check;
alter table transactions add constraint transactions_kind_check
    check (kind in ('transfer', 'cash_out', 'bill_pay', 'airtime', 'savings_move', 'savings_withdraw', 'mpesa_deposit'));
