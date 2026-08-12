import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            settingsList
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            AnalyticsEvents.logButtonClick("done", screen: "settings")
                            dismiss()
                        }
                    }
                }
        }
    }

    private var settingsList: some View {
        List {
            countdownSection
            teleprompterSection
            textSizeSection
            overlaySection
            appearanceSection
            resetSection
        }
    }

    private var countdownSection: some View {
        Section("Countdown") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Start Delay")
                    Spacer()
                    Text("\(settingsService.settings.countdownSeconds) seconds")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: { Double(settingsService.settings.countdownSeconds) },
                        set: { settingsService.settings.countdownSeconds = Int($0) }
                    ),
                    in: 0...10,
                    step: 1
                )
            }
            .padding(.vertical, 4)
        }
    }

    private var teleprompterSection: some View {
        Section("Teleprompter") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Highlight Speed")
                    Spacer()
                    Text("\(settingsService.settings.wordsPerMinute) WPM")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: { Double(settingsService.settings.wordsPerMinute) },
                        set: { settingsService.settings.wordsPerMinute = Int($0) }
                    ),
                    in: Double(TeleprompterSettings.wpmRange.lowerBound)...Double(TeleprompterSettings.wpmRange.upperBound),
                    step: 10
                )
            }
            .padding(.vertical, 4)
        }
    }

    private var textSizeSection: some View {
        Section("Text Size") {
            VStack(alignment: .leading, spacing: 8) {
                Text("App Text Size")
                Picker("App Text Size", selection: $settingsService.settings.fontSizePreset) {
                    ForEach(FontSizePreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Overlay Text Size")
                Picker("Overlay Text Size", selection: $settingsService.settings.pipFontSizePreset) {
                    ForEach(FontSizePreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var overlaySection: some View {
        Section("Overlay") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Overlay Dimension Ratio")
                Picker("Overlay Dimension Ratio", selection: $settingsService.settings.overlayAspectRatio) {
                    ForEach(OverlayAspectRatio.allCases, id: \.self) { ratio in
                        Text(ratio.rawValue).tag(ratio)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $settingsService.settings.themePreference) {
                ForEach(ThemePreference.allCases, id: \.self) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset to Defaults") {
                AnalyticsEvents.logButtonClick("reset_to_defaults", screen: "settings")
                settingsService.resetSettings()
            }
        }
    }

}

#Preview {
    SettingsView()
        .environmentObject(SettingsService.shared)
}
