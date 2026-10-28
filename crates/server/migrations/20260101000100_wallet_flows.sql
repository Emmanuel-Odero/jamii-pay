-- Schema backing the onboarding/wallet/recovery screens in the Flutter app
-- (see designs/jammii-pay-mockup.html). Balances are stored as columns
-- rather than derived from a ledger for now — swap for a real
-- double-entry ledger before this handles actual money.

alter table wallets
    add column if not exists everyday_balance_cents bigint not null default 0,
    add column if not exists savings_balance_cents bigint not null default 0;

-- A wallet's "payment name" — a human-typed base plus a check digit that
-- catches typos and lookalike-registration attempts (see HandleChip / the
-- onboarding Handle screen).
create table if not exists handles (
    id uuid primary key default gen_random_uuid(),
    wallet_id uuid not null references wallets(id),
    base text not null,
    check_digit char(1) not null,
    full_handle text generated always as (base || check_digit) stored,
    created_at timestamptz not null default now(),
    unique (full_handle)
);

create index if not exists idx_handles_wallet_id on handles(wallet_id);

create table if not exists transactions (
    id uuid primary key default gen_random_uuid(),
    wallet_id uuid not null references wallets(id),
    direction text not null check (direction in ('in', 'out')),
    counterparty_name text not null,
    amount_usd_cents bigint not null,
    amount_local_minor bigint,
    local_currency text,
    fx_rate numeric(12, 4),
    kind text not null check (kind in ('transfer', 'cash_out', 'bill_pay', 'airtime')),
    status text not null default 'settled' check (status in ('pending', 'settled', 'failed')),
    created_at timestamptz not null default now()
);

create index if not exists idx_transactions_wallet_id on transactions(wallet_id, created_at desc);

-- The recovery-method menu from the onboarding Guardians screen. Guardians
-- are stored as salted hashes per the tech deck ("never published in
-- plaintext"); `secret_hash` is null for guardian types that don't have a
-- user-supplied secret (e.g. the institutional Jamii Pay guardian).
create table if not exists guardians (
    id uuid primary key default gen_random_uuid(),
    wallet_id uuid not null references wallets(id),
    guardian_type text not null check (
        guardian_type in ('device', 'printed_code', 'institutional', 'trusted_person')
    ),
    secret_hash text,
    label text,
    created_at timestamptz not null default now()
);

create index if not exists idx_guardians_wallet_id on guardians(wallet_id);

-- One row per recovery attempt (Recovery R1-R4). `threshold` is 2-of-3 per
-- the design, kept as a column rather than a constant so it can vary if a
-- wallet configures more than three guardians later.
create table if not exists recovery_requests (
    id uuid primary key default gen_random_uuid(),
    wallet_id uuid not null references wallets(id),
    status text not null default 'pending_approvals' check (
        status in ('pending_approvals', 'waiting', 'completed', 'cancelled')
    ),
    threshold integer not null default 2,
    reported_stolen boolean not null default false,
    started_at timestamptz not null default now(),
    wait_completes_at timestamptz,
    cancelled_at timestamptz,
    completed_at timestamptz
);

create index if not exists idx_recovery_requests_wallet_id on recovery_requests(wallet_id);

create table if not exists recovery_approvals (
    id uuid primary key default gen_random_uuid(),
    recovery_request_id uuid not null references recovery_requests(id),
    guardian_id uuid not null references guardians(id),
    approved_at timestamptz not null default now(),
    unique (recovery_request_id, guardian_id)
);
