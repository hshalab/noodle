import BrowserBridge
import ComputerBridge
import Foundation
import HubCore
import HubLink
import NoodleCore
import NoodleRuntime
import XCTest

/// Noodle serving its own owner's devices: the bots already on the Mac, with nobody else to share them.
@MainActor final class PersonalHubTests: XCTestCase {
    private struct Fixture {
        let personal: PersonalHub
        let repository: WorkspaceRepository
        let device: HubPairing
    }

    private func fixture(bots names: [String], runtime: AgentRuntimeCoordinator? = nil) async throws -> (Fixture, [AgentRecord]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("noodle-personal-hub-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let repository = WorkspaceRepository(rootURL: root.appendingPathComponent("Noodle"))
        try repository.prepare()
        // Bots made in Noodle before it served anyone.
        let made = try names.map { try repository.createAgent(named: $0).agent }
        let runtime = runtime ?? AgentRuntimeCoordinator(discovery: HarnessDiscovery(managedHarnesses: repository.managedHarnesses))
        let personal = PersonalHub(name: "Studio", directory: root.appendingPathComponent("Remote"), repository: repository,
                                   runtime: runtime, applets: AppletController(repository: repository),
                                   profiles: HarnessProfilesController(store: repository.harnessProfiles), port: 0,
                                   localEndpoints: { [LinkEndpoint(host: "::1", port: $0)] })
        await personal.start()
        addTeardownBlock { await MainActor.run { personal.stop() } }
        guard case .listening = personal.link.state else { throw XCTSkip("Could not listen: \(personal.link.state)") }
        let device = HubPairing(directory: root.appendingPathComponent("Phone"), deviceName: "iPhone")
        await device.join(personal.link.invite(personal.owner).url().absoluteString)
        XCTAssertNil(device.error)
        return (Fixture(personal: personal, repository: repository, device: device), made)
    }

    func testAPhoneSeesTheBotsAlreadyOnTheMacAndTalksToThem() async throws {
        let (f, made) = try await fixture(bots: ["Kai", "Eli"])
        guard case .bots(let bots) = try await f.device.request(.bots) else { return XCTFail("no bots") }
        XCTAssertEqual(Set(bots.map(\.id)), Set(made.map(\.id)))

        let kai = try XCTUnwrap(bots.first { $0.id == made[0].id })
        _ = try await f.device.request(.send(LinkOutgoingMessage(conversationID: kai.conversationID, id: UUID(), body: "Hello from the phone")))
        XCTAssertEqual(try f.repository.loadMessages(conversationID: kai.conversationID).map(\.body), ["Hello from the phone"])

        // A bot made on the Mac later shows up too.
        let later = try f.repository.createAgent(named: "Cass").agent
        guard case .bots(let now) = try await f.device.request(.bots) else { return XCTFail("no bots") }
        XCTAssertTrue(now.contains { $0.id == later.id })
    }

    /// A phone joining later reads the conversations as they already are.
    func testAPhoneReadsTheConversationsAlreadyOnTheMac() async throws {
        let (f, made) = try await fixture(bots: ["Eli"])
        let conversation = try XCTUnwrap(f.repository.loadConversations().first { $0.participantIDs == [made[0].id] })
        _ = try f.repository.sendUserMessage(conversationID: conversation.id, body: "Hi there")
        _ = try f.repository.sendAgentMessage(agentID: made[0].id, conversationID: conversation.id, body: "Hey, how are you?")
        guard case .bots(let bots) = try await f.device.request(.bots) else { return XCTFail("no bots") }
        let eli = try XCTUnwrap(bots.first)
        XCTAssertEqual(eli.conversationID, conversation.id)
        guard case .messages(let page) = try await f.device.request(.messages(conversationID: eli.conversationID, after: 0)) else {
            return XCTFail("no messages")
        }
        XCTAssertEqual(page.messages.map(\.body), ["Hi there", "Hey, how are you?"])
    }

    /// Reading on the Mac reads on the phone, and reading on the phone tells the Mac.
    func testReadingIsSharedBetweenTheMacAndThePhone() async throws {
        let (f, made) = try await fixture(bots: ["Eli"])
        let conversation = try XCTUnwrap(f.repository.loadConversations().first { $0.participantIDs == [made[0].id] })
        _ = try f.repository.sendAgentMessage(agentID: made[0].id, conversationID: conversation.id, body: "Morning")
        // As kept, which is to the second.
        let morning = try XCTUnwrap(f.repository.loadMessages(conversationID: conversation.id).last)

        f.personal.markRead(conversation: conversation.id)
        guard case .bots(let bots) = try await f.device.request(.bots) else { return XCTFail("no bots") }
        XCTAssertEqual(bots.first?.readUpTo, morning.createdAt)

        let evening = ChatMessage(id: UUID(), conversationID: conversation.id, author: .agent(made[0].id), body: "Evening",
                                  createdAt: morning.createdAt.addingTimeInterval(60), delivery: .delivered)
        try f.repository.append(evening)
        var read: (conversation: UUID, upTo: Date)?
        f.personal.onRead = { read = ($0, $1) }
        _ = try await f.device.request(.markRead(LinkReadMark(conversationID: conversation.id, messageID: evening.id)))
        XCTAssertEqual(read?.conversation, conversation.id)
        XCTAssertEqual(read?.upTo, evening.createdAt)
    }

    /// A long conversation, well past what one answer may carry, arrives newest first and page by
    /// page as the person scrolls back; a device reading onward gets the rest the same way.
    func testALongConversationArrivesPageByPage() async throws {
        let (f, made) = try await fixture(bots: ["Eli"])
        let conversation = try XCTUnwrap(f.repository.loadConversations().first { $0.participantIDs == [made[0].id] })
        let long = String(repeating: "The little bookshop at the end of the street opened at nine. ", count: 800)
        for index in 0..<40 { _ = try f.repository.sendAgentMessage(agentID: made[0].id, conversationID: conversation.id, body: "\(index) \(long)") }
        func page(_ request: LinkMessagePage) async throws -> LinkMessages {
            guard case .messages(let page) = try await f.device.request(.messagePage(request)) else { throw LinkError("no messages") }
            return page
        }
        func numbers(_ page: LinkMessages) -> [Int] { page.messages.compactMap { $0.body.split(separator: " ").first.flatMap { Int($0) } } }

        var newest = try await page(LinkMessagePage(conversationID: conversation.id))
        XCTAssertEqual(newest.count, 40)
        XCTAssertLessThan(newest.messages.count, 40, "the whole conversation came at once")
        XCTAssertEqual(numbers(newest).last, 39, "the first page was not the newest")
        var seen = numbers(newest)
        while let start = newest.start, start > 0 {
            newest = try await page(LinkMessagePage(conversationID: conversation.id, before: start))
            seen = numbers(newest) + seen
        }
        XCTAssertEqual(seen, Array(0..<40))

        var onward: [Int] = [], at = 0
        while at < 40 {
            let next = try await page(LinkMessagePage(conversationID: conversation.id, after: at))
            onward += numbers(next)
            at += next.messages.count
        }
        XCTAssertEqual(onward, Array(0..<40))
    }

    /// Pages leave card pictures out; each card's picture comes on its own when it is shown.
    func testCardPicturesComeOnTheirOwn() async throws {
        let (f, made) = try await fixture(bots: ["Kai"])
        let conversation = try XCTUnwrap(f.repository.loadConversations().first { $0.participantIDs == [made[0].id] })
        let picture = Data(repeating: 7, count: 400_000)
        let card = try f.repository.importLinkAttachment(BrowserLink.url(browser: UUID(), tab: UUID()), into: conversation.id,
                                                          card: LinkCard(title: "Hacker News", detail: "https://news.ycombinator.com", image: picture))
        _ = try f.repository.sendAgentMessage(agentID: made[0].id, conversationID: conversation.id, body: "Here", attachmentIDs: [card.id])
        guard case .messages(let page) = try await f.device.request(.messagePage(LinkMessagePage(conversationID: conversation.id))) else {
            return XCTFail("no messages")
        }
        let listed = try XCTUnwrap(page.messages.last?.attachments.first)
        XCTAssertEqual(listed.card?.title, "Hacker News")
        XCTAssertNil(listed.card?.image, "a page carried a card's picture")
        let fetched = try await f.device.request(.linkPreview(conversationID: conversation.id, attachmentID: card.id))
        XCTAssertEqual(fetched, .picture(picture))
    }

    /// Stands in for a harness, so the Mac's own runtime can be told to fail and seen to restart.
    private final class FakeProcess: AgentRuntimeProcess {
        let launch: AgentRuntimeLaunch
        var configuration: AgentRecord { launch.agent }
        var snapshot: AgentRuntimeSnapshot
        var isAlive = false
        var hasInterruptedWork: Bool { false }
        var canReceiveHeartbeat: Bool { false }
        var stops = 0

        init(_ launch: AgentRuntimeLaunch) {
            self.launch = launch
            snapshot = AgentRuntimeSnapshot(agentID: launch.agent.id, phase: .offline, detail: "")
        }
        func set(_ phase: AgentRuntimePhase, failure: AgentRuntimeFailure? = nil) {
            snapshot.phase = phase
            snapshot.failure = failure
            launch.onSnapshot(snapshot)
        }
        func start() { isAlive = true; set(.ready) }
        func stop(completion: @escaping (Bool) -> Void) { stops += 1; isAlive = false; set(.offline); completion(true) }
        func notify(immediately: Bool) -> UUID { UUID() }
        func promoteNotification(_ id: UUID) {}
        func heartbeat() {}
    }

    /// Noodle's own runtime, with a harness that is only a file and processes that are fakes.
    private func fakeRuntime() throws -> (AgentRuntimeCoordinator, () -> [FakeProcess]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("noodle-personal-runtime-\(UUID())").resolvingSymlinksInPath()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin"), codex = root.appendingPathComponent("bin/codex")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 99\n".utf8).write(to: codex)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: codex.path)
        let suite = "Noodle.PersonalHubTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        var processes: [FakeProcess] = []
        let runtime = AgentRuntimeCoordinator(
            discovery: HarnessDiscovery(homeDirectory: root, applicationsDirectory: root, executableSearchDirectories: [bin],
                                        applicationBundleURL: root, environment: [:]),
            defaults: defaults, makeProcess: { launch in
                let process = FakeProcess(launch)
                processes.append(process)
                return process
            })
        addTeardownBlock { await MainActor.run { runtime.stopAll() } }
        return (runtime, { processes })
    }

    private func startedBot(_ f: Fixture, in runtime: AgentRuntimeCoordinator, _ processes: () -> [FakeProcess]) throws -> (AgentRecord, FakeProcess) {
        let made = try f.repository.createAgent(named: "Kai", harnessIdentifier: "codex").agent
        // As Noodle runs it: read back from its library.
        let agent = try XCTUnwrap(f.repository.loadAgents().first { $0.id == made.id })
        runtime.start(agent: agent, repository: f.repository)
        return (agent, try XCTUnwrap(processes().last))
    }

    /// As in Noodle's sidebar: Kick restarts a failed bot at once, through the Mac's own runtime.
    func testAPhoneKicksAFailedBotThroughTheMacsRuntime() async throws {
        let (runtime, processes) = try fakeRuntime()
        let (f, _) = try await fixture(bots: [], runtime: runtime)
        let (agent, first) = try startedBot(f, in: runtime, processes)
        first.set(.failed)

        let answer = try await f.device.request(.kick(botID: agent.id))
        XCTAssertEqual(answer, .done)
        XCTAssertEqual(first.stops, 1)
        XCTAssertEqual(processes().count, 2, "Kick starts the bot again in Noodle's runtime, not another")
        XCTAssertEqual(runtime.snapshot(for: agent.id).phase, .ready)
    }

    /// A failure Noodle asks about first is asked about on the phone too, in Noodle's words,
    /// and only the confirmation restarts the bot, once.
    func testAPhoneConfirmsAKickNoodleWouldAskAbout() async throws {
        let (runtime, processes) = try fakeRuntime()
        let (f, _) = try await fixture(bots: [], runtime: runtime)
        let (agent, first) = try startedBot(f, in: runtime, processes)
        first.set(.failed, failure: .safetyStop)

        guard case .kickConfirmation(let confirmation) = try await f.device.request(.kick(botID: agent.id)) else {
            return XCTFail("no confirmation")
        }
        XCTAssertEqual(confirmation.title, "Safeguards stopped Kai")
        XCTAssertTrue(confirmation.message.hasPrefix("The model's safeguards stopped a response."))
        XCTAssertEqual(confirmation.confirmTitle, "Resume")
        XCTAssertTrue(confirmation.offersNewSession)
        XCTAssertEqual(first.stops, 0, "Asking must leave the bot alone")

        let confirmed = try await f.device.request(.confirmKick(botID: agent.id, confirmationID: confirmation.id))
        XCTAssertEqual(confirmed, .done)
        XCTAssertEqual(first.stops, 1)
        XCTAssertEqual(processes().count, 2)
        let again = try await f.device.request(.confirmKick(botID: agent.id, confirmationID: confirmation.id))
        XCTAssertEqual(again, .done)
        XCTAssertEqual(processes().count, 2, "A confirmation works once")
    }

    /// As in Noodle's sidebar: New Session is there whatever the bot is doing, but not for another Hub's bot.
    func testAPhoneStartsANewSession() async throws {
        let (runtime, processes) = try fakeRuntime()
        let (f, _) = try await fixture(bots: [], runtime: runtime)
        let (agent, first) = try startedBot(f, in: runtime, processes)

        let answer = try await f.device.request(.newSession(botID: agent.id))
        XCTAssertEqual(answer, .done)
        XCTAssertEqual(first.stops, 1)
        XCTAssertEqual(processes().count, 2)

        f.personal.bots.isHidden = { $0 == agent.id }
        do {
            _ = try await f.device.request(.newSession(botID: agent.id))
            XCTFail("another Hub's bot was restarted")
        } catch {}
        XCTAssertEqual(processes().count, 2)
    }

    /// Copies of bots the owner keeps on another Hub are that Hub's, not this Mac's.
    func testBotsOfAnotherHubStayHidden() async throws {
        let (f, made) = try await fixture(bots: ["Kai", "Mirrored"])
        f.personal.bots.isHidden = { $0 == made[1].id }
        guard case .bots(let bots) = try await f.device.request(.bots) else { return XCTFail("no bots") }
        XCTAssertEqual(bots.map(\.id), [made[0].id])
        let mirrored = try XCTUnwrap(f.repository.loadConversations().first { $0.participantIDs == [made[1].id] })
        do {
            _ = try await f.device.request(.messages(conversationID: mirrored.id, after: 0))
            XCTFail("another Hub's bot was readable")
        } catch {}
    }

    /// Tools, computers and browsers on the Mac belong to Noodle's own settings; a device does
    /// not make or change them there yet, so none is made where Noodle would not see it.
    func testToolsComputersAndBrowsersAreManagedOnTheMac() async throws {
        let (f, _) = try await fixture(bots: [])
        for request: LinkRequest in [.createBrowser(LinkBrowserDraft(name: "Work")), .deleteComputer(id: UUID()),
                                     .saveConnection(LinkConnectionDraft(name: "Notes", endpoint: URL(string: "https://example.com/mcp")!))] {
            do {
                _ = try await f.device.request(request)
                XCTFail("\(request) was taken")
            } catch {
                XCTAssertEqual(error.localizedDescription, "Manage tools, computers and browsers in Noodle on the Mac.")
            }
        }
    }

    /// It is the owner's own Mac: there is nobody else to add.
    func testNobodyElseCanBeAdded() async throws {
        let (f, _) = try await fixture(bots: [])
        XCTAssertThrowsError(try f.personal.access.addUser(named: "Bob"))
        XCTAssertEqual(f.personal.access.users.count, 1)
    }

    /// On a personal Mac everything is its owner's own: no bot, computer or browser is told whom it is for.
    func testAPersonalMacNamesNoOwners() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("noodle-personal-hub-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let repository = WorkspaceRepository(rootURL: root.appendingPathComponent("Noodle"))
        try repository.prepare()
        let bot = try repository.createAgent(named: "Kai").agent
        let runtime = AgentRuntimeCoordinator(discovery: HarnessDiscovery(managedHarnesses: repository.managedHarnesses))
        let personal = PersonalHub(name: "Studio", directory: root.appendingPathComponent("Remote"), repository: repository,
                                   runtime: runtime, applets: AppletController(repository: repository),
                                   profiles: HarnessProfilesController(store: repository.harnessProfiles), port: 0)
        personal.bots.synchronizeOwners()
        try personal.access.rename(personal.owner, to: "Someone Else")
        personal.bots.synchronizeOwners()
        XCTAssertNil(try repository.loadAgentOwner(bot))

        let computer = HubComputersTests.FakeComputer(), browser = HubBrowsersTests.FakeBrowser()
        let tools = ToolProviderRegistry(), assignments = ToolAssignmentStore()
        let computers = HubComputers(root: root, access: personal.access, tools: tools, assignments: assignments, call: { try computer.call($0) })
        let browsers = HubBrowsers(root: root, access: personal.access, tools: tools, assignments: assignments, call: { try browser.call($0) })
        let madeComputer = try await computers.create(ComputerDraft(template: "ubuntu", name: "Bench"), for: personal.owner)
        let madeBrowser = try await browsers.create(BrowserDraft(name: "Work"), for: personal.owner)
        await computers.refresh()
        await browsers.refresh()
        XCTAssertNil(computer.owner(of: madeComputer.id))
        XCTAssertNil(browser.owner(of: madeBrowser.id))
    }
}
