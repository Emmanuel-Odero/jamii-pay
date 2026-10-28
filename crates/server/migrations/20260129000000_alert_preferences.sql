-- Backs the per-event alert settings screen (see
-- `designs/jammii-pay-prototype.html`'s `SCR.alerts` — read-only there;
-- this app makes it genuinely editable). One row per (wallet, event);
-- `recovery_started` is seeded like every other event but
-- `routes/alerts.rs`'s update handler refuses to let it be edited — the
-- prototype's own stated rule is that recovery alerts override quiet
-- hours and preferences entirely, so there is nothing to toggle there by
-- design, not by omission.
create table if not exists alert_preferences (
    wallet_id uuid not null references wallets(id),
    event_key text not null check (
        event_key in ('money_arrives', 'money_sent', 'claim_expiring', 'group_vote_opened', 'recovery_started')
    ),
    sms boolean not null default false,
    push boolean not null default false,
    email boolean not null default false,
    primary key (wallet_id, event_key)
);
