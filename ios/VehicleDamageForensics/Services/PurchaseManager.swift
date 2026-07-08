// PurchaseManager.swift
// Vehicle Damage Investigation Assistant
// StoreKit 2 purchase/entitlement manager for the app's monetization model.
//
// NOTE(AI Developer), added 2026-07 per Sean's explicit business decision:
// this app serves two very different audiences with two different natural
// price points --
//   1. A one-time consumer (fender bender, overnight hit-and-run) who will
//      use the app once or twice ever -> pays PER CASE (consumable IAP).
//   2. An insurance adjuster / body-shop pro running many cases as part of
//      their job -> pays a SUBSCRIPTION for unlimited case access.
// Per Sean's confirmation: v1 is LOCAL-ONLY (no backend, no cross-device
// sync of purchase state beyond what Apple's own StoreKit APIs give us for
// free). This deliberately keeps the architecture simple:
//   - Subscription status is never persisted by us at all -- it's derived
//     live from `Transaction.currentEntitlements` every time we need it,
//     which is exactly what Apple's APIs are for and handles renewal/
//     expiration/family sharing/refunds correctly with zero custom code.
//   - Consumable "case credit" balance IS something we must track
//     ourselves -- Apple does not remember "this consumable is unused" the
//     way it does for subscriptions/non-consumables, so once a consumable
//     transaction is delivered, tracking its unspent balance is entirely
//     our app's responsibility. Stored in UserDefaults for v1 per "local
//     only" -- see `CaseCreditsStore` below for the explicit trade-off
//     this implies (credits are lost on uninstall/device change since
//     there is no backend or iCloud sync yet; flagged as a clear v2
//     candidate, not silently swept under the rug).
//
// IMPORTANT for Sean: the actual Product IDs below (`ProductID` enum) must
// be created to match EXACTLY in App Store Connect (Features > In-App
// Purchases / Subscriptions) before this will load real products on
// device. See the setup notes shared alongside this change for the exact
// steps + suggested pricing.

import Foundation
import StoreKit

// MARK: - Purchase Manager

@MainActor
final class PurchaseManager: NSObject, ObservableObject {

    // MARK: Singleton

    static let shared = PurchaseManager()

    // MARK: Product Identifiers

    /// NOTE(AI Developer): Centralized here (rather than scattered string
    /// literals) so App Store Connect setup and in-app references can never
    /// drift out of sync -- same "single source of truth" principle already
    /// used elsewhere in this codebase (e.g. `PhotoType.requiredCaptureProtocol`).
    enum ProductID {
        /// One-time unlock for a single case's full report + PDF export.
        static let unlockSingle = "com.spearitnow.vehicledamageforensics.unlock.single"
        /// One-time unlock bundle: 5 case credits at a discount vs. buying
        /// singly -- aimed at the "occasional user" (small body shop,
        /// independent adjuster) not yet ready to commit to a subscription.
        static let unlockFive = "com.spearitnow.vehicledamageforensics.unlock.five"
        /// Unlimited case unlocks, billed monthly. Aimed at insurance
        /// adjusters / professionals running many cases.
        static let proMonthly = "com.spearitnow.vehicledamageforensics.pro.monthly"
        /// Unlimited case unlocks, billed annually (discounted vs. monthly
        /// x12 -- standard subscription-conversion lever).
        static let proAnnual = "com.spearitnow.vehicledamageforensics.pro.annual"

        static let consumables: Set<String> = [unlockSingle, unlockFive]
        static let subscriptions: Set<String> = [proMonthly, proAnnual]
        static let all: Set<String> = consumables.union(subscriptions)
    }

    // MARK: Published State

    @Published private(set) var products: [Product] = []
    @Published private(set) var isProSubscriber: Bool = false
    @Published private(set) var caseCredits: Int
    @Published private(set) var isLoadingProducts: Bool = false
    @Published var isPurchasing: Bool = false
    @Published var lastError: String?

    // MARK: Private

    private let creditsStore: CaseCreditsStore
    private var transactionListenerTask: Task<Void, Never>?
    /// Guards against double-granting credits/entitlements when the same
    /// transaction is delivered both as `product.purchase()`'s direct
    /// result AND via the `Transaction.updates` async stream -- a
    /// well-documented StoreKit 2 behavior (both paths can see the same
    /// unfinished transaction). Every grant goes through `process(_:)`,
    /// which checks this set before applying anything.
    private var processedTransactionIDs: Set<UInt64> = []

    // MARK: Init

    private init(creditsStore: CaseCreditsStore = CaseCreditsStore()) {
        self.creditsStore = creditsStore
        self.caseCredits = creditsStore.load()
        super.init()
        transactionListenerTask = listenForTransactions()
        Task { await refreshEntitlements() }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: Public API — Loading

    /// Fetches product metadata (localized price/title/description) from
    /// the App Store. Safe to call repeatedly (e.g. every time the paywall
    /// is presented) -- StoreKit caches internally.
    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: ProductID.all)
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            lastError = "Could not load store products: \(error.localizedDescription)"
        }
    }

    /// Re-derives subscription status from Apple's own entitlement records.
    /// NOTE(AI Developer): Deliberately never cached/persisted by us --
    /// `Transaction.currentEntitlements` already reflects renewals,
    /// expirations, refunds, and Family Sharing correctly on-device, which
    /// is exactly the "local only, no backend" simplicity Sean asked for.
    func refreshEntitlements() async {
        var subscribed = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if ProductID.subscriptions.contains(transaction.productID),
               transaction.revocationDate == nil {
                subscribed = true
            }
        }
        isProSubscriber = subscribed
    }

    // MARK: Public API — Purchasing

    /// Initiates a purchase for the given product. Returns true only once
    /// the transaction has been verified and applied (credits granted /
    /// subscription entitlement refreshed).
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "Your purchase could not be verified. Please try again or contact support if you were charged."
                    return false
                }
                await process(transaction)
                return true
            case .userCancelled:
                return false
            case .pending:
                lastError = "Purchase is pending approval (e.g. Ask to Buy / parental approval). It will unlock automatically once approved."
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Re-syncs purchase history from the App Store.
    /// NOTE(AI Developer): This restores SUBSCRIPTIONS correctly (Apple
    /// tracks those as entitlements). It does NOT and CANNOT restore
    /// unused CONSUMABLE credits -- Apple does not track "this consumable
    /// was never spent" at all; that bookkeeping is entirely our app's
    /// responsibility (`CaseCreditsStore`). This is a real, user-visible
    /// limitation of the "local only" v1 design: a user who buys a 5-pack,
    /// uses 2, then deletes/reinstalls the app (or moves to a new phone)
    /// will NOT get their remaining 3 credits back via "Restore
    /// Purchases" -- there is nowhere for the count to be restored FROM.
    /// Flagging this explicitly rather than letting it be a silent gap;
    /// the fix (if/when Sean wants it) is a real backend or CloudKit/iCloud
    /// key-value sync of the credit balance, which is out of scope for the
    /// "local only" v1 Sean asked for.
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: Public API — Case unlock consumption

    /// True when the user has unlimited access via an active subscription.
    /// Cases don't need individual credits consumed while this is true.
    var hasUnlimitedAccess: Bool { isProSubscriber }

    /// Attempts to spend one case credit. Returns true if a credit was
    /// available and consumed (caller is responsible for then marking the
    /// specific case as unlocked and persisting that). Returns false (and
    /// consumes nothing) if the user is already an unlimited subscriber
    /// (they never need credits) or has no credits remaining.
    @discardableResult
    func consumeCreditForUnlock() -> Bool {
        guard !isProSubscriber else { return false }
        guard caseCredits > 0 else { return false }
        caseCredits -= 1
        creditsStore.save(caseCredits)
        return true
    }

    // MARK: Transaction handling

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await self?.process(transaction)
            }
        }
    }

    /// Single choke-point for applying a verified transaction's effect
    /// (grant credits / refresh subscription entitlement) and finishing
    /// it. Idempotent via `processedTransactionIDs` so it's safe to call
    /// from both `purchase(_:)`'s direct result AND the background
    /// `Transaction.updates` listener without double-granting.
    private func process(_ transaction: StoreKit.Transaction) async {
        guard !processedTransactionIDs.contains(transaction.id) else {
            await transaction.finish()
            return
        }
        processedTransactionIDs.insert(transaction.id)

        if ProductID.subscriptions.contains(transaction.productID) {
            await refreshEntitlements()
        } else if transaction.productID == ProductID.unlockSingle {
            grantCredits(1)
        } else if transaction.productID == ProductID.unlockFive {
            grantCredits(5)
        }

        await transaction.finish()
    }

    private func grantCredits(_ count: Int) {
        caseCredits += count
        creditsStore.save(caseCredits)
    }
}

// MARK: - Case Credits Store

/// Persists the consumable "case credit" balance.
/// NOTE(AI Developer): UserDefaults-backed for v1 per Sean's explicit
/// "local only" decision (2026-07). See the doc comment on
/// `PurchaseManager.restorePurchases()` for the concrete trade-off this
/// implies (credits don't survive uninstall/device change). A future
/// upgrade path without a full backend would be `NSUbiquitousKeyValueStore`
/// (free iCloud key-value sync tied to the user's Apple ID, no server to
/// run) -- deliberately not done now since it adds its own edge cases
/// (iCloud account changes, conflict resolution) that are out of scope for
/// a "local only" v1.
struct CaseCreditsStore {
    private let key = "com.spearitnow.vehicledamageforensics.caseCredits"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Int {
        defaults.integer(forKey: key)
    }

    func save(_ value: Int) {
        defaults.set(max(0, value), forKey: key)
    }
}
