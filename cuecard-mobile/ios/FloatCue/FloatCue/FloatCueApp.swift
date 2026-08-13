import SwiftUI

@main
struct FloatCueApp: App {
    @StateObject private var settingsService = SettingsService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settingsService)
                .preferredColorScheme(settingsService.settings.themePreference.colorScheme)
        }
    }
}

/// Local interaction logging for development. No events leave the device.
struct AnalyticsEvents {
    static func logButtonClick(_ buttonName: String, screen: String, parameters: [String: Any]? = nil) {
        #if DEBUG
        print("[FloatCue] button=\(buttonName) screen=\(screen) parameters=\(parameters ?? [:])")
        #endif
    }
}
