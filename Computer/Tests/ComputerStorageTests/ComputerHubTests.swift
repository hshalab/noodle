import ComputerBridge
import ComputerCore
import XCTest
@testable import NoodleComputer

@MainActor final class ComputerHubTests: XCTestCase {
    func testComputersTheHubUsesAreListedAsHub() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ComputerStore(root: root), identity = ComputerBuildIdentity.current
        let computer = Computer(name: "Shell", kind: .container)
        try FileManager.default.createDirectory(at: store.library.stagingDirectory(for: computer.id), withIntermediateDirectories: true)
        let session = ComputerSession(try store.library.commit(computer))
        store.sessions = [session]
        store.note(session, usedBy: identity.noodleIDs[0])
        XCTAssertNil(session.computer.hub)
        store.note(session, usedBy: identity.hubID)
        XCTAssertEqual(session.computer.hub, true)
        XCTAssertEqual(try store.library.load().first?.hub, true)
    }

    func testOnlyTheHubSaysWhomAComputerIsKeptFor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ComputerStore(root: root), identity = ComputerBuildIdentity.current
        let computer = Computer(name: "Shell", kind: .container)
        try FileManager.default.createDirectory(at: store.library.stagingDirectory(for: computer.id), withIntermediateDirectories: true)
        let session = ComputerSession(try store.library.commit(computer))
        store.sessions = [session]
        XCTAssertThrowsError(try store.setHubOwner(session, HubOwner(id: UUID(), name: "Eve"), from: identity.noodleIDs[0]))
        XCTAssertNil(session.computer.hubOwner)
        let ada = HubOwner(id: UUID(), name: "Ada")
        try store.setHubOwner(session, ada, from: identity.hubID)
        XCTAssertEqual(session.computer.hubOwner, ada)
        XCTAssertEqual(session.computer.hub, true)
        XCTAssertEqual(try store.library.load().first?.hubOwner, ada)
        try store.setHubOwner(session, nil, from: identity.hubID)
        XCTAssertNil(try store.library.load().first?.hubOwner)
    }

    func testTheHubsComputersAreGroupedByPerson() {
        let ada = HubOwner(id: UUID(), name: "Ada"), bob = HubOwner(id: UUID(), name: "Bob")
        func session(_ name: String, _ owner: HubOwner?) -> ComputerSession {
            var computer = Computer(name: name, kind: .container)
            computer.hub = true
            computer.hubOwner = owner
            return ComputerSession(computer)
        }
        let sessions = [session("Build", bob), session("Shell", ada), session("Loose", nil), session("Lab", ada)]
        let groups = ComputerStore.hubGroups(sessions)
        XCTAssertEqual(groups.people.map(\.owner), [ada, bob])
        XCTAssertEqual(groups.people.first?.sessions.map(\.computer.name), ["Shell", "Lab"])
        XCTAssertEqual(groups.unowned.map(\.computer.name), ["Loose"])
    }
}
