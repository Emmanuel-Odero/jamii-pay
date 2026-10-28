-- Lets a group member invite anyone by payment handle, not only people
-- already in their Contacts — the invite target is now resolved and
-- stored directly (wallet + display name) instead of only through a
-- `contacts` row, which required the proposer to have already saved
-- that person. `new_member_contact_id` is kept (still populated when an
-- invite happens to come from an existing contact) but nothing reads
-- through it anymore.
alter table group_withdrawal_requests
    add column if not exists new_member_wallet_id uuid references wallets(id),
    add column if not exists new_member_name text;
