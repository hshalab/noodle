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
}
