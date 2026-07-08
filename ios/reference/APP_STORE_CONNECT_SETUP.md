# App Store Connect Setup — Monetization Products

**For**: Sean Pierce
**Date**: 2026-07-08
**Why you need this**: `PurchaseManager.swift` references 4 specific product IDs. Until these
exist in App Store Connect with these **exact** IDs, `Product.products(for:)` will return an
empty array and the paywall will show no purchase options (it will just spin / show nothing to
buy). This is expected and not a bug — it's a signal these products haven't been created yet.

---

## 1. Prerequisites

- You already have an active Apple Developer Program account (confirmed).
- Your app record must exist in App Store Connect with the bundle ID
  `com.spearitnow.vehicledamageforensics`. If you haven't created the app record yet in
  App Store Connect (My Apps → +), do that first — Xcode can also do this automatically the
  first time you archive/upload a build, but it's cleaner to do it manually first so you can set
  up the IAP products before your first TestFlight build.

## 2. Create the two consumable (pay-per-case) products

Go to **App Store Connect → My Apps → [your app] → Monetization → In-App Purchases → +**

### Product 1 — Single case unlock
- **Type**: Consumable
- **Reference Name**: `Unlock Single Case` (internal only, not shown to users)
- **Product ID**: `com.spearitnow.vehicledamageforensics.unlock.single`
  ⚠️ Must match exactly — this is hardcoded in `PurchaseManager.ProductID.unlockSingle`.
- **Price**: suggested **$9.99–$14.99** (Tier 10 or Tier 15) — a one-time fender-bender victim is
  price-insensitive for "get my insurance claim right," but this shouldn't feel like a subscription
  trap. Final call is yours.
- **Display Name** (localized, shown to users): e.g. "Single Case Unlock"
- **Description** (shown to users): e.g. "Unlock the full correlation report — per-factor
  breakdown, investigative recommendations, and a shareable PDF — for one case."
- Add a screenshot for review (App Store Connect requires one for IAP review — a screenshot of
  the paywall or the locked results screen works).

### Product 2 — 5-case bundle
- **Type**: Consumable
- **Reference Name**: `Unlock 5 Cases`
- **Product ID**: `com.spearitnow.vehicledamageforensics.unlock.five`
  ⚠️ Must match `PurchaseManager.ProductID.unlockFive` exactly.
- **Price**: suggested **$39.99–$49.99** (a discount vs. 5x the single price — aimed at small
  body shops / independent adjusters not yet ready to subscribe).
- **Display Name**: e.g. "5-Case Bundle"
- **Description**: e.g. "Unlock 5 case reports — ideal for occasional professional use without a
  subscription."

## 3. Create the subscription group + two subscription products

Subscriptions require a **Subscription Group** first (a group is how Apple lets a user upgrade/
downgrade between plans in the same group without being double-charged).

Go to **App Store Connect → My Apps → [your app] → Monetization → Subscriptions → +** (create
group first if prompted):

- **Subscription Group Name**: e.g. `Pro Access` (internal only)

### Product 3 — Monthly Pro subscription
- **Product ID**: `com.spearitnow.vehicledamageforensics.pro.monthly`
  ⚠️ Must match `PurchaseManager.ProductID.proMonthly` exactly.
- **Subscription Duration**: 1 month
- **Price**: suggested **$29.99/month**
- **Display Name**: e.g. "Pro Monthly"
- **Description**: e.g. "Unlimited case unlocks for insurance adjusters, body shops, and
  investigators. Billed monthly, cancel anytime."

### Product 4 — Annual Pro subscription
- **Product ID**: `com.spearitnow.vehicledamageforensics.pro.annual`
  ⚠️ Must match `PurchaseManager.ProductID.proAnnual` exactly.
- **Subscription Duration**: 1 year
- **Price**: suggested **$299/year** (≈2 months free vs. monthly x12 — standard annual-conversion
  discount).
- **Display Name**: e.g. "Pro Annual"
- **Description**: e.g. "Unlimited case unlocks, billed once a year at a discount vs. monthly."

Both subscription products need:
- Localized display name/description (same as above, or refine as you like).
- A subscription-specific screenshot for review (the paywall screenshot works for both).
- **App Store Review Information** subscription details — length, price, and auto-renewal terms.
  Note: `PaywallView.swift` already displays the required auto-renewal disclosure directly on the
  purchase screen (Apple Guideline 3.1.2), so you're covered on the in-app side; App Store Connect
  just wants the same info recorded for review.

## 4. Sandbox testing (before your first real purchase)

1. **App Store Connect → Users and Access → Sandbox → Testers → +** — create a sandbox test
   Apple ID (use an email you don't otherwise use for your real Apple ID; it can't already be a
   real Apple ID).
2. On your test device: **Settings → App Store → Sandbox Account** (iOS 17+) — sign in with the
   sandbox tester.
3. Run the app from Xcode on that device. Opening `PaywallView` should now show real prices for
   all 4 products (once they've finished propagating — can take a few minutes to a few hours
   after first creating them).
4. Sandbox purchases are free but go through the full StoreKit flow (including the "Confirm Your
   In-App Purchase" sheet) so you can verify the whole flow end-to-end, including "Restore
   Purchases."

## 5. What "Ready to Submit" vs. "Missing Metadata" means

New IAP/subscription products often sit in **"Missing Metadata"** status until you fill in every
required field (screenshot, review notes, localized description in at least your primary
language). They don't need to be "Ready to Submit" to test in sandbox — sandbox works as soon as
the product exists with an ID, even mid-setup. They DO need to be fully approved before your first
production release that uses them ships to the App Store (Apple typically reviews new IAPs
alongside your next app binary submission, not standalone).

## 6. Open items not yet handled (flagging, not blocking)

- **Terms of Use / Privacy Policy**: not yet drafted or published. Apple requires a Privacy Policy
  URL in App Store Connect (App Information) for any app collecting data, and a Terms of Use link
  is required if you have auto-renewing subscriptions (can use Apple's standard EULA if you don't
  want to write your own — App Store Connect → App Information → add the standard Apple EULA URL,
  or link your own).
- **Final pricing**: the numbers above are suggestions carried over from earlier discussion, not
  finalized. Easy to change anytime in App Store Connect before/after launch (existing subscribers
  get a price-increase notification if you raise prices later; consumables can change freely).
