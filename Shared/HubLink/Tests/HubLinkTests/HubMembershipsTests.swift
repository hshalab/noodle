import Foundation
@testable import HubLink
import XCTest

/// Any web page or app can open an invitation link, so one opened that way joins only once confirmed.
@MainActor final class HubMembershipsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("HubMembershipsTests-\(UUID())", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func invitation(expires: Date) -> LinkInvitation {
        LinkInvitation(hubName: "Mac mini", hubKey: LinkIdentity().publicKey,
                       endpoints: [LinkEndpoint(host: "Mac-mini.local", port: 38_415)], userName: "Ada",
                       joinKey: LinkIdentity().privateKey.rawRepresentation, expires: expires)
    }

    func testAnOpenedLinkWaitsWithTheHubsKeyUntilConfirmed() {
        let invitation = invitation(expires: Date().addingTimeInterval(600))
        let hubs = HubMemberships(directory: directory, deviceName: "Phone")
        hubs.offer(invitation.url().absoluteString)
        XCTAssertEqual(hubs.offered?.hubKey.fingerprint, invitation.hubKey.fingerprint)
        XCTAssertTrue(hubs.hubs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        hubs.declineOffered()
        XCTAssertNil(hubs.offered)
        XCTAssertTrue(hubs.hubs.isEmpty)
    }

    func testABrokenLinkIsNotOffered() {
        let hubs = HubMemberships(directory: directory, deviceName: "Phone")
        hubs.offer("noodle://join-hub?i=bm90IGpzb24")
        XCTAssertNil(hubs.offered)
        XCTAssertNotNil(hubs.joinError)
    }
}
