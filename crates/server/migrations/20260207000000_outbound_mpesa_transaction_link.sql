-- Links each outbound_mpesa_payments row back to the `transactions` row
-- it corresponds to, so the B2C result/timeout callback
-- (routes/send_to_mpesa.rs) can find and settle/fail the right
-- transaction without guessing by wallet+kind+timestamp.
alter table outbound_mpesa_payments
    add column if not exists transaction_id uuid references transactions(id);
