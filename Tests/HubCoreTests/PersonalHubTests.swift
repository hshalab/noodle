import BrowserBridge
import ComputerBridge
import Foundation
import HubCore
import HubLink
import NoodleCore
import NoodleRuntime
import XCTest
@testable import NoodleMCP

/// Noodle serving its own owner's devices: the bots already on the Mac, with nobody else to share them.
@MainActor final class PersonalHubTests: XCTestCase {
    private struct Fixture {
        let personal: PersonalHub
        let repository: WorkspaceRepository
        let device: HubPairing
        let computer: HubComputersTests.FakeComputer
        let browser: HubBrowsersTests.FakeBrowser
        let hubDirectory: URL
    }

    private func fixture(bots names: [String]) async throws -> (Fixture, [AgentRecord]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("noodle-personal-hub-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let repository = WorkspaceRepository(rootURL: root.appendingPathComponent("Noodle"))
        try repository.prepare()
        // Bots made in Noodle before it served anyone.
        let made = try names.map { try repository.createAgent(named: $0).agent }
        let runtime = AgentRuntimeCoordinator(discovery: HarnessDiscovery(managedHarnesses: repository.managedHarnesses))
        let computer = HubComputersTests.FakeComputer(), browser = HubBrowsersTests.FakeBrowser()
        let personal = PersonalHub(name: "Studio", directory: root.appendingPathComponent("Remote"), repository: repository,
                                   runtime: runtime, applets: AppletController(repository: repository),
                                   profiles: HarnessProfilesController(store: repository.harnessProfiles), service: Self.service(),
                                   computer: { try computer.call($0) }, browser: { try browser.call($0) }, port: 0,
                                   localEndpoints: { [LinkEndpoint(host: "::1", port: $0)] })
        await personal.start()
        addTeardownBlock { await MainActor.run { personal.stop() } }
        guard case .listening = personal.link.state else { throw XCTSkip("Could not listen: \(personal.link.state)") }
        let device = HubPairing(directory: root.appendingPathComponent("Phone"), deviceName: "iPhone")
        await device.join(personal.link.invite(personal.owner).url().absoluteString)
        XCTAssertNil(device.error)
        return (Fixture(personal: personal, repository: repository, device: device, computer: computer, browser: browser,
                        hubDirectory: root.appendingPathComponent("Remote")), made)
    }

    /// Noodle's own tool service, with a Keychain that holds no sign-ins.
    private static func service() -> MCPService {
        MCPService(credentials: NoPersonalCredentials(), oauth: MCPOAuth(), httpConfiguration: { .ephemeral })
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

    /// The phone makes, changes, assigns and deletes the Mac's own tools, computers and browsers:
    /// the ones Noodle keeps beside its bots, not a copy only devices see.
    func testAPhoneManagesTheMacsOwnToolsComputersAndBrowsers() async throws {
        let (f, made) = try await fixture(bots: ["Kai"])
        let kai = made[0].id, root = f.repository.rootURL
        var edits = 0
        f.personal.onToolsEdited = { edits += 1 }

        let notes = LinkConnectionDraft(name: "Notes", endpoint: URL(string: "https://example.com/mcp")!)
        _ = try await f.device.request(.saveConnection(notes))
        _ = try await f.device.request(.assignConnections(botID: kai, connectionIDs: [notes.id]))
        XCTAssertEqual(try MCPRegistry.load(root: root).assigned(to: kai).map(\.name), ["Notes"])

        guard case .browser(let work) = try await f.device.request(.createBrowser(LinkBrowserDraft(name: "Work"))) else {
            return XCTFail("no browser")
        }
        _ = try await f.device.request(.assignBrowsers(botID: kai, browserIDs: [work.id]))
        guard case .browsers(let browsers) = try await f.device.request(.browsers) else { return XCTFail("no browsers") }
        XCTAssertEqual(browsers.map(\.botIDs), [[kai]])

        // Made in Noodle Computer on the Mac, then given to Kai from the phone.
        var create = ComputerRequest(.create)
        create.computer = ComputerDraft(template: "ubuntu", name: "Bench")
        let bench = try XCTUnwrap(try f.computer.call(create).computers?.first)
        guard case .computers(let listed) = try await f.device.request(.computers) else { return XCTFail("no computers") }
        XCTAssertEqual(listed.map(\.id), [bench.id])
        _ = try await f.device.request(.assignComputers(botID: kai, computerIDs: [bench.id]))
        _ = try await f.device.request(.updateComputer(id: bench.id, LinkComputerDraft(template: "ubuntu", name: "Workbench")))
        guard case .computers(let computers) = try await f.device.request(.computers) else { return XCTFail("no computers") }
        XCTAssertEqual(computers.map(\.name), ["Workbench"])
        XCTAssertEqual(computers.map(\.botIDs), [[kai]])
        _ = try await f.device.request(.deleteBrowser(id: work.id))
        guard case .browsers(let left) = try await f.device.request(.browsers) else { return XCTFail("no browsers") }
        XCTAssertTrue(left.isEmpty)

        // Kept in Noodle's own files, beside its bots, where its Settings and tool broker read them.
        // (Their contents are not read back: this macOS refuses to reopen protected files in tests.)
        for file in ["MCP/connections.json", "browsers.json", "computers.json"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path), file)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.hubDirectory.appendingPathComponent(file).path), file)
        }
        XCTAssertGreaterThan(edits, 0, "Noodle was not told to read its tools again")
    }

    /// What Noodle changed on the Mac after the phone joined is what the phone sees and changes,
    /// and a change from the phone keeps it.
    func testThePhoneWorksOnWhatNoodleChangedMeanwhile() async throws {
        let (f, made) = try await fixture(bots: ["Kai"])
        let kai = made[0].id, root = f.repository.rootURL
        // Saved in Noodle's Settings, as its tool controller does.
        var registry = try MCPRegistry.load(root: root)
        let notes = try MCPConnectionRecord(name: "Notes", endpoint: URL(string: "https://example.com/notes")!)
        registry.connections.append(notes)
        try registry.assign([notes.id], to: kai)
        try registry.save(root: root)

        guard case .connections(let listed) = try await f.device.request(.connections) else { return XCTFail("no connections") }
        XCTAssertEqual(listed.map(\.id), [notes.id])
        XCTAssertEqual(listed.first?.botIDs, [kai])

        let calendar = LinkConnectionDraft(name: "Calendar", endpoint: URL(string: "https://example.com/calendar")!)
        _ = try await f.device.request(.saveConnection(calendar))
        let saved = try MCPRegistry.load(root: root)
        XCTAssertEqual(Set(saved.connections.map(\.name)), ["Notes", "Calendar"])
        XCTAssertEqual(saved.assigned(to: kai).map(\.id), [notes.id])
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
                                   profiles: HarnessProfilesController(store: repository.harnessProfiles), service: Self.service(), port: 0)
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

/// A Keychain with no sign-ins, that takes none.
private final class NoPersonalCredentials: MCPCredentialStorage, @unchecked Sendable {
    func load(_ id: UUID) throws -> MCPCredentials? { nil }
    func save(_ credentials: MCPCredentials, id: UUID) { XCTFail("These tests must never authorize an account") }
    func remove(_ id: UUID) throws {}
}
