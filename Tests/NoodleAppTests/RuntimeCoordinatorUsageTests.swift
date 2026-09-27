import Foundation
import NoodleCore
import XCTest
@testable import Noodle
@testable import NoodleRuntime

@MainActor final class RuntimeCoordinatorUsageTests: XCTestCase {
    func testHarnessMessagesBecomeSamplesForTheirBotAndRuntime() throws {
        let f = try RuntimeCoordinatorFixture()
        defer { f.cleanUp() }
        var samples: [UsageSample] = []
        f.runtime.onUsage = { samples.append($0) }
        let agent = try f.agent("Ada", harness: .claudeCode)
        let first = try f.start(agent)
        func result(output: Int, cost: Double) -> [String: Any] {
            ["type": "result", "modelUsage": ["claude-opus-5-5": ["outputTokens": output, "costUSD": cost]]]
        }
        first.launch.onActivity(result(output: 10, cost: 0.1))
        first.launch.onActivity(result(output: 25, cost: 0.3))
        XCTAssertEqual(samples.map(\.tokens.output), [10, 15])
        XCTAssertEqual(samples.last?.agentID, agent.id)
        XCTAssertEqual(samples.last?.agentName, "Ada")
        XCTAssertEqual(samples.last?.harness, "claude-code")
        XCTAssertEqual(samples.last?.model, "claude-opus-5-5")
        XCTAssertEqual(samples.last?.date, f.clock.date)

        // A new runtime starts its own totals, and the old one's late messages are ignored.
        f.runtime.restart(agent: agent, repository: f.repository)
        let second = try XCTUnwrap(f.factory.processes.last)
        XCTAssertFalse(second === first)
        first.launch.onActivity(result(output: 40, cost: 0.5))
        second.launch.onActivity(result(output: 25, cost: 0.3))
        XCTAssertEqual(samples.map(\.tokens.output), [10, 15, 25])
    }

    /// A resumed Claude session repeats its totals; what the ledger holds for it is not counted again.
    func testRestartedClaudeSessionSubtractsWhatWasRecorded() throws {
        let f = try RuntimeCoordinatorFixture()
        defer { f.cleanUp() }
        var samples: [UsageSample] = []
        f.runtime.onUsage = { samples.append($0) }
        f.runtime.recordedUsage = { session in
            session == "s" ? ["claude-opus-5-5": UsageTotal(tokens: UsageTokens(output: 40), costUSD: 0.5)] : [:]
        }
        let agent = try f.agent("Ada", harness: .claudeCode)
        try f.start(agent).launch.onActivity(["type": "result", "session_id": "s",
            "modelUsage": ["claude-opus-5-5": ["outputTokens": 45, "costUSD": 0.75]]])
        XCTAssertEqual(samples.map(\.tokens.output), [5])
        XCTAssertEqual(samples.map(\.costUSD), [0.25])
        XCTAssertEqual(samples.map(\.session), ["s"])
    }
}
