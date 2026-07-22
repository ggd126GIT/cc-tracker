# Interest Computation — Design Spec
_Date: 2026-04-25 (revised after logic-gap audit)_

## Overview

Add per-loan interest computation to the borrower/loan system. Each loan can opt into interest tracking with a configurable rate, type, and penalty structure. All financial history is stored in an immutable ledger that mirrors industry-standard bank-statement output.

---

## Decisions Made

| Question | Decision |
|---|---|
| Interest type | Per-loan choice: **Simple** or **Diminishing Balance** |
| Penalty interest | Added **on top** of regular interest (not a replacement) |
| Penalty trigger | **Auto-applied** when due date is missed; manual override via penalty waiver entry |
| Penalty rates | Configurable per loan (default: 1% late fee + 5%/mo penalty interest) |
| Partial payment threshold | Optional `minimum_payment` field — if set, partial payments still trigger penalties |
| Payment allocation | **Penalties → Interest → Principal** (industry standard) |
| Rate changes | **Forward-only** from effective date ≥ last ledger entry date; full history preserved |
| Accrual frequency | **Monthly** (weekly support reserved for future) |
| First period proration | **None** — always one full period's interest on first due date regardless of loan start day |
| One payment = one period | One `payment` ledger entry covers exactly one billing period |
| Architecture | **Ledger-based** — every financial event is an immutable DB row |
| Entry generation | **Lazy** — generated when the loan page is opened, no cron job needed |
| Backward compat | Existing loans with `interest_bearing = false` are completely untouched |

---

## Data Model

### 1. `loans` table — two new columns

```sql
ALTER TABLE loans
  ADD COLUMN interest_bearing  BOOLEAN         NOT NULL DEFAULT false,
  ADD COLUMN minimum_payment   numeric(15,4)   NULL;     -- NULL = any amount clears period
```

`interest_bearing = false` → existing behavior (uses `loan_payments`, no interest math).
`interest_bearing = true` → new behavior (uses `loan_ledger`, interest computed on open).

`minimum_payment` — optional installment threshold. When set, a period is only considered paid if the sum of payments for that `period_date` ≥ `minimum_payment`. If null, any payment of any amount clears the missed-payment flag.

---

### 2. `loan_interest_rates` — rate history per loan

```sql
CREATE TABLE loan_interest_rates (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id         uuid NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES auth.users(id),
  interest_rate   numeric(8,4)  NOT NULL,          -- e.g. 4.0000 = 4%
  interest_type   text NOT NULL CHECK (interest_type IN ('simple', 'diminishing')),
  rate_period     text NOT NULL DEFAULT 'monthly'
                    CHECK (rate_period IN ('monthly')),  -- weekly reserved
  late_fee_rate   numeric(8,4)  NOT NULL DEFAULT 1.0,   -- % of outstanding
  penalty_rate    numeric(8,4)  NOT NULL DEFAULT 5.0,   -- % per month
  effective_from  date NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);
```

**Active rate for a given date** = the row where `effective_from <= date`, ordered by `effective_from DESC LIMIT 1`.

Rate changes are **insert-only** — existing rows are never updated or deleted.

**Validation**: `effective_from` must be ≥ the `period_date` of the most recent ledger entry for this loan (or ≥ today if no ledger entries yet). Prevents retroactive rate changes that would conflict with already-computed immutable entries.

RLS: owner (`user_id = auth.uid()`) read/write only.

---

### 3. `loan_ledger` — immutable financial event log

```sql
CREATE TABLE loan_ledger (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id           uuid NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  user_id           uuid NOT NULL REFERENCES auth.users(id),
  entry_type        text NOT NULL CHECK (entry_type IN (
                      'interest_charge',
                      'late_fee',
                      'penalty_interest',
                      'payment',
                      'penalty_waiver'    -- manual credit to offset a penalty
                    )),
  amount            numeric(15,4) NOT NULL CHECK (amount > 0),
  -- Payment allocation (populated only for 'payment' entries)
  principal_applied numeric(15,4) NOT NULL DEFAULT 0,
  interest_applied  numeric(15,4) NOT NULL DEFAULT 0,
  penalty_applied   numeric(15,4) NOT NULL DEFAULT 0,
  period_date       date NOT NULL,   -- billing period this entry belongs to
  is_manual         boolean NOT NULL DEFAULT false,
  notes             text,
  created_at        timestamptz NOT NULL DEFAULT now()
);
```

**Entry types:**
- `interest_charge` — auto-generated monthly interest debit
- `late_fee` — 1% of outstanding balance when payment is missed (auto or manual)
- `penalty_interest` — 5%/mo on outstanding balance when payment is missed (auto or manual)
- `payment` — payment received (credit), with allocation breakdown
- `penalty_waiver` — manual credit that offsets existing penalties (inserted by lender to forgive a penalty); `is_manual = true` always

Ledger entries are **never updated or deleted** after creation. Corrections are made by inserting new offset entries.

RLS: owner read/write only.

---

## Computation Engine

New file: `src/utils/loanInterest.js`

All arithmetic uses integer cents via the existing `money.js` helpers (`toCents`, `fromCents`) to avoid IEEE 754 errors.

### `getActiveRate(rateHistory, date)`
Returns the rate row with the highest `effective_from` that is ≤ `date`. Returns `null` if none found. Callers must handle `null` by skipping the period.

### `computeInterestCharge(loanAmount, principalBalance, rate, interestType)`
- **Simple**: `loanAmount × rate / 100` — always on the original loan amount, never changes as payments come in
- **Diminishing**: `principalBalance × rate / 100` — shrinks as principal is paid down

All arithmetic in integer cents. Result returned as PHP numeric.

### `computeOutstanding(loanAmount, ledgerEntries)`
Returns `{ principalBalance, interestBalance, penaltyBalance, total }`.

```
principalBalance = loanAmount − Σ(principal_applied from payment entries)
interestBalance  = Σ(interest_charge) − Σ(interest_applied from payment entries)
penaltyBalance   = Σ(late_fee + penalty_interest) − Σ(penalty_applied from payment entries)
                   − Σ(penalty_waiver entries)
total            = principalBalance + interestBalance + penaltyBalance
```

All four values are always ≥ 0 (floor at 0).

### `allocatePayment(paymentAmount, outstanding)`
Returns `{ principalApplied, interestApplied, penaltyApplied }`.

```
1. penaltyApplied  = min(paymentAmount, outstanding.penaltyBalance)
   remainder      -= penaltyApplied
2. interestApplied = min(remainder, outstanding.interestBalance)
   remainder      -= interestApplied
3. principalApplied = min(remainder, outstanding.principalBalance)
   -- capped at principalBalance — cannot reduce principal below 0
```

The payment input in `LoanPaymentModal` is capped at `outstanding.total` (not just principal) to prevent overpayment.

### `isPeriodSufficientlyPaid(periodDate, ledgerEntries, minimumPayment)`
Returns `true` if the period should be treated as paid (no missed-payment penalties apply).

```
periodPayments = sum of amount for all 'payment' entries with period_date = periodDate
if minimumPayment is null:
    return periodPayments > 0        -- any payment clears the period
else:
    return periodPayments >= minimumPayment   -- must meet the installment threshold
```

### `generateMissingEntries(loan, rateHistory, ledgerEntries, today)`

**Guard**: if `loan.status === 'completed'` OR `loan.status === 'defaulted'`, return `[]` immediately.

Returns an array of ledger entry objects to insert for all due dates that have passed with no existing `interest_charge` entry.

**Period iteration** — starting from `loan.next_payment_date` (set at loan creation), walk forward using `advanceNextPaymentDate`:
- For `payment_frequency = 'one-time'`: after the first due date, if no payment exists, continue generating monthly entries from that due date forward (monthly cadence) until today. This handles the "one-time loan that goes unpaid" scenario.
- For `weekly` / `monthly`: use normal `advanceNextPaymentDate` cadence.

**For each missing period** (no `interest_charge` entry for this `period_date`):
1. Call `getActiveRate(rateHistory, periodDate)` — if `null`, skip this period
2. Compute `interest_charge` via `computeInterestCharge` using current outstanding principal balance
3. Tentatively add the `interest_charge` to the running outstanding total
4. Call `isPeriodSufficientlyPaid(periodDate, ledgerEntries, loan.minimum_payment)`
5. If not sufficiently paid (missed): generate `late_fee` and `penalty_interest` on the outstanding total **after** step 3 (penalties include that period's interest in their base)
6. Add all generated entries to the result array

`period_date` for a **payment entry** is the loan's `next_payment_date` at the moment the payment is recorded. If `next_payment_date` is null (one-time loan past due with no scheduled next date), use the last unpaid `period_date` from the generated missing entries.

---

## Hooks

### `useLoans(borrowerId)` — extended
After fetching loans, for each `interest_bearing` loan:
1. Fetch `loan_ledger` and `loan_interest_rates` in parallel (separate Supabase queries)
2. Call `generateMissingEntries`
3. If entries returned → batch insert to `loan_ledger` via Supabase
4. Invalidate query → re-render with complete ledger

On the **first open** after a due date passes, this causes two fetches: one to detect missing entries, one after insertion. This is expected and intentional — subsequent opens within the same period find no missing entries and skip the insert.

Non-interest-bearing loans: no change to existing behavior.

### `useRecordLoanPayment()` — extended
For `interest_bearing` loans:
1. Compute `outstanding` via `computeOutstanding`
2. Call `allocatePayment` to get the breakdown
3. Insert a `payment` entry to `loan_ledger` with `period_date = loan.next_payment_date` (or last unpaid period_date if next_payment_date is null)
4. If `outstanding.total − paymentAmount ≤ 0` → update `loan.status = 'completed'`, `loan.next_payment_date = null`
5. Otherwise → advance `next_payment_date` via `advanceNextPaymentDate` as before

### New: `useAddLoanInterestRate()`
Inserts a new row to `loan_interest_rates`. Validates `effective_from ≥ most recent ledger entry's period_date` before inserting. Returns an error if validation fails.

### New: `useLoanLedger(loanId)`
Fetches all `loan_ledger` rows for a loan, ordered by `period_date ASC, created_at ASC`. Used by the Statement view.

### New: `useWaivePenalty()`
Inserts a `penalty_waiver` entry to `loan_ledger` with `is_manual = true`. Called from the Statement modal. Amount = the penalty being waived (partial waivers allowed). Invalidates the ledger query.

---

## UI Changes

### LoanForm — new interest section
A toggle **"This loan earns interest"** (default off) reveals:
- Interest Rate (%/month) — numeric, required
- Interest Type — dropdown: Simple | Diminishing Balance
- Late Fee Rate (%) — numeric, default 1.00
- Penalty Rate (%/month) — numeric, default 5.00
- Minimum Monthly Payment (PHP) — numeric, optional. If filled, partial payments below this amount still trigger missed-payment penalties.

On submit, if `interest_bearing = true`:
- Insert loan as normal (including `minimum_payment` if provided)
- Also insert the first row to `loan_interest_rates` with `effective_from = loan_date`

### LoanTable — new columns for interest-bearing loans
Add three columns between "Remaining" and "Next Payment":
- **Interest Due** — `interestBalance` (green)
- **Penalties** — `penaltyBalance` (red, hidden if 0)
- **Total Owed** — `total` (bold)

Non-interest loans show `—` in these columns.

Add two new action buttons per interest-bearing loan row:
- **⚙ Edit Rate** — opens Edit Rate modal
- **📄 Statement** — opens Ledger Statement modal

### LoanPaymentModal — extended for interest-bearing loans
When `loan.interest_bearing = true`:
- Show **Current Balance Breakdown** panel: Principal / Interest Due / Penalties / Total Owed
- Payment input `max` = `outstanding.total` (replaces current `remaining`)
- Show **Payment Allocation Preview** panel that updates live as the user types: → Penalties / → Interest / → Principal
- Show "New principal balance after payment: ₱X" below allocation

### New: Edit Rate Modal
- Shows rate history table (read-only, newest first)
- Form to add new rate: Interest Rate, Interest Type, Late Fee Rate, Penalty Rate, Effective From
- `Effective From` defaults to today; validated client-side: must be ≥ `period_date` of last ledger entry. Error shown if user picks an earlier date.
- On save: calls `useAddLoanInterestRate()`

### New: Ledger Statement Modal
- Table columns: Date | Entry | Charge | Payment | Balance
- First row: synthetic "Loan disbursed" row (from `loan.amount` and `loan.loan_date`, not a real ledger entry)
- All ledger entries ordered by `period_date ASC, created_at ASC` with running balance column
- Rate change events shown as informational rows (from `loan_interest_rates`, sorted by `effective_from`)
- `penalty_waiver` entries shown in green as "Penalty waived"
- Per-row "Waive" button on `late_fee` and `penalty_interest` rows (only if not already fully waived)
- Export to PDF/CSV (reuses existing `export.js` infrastructure)

---

## Interest Type Comparison

| | Simple | Diminishing Balance |
|---|---|---|
| Base for interest | Always original `loan.amount` | Current `principalBalance` |
| Interest per month | Fixed (never changes) | Decreases as principal is paid |
| Use case | Contract-style informal loans (like interest.md) | Bank installment loans |

---

## Missed Payment Logic

A period is considered **missed** if all of:
- `period_date < today`
- `loan.status ≠ 'completed'` and `≠ 'defaulted'`
- `isPeriodSufficientlyPaid(periodDate, ledgerEntries, loan.minimum_payment)` returns `false`

On a missed period, two entries are auto-generated after the interest_charge:
```
late_fee         = outstandingTotal × late_fee_rate / 100   (one-time per missed period)
penalty_interest = outstandingTotal × penalty_rate / 100    (per month missed)
```

`outstandingTotal` here is the balance **including** the current period's interest_charge (see step 3 of generateMissingEntries).

Both charges are added **on top of** the regular `interest_charge` for that period.

**Manual penalty waiver**: lender can insert a `penalty_waiver` entry from the Statement modal to partially or fully offset any penalty. Waivers are irreversible (immutable) but additional waivers can be added.

---

## Scenario Walkthroughs

### Scenario A — Normal payment (₱7,000 on a ₱79,000 @ 4%/mo Simple loan, minimum_payment = ₱7,000)
1. April 30 passes. `generateMissingEntries` runs.
2. No `interest_charge` for April 30 → generate: `interest_charge = ₱3,160`
3. `isPeriodSufficientlyPaid` → payments for April 30 = ₱0 < ₱7,000 → missed
4. Outstanding after interest = ₱79,000 + ₱3,160 = ₱82,160
5. `late_fee = ₱82,160 × 1% = ₱821.60`, `penalty_interest = ₱82,160 × 5% = ₱4,108`
6. User records ₱7,000 payment:
   - `allocatePayment`: penalty ₱4,929.60 → interest ₱0 → principal ₱2,070.40
   - `outstanding.total` after = ₱74,090.40 (interest still owed: ₱3,160)

### Scenario B — Partial payment (₱2,000, minimum_payment = ₱7,000)
1. Same as A steps 1-5 — penalties generated
2. User records ₱2,000 payment → period still marked as partial since sum(payments for period) = ₱2,000 < ₱7,000
3. **Next period**: penalties ARE generated because `isPeriodSufficientlyPaid` = false for prior period... wait — penalties are generated per period independently. April 30 already has its penalty entries. May 31 will get its own interest charge. If May 31 also has no sufficient payment, May 31 gets its own penalty entries too.

### Scenario C — Partial payment (₱2,000, minimum_payment = null)
1. Any payment clears the missed flag for that period
2. ₱2,000 → `isPeriodSufficientlyPaid` returns true → NO penalties for April
3. Allocation: penalty ₱0 → interest ₱2,000 (partial) → principal ₱0
4. Interest balance = ₱3,160 − ₱2,000 = ₱1,160 still owed; carries forward

### Scenario D — Overpayment attempt
1. Outstanding total = ₱500 (nearly paid off)
2. User types ₱10,000 in payment modal
3. Modal `max` = ₱500 → input capped client-side
4. Even if ₱10,000 is submitted, `allocatePayment` caps `principalApplied` at `₱500`
5. After payment: `outstanding.total ≤ 0` → loan marked `completed`

### Scenario E — Rate change
1. Loan has entries through April 30 at 4%/mo
2. Lender opens Edit Rate modal, tries to set effective_from = March 1
3. Validation fails: last ledger entry is April 30, effective_from must be ≥ April 30
4. Lender sets effective_from = May 1 → inserts new rate row (3.5%/mo)
5. May 31 interest entry uses 3.5%; all prior entries unchanged

### Scenario F — One-time loan unpaid
1. Loan amount ₱10,000, payment_frequency = 'one-time', due date = June 30
2. June 30 passes. `generateMissingEntries` runs.
3. June 30 has no `interest_charge` → generate interest + penalties (if no payment)
4. Since payment_frequency = 'one-time', next iteration uses monthly cadence from June 30
5. July 31, August 31, etc. all get interest + penalty entries until paid
6. User pays → `useRecordLoanPayment` sets `period_date` to last unpaid period_date (June 30), advances to next outstanding

---

## Backward Compatibility

- All existing loans default to `interest_bearing = false`
- `minimum_payment = null` for all existing loans
- Existing `loan_payments` table and all code paths are unchanged
- `useLoans`, `useRecordLoanPayment`, and all UI components fork on `interest_bearing`
- No data migration required

---

## Out of Scope

- Weekly interest accrual (`rate_period = 'weekly'`) — schema supports it, not implemented now
- Compound interest (interest on interest) — not a requested type
- Shared borrower read-only view for interest data — deferred
- Push/email notifications for missed payments — deferred
