import AppKit
import Testing

@testable import LockIMEKit

@Suite("ProcessIdentity")
struct ProcessIdentityTests {
    // MARK: - Synthesis

    @Test func synthesizesFromExecutableName() {
        #expect(ProcessIdentity.syntheticID(executableName: "java") == "process:java")
    }

    @Test func synthesizesNothingWithoutAName() {
        #expect(ProcessIdentity.syntheticID(executableName: nil) == nil)
        #expect(ProcessIdentity.syntheticID(executableName: "") == nil)
    }

    /// The namespace marker must stay collision-proof: a real
    /// `CFBundleIdentifier` may contain only alphanumerics, `.`, and `-`,
    /// so the `:` is what guarantees a synthetic ID never shadows a real one.
    @Test func prefixCanNeverCollideWithABundleID() {
        #expect(ProcessIdentity.prefix.contains(":"))
    }

    // MARK: - Round trip

    @Test func extractsExecutableNameFromSyntheticID() {
        #expect(ProcessIdentity.executableName(from: "process:java") == "java")
    }

    @Test func roundTripsThroughSynthesisAndExtraction() {
        let id = ProcessIdentity.syntheticID(executableName: "java")
        #expect(id.flatMap(ProcessIdentity.executableName(from:)) == "java")
    }

    @Test func rejectsRealBundleIDs() {
        #expect(ProcessIdentity.executableName(from: "com.oomol.LockIME") == nil)
        #expect(!ProcessIdentity.isSynthetic("com.oomol.LockIME"))
    }

    @Test func rejectsDegeneratePrefixOnlyID() {
        #expect(ProcessIdentity.executableName(from: "process:") == nil)
        #expect(!ProcessIdentity.isSynthetic("process:"))
    }

    @Test func recognizesSyntheticIDs() {
        #expect(ProcessIdentity.isSynthetic("process:java"))
    }

    // MARK: - NSRunningApplication bridge

    /// A bundled process (this test runner) keeps its real bundle identifier —
    /// the synthetic identity is strictly a fallback.
    @MainActor
    @Test func bundledProcessKeepsItsBundleIdentifier() {
        let current = NSRunningApplication.current
        #expect(current.ruleIdentity == current.bundleIdentifier)
    }

    /// The synthesis keys on the executable basename — the stable,
    /// locale-invariant key that survives JVM/launcher upgrades (the *path*
    /// is versioned) — never the full path.
    @Test func synthesisUsesExecutableBasename() {
        let url = URL(fileURLWithPath: "/Library/Java/mojang-25.0.1.bundle/Contents/Home/bin/java")
        #expect(ProcessIdentity.syntheticID(executableURL: url) == "process:java")
    }

    /// Without an executable URL there is no identity — a display name would
    /// be an unstable (localizable) key, so none is minted at all.
    @Test func synthesisRequiresAnExecutableURL() {
        #expect(ProcessIdentity.syntheticID(executableURL: nil) == nil)
    }
}
