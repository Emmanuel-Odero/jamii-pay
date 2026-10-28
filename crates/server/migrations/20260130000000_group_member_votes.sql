-- Generalizes `group_withdrawal_requests` from "vote to move money" into
-- "vote on any group action" — adding or removing a member now goes
-- through the exact same approve/withhold/veto tally
-- (`crates/server/src/group_vote.rs`) as a withdrawal, rather than a
-- separate ad-hoc mechanism. `amount_usd_cents`/`payee_name` are only
-- meaningful for `action_type = 'withdrawal'`, hence dropping their
-- not-null constraints.
alter table group_withdrawal_requests
    add column if not exists action_type text not null default 'withdrawal'
        check (action_type in ('withdrawal', 'add_member', 'remove_member')),
    add column if not exists target_member_id uuid references group_members(id),
    add column if not exists new_member_contact_id uuid references contacts(id);

alter table group_withdrawal_requests alter column amount_usd_cents drop not null;
alter table group_withdrawal_requests alter column payee_name drop not null;

-- A removed member's past votes must stay intact (group_votes.member_id
-- references them), so removal is a soft-delete: `active = false` drops
-- them from the live member list and the voting-power split, without
-- breaking history.
alter table group_members add column if not exists active boolean not null default true;
