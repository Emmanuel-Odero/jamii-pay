-- OPAQUE password files for split backups + server secret storage.
--
-- `wallet_backups.opaque_file` holds the per-backup OPAQUE password file
-- (created at export by register/finish). Backups with NULL here predate
-- OPAQUE and keep the legacy pin_hash release path until rotated.
-- `server_secrets` holds the OPAQUE ServerSetup (row `opaque_setup`,
-- created once at first boot, never rotated without re-registering every
-- password file — rotation means new backups, old ones keep working only
-- on the old setup, so setups are versioned, never overwritten).

create table if not exists server_secrets (
    name text primary key,
    value bytea not null,
    created_at timestamptz not null default now()
);

alter table wallet_backups
    add column if not exists opaque_file bytea;
