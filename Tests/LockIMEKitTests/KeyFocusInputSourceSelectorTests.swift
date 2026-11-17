import Foundation
import Testing

@testable import LockIMEKit

/// Covers the transport-independent half of the key-focus selection: focus
/// resolution, request encoding, and reply decoding. The private HIToolbox
/// calls themselves are injected, so nothing here touches the keyboard.
@MainActor
@Suite("KeyFocusInputSourceSelector")
struct KeyFocusInputSourceSelectorTests {
    private typealias Selector = KeyFocusInputSourceSelector
    private typealias Failure = KeyFocusInputSourceSelector.Failure

    /// Records what the sequence sent, and answers with a canned reply.
    @MainActor
    private final class FakeTransport {
        var focusPID: pid_t? = 4242
        var ownPID: pid_t = 100
        var reply: Result<Data?, Failure> = .success(KeyFocusInputSourceSelectorTests.reply(status: 0))
        private(set) var sent: [(pid: pid_t, request: Data)] = []

        var transport: KeyFocusInputSourceSelector.Transport {
            .init(
                keyFocusPID: { self.focusPID },
                ownPID: { self.ownPID },
                send: { pid, request in
                    self.sent.append((pid, request))
                    return self.reply
                }
            )
        }
    }

    private static func reply(status: Int32) -> Data? {
        try? PropertyListSerialization.data(
            fromPropertyList: [KeyFocusInputSourceSelector.replyErrorKey: NSNumber(value: status)],
            format: .xml,
            options: 0
        )
    }

    private func select(_ fake: FakeTransport, flattened: Any? = Data([1, 2, 3])) -> Result<Void, Failure> {
        Selector.select(flatten: { flattened }, transport: fake.transport)
    }

    private func failure(_ result: Result<Void, Failure>) -> Failure? {
        if case let .failure(error) = result { return error }
        return nil
    }

    // MARK: - Sequence

    @Test("a zero-status reply from the focused process is a success")
    func successSendsToFocusedProcess() throws {
        let fake = FakeTransport()
        let result = select(fake)

        #expect(failure(result) == nil)
        #expect(fake.sent.count == 1)
        #expect(fake.sent.first?.pid == 4242)
        // The request carries the flattened source under HIToolbox's key.
        let request = try #require(fake.sent.first?.request)
        let plist = try PropertyListSerialization.propertyList(from: request, options: [], format: nil)
        let dictionary = try #require(plist as? [String: Any])
        #expect(dictionary[Selector.requestKey] as? Data == Data([1, 2, 3]))
    }

    @Test("no key-focus process fails without sending")
    func noFocus() {
        let fake = FakeTransport()
        fake.focusPID = nil
        #expect(failure(select(fake)) == .noFocus)
        #expect(fake.sent.isEmpty)
    }

    @Test("owning keyboard focus ourselves fails without sending")
    func ownProcess() {
        let fake = FakeTransport()
        fake.focusPID = fake.ownPID
        #expect(failure(select(fake)) == .ownProcess)
        #expect(fake.sent.isEmpty)
    }

    @Test("a source that cannot be flattened fails without sending")
    func flattenFails() {
        let fake = FakeTransport()
        #expect(failure(select(fake, flattened: nil)) == .serialization)
        #expect(fake.sent.isEmpty)
    }

    @Test("a flattened value that is not a property list fails without sending")
    func flattenedNotPropertyList() {
        let fake = FakeTransport()
        #expect(failure(select(fake, flattened: NSObject())) == .serialization)
        #expect(fake.sent.isEmpty)
    }

    @Test("a transport failure is passed through", arguments: [
        Failure.noPort, .transport(-1), .transport(-2),
    ])
    func transportFailure(error: KeyFocusInputSourceSelector.Failure) {
        let fake = FakeTransport()
        fake.reply = .failure(error)
        #expect(failure(select(fake)) == error)
    }

    @Test("a non-zero TSM status is a rejection")
    func rejected() {
        let fake = FakeTransport()
        fake.reply = .success(Self.reply(status: -50))
        #expect(failure(select(fake)) == .rejected(-50))
    }

    // MARK: - Reply decoding

    @Test("a missing reply is invalid")
    func missingReply() {
        #expect(failure(Selector.parseReply(nil)) == .invalidReply)
    }

    @Test("a reply that is not a property list is invalid")
    func garbageReply() {
        #expect(failure(Selector.parseReply(Data("not a plist".utf8))) == .invalidReply)
    }

    @Test("a reply without the status key is invalid")
    func replyWithoutStatus() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["other": 0], format: .xml, options: 0)
        #expect(failure(Selector.parseReply(data)) == .invalidReply)
    }

    @Test("a reply whose status is not a number is invalid")
    func replyWithWrongStatusType() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: [Selector.replyErrorKey: "0"], format: .xml, options: 0
        )
        #expect(failure(Selector.parseReply(data)) == .invalidReply)
    }

    @Test("a boolean status is not mistaken for a number")
    func replyWithBooleanStatus() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: [Selector.replyErrorKey: false], format: .xml, options: 0
        )
        #expect(failure(Selector.parseReply(data)) == .invalidReply)
    }
}
