-- Idempotency keys for money-moving endpoints — prevents double-send on
-- double-tap / retry after timeout / STK re-push. Client generates a UUID
-- per user intent (per review-sheet confirmation) and sends it as
-- `idempotency_key`; server returns the original result when the same key
-- is seen again instead of executing twice.

-- Transfers: key scoped per sender wallet.
alter table transactions
    add column if not exists idempotency_key text;

create unique index if not exists idx_transactions_idempotency
    on transactions(wallet_id, idempotency_key)
    where idempotency_key is not null;

-- STK deposits: key scoped per wallet.
alter table mpesa_deposits
    add column if not exists idempotency_key text;

create unique index if not exists idx_mpesa_deposits_idempotency
    on mpesa_deposits(wallet_id, idempotency_key)
    where idempotency_key is not null;

-- Outbound M-Pesa payouts (cash-out): same guard.
alter table outbound_mpesa_payments
    add column if not exists idempotency_key text;

create unique index if not exists idx_outbound_mpesa_idempotency
    on outbound_mpesa_payments(wallet_id, idempotency_key)
    where idempotency_key is not null;
