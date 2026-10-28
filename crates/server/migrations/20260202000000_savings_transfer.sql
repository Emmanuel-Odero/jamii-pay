-- "Move to savings" / "withdraw from savings" — a wallet moving its own
-- money between its own two balances, no counterparty and no vote
-- needed (unlike group withdrawals): it's already the owner's money.
alter table transactions drop constraint if exists transactions_kind_check;
alter table transactions add constraint transactions_kind_check
    check (kind in ('transfer', 'cash_out', 'bill_pay', 'airtime', 'savings_move', 'savings_withdraw'));
