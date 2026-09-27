import Foundation
import HubCore
import NoodleCore
import XCTest

@MainActor final class HubAccessTests: XCTestCase {
    private func access() -> (HubAccess, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("noodle-hub-access-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return (HubAccess(url: url), url)
    }

    func testHubStartsWithAnEmptyDefaultPlanThatNewUsersGet() throws {
        let (access, _) = access()
        XCTAssertEqual(access.plans.map(\.name), ["Default"])
        XCTAssertEqual(access.plans.first?.harnesses, [])
        let user = try access.addUser(named: "Ada")
        XCTAssertEqual(user.plan, HubPlan.defaultID)
        XCTAssertEqual(access.harnesses(for: user), [])
    }

    func testUsersGetTheHarnessesOfTheirPlan() throws {
        let (access, _) = access()
        let codex = HubHarness(provider: .codex, profile: UUID())
        let family = try access.addPlan(named: "Family")
        access.set(codex, included: true, in: family)
        let user = try access.addUser(named: "Ada")
        XCTAssertEqual(access.harnesses(for: user), [])
        access.move(user, to: family)
        XCTAssertEqual(access.harnesses(for: access.users[0]), [codex])
    }

    func testDeletingAPlanMovesItsUsersToDefault() throws {
        let (access, _) = access()
        let family = try access.addPlan(named: "Family")
        let user = try access.addUser(named: "Ada")
        access.move(user, to: family)
        access.delete(family)
        XCTAssertEqual(access.plans.map(\.name), ["Default"])
        XCTAssertEqual(access.users.first?.plan, HubPlan.defaultID)
        access.delete(access.plans[0])
        XCTAssertEqual(access.plans.map(\.name), ["Default"])
    }

    func testDeletedProfilesLeaveEveryPlan() throws {
        let (access, _) = access()
        let profile = UUID()
        access.set(HubHarness(provider: .codex, profile: profile), included: true, in: access.plans[0])
        access.set(HubHarness(provider: .apple, profile: nil), included: true, in: access.plans[0])
        access.removeProfile(profile)
        XCTAssertEqual(access.plans[0].harnesses, [HubHarness(provider: .apple, profile: nil)])
    }

    func testUsersAndPlansSurviveARelaunch() throws {
        let (access, url) = access()
        let family = try access.addPlan(named: "Family")
        access.set(HubHarness(provider: .claudeCode, profile: nil), included: true, in: family)
        let user = try access.addUser(named: "Ada")
        access.move(user, to: family)
        let reopened = HubAccess(url: url)
        XCTAssertEqual(reopened.plans, access.plans)
        XCTAssertEqual(reopened.users, access.users)
    }

    func testAPlanCanLimitTheModelsOfAHarness() throws {
        let (access, url) = access()
        let codex = HubHarness(provider: .codex, profile: nil)
        let family = try access.addPlan(named: "Family")
        access.set(codex, included: true, in: family)
        let user = try access.addUser(named: "Ada")
        access.move(user, to: family)
        XCTAssertNil(access.models(on: codex, for: access.users[0]))
        XCTAssertTrue(access.lends(codex, model: nil, to: user))
        XCTAssertTrue(access.lends(codex, model: "gpt-5", to: user))

        access.setModels(["gpt-5-mini"], for: codex, in: family)
        XCTAssertEqual(access.models(on: codex, for: access.users[0]), ["gpt-5-mini"])
        XCTAssertTrue(access.lends(codex, model: "gpt-5-mini", to: user))
        XCTAssertFalse(access.lends(codex, model: "gpt-5", to: user))
        // The harness default could be any model.
        XCTAssertFalse(access.lends(codex, model: nil, to: user))
        XCTAssertEqual(HubAccess(url: url).plans, access.plans)

        access.setModels(nil, for: codex, in: family)
        XCTAssertTrue(access.lends(codex, model: "gpt-5", to: user))
    }

    func testAHarnessLeavingAPlanTakesItsModelsWithIt() throws {
        let (access, _) = access()
        let profile = UUID()
        let codex = HubHarness(provider: .codex, profile: profile), claude = HubHarness(provider: .claudeCode, profile: nil)
        let plan = access.plans[0]
        access.set(codex, included: true, in: plan)
        access.set(claude, included: true, in: plan)
        access.setModels(["gpt-5"], for: codex, in: plan)
        access.setModels(["opus"], for: claude, in: plan)
        access.removeProfile(profile)
        access.set(claude, included: false, in: plan)
        XCTAssertEqual(access.plans[0].models, [:])
    }

    func testPlansSavedBeforeModelsStillRead() throws {
        let (_, url) = access()
        let json = #"{"users":[],"plans":[{"id":"00000000-0000-0000-0000-000000000000","name":"Default","harnesses":[{"provider":"codex"}]}]}"#
        try Data(json.utf8).write(to: url)
        let access = HubAccess(url: url)
        XCTAssertEqual(access.plans.first?.harnesses, [HubHarness(provider: .codex, profile: nil)])
        XCTAssertEqual(access.plans.first?.models, [:])
    }

    func testUsersCanPairTheirOwnDevicesUnlessTheOwnerTurnsItOff() throws {
        let (access, url) = access()
        let ada = try access.addUser(named: "Ada")
        XCTAssertTrue(ada.canPairDevices)
        access.setCanPairDevices(false, for: ada)
        XCTAssertEqual(HubAccess(url: url).users.first?.canPairDevices, false)
        access.setCanPairDevices(true, for: ada)
        XCTAssertEqual(HubAccess(url: url).users.first?.canPairDevices, true)
    }

    func testUsersSavedBeforePairingCanPairTheirOwnDevices() throws {
        let (_, url) = access()
        let json = #"{"users":[{"id":"\#(UUID())","name":"Ada","plan":"\#(HubPlan.defaultID)"}],"plans":[]}"#
        try Data(json.utf8).write(to: url)
        XCTAssertEqual(HubAccess(url: url).users.first?.canPairDevices, true)
    }
}
