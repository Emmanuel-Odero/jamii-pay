-- Backs the Contacts screen (see `designs/jammii-pay-prototype.html`'s
-- `contacts`/`contactNew` screens). `linked_wallet_id` is the on/off-Jamii
-- distinction from the prototype's `.handle`-chip "ON JAMII"/"INVITE"
-- tag: set only for `contact_kind = 'handle'` entries, where the value
-- is a real, currently-registered payment name — this app has a real
-- backend, so unlike the prototype's checksum-only demo simplification,
-- a handle-kind contact is only ever created after a real lookup
-- succeeds (see `routes/contacts.rs`'s `create_contact`).
create table if not exists contacts (
    id uuid primary key default gen_random_uuid(),
    owner_wallet_id uuid not null references wallets(id),
    name text not null,
    contact_kind text not null check (contact_kind in ('handle', 'phone', 'email')),
    contact_value text not null,
    linked_wallet_id uuid references wallets(id),
    created_at timestamptz not null default now()
);

create index if not exists idx_contacts_owner_wallet_id on contacts(owner_wallet_id, created_at desc);
