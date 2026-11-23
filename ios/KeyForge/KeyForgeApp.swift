import SwiftUI

@main
struct KeyForgeApp: App {
    @State private var settings: AppSettings
    @State private var vault = VaultStore()
    @State private var generator: GeneratorModel
    @State private var toasts = ToastCenter()

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _generator = State(initialValue: GeneratorModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(vault)
                .environment(generator)
                .environment(toasts)
                .preferredColorScheme(.dark)
                .tint(.ember)
        }
    }
}
