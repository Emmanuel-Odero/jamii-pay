-- Real outbound M-Pesa payments (B2C/B2B, distinct from the inbound STK
-- Push in `daraja.rs`) — see `routes/send_to_mpesa.rs`. Covers every
-- destination a Kenyan M-Pesa user actually pays into:
--   'phone'   — personal number or Pochi la Biashara (same rail — Pochi
--               is just a personal number registered as a small-business
--               wallet), via the B2C API.
--   'till'    — Buy Goods till number, via the B2B API.
--   'paybill' — Paybill + account number, via the B2B API. This is also
--               how you pay into a bank account in Kenya: most banks
--               (Equity, KCB, Co-op, ...) expose a Paybill number for
--               M-Pesa deposits, with the account number as the
--               reference — there's no separate "bank transfer" rail to
--               integrate, it's this same flow with the bank's numbers.
create table if not exists outbound_mpesa_payments (
    id uuid primary key default gen_random_uuid(),
    wallet_id uuid not null references wallets(id),
    destination_type text not null check (destination_type in ('phone', 'till', 'paybill')),
    destination_identifier text not null, -- phone number, till number, or paybill number
    account_reference text,               -- paybill only
    amount_usd_cents bigint not null,
    amount_kes_minor bigint not null,
    conversation_id text unique,
    status text not null default 'pending' check (status in ('pending', 'completed', 'failed')),
    result_desc text,
    created_at timestamptz not null default now(),
    completed_at timestamptz
);

create index if not exists idx_outbound_mpesa_payments_wallet_id on outbound_mpesa_payments(wallet_id);

alter table transactions drop constraint if exists transactions_kind_check;
alter table transactions add constraint transactions_kind_check
    check (kind in (
        'transfer', 'cash_out', 'bill_pay', 'airtime', 'savings_move', 'savings_withdraw',
        'mpesa_deposit', 'card_topup', 'mpesa_send'
    ));
