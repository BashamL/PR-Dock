import Combine
import Foundation
import ServiceManagement

enum DockSidePreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case leading
    case trailing

    var id: Self { self }

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .leading: "Left"
        case .trailing: "Right"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let dockSide = "dockSide"
        static let showsAuthored = "showsAuthored"
        static let showsReviewRequests = "showsReviewRequests"
        static let refreshIntervalMinutes = "refreshIntervalMinutes"
        static let customGitHubCLIPath = "customGitHubCLIPath"
    }

    @Published var dockSide: DockSidePreference {
        didSet { defaults.set(dockSide.rawValue, forKey: Key.dockSide) }
    }

    @Published var showsAuthored: Bool {
        didSet { defaults.set(showsAuthored, forKey: Key.showsAuthored) }
    }

    @Published var showsReviewRequests: Bool {
        didSet { defaults.set(showsReviewRequests, forKey: Key.showsReviewRequests) }
    }

    @Published var refreshIntervalMinutes: Double {
        didSet {
            let clamped = min(max(refreshIntervalMinutes, 1), 30)
            if clamped != refreshIntervalMinutes {
                refreshIntervalMinutes = clamped
                return
            }
            defaults.set(clamped, forKey: Key.refreshIntervalMinutes)
        }
    }

    @Published var customGitHubCLIPath: String {
        didSet {
            defaults.set(
                customGitHubCLIPath.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: Key.customGitHubCLIPath
            )
        }
    }

    @Published private(set) var launchAtLoginStatus: SMAppService.Status
    @Published private(set) var launchAtLoginError: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        dockSide = DockSidePreference(
            rawValue: defaults.string(forKey: Key.dockSide) ?? ""
        ) ?? .automatic

        showsAuthored = defaults.object(forKey: Key.showsAuthored) as? Bool ?? true
        showsReviewRequests =
            defaults.object(forKey: Key.showsReviewRequests) as? Bool ?? true

        let storedInterval = defaults.double(forKey: Key.refreshIntervalMinutes)
        refreshIntervalMinutes = storedInterval == 0 ? 2 : storedInterval
        customGitHubCLIPath = defaults.string(forKey: Key.customGitHubCLIPath) ?? ""
        launchAtLoginStatus = SMAppService.mainApp.status
    }

    var launchAtLogin: Bool {
        launchAtLoginStatus == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLoginStatus = SMAppService.mainApp.status
    }

    func resolvedGitHubCLIURL(fileManager: FileManager = .default) -> URL? {
        let customPath = customGitHubCLIPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !customPath.isEmpty, fileManager.isExecutableFile(atPath: customPath) {
            return URL(fileURLWithPath: customPath)
        }

        let environmentPaths = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map { String($0) } ?? []
        let standardPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin",
        ]

        for directory in environmentPaths + standardPaths {
            let path = URL(fileURLWithPath: directory)
                .appendingPathComponent("gh")
                .path
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    func reset() {
        dockSide = .automatic
        showsAuthored = true
        showsReviewRequests = true
        refreshIntervalMinutes = 2
        customGitHubCLIPath = ""
    }
}
