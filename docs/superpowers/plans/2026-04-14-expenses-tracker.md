# Expenses Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated Expenses section for logging all non-card spending (cash, GCash, Maya, bank transfer) organized by category (utilities, food, rent, etc.) with a filterable table and category overview.

**Architecture:** New `expenses` Supabase table with RLS; React Query hooks following the existing `useTransactions`/`useLoans` pattern; new `/expenses` page with sticky summary header, category tiles, month filter, and table; a dashboard section for quick access.

**Tech Stack:** React, Supabase, @tanstack/react-query, react-router-dom, react-hook-form, zod, Tailwind CSS, Vitest

> **Note:** Per project policy, do NOT commit any changes. Stage files only. Push/commit only when the user explicitly says so.

---

## File Map

**Create:**
- `src/utils/expenses.js` — category/payment constants, label helpers, filter & group utilities
- `src/utils/expenses.test.js` — unit tests for all utility functions
- `src/hooks/useExpenses.js` — React Query hooks: fetch, add, edit, archive
- `src/components/expenses/ExpenseForm.jsx` — add/edit modal (supports both modes)
- `src/components/expenses/ExpenseTable.jsx` — filterable table with edit/archive actions
- `src/components/expenses/CategoryTiles.jsx` — category summary tiles row
- `src/components/expenses/ExpenseSummary.jsx` — sticky header with month total + payment breakdown
- `src/pages/ExpensesPage.jsx` — full expenses page assembling all components

**Modify:**
- `src/lib/zod-schemas.js` — add `expenseSchema`
- `src/components/ui/icons.jsx` — add 12 category SVG icons + `ExpensesIcon`
- `src/pages/DashboardPage.jsx` — add "My Expenses" section
- `src/components/layout/Navbar.jsx` — add "Expenses" nav link
- `src/App.jsx` — add `/expenses` protected route

---

### Task 1: Supabase Migration

**Files:**
- Reference: Supabase SQL Editor (run manually — no file to create)

- [ ] **Step 1: Run this SQL in the Supabase dashboard → SQL Editor**

```sql
-- Create expenses table
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

-- Enable RLS
alter table public.expenses enable row level security;

-- Policies
create policy "Users can view own expenses"
  on public.expenses for select
  using (auth.uid() = user_id);

create policy "Users can insert own expenses"
  on public.expenses for insert
  with check (auth.uid() = user_id);

create policy "Users can update own expenses"
  on public.expenses for update
  using (auth.uid() = user_id);

create policy "Users can delete own expenses"
  on public.expenses for delete
  using (auth.uid() = user_id);

-- Index for fast user+date queries
create index expenses_user_id_date_idx
  on public.expenses(user_id, expense_date desc);
```

- [ ] **Step 2: Verify in Supabase Table Editor**

Confirm the `expenses` table exists with all 10 columns and RLS is enabled (shown as green shield icon).

---

### Task 2: Expense Utility Functions + Tests

**Files:**
- Create: `src/utils/expenses.js`
- Create: `src/utils/expenses.test.js`

- [ ] **Step 1: Write the failing tests first**

Create `src/utils/expenses.test.js`:

```js
import { describe, it, expect } from 'vitest'
import {
  CATEGORIES,
  PAYMENT_METHODS,
  getCategoryLabel,
  getPaymentMethodLabel,
  filterByMonth,
  groupByCategory,
  groupByPaymentMethod,
} from './expenses.js'

describe('getCategoryLabel', () => {
  it('returns human label for known category', () => {
    expect(getCategoryLabel('food')).toBe('Food & Dining')
  })
  it('returns human label for utilities', () => {
    expect(getCategoryLabel('utilities')).toBe('Utilities')
  })
  it('returns Others for unknown key', () => {
    expect(getCategoryLabel('unknown')).toBe('Others')
  })
})

describe('getPaymentMethodLabel', () => {
  it('returns GCash for gcash', () => {
    expect(getPaymentMethodLabel('gcash')).toBe('GCash')
  })
  it('returns Cash for cash', () => {
    expect(getPaymentMethodLabel('cash')).toBe('Cash')
  })
  it('returns Others for unknown key', () => {
    expect(getPaymentMethodLabel('unknown')).toBe('Others')
  })
})

describe('filterByMonth', () => {
  const expenses = [
    { id: '1', expense_date: '2026-04-05', amount: 100 },
    { id: '2', expense_date: '2026-04-20', amount: 200 },
    { id: '3', expense_date: '2026-03-15', amount: 50 },
  ]
  it('returns only expenses in the given month/year', () => {
    const result = filterByMonth(expenses, 2026, 4)
    expect(result).toHaveLength(2)
    expect(result.map((e) => e.id)).toEqual(['1', '2'])
  })
  it('returns empty array when no match', () => {
    expect(filterByMonth(expenses, 2025, 1)).toHaveLength(0)
  })
  it('returns empty array for empty input', () => {
    expect(filterByMonth([], 2026, 4)).toHaveLength(0)
  })
})

describe('groupByCategory', () => {
  const expenses = [
    { category: 'food', amount: 300 },
    { category: 'food', amount: 200 },
    { category: 'utilities', amount: 1500 },
  ]
  it('sums amounts by category', () => {
    const result = groupByCategory(expenses)
    expect(result.food).toBeCloseTo(500)
    expect(result.utilities).toBeCloseTo(1500)
  })
  it('returns 0 for categories with no expenses', () => {
    const result = groupByCategory(expenses)
    expect(result.rent).toBe(0)
  })
})

describe('groupByPaymentMethod', () => {
  const expenses = [
    { payment_method: 'cash', amount: 500 },
    { payment_method: 'gcash', amount: 300 },
    { payment_method: 'cash', amount: 200 },
  ]
  it('sums amounts by payment method', () => {
    const result = groupByPaymentMethod(expenses)
    expect(result.cash).toBeCloseTo(700)
    expect(result.gcash).toBeCloseTo(300)
  })
  it('returns 0 for methods with no expenses', () => {
    const result = groupByPaymentMethod(expenses)
    expect(result.maya).toBe(0)
  })
})

describe('CATEGORIES constant', () => {
  it('has 12 entries', () => {
    expect(CATEGORIES).toHaveLength(12)
  })
  it('each entry has value, label, color', () => {
    CATEGORIES.forEach((c) => {
      expect(c).toHaveProperty('value')
      expect(c).toHaveProperty('label')
      expect(c).toHaveProperty('color')
    })
  })
})

describe('PAYMENT_METHODS constant', () => {
  it('has 5 entries', () => {
    expect(PAYMENT_METHODS).toHaveLength(5)
  })
})
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
npx vitest run src/utils/expenses.test.js
```

Expected: all tests FAIL with "Cannot find module './expenses.js'"

- [ ] **Step 3: Create `src/utils/expenses.js`**

```js
import { addMoney } from './money.js'

export const CATEGORIES = [
  { value: 'utilities',     label: 'Utilities',        color: '#3B82F6' },
  { value: 'food',          label: 'Food & Dining',    color: '#F59E0B' },
  { value: 'transportation',label: 'Transportation',   color: '#8B5CF6' },
  { value: 'rent',          label: 'Rent / Housing',   color: '#EC4899' },
  { value: 'healthcare',    label: 'Healthcare',       color: '#EF4444' },
  { value: 'shopping',      label: 'Shopping',         color: '#F97316' },
  { value: 'entertainment', label: 'Entertainment',    color: '#06B6D4' },
  { value: 'subscriptions', label: 'Subscriptions',    color: '#6366F1' },
  { value: 'education',     label: 'Education',        color: '#10B981' },
  { value: 'personal_care', label: 'Personal Care',    color: '#D946EF' },
  { value: 'insurance',     label: 'Insurance',        color: '#64748B' },
  { value: 'others',        label: 'Others',           color: '#9CA3AF' },
]

export const PAYMENT_METHODS = [
  { value: 'cash',          label: 'Cash' },
  { value: 'gcash',         label: 'GCash' },
  { value: 'maya',          label: 'Maya' },
  { value: 'bank_transfer', label: 'Bank Transfer' },
  { value: 'others',        label: 'Others' },
]

export function getCategoryLabel(value) {
  return CATEGORIES.find((c) => c.value === value)?.label ?? 'Others'
}

export function getPaymentMethodLabel(value) {
  return PAYMENT_METHODS.find((m) => m.value === value)?.label ?? 'Others'
}

// Returns expenses matching the given year and 1-based month
export function filterByMonth(expenses, year, month) {
  return expenses.filter((e) => {
    const d = new Date(e.expense_date + 'T00:00:00')
    return d.getFullYear() === year && d.getMonth() + 1 === month
  })
}

// Returns { utilities: 0, food: 300, ... } — all 12 categories initialized to 0
export function groupByCategory(expenses) {
  const result = Object.fromEntries(CATEGORIES.map((c) => [c.value, 0]))
  for (const e of expenses) {
    if (result[e.category] !== undefined) {
      result[e.category] = addMoney(result[e.category], e.amount)
    }
  }
  return result
}

// Returns { cash: 0, gcash: 0, ... } — all 5 methods initialized to 0
export function groupByPaymentMethod(expenses) {
  const result = Object.fromEntries(PAYMENT_METHODS.map((m) => [m.value, 0]))
  for (const e of expenses) {
    if (result[e.payment_method] !== undefined) {
      result[e.payment_method] = addMoney(result[e.payment_method], e.amount)
    }
  }
  return result
}
```

- [ ] **Step 4: Run tests — confirm all pass**

```bash
npx vitest run src/utils/expenses.test.js
```

Expected: all tests PASS

---

### Task 3: Zod Schema

**Files:**
- Modify: `src/lib/zod-schemas.js`

- [ ] **Step 1: Add `expenseSchema` at the bottom of `src/lib/zod-schemas.js`**

```js
export const expenseSchema = z.object({
  expense_date: z.string().min(1, 'Date is required'),
  category: z.enum([
    'utilities','food','transportation','rent','healthcare',
    'shopping','entertainment','subscriptions','education',
    'personal_care','insurance','others',
  ], { required_error: 'Category is required' }),
  description: z.string().min(1, 'Description is required'),
  amount: z.coerce
    .number({ invalid_type_error: 'Must be a number' })
    .positive('Amount must be greater than 0'),
  payment_method: z.enum(
    ['cash','gcash','maya','bank_transfer','others'],
    { required_error: 'Payment method is required' }
  ),
  notes: z.string().optional(),
})
```

---

### Task 4: Category Icons

**Files:**
- Modify: `src/components/ui/icons.jsx`

- [ ] **Step 1: Append these icon components to the end of `src/components/ui/icons.jsx`**

```jsx
// ── Expense nav icon ──────────────────────────────────────────────────────────
export function ExpensesIcon({ className = '' }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" xmlns="http://www.w3.org/2000/svg"
      className={className} aria-hidden="true">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-4H9l3-3 3 3h-2v4z"/>
    </svg>
  )
}

// ── Category icons ─────────────────────────────────────────────────────────────
export function UtilitiesIcon({ className = '' }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" xmlns="http://www.w3.org/2000/svg"
      className={className} aria-hidden="true">
      <path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/>
    </svg>
  )
}

export function FoodIcon({ className = '' }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" xmlns="http://www.w3.org/2000/svg"
      className={className} aria-hidden="true">
      <path d="M18 8h1a4 4 0 010 8h-1M2 8h16v9a4 4 0 01-4 4H6a4 4 0 01-4-4V8zM6 1v3M10 1v3M14 1v3"/>
    </svg>
  )
}

export function TransportIcon({ className = '' }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" xmlns="http://www.w3.org/2000/svg"
      className={className} aria-hidden="true">
      <rect x="1" y="3" width="15" height="13" rx="2"/>
      <path d="M16 8h4l3 3v5h-7V8zM5.5 17a1.5 1.5 0 100 3 1.5 1.5 0 000-3zM18.5 17a1.5 1.5 0 100 3 1.5 1.5 0 000-3z"/>
    </svg>
  )
}

export function RentIcon({ className = '' }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" xmlns="http://www.w3.org/2000/svg"
      className={className} aria-hidden="true">
      <path d="M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z"/>
      <polyline points="9 22 9 12 15 12 15 22"/>
    </svg>
  )
}

export function HealthcareIcon({ className = '' }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" xmlns="http://www.w3.org/2000/svg"
      className={className} aria-hidden="true">
      <path d="M20.84 4.61a5.5 5.5 0 00-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 00-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 000-7.78z"/>
    </svg>
  )
}

export function ShoppingIcon({ className = '' }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" xmlns="http://www.w3.org/2000/svg"
      className={className} aria-hidden="true">
      <path d="M6 2L3 6v14a2 2 0 002 2h14a2 2 0 002-2V6l-3-4zM3 6h18M16 10a4 4 0 01-8 0"/>
    </svg>
  )
}

export function EntertainmentIcon({ className = '' }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" xmlns="http://www.w3.org/2000/svg"
      className={className} aria-hidden="true">
      <polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/>
    </svg>
  )
}

export function SubscriptionsIcon({ className = '' }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" xmlns="http://www.w3.org/2000/svg"
      className={className} aria-hidden="true">
      <polyline points="23 4 23 10 17 10"/>
      <polyline points="1 20 1 14 7 14"/>
      <path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/>
    </svg>
  )
}

export function EducationIcon({ className = '' }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" xmlns="http://www.w3.org/2000/svg"
      className={className} aria-hidden="true">
      <path d="M2 3h6a4 4 0 014 4v14a3 3 0 00-3-3H2zM22 3h-6a4 4 0 00-4 4v14a3 3 0 013-3h7z"/>
    </svg>
  )
}

export function PersonalCareIcon({ className = '' }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" xmlns="http://www.w3.org/2000/svg"
      className={className} aria-hidden="true">
      <path d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2"/>
      <circle cx="12" cy="7" r="4"/>
    </svg>
  )
}

export function InsuranceIcon({ className = '' }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" xmlns="http://www.w3.org/2000/svg"
      className={className} aria-hidden="true">
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
    </svg>
  )
}

export function OthersIcon({ className = '' }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" xmlns="http://www.w3.org/2000/svg"
      className={className} aria-hidden="true">
      <circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>
    </svg>
  )
}
```

---

### Task 5: useExpenses Hook

**Files:**
- Create: `src/hooks/useExpenses.js`

- [ ] **Step 1: Create `src/hooks/useExpenses.js`**

```js
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase.js'

export function useExpenses() {
  return useQuery({
    queryKey: ['expenses'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('expenses')
        .select('*')
        .eq('archived', false)
        .order('expense_date', { ascending: false })
      if (error) throw error
      return data
    },
  })
}

export function useAddExpense() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (expenseData) => {
      const { data: { user } } = await supabase.auth.getUser()
      const { data, error } = await supabase
        .from('expenses')
        .insert({ ...expenseData, user_id: user.id })
        .select()
        .single()
      if (error) throw error
      return data
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['expenses'] }),
  })
}

export function useEditExpense() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, expenseData }) => {
      const { data, error } = await supabase
        .from('expenses')
        .update(expenseData)
        .eq('id', id)
        .select()
        .single()
      if (error) throw error
      return data
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['expenses'] }),
  })
}

export function useArchiveExpense() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id) => {
      const { error } = await supabase
        .from('expenses')
        .update({ archived: true })
        .eq('id', id)
      if (error) throw error
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['expenses'] }),
  })
}
```

---

### Task 6: ExpenseForm Modal

**Files:**
- Create: `src/components/expenses/ExpenseForm.jsx`

This component handles both **add** (no `expense` prop) and **edit** (`expense` prop with existing data) modes.

- [ ] **Step 1: Create `src/components/expenses/ExpenseForm.jsx`**

```jsx
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { expenseSchema } from '../../lib/zod-schemas.js'
import { useAddExpense, useEditExpense } from '../../hooks/useExpenses.js'
import { CATEGORIES, PAYMENT_METHODS } from '../../utils/expenses.js'
import Modal from '../ui/Modal.jsx'
import Button from '../ui/Button.jsx'

const today = new Date().toISOString().slice(0, 10)

const inputClass =
  'w-full border border-gray-300 dark:border-gray-700 rounded-xl px-4 py-2.5 text-sm bg-white dark:bg-gray-800 text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-[#9FE870] focus:border-transparent'

const labelClass =
  'block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5'

export default function ExpenseForm({ expense = null, onClose, onSuccess }) {
  const isEdit = !!expense
  const addExpense = useAddExpense()
  const editExpense = useEditExpense()

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm({
    resolver: zodResolver(expenseSchema),
    defaultValues: {
      expense_date: expense?.expense_date ?? today,
      category: expense?.category ?? '',
      description: expense?.description ?? '',
      amount: expense?.amount ?? '',
      payment_method: expense?.payment_method ?? '',
      notes: expense?.notes ?? '',
    },
  })

  async function onSubmit(values) {
    try {
      if (isEdit) {
        await editExpense.mutateAsync({ id: expense.id, expenseData: values })
      } else {
        await addExpense.mutateAsync(values)
      }
      onSuccess?.()
      onClose()
    } catch (err) {
      console.error(err)
    }
  }

  const isPending = addExpense.isPending || editExpense.isPending
  const mutationError = addExpense.error || editExpense.error

  return (
    <Modal title={isEdit ? 'Edit Expense' : 'Add Expense'} onClose={onClose}>
      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
        {/* Date */}
        <div>
          <label className={labelClass}>Date</label>
          <input
            {...register('expense_date')}
            type="date"
            max={today}
            className={inputClass}
          />
          {errors.expense_date && (
            <p className="text-red-500 text-xs mt-1">{errors.expense_date.message}</p>
          )}
        </div>

        {/* Category */}
        <div>
          <label className={labelClass}>Category</label>
          <select {...register('category')} className={inputClass}>
            <option value="">Select category</option>
            {CATEGORIES.map((c) => (
              <option key={c.value} value={c.value}>{c.label}</option>
            ))}
          </select>
          {errors.category && (
            <p className="text-red-500 text-xs mt-1">{errors.category.message}</p>
          )}
        </div>

        {/* Description */}
        <div>
          <label className={labelClass}>Description</label>
          <input
            {...register('description')}
            type="text"
            placeholder="e.g. Meralco bill, Groceries, Rent"
            className={inputClass}
          />
          {errors.description && (
            <p className="text-red-500 text-xs mt-1">{errors.description.message}</p>
          )}
        </div>

        {/* Amount */}
        <div>
          <label className={labelClass}>Amount (PHP)</label>
          <input
            {...register('amount')}
            type="number"
            step="0.01"
            placeholder="0.00"
            className={inputClass}
          />
          {errors.amount && (
            <p className="text-red-500 text-xs mt-1">{errors.amount.message}</p>
          )}
        </div>

        {/* Payment Method */}
        <div>
          <label className={labelClass}>Payment Method</label>
          <select {...register('payment_method')} className={inputClass}>
            <option value="">Select method</option>
            {PAYMENT_METHODS.map((m) => (
              <option key={m.value} value={m.value}>{m.label}</option>
            ))}
          </select>
          {errors.payment_method && (
            <p className="text-red-500 text-xs mt-1">{errors.payment_method.message}</p>
          )}
        </div>

        {/* Notes */}
        <div>
          <label className={labelClass}>Notes (optional)</label>
          <textarea
            {...register('notes')}
            rows={2}
            placeholder="Any additional details…"
            className={inputClass}
          />
        </div>

        {mutationError && (
          <p className="text-red-500 text-sm">{mutationError.message}</p>
        )}

        <div className="flex gap-2 pt-2">
          <Button type="button" variant="ghost" onClick={onClose} className="flex-1">
            Cancel
          </Button>
          <Button type="submit" disabled={isPending} className="flex-1">
            {isPending ? 'Saving…' : isEdit ? 'Save Changes' : 'Add Expense'}
          </Button>
        </div>
      </form>
    </Modal>
  )
}
```

---

### Task 7: ExpenseTable Component

**Files:**
- Create: `src/components/expenses/ExpenseTable.jsx`

- [ ] **Step 1: Create `src/components/expenses/ExpenseTable.jsx`**

```jsx
import { useState } from 'react'
import { formatPeso } from '../../utils/money.js'
import { getCategoryLabel, getPaymentMethodLabel, CATEGORIES } from '../../utils/expenses.js'
import { useArchiveExpense } from '../../hooks/useExpenses.js'
import Button from '../ui/Button.jsx'

function formatDate(dateStr) {
  if (!dateStr) return '—'
  return new Date(dateStr + 'T00:00:00').toLocaleDateString('en-PH', {
    month: 'short', day: 'numeric', year: 'numeric',
  })
}

function CategoryBadge({ category }) {
  const cat = CATEGORIES.find((c) => c.value === category)
  return (
    <span
      className="text-xs font-semibold px-2.5 py-1 rounded-full"
      style={{
        backgroundColor: cat ? cat.color + '22' : '#9CA3AF22',
        color: cat ? cat.color : '#9CA3AF',
      }}
    >
      {getCategoryLabel(category)}
    </span>
  )
}

export default function ExpenseTable({ expenses, onEdit }) {
  const archive = useArchiveExpense()
  const [confirmArchiveId, setConfirmArchiveId] = useState(null)

  if (!expenses || expenses.length === 0) {
    return (
      <div className="text-center py-16 text-gray-500 border border-dashed border-gray-300 dark:border-gray-700 rounded-xl">
        No expenses for this period.
      </div>
    )
  }

  return (
    <div className="overflow-x-auto rounded-2xl border border-gray-200 dark:border-gray-700">
      <table className="w-full text-sm">
        <thead>
          <tr className="bg-gray-100 dark:bg-gray-800 text-gray-500 dark:text-gray-400 text-xs uppercase tracking-wide">
            <th className="px-4 py-3 text-left whitespace-nowrap">Date</th>
            <th className="px-4 py-3 text-left whitespace-nowrap">Category</th>
            <th className="px-4 py-3 text-left">Description</th>
            <th className="px-4 py-3 text-right whitespace-nowrap">Amount</th>
            <th className="px-4 py-3 text-left whitespace-nowrap">Payment</th>
            <th className="px-4 py-3 text-left">Notes</th>
            <th className="px-4 py-3 text-center whitespace-nowrap">Actions</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100 dark:divide-gray-800">
          {expenses.map((e) => (
            <tr key={e.id} className="hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors text-gray-700 dark:text-gray-200">
              <td className="px-4 py-3 whitespace-nowrap text-gray-500 dark:text-gray-400">
                {formatDate(e.expense_date)}
              </td>
              <td className="px-4 py-3 whitespace-nowrap">
                <CategoryBadge category={e.category} />
              </td>
              <td className="px-4 py-3 max-w-[180px] truncate">{e.description}</td>
              <td className="px-4 py-3 text-right font-mono text-red-600 dark:text-red-400">
                {formatPeso(e.amount)}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-gray-500 dark:text-gray-400">
                {getPaymentMethodLabel(e.payment_method)}
              </td>
              <td className="px-4 py-3 text-gray-500 dark:text-gray-400 max-w-[120px] truncate">
                {e.notes || '—'}
              </td>
              <td className="px-4 py-3 text-center">
                <div className="flex gap-2 justify-center items-center">
                  <Button
                    variant="ghost"
                    className="text-xs py-1 px-2"
                    onClick={() => onEdit(e)}
                  >
                    Edit
                  </Button>
                  {confirmArchiveId === e.id ? (
                    <span className="flex items-center gap-1">
                      <span className="text-xs text-gray-500 dark:text-gray-400 whitespace-nowrap">Archive?</span>
                      <button
                        onClick={() => { archive.mutate(e.id); setConfirmArchiveId(null) }}
                        className="text-xs text-red-500 hover:text-red-600 font-medium transition-colors"
                        disabled={archive.isPending}
                      >
                        Yes
                      </button>
                      <span className="text-gray-300 dark:text-gray-600">/</span>
                      <button
                        onClick={() => setConfirmArchiveId(null)}
                        className="text-xs text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors"
                      >
                        No
                      </button>
                    </span>
                  ) : (
                    <button
                      onClick={() => setConfirmArchiveId(e.id)}
                      className="text-gray-400 hover:text-red-500 dark:hover:text-red-400 text-xs transition-colors"
                      disabled={archive.isPending}
                    >
                      Archive
                    </button>
                  )}
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
```

---

### Task 8: CategoryTiles Component

**Files:**
- Create: `src/components/expenses/CategoryTiles.jsx`

- [ ] **Step 1: Create `src/components/expenses/CategoryTiles.jsx`**

```jsx
import { formatPeso } from '../../utils/money.js'
import { CATEGORIES } from '../../utils/expenses.js'
import {
  UtilitiesIcon, FoodIcon, TransportIcon, RentIcon,
  HealthcareIcon, ShoppingIcon, EntertainmentIcon,
  SubscriptionsIcon, EducationIcon, PersonalCareIcon,
  InsuranceIcon, OthersIcon,
} from '../ui/icons.jsx'

const ICONS = {
  utilities: UtilitiesIcon,
  food: FoodIcon,
  transportation: TransportIcon,
  rent: RentIcon,
  healthcare: HealthcareIcon,
  shopping: ShoppingIcon,
  entertainment: EntertainmentIcon,
  subscriptions: SubscriptionsIcon,
  education: EducationIcon,
  personal_care: PersonalCareIcon,
  insurance: InsuranceIcon,
  others: OthersIcon,
}

export default function CategoryTiles({ totals, activeCategory, onSelect }) {
  return (
    <div className="grid grid-cols-3 sm:grid-cols-4 lg:grid-cols-6 gap-2 mb-6">
      {CATEGORIES.map((cat) => {
        const Icon = ICONS[cat.value]
        const amount = totals[cat.value] ?? 0
        const isActive = activeCategory === cat.value
        const hasAmount = amount > 0

        return (
          <button
            key={cat.value}
            onClick={() => onSelect(isActive ? null : cat.value)}
            className={`flex flex-col items-center gap-1.5 p-3 rounded-2xl border transition-all text-center ${
              isActive
                ? 'border-2 shadow-sm'
                : 'border-gray-200 dark:border-gray-700 hover:border-gray-300 dark:hover:border-gray-600'
            } ${hasAmount ? 'bg-white dark:bg-gray-900' : 'bg-gray-50 dark:bg-gray-900/50 opacity-60'}`}
            style={isActive ? { borderColor: cat.color } : {}}
          >
            <div
              className="w-8 h-8 rounded-full flex items-center justify-center"
              style={{ backgroundColor: cat.color + '22', color: cat.color }}
            >
              <Icon className="w-4 h-4" />
            </div>
            <p className="text-xs font-medium text-gray-700 dark:text-gray-200 leading-tight">
              {cat.label}
            </p>
            <p
              className="text-xs font-mono font-semibold"
              style={{ color: hasAmount ? cat.color : '#9CA3AF' }}
            >
              {formatPeso(amount)}
            </p>
          </button>
        )
      })}
    </div>
  )
}
```

---

### Task 9: ExpenseSummary Component

**Files:**
- Create: `src/components/expenses/ExpenseSummary.jsx`

- [ ] **Step 1: Create `src/components/expenses/ExpenseSummary.jsx`**

```jsx
import { formatPeso } from '../../utils/money.js'
import { PAYMENT_METHODS } from '../../utils/expenses.js'

export default function ExpenseSummary({ total, paymentTotals, monthLabel }) {
  return (
    <div className="sticky top-[57px] z-30 bg-white/95 dark:bg-gray-900/95 backdrop-blur border-b border-gray-200 dark:border-gray-700 px-4 py-4">
      <div className="max-w-6xl mx-auto">
        <p className="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-1">
          {monthLabel} Total
        </p>
        <p className="text-3xl font-black font-mono text-red-600 dark:text-red-400 mb-3">
          {formatPeso(total)}
        </p>
        <div className="flex flex-wrap gap-4">
          {PAYMENT_METHODS.filter((m) => (paymentTotals[m.value] ?? 0) > 0).map((m) => (
            <div key={m.value} className="flex flex-col">
              <p className="text-xs text-gray-400 uppercase tracking-wide">{m.label}</p>
              <p className="text-sm font-mono font-semibold text-gray-700 dark:text-gray-200">
                {formatPeso(paymentTotals[m.value])}
              </p>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
```

---

### Task 10: ExpensesPage

**Files:**
- Create: `src/pages/ExpensesPage.jsx`

- [ ] **Step 1: Create `src/pages/ExpensesPage.jsx`**

```jsx
import { useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { useExpenses } from '../hooks/useExpenses.js'
import {
  filterByMonth,
  groupByCategory,
  groupByPaymentMethod,
  CATEGORIES,
  PAYMENT_METHODS,
} from '../utils/expenses.js'
import { addMoney } from '../utils/money.js'
import Navbar from '../components/layout/Navbar.jsx'
import ExpenseSummary from '../components/expenses/ExpenseSummary.jsx'
import CategoryTiles from '../components/expenses/CategoryTiles.jsx'
import ExpenseTable from '../components/expenses/ExpenseTable.jsx'
import ExpenseForm from '../components/expenses/ExpenseForm.jsx'
import { useToast, ToastContainer } from '../components/ui/Toast.jsx'
import Button from '../components/ui/Button.jsx'
import { ReturnIcon } from '../components/ui/icons.jsx'

const MONTH_NAMES = [
  'January','February','March','April','May','June',
  'July','August','September','October','November','December',
]

export default function ExpensesPage() {
  const navigate = useNavigate()
  const { data: allExpenses = [], isLoading } = useExpenses()
  const { toasts, toast } = useToast()

  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [month, setMonth] = useState(now.getMonth() + 1) // 1-based
  const [activeCategory, setActiveCategory] = useState(null)
  const [activePayment, setActivePayment] = useState(null)
  const [showForm, setShowForm] = useState(false)
  const [editingExpense, setEditingExpense] = useState(null)

  function prevMonth() {
    if (month === 1) { setMonth(12); setYear((y) => y - 1) }
    else setMonth((m) => m - 1)
  }
  function nextMonth() {
    const isCurrentMonth = year === now.getFullYear() && month === now.getMonth() + 1
    if (isCurrentMonth) return
    if (month === 12) { setMonth(1); setYear((y) => y + 1) }
    else setMonth((m) => m + 1)
  }

  const monthExpenses = useMemo(
    () => filterByMonth(allExpenses, year, month),
    [allExpenses, year, month]
  )

  const categoryTotals = useMemo(() => groupByCategory(monthExpenses), [monthExpenses])
  const paymentTotals = useMemo(() => groupByPaymentMethod(monthExpenses), [monthExpenses])
  const monthTotal = useMemo(
    () => monthExpenses.reduce((sum, e) => addMoney(sum, e.amount), 0),
    [monthExpenses]
  )

  const filteredExpenses = useMemo(() => {
    let list = monthExpenses
    if (activeCategory) list = list.filter((e) => e.category === activeCategory)
    if (activePayment) list = list.filter((e) => e.payment_method === activePayment)
    return list
  }, [monthExpenses, activeCategory, activePayment])

  const monthLabel = `${MONTH_NAMES[month - 1]} ${year}`
  const isCurrentMonth = year === now.getFullYear() && month === now.getMonth() + 1

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      <Navbar />
      <ExpenseSummary
        total={monthTotal}
        paymentTotals={paymentTotals}
        monthLabel={monthLabel}
      />

      <main className="max-w-6xl mx-auto p-6">
        {/* Back + Add */}
        <div className="flex items-center justify-between mb-6">
          <button
            onClick={() => navigate('/')}
            className="flex items-center gap-1.5 text-xs text-gray-600 dark:text-gray-300 border border-gray-300 dark:border-gray-600 px-3 py-2 rounded-xl hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
          >
            <ReturnIcon className="w-3.5 h-3.5" />
            Back to Dashboard
          </button>
          <Button onClick={() => setShowForm(true)}>+ Add Expense</Button>
        </div>

        {/* Month navigator */}
        <div className="flex items-center gap-3 mb-6">
          <button
            onClick={prevMonth}
            className="text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white transition-colors px-2 py-1 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800"
          >
            ‹
          </button>
          <span className="text-sm font-semibold text-gray-900 dark:text-white w-36 text-center">
            {monthLabel}
          </span>
          <button
            onClick={nextMonth}
            disabled={isCurrentMonth}
            className="text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white transition-colors px-2 py-1 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 disabled:opacity-30 disabled:cursor-not-allowed"
          >
            ›
          </button>
        </div>

        {/* Category tiles */}
        <CategoryTiles
          totals={categoryTotals}
          activeCategory={activeCategory}
          onSelect={setActiveCategory}
        />

        {/* Payment method filter pills */}
        <div className="flex flex-wrap gap-2 mb-5">
          <button
            onClick={() => setActivePayment(null)}
            className={`text-xs px-3 py-1.5 rounded-full border transition-colors ${
              !activePayment
                ? 'bg-[#9FE870]/20 border-[#9FE870] text-[#2D6A4F] dark:text-[#9FE870] font-semibold'
                : 'border-gray-300 dark:border-gray-600 text-gray-600 dark:text-gray-400 hover:border-gray-400'
            }`}
          >
            All Methods
          </button>
          {PAYMENT_METHODS.map((m) => (
            <button
              key={m.value}
              onClick={() => setActivePayment(activePayment === m.value ? null : m.value)}
              className={`text-xs px-3 py-1.5 rounded-full border transition-colors ${
                activePayment === m.value
                  ? 'bg-[#9FE870]/20 border-[#9FE870] text-[#2D6A4F] dark:text-[#9FE870] font-semibold'
                  : 'border-gray-300 dark:border-gray-600 text-gray-600 dark:text-gray-400 hover:border-gray-400'
              }`}
            >
              {m.label}
            </button>
          ))}
        </div>

        {/* Table */}
        {isLoading ? (
          <p className="text-gray-500 text-center py-10">Loading expenses…</p>
        ) : (
          <ExpenseTable
            expenses={filteredExpenses}
            onEdit={(e) => setEditingExpense(e)}
          />
        )}
      </main>

      {showForm && (
        <ExpenseForm
          onClose={() => setShowForm(false)}
          onSuccess={() => toast('Expense added!', 'success')}
        />
      )}

      {editingExpense && (
        <ExpenseForm
          expense={editingExpense}
          onClose={() => setEditingExpense(null)}
          onSuccess={() => { toast('Expense updated!', 'success'); setEditingExpense(null) }}
        />
      )}

      <ToastContainer toasts={toasts} />
    </div>
  )
}
```

---

### Task 11: Dashboard Section

**Files:**
- Modify: `src/pages/DashboardPage.jsx`

- [ ] **Step 1: Add imports at the top of `DashboardPage.jsx` (after existing imports)**

Add these lines to the existing imports block:

```jsx
import { useNavigate } from 'react-router-dom'
import { useExpenses } from '../hooks/useExpenses.js'
import { filterByMonth } from '../utils/expenses.js'
import { addMoney, formatPeso } from '../utils/money.js'
import ExpenseForm from '../components/expenses/ExpenseForm.jsx'
```

- [ ] **Step 2: Add state and data inside `DashboardPage` function body, after the existing borrower state lines**

```jsx
const navigate = useNavigate()
const { data: allExpenses = [] } = useExpenses()
const [showAddExpense, setShowAddExpense] = useState(false)

const now = new Date()
const thisMonthExpenses = filterByMonth(allExpenses, now.getFullYear(), now.getMonth() + 1)
const thisMonthTotal = thisMonthExpenses.reduce((sum, e) => addMoney(sum, e.amount), 0)
const MONTH_NAME = now.toLocaleString('en-PH', { month: 'long' })
```

- [ ] **Step 3: Add the "My Expenses" section inside `<main>`, after the Borrowers section closing `</div>`**

```jsx
{/* Expenses section */}
<div className="mt-10">
  <div className="flex items-center justify-between mb-4">
    <div>
      <h1 className="text-2xl font-bold text-gray-900 dark:text-white">My Expenses</h1>
      <p className="text-gray-500 dark:text-gray-500 text-sm mt-0.5">
        <span className="font-mono">{formatPeso(thisMonthTotal)}</span> this {MONTH_NAME}
      </p>
    </div>
    <div className="flex gap-2">
      <Button variant="ghost" onClick={() => navigate('/expenses')}>View All</Button>
      <Button onClick={() => setShowAddExpense(true)}>+ Add Expense</Button>
    </div>
  </div>
</div>
```

- [ ] **Step 4: Add `ExpenseForm` modal at the bottom of the return, before `<ToastContainer />`**

```jsx
{showAddExpense && (
  <ExpenseForm
    onClose={() => setShowAddExpense(false)}
    onSuccess={() => toast('Expense added!', 'success')}
  />
)}
```

---

### Task 12: Navbar Link + App Route

**Files:**
- Modify: `src/components/layout/Navbar.jsx`
- Modify: `src/App.jsx`

- [ ] **Step 1: Add `ExpensesIcon` import in `Navbar.jsx`**

Change the icons import line from:
```jsx
import { SunIcon, MoonIcon, OwlIcon } from '../ui/icons.jsx'
```
To:
```jsx
import { SunIcon, MoonIcon, OwlIcon, ExpensesIcon } from '../ui/icons.jsx'
```

- [ ] **Step 2: Add the Expenses nav link in `Navbar.jsx`, after the "Borrowers" button block (before the dark mode toggle button)**

```jsx
{/* Expenses link */}
{user && (
  <button
    onClick={() => navigate('/expenses')}
    className={`relative text-sm px-3 py-1.5 rounded-lg transition-colors ${
      location.pathname === '/expenses'
        ? 'bg-[#9FE870]/20 text-[#2D6A4F] dark:text-[#9FE870] font-semibold'
        : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white hover:bg-gray-100 dark:hover:bg-gray-700'
    }`}
  >
    Expenses
  </button>
)}
```

- [ ] **Step 3: Add `ExpensesPage` import in `App.jsx`**

Add after the last page import:
```jsx
import ExpensesPage from './pages/ExpensesPage.jsx'
```

- [ ] **Step 4: Add the `/expenses` route in `App.jsx`, inside `<Routes>`, after the `/shared-borrowers` route**

```jsx
<Route
  path="/expenses"
  element={
    <ProtectedRoute>
      <ExpensesPage />
    </ProtectedRoute>
  }
/>
```

---

### Task 13: Manual Testing Checklist

- [ ] Run dev server: `npm run dev`
- [ ] Open `http://localhost:5173` and log in
- [ ] Confirm "Expenses" nav link appears
- [ ] Confirm "My Expenses" section appears on dashboard
- [ ] Click "+ Add Expense" — form opens with all 6 fields
- [ ] Add an expense (e.g., Utilities / Meralco bill / ₱2,400 / Cash) — confirm toast and it appears in table on `/expenses`
- [ ] Confirm amount shows in the sticky summary header
- [ ] Confirm the correct category tile highlights with the amount
- [ ] Click a category tile — table filters to that category only; click again to deselect
- [ ] Click a payment method pill — table filters; click "All Methods" to reset
- [ ] Navigate months with ‹ › arrows; confirm next month is disabled when on current month
- [ ] Click Edit on a row — form opens pre-filled; save change — row updates
- [ ] Archive a row — confirm/no prompt appears; confirm Yes removes it from table
- [ ] Toggle dark mode — all new components render correctly
- [ ] Run tests: `npx vitest run src/utils/expenses.test.js` — all pass
