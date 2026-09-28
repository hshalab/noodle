import Foundation
import NoodleCore
import XCTest
@testable import Noodle
@testable import NoodleRuntime

@MainActor final class RuntimeCoordinatorSessionTests: XCTestCase {
    private func fixture() throws -> RuntimeCoordinatorFixture {
        let f = try RuntimeCoordinatorFixture()
        addTeardownBlock { @MainActor in f.cleanUp() }
        return f
    }

    private func idleBot(_ f: RuntimeCoordinatorFixture) throws -> (AgentRecord, RuntimeProcessFixture, URL) {
        let agent = try f.agent(harness: .claudeCode), process = try f.start(agent)
        process.canReceiveHeartbeat = true
        let url = f.repository.storage(for: agent.id).sessionState(provider: .claudeCode, extendedAccess: false)
        try Data("saved session".utf8).write(to: url)
        return (agent, process, url)
    }

    private func advance(_ f: RuntimeCoordinatorFixture, hours: Double) {
        f.clock.date = f.clock.date.addingTimeInterval(hours * 3600)
    }

    func testIdleSessionOlderThanADayStartsFreshButHeartbeatsDoNotKeepItAlive() throws {
        let f = try fixture(), (agent, process, url) = try idleBot(f)
        let check = { f.runtime.reconcile(agents: [agent], repository: f.repository) }
        check()
        advance(f, hours: 23.5); check()
        XCTAssertEqual(f.factory.processes.count, 1, "The session is not a day old yet")
        advance(f, hours: 1); f.runtime.notify([agent], repository: f.repository); check()
        XCTAssertEqual(f.factory.processes.count, 1, "A message just arrived")
        advance(f, hours: 0.5)
        process.heartbeat(); process.transition(.working); process.transition(.ready)
        advance(f, hours: 0.4); check()
        XCTAssertEqual(f.factory.processes.count, 1, "Still within the idle time since the message")
        advance(f, hours: 0.2); check()
        XCTAssertEqual(process.stops, 1, "A heartbeat is not an interaction")
        XCTAssertEqual(f.factory.processes.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let fresh = try XCTUnwrap(f.factory.processes.last)
        fresh.canReceiveHeartbeat = true
        advance(f, hours: 12); check()
        XCTAssertEqual(f.factory.processes.count, 2, "The new session starts its own day")
    }

    func testRolloverRespectsTheSettingAndBusyBots() throws {
        let f = try fixture(), (agent, process, url) = try idleBot(f)
        let check = { f.runtime.reconcile(agents: [agent], repository: f.repository) }
        f.defaults.set(0, forKey: AgentSessionRollover.ageDefaultsKey)
        check(); advance(f, hours: 72); check()
        XCTAssertEqual(f.factory.processes.count, 1, "Never keeps the session")
        f.defaults.set(24 * 3600, forKey: AgentSessionRollover.ageDefaultsKey)
        process.canReceiveHeartbeat = false; check()
        XCTAssertEqual(f.factory.processes.count, 1, "Busy or queued work is never cut off")
        process.canReceiveHeartbeat = true; check()
        XCTAssertEqual(f.factory.processes.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testNewSessionWorksForAReadyBotAndRestartsTheClock() throws {
        let f = try fixture(), (agent, process, url) = try idleBot(f)
        let check = { f.runtime.reconcile(agents: [agent], repository: f.repository) }
        check(); advance(f, hours: 20)
        f.runtime.startNewSession(agent: agent, repository: f.repository)
        XCTAssertEqual(process.stops, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let fresh = try XCTUnwrap(f.factory.processes.last)
        fresh.canReceiveHeartbeat = true
        advance(f, hours: 10); check()
        XCTAssertEqual(f.factory.processes.count, 2)
    }

    func testFinishedTurnCountsAsActivity() throws {
        let f = try fixture(), (agent, process, _) = try idleBot(f)
        let check = { f.runtime.reconcile(agents: [agent], repository: f.repository) }
        check(); advance(f, hours: 24.5)
        process.transition(.working); process.transition(.ready)
        check()
        XCTAssertEqual(f.factory.processes.count, 1, "The bot just finished work")
        advance(f, hours: 1.1); check()
        XCTAssertEqual(f.factory.processes.count, 2)
    }

    func testSessionAgeSurvivesRestartAndIsForgottenWithTheBot() throws {
        let f = try fixture(), (agent, _, url) = try idleBot(f)
        f.runtime.reconcile(agents: [agent], repository: f.repository)
        let starts = { f.defaults.dictionary(forKey: "Noodle.session.startDates")?[agent.id.uuidString] }
        XCTAssertNotNil(starts())
        f.runtime.stopAll()

        advance(f, hours: 25)
        let factory = f.factory, clock = f.clock
        let reopened = AgentRuntimeCoordinator(discovery: f.discovery, defaults: f.defaults,
            makeProcess: { factory.make($0) }, sleep: { try await clock.sleep($0) }, now: { clock.date })
        defer { reopened.stopAll() }
        reopened.start(agent: agent, repository: f.repository)
        let process = try XCTUnwrap(f.factory.processes.last)
        process.canReceiveHeartbeat = true
        let launches = f.factory.processes.count
        reopened.reconcile(agents: [agent], repository: f.repository)
        XCTAssertEqual(f.factory.processes.count, launches + 1, "The session's age carries across a restart")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        reopened.refresh(agents: [], repository: nil)
        XCTAssertNil(starts())
    }
}
