# Reconstructed schema

The original Supabase project became inaccessible (its dashboard login was
tied to a GitHub account that was lost). No SQL migration files ever existed
in this repo, so `schema.sql` was rebuilt by reading every planning/spec doc
under `docs/superpowers/` in chronological order and reconciling their
`CREATE TABLE` / `ALTER TABLE` statements into one end-state schema, then
cross-checking every table/column name against the actual current code in
`src/hooks/*.js` (the ground truth for what the app queries today).

Run `schema.sql` once, top to bottom, against a brand-new empty Supabase
project's SQL Editor. It creates all 16 tables, RLS policies, the two RPCs
(`claim_pending_shares`, `claim_pending_borrower_shares`), the `updated_at`
trigger on `transactions`, and the private `attachments` storage bucket +
policies.

## Not fully confident about — please verify after running

- **`loan_interest_rates.interest_rate` and `loan_ledger.amount` CHECK
  constraints**: the original plan doc had `CHECK (amount > 0)` /
  `CHECK (interest_rate > 0)`. Session memory records that 0% interest rate
  support was added afterward (commit `5cfa672`), which requires these to
  allow zero. I relaxed both to `>= 0` since a `> 0` constraint would reject
  a legitimate $0 interest_charge row on a 0%-rate loan. I could not find the
  exact `ALTER TABLE ... DROP CONSTRAINT / ADD CONSTRAINT` statement anywhere
  in the docs, so this is an inference, not a recovered statement. If your
  app throws a Postgres check-violation on 0%-rate loans, this constraint is
  the first place to look.

- **`shares` / `transactions` and `cards` viewer SELECT policies**: the
  card-sharing spec's own note says "split the existing policy first if it's
  a single all-operations policy," but never spells out the drop/recreate
  SQL. `schema.sql` does **not** split the original owner `for all` policy —
  it just adds a second permissive `for select` policy for viewers.
  Postgres OR-combines multiple permissive policies for the same command, so
  this should be equivalent, but it's a reconstruction, not a literal replay
  of what was run originally.

- **`payments` and `borrowers` tables have no viewer SELECT policy** — this
  matches what the docs describe (card sharing only extended `cards` +
  `transactions`; borrower sharing avoided RLS on `borrowers`/`loans` reads
  by denormalizing borrower name/phone/email onto `borrower_shares` instead).
  If a shared/read-only view in the app turns out to need direct `payments`
  or `borrowers` access, that RLS policy never existed in the docs and will
  need to be added fresh.

- **Historical loan payments** (`is_manual = true`, `notes = 'Historical
  payment'` on `loan_ledger`) — this is application-level behavior in
  `useAddLoan`, not a schema feature. No schema changes were needed for it,
  but flagging it here since it wasn't in the original interest-computation
  design doc and was added in a later session.

## What's intentionally NOT recreated

- Any actual data. This is schema only — the old project's rows (loans,
  borrowers, transactions, payment history, receipts in Storage, etc.) are
  gone unless you can still recover the old Supabase account.
- Supabase Auth users — you'll need to sign up again in the new project.
- The `attachments` storage bucket will be empty — old uploaded files are
  not recoverable from this file.
