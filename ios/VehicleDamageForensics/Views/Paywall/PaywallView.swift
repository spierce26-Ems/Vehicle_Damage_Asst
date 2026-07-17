// PaywallView.swift
// Vehicle Damage Investigation Assistant
// Presents the app's monetization options: one-time per-case unlocks
// (for a consumer who will only ever use this once or twice) and a Pro
// subscription (for insurance adjusters / professionals running many
// cases). See `PurchaseManager` for the full architecture rationale.
//
// NOTE(AI Developer), added 2026-07 per Sean's explicit business decision
// (2026-07): "make a scaleable app that consumers can use... to insurance
// claims adjusters who can build a solid case... fee structure should
// reflect that. One time use to a pro using it for multiple cases." This
// sheet is presented from `MatchResultsView` when the user reaches a
// gated section (per-factor breakdown, recommendations, PDF export) on a
// case that isn't yet unlocked.

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var purchases = PurchaseManager.shared

    /// NOTE(AI Developer), added 2026-07 per Sean's request to finish the
    /// three remaining App Store submission blockers ("app icon,
    /// Terms/Privacy Policy, Privacy Manifest"). These point at GitHub
    /// Pages served from the repo-root `docs/` folder (source HTML
    /// committed alongside this change at `docs/privacy-policy.html` and
    /// `docs/terms-of-use.html` — NOT under `ios/`, because GitHub Pages'
    /// "Deploy from a branch" option only supports serving from the repo
    /// root or a root-level `/docs` folder, not an arbitrary nested path).
    /// This is a free host requiring no new account, but GitHub Pages is
    /// NOT enabled automatically by pushing these files — Sean still needs
    /// to turn it on once, in the repo's Settings → Pages, and pick
    /// "Deploy from a branch" → `main` → `/docs`. If Sean prefers a
    /// different host (his own site, or Cloudflare Pages), just swap these
    /// two URLs.
    private let privacyPolicyURL = URL(string: "https://spierce26-ems.github.io/Vehicle_Damage_Asst/privacy-policy.html")!
    private let termsOfUseURL = URL(string: "https://spierce26-ems.github.io/Vehicle_Damage_Asst/terms-of-use.html")!

    /// Called once a purchase/credit-consumption successfully unlocks
    /// access. The caller is responsible for marking the specific case as
    /// unlocked and persisting it — this view only handles the
    /// storefront/entitlement side, not case-specific state.
    var onUnlocked: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if purchases.isLoadingProducts && purchases.products.isEmpty {
                        ProgressView("Loading options…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        consumerSection
                        proSection
                    }
                    restoreButton
                    legalFooter
                }
                .padding()
            }
            .navigationTitle("Unlock Full Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await purchases.loadProducts() }
            .alert("Something Went Wrong", isPresented: Binding(
                get: { purchases.lastError != nil },
                set: { if !$0 { purchases.lastError = nil } }
            )) {
                Button("OK", role: .cancel) { purchases.lastError = nil }
            } message: {
                Text(purchases.lastError ?? "")
            }
            .overlay {
                if purchases.isPurchasing {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        ProgressView().tint(.white).scaleEffect(1.4)
                    }
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Full Correlation Report", systemImage: "doc.text.magnifyingglass")
                .font(.title2.bold())
            Text("Your composite score is ready. Unlock the per-factor breakdown, investigative recommendations, and a shareable PDF report to hand to an insurer, investigator, or attorney.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Consumer (pay-per-case) section

    private var consumerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("One-Time Use").font(.headline)
            Text("For a single incident — no subscription required.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if purchases.caseCredits > 0 {
                creditsBanner
            }

            ForEach(consumerProducts, id: \.id) { product in
                PaywallOptionRow(
                    title: product.displayName,
                    subtitle: product.description,
                    price: product.displayPrice
                ) {
                    Task {
                        if await purchases.purchase(product) {
                            onUnlocked()
                            dismiss()
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var creditsBanner: some View {
        Label("You have \(purchases.caseCredits) unused case credit\(purchases.caseCredits == 1 ? "" : "s").", systemImage: "checkmark.seal.fill")
            .font(.subheadline.bold())
            .foregroundStyle(.green)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Pro (subscription) section

    private var proSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("For Professionals").font(.headline)
            Text("Insurance adjusters, body shops, and investigators handling multiple cases — unlimited unlocks, billed on a recurring basis.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(subscriptionProducts, id: \.id) { product in
                PaywallOptionRow(
                    title: product.displayName,
                    subtitle: subscriptionSubtitle(for: product),
                    price: product.displayPrice,
                    isHighlighted: product.id == PurchaseManager.ProductID.proAnnual
                ) {
                    Task {
                        if await purchases.purchase(product) {
                            onUnlocked()
                            dismiss()
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func subscriptionSubtitle(for product: Product) -> String {
        if product.id == PurchaseManager.ProductID.proAnnual {
            return "Unlimited case unlocks. Best value — billed yearly."
        }
        return "Unlimited case unlocks. Billed monthly, cancel anytime."
    }

    // MARK: Restore

    private var restoreButton: some View {
        Button {
            Task { await purchases.restorePurchases() }
        } label: {
            Text("Restore Purchases")
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Legal

    /// NOTE(AI Developer): Apple's App Store Review Guidelines (3.1.2)
    /// require auto-renewing subscription terms (length, price, and that
    /// it auto-renews unless cancelled) to be disclosed before purchase,
    /// not just buried in a separate Terms document. Kept short here by
    /// design — full text belongs in a real Terms of Use / Privacy Policy
    /// Sean still needs to publish (see the setup notes shared alongside
    /// this change), but this inline disclosure is the part Apple
    /// specifically checks for on the purchase screen itself.
    private var legalFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Settings > Apple ID > Subscriptions. Payment is charged to your Apple ID account at purchase confirmation.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 16) {
                Link("Terms of Use", destination: termsOfUseURL)
                Link("Privacy Policy", destination: privacyPolicyURL)
            }
            .font(.caption2.bold())
        }
    }

    // MARK: Product filtering

    private var consumerProducts: [Product] {
        purchases.products.filter { PurchaseManager.ProductID.consumables.contains($0.id) }
    }

    private var subscriptionProducts: [Product] {
        purchases.products.filter { PurchaseManager.ProductID.subscriptions.contains($0.id) }
    }
}

// MARK: - Paywall Option Row

private struct PaywallOptionRow: View {
    let title: String
    let subtitle: String
    let price: String
    var isHighlighted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Text(price)
                    .font(.subheadline.bold())
                    .foregroundStyle(.tint)
            }
            .padding()
            .background(
                isHighlighted ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHighlighted ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
