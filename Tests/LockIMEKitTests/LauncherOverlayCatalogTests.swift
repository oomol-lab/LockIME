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

    // macOS 27 draws the Cmd-Space panel from the Siri AI process and never
    // runs `Spotlight`; the host must be observed or Spotlight is undetectable.
    @Test("the Siri AI process hosting Spotlight's panel is observed as a launcher")
    func recognisesSpotlightHost() {
        #expect(LauncherOverlayCatalog.siriAI == "com.apple.campo")
        #expect(LauncherOverlayCatalog.isLauncher(LauncherOverlayCatalog.siriAI))
        #expect(LauncherOverlayCatalog.bundleIDs.contains(LauncherOverlayCatalog.spotlight))
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
        // The host is reported as the *process* it is; `ruleIdentity` maps it.
        #expect(LauncherOverlayCatalog.launcher(forFocusedBundleID: "com.apple.campo") == "com.apple.campo")
        #expect(LauncherOverlayCatalog.launcher(forFocusedBundleID: "com.apple.Safari") == nil)
        #expect(LauncherOverlayCatalog.launcher(forFocusedBundleID: nil) == nil)
    }

    @Test("the Spotlight panel hosted by Siri AI resolves the Spotlight rule")
    func hostOverlayResolvesSpotlight() {
        // The panel floats over another app: the host is focused but not
        // frontmost, which is exactly what makes it an overlay.
        #expect(LauncherOverlayCatalog.ruleIdentity(forLauncher: "com.apple.campo", frontmostBundleID: "com.apple.finder") == "com.apple.Spotlight")
        // No frontmost app at all (nothing active yet) still reads as the panel.
        #expect(LauncherOverlayCatalog.ruleIdentity(forLauncher: "com.apple.campo", frontmostBundleID: nil) == "com.apple.Spotlight")
    }

    @Test("a frontmost Siri AI is its regular chat window, not the Spotlight panel")
    func frontmostHostKeepsOwnIdentity() {
        #expect(LauncherOverlayCatalog.ruleIdentity(forLauncher: "com.apple.campo", frontmostBundleID: "com.apple.campo") == "com.apple.campo")
    }

    @Test("launchers that are not hosts resolve as themselves in either mode")
    func plainLaunchersResolveAsThemselves() {
        #expect(LauncherOverlayCatalog.ruleIdentity(forLauncher: "com.apple.Spotlight", frontmostBundleID: "com.apple.finder") == "com.apple.Spotlight")
        #expect(LauncherOverlayCatalog.ruleIdentity(forLauncher: "com.raycast.macos", frontmostBundleID: "com.apple.finder") == "com.raycast.macos")
        #expect(LauncherOverlayCatalog.ruleIdentity(forLauncher: "com.raycast.macos", frontmostBundleID: "com.raycast.macos") == "com.raycast.macos")
    }
}
