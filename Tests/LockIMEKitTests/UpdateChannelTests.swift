import Testing

@testable import LockIMEKit

@Suite("UpdateChannel")
struct UpdateChannelTests {
    @Test("stable allows only the default channel (empty set)")
    func stable() {
        #expect(UpdateChannel.allowedChannels(for: .stable) == [])
    }

    @Test("beta adds the beta channel")
    func beta() {
        #expect(UpdateChannel.allowedChannels(for: .beta) == ["beta"])
    }

    @Test("maps from a beta preference flag")
    func fromFlag() {
        #expect(UpdateChannel.from(usesBeta: true) == .beta)
        #expect(UpdateChannel.from(usesBeta: false) == .stable)
    }

    @Test("id is the raw channel name")
    func id() {
        #expect(UpdateChannel.stable.id == "stable")
        #expect(UpdateChannel.beta.id == "beta")
        for channel in UpdateChannel.allCases {
            #expect(channel.id == channel.rawValue)
        }
    }
}
