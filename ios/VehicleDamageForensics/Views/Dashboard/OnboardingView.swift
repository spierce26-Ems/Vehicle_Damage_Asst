// OnboardingView.swift
// Vehicle Damage Investigation Assistant
// First-launch "how this works" walkthrough.
//
// NOTE(AI Developer), added 2026-07 per Sean's explicit request:
// "right now a first-time user lands on an empty dashboard with no
// explanation of what to do. A 2-3 screen 'how this works' intro (or
// just a helpful empty-state message with a "Start New Case"
// call-to-action) would reduce confusion for a stressed hit-and-run
// victim opening this for the first time." Sean offered these as an
// "or," but they're complementary rather than exclusive, so this
// implements both: `DashboardView.emptyState` now has a clear
// explanation + prominent "Start New Case" CTA (see NOTE there), and
// this file adds the 3-screen intro on top of that -- shown
// automatically the first time the dashboard appears (gated by the
// `hasSeenOnboarding` @AppStorage flag in DashboardView), and
// re-openable anytime via the empty state's "How does this work?" link
// so it isn't a one-shot dead end if someone dismisses it too fast while
// stressed.
//
// Presented as a `.fullScreenCover`, NOT wrapped in its own
// `NavigationStack` -- there's nothing to navigate to/from here, and
// `DashboardView.swift` already has an explicit NOTE warning against
// nesting a second `NavigationStack` inside its own.
import SwiftUI

/// Static content for one onboarding page.
struct OnboardingPage: Identifiable {
    let id = UUID()
    let systemImage: String
    let tint: Color
    let title: String
    let description: String
}

/// The 3-screen "how this works" intro. Content is deliberately written
/// for someone stressed/upset right after an incident, not a generic
/// feature tour -- short sentences, plain language, and page 3 explains
/// *why* the impact-marking step exists (echoing the same reasoning
/// Sean asked to surface in-flow on `ImpactMarkerView`), so the app's
/// most unusual/least-obvious step doesn't come as a surprise later.
struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            systemImage: "shield.lefthalf.filled",
            tint: .blue,
            title: "You're in the right place",
            description: "This app helps you document vehicle damage after a hit-and-run, so what you gather today holds up later — with your insurer, police, or in court."
        ),
        OnboardingPage(
            systemImage: "camera.viewfinder",
            tint: .orange,
            title: "Three quick steps per vehicle",
            description: "Take a few guided photos (and a LiDAR scan if your phone supports it), then mark where each vehicle was hit. It takes about 5 minutes per vehicle — the app walks you through every shot."
        ),
        OnboardingPage(
            systemImage: "checkmark.seal.fill",
            tint: .green,
            title: "Built to prove a match, not just log damage",
            description: "Marking the impact point and direction of travel lets the app check whether the damage on both vehicles actually lines up — not just that you say it does."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    OnboardingPageView(page: item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            VStack(spacing: 12) {
                Button {
                    if page == pages.count - 1 {
                        onFinish()
                    } else {
                        withAnimation { page += 1 }
                    }
                } label: {
                    Text(page == pages.count - 1 ? "Get Started" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if page < pages.count - 1 {
                    Button("Skip") { onFinish() }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .padding(.top, 8)
        }
    }
}

/// A single onboarding page's layout.
private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: page.systemImage)
                .font(.system(size: 72))
                .foregroundStyle(page.tint)
            Text(page.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(page.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
