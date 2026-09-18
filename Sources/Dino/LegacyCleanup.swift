import Foundation

/// The app used to be called DinoWidget. Remove what that left behind: the old
/// Application Support folder (its key and history) and the old preferences
/// domain, so nothing stale is left sitting in the user's Library.
///
/// Both steps are no-ops once they are gone, and the flag is only written after
/// they succeed, so a failure retries on the next launch.
enum LegacyCleanup {
    private static let flagKey = "removedDinoWidgetLeftovers"
    private static let legacyDomain = "com.vitor.dinowidget"
    private static let legacyFolder = "DinoWidget"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: flagKey) else { return }

        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

        try? manager.removeItem(
            at: base.appendingPathComponent(legacyFolder, isDirectory: true))

        // removePersistentDomain alone is not enough: cfprefsd still has the
        // domain cached from the old app's last run, so the plist comes back.
        defaults.removePersistentDomain(forName: legacyDomain)
        try? manager.removeItem(
            at: home.appendingPathComponent("Library/Preferences/\(legacyDomain).plist"))

        defaults.set(true, forKey: flagKey)
    }
}
