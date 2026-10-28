-- Wires the previously-dead `claims` table (see `20260101000000_init.sql`)
-- into the Escrow claim-by-link flow (see
-- `designs/jammii-pay-prototype.html`'s send-to-unregistered-recipient
-- path and its `SCR.claim` recipient-facing screen). `amount_minor_units`
-- is read as USD cents throughout `routes/escrow.rs`, matching every
-- other USD amount column in this schema — `currency` stays for the
-- original schema's future-proofing but isn't branched on anywhere yet.
alter table claims
    add column if not exists recipient_addr text,
    add column if not exists recipient_kind text check (recipient_kind in ('phone', 'email')),
    add column if not exists expires_at timestamptz,
    add column if not exists status text not null default 'pending' check (
        status in ('pending', 'claimed', 'expired', 'cancelled')
    );
