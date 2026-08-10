import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: PRDockViewModel

    var body: some View {
        Form {
            Section("Dock") {
                Picker("Position", selection: $settings.dockSide) {
                    ForEach(DockSidePreference.allCases) { side in
                        Text(side.label).tag(side)
                    }
                }
                .pickerStyle(.segmented)

                Text("Automatic follows the Dock edge and uses the trailing side.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pull requests") {
                Toggle("Authored by me", isOn: $settings.showsAuthored)
                Toggle("Review requested from me", isOn: $settings.showsReviewRequests)

                Picker("Refresh", selection: $settings.refreshIntervalMinutes) {
                    Text("Every minute").tag(1.0)
                    Text("Every 2 minutes").tag(2.0)
                    Text("Every 5 minutes").tag(5.0)
                    Text("Every 10 minutes").tag(10.0)
                    Text("Every 30 minutes").tag(30.0)
                }
            }

            Section("GitHub CLI") {
                HStack {
                    TextField(
                        "Automatic",
                        text: $settings.customGitHubCLIPath,
                        prompt: Text("/opt/homebrew/bin/gh")
                    )
                    Button("Choose…", action: chooseGitHubCLI)
                }

                HStack {
                    Text(resolvedGitHubCLI)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Refresh Now", action: model.refresh)
                }
            }

            Section("Startup") {
                Toggle(
                    "Launch PR Dock at login",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { enabled in settings.setLaunchAtLogin(enabled) }
                    )
                )
                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(PRTone.danger.color)
                }
            }

            Section {
                HStack {
                    Button("Clear Cache", action: model.clearCache)
                    Spacer()
                    Button("Reset Settings", action: settings.reset)
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 500, height: 520)
    }

    private var resolvedGitHubCLI: String {
        settings.resolvedGitHubCLIURL()?.path ?? "GitHub CLI not found"
    }

    private func chooseGitHubCLI() {
        let panel = NSOpenPanel()
        panel.message = "Choose the GitHub CLI executable"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            settings.customGitHubCLIPath = url.path
        }
    }
}
