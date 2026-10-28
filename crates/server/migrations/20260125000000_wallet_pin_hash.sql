-- Backs the "restore from wallet key" import flow (see
-- RestoreFromKeyScreen / WalletKeyBackupScreen in the Flutter app): once a
-- device has decrypted a wallet's exported private key locally, it still
-- has to prove it's the wallet's owner before the app treats it as a real
-- session — this is that second factor, checked server-side.
--
-- The client never sends a raw PIN: `pin_hash` is the client's own
-- unsalted sha256(pin) (see `security/pin_hash.dart`), which this column
-- re-hashes with bcrypt before storage — bcrypt's per-row salt and cost
-- factor protect against a leaked table being brute-forced offline, which
-- an unsalted sha256 alone would not (see the migration in
-- `routes/wallets.rs`'s `verify_pin` for the check itself).
alter table wallets
    add column if not exists pin_hash_bcrypt text;
