import HubLink
@testable import NoodleMobile
import Testing

/// Whether a Hub answers, and what that makes its bots show.
@Suite struct HubConnectionTests {
    @Test func connectedOnlyOnceTheHubAnswered() {
        #expect(HubConnection(isWorking: false, answered: false, failed: false) == .connecting)
        #expect(HubConnection(isWorking: true, answered: true, failed: true) == .connecting)
        #expect(HubConnection(isWorking: false, answered: true, failed: true) == .notConnected)
        #expect(HubConnection(isWorking: false, answered: false, failed: true) == .notConnected)
        #expect(HubConnection(isWorking: false, answered: true, failed: false) == .connected)
    }

    @Test func botsOfAHubNotConnectedShowAsOffline() {
        #expect(HubConnection.notConnected.phase(of: .ready) == .offline)
        #expect(HubConnection.notConnected.phase(of: .working) == .offline)
        #expect(HubConnection.connected.phase(of: .working) == .working)
        #expect(HubConnection.connecting.phase(of: .ready) == .ready)
    }
}
