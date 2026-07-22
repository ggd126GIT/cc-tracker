-- ============================================================================
-- CC Tracker — Consolidated Supabase Schema
-- ============================================================================
-- RECONSTRUCTED from docs/superpowers/plans/*.md and docs/superpowers/specs/*.md
-- after the original Supabase project became inaccessible (GitHub OAuth login
-- lost). This file is NOT a copy of a real migration history — it is a
-- best-effort reassembly. Read supabase/README.md before running this on a
-- fresh project, especially the "Not fully confident about" section.
--
-- Run this entire file once, in order, against a brand-new empty Supabase
-- project (SQL Editor → New query → paste → Run). It targets Postgres +
-- Supabase's built-in `auth.users` and `storage` schemas.
-- ============================================================================


-- ============================================================================
-- 1. cards  — source: docs/superpowers/plans/2026-04-10-cc-tracker.md
-- ============================================================================
create table cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  bank_name text not null,
  nickname text not null,
  cardholder_name text not null,
  expiry_display text not null,        -- display only, e.g. "12/26"
  mock_last4 text not null default '0000',
  spending_limit numeric(12,2) not null default 0,
  color_primary text not null default '#1a3a52',
  color_secondary text not null default '#2d6a8f',
  created_at timestamptz not null default now()
);
alter table cards enable row level security;

create policy "Users own cards" on cards
  for all using (auth.uid() = user_id);


-- ============================================================================
-- 2. borrowers  — source: docs/superpowers/plans/2026-04-11-borrowers-feature.md
-- ============================================================================
create table borrowers (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users not null,
  full_name text not null,
  address text not null,
  phone text not null,
  email text not null,
  is_archived boolean default false,
  created_at timestamptz default now()
);
alter table borrowers enable row level security;
create policy "Users manage own borrowers" on borrowers
  for all using (auth.uid() = user_id);


-- ============================================================================
-- 3. expenses  — source: docs/superpowers/plans/2026-04-14-expenses-tracker.md
-- ============================================================================
create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category in (
    'utilities','food','transportation','rent','healthcare',
    'shopping','entertainment','subscriptions','education',
    'personal_care','insurance','others'
  )),
  description text not null,
  amount numeric(12,2) not null check (amount > 0),
  expense_date date not null,
  payment_method text not null check (payment_method in (
    'cash','gcash','maya','bank_transfer','others'
  )),
  notes text,
  archived boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.expenses enable row level security;

create policy "Users can view own expenses"
  on public.expenses for select using (auth.uid() = user_id);
create policy "Users can insert own expenses"
  on public.expenses for insert with check (auth.uid() = user_id);
create policy "Users can update own expenses"
  on public.expenses for update using (auth.uid() = user_id);
create policy "Users can delete own expenses"
  on public.expenses for delete using (auth.uid() = user_id);

create index expenses_user_id_date_idx
  on public.expenses(user_id, expense_date desc);


-- ============================================================================
-- 4. shares  — card sharing. source: docs/superpowers/plans/2026-04-11-card-sharing.md
-- ============================================================================
create table shares (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid references auth.users not null,
  owner_email  text not null,
  viewer_email text not null,
  viewer_id    uuid references auth.users,
  card_ids     uuid[] not null,
  status       text not null default 'unclaimed'
               check (status in ('unclaimed', 'pending', 'active', 'declined')),
  created_at   timestamptz default now()
);

-- Prevent duplicate active/pending invites (allows re-invite after decline)
create unique index shares_owner_viewer_unique
  on shares(owner_id, lower(viewer_email))
  where status not in ('declined');

alter table shares enable row level security;

create policy "owner_manage_shares" on shares
  for all using (auth.uid() = owner_id);

create policy "viewer_read_shares" on shares
  for select using (
    auth.uid() = viewer_id
    or lower(viewer_email) = lower((
      select email from auth.users where id = auth.uid()
    ))
  );

create policy "viewer_update_status" on shares
  for update using (auth.uid() = viewer_id)
  with check (auth.uid() = viewer_id);

create or replace function claim_pending_shares()
returns void
language plpgsql security definer as $$
begin
  update shares
  set viewer_id = auth.uid(),
      status    = 'pending'
  where lower(viewer_email) = lower((
          select email from auth.users where id = auth.uid()
        ))
    and viewer_id is null
    and status = 'unclaimed';
end;
$$;

-- Viewer read-path for shared cards (added on top of the owner "for all" policy —
-- Postgres OR-combines multiple permissive policies for the same command)
create policy "viewer_select_shared_cards" on cards
  for select using (
    user_id = auth.uid()
    or id = any(
      select unnest(card_ids) from shares
      where viewer_id = auth.uid() and status = 'active'
    )
  );


-- ============================================================================
-- 5. borrower_shares  — source: docs/superpowers/plans/2026-04-11-borrower-sharing.md
-- ============================================================================
create table borrower_shares (
  id uuid default gen_random_uuid() primary key,
  owner_id uuid references auth.users not null,
  owner_email text not null,
  viewer_email text not null,
  viewer_id uuid references auth.users,
  borrower_id uuid references borrowers(id) on delete cascade not null,
  borrower_name text not null,
  borrower_phone text not null,
  borrower_email text not null,
  status text not null default 'unclaimed',
  created_at timestamptz default now()
);
alter table borrower_shares enable row level security;

create policy "Owner manages borrower shares" on borrower_shares
  for all using (auth.uid() = owner_id);

create policy "Viewer reads borrower shares" on borrower_shares
  for select using (
    viewer_id = auth.uid()
    or viewer_email = (select email from auth.users where id = auth.uid())
  );

create policy "Viewer updates borrower shares" on borrower_shares
  for update using (viewer_id = auth.uid());

create or replace function claim_pending_borrower_shares()
returns void language plpgsql security definer as $$
declare
  _user_email text;
  _user_id uuid;
begin
  select id, email into _user_id, _user_email
  from auth.users where id = auth.uid();

  update borrower_shares
  set viewer_id = _user_id, status = 'pending'
  where viewer_email = _user_email
    and status = 'unclaimed';
end;
$$;


-- ============================================================================
-- 6. billing_cycles  — source: docs/superpowers/plans/2026-04-18-card-transactions-v2.md
-- ============================================================================
create table billing_cycles (
  id         uuid primary key default gen_random_uuid(),
  card_id    uuid references cards(id) not null,
  user_id    uuid references auth.users(id) not null,
  label      text not null,
  start_date date not null,
  end_date   date not null,
  closed_at  timestamptz not null default now(),
  created_at timestamptz not null default now()
);
alter table billing_cycles enable row level security;
create policy "Users can manage their own billing cycles"
  on billing_cycles for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ============================================================================
-- 7. transactions  — source: 2026-04-10-cc-tracker.md, extended by
--    2026-04-18-card-transactions-v2.md (cycle_id) and card-sharing (viewer SELECT)
-- ============================================================================
create table transactions (
  id uuid primary key default gen_random_uuid(),
  card_id uuid references cards(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  transaction_date date not null,
  amount numeric(12,2) not null,
  payment_due_date date,
  payment_status text not null default 'unpaid'
    check (payment_status in ('unpaid', 'partial', 'paid')),
  amount_paid numeric(12,2) not null default 0,
  notes text,
  is_archived boolean not null default false,
  cycle_id uuid references billing_cycles(id) default null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger transactions_updated_at
  before update on transactions
  for each row execute function update_updated_at();

alter table transactions enable row level security;

create policy "Users own transactions" on transactions
  for all using (auth.uid() = user_id);

create policy "viewer_select_shared_transactions" on transactions
  for select using (
    user_id = auth.uid()
    or card_id = any(
      select unnest(card_ids) from shares
      where viewer_id = auth.uid() and status = 'active'
    )
  );


-- ============================================================================
-- 8. payments  — card transaction payment history. source: 2026-04-10-cc-tracker.md
-- ============================================================================
create table payments (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid references transactions(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  amount numeric(12,2) not null,
  notes text,
  paid_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
alter table payments enable row level security;
create policy "Users own payments" on payments
  for all using (auth.uid() = user_id);


-- ============================================================================
-- 9. transaction_attachments  — source: docs/superpowers/plans/2026-04-12-attachments.md
-- ============================================================================
create table transaction_attachments (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid references transactions(id) on delete cascade not null,
  user_id uuid references auth.users(id) not null,
  file_path text not null,
  file_name text not null,
  file_size int8 not null,
  mime_type text not null,
  created_at timestamptz not null default now()
);
alter table transaction_attachments enable row level security;

create policy "Owner manages transaction_attachments" on transaction_attachments
  for all using (auth.uid() = user_id);

create policy "Viewer reads transaction_attachments" on transaction_attachments
  for select using (
    exists (
      select 1 from transactions t
      join shares s on s.card_ids @> array[t.card_id]::uuid[]
      where t.id = transaction_attachments.transaction_id
        and s.viewer_id = auth.uid()
        and s.status = 'active'
    )
  );


-- ============================================================================
-- 10. payment_attachments  — receipts on card payments.
--     source: docs/superpowers/plans/2026-04-24-payment-receipts.md
-- ============================================================================
create table payment_attachments (
  id               uuid         primary key default gen_random_uuid(),
  payment_id       uuid         not null references payments(id) on delete cascade,
  user_id          uuid         not null references auth.users(id) on delete cascade,
  file_path        text         not null,
  file_name        text         not null,
  file_size        integer      not null,
  mime_type        text         not null,
  created_at       timestamptz  default now()
);
alter table payment_attachments enable row level security;
create policy "Users manage own payment attachments"
  on payment_attachments for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ============================================================================
-- 11. loans  — source: 2026-04-11-borrowers-feature.md, extended by
--     borrower-sharing (viewer SELECT) and 2026-04-25-interest-computation.md
--     (interest_bearing, minimum_payment)
-- ============================================================================
create table loans (
  id uuid default gen_random_uuid() primary key,
  borrower_id uuid references borrowers(id) on delete cascade not null,
  user_id uuid references auth.users not null,
  amount numeric not null,
  loan_date date not null,
  description text,
  payment_frequency text not null default 'one-time',
  payment_day integer,
  next_payment_date date,
  status text not null default 'active',
  notarized boolean default false,
  lawyer_name text,
  ptr_number text,
  date_notarized date,
  is_archived boolean default false,
  interest_bearing boolean not null default false,
  minimum_payment numeric(15,4) null,   -- null = any payment amount clears a period
  created_at timestamptz default now()
);
alter table loans enable row level security;

create policy "Users manage own loans" on loans
  for all using (auth.uid() = user_id);

create policy "Viewer reads shared loans" on loans
  for select using (
    exists (
      select 1 from borrower_shares
      where borrower_id = loans.borrower_id
        and viewer_id = auth.uid()
        and status = 'active'
    )
  );


-- ============================================================================
-- 12. loan_payments  — source: 2026-04-11-borrowers-feature.md,
--     extended by borrower-sharing (viewer SELECT)
-- ============================================================================
create table loan_payments (
  id uuid default gen_random_uuid() primary key,
  loan_id uuid references loans(id) on delete cascade not null,
  user_id uuid references auth.users not null,
  amount numeric not null,
  notes text,
  paid_at timestamptz default now()
);
alter table loan_payments enable row level security;

create policy "Users manage own loan_payments" on loan_payments
  for all using (auth.uid() = user_id);

create policy "Viewer reads shared loan_payments" on loan_payments
  for select using (
    exists (
      select 1 from loans l
      join borrower_shares bs on bs.borrower_id = l.borrower_id
      where l.id = loan_payments.loan_id
        and bs.viewer_id = auth.uid()
        and bs.status = 'active'
    )
  );


-- ============================================================================
-- 13. loan_attachments  — source: docs/superpowers/plans/2026-04-12-attachments.md
--     NOTE: plan deviated from the original design spec (which named this table
--     loan_payment_attachments w/ FK -> loan_payments). Actual shipped code
--     (src/hooks/useAttachments.js) uses loan_attachments w/ FK -> loans, plus a
--     denormalized borrower_id for RLS. That is what's captured here.
-- ============================================================================
create table loan_attachments (
  id uuid primary key default gen_random_uuid(),
  loan_id uuid references loans(id) on delete cascade not null,
  borrower_id uuid references borrowers(id) on delete cascade not null,
  user_id uuid references auth.users(id) not null,
  file_path text not null,
  file_name text not null,
  file_size int8 not null,
  mime_type text not null,
  created_at timestamptz not null default now()
);
alter table loan_attachments enable row level security;

create policy "Owner manages loan_attachments" on loan_attachments
  for all using (auth.uid() = user_id);

create policy "Viewer reads loan_attachments" on loan_attachments
  for select using (
    exists (
      select 1 from borrower_shares bs
      where bs.borrower_id = loan_attachments.borrower_id
        and bs.viewer_id = auth.uid()
        and bs.status = 'active'
    )
  );


-- ============================================================================
-- 14. loan_payment_attachments  — receipts on loan payments (non-interest-bearing
--     loans only — interest-bearing loans record payments in loan_ledger instead).
--     source: docs/superpowers/plans/2026-04-24-payment-receipts.md
-- ============================================================================
create table loan_payment_attachments (
  id                  uuid         primary key default gen_random_uuid(),
  loan_payment_id     uuid         not null references loan_payments(id) on delete cascade,
  user_id             uuid         not null references auth.users(id) on delete cascade,
  file_path           text         not null,
  file_name           text         not null,
  file_size           integer      not null,
  mime_type           text         not null,
  created_at          timestamptz  default now()
);
alter table loan_payment_attachments enable row level security;
create policy "Users manage own loan payment attachments"
  on loan_payment_attachments for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ============================================================================
-- 15. loan_interest_rates  — rate history per loan (insert-only).
--     source: docs/superpowers/plans/2026-04-25-interest-computation.md
-- ============================================================================
create table loan_interest_rates (
  id             uuid primary key default gen_random_uuid(),
  loan_id        uuid not null references loans(id) on delete cascade,
  user_id        uuid not null references auth.users(id),
  interest_rate  numeric(8,4) not null check (interest_rate >= 0),
  interest_type  text not null check (interest_type in ('simple', 'diminishing')),
  rate_period    text not null default 'monthly' check (rate_period in ('monthly')),
  late_fee_rate  numeric(8,4) not null default 1.0 check (late_fee_rate >= 0),
  penalty_rate   numeric(8,4) not null default 5.0 check (penalty_rate >= 0),
  effective_from date not null,
  created_at     timestamptz not null default now()
);
-- NOTE: interest_rate check relaxed to >= 0 (not > 0) — session notes record
-- "0% interest rate" support being added after the original plan shipped with
-- `> 0`. See README for confidence level on this line.

alter table loan_interest_rates enable row level security;
create policy "owner_all" on loan_interest_rates
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create index idx_lir_loan_id on loan_interest_rates(loan_id);


-- ============================================================================
-- 16. loan_ledger  — immutable financial event log for interest-bearing loans.
--     source: docs/superpowers/plans/2026-04-25-interest-computation.md
-- ============================================================================
create table loan_ledger (
  id                uuid primary key default gen_random_uuid(),
  loan_id           uuid not null references loans(id) on delete cascade,
  user_id           uuid not null references auth.users(id),
  entry_type        text not null check (entry_type in (
                      'interest_charge', 'late_fee', 'penalty_interest',
                      'payment', 'penalty_waiver'
                    )),
  amount            numeric(15,4) not null check (amount >= 0),
  principal_applied numeric(15,4) not null default 0,
  interest_applied  numeric(15,4) not null default 0,
  penalty_applied   numeric(15,4) not null default 0,
  period_date       date not null,
  is_manual         boolean not null default false,
  notes             text,
  created_at        timestamptz not null default now()
);
-- NOTE: amount check relaxed to >= 0 (original plan had `> 0`) — 0% interest
-- rate loans can generate a $0 interest_charge entry. See README.

alter table loan_ledger enable row level security;
create policy "owner_all" on loan_ledger
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create index idx_ll_loan_id on loan_ledger(loan_id);
create index idx_ll_period_date on loan_ledger(loan_id, period_date);


-- ============================================================================
-- Storage — private bucket for all file attachments (screenshots, PDFs,
-- notarized documents, payment receipts). source: 2026-04-12-attachments.md
-- ============================================================================
insert into storage.buckets (id, name, public)
values ('attachments', 'attachments', false)
on conflict (id) do nothing;

create policy "Authenticated users can upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'attachments');

create policy "Authenticated users can read"
  on storage.objects for select to authenticated
  using (bucket_id = 'attachments');

create policy "Authenticated users can delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'attachments');

-- ============================================================================
-- End of schema
-- ============================================================================
