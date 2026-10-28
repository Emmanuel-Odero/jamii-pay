-- v2 split backups: the server-held share (`S2`) of each 2-of-2 backup,
-- plus the append-only security audit log backing the release oracle.
--
-- Trust model: the QR holds only the PIN-wrapped random share `S1`. `S2`
-- alone is equally random. The private key exists only when the app holds
-- both — i.e. after this oracle verifies wallet-PIN knowledge, rate
-- limits, and logs. Brute-forcing the QR can never yield the key.
--
-- `s2_sealed_hex` is the raw share hex for now. Envelope it with
-- KMS/HSM (e.g. AWS KMS `Encrypt` with a per-deploy data key) before any
-- non-local deployment — a bare database dump must not become an `S2`
-- dump. The column name already says "sealed" so the cutover is data-only.

create table if not exists wallet_backups (
    id uuid primary key default gen_random_uuid(),
    -- Client-generated v2 `backup_id` (the `id` inside the QR envelope).
    backup_id text not null unique,
    wallet_id uuid not null references wallets(id),
    -- Server share `S2` hex, KMS-sealed before non-local deploy (see above).
    s2_sealed_hex text not null,
    -- Release-oracle throttle state. Incremented per failed PIN attempt
    -- under row lock; `locked_until` set on exhaustion (guardians alerted).
    failed_attempts integer not null default 0,
    locked_until timestamptz,
    revoked boolean not null default false,
    created_at timestamptz not null default now()
);

create index if not exists idx_wallet_backups_wallet_id
    on wallet_backups(wallet_id);

-- Append-only: no updates, no deletes (enforced by convention + grants).
-- Every share release, lock, and revocation lands here; guardians and the
-- Notifications feed read from it.
create table if not exists security_audit (
    id uuid primary key default gen_random_uuid(),
    wallet_id uuid not null references wallets(id),
    backup_id text,
    action text not null check (
        action in ('share_stored', 'share_released', 'release_denied',
                   'backup_locked', 'backup_revoked')
    ),
    detail text not null default '',
    created_at timestamptz not null default now()
);

create index if not exists idx_security_audit_wallet_id
    on security_audit(wallet_id, created_at desc);
