# Interest Computation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-loan interest computation with a ledger-based audit trail, configurable rates, auto-generated penalties for missed payments, and a full statement view.

**Architecture:** Each interest-bearing loan maintains two side tables — `loan_interest_rates` (rate history, insert-only) and `loan_ledger` (immutable financial events). When the loan page opens, the app lazily generates any missing interest/penalty entries for past periods. Non-interest-bearing loans are completely unaffected.

**Tech Stack:** React 18, Supabase (Postgres + RLS), React Query v5, React Hook Form + Zod, Tailwind CSS, Vitest

---

## File Map

| File | Change |
|---|---|
| Supabase SQL editor | Run migration (Task 1) |
| `src/utils/loanInterest.js` | **CREATE** — computation engine |
| `src/utils/loanInterest.test.js` | **CREATE** — unit tests |
| `src/lib/zod-schemas.js` | **MODIFY** — add interest fields to loanSchema + new rateSchema |
| `src/hooks/useLoans.js` | **MODIFY** — extend useLoans, useRecordLoanPayment; add 3 new hooks |
| `src/components/borrowers/LoanForm.jsx` | **MODIFY** — add interest toggle + 5 new fields |
| `src/components/borrowers/EditRateModal.jsx` | **CREATE** — rate history + new rate form |
| `src/components/borrowers/LoanPaymentModal.jsx` | **MODIFY** — balance breakdown + live allocation preview |
| `src/components/borrowers/LoanTable.jsx` | **MODIFY** — 3 new columns + Edit Rate + Statement buttons |
| `src/components/borrowers/LedgerStatementModal.jsx` | **CREATE** — full statement + waiver UI |

---

## Task 1: Database Migration

**Files:**
- Run in: Supabase Dashboard → SQL Editor

- [ ] **Step 1: Run the migration SQL**

Open the Supabase dashboard, go to SQL Editor, paste and run:

```sql
-- 1. Add two columns to loans table
ALTER TABLE loans
  ADD COLUMN IF NOT EXISTS interest_bearing BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS minimum_payment  NUMERIC(15,4) NULL;

-- 2. Rate history table
CREATE TABLE IF NOT EXISTS loan_interest_rates (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id        UUID NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  user_id        UUID NOT NULL REFERENCES auth.users(id),
  interest_rate  NUMERIC(8,4) NOT NULL CHECK (interest_rate > 0),
  interest_type  TEXT NOT NULL CHECK (interest_type IN ('simple', 'diminishing')),
  rate_period    TEXT NOT NULL DEFAULT 'monthly' CHECK (rate_period IN ('monthly')),
  late_fee_rate  NUMERIC(8,4) NOT NULL DEFAULT 1.0 CHECK (late_fee_rate >= 0),
  penalty_rate   NUMERIC(8,4) NOT NULL DEFAULT 5.0 CHECK (penalty_rate >= 0),
  effective_from DATE NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE loan_interest_rates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner_all" ON loan_interest_rates
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_lir_loan_id ON loan_interest_rates(loan_id);

-- 3. Immutable financial event ledger
CREATE TABLE IF NOT EXISTS loan_ledger (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id           UUID NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES auth.users(id),
  entry_type        TEXT NOT NULL CHECK (entry_type IN (
                      'interest_charge', 'late_fee', 'penalty_interest',
                      'payment', 'penalty_waiver'
                    )),
  amount            NUMERIC(15,4) NOT NULL CHECK (amount > 0),
  principal_applied NUMERIC(15,4) NOT NULL DEFAULT 0,
  interest_applied  NUMERIC(15,4) NOT NULL DEFAULT 0,
  penalty_applied   NUMERIC(15,4) NOT NULL DEFAULT 0,
  period_date       DATE NOT NULL,
  is_manual         BOOLEAN NOT NULL DEFAULT false,
  notes             TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE loan_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner_all" ON loan_ledger
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_ll_loan_id ON loan_ledger(loan_id);
CREATE INDEX IF NOT EXISTS idx_ll_period_date ON loan_ledger(loan_id, period_date);
```

- [ ] **Step 2: Verify in Table Editor**

In Supabase Table Editor, confirm:
- `loans` table has `interest_bearing` (bool, default false) and `minimum_payment` (numeric, nullable)
- `loan_interest_rates` table exists with all columns
- `loan_ledger` table exists with all columns and RLS enabled

- [ ] **Step 3: Commit (empty commit for DB record)**

```bash
git commit --allow-empty -m "db: add loan_ledger, loan_interest_rates tables and interest_bearing column"
```

---

## Task 2: Computation Engine + Tests

**Files:**
- Create: `src/utils/loanInterest.js`
- Create: `src/utils/loanInterest.test.js`

- [ ] **Step 1: Write the failing tests first**

Create `src/utils/loanInterest.test.js`:

```javascript
import { describe, it, expect } from 'vitest'
import {
  getActiveRate,
  computeInterestCharge,
  computeOutstanding,
  allocatePayment,
  isPeriodSufficientlyPaid,
  generateMissingEntries,
  getNextPeriodDate,
} from './loanInterest.js'

// ─── getActiveRate ────────────────────────────────────────────────────────────

describe('getActiveRate', () => {
  const rates = [
    { id: '1', effective_from: '2025-01-01', interest_rate: 4 },
    { id: '2', effective_from: '2025-06-01', interest_rate: 3.5 },
    { id: '3', effective_from: '2026-01-01', interest_rate: 3 },
  ]

  it('returns the most recent rate on or before date', () =>
    expect(getActiveRate(rates, '2025-08-01').id).toBe('2'))

  it('returns first rate when date is exactly effective_from', () =>
    expect(getActiveRate(rates, '2025-01-01').id).toBe('1'))

  it('returns null when no rate applies', () =>
    expect(getActiveRate(rates, '2024-12-31')).toBeNull())

  it('returns most recent when date is after all rates', () =>
    expect(getActiveRate(rates, '2099-01-01').id).toBe('3'))

  it('handles empty array', () =>
    expect(getActiveRate([], '2025-01-01')).toBeNull())
})

// ─── computeInterestCharge ───────────────────────────────────────────────────

describe('computeInterestCharge', () => {
  it('simple: always uses loanAmount regardless of principal paid', () => {
    expect(computeInterestCharge(79000, 70000, 4, 'simple')).toBe(3160)
  })

  it('diminishing: uses principalBalance', () => {
    expect(computeInterestCharge(79000, 70000, 4, 'diminishing')).toBe(2800)
  })

  it('simple: produces same charge after partial payment', () => {
    expect(computeInterestCharge(79000, 50000, 4, 'simple')).toBe(3160)
  })

  it('handles fractional rates without float error', () => {
    // 3.5% of 10000 = 350
    expect(computeInterestCharge(10000, 10000, 3.5, 'simple')).toBe(350)
  })

  it('rounds to nearest cent', () => {
    // 4% of 79001 = 3160.04 → rounds to 3160.04 (exact cents)
    expect(computeInterestCharge(79001, 79001, 4, 'simple')).toBeCloseTo(3160.04, 2)
  })
})

// ─── computeOutstanding ──────────────────────────────────────────────────────

describe('computeOutstanding', () => {
  it('empty ledger: principalBalance equals loanAmount', () => {
    const out = computeOutstanding(79000, [])
    expect(out.principalBalance).toBe(79000)
    expect(out.interestBalance).toBe(0)
    expect(out.penaltyBalance).toBe(0)
    expect(out.total).toBe(79000)
  })

  it('interest_charge increases interestBalance', () => {
    const ledger = [
      { entry_type: 'interest_charge', amount: 3160, principal_applied: 0, interest_applied: 0, penalty_applied: 0 },
    ]
    const out = computeOutstanding(79000, ledger)
    expect(out.interestBalance).toBe(3160)
    expect(out.total).toBe(82160)
  })

  it('payment reduces all balances per allocation', () => {
    const ledger = [
      { entry_type: 'interest_charge', amount: 3160, principal_applied: 0, interest_applied: 0, penalty_applied: 0 },
      { entry_type: 'payment', amount: 7000, principal_applied: 3840, interest_applied: 3160, penalty_applied: 0 },
    ]
    const out = computeOutstanding(79000, ledger)
    expect(out.principalBalance).toBe(75160)
    expect(out.interestBalance).toBe(0)
    expect(out.total).toBe(75160)
  })

  it('penalty_waiver reduces penaltyBalance', () => {
    const ledger = [
      { entry_type: 'late_fee', amount: 500, principal_applied: 0, interest_applied: 0, penalty_applied: 0 },
      { entry_type: 'penalty_waiver', amount: 500, principal_applied: 0, interest_applied: 0, penalty_applied: 0 },
    ]
    const out = computeOutstanding(10000, ledger)
    expect(out.penaltyBalance).toBe(0)
  })

  it('balances never go below 0', () => {
    const ledger = [
      { entry_type: 'payment', amount: 999999, principal_applied: 999999, interest_applied: 0, penalty_applied: 0 },
    ]
    const out = computeOutstanding(1000, ledger)
    expect(out.principalBalance).toBe(0)
    expect(out.total).toBe(0)
  })
})

// ─── allocatePayment ─────────────────────────────────────────────────────────

describe('allocatePayment', () => {
  const outstanding = { principalBalance: 75000, interestBalance: 3160, penaltyBalance: 5000, total: 83160 }

  it('fills penalties first', () => {
    const alloc = allocatePayment(3000, outstanding)
    expect(alloc.penaltyApplied).toBe(3000)
    expect(alloc.interestApplied).toBe(0)
    expect(alloc.principalApplied).toBe(0)
  })

  it('fills interest after penalties are cleared', () => {
    const alloc = allocatePayment(8160, outstanding)
    expect(alloc.penaltyApplied).toBe(5000)
    expect(alloc.interestApplied).toBe(3160)
    expect(alloc.principalApplied).toBe(0)
  })

  it('remainder goes to principal after penalties and interest', () => {
    const alloc = allocatePayment(10000, outstanding)
    expect(alloc.penaltyApplied).toBe(5000)
    expect(alloc.interestApplied).toBe(3160)
    expect(alloc.principalApplied).toBe(1840)
  })

  it('caps principalApplied at principalBalance — no negative principal', () => {
    const small = { principalBalance: 100, interestBalance: 0, penaltyBalance: 0, total: 100 }
    const alloc = allocatePayment(99999, small)
    expect(alloc.principalApplied).toBe(100)
  })

  it('no-penalty no-interest: all goes to principal', () => {
    const noCharges = { principalBalance: 5000, interestBalance: 0, penaltyBalance: 0, total: 5000 }
    const alloc = allocatePayment(5000, noCharges)
    expect(alloc.principalApplied).toBe(5000)
    expect(alloc.penaltyApplied).toBe(0)
    expect(alloc.interestApplied).toBe(0)
  })
})

// ─── isPeriodSufficientlyPaid ─────────────────────────────────────────────────

describe('isPeriodSufficientlyPaid', () => {
  const ledger = [
    { entry_type: 'payment', amount: 2000, period_date: '2026-04-30' },
    { entry_type: 'payment', amount: 3000, period_date: '2026-04-30' },
    { entry_type: 'payment', amount: 7000, period_date: '2026-05-31' },
  ]

  it('minimumPayment null: any payment clears period', () => {
    expect(isPeriodSufficientlyPaid('2026-04-30', ledger, null)).toBe(true)
  })

  it('minimumPayment null: no payment → not paid', () => {
    expect(isPeriodSufficientlyPaid('2026-03-31', ledger, null)).toBe(false)
  })

  it('minimumPayment set: sums multiple payments in period', () => {
    // 2000 + 3000 = 5000 < 7000 → not paid
    expect(isPeriodSufficientlyPaid('2026-04-30', ledger, 7000)).toBe(false)
  })

  it('minimumPayment set: single full payment clears period', () => {
    expect(isPeriodSufficientlyPaid('2026-05-31', ledger, 7000)).toBe(true)
  })

  it('only counts payment entries, not other entry types', () => {
    const mixed = [
      { entry_type: 'interest_charge', amount: 9999, period_date: '2026-06-30' },
      { entry_type: 'payment', amount: 100, period_date: '2026-06-30' },
    ]
    expect(isPeriodSufficientlyPaid('2026-06-30', mixed, null)).toBe(true)
  })
})

// ─── generateMissingEntries ──────────────────────────────────────────────────

describe('generateMissingEntries', () => {
  const baseLoan = {
    id: 'loan-1',
    amount: 79000,
    loan_date: '2025-03-15',
    next_payment_date: '2025-04-30',
    payment_frequency: 'monthly',
    payment_day: 30,
    status: 'active',
    minimum_payment: 7000,
  }
  const rates = [
    {
      id: 'r1',
      effective_from: '2025-03-15',
      interest_rate: 4,
      interest_type: 'simple',
      late_fee_rate: 1,
      penalty_rate: 5,
    },
  ]

  it('returns [] for completed loan', () => {
    const loan = { ...baseLoan, status: 'completed' }
    expect(generateMissingEntries(loan, rates, [], '2026-04-25')).toHaveLength(0)
  })

  it('returns [] for defaulted loan', () => {
    const loan = { ...baseLoan, status: 'defaulted' }
    expect(generateMissingEntries(loan, rates, [], '2026-04-25')).toHaveLength(0)
  })

  it('returns [] when next_payment_date is null', () => {
    const loan = { ...baseLoan, next_payment_date: null }
    expect(generateMissingEntries(loan, rates, [], '2026-04-25')).toHaveLength(0)
  })

  it('returns [] when due date has not passed yet', () => {
    expect(generateMissingEntries(baseLoan, rates, [], '2025-04-29')).toHaveLength(0)
  })

  it('generates interest_charge for one missed period', () => {
    const entries = generateMissingEntries(baseLoan, rates, [], '2025-04-30')
    const charge = entries.find(e => e.entry_type === 'interest_charge')
    expect(charge).toBeDefined()
    expect(charge.amount).toBe(3160) // 79000 * 4%
    expect(charge.period_date).toBe('2025-04-30')
  })

  it('generates late_fee and penalty_interest for missed period (no payment)', () => {
    const entries = generateMissingEntries(baseLoan, rates, [], '2025-04-30')
    const types = entries.map(e => e.entry_type)
    expect(types).toContain('late_fee')
    expect(types).toContain('penalty_interest')
  })

  it('does NOT generate penalties when period is sufficiently paid', () => {
    const ledger = [
      { entry_type: 'payment', amount: 7000, period_date: '2025-04-30', principal_applied: 3840, interest_applied: 3160, penalty_applied: 0 },
    ]
    const entries = generateMissingEntries(baseLoan, rates, ledger, '2025-04-30')
    const types = entries.map(e => e.entry_type)
    expect(types).not.toContain('late_fee')
    expect(types).not.toContain('penalty_interest')
  })

  it('skips periods that already have interest_charge entries', () => {
    const ledger = [
      { entry_type: 'interest_charge', amount: 3160, period_date: '2025-04-30', principal_applied: 0, interest_applied: 0, penalty_applied: 0 },
    ]
    const entries = generateMissingEntries(baseLoan, rates, ledger, '2025-04-30')
    expect(entries.filter(e => e.entry_type === 'interest_charge')).toHaveLength(0)
  })

  it('generates entries for multiple missed periods in sequence', () => {
    const entries = generateMissingEntries(baseLoan, rates, [], '2025-06-30')
    const charges = entries.filter(e => e.entry_type === 'interest_charge')
    // April 30, May 31, June 30 = 3 periods
    expect(charges).toHaveLength(3)
    expect(charges[0].period_date).toBe('2025-04-30')
    expect(charges[1].period_date).toBe('2025-05-31')
    expect(charges[2].period_date).toBe('2025-06-30')
  })

  it('skips period when getActiveRate returns null (no applicable rate)', () => {
    const futureRates = [{ ...rates[0], effective_from: '2099-01-01' }]
    const entries = generateMissingEntries(baseLoan, futureRates, [], '2025-04-30')
    expect(entries).toHaveLength(0)
  })

  it('one-time loan: continues monthly cadence after due date if unpaid', () => {
    const oneTimeLoan = {
      ...baseLoan,
      payment_frequency: 'one-time',
      payment_day: null,
      next_payment_date: '2025-04-30',
    }
    const entries = generateMissingEntries(oneTimeLoan, rates, [], '2025-06-30')
    const charges = entries.filter(e => e.entry_type === 'interest_charge')
    expect(charges).toHaveLength(3)
    expect(charges[0].period_date).toBe('2025-04-30')
    expect(charges[1].period_date).toBe('2025-05-30')
    expect(charges[2].period_date).toBe('2025-06-30')
  })

  it('penalty amounts are computed on outstanding AFTER interest is added', () => {
    const entries = generateMissingEntries(baseLoan, rates, [], '2025-04-30')
    // outstanding before interest = 79000
    // interest_charge = 3160 → outstanding after = 82160
    // late_fee = 82160 * 1% = 821.60
    const lateFee = entries.find(e => e.entry_type === 'late_fee')
    expect(lateFee.amount).toBeCloseTo(821.6, 2)
  })
})

// ─── getNextPeriodDate ───────────────────────────────────────────────────────

describe('getNextPeriodDate', () => {
  it('monthly: advances to next month', () => {
    const loan = { payment_frequency: 'monthly', next_payment_date: '2026-04-30', payment_day: 30 }
    expect(getNextPeriodDate(loan)).toBe('2026-05-31')
  })

  it('weekly: advances by 7 days', () => {
    const loan = { payment_frequency: 'weekly', next_payment_date: '2026-04-25', payment_day: null }
    expect(getNextPeriodDate(loan)).toBe('2026-05-02')
  })

  it('one-time: advances monthly from due date', () => {
    const loan = { payment_frequency: 'one-time', next_payment_date: '2026-04-30', payment_day: null }
    expect(getNextPeriodDate(loan)).toBe('2026-05-30')
  })
})
```

- [ ] **Step 2: Run tests to confirm they all fail**

```bash
npm test -- loanInterest
```

Expected: all tests FAIL with "Cannot find module './loanInterest.js'"

- [ ] **Step 3: Create `src/utils/loanInterest.js`**

```javascript
import { toCents, fromCents } from './money.js'
import { advanceNextPaymentDate } from './loans.js'

export function getActiveRate(rateHistory, date) {
  return (
    [...rateHistory]
      .filter(r => r.effective_from <= date)
      .sort((a, b) => b.effective_from.localeCompare(a.effective_from))[0] ?? null
  )
}

export function computeInterestCharge(loanAmount, principalBalance, interestRate, interestType) {
  const baseCents = interestType === 'simple' ? toCents(loanAmount) : toCents(principalBalance)
  return fromCents(Math.round(baseCents * Number(interestRate) / 100))
}

export function computeOutstanding(loanAmount, ledgerEntries) {
  let principalPaidCents = 0
  let interestChargedCents = 0
  let interestPaidCents = 0
  let penaltyChargedCents = 0
  let penaltyPaidCents = 0
  let penaltyWaivedCents = 0

  for (const e of ledgerEntries) {
    switch (e.entry_type) {
      case 'interest_charge':
        interestChargedCents += toCents(e.amount)
        break
      case 'late_fee':
      case 'penalty_interest':
        penaltyChargedCents += toCents(e.amount)
        break
      case 'payment':
        principalPaidCents += toCents(e.principal_applied)
        interestPaidCents  += toCents(e.interest_applied)
        penaltyPaidCents   += toCents(e.penalty_applied)
        break
      case 'penalty_waiver':
        penaltyWaivedCents += toCents(e.amount)
        break
    }
  }

  const principalBalance = Math.max(0, fromCents(toCents(loanAmount) - principalPaidCents))
  const interestBalance  = Math.max(0, fromCents(interestChargedCents - interestPaidCents))
  const penaltyBalance   = Math.max(0, fromCents(penaltyChargedCents - penaltyPaidCents - penaltyWaivedCents))
  const total            = fromCents(toCents(principalBalance) + toCents(interestBalance) + toCents(penaltyBalance))

  return { principalBalance, interestBalance, penaltyBalance, total }
}

export function allocatePayment(paymentAmount, outstanding) {
  let remainderCents = toCents(paymentAmount)

  const penaltyAppliedCents  = Math.min(remainderCents, toCents(outstanding.penaltyBalance))
  remainderCents -= penaltyAppliedCents

  const interestAppliedCents = Math.min(remainderCents, toCents(outstanding.interestBalance))
  remainderCents -= interestAppliedCents

  const principalAppliedCents = Math.min(remainderCents, toCents(outstanding.principalBalance))

  return {
    penaltyApplied:  fromCents(penaltyAppliedCents),
    interestApplied: fromCents(interestAppliedCents),
    principalApplied: fromCents(principalAppliedCents),
  }
}

export function isPeriodSufficientlyPaid(periodDate, ledgerEntries, minimumPayment) {
  const totalPaidCents = ledgerEntries
    .filter(e => e.entry_type === 'payment' && e.period_date === periodDate)
    .reduce((sum, e) => sum + toCents(e.amount), 0)

  if (minimumPayment == null) return totalPaidCents > 0
  return totalPaidCents >= toCents(minimumPayment)
}

export function getNextPeriodDate(loan) {
  if (loan.payment_frequency === 'one-time') {
    return advanceNextPaymentDate({
      payment_frequency: 'monthly',
      next_payment_date: loan.next_payment_date,
      payment_day: Number(loan.next_payment_date.split('-')[2]),
    })
  }
  return advanceNextPaymentDate(loan)
}

export function generateMissingEntries(loan, rateHistory, ledgerEntries, today) {
  if (loan.status === 'completed' || loan.status === 'defaulted') return []
  if (!loan.next_payment_date) return []

  const chargedPeriods = new Set(
    ledgerEntries.filter(e => e.entry_type === 'interest_charge').map(e => e.period_date)
  )

  const result = []
  const workingLedger = [...ledgerEntries]
  let currentDueDate = loan.next_payment_date
  const isOneTime = loan.payment_frequency === 'one-time'
  const oneTimeDayOfMonth = isOneTime ? Number(loan.next_payment_date.split('-')[2]) : null

  while (currentDueDate <= today) {
    if (!chargedPeriods.has(currentDueDate)) {
      const rate = getActiveRate(rateHistory, currentDueDate)
      if (rate !== null) {
        const outstanding = computeOutstanding(loan.amount, workingLedger)

        const interestAmount = computeInterestCharge(
          loan.amount,
          outstanding.principalBalance,
          rate.interest_rate,
          rate.interest_type
        )

        const interestEntry = {
          loan_id: loan.id,
          entry_type: 'interest_charge',
          amount: interestAmount,
          principal_applied: 0,
          interest_applied: 0,
          penalty_applied: 0,
          period_date: currentDueDate,
          is_manual: false,
          notes: null,
        }
        result.push(interestEntry)
        workingLedger.push(interestEntry)

        const paid = isPeriodSufficientlyPaid(currentDueDate, workingLedger, loan.minimum_payment)
        if (!paid) {
          const outstandingAfter = computeOutstanding(loan.amount, workingLedger)
          const totalCents = toCents(outstandingAfter.total)

          const lateFeeEntry = {
            loan_id: loan.id,
            entry_type: 'late_fee',
            amount: fromCents(Math.round(totalCents * Number(rate.late_fee_rate) / 100)),
            principal_applied: 0,
            interest_applied: 0,
            penalty_applied: 0,
            period_date: currentDueDate,
            is_manual: false,
            notes: null,
          }
          const penaltyEntry = {
            loan_id: loan.id,
            entry_type: 'penalty_interest',
            amount: fromCents(Math.round(totalCents * Number(rate.penalty_rate) / 100)),
            principal_applied: 0,
            interest_applied: 0,
            penalty_applied: 0,
            period_date: currentDueDate,
            is_manual: false,
            notes: null,
          }
          result.push(lateFeeEntry, penaltyEntry)
          workingLedger.push(lateFeeEntry, penaltyEntry)
        }
      }
    }

    // Advance to next period
    const next = isOneTime
      ? advanceNextPaymentDate({ payment_frequency: 'monthly', next_payment_date: currentDueDate, payment_day: oneTimeDayOfMonth })
      : advanceNextPaymentDate({ payment_frequency: loan.payment_frequency, next_payment_date: currentDueDate, payment_day: loan.payment_day })

    if (!next || next === currentDueDate) break
    currentDueDate = next
  }

  return result
}
```

- [ ] **Step 4: Run tests — all should pass**

```bash
npm test -- loanInterest
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/utils/loanInterest.js src/utils/loanInterest.test.js
git commit -m "feat: add loanInterest computation engine with full test coverage"
```

---

## Task 3: Zod Schema Updates

**Files:**
- Modify: `src/lib/zod-schemas.js`

- [ ] **Step 1: Update `loanSchema` and add `loanInterestRateSchema`**

In `src/lib/zod-schemas.js`, replace the existing `loanSchema` and append the new schema:

```javascript
export const loanSchema = z
  .object({
    amount: z.coerce
      .number({ invalid_type_error: 'Must be a number' })
      .positive('Amount must be greater than 0'),
    loan_date: z.string().min(1, 'Loan date is required'),
    description: z.string().optional(),
    payment_frequency: z.enum(['one-time', 'weekly', 'monthly']),
    payment_day: z.coerce.number().optional().nullable(),
    next_payment_date: z.string().optional().nullable(),
    notarized: z.boolean().default(false),
    lawyer_name: z.string().optional().nullable(),
    ptr_number: z.string().optional().nullable(),
    date_notarized: z.string().optional().nullable(),
    // Interest fields
    interest_bearing: z.boolean().default(false),
    minimum_payment: z.coerce.number().positive().optional().nullable(),
    interest_rate: z.coerce.number().positive().optional().nullable(),
    interest_type: z.enum(['simple', 'diminishing']).optional().nullable(),
    late_fee_rate: z.coerce.number().min(0).optional().nullable(),
    penalty_rate: z.coerce.number().min(0).optional().nullable(),
  })
  .refine(
    (d) => {
      if (d.payment_frequency === 'monthly') {
        return d.payment_day === 15 || d.payment_day === 30
      }
      return true
    },
    { message: 'Payment day must be 15 or 30 for monthly frequency', path: ['payment_day'] }
  )
  .refine(
    (d) => {
      if (d.notarized) {
        return !!d.lawyer_name && !!d.ptr_number && !!d.date_notarized
      }
      return true
    },
    { message: 'Lawyer name, PTR number, and date notarized are required when notarized', path: ['lawyer_name'] }
  )
  .refine(
    (d) => {
      if (d.interest_bearing) {
        return !!d.interest_rate && !!d.interest_type
      }
      return true
    },
    { message: 'Interest rate and type are required when interest is enabled', path: ['interest_rate'] }
  )

export const loanInterestRateSchema = z.object({
  interest_rate: z.coerce
    .number({ invalid_type_error: 'Must be a number' })
    .positive('Interest rate must be greater than 0'),
  interest_type: z.enum(['simple', 'diminishing'], { required_error: 'Interest type is required' }),
  late_fee_rate: z.coerce.number().min(0, 'Must be 0 or greater'),
  penalty_rate: z.coerce.number().min(0, 'Must be 0 or greater'),
  effective_from: z.string().min(1, 'Effective date is required'),
})
```

- [ ] **Step 2: Run existing tests to confirm nothing broke**

```bash
npm test
```

Expected: all existing tests still PASS.

- [ ] **Step 3: Commit**

```bash
git add src/lib/zod-schemas.js
git commit -m "feat: add interest fields to loanSchema, add loanInterestRateSchema"
```

---

## Task 4: Hook Updates

**Files:**
- Modify: `src/hooks/useLoans.js`

Replace the entire file with the updated version below. The non-interest paths are byte-for-byte identical to the original — only the interest-bearing paths are new.

- [ ] **Step 1: Replace `src/hooks/useLoans.js`**

```javascript
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase.js'
import { getLoanTotalPaid, getLoanRemaining, advanceNextPaymentDate } from '../utils/loans.js'
import { addMoney, toCents, fromCents } from '../utils/money.js'
import {
  computeOutstanding,
  allocatePayment,
  generateMissingEntries,
  getNextPeriodDate,
} from '../utils/loanInterest.js'

export function useLoans(borrowerId) {
  return useQuery({
    queryKey: ['loans', borrowerId],
    enabled: !!borrowerId,
    queryFn: async () => {
      const today = new Date().toISOString().slice(0, 10)

      const { data: loans, error } = await supabase
        .from('loans')
        .select('*, loan_payments(id, amount, notes, paid_at)')
        .eq('borrower_id', borrowerId)
        .eq('is_archived', false)
        .order('created_at', { ascending: false })
      if (error) throw error

      const {
        data: { user },
      } = await supabase.auth.getUser()

      for (const loan of loans) {
        if (!loan.interest_bearing) continue

        const [{ data: ledger, error: ledgerErr }, { data: rates, error: ratesErr }] =
          await Promise.all([
            supabase
              .from('loan_ledger')
              .select('*')
              .eq('loan_id', loan.id)
              .order('period_date', { ascending: true })
              .order('created_at', { ascending: true }),
            supabase
              .from('loan_interest_rates')
              .select('*')
              .eq('loan_id', loan.id)
              .order('effective_from', { ascending: true }),
          ])
        if (ledgerErr) throw ledgerErr
        if (ratesErr) throw ratesErr

        const missing = generateMissingEntries(loan, rates, ledger, today)
        if (missing.length > 0) {
          const { error: insertErr } = await supabase
            .from('loan_ledger')
            .insert(missing.map((e) => ({ ...e, user_id: user.id })))
          if (insertErr) throw insertErr

          const { data: updatedLedger, error: refetchErr } = await supabase
            .from('loan_ledger')
            .select('*')
            .eq('loan_id', loan.id)
            .order('period_date', { ascending: true })
            .order('created_at', { ascending: true })
          if (refetchErr) throw refetchErr

          loan._ledger = updatedLedger
        } else {
          loan._ledger = ledger
        }
        loan._rates = rates
      }

      return loans
    },
  })
}

export function useAddLoan() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ borrowerId, loanData }) => {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      const {
        interest_bearing,
        minimum_payment,
        interest_rate,
        interest_type,
        late_fee_rate,
        penalty_rate,
        ...rest
      } = loanData

      const { data, error } = await supabase
        .from('loans')
        .insert({
          ...rest,
          interest_bearing: interest_bearing ?? false,
          minimum_payment: interest_bearing ? (minimum_payment ?? null) : null,
          borrower_id: borrowerId,
          user_id: user.id,
          status: 'active',
        })
        .select()
        .single()
      if (error) throw error

      // If interest-bearing, insert the initial rate row
      if (interest_bearing && interest_rate && interest_type) {
        const { error: rateErr } = await supabase.from('loan_interest_rates').insert({
          loan_id: data.id,
          user_id: user.id,
          interest_rate,
          interest_type,
          rate_period: 'monthly',
          late_fee_rate: late_fee_rate ?? 1.0,
          penalty_rate: penalty_rate ?? 5.0,
          effective_from: rest.loan_date,
        })
        if (rateErr) throw rateErr
      }

      return data
    },
    onSuccess: (_data, { borrowerId }) =>
      qc.invalidateQueries({ queryKey: ['loans', borrowerId] }),
  })
}

export function useRecordLoanPayment() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ loan, paymentAmount, notes }) => {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      // ── Non-interest path (unchanged) ──────────────────────────────────────
      if (!loan.interest_bearing) {
        const { data: payData, error: payErr } = await supabase
          .from('loan_payments')
          .insert({ loan_id: loan.id, user_id: user.id, amount: paymentAmount, notes })
          .select()
          .single()
        if (payErr) throw payErr

        const previousPaid = getLoanTotalPaid(loan.loan_payments)
        const newTotalPaid = addMoney(previousPaid, paymentAmount)
        const newRemaining = getLoanRemaining(loan.amount, newTotalPaid)

        const updates = {}
        if (newRemaining <= 0) {
          updates.status = 'completed'
          updates.next_payment_date = null
        } else {
          updates.next_payment_date = advanceNextPaymentDate(loan)
        }
        const { error: loanErr } = await supabase.from('loans').update(updates).eq('id', loan.id)
        if (loanErr) throw loanErr

        return { borrowerId: loan.borrower_id, loanPaymentId: payData.id }
      }

      // ── Interest-bearing path ──────────────────────────────────────────────
      const ledger = loan._ledger ?? []
      const outstanding = computeOutstanding(loan.amount, ledger)
      const allocation = allocatePayment(paymentAmount, outstanding)

      const periodDate = loan.next_payment_date ?? loan.loan_date

      const { data: payData, error: payErr } = await supabase
        .from('loan_ledger')
        .insert({
          loan_id: loan.id,
          user_id: user.id,
          entry_type: 'payment',
          amount: paymentAmount,
          principal_applied: allocation.principalApplied,
          interest_applied: allocation.interestApplied,
          penalty_applied: allocation.penaltyApplied,
          period_date: periodDate,
          is_manual: false,
          notes: notes ?? null,
        })
        .select()
        .single()
      if (payErr) throw payErr

      const newTotalCents = Math.max(0, toCents(outstanding.total) - toCents(paymentAmount))
      const updates = {}
      if (newTotalCents <= 0) {
        updates.status = 'completed'
        updates.next_payment_date = null
      } else {
        const nextDate = getNextPeriodDate(loan)
        if (nextDate && nextDate !== loan.next_payment_date) {
          updates.next_payment_date = nextDate
        }
      }

      if (Object.keys(updates).length > 0) {
        const { error: loanErr } = await supabase.from('loans').update(updates).eq('id', loan.id)
        if (loanErr) throw loanErr
      }

      return { borrowerId: loan.borrower_id, loanPaymentId: payData.id }
    },
    onSuccess: (_data, { loan }) =>
      qc.invalidateQueries({ queryKey: ['loans', loan.borrower_id] }),
  })
}

export function useAddLoanInterestRate() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ loan, rateData }) => {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      // Validate effective_from >= last ledger period_date
      const lastLedgerDate = (loan._ledger ?? [])
        .map((e) => e.period_date)
        .sort()
        .at(-1)

      if (lastLedgerDate && rateData.effective_from < lastLedgerDate) {
        throw new Error(
          `Effective date must be on or after the last computed period (${lastLedgerDate})`
        )
      }

      const { error } = await supabase.from('loan_interest_rates').insert({
        loan_id: loan.id,
        user_id: user.id,
        interest_rate: rateData.interest_rate,
        interest_type: rateData.interest_type,
        rate_period: 'monthly',
        late_fee_rate: rateData.late_fee_rate,
        penalty_rate: rateData.penalty_rate,
        effective_from: rateData.effective_from,
      })
      if (error) throw error
    },
    onSuccess: (_data, { loan }) =>
      qc.invalidateQueries({ queryKey: ['loans', loan.borrower_id] }),
  })
}

export function useLoanLedger(loanId) {
  return useQuery({
    queryKey: ['loan_ledger', loanId],
    enabled: !!loanId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('loan_ledger')
        .select('*')
        .eq('loan_id', loanId)
        .order('period_date', { ascending: true })
        .order('created_at', { ascending: true })
      if (error) throw error
      return data
    },
  })
}

export function useWaivePenalty() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ loan, amount, notes }) => {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      const lastLedgerDate = (loan._ledger ?? [])
        .map((e) => e.period_date)
        .sort()
        .at(-1) ?? loan.loan_date

      const { error } = await supabase.from('loan_ledger').insert({
        loan_id: loan.id,
        user_id: user.id,
        entry_type: 'penalty_waiver',
        amount,
        principal_applied: 0,
        interest_applied: 0,
        penalty_applied: 0,
        period_date: lastLedgerDate,
        is_manual: true,
        notes: notes ?? null,
      })
      if (error) throw error
    },
    onSuccess: (_data, { loan }) => {
      qc.invalidateQueries({ queryKey: ['loans', loan.borrower_id] })
      qc.invalidateQueries({ queryKey: ['loan_ledger', loan.id] })
    },
  })
}
```

- [ ] **Step 2: Run existing tests**

```bash
npm test
```

Expected: all existing tests PASS (hook changes have no pure-function tests to break).

- [ ] **Step 3: Commit**

```bash
git add src/hooks/useLoans.js
git commit -m "feat: extend useLoans for interest-bearing loans, add useAddLoanInterestRate, useLoanLedger, useWaivePenalty"
```

---

## Task 5: LoanForm — Interest Section

**Files:**
- Modify: `src/components/borrowers/LoanForm.jsx`

- [ ] **Step 1: Replace `src/components/borrowers/LoanForm.jsx`**

```jsx
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { loanSchema } from '../../lib/zod-schemas.js'
import { useAddLoan } from '../../hooks/useLoans.js'
import Modal from '../ui/Modal.jsx'
import Button from '../ui/Button.jsx'

const today = new Date().toISOString().slice(0, 10)

const INPUT_CLS =
  'w-full border border-gray-300 dark:border-gray-700 rounded-xl px-4 py-2.5 text-sm bg-white dark:bg-gray-800 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-[#9FE870] focus:border-transparent'

export default function LoanForm({ borrowerId, onClose, onSuccess }) {
  const addLoan = useAddLoan()
  const {
    register,
    handleSubmit,
    watch,
    formState: { errors },
  } = useForm({
    resolver: zodResolver(loanSchema),
    defaultValues: {
      amount: '',
      loan_date: today,
      description: '',
      payment_frequency: 'one-time',
      payment_day: null,
      next_payment_date: '',
      notarized: false,
      lawyer_name: '',
      ptr_number: '',
      date_notarized: '',
      interest_bearing: false,
      minimum_payment: '',
      interest_rate: '',
      interest_type: 'simple',
      late_fee_rate: '1',
      penalty_rate: '5',
    },
  })

  const frequency = watch('payment_frequency')
  const notarized = watch('notarized')
  const interestBearing = watch('interest_bearing')

  async function onSubmit(values) {
    try {
      const loanData = {
        ...values,
        payment_day: frequency === 'monthly' ? values.payment_day : null,
        next_payment_date: values.next_payment_date || null,
        lawyer_name: values.notarized ? values.lawyer_name : null,
        ptr_number: values.notarized ? values.ptr_number : null,
        date_notarized: values.notarized ? values.date_notarized : null,
        minimum_payment: values.interest_bearing && values.minimum_payment ? Number(values.minimum_payment) : null,
        interest_rate: values.interest_bearing ? Number(values.interest_rate) : null,
        interest_type: values.interest_bearing ? values.interest_type : null,
        late_fee_rate: values.interest_bearing ? Number(values.late_fee_rate) : null,
        penalty_rate: values.interest_bearing ? Number(values.penalty_rate) : null,
      }
      await addLoan.mutateAsync({ borrowerId, loanData })
      onSuccess?.()
      onClose()
    } catch (err) {
      console.error(err)
    }
  }

  return (
    <Modal title="Add Loan" onClose={onClose}>
      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
        {/* Amount */}
        <div>
          <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">
            Loan Amount (PHP)
          </label>
          <input {...register('amount')} type="number" step="0.01" placeholder="5000.00" className={INPUT_CLS} />
          {errors.amount && <p className="text-red-500 text-xs mt-1">{errors.amount.message}</p>}
        </div>

        {/* Loan Date */}
        <div>
          <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">
            Loan Date
          </label>
          <input {...register('loan_date')} type="date" max={today} className={INPUT_CLS} />
          {errors.loan_date && <p className="text-red-500 text-xs mt-1">{errors.loan_date.message}</p>}
        </div>

        {/* Description */}
        <div>
          <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">
            Description (optional)
          </label>
          <input {...register('description')} placeholder="e.g. Cash loan, iPhone 15" className={INPUT_CLS} />
        </div>

        {/* Payment Frequency */}
        <div>
          <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">
            Payment Frequency
          </label>
          <select {...register('payment_frequency')} className={INPUT_CLS}>
            <option value="one-time">One-time</option>
            <option value="weekly">Weekly</option>
            <option value="monthly">Monthly</option>
          </select>
        </div>

        {/* Payment Day (monthly only) */}
        {frequency === 'monthly' && (
          <div>
            <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">
              Payment Day
            </label>
            <select {...register('payment_day')} className={INPUT_CLS}>
              <option value="">Select day</option>
              <option value={15}>15th</option>
              <option value={30}>30th</option>
            </select>
            {errors.payment_day && <p className="text-red-500 text-xs mt-1">{errors.payment_day.message}</p>}
          </div>
        )}

        {/* First Payment Date */}
        {frequency !== 'one-time' && (
          <div>
            <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">
              First Payment Date
            </label>
            <input {...register('next_payment_date')} type="date" className={INPUT_CLS} />
          </div>
        )}

        {/* Notarized */}
        <div className="flex items-center gap-2">
          <input {...register('notarized')} type="checkbox" id="notarized" className="h-4 w-4 rounded border-gray-300 accent-[#9FE870]" />
          <label htmlFor="notarized" className="text-sm text-gray-700 dark:text-gray-200">
            This loan is notarized
          </label>
        </div>

        {notarized && (
          <div className="space-y-3 border border-gray-200 dark:border-gray-700 rounded-lg p-3">
            {[
              { name: 'lawyer_name', label: 'Lawyer Name', placeholder: 'Atty. Juan dela Cruz' },
              { name: 'ptr_number', label: 'PTR Number', placeholder: 'PTR-12345' },
            ].map(({ name, label, placeholder }) => (
              <div key={name}>
                <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">{label}</label>
                <input {...register(name)} placeholder={placeholder} className={INPUT_CLS} />
                {errors[name] && <p className="text-red-500 text-xs mt-1">{errors[name].message}</p>}
              </div>
            ))}
            <div>
              <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">Date Notarized</label>
              <input {...register('date_notarized')} type="date" className={INPUT_CLS} />
            </div>
          </div>
        )}

        {/* Interest toggle */}
        <div className="flex items-center gap-2">
          <input {...register('interest_bearing')} type="checkbox" id="interest_bearing" className="h-4 w-4 rounded border-gray-300 accent-[#9FE870]" />
          <label htmlFor="interest_bearing" className="text-sm text-gray-700 dark:text-gray-200">
            This loan earns interest
          </label>
        </div>

        {/* Interest fields */}
        {interestBearing && (
          <div className="space-y-3 border border-[#9FE870]/30 dark:border-[#9FE870]/20 rounded-lg p-3 bg-[#9FE870]/5">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">
                  Interest Rate (%/month)
                </label>
                <input {...register('interest_rate')} type="number" step="0.01" placeholder="4.00" className={INPUT_CLS} />
                {errors.interest_rate && <p className="text-red-500 text-xs mt-1">{errors.interest_rate.message}</p>}
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">
                  Interest Type
                </label>
                <select {...register('interest_type')} className={INPUT_CLS}>
                  <option value="simple">Simple</option>
                  <option value="diminishing">Diminishing Balance</option>
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">
                  Late Fee Rate (%)
                </label>
                <input {...register('late_fee_rate')} type="number" step="0.01" placeholder="1.00" className={INPUT_CLS} />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">
                  Penalty Rate (%/month)
                </label>
                <input {...register('penalty_rate')} type="number" step="0.01" placeholder="5.00" className={INPUT_CLS} />
              </div>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">
                Minimum Monthly Payment (PHP) — optional
              </label>
              <input {...register('minimum_payment')} type="number" step="0.01" placeholder="7000.00 — leave blank if any amount clears the period" className={INPUT_CLS} />
              <p className="text-gray-400 text-xs mt-1">
                If set, partial payments below this amount still trigger late fees.
              </p>
            </div>
          </div>
        )}

        {addLoan.error && <p className="text-red-500 text-sm">{addLoan.error.message}</p>}

        <div className="flex gap-2 pt-2">
          <Button type="button" variant="ghost" onClick={onClose} className="flex-1">Cancel</Button>
          <Button type="submit" disabled={addLoan.isPending} className="flex-1">
            {addLoan.isPending ? 'Saving…' : 'Add Loan'}
          </Button>
        </div>
      </form>
    </Modal>
  )
}
```

- [ ] **Step 2: Test in browser**

Start dev server (`npm run dev:client`), open a borrower's loan page, click "+ Add Loan". Verify:
- "This loan earns interest" checkbox appears
- Checking it reveals the 5 interest fields
- Unchecking hides them
- Submitting without interest fields works (existing behavior)
- Submitting with interest fields saves the loan and creates a rate entry in Supabase

- [ ] **Step 3: Commit**

```bash
git add src/components/borrowers/LoanForm.jsx
git commit -m "feat: add interest section to LoanForm"
```

---

## Task 6: EditRateModal

**Files:**
- Create: `src/components/borrowers/EditRateModal.jsx`

- [ ] **Step 1: Create `src/components/borrowers/EditRateModal.jsx`**

```jsx
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { loanInterestRateSchema } from '../../lib/zod-schemas.js'
import { useAddLoanInterestRate } from '../../hooks/useLoans.js'
import Modal from '../ui/Modal.jsx'
import Button from '../ui/Button.jsx'
import { formatPeso } from '../../utils/money.js'

const today = new Date().toISOString().slice(0, 10)

const INPUT_CLS =
  'w-full border border-gray-300 dark:border-gray-700 rounded-xl px-4 py-2.5 text-sm bg-white dark:bg-gray-800 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-[#9FE870] focus:border-transparent'

const ENTRY_TYPE_LABELS = {
  simple: 'Simple',
  diminishing: 'Diminishing Balance',
}

export default function EditRateModal({ loan, onClose, onSuccess }) {
  const addRate = useAddLoanInterestRate()
  const rates = [...(loan._rates ?? [])].sort((a, b) =>
    b.effective_from.localeCompare(a.effective_from)
  )
  const currentRate = rates[0]

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm({
    resolver: zodResolver(loanInterestRateSchema),
    defaultValues: {
      interest_rate: currentRate?.interest_rate ?? '',
      interest_type: currentRate?.interest_type ?? 'simple',
      late_fee_rate: currentRate?.late_fee_rate ?? 1,
      penalty_rate: currentRate?.penalty_rate ?? 5,
      effective_from: today,
    },
  })

  async function onSubmit(values) {
    try {
      await addRate.mutateAsync({ loan, rateData: values })
      onSuccess?.()
      onClose()
    } catch (err) {
      console.error(err)
    }
  }

  const lastLedgerDate = (loan._ledger ?? []).map((e) => e.period_date).sort().at(-1)

  return (
    <Modal title="Edit Interest Rate" onClose={onClose}>
      {/* Rate history */}
      {rates.length > 0 && (
        <div className="mb-5">
          <p className="text-xs text-gray-400 uppercase tracking-wide mb-2">Rate History</p>
          <div className="divide-y divide-gray-100 dark:divide-gray-700 border border-gray-200 dark:border-gray-700 rounded-lg overflow-hidden text-sm">
            {rates.map((r, i) => (
              <div key={r.id} className="flex justify-between items-center px-3 py-2 bg-white dark:bg-gray-900">
                <span className={`font-mono text-xs ${i === 0 ? 'text-[#9FE870]' : 'text-gray-400'}`}>
                  {r.effective_from}{i === 0 ? ' ← current' : ''}
                </span>
                <span className="font-mono text-gray-900 dark:text-white">{r.interest_rate}%/mo · {ENTRY_TYPE_LABELS[r.interest_type]}</span>
                <span className="text-gray-400 text-xs">Late {r.late_fee_rate}% · Penalty {r.penalty_rate}%</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {lastLedgerDate && (
        <p className="text-xs text-amber-600 dark:text-amber-400 mb-4">
          Effective date must be on or after <strong>{lastLedgerDate}</strong> (last computed period).
        </p>
      )}

      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">
              New Rate (%/month)
            </label>
            <input {...register('interest_rate')} type="number" step="0.01" className={INPUT_CLS} />
            {errors.interest_rate && <p className="text-red-500 text-xs mt-1">{errors.interest_rate.message}</p>}
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">
              Interest Type
            </label>
            <select {...register('interest_type')} className={INPUT_CLS}>
              <option value="simple">Simple</option>
              <option value="diminishing">Diminishing Balance</option>
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">
              Late Fee Rate (%)
            </label>
            <input {...register('late_fee_rate')} type="number" step="0.01" className={INPUT_CLS} />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">
              Penalty Rate (%/month)
            </label>
            <input {...register('penalty_rate')} type="number" step="0.01" className={INPUT_CLS} />
          </div>
        </div>

        <div>
          <label className="block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5">
            Effective From
          </label>
          <input
            {...register('effective_from')}
            type="date"
            min={lastLedgerDate ?? undefined}
            className={INPUT_CLS}
          />
          {errors.effective_from && <p className="text-red-500 text-xs mt-1">{errors.effective_from.message}</p>}
          <p className="text-gray-400 text-xs mt-1">
            All charges from this date onward use the new rate. Past entries are unchanged.
          </p>
        </div>

        {addRate.error && <p className="text-red-500 text-sm">{addRate.error.message}</p>}

        <div className="flex gap-2 pt-2">
          <Button type="button" variant="ghost" onClick={onClose} className="flex-1">Cancel</Button>
          <Button type="submit" disabled={addRate.isPending} className="flex-1">
            {addRate.isPending ? 'Saving…' : 'Save New Rate'}
          </Button>
        </div>
      </form>
    </Modal>
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add src/components/borrowers/EditRateModal.jsx
git commit -m "feat: add EditRateModal for mid-loan rate changes"
```

---

## Task 7: LoanPaymentModal — Balance Breakdown + Allocation Preview

**Files:**
- Modify: `src/components/borrowers/LoanPaymentModal.jsx`

Add the balance breakdown panel and live allocation preview for interest-bearing loans. The non-interest path is unchanged.

- [ ] **Step 1: Replace `src/components/borrowers/LoanPaymentModal.jsx`**

```jsx
import { useRef, useState, useMemo } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { loanPaymentSchema } from '../../lib/zod-schemas.js'
import { useRecordLoanPayment } from '../../hooks/useLoans.js'
import {
  useUploadAttachment,
  useLoanPaymentAttachmentCounts,
  ALLOWED_TYPES,
  MAX_SIZE,
  MAX_FILES,
} from '../../hooks/useAttachments.js'
import { getLoanTotalPaid, getLoanRemaining } from '../../utils/loans.js'
import { computeOutstanding, allocatePayment } from '../../utils/loanInterest.js'
import { formatPeso } from '../../utils/money.js'
import Modal from '../ui/Modal.jsx'
import Button from '../ui/Button.jsx'
import AttachmentModal from '../ui/AttachmentModal.jsx'

export default function LoanPaymentModal({ loan, onClose, onSuccess }) {
  const recordPayment = useRecordLoanPayment()
  const fileInputRef = useRef(null)
  const [stagedFiles, setStagedFiles] = useState([])
  const [fileError, setFileError] = useState('')
  const [uploadWarning, setUploadWarning] = useState('')
  const [attachmentModalPaymentId, setAttachmentModalPaymentId] = useState(null)
  const uploadAttachment = useUploadAttachment()
  const loanPaymentIds = loan.loan_payments.map((p) => p.id)
  const { data: attachmentCounts } = useLoanPaymentAttachmentCounts(loanPaymentIds)

  // ── Interest-bearing outstanding ──────────────────────────────────────────
  const outstanding = useMemo(
    () => (loan.interest_bearing ? computeOutstanding(loan.amount, loan._ledger ?? []) : null),
    [loan]
  )

  // Non-interest remaining (existing path)
  const nonInterestRemaining = loan.interest_bearing
    ? null
    : getLoanRemaining(loan.amount, getLoanTotalPaid(loan.loan_payments))

  const maxPayment = loan.interest_bearing ? outstanding.total : nonInterestRemaining

  const {
    register,
    handleSubmit,
    watch,
    formState: { errors },
  } = useForm({
    resolver: zodResolver(loanPaymentSchema),
    defaultValues: { amount: '', notes: '' },
  })

  const amountValue = watch('amount')

  const allocation = useMemo(() => {
    if (!loan.interest_bearing || !outstanding) return null
    const amt = Number(amountValue) || 0
    if (amt <= 0) return null
    return allocatePayment(Math.min(amt, outstanding.total), outstanding)
  }, [amountValue, outstanding, loan.interest_bearing])

  function handleFileSelect(e) {
    setFileError('')
    const files = Array.from(e.target.files || [])
    const slots = MAX_FILES - stagedFiles.length
    if (files.length > slots) { setFileError(`Maximum ${MAX_FILES} files allowed.`); e.target.value = ''; return }
    const invalid = files.filter((f) => !ALLOWED_TYPES.includes(f.type) || f.size > MAX_SIZE)
    if (invalid.length > 0) { setFileError('Only JPG, PNG, WEBP, PDF under 10 MB allowed.'); e.target.value = ''; return }
    setStagedFiles((prev) => [...prev, ...files])
    e.target.value = ''
  }

  function removeStagedFile(index) {
    setStagedFiles((prev) => prev.filter((_, i) => i !== index))
  }

  async function onSubmit(values) {
    const amt = Number(values.amount)
    if (amt > maxPayment) return
    let result
    try {
      result = await recordPayment.mutateAsync({ loan, paymentAmount: amt, notes: values.notes || null })
    } catch (err) { console.error(err); return }

    if (stagedFiles.length > 0) {
      const failed = []
      for (const file of stagedFiles) {
        try {
          await uploadAttachment.mutateAsync({ file, entityType: 'loan_payment', entityId: result.loanPaymentId })
        } catch { failed.push(file.name) }
      }
      if (failed.length > 0) {
        setUploadWarning(`Payment saved. Receipt upload failed for: ${failed.join(', ')}. You can retry from payment history.`)
        return
      }
    }
    onSuccess?.()
    onClose()
  }

  return (
    <Modal title="Record Payment" onClose={onClose}>
      <p className="text-gray-400 text-sm mb-4">
        {loan.description || 'Loan'} · {loan.interest_bearing ? `Total owed: ${formatPeso(outstanding.total)}` : `Remaining: ${formatPeso(nonInterestRemaining)}`}
      </p>

      {/* Interest breakdown panel */}
      {loan.interest_bearing && outstanding && (
        <div className="mb-5 border border-gray-200 dark:border-gray-700 rounded-lg overflow-hidden text-sm">
          <p className="text-xs text-gray-400 uppercase tracking-wide px-3 py-2 bg-gray-50 dark:bg-gray-800">
            Balance Breakdown
          </p>
          <div className="divide-y divide-gray-100 dark:divide-gray-700">
            <div className="flex justify-between px-3 py-2">
              <span className="text-gray-600 dark:text-gray-300">Principal</span>
              <span className="font-mono text-gray-900 dark:text-white">{formatPeso(outstanding.principalBalance)}</span>
            </div>
            <div className="flex justify-between px-3 py-2">
              <span className="text-[#2D6A4F] dark:text-[#9FE870]">Interest Due</span>
              <span className="font-mono text-[#2D6A4F] dark:text-[#9FE870]">{formatPeso(outstanding.interestBalance)}</span>
            </div>
            {outstanding.penaltyBalance > 0 && (
              <div className="flex justify-between px-3 py-2">
                <span className="text-red-500">Penalties</span>
                <span className="font-mono text-red-500">{formatPeso(outstanding.penaltyBalance)}</span>
              </div>
            )}
            <div className="flex justify-between px-3 py-2 font-semibold">
              <span className="text-gray-900 dark:text-white">Total Owed</span>
              <span className="font-mono text-gray-900 dark:text-white">{formatPeso(outstanding.total)}</span>
            </div>
          </div>
        </div>
      )}

      {/* Payment history (non-interest) */}
      {!loan.interest_bearing && loan.loan_payments.length > 0 && (
        <div className="mb-5">
          <p className="text-xs text-gray-400 uppercase tracking-wide mb-2">Payment History</p>
          <div className="divide-y divide-gray-100 dark:divide-gray-700 border border-gray-200 dark:border-gray-700 rounded-lg overflow-hidden">
            {[...loan.loan_payments]
              .sort((a, b) => new Date(b.paid_at) - new Date(a.paid_at))
              .map((p) => (
                <div key={p.id} className="flex justify-between items-center px-3 py-2 bg-white dark:bg-gray-900">
                  <div>
                    <p className="text-sm text-gray-900 dark:text-white font-medium">{formatPeso(p.amount)}</p>
                    {p.notes && <p className="text-xs text-gray-400">{p.notes}</p>}
                  </div>
                  <div className="flex items-center gap-1.5">
                    <p className="text-xs text-gray-400">{new Date(p.paid_at).toLocaleDateString('en-PH')}</p>
                    {(attachmentCounts?.[p.id] ?? 0) > 0 && (
                      <button type="button" onClick={() => setAttachmentModalPaymentId(p.id)}
                        className="text-gray-400 hover:text-blue-500 transition-colors text-base leading-none" title="View receipts">
                        📎
                      </button>
                    )}
                  </div>
                </div>
              ))}
          </div>
        </div>
      )}

      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Payment Amount (PHP)
          </label>
          <input
            {...register('amount')}
            type="number"
            step="0.01"
            max={maxPayment}
            placeholder={`Max ${formatPeso(maxPayment)}`}
            className="w-full border border-gray-300 dark:border-gray-700 rounded-lg px-3 py-2 text-sm bg-white dark:bg-gray-800 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          {errors.amount && <p className="text-red-500 text-xs mt-1">{errors.amount.message}</p>}
        </div>

        {/* Live allocation preview */}
        {loan.interest_bearing && allocation && (
          <div className="border border-[#9FE870]/30 rounded-lg overflow-hidden text-sm bg-[#9FE870]/5">
            <p className="text-xs text-[#2D6A4F] dark:text-[#9FE870] uppercase tracking-wide px-3 py-2">
              Payment Allocation Preview
            </p>
            <div className="divide-y divide-gray-100 dark:divide-gray-700/50 px-3 pb-2">
              <div className="flex justify-between py-1.5">
                <span className="text-red-500">→ Penalties</span>
                <span className="font-mono text-red-500">{formatPeso(allocation.penaltyApplied)}</span>
              </div>
              <div className="flex justify-between py-1.5">
                <span className="text-[#2D6A4F] dark:text-[#9FE870]">→ Interest</span>
                <span className="font-mono text-[#2D6A4F] dark:text-[#9FE870]">{formatPeso(allocation.interestApplied)}</span>
              </div>
              <div className="flex justify-between py-1.5">
                <span className="text-gray-600 dark:text-gray-300">→ Principal</span>
                <span className="font-mono text-gray-600 dark:text-gray-300">{formatPeso(allocation.principalApplied)}</span>
              </div>
            </div>
            <p className="text-xs text-gray-400 px-3 pb-2">
              New principal after payment:{' '}
              <span className="text-gray-900 dark:text-white font-mono">
                {formatPeso(Math.max(0, outstanding.principalBalance - allocation.principalApplied))}
              </span>
            </p>
          </div>
        )}

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Notes (optional)</label>
          <input {...register('notes')} placeholder="e.g. Cash, GCash"
            className="w-full border border-gray-300 dark:border-gray-700 rounded-lg px-3 py-2 text-sm bg-white dark:bg-gray-800 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>

        {/* Receipt upload */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Receipts (optional)</label>
          <div role="button" tabIndex={0}
            className="border-2 border-dashed border-gray-300 dark:border-gray-600 rounded-lg p-3 text-center cursor-pointer hover:border-blue-400 transition-colors"
            onClick={() => fileInputRef.current?.click()}
            onKeyDown={(e) => e.key === 'Enter' && fileInputRef.current?.click()}>
            <span className="text-gray-500 dark:text-gray-400 text-sm">📎 Attach receipt</span>
            <p className="text-gray-400 dark:text-gray-500 text-xs mt-0.5">JPG, PNG, PDF · max 10 MB · up to 10 files</p>
          </div>
          <input ref={fileInputRef} type="file" multiple accept=".jpg,.jpeg,.png,.webp,.pdf" className="hidden" onChange={handleFileSelect} />
          {fileError && <p className="text-red-500 text-xs mt-1">{fileError}</p>}
          {stagedFiles.length > 0 && (
            <div className="flex flex-wrap gap-1 mt-2">
              {stagedFiles.map((f, i) => (
                <span key={i} className="flex items-center gap-1 bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-300 text-xs rounded-full px-2 py-0.5 border border-gray-200 dark:border-gray-700">
                  {f.name.length > 22 ? f.name.slice(0, 20) + '…' : f.name}
                  <button type="button" onClick={() => removeStagedFile(i)} className="text-gray-400 hover:text-red-500 ml-0.5 leading-none">×</button>
                </span>
              ))}
            </div>
          )}
        </div>

        {recordPayment.error && <p className="text-red-500 text-sm">{recordPayment.error.message}</p>}
        {uploadWarning && (
          <p className="bg-yellow-50 dark:bg-yellow-900/30 border border-yellow-300 dark:border-yellow-700 text-yellow-700 dark:text-yellow-300 text-xs rounded-lg px-3 py-2">
            {uploadWarning}
          </p>
        )}

        <div className="flex gap-2 pt-2">
          <Button type="button" variant="ghost" onClick={onClose} className="flex-1">{uploadWarning ? 'Close' : 'Cancel'}</Button>
          {!uploadWarning && (
            <Button type="submit" disabled={recordPayment.isPending || uploadAttachment.isPending || maxPayment <= 0} className="flex-1">
              {uploadAttachment.isPending ? 'Uploading receipts…' : recordPayment.isPending ? 'Recording…' : 'Record Payment'}
            </Button>
          )}
        </div>
      </form>

      {attachmentModalPaymentId && (
        <AttachmentModal entityType="loan_payment" entityId={attachmentModalPaymentId} onClose={() => setAttachmentModalPaymentId(null)} />
      )}
    </Modal>
  )
}
```

- [ ] **Step 2: Test in browser**

On an interest-bearing loan, click Pay. Verify:
- Balance breakdown panel shows Principal / Interest Due / Penalties / Total Owed
- Typing an amount shows the live allocation preview updating
- Allocation sums to payment amount
- Submitting records the payment and the balance updates correctly

- [ ] **Step 3: Commit**

```bash
git add src/components/borrowers/LoanPaymentModal.jsx
git commit -m "feat: add balance breakdown and live allocation preview to LoanPaymentModal"
```

---

## Task 8: LoanTable — New Columns + Action Buttons

**Files:**
- Modify: `src/components/borrowers/LoanTable.jsx`

- [ ] **Step 1: Replace `src/components/borrowers/LoanTable.jsx`**

```jsx
import { useState, useMemo } from 'react'
import { getLoanTotalPaid, getLoanRemaining, isLoanOverdue } from '../../utils/loans.js'
import { computeOutstanding } from '../../utils/loanInterest.js'
import { formatPeso } from '../../utils/money.js'
import { useLoanAttachmentCounts } from '../../hooks/useAttachments.js'
import AttachmentModal from '../ui/AttachmentModal.jsx'
import EditRateModal from './EditRateModal.jsx'
import LedgerStatementModal from './LedgerStatementModal.jsx'
import { AttachmentIcon } from '../ui/icons.jsx'

const STATUS_STYLES = {
  active: 'bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400',
  completed: 'bg-emerald-100 dark:bg-emerald-900/30 text-emerald-700 dark:text-emerald-400',
  defaulted: 'bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400',
  overdue: 'bg-red-100 dark:bg-red-900/30 text-red-600 dark:text-red-400',
}

function progressBarColor(pct) {
  if (pct >= 100) return 'bg-emerald-600'
  if (pct > 80) return 'bg-emerald-500'
  if (pct >= 50) return 'bg-amber-400'
  return 'bg-red-400'
}

export default function LoanTable({ loans, onPay, readOnly = false, borrowerId }) {
  const [attachingLoanId, setAttachingLoanId] = useState(null)
  const [editingRateLoan, setEditingRateLoan] = useState(null)
  const [statementLoan, setStatementLoan] = useState(null)

  const loanIds = useMemo(() => loans.map((l) => l.id), [loans])
  const { data: attCounts = {} } = useLoanAttachmentCounts(loanIds)

  if (loans.length === 0) {
    return <p className="text-gray-400 text-center py-10 text-sm">No loans yet. Click "+ Add Loan" to get started.</p>
  }

  return (
    <>
      <div className="overflow-x-auto rounded-2xl border border-gray-200 dark:border-gray-700">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 dark:bg-gray-800 text-gray-500 dark:text-gray-400 text-xs uppercase tracking-wide">
            <tr>
              <th className="px-4 py-3 text-left">Description</th>
              <th className="px-4 py-3 text-left">Date</th>
              <th className="px-4 py-3 text-right">Principal</th>
              <th className="px-4 py-3 text-right">Paid</th>
              <th className="px-4 py-3 text-right">Interest Due</th>
              <th className="px-4 py-3 text-right">Penalties</th>
              <th className="px-4 py-3 text-right">Total Owed</th>
              <th className="px-4 py-3 text-left">Next Payment</th>
              <th className="px-4 py-3 text-left">Status</th>
              <th className="px-4 py-3 text-center">Files</th>
              <th className="px-4 py-3 text-left">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100 dark:divide-gray-700">
            {loans.map((loan) => {
              // Compute figures depending on interest_bearing
              let principalBalance, totalPaid, interestBalance, penaltyBalance, totalOwed, overdue

              if (loan.interest_bearing) {
                const out = computeOutstanding(loan.amount, loan._ledger ?? [])
                principalBalance = out.principalBalance
                interestBalance = out.interestBalance
                penaltyBalance = out.penaltyBalance
                totalOwed = out.total
                totalPaid = (loan._ledger ?? [])
                  .filter((e) => e.entry_type === 'payment')
                  .reduce((sum, e) => sum + Number(e.amount), 0)
                overdue = isLoanOverdue(loan, loan.amount - principalBalance)
              } else {
                totalPaid = getLoanTotalPaid(loan.loan_payments)
                principalBalance = getLoanRemaining(loan.amount, totalPaid)
                interestBalance = null
                penaltyBalance = null
                totalOwed = principalBalance
                overdue = isLoanOverdue(loan, totalPaid)
              }

              const statusKey = overdue ? 'overdue' : loan.status
              const statusLabel = overdue ? 'Overdue' : loan.status.charAt(0).toUpperCase() + loan.status.slice(1)
              const pct = loan.amount > 0 ? Math.min(((loan.amount - principalBalance) / loan.amount) * 100, 100) : 0
              const count = attCounts[loan.id] || 0

              return (
                <tr key={loan.id} className="bg-white dark:bg-gray-900 hover:bg-gray-50 dark:hover:bg-gray-800/50">
                  <td className="px-4 py-3">
                    <div>
                      <p className="font-medium text-gray-900 dark:text-white">{loan.description || '—'}</p>
                      {loan.notarized && <p className="text-gray-400 text-xs mt-0.5">Notarized</p>}
                      {loan.interest_bearing && loan._rates?.length > 0 && (
                        <p className="text-[#9FE870] text-xs mt-0.5">
                          {loan._rates.at(-1).interest_rate}%/mo · {loan._rates.at(-1).interest_type === 'simple' ? 'Simple' : 'Diminishing'}
                        </p>
                      )}
                      <div className="mt-1.5 h-1.5 bg-gray-100 dark:bg-gray-700 rounded-full w-32 overflow-hidden">
                        <div className={`h-full rounded-full ${progressBarColor(pct)}`} style={{ width: `${pct}%` }} />
                      </div>
                    </div>
                  </td>
                  <td className="px-4 py-3 text-gray-500 dark:text-gray-400 whitespace-nowrap">{loan.loan_date}</td>
                  <td className="px-4 py-3 text-right font-mono font-medium text-gray-900 dark:text-white whitespace-nowrap">{formatPeso(principalBalance)}</td>
                  <td className="px-4 py-3 text-right font-mono text-emerald-600 dark:text-emerald-400 whitespace-nowrap">{formatPeso(totalPaid)}</td>
                  <td className="px-4 py-3 text-right font-mono whitespace-nowrap">
                    {interestBalance !== null
                      ? <span className="text-[#2D6A4F] dark:text-[#9FE870]">{formatPeso(interestBalance)}</span>
                      : <span className="text-gray-300 dark:text-gray-600">—</span>}
                  </td>
                  <td className="px-4 py-3 text-right font-mono whitespace-nowrap">
                    {penaltyBalance !== null
                      ? penaltyBalance > 0
                        ? <span className="text-red-500">{formatPeso(penaltyBalance)}</span>
                        : <span className="text-gray-400">₱0.00</span>
                      : <span className="text-gray-300 dark:text-gray-600">—</span>}
                  </td>
                  <td className="px-4 py-3 text-right font-mono font-bold text-gray-900 dark:text-white whitespace-nowrap">{formatPeso(totalOwed)}</td>
                  <td className="px-4 py-3 text-gray-500 dark:text-gray-400 whitespace-nowrap">{loan.next_payment_date || '—'}</td>
                  <td className="px-4 py-3">
                    <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${STATUS_STYLES[statusKey]}`}>{statusLabel}</span>
                  </td>
                  <td className="px-4 py-3 text-center">
                    {(!readOnly || count > 0) && (
                      <button onClick={() => setAttachingLoanId(loan.id)}
                        className="inline-flex items-center gap-1 text-gray-400 hover:text-[#2D6A4F] dark:hover:text-[#9FE870] transition-colors text-xs" title="Attachments">
                        <AttachmentIcon className="w-4 h-4" />
                        {count > 0 && (
                          <span className="bg-[#9FE870]/20 text-[#2D6A4F] dark:text-[#9FE870] text-xs font-medium px-1.5 py-0.5 rounded-full leading-none">{count}</span>
                        )}
                      </button>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      {!readOnly && loan.status !== 'completed' && loan.status !== 'defaulted' && (
                        <button onClick={() => onPay(loan)}
                          className="text-[#2D6A4F] dark:text-[#9FE870] hover:text-[#9FE870] dark:hover:text-white text-xs font-semibold transition-colors">
                          Pay
                        </button>
                      )}
                      {!readOnly && loan.interest_bearing && (
                        <>
                          <button onClick={() => setEditingRateLoan(loan)}
                            className="text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 text-xs transition-colors" title="Edit interest rate">
                            ⚙
                          </button>
                          <button onClick={() => setStatementLoan(loan)}
                            className="text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 text-xs transition-colors" title="View statement">
                            📄
                          </button>
                        </>
                      )}
                    </div>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>

      {attachingLoanId && (
        <AttachmentModal entityType="loan" entityId={attachingLoanId} borrowerId={borrowerId} readOnly={readOnly} onClose={() => setAttachingLoanId(null)} />
      )}
      {editingRateLoan && (
        <EditRateModal loan={editingRateLoan} onClose={() => setEditingRateLoan(null)} onSuccess={() => setEditingRateLoan(null)} />
      )}
      {statementLoan && (
        <LedgerStatementModal loan={statementLoan} onClose={() => setStatementLoan(null)} />
      )}
    </>
  )
}
```

- [ ] **Step 2: Test in browser**

Open a borrower with at least one interest-bearing loan. Verify:
- New columns show correctly (Interest Due in green, Penalties in red if >0, Total Owed in bold)
- Non-interest loans show `—` in Interest Due, Penalties columns
- ⚙ and 📄 buttons appear only on interest-bearing loan rows
- ⚙ opens EditRateModal, 📄 opens LedgerStatementModal (placeholder until Task 9)

- [ ] **Step 3: Commit**

```bash
git add src/components/borrowers/LoanTable.jsx
git commit -m "feat: add interest columns and rate/statement action buttons to LoanTable"
```

---

## Task 9: LedgerStatementModal

**Files:**
- Create: `src/components/borrowers/LedgerStatementModal.jsx`

- [ ] **Step 1: Create `src/components/borrowers/LedgerStatementModal.jsx`**

```jsx
import { useState, useMemo } from 'react'
import { useLoanLedger, useWaivePenalty } from '../../hooks/useLoans.js'
import { computeOutstanding } from '../../utils/loanInterest.js'
import { formatPeso } from '../../utils/money.js'
import Modal from '../ui/Modal.jsx'
import Button from '../ui/Button.jsx'

const ENTRY_LABELS = {
  interest_charge: 'Interest charge',
  late_fee: 'Late fee',
  penalty_interest: 'Penalty interest',
  payment: 'Payment received',
  penalty_waiver: 'Penalty waived',
}

const CHARGE_TYPES = new Set(['interest_charge', 'late_fee', 'penalty_interest'])
const PENALTY_TYPES = new Set(['late_fee', 'penalty_interest'])

export default function LedgerStatementModal({ loan, onClose }) {
  const { data: ledger = [], isLoading } = useLoanLedger(loan.id)
  const waivePenalty = useWaivePenalty()
  const [waivingEntry, setWaivingEntry] = useState(null)
  const [waiveAmount, setWaiveAmount] = useState('')
  const [waiveNotes, setWaiveNotes] = useState('')

  // Rate change rows from _rates
  const rateRows = useMemo(
    () =>
      (loan._rates ?? []).map((r) => ({
        type: 'rate_change',
        date: r.effective_from,
        label: `Rate changed → ${r.interest_rate}%/mo (${r.interest_type === 'simple' ? 'Simple' : 'Diminishing'}) · Late ${r.late_fee_rate}% · Penalty ${r.penalty_rate}%`,
      })),
    [loan._rates]
  )

  // Build rows: synthetic disbursement + ledger + rate changes, sorted by date
  const allRows = useMemo(() => {
    const rows = [
      { type: 'disbursement', date: loan.loan_date, amount: loan.amount },
      ...ledger.map((e) => ({ type: 'ledger', entry: e, date: e.period_date })),
      ...rateRows,
    ].sort((a, b) => a.date.localeCompare(b.date))
    return rows
  }, [ledger, rateRows, loan])

  // Running balance computation
  const rowsWithBalance = useMemo(() => {
    let balance = 0
    return allRows.map((row) => {
      if (row.type === 'disbursement') {
        balance = row.amount
        return { ...row, balance }
      }
      if (row.type === 'rate_change') return { ...row, balance }
      const e = row.entry
      if (CHARGE_TYPES.has(e.entry_type)) {
        balance = Math.round((balance + Number(e.amount)) * 100) / 100
      } else if (e.entry_type === 'payment') {
        balance = Math.round((balance - Number(e.amount)) * 100) / 100
      } else if (e.entry_type === 'penalty_waiver') {
        balance = Math.round((balance - Number(e.amount)) * 100) / 100
      }
      return { ...row, balance: Math.max(0, balance) }
    })
  }, [allRows])

  const outstanding = useMemo(() => computeOutstanding(loan.amount, ledger), [loan.amount, ledger])

  async function handleWaive() {
    const amt = Number(waiveAmount)
    if (!waivingEntry || amt <= 0) return
    try {
      await waivePenalty.mutateAsync({ loan, amount: amt, notes: waiveNotes || null })
      setWaivingEntry(null)
      setWaiveAmount('')
      setWaiveNotes('')
    } catch (err) {
      console.error(err)
    }
  }

  return (
    <Modal title={`Statement — ${loan.description || 'Loan'}`} onClose={onClose}>
      {/* Summary */}
      <div className="grid grid-cols-3 gap-3 mb-5 text-center">
        <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-3">
          <p className="text-xs text-gray-400 uppercase tracking-wide mb-1">Principal Left</p>
          <p className="font-mono font-bold text-gray-900 dark:text-white text-sm">{formatPeso(outstanding.principalBalance)}</p>
        </div>
        <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-3">
          <p className="text-xs text-[#2D6A4F] dark:text-[#9FE870] uppercase tracking-wide mb-1">Interest Due</p>
          <p className="font-mono font-bold text-[#2D6A4F] dark:text-[#9FE870] text-sm">{formatPeso(outstanding.interestBalance)}</p>
        </div>
        <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-3">
          <p className="text-xs text-red-500 uppercase tracking-wide mb-1">Penalties</p>
          <p className="font-mono font-bold text-red-500 text-sm">{formatPeso(outstanding.penaltyBalance)}</p>
        </div>
      </div>

      {/* Ledger table */}
      {isLoading ? (
        <p className="text-gray-400 text-center py-6 text-sm">Loading statement…</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-gray-200 dark:border-gray-700 mb-4">
          <table className="w-full text-xs">
            <thead className="bg-gray-50 dark:bg-gray-800 text-gray-500 dark:text-gray-400 uppercase tracking-wide">
              <tr>
                <th className="px-3 py-2 text-left">Date</th>
                <th className="px-3 py-2 text-left">Entry</th>
                <th className="px-3 py-2 text-right">Charge</th>
                <th className="px-3 py-2 text-right">Payment</th>
                <th className="px-3 py-2 text-right">Balance</th>
                <th className="px-3 py-2"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100 dark:divide-gray-700">
              {rowsWithBalance.map((row, i) => {
                if (row.type === 'disbursement') {
                  return (
                    <tr key="disbursement" className="bg-white dark:bg-gray-900">
                      <td className="px-3 py-2 text-gray-400">{row.date}</td>
                      <td className="px-3 py-2 font-medium text-gray-900 dark:text-white">Loan disbursed</td>
                      <td className="px-3 py-2 text-right font-mono text-gray-900 dark:text-white">{formatPeso(row.amount)}</td>
                      <td className="px-3 py-2 text-right text-gray-300 dark:text-gray-600">—</td>
                      <td className="px-3 py-2 text-right font-mono text-gray-900 dark:text-white">{formatPeso(row.balance)}</td>
                      <td className="px-3 py-2"></td>
                    </tr>
                  )
                }
                if (row.type === 'rate_change') {
                  return (
                    <tr key={`rate-${i}`} className="bg-blue-50/30 dark:bg-blue-900/10">
                      <td className="px-3 py-2 text-gray-400">{row.date}</td>
                      <td className="px-3 py-2 text-blue-500 dark:text-blue-400 italic" colSpan={3}>{row.label}</td>
                      <td className="px-3 py-2 text-right font-mono text-gray-500">{formatPeso(row.balance)}</td>
                      <td className="px-3 py-2"></td>
                    </tr>
                  )
                }

                const e = row.entry
                const isCharge = CHARGE_TYPES.has(e.entry_type)
                const isPenalty = PENALTY_TYPES.has(e.entry_type)
                const isWaiver = e.entry_type === 'penalty_waiver'
                const isPayment = e.entry_type === 'payment'

                return (
                  <tr key={e.id} className={`bg-white dark:bg-gray-900 ${isPenalty ? 'bg-red-50/30 dark:bg-red-900/5' : ''}`}>
                    <td className="px-3 py-2 text-gray-400">{e.period_date}</td>
                    <td className="px-3 py-2">
                      <span className={
                        isPayment ? 'text-blue-500' :
                        isPenalty ? 'text-red-500' :
                        isWaiver ? 'text-emerald-500' :
                        'text-[#2D6A4F] dark:text-[#9FE870]'
                      }>
                        {ENTRY_LABELS[e.entry_type]}
                      </span>
                      {isPayment && (
                        <p className="text-gray-400 text-xs mt-0.5">
                          → penalty {formatPeso(e.penalty_applied)} · interest {formatPeso(e.interest_applied)} · principal {formatPeso(e.principal_applied)}
                        </p>
                      )}
                      {e.notes && <p className="text-gray-400 text-xs">{e.notes}</p>}
                    </td>
                    <td className="px-3 py-2 text-right font-mono">
                      {isCharge ? <span className={isPenalty ? 'text-red-500' : 'text-[#2D6A4F] dark:text-[#9FE870]'}>{formatPeso(e.amount)}</span> : <span className="text-gray-300 dark:text-gray-600">—</span>}
                    </td>
                    <td className="px-3 py-2 text-right font-mono">
                      {(isPayment || isWaiver) ? <span className="text-blue-500">−{formatPeso(e.amount)}</span> : <span className="text-gray-300 dark:text-gray-600">—</span>}
                    </td>
                    <td className="px-3 py-2 text-right font-mono text-gray-900 dark:text-white">{formatPeso(row.balance)}</td>
                    <td className="px-3 py-2">
                      {isPenalty && outstanding.penaltyBalance > 0 && (
                        <button onClick={() => { setWaivingEntry(e); setWaiveAmount(String(e.amount)) }}
                          className="text-xs text-amber-500 hover:text-amber-700 transition-colors">Waive</button>
                      )}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* Waive panel */}
      {waivingEntry && (
        <div className="border border-amber-200 dark:border-amber-700 rounded-lg p-3 mb-4 bg-amber-50 dark:bg-amber-900/20">
          <p className="text-xs font-medium text-amber-700 dark:text-amber-400 mb-2">Waive Penalty ({ENTRY_LABELS[waivingEntry.entry_type]})</p>
          <div className="flex gap-2 mb-2">
            <input
              type="number" step="0.01" value={waiveAmount}
              onChange={(e) => setWaiveAmount(e.target.value)}
              className="flex-1 border border-amber-300 rounded px-2 py-1 text-sm bg-white dark:bg-gray-800 text-gray-900 dark:text-white"
              placeholder="Amount to waive"
            />
            <input
              type="text" value={waiveNotes}
              onChange={(e) => setWaiveNotes(e.target.value)}
              className="flex-1 border border-amber-300 rounded px-2 py-1 text-sm bg-white dark:bg-gray-800 text-gray-900 dark:text-white"
              placeholder="Reason (optional)"
            />
          </div>
          <div className="flex gap-2">
            <button onClick={() => setWaivingEntry(null)} className="text-xs text-gray-500 hover:text-gray-700">Cancel</button>
            <Button onClick={handleWaive} disabled={waivePenalty.isPending} className="text-xs py-1 px-3">
              {waivePenalty.isPending ? 'Waiving…' : 'Confirm Waiver'}
            </Button>
          </div>
          {waivePenalty.error && <p className="text-red-500 text-xs mt-1">{waivePenalty.error.message}</p>}
        </div>
      )}

      <div className="flex justify-end">
        <Button variant="ghost" onClick={onClose}>Close</Button>
      </div>
    </Modal>
  )
}
```

- [ ] **Step 2: Test in browser**

Open an interest-bearing loan's statement (📄 button). Verify:
- Summary row shows Principal Left / Interest Due / Penalties
- Ledger table shows all entries with correct charge/payment/balance columns
- Rate change rows appear in correct date order (blue/italic)
- Disbursement row appears first
- Clicking "Waive" on a penalty row opens the waive panel
- Confirming a waiver inserts a `penalty_waiver` entry and the balance updates

- [ ] **Step 3: Commit**

```bash
git add src/components/borrowers/LedgerStatementModal.jsx
git commit -m "feat: add LedgerStatementModal with full statement view and penalty waiver UI"
```

---

## Self-Review Checklist

After all tasks are committed, verify against spec:

- [ ] `minimum_payment` in DB and LoanForm — partial payments correctly trigger penalties when set
- [ ] `allocatePayment` caps `principalApplied` at `principalBalance` (tested in Task 2)
- [ ] Loan completion detected: `outstanding.total - payment <= 0` → `status = completed` (in `useRecordLoanPayment`)
- [ ] `generateMissingEntries` guard: returns `[]` for completed/defaulted loans (tested in Task 2)
- [ ] `getActiveRate` null → period skipped (tested in Task 2)
- [ ] Rate change validates `effective_from >= lastLedgerDate` (in `useAddLoanInterestRate`)
- [ ] `penalty_waiver` entry_type in DB schema, `useWaivePenalty` hook, statement UI
- [ ] One-time loan monthly cadence after due date (tested in Task 2)
- [ ] Payment `period_date = loan.next_payment_date` at time of recording
- [ ] Non-interest loans: zero changes to existing behavior (`loan_payments` path unchanged)
- [ ] Run full test suite: `npm test` — all pass
