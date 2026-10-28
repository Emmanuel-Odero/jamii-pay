-- Two-phase "add member": the invitee must accept before the proposal
-- is even visible to the rest of the group for a vote — see
-- `routes/groups.rs`'s `propose_add_member`/`respond_to_invite`. Only
-- meaningful for `action_type = 'add_member'`; null for withdrawals and
-- remove-member proposals, which have no invitee to wait on.
alter table group_withdrawal_requests
    add column if not exists invite_status text check (invite_status in ('pending', 'accepted', 'declined'));
