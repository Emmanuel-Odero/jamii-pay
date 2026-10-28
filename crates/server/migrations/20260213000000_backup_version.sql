-- Backup format version, recorded per escrowed backup for support and
-- policy ("which print is this row?"). v1 whole-key QRs predate server
-- registration entirely and never appear here; every row written by the
-- current API is a v2 split backup. The default keeps historical rows
-- (written before this column existed) honest instead of NULL.
alter table wallet_backups
    add column if not exists version integer not null default 2;
