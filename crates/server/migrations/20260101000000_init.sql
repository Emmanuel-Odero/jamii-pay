-- Baseline schema. Extend with additional migrations rather than editing
-- this file once it has shipped anywhere.

create table if not exists wallets (
    id uuid primary key default gen_random_uuid(),
    owner_user_id uuid not null,
    evm_address text not null unique,
    smart_account_address text,
    created_at timestamptz not null default now()
);

create table if not exists claims (
    id uuid primary key default gen_random_uuid(),
    wallet_id uuid not null references wallets(id),
    claim_code_hash text not null unique,
    amount_minor_units bigint not null,
    currency text not null default 'USDC',
    claimed_at timestamptz,
    created_at timestamptz not null default now()
);

create index if not exists idx_claims_wallet_id on claims(wallet_id);
