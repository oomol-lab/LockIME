import Testing

@testable import LockIMEKit

@Suite("LauncherOverlayCatalog")
struct LauncherOverlayCatalogTests {
    @Test("recognises the curated launcher overlays")
    func recognisesLaunchers() {
        #expect(LauncherOverlayCatalog.isLauncher("com.apple.Spotlight"))
        #expect(LauncherOverlayCatalog.isLauncher("com.raycast.macos"))
        #expect(LauncherOverlayCatalog.isLauncher("com.runningwithcrayons.Alfred"))
        #expect(LauncherOverlayCatalog.isLauncher("at.obdev.LaunchBar"))
    }

    @Test("ordinary apps and nil are not launchers")
    func rejectsNonLaunchers() {
        #expect(!LauncherOverlayCatalog.isLauncher("com.apple.Safari"))
        #expect(!LauncherOverlayCatalog.isLauncher("com.foo.App"))
        #expect(!LauncherOverlayCatalog.isLauncher(nil))
    }

    @Test("launcher(forFocusedBundleID:) passes through launchers and nils out the rest")
    func resolvesFocusedBundle() {
        #expect(LauncherOverlayCatalog.launcher(forFocusedBundleID: "com.apple.Spotlight") == "com.apple.Spotlight")
        #expect(LauncherOverlayCatalog.launcher(forFocusedBundleID: "com.apple.Safari") == nil)
        #expect(LauncherOverlayCatalog.launcher(forFocusedBundleID: nil) == nil)
    }
}
