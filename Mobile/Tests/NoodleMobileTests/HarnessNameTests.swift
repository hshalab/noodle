import Foundation
import HubLink
@testable import NoodleMobile
import Testing

/// A chosen harness reads on one line, with its profile after the provider.
struct HarnessNameTests {
    @Test func ownLoginIsTheProvider() {
        #expect(LinkHarness(provider: "codex", providerName: "Codex", profileName: nil).chosenName == "Codex")
    }

    @Test func profileFollowsTheProvider() {
        let harness = LinkHarness(provider: "codex", providerName: "Codex", profile: UUID(), profileName: "ada@example.com")
        #expect(harness.chosenName == "Codex · ada@example.com")
    }
}
