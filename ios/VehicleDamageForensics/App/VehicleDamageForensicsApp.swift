// VehicleDamageForensicsApp.swift
// Vehicle Damage Forensic Matcher
// Main app entry point with AppDelegate integration

import SwiftUI
import UserNotifications

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureAppearance()
        requestNotificationPermissions()
        return true
    }

    private func configureAppearance() {
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor.systemBackground
        navBarAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }
}

// MARK: - Main App

@main
struct VehicleDamageForensicsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var storageService = StorageService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(storageService)
                .onAppear {
                    appState.loadCases(from: storageService)
                }
        }
    }
}

// MARK: - App State

/// Central observable state container for the app
final class AppState: ObservableObject {
    @Published var cases: [ForensicCase] = []
    @Published var activeCase: ForensicCase?
    @Published var isAnalyzing: Bool = false
    @Published var errorMessage: String?

    // MARK: Case Management

    /// Creates a new blank case and sets it as active
    func createNewCase(caseNumber: String = "") -> ForensicCase {
        let newCase = ForensicCase(caseNumber: caseNumber.isEmpty ? generateCaseNumber() : caseNumber)
        cases.insert(newCase, at: 0)
        activeCase = newCase
        return newCase
    }

    // NOTE(AI Developer): The three methods below previously called
    // StorageService with signatures that don't match the real
    // implementation in Services/StorageService.swift:
    //   - loadAllCases() is `async -> Void` (non-throwing, populates
    //     storage.cases internally) — not `async throws -> [ForensicCase]`.
    //   - save(_:) is `async -> Bool` (non-throwing) — not `async throws`.
    //   - delete(caseID:) is synchronous (non-async), non-throwing, and
    //     takes a `UUID`, not a `ForensicCase`.
    // Rewritten to match the real API. Also worth flagging: AppState is
    // not currently read by any View (DashboardView drives its own
    // CaseListViewModel against StorageService directly), so this is
    // dead/unused state today — kept for future wiring per Section 4's
    // "AppState (env object) owns cases + active case" guardrail.

    /// Loads persisted cases from storage service
    func loadCases(from storage: StorageService) {
        Task { @MainActor in
            await storage.loadAllCases()
            cases = storage.cases
        }
    }

    /// Persists a case via the storage service
    func saveCase(_ forensicCase: ForensicCase, using storage: StorageService) {
        Task { @MainActor in
            let success = await storage.save(forensicCase)
            guard success else {
                errorMessage = "Failed to save case."
                return
            }
            if let idx = cases.firstIndex(where: { $0.id == forensicCase.id }) {
                cases[idx] = forensicCase
            } else {
                cases.insert(forensicCase, at: 0)
            }
        }
    }

    func deleteCase(_ forensicCase: ForensicCase, using storage: StorageService) {
        _ = storage.delete(caseID: forensicCase.id)
        cases.removeAll { $0.id == forensicCase.id }
        if activeCase?.id == forensicCase.id { activeCase = nil }
    }

    // MARK: Helpers

    private func generateCaseNumber() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateStr = formatter.string(from: Date())
        let seq = (cases.filter { $0.caseNumber.hasPrefix("VDF-\(dateStr)") }.count + 1)
        return String(format: "VDF-%@-%03d", dateStr, seq)
    }
}

// MARK: - Root Content View

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        // NOTE(AI Developer): NavigationView is deprecated on iOS 16+ and was
        // replaced with NavigationStack per Section 3, task 6 of the handoff
        // brief. IMPORTANT: DashboardView (Views/Dashboard/DashboardView.swift)
        // already wraps its own body in a NavigationStack (with its own
        // .navigationDestination routing for push-to-detail/capture/analysis).
        // Wrapping it in a second NavigationStack here would compile but is a
        // real SwiftUI bug: nested NavigationStacks each try to own path/
        // destination resolution, which breaks programmatic navigation
        // (navigationDestination(item:)/(for:) attached to the inner stack
        // can silently fail to trigger). So we do NOT wrap DashboardView in
        // another NavigationStack — just attach the app-level error alert.
        DashboardView()
            .alert("Error", isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { if !$0 { appState.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { appState.errorMessage = nil }
            } message: {
                Text(appState.errorMessage ?? "")
            }
    }
}
