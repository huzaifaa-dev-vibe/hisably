# Hisably — Architecture & Decisions

This document records the major architectural decisions, the reasoning behind
them, and the trade-offs accepted. It is updated with every phase.

## 1. Layers

```
presentation (features/)  →  data (repositories, providers)  →  core (money, db, theme)
```

* **core/** — pure Dart + schema. `money.dart`, `currency.dart` and the
  Drift table definitions have no Flutter widget dependencies beyond
  `foundation.dart` (immutability annotations) and can be unit-tested
  without a widget tree.
* **data/** — `AccountRepository` and `TransactionRepository` own **every**
  write. Validation (positive amounts, same-currency transfers, category
  direction, fee bounds) lives in exactly one place. UI code never issues
  SQL.
* **features/** — one folder per screen. Screens watch Riverpod
  `StreamProvider`s backed by Drift `watch()` queries; there is no manual
  refresh anywhere.

**Rule:** dependencies point inward. `core` knows nothing about `data`;
`data` knows nothing about `features`.

## 2. Money representation

**Decision:** integer minor units (`int`) everywhere; `Money` wraps the value
with its `Currency`. **No `double` is ever an authoritative amount.**

* `Money.fromMinor` rejects negatives — the constructor for *user-entered*
  amounts.
* `Money.fromSigned` allows negatives — the constructor for *derived* values
  (balances, totals) which can be negative (overdrawn cash after exchange
  fees). Formatting renders `-Rs 25.00` via `AmountFormat.money`.
* Overflow above `kMaxMinorUnits` (≈10¹³) throws instead of wrapping.
* Parsing (`Money.parseRaw`) is pure string/integer math — `int.tryParse`
  on digit substrings, no `double.parse` anywhere in the input path.
* Currency precision is explicit: `CurrencyRegistry` pins ISO 4217 digits
  (JPY=0, USD=2, BHD=3). The keypad caps fraction input to the active
  currency's digits; 0-decimal currencies disable the decimal key.

**Trade-off:** `Money.operator -` clamps at zero so it can never produce a
negative from non-negative inputs; true signed differences use
`deltaMinor()`. This keeps the type safe for ledger inputs at the cost of a
slightly surprising `a - b` for UI comparisons — documented on the class.

## 3. Ledger model

**Decision:** one row per financial event in a single `transactions` table;
`type ∈ {income, expense, transfer, exchange}`.

| type | debit | credit | counts as P&L |
|------|-------|--------|----------------|
| income | — | amount | income |
| expense | amount | — | expense |
| transfer | amount | to_amount (== amount) | never |
| exchange | amount + fee | to_amount (other currency) | never |

Consequences:

* "An expense is not a transfer" is enforced by the schema: a transfer row
  cannot have a category and is excluded from P&L aggregates by construction.
* Exchange rows preserve **both** original amounts verbatim. The effective
  rate is always derived (`to_amount_minor / amount_minor`) with integer long
  division at display time. No rate is ever stored, so there is nothing to
  drift or round-trip incorrectly.
* Every write is wrapped in `_db.transaction(...)` — a half-applied financial
  event is impossible.

**Trade-off:** denormalised `to_account_id` instead of double-entry
bookkeeping. Double-entry was rejected as overkill for a personal-finance UX;
the single-row-per-event model keeps the Quick Add write path to exactly one
INSERT while remaining fully auditable.

## 4. Balances are derived, never stored

**Decision:** no balance column. `balance = opening_balance + Σ(derived
deltas of ledger rows)`, computed in SQL inside `AccountRepository`.

* Reproducible by definition — any balance shown can be recomputed from
  rows (`test/data/balance_test.dart` does exactly this over real SQLite).
* Streams update automatically when rows change (delete = undo works for
  free).
* **Trade-off:** the per-account correlated subquery is O(rows-per-account)
  per refresh — irrelevant at personal-finance scale (thousands of rows).
  If profiling ever says otherwise, the documented upgrade path is a
  transactional balance cache in `app_meta` (the table is reserved for
  exactly this), invalidated inside the same transaction as writes.

## 5. Persistence & recovery

* Drift over `sqlite3_flutter_libs`, WAL journal mode, foreign keys ON.
* The DB opens **before the first frame** (`main()` awaits
  `AppDatabase.open()`); if that fails the app shows an error screen rather
  than a white flash — user data is untouched on disk.
* Schema v2 with a documented forward-only `onUpgrade` switch. Migrations
  are additive: v1→v2 creates `budgets`, `khata_people`, `khata_entries`
  (no rewrites of existing tables, no data loss path).
* System categories are seeded inside a transaction on first create, so a
  crashed first launch cannot half-seed.
* Restart recovery is proven by `persistence_test.dart` (close file-backed
  DB → reopen → identical balances).

## 6. Quick Add (signature flow)

Two-step state machine (`QuickAddStep.amount → details`) in
`QuickAddController` (Riverpod `Notifier`):

* **Amount step (redesigned in v0.90.12)** — top bar (close + centered
  title + currency selector), an explicit **In / Out segmented toggle**
  (colour-coded, selection alone does not advance), the large amount with
  the currency symbol inline and a soft caret, a round 3×4 keypad, and one
  bottom button that always names the next action ("Continue · Out Rs 500"
  / "Pick In or Out to continue"). The system keyboard is never summoned;
  the note `TextField` exists only on the details step.
* Direction selection and advancing are separate controller methods
  (`selectDirection` stays on the amount step; `proceedToDetails` advances),
  so the UI can highlight the toggle without jumping screens.
* Input model: the keypad mutates a raw string (`"12"`, `"12."`, `"12.5"`);
  grouping/formatting is a pure view concern (`AmountFormat.typing`). This
  makes the controller trivially testable and locale changes safe.
* Caps: no leading zeros, fraction length ≤ currency digits, ≤ 12 integer
  digits.
* Duplicate-submission guard: `saving` flag rejects re-entrant `save()`
  calls; `saved` rejects double saves.
* Haptics funnel through `AppHaptics` — the only file allowed to call
  `HapticFeedback` (selection click per key, medium impact on direction
  pick, heavy impact on save success, vibrate on validation failure).
* Success: restrained scaling-check overlay (~720 ms), then the route pops
  returning the new transaction id; the shell shows a 5-second Undo
  snackbar. Undo = `deleteTransaction(id)`; balances re-derive
  automatically.
* The "save immediately vs. show details" preference exists
  (`quickSaveImmediatelyProvider`) for Phase-4 wiring of the settings
  screen.

## 7. UI system

* **Glass material**: `GlassPanel` = translucent gradient fill + hairline
  border + soft shadow; `blurred: true` adds a real `BackdropFilter`.
  Performance contract: at most a handful of *blurred* panels per screen
  (hero card, bottom bar, FAB); list items use `blurred: false` — visually
  consistent, far cheaper on mid-range devices.
* Aurora-style static gradients as backgrounds; no blur behind critical
  text.
* **Theme system (v0.90.12)**: one `AppThemeSpec` per theme holds EVERY
  token — background gradient, aurora blobs, glass fill/border, key fill,
  three text tiers, accent/onAccent, income/expense/warn/transfer — and is
  registered as a `ThemeExtension`. Screens read tokens via `context.spec`;
  semantic colours are per-theme (e.g. the light themes use darkened
  income/expense variants so coloured text stays readable on white glass).
  `AppTheme.fromSpec` gives every text style an EXPLICIT colour — nothing
  relies on inherited defaults, which is the root fix for the "white text
  on white background" bug. Six themes ship: System (follows OS),
  Porcelain, Obsidian (default), Midnight, Forest, Sand. The choice is
  stored in `shared_preferences` (`themeSettingProvider`) and applied by
  `HisablyApp` (`themeMode` handles the System case reactively).
* **Contrast is a tested contract** (`theme_contrast_test.dart`): for every
  shipped spec, textPrimary/textSecondary ≥ 4.5:1 on glassFill,
  textPrimary ≥ 7:1 on bgTop, semantic colours ≥ 3:1 as text, onAccent ≥
  3:1 on accent. A new theme that fails the test does not ship.
* Tabular figures are forced on every amount so digits never jitter
  horizontally.
* Every touchable carries a `Semantics` label; the amount display is a
  live region. Motion uses a single curve/duration vocabulary
  (`AppMotion`).

## 8. Testing strategy

* `test/core/` — money parsing/formatting/overflow, currency precision
  (2/1/0/3-digit), exact rational rate display.
* `test/data/` — repository behaviour over **real in-memory SQLite**:
  derived balances, P&L exclusion for transfers/exchanges, fee handling,
  domain-rule rejections, filters/search, undo, archive, restart recovery.
* Negative-total regression: an exchange fee can push a total below zero;
  the home formatting path is exercised against a `-1`-minor total to prove
  no crash (the original implementation threw here).
* `theme_contrast_test.dart` — WCAG contrast contract per theme (above).
* `budget_test.dart` — upsert on the unique (category, currency) index,
  month-scoped spend derivation, ok/warning/over states.
* `khata_test.dart` — net balance = Σ(gave) − Σ(took) per currency, partial
  repayments as opposite-direction entries, settle-up exactness, delete
  recalculation, archive, validation.
* `reports_export_test.dart` — category breakdown/daily/monthly series and
  the balance-series identity (last point == derived total, exchanges
  contribute −(amount+fee) from the source currency); CSV RFC-4180
  escaping; backup→restore roundtrip with id remapping inside one
  transaction; malformed-payload rejection leaves data untouched.
* Widget tests (`shell_profile_test.dart`) boot the REAL app (in-memory DB
  + mocked prefs): the dock-geometry regression (Quick Add button rect must
  be fully inside the nav dock), theme switching, haptics toggle.
* A widget test caught a real production bug during development:
  `monthlyTotalsProvider(DateTime.now())` created a NEW family provider
  (and a new live SQL stream) on every rebuild because family args compare
  by value — Home re-rendered forever. Fixed by passing a month-truncated
  key; the pattern is documented here so it does not come back.

## 8b. Budgets, khata, reports, export (v0.90.12)

* **Budgets** (`budgets` table, unique per category+currency): a budget is
  ONLY a stored limit. Spent totals are re-derived from expense rows of the
  month (Dart-side aggregation over watched queries), so deleting or
  editing any transaction moves the progress bar instantly. States:
  ok < 80 %, warning ≥ 80 %, over > 100 %.
* **Khata** (`khata_people`, `khata_entries`): entries are immutable facts
  with direction `gave`/`took`; the net balance per person per currency is
  Σ(gave) − Σ(took). Repayments are ordinary opposite-direction entries;
  **settle-up** writes one exact opposite entry (history stays honest — no
  edits of past rows). FK constraints ON; entry deletion re-derives.
* **Reports**: all series are Dart-side aggregations over the existing
  watched repository streams — figures are exactly consistent with the
  ledger by construction, and every series is scoped to ONE currency. The
  30-day balance series derives its opening as `currentTotal − windowDelta`
  and asserts internally that walking forward lands on the current total.
* **Export/backup**: CSV is RFC-4180-escaped; the JSON backup is
  version-stamped and validated before restore; restore remaps category/
  account/person ids (SQLite AUTOINCREMENT never reuses ids) and runs
  inside ONE transaction so a malformed file can never half-destroy data.
  Files land in the app documents dir — no permissions, no network.

## 9. Honest verification log

| Check | Result | Where |
|-------|--------|-------|
| `flutter analyze` | 0 issues | Flutter 3.47.8 / Dart 3.13.7 |
| `flutter test` | 113/113 pass | same toolchain |
| `flutter build apk --debug --target-platform android-arm64` | ✅ built (v0.90.12) | same toolchain |
| Main (release) manifest | **zero permissions** | `android/app/src/main/AndroidManifest.xml` |
| Release APK / device run | not performed in this environment (no emulator) | — |

Not yet implemented (by phase plan): recurring engine, category management
UI, accessibility audit, branding/logo pass.

## 10. Known trade-offs / future work

* `AmountFormat.compact` uses K/L/M (South-Asian) grouping — cosmetic only;
  revisit if the audience expands.
* `TxQueryFilter.limit` defaults to 500 rows for history screens; infinite
  scroll is a Phase-5 concern.
* Recurring transactions: `recurring_rule_id` column reserved in schema v1;
  engine ships in Phase 5 without a migration (column already exists).
* Sync: repositories form the boundary; no cloud code exists or will until
  the local system is stable (per product mandate).
* Report aggregation is Dart-side (not SQL GROUP BY) — the right trade for
  personal data volumes; revisit only if ledgers grow to tens of thousands
  of rows per month.
* Backup restore assumes backup categories/people are ordered by id (they
  are — inserts happen in select order); combined with AUTOINCREMENT this
  yields stable remapping. A future schema could store explicit id maps.
* Khata balances are informational (they do NOT feed account balances) —
  informal debts live outside the tracked accounts until the user records
  a real transaction.
