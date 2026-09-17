import Foundation

/// Copy only app-owned settings once; never modify the previous application's domain.
enum PreferenceMigration {
    static let completedKey = "MeisterAI.preferencesMigrated.v1"
    static let legacyDomain = "com.maf4711.meistersiri"

    static func migrate(to preferences: UserDefaults = .standard, legacy: [String: Any]? = nil) {
        guard !preferences.bool(forKey: completedKey) else { return }
        let previous = legacy ?? preferences.persistentDomain(forName: legacyDomain) ?? [:]
        if preferences.object(forKey: "dryRunDefault") == nil,
           let dryRun = previous["dryRunDefault"] as? Bool {
            preferences.set(dryRun, forKey: "dryRunDefault")
        }
        preferences.set(true, forKey: completedKey)
    }
}
