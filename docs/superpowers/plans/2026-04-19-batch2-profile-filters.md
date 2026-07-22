# Batch 2: Profile Page + Transaction Filters — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/profile` page for updating display name and password, and add status + date-range filters to the transaction table in TrackerPage.

**Architecture:** `ProfilePage` is a simple form-only page using Supabase `auth.updateUser()` directly — no new DB table. Transaction filtering is a `useMemo` in `TrackerPage` that derives `filteredTransactions` from the existing loaded array — no new hooks or DB calls.

**Tech Stack:** React, Supabase Auth (`updateUser`), @tanstack/react-query (existing), Tailwind CSS

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `src/pages/ProfilePage.jsx` | Display name + password change form |
| Modify | `src/App.jsx` | Add `/profile` route |
| Modify | `src/components/layout/Navbar.jsx` | Add Profile nav link (desktop + mobile) |
| Modify | `src/pages/TrackerPage.jsx` | Add filter state + filteredTransactions memo + filter bar UI |

---

### Task 1: Create `ProfilePage`

**Files:**
- Create: `src/pages/ProfilePage.jsx`

- [ ] **Step 1: Create the page**

Create `src/pages/ProfilePage.jsx`:

```jsx
import { useState } from 'react'
import { supabase } from '../lib/supabase.js'
import useAppStore from '../store/useAppStore.js'
import Navbar from '../components/layout/Navbar.jsx'
import Button from '../components/ui/Button.jsx'
import { useToast, ToastContainer } from '../components/ui/Toast.jsx'

export default function ProfilePage() {
  const user = useAppStore((s) => s.user)
  const setUser = useAppStore((s) => s.setUser)

  const [displayName, setDisplayName] = useState(user?.user_metadata?.display_name ?? '')
  const [savingName, setSavingName] = useState(false)

  const [newPassword, setNewPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [savingPassword, setSavingPassword] = useState(false)

  const { toasts, toast } = useToast()

  async function handleSaveName(e) {
    e.preventDefault()
    setSavingName(true)
    const { data, error } = await supabase.auth.updateUser({
      data: { display_name: displayName.trim() },
    })
    setSavingName(false)
    if (error) {
      toast(error.message, 'error')
    } else {
      setUser(data.user)
      toast('Display name updated!', 'success')
    }
  }

  async function handleSavePassword(e) {
    e.preventDefault()
    if (newPassword !== confirmPassword) {
      toast('Passwords do not match', 'error')
      return
    }
    if (newPassword.length < 6) {
      toast('Password must be at least 6 characters', 'error')
      return
    }
    setSavingPassword(true)
    const { error } = await supabase.auth.updateUser({ password: newPassword })
    setSavingPassword(false)
    if (error) {
      toast(error.message, 'error')
    } else {
      setNewPassword('')
      setConfirmPassword('')
      toast('Password updated!', 'success')
    }
  }

  const inputClass =
    'bg-gray-50 dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-xl px-4 py-2.5 text-gray-900 dark:text-white text-sm placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-[#9FE870] focus:border-transparent transition-colors w-full'

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      <Navbar />
      <main className="max-w-lg mx-auto p-6">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white mb-1">Profile</h1>
        <p className="text-gray-500 text-sm mb-8">{user?.email}</p>

        {/* Display Name */}
        <section className="bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded-2xl p-6 mb-4">
          <h2 className="text-base font-semibold text-gray-900 dark:text-white mb-4">Display Name</h2>
          <form onSubmit={handleSaveName} className="flex flex-col gap-3">
            <input
              className={inputClass}
              placeholder="Your name"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
            />
            <Button type="submit" disabled={savingName} className="self-start">
              {savingName ? 'Saving…' : 'Save Name'}
            </Button>
          </form>
        </section>

        {/* Change Password */}
        <section className="bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded-2xl p-6">
          <h2 className="text-base font-semibold text-gray-900 dark:text-white mb-4">Change Password</h2>
          <form onSubmit={handleSavePassword} className="flex flex-col gap-3">
            <input
              className={inputClass}
              type="password"
              placeholder="New password"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              autoComplete="new-password"
            />
            <input
              className={inputClass}
              type="password"
              placeholder="Confirm new password"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              autoComplete="new-password"
            />
            <Button type="submit" disabled={savingPassword} className="self-start">
              {savingPassword ? 'Saving…' : 'Update Password'}
            </Button>
          </form>
        </section>
      </main>
      <ToastContainer toasts={toasts} />
    </div>
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add src/pages/ProfilePage.jsx
git commit -m "feat: add ProfilePage with display name and password change"
```

---

### Task 2: Add `/profile` route to `App.jsx`

**Files:**
- Modify: `src/App.jsx`

- [ ] **Step 1: Import ProfilePage**

In `src/App.jsx`, add after the existing page imports:

```js
import ProfilePage from './pages/ProfilePage.jsx'
```

- [ ] **Step 2: Add route**

Inside `<Routes>`, add after the `/expenses` route (before the catch-all `*`):

```jsx
<Route
  path="/profile"
  element={
    <ProtectedRoute>
      <ProfilePage />
    </ProtectedRoute>
  }
/>
```

- [ ] **Step 3: Commit**

```bash
git add src/App.jsx
git commit -m "feat: add /profile route"
```

---

### Task 3: Add Profile link to Navbar

**Files:**
- Modify: `src/components/layout/Navbar.jsx`

- [ ] **Step 1: Add ProfileIcon to icons.jsx**

In `src/components/ui/icons.jsx`, add at the end of the file:

```jsx
export function ProfileIcon({ className = '', ...props }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden="true"
      {...props}
    >
      <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
      <circle cx="12" cy="7" r="4" />
    </svg>
  )
}
```

- [ ] **Step 2: Add Profile to navLinks in Navbar**

In `src/components/layout/Navbar.jsx`, update the import to add `ProfileIcon`:

```js
import { SunIcon, MoonIcon, OwlIcon, ExpensesIcon, HomeIcon, UsersIcon, ShareIcon, ProfileIcon } from '../ui/icons.jsx'
```

Add Profile to the `navLinks` array:

```js
const navLinks = [
  { path: '/', label: 'Dashboard', Icon: HomeIcon, badge: 0 },
  { path: '/shared', label: 'Shared', Icon: ShareIcon, badge: pendingInvites.length },
  { path: '/shared-borrowers', label: 'Borrowers', Icon: UsersIcon, badge: pendingBorrowerInvites.length },
  { path: '/expenses', label: 'Expenses', Icon: ExpensesIcon, badge: 0 },
  { path: '/profile', label: 'Profile', Icon: ProfileIcon, badge: 0 },
]
```

The existing `navLinks.map(...)` loops in both desktop and mobile nav will automatically pick up the new entry.

Also update the desktop email display (around line 49) to show `display_name` when set:

```jsx
{user && (
  <span className="text-gray-500 dark:text-gray-500 text-sm truncate max-w-[200px]">
    {user.user_metadata?.display_name || user.email}
  </span>
)}
```

- [ ] **Step 3: Commit**

```bash
git add src/components/ui/icons.jsx src/components/layout/Navbar.jsx
git commit -m "feat: add Profile link to Navbar and ProfileIcon"
```

---

### Task 4: Add transaction filters to `TrackerPage`

**Files:**
- Modify: `src/pages/TrackerPage.jsx`

- [ ] **Step 1: Add filter state**

In `src/pages/TrackerPage.jsx`, add three new state variables after the existing `useState` declarations (around line 34):

```js
const [statusFilter, setStatusFilter] = useState('all')
const [dateFrom, setDateFrom] = useState('')
const [dateTo, setDateTo] = useState('')
```

- [ ] **Step 2: Add filteredTransactions memo**

After the existing `useMemo` for `selectedIds` and `selectedTotal`, add:

```js
const filteredTransactions = useMemo(() => {
  return transactions.filter((t) => {
    if (statusFilter !== 'all' && t.payment_status !== statusFilter) return false
    if (dateFrom && t.transaction_date < dateFrom) return false
    if (dateTo && t.transaction_date > dateTo) return false
    return true
  })
}, [transactions, statusFilter, dateFrom, dateTo])
```

- [ ] **Step 3: Add filter bar JSX**

In the `activeTab === 'active'` block, add the filter bar after `{!readOnly && (... TransactionForm ...)}` and before the action bar `{!readOnly && transactions.length > 0 && (`:

```jsx
{/* Filter bar */}
<div className="flex flex-wrap items-center gap-3 mt-4 mb-2">
  {/* Status pills */}
  <div className="flex gap-1">
    {['all', 'unpaid', 'partial', 'paid'].map((s) => (
      <button
        key={s}
        onClick={() => setStatusFilter(s)}
        className={`px-3 py-1 rounded-full text-xs font-medium capitalize transition-colors ${
          statusFilter === s
            ? 'bg-[#9FE870]/20 text-[#2D6A4F] dark:text-[#9FE870] font-semibold'
            : 'text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
        }`}
      >
        {s === 'all' ? 'All' : s.charAt(0).toUpperCase() + s.slice(1)}
      </button>
    ))}
  </div>

  {/* Date range */}
  <div className="flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
    <input
      type="date"
      value={dateFrom}
      onChange={(e) => setDateFrom(e.target.value)}
      className="bg-gray-50 dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-lg px-2 py-1 text-xs text-gray-700 dark:text-gray-300 focus:outline-none focus:ring-1 focus:ring-[#9FE870]"
      aria-label="From date"
    />
    <span>—</span>
    <input
      type="date"
      value={dateTo}
      onChange={(e) => setDateTo(e.target.value)}
      className="bg-gray-50 dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-lg px-2 py-1 text-xs text-gray-700 dark:text-gray-300 focus:outline-none focus:ring-1 focus:ring-[#9FE870]"
      aria-label="To date"
    />
    {(dateFrom || dateTo) && (
      <button
        onClick={() => { setDateFrom(''); setDateTo('') }}
        className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 text-xs"
      >
        Clear
      </button>
    )}
  </div>
</div>
```

- [ ] **Step 4: Pass filteredTransactions to TransactionTable**

Find the `<TransactionTable` render in the `activeTab === 'active'` block:

```jsx
<TransactionTable
  transactions={transactions}
```

Change `transactions={transactions}` to:

```jsx
<TransactionTable
  transactions={filteredTransactions}
```

- [ ] **Step 5: Smoke test in browser**

```bash
npm run dev
```

Verify:
1. Filter bar appears above the transaction table in the active tab
2. Status pills filter the list correctly (All / Unpaid / Partial / Paid)
3. Date range filters transactions by `transaction_date`
4. Clear button resets both date inputs
5. History tab is unaffected (no filter bar there)
6. Profile page accessible at `/profile` — display name saves, password update works, toasts appear

- [ ] **Step 6: Commit**

```bash
git add src/pages/TrackerPage.jsx
git commit -m "feat: add status and date range filters to TrackerPage"
```
