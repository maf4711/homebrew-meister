import Foundation
import Combine

struct TweakItem: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    var isOn: Bool
}

/// OnyX-style hidden macOS settings — mirrors `meisterSiri tweaks`.
@MainActor
final class TweaksService: ObservableObject {
    @Published var items: [TweakItem] = []
    @Published var lastMessage: String = ""

    func refresh() {
        items = [
            TweakItem(
                id: "showhidden",
                title: "Versteckte Dateien",
                detail: "Finder zeigt Dotfiles",
                isOn: boolDefault("com.apple.finder", "AppleShowAllFiles")
            ),
            TweakItem(
                id: "extensions",
                title: "Datei-Endungen",
                detail: "Alle Extensions anzeigen",
                isOn: boolDefault(nil, "AppleShowAllExtensions")
            ),
            TweakItem(
                id: "pathbar",
                title: "Pfad- & Statusleiste",
                detail: "Finder Pfad/Status",
                isOn: boolDefault("com.apple.finder", "ShowPathbar")
            ),
            TweakItem(
                id: "keyrepeat",
                title: "Schnelle Tastenwiederholung",
                detail: "KeyRepeat 2 / Initial 15",
                isOn: (intDefault(nil, "KeyRepeat") ?? 99) <= 2
            ),
            TweakItem(
                id: "savepanel",
                title: "Sichern-Dialog ausgeklappt",
                detail: "Immer erweiterter Save-Panel",
                isOn: boolDefault(nil, "NSNavPanelExpandedStateForSaveMode")
            ),
            TweakItem(
                id: "dockfast",
                title: "Dock-Autohide schnell",
                detail: "Keine Verzögerung beim Einblenden",
                isOn: (floatDefault("com.apple.dock", "autohide-time-modifier") ?? 1) < 0.5
            ),
            TweakItem(
                id: "screenshots-jpg",
                title: "Screenshots als JPG",
                detail: "Statt PNG (kleinere Dateien)",
                isOn: (stringDefault("com.apple.screencapture", "type") ?? "png") == "jpg"
            ),
        ]
    }

    func set(id: String, on: Bool, viaCLI: CLIRunner) {
        let mode = on ? "on" : "off"
        // Prefer CLI so behavior stays identical to meisterSiri tweaks
        let result = viaCLI.runSync(arguments: ["tweaks", id, mode], timeout: 15)
        lastMessage = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if lastMessage.isEmpty {
            lastMessage = "\(id) → \(mode) (exit \(result.code))"
        }
        refresh()
    }

    // MARK: - defaults helpers

    private func boolDefault(_ domain: String?, _ key: String) -> Bool {
        let d = UserDefaults(suiteName: domain)
        if domain == nil {
            return UserDefaults.standard.object(forKey: key) as? Bool
                ?? (UserDefaults.standard.object(forKey: key) as? NSNumber)?.boolValue
                ?? false
        }
        return d?.object(forKey: key) as? Bool
            ?? (d?.object(forKey: key) as? NSNumber)?.boolValue
            ?? false
    }

    private func intDefault(_ domain: String?, _ key: String) -> Int? {
        if let domain {
            return UserDefaults(suiteName: domain)?.object(forKey: key) as? Int
                ?? (UserDefaults(suiteName: domain)?.object(forKey: key) as? NSNumber)?.intValue
        }
        return UserDefaults.standard.object(forKey: key) as? Int
            ?? (UserDefaults.standard.object(forKey: key) as? NSNumber)?.intValue
    }

    private func floatDefault(_ domain: String?, _ key: String) -> Double? {
        if let domain {
            return UserDefaults(suiteName: domain)?.object(forKey: key) as? Double
                ?? (UserDefaults(suiteName: domain)?.object(forKey: key) as? NSNumber)?.doubleValue
        }
        return UserDefaults.standard.object(forKey: key) as? Double
            ?? (UserDefaults.standard.object(forKey: key) as? NSNumber)?.doubleValue
    }

    private func stringDefault(_ domain: String?, _ key: String) -> String? {
        if let domain {
            return UserDefaults(suiteName: domain)?.string(forKey: key)
        }
        return UserDefaults.standard.string(forKey: key)
    }
}
