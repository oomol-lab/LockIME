import Testing

@testable import LockIMEKit

@MainActor
@Suite("InstalledAppsScanner")
struct InstalledAppsScannerTests {
    // Spotlight lives in `/System/Library/CoreServices` (never scanned) and,
    // on macOS 27, is not a running process either — the Siri AI process draws
    // its panel. It must still be offered, since `com.apple.Spotlight` is the
    // identity a Spotlight rule keys on (issue #63).
    @Test("offers Spotlight even when its process is not running")
    func offersSpotlight() {
        let apps = InstalledAppsScanner.scan()
        let spotlight = apps.filter { $0.bundleID == LauncherOverlayCatalog.spotlight }
        #expect(spotlight.count == 1)
        #expect(spotlight.first?.name.isEmpty == false)
    }

    @Test("rows are unique per identity and sorted by name")
    func uniqueAndSorted() {
        let apps = InstalledAppsScanner.scan()
        #expect(Set(apps.map(\.bundleID)).count == apps.count)
        let names = apps.map(\.name)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }
}
