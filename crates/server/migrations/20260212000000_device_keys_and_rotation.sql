-- Device attestation columns + rotation audit action.
--
-- `device_key_pub` is the hardware-bound DeviceVault public key (Secure
-- Enclave / StrongBox) of the device holding the live session, with
-- `device_enclave` telling whether it is actually hardware-backed
-- (simulators and vault-less builds report false — loudly, not silently).
-- No private material ever touches this table. Future release policy
-- (e.g. requiring enclave devices for large releases) reads these two
-- columns; rotation refreshes them to the new device.
alter table wallets
    add column if not exists device_key_pub text,
    add column if not exists device_enclave boolean not null default false;

-- Rotation needs its own audit action: dropping and re-adding the CHECK
-- (auto-named `{table}_{column}_check` by Postgres for the inline
-- constraint in 20260209000000_split_backups.sql).
alter table security_audit drop constraint if exists security_audit_action_check;
alter table security_audit
    add constraint security_audit_action_check check (
        action in ('share_stored', 'share_released', 'release_denied',
                   'backup_locked', 'backup_revoked', 'key_rotated')
    );
