# Hisably v0.90.12 — Public Pre-release

**Release type: Released** (development pre-release) · Stability: *not recommended for critical financial recordkeeping*

> **⏭️ v1.0.0 is coming soon.** The next release — the stability milestone — will be available
> shortly and targets every item listed below: correct dashboard/account balances, an overspend
> guard, the Quick Add state fix, History loading states, account editing, and a simpler dashboard.
> Watch the repo for the update.

Hisably is an offline-first, open-source personal finance app for Android: accounts, transfers,
manual currency exchange, monthly budgets, a personal khata, four report chart types, CSV export
and JSON backup/restore — all on a local SQLite ledger, with **zero Android permissions in release
builds** and no network code at all.

This is the **second iteration** of Hisably and the first public release: redesigned Quick Add,
six themes with an enforced WCAG contrast contract, a Profile tab, haptics toggle, budgets, khata,
reports and backup tooling.

## ✨ Highlights

- **Charts & reports** — four chart types painted from the real ledger (category donut with legend, daily in/out bars per month, monthly comparison bars, 30-day balance trend). Always scoped to a single currency — never mixed.
- **Profile tab** — editable display name, theme picker (**6 themes:** System, Porcelain, Obsidian, Midnight, Forest, Sand), haptics toggle, primary-currency preference, data tools.
- **Contrast contract** — every text style carries an explicit colour from the active theme spec; an automated WCAG test enforces legibility for every theme. The "white text on white background" class of bug is structurally impossible now.
- **Fixed Quick Add overlapping the bottom bar** — the dock is a floating glass bar with a Quick Add button fully inside it (verified geometrically by a widget test).
- **Quick Add redesigned** — In/Out toggle on top, currency symbol inline with the amount, round keypad, one bottom button that names the next action.
- **Budgets** — monthly limit per (category, currency); live derived progress with ok / warning / over states.
- **Khata** — people, gave/took entries in any currency, partial repayments, exact settle-up.
- **Export & backup** — RFC-4180 CSV export; validated JSON backup/restore in one transaction with foreign-key remapping.
- **Settings persistence** — theme, haptics, display name and primary currency survive restarts.

## ✅ Verification gate

| Check | Result |
|---|---|
| `flutter analyze` | 0 issues |
| `flutter test` | 113 / 113 passed |
| WCAG contrast contract | enforced by test for all 6 themes |
| Release-manifest permissions | 0 (binary-verified) |
| Secret scan (source + APK) | clean |

## ⚠️ Known Issues & Limitations

**Release status: Development / Pre-release — not recommended for critical financial recordkeeping.**

Several issues remain unresolved and may affect usability, transaction reliability, and financial data accuracy.

### 1. Dashboard and account balance inconsistencies
- The total balance displayed on the dashboard may not match the balance shown on the Accounts page.
- Some account balances may display unexpectedly large negative values.
- Balance calculation and synchronization between different sections require further investigation.

### 2. Negative account balances
- The application currently allows transactions that exceed an account's available balance.
- This can result in negative account balances.
- Account-level spending limits and insufficient-balance validation are not yet enforced.

### 3. Quick Add — persistent success state
- After completing an In/Out transaction, reopening Quick Add may display the previous transaction's success screen.
- Users may need to restart the application to use Quick Add again.
- Transaction state and screen lifecycle management require fixing.

### 4. Transaction history — loading issue
- The History section may remain stuck on an infinite loading screen.
- Transaction records may not load correctly.
- Proper empty, error, and retry states are currently needed.

### 5. Account management limitations
- Existing accounts cannot currently be edited after creation.
- Users can create new accounts, but account modification functionality is missing.

### 6. Dashboard UI redundancy
- The dashboard contains a separate In/Out summary card that duplicates information available in Recent Activity.
- This creates unnecessary visual clutter and will be reconsidered in a future update.

### 🔐 Security & data integrity considerations

No confirmed security vulnerability has been established from the current review. However, the
following areas require verification before a stable release:

- Financial transaction validation
- Account balance integrity
- Protection against duplicate transactions
- Database consistency and recovery
- Secure local data storage and backup handling
- Input validation for monetary values and currency conversions

A dedicated security review has not yet been completed.

### 🧭 Planned improvements (→ v1.0.0)

- Correct dashboard and account balance calculations
- Prevent overspending beyond available account balances by default
- Fix Quick Add state persistence
- Resolve History loading issues
- Introduce account editing
- Simplify the dashboard layout
- Improve transaction validation and error handling
- Strengthen data integrity and application stability

## 📦 About this artifact

`hisably-v0.90.12-debug.apk` — **debug build**, `arm64-v8a` only, Android 7.0+ (minSdk 24).
As a debug build it is `debuggable` and carries the standard debug-only `INTERNET` permission used
by the Flutter tool for hot reload; it also inherits the tooling-layer `DUMP` permission
(signature-level — never granted to sideloaded apps). **Release builds request zero permissions**
and are planned alongside signed release artifacts.

SHA-256 (`hisably-v0.90.12-debug.apk`):

```
b669c4aa21ca7af8b706e7f37657b96a5b0ea2b6d92b3212765a0c6b08fa1130
```

## 💡 Recommendation

This is an early development release intended for testing and feedback. Please report bugs and
unexpected behavior through [GitHub Issues](../../issues).

> **Important:** Do not rely on this version as the sole record of important financial
> transactions. Maintain independent records and backups until the known issues are resolved
> and verified.

---

**Hisably — Know your money. Own your numbers.**
