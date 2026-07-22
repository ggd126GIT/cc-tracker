# Design System — Inspired by Wise

> Source: `design-idea.png` — a Wise-inspired financial product design system.
> Apply this guide to elevate CC Tracker's UI to a professional, trustworthy financial tool.

---

## Philosophy

Wise's design language is built on **trust, clarity, and speed**. Everything is intentional:
- No decorative noise
- Numbers are always legible at a glance
- Actions are obvious
- Green = positive / primary action
- Red = danger / outstanding balance
- Dark = authority / data density

---

## Color Palette

### Primary
| Token | Hex | Usage |
|-------|-----|-------|
| `green-primary` | `#9FE870` | Primary CTA buttons, active nav, success states |
| `green-dark` | `#2D6A4F` | Hover on primary button, progress bars |

### Neutral
| Token | Hex | Usage |
|-------|-----|-------|
| `black` | `#1A1A1A` | Headings, card backgrounds (dark mode base) |
| `gray-900` | `#111827` | Dark mode background |
| `gray-800` | `#1F2937` | Dark mode card surface |
| `gray-100` | `#F3F4F6` | Light mode background |
| `white` | `#FFFFFF` | Card surface (light mode) |

### Semantic
| Token | Hex | Usage |
|-------|-----|-------|
| `red` | `#E03131` | Overdue, outstanding balance, destructive actions |
| `amber` | `#F59F00` | Warnings, partial payment, pending states |
| `emerald` | `#37B24D` | Paid, completed, positive balance |

### Usage Rule
- **Never** use color alone to convey meaning — always pair with a label or icon
- Primary green is for **one action per screen** (the most important CTA)
- Gray tones carry all supporting information

---

## Typography

### Scale
| Level | Size | Weight | Usage |
|-------|------|--------|-------|
| Display / Hero | `text-5xl` (48px) | `font-black` (900) | Page hero stats (total balance) |
| Section Title | `text-2xl` (24px) | `font-bold` (700) | Page headings (Dashboard, Tracker) |
| Card Title | `text-lg` (18px) | `font-semibold` (600) | Card names, borrower names |
| Body | `text-sm` (14px) | `font-normal` (400) | Table rows, descriptions |
| Caption / Label | `text-xs` (12px) | `font-medium` (500) | Column headers, badges, helper text |

### Rules
- Use `font-mono` for **all financial figures** (amounts, balances) — prevents layout shift when numbers change
- Column headers: `uppercase tracking-wide text-xs` — Wise's signature table style
- Never mix more than 2 type weights per card

---

## Buttons

### Primary (Green)
```
bg-[#9FE870] text-black font-semibold rounded-xl px-5 py-2.5
hover:bg-[#8ADF5A] transition-colors
```
- Dark text on light green (accessibility contrast)
- Used for: Add Card, Add Loan, Send Invite, Record Payment

### Ghost / Secondary
```
border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300
rounded-xl px-5 py-2.5 hover:bg-gray-100 dark:hover:bg-gray-800
```
- Used for: Cancel, Back, secondary actions

### Danger
```
bg-red-50 dark:bg-red-900/20 text-red-600 dark:text-red-400
border border-red-200 dark:border-red-800 rounded-xl px-4 py-2
```
- Used for: Revoke, Archive, Delete

### Size
- Default: `px-5 py-2.5 text-sm`
- Small (table actions): `px-3 py-1.5 text-xs`

---

## Cards

### Surface
```
bg-white dark:bg-gray-900
border border-gray-200 dark:border-gray-800
rounded-2xl
shadow-sm hover:shadow-md transition-shadow
```

### Inner spacing
- Card padding: `p-5` or `p-6`
- Between label and value: `mb-0.5`
- Between sections inside card: `gap-4` or `mb-5`

### Key pattern — Stat block
```
<p class="text-xs text-gray-400 uppercase tracking-wide">Total Outstanding</p>
<p class="text-3xl font-black font-mono text-red-500">₱200,377.30</p>
```
- Labels always uppercase, tiny, muted
- Values always large, mono, colored by sentiment

---

## Forms

### Input
```
w-full bg-gray-50 dark:bg-gray-800
border border-gray-300 dark:border-gray-600
rounded-xl px-4 py-2.5 text-sm
focus:outline-none focus:ring-2 focus:ring-[#9FE870] focus:border-transparent
transition-colors
```

### Label
```
block text-xs font-medium text-gray-600 dark:text-gray-400 uppercase tracking-wide mb-1.5
```

### Validation
- Error: `border-red-400 focus:ring-red-400`
- Error message: `text-red-500 text-xs mt-1`

---

## Tables

### Header row
```
bg-gray-50 dark:bg-gray-800/50
text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider
px-4 py-3
```

### Body rows
```
bg-white dark:bg-gray-900
divide-y divide-gray-100 dark:divide-gray-800
hover:bg-gray-50 dark:hover:bg-gray-800/40 transition-colors
px-4 py-3.5
```

### Amount cells — always right-aligned, always monospace
```
text-right font-mono font-medium
```

### Table container
```
rounded-2xl border border-gray-200 dark:border-gray-700 overflow-hidden
```

---

## Badges / Status Pills

```
text-xs font-semibold px-2.5 py-1 rounded-full
```

| Status | Classes |
|--------|---------|
| Paid / Active | `bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400` |
| Unpaid / Pending | `bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400` |
| Overdue / Defaulted | `bg-red-100 text-red-600 dark:bg-red-900/30 dark:text-red-400` |
| Partial | `bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300` |

---

## Spacing Scale

Follow an 8px base grid:

| Token | Value | Usage |
|-------|-------|-------|
| `space-1` | 4px | Icon gaps, tight padding |
| `space-2` | 8px | Label-to-input, inline gaps |
| `space-3` | 12px | Button padding (vertical) |
| `space-4` | 16px | Card inner padding |
| `space-5` | 20px | Card padding (preferred) |
| `space-6` | 24px | Section gaps |
| `space-8` | 32px | Between major sections |
| `space-12` | 48px | Page-level vertical rhythm |

---

## Border Radius Scale

| Token | Value | Usage |
|-------|-------|-------|
| `rounded` | 4px | Badges, small pills |
| `rounded-lg` | 8px | Inputs, small buttons |
| `rounded-xl` | 12px | Buttons, form fields |
| `rounded-2xl` | 16px | Cards, modals, table containers |
| `rounded-full` | 9999px | Avatar initials, status dots |

---

## Depth / Elevation

| Level | Classes | Usage |
|-------|---------|-------|
| 0 — Flat | (none) | Table rows, list items |
| 1 — Raised | `shadow-sm` | Cards at rest |
| 2 — Elevated | `shadow-md` | Cards on hover |
| 3 — Floating | `shadow-xl` | Modals, dropdowns |
| 4 — Overlay | `shadow-2xl` + backdrop | Full-screen modals |

---

## Navigation (Navbar)

- Background: `bg-white/90 dark:bg-gray-900/90 backdrop-blur`
- Height: `py-3 px-6`
- Logo: brand color pill (`bg-[#9FE870] text-black font-black`)
- Active link: `bg-[#9FE870]/20 text-[#2D6A4F] dark:text-[#9FE870]` with `rounded-lg`
- Inactive link: `text-gray-500 hover:text-gray-900 dark:hover:text-white`

---

## Progress Bars

```
h-1.5 bg-gray-100 dark:bg-gray-800 rounded-full overflow-hidden
```
Fill:
- `< 50% paid` → `bg-red-400`
- `50–80% paid` → `bg-amber-400`
- `> 80% paid` → `bg-emerald-500`
- `100%` → `bg-emerald-600`

---

## Avatar / Initials

```
w-11 h-11 rounded-full flex items-center justify-center
text-white font-bold text-sm
```
Color assigned deterministically by name hash (existing pattern — keep it).

---

## Dark Mode

- Never use pure black (`#000`) for backgrounds — use `gray-950` (`#030712`) or `gray-900`
- Never use pure white (`#FFF`) for text in dark mode — use `gray-100` or `gray-50`
- All semantic colors (green, red, amber) must have dark-mode variants at reduced opacity (`/30`) for backgrounds and higher brightness for text

---

## Key UI Improvements to Apply

Based on the design reference, these are the highest-impact changes to bring CC Tracker to the Wise aesthetic:

1. **Replace the blue primary color** with Wise green (`#9FE870`) across all primary buttons and active states
2. **Hero stat numbers** on the Dashboard and TrackerPage should be large (`text-4xl font-black font-mono`) not just `font-semibold`
3. **Table column headers** → add `uppercase tracking-wider` if not already present
4. **Card tiles** → increase radius from `rounded-xl` to `rounded-2xl`, ensure `shadow-sm hover:shadow-md`
5. **Input focus rings** → switch to green (`focus:ring-[#9FE870]`) from blue
6. **Progress bar coloring** → make it dynamic (red/amber/green) based on repayment percentage
7. **Navbar active state** → replace blue pill with green tint (`bg-green-100 dark:bg-green-900/20 text-green-700`)
8. **Amount cells** → ensure all monetary values use `font-mono` throughout every table
9. **Section headers** → upgrade to `uppercase tracking-wide text-xs text-gray-400` label above bold title pattern
10. **Modal max-width** → `max-w-lg` instead of `max-w-md` for breathing room
