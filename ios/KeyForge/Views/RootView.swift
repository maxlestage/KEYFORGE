import SwiftUI

/// Onboarding on the first launch, then the tabs; a privacy screen hides
/// everything as soon as the app is not in the foreground.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VaultStore.self) private var vault
    @Environment(GeneratorModel.self) private var generator
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if settings.onboardingDone {
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else {
                OnboardingView {
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                        settings.onboardingDone = true
                    }
                }
                .transition(.opacity)
            }

            if scenePhase != .active {
                PrivacyOverlay()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .overlay(alignment: .top) {
            if let toast = toasts.current {
                ToastView(toast: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(toast.id)
                    .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: scenePhase)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                // The decrypted entries and the session history leave memory.
                vault.lock()
                generator.clearHistory()
            }
        }
    }
}

/// Shown in the app switcher and whenever the app is inactive.
struct PrivacyOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.ink.opacity(0.6)
            VStack(spacing: 14) {
                LogoMark(size: 84, animated: false)
                Text("KeyForge")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct MainTabView: View {
    enum Tab: Hashable {
        case generator, vault, analyzer, settings
    }

    @State private var tab: Tab = .generator

    var body: some View {
        TabView(selection: $tab) {
            GeneratorView()
                .tabItem { Label("Générer", systemImage: "wand.and.stars") }
                .tag(Tab.generator)
            VaultView()
                .tabItem { Label("Coffre", systemImage: "lock.shield.fill") }
                .tag(Tab.vault)
            AnalyzerView()
                .tabItem { Label("Analyse", systemImage: "gauge.with.needle.fill") }
                .tag(Tab.analyzer)
            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .onChange(of: tab) { _, _ in Haptics.selection() }
    }
}
