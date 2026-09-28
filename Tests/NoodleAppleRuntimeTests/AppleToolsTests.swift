import XCTest
import FoundationModels
import NoodleCore
@testable import NoodleAppleRuntime

final class AppleToolsTests: XCTestCase {
    private var root: URL!
    private var repository: WorkspaceRepository!
    private var workspace: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("apple-tools-\(UUID())").resolvingSymlinksInPath()
        repository = WorkspaceRepository(rootURL: root)
        let bot = try repository.createAgent(named: "Apple test")
        workspace = repository.directory(for: bot.agent)
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent(".noodle/tmp"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testReadWriteAndPaginationPreserveFullOutput() async throws {
        let tools = try AppleToolContext(workspace: workspace)
        let content = String(repeating: "abcdef", count: 1_000)
        _ = try await tools.write(path: "sample.txt", content: content)
        let first = try await tools.read(path: "sample.txt")
        let next = try await tools.read(path: "sample.txt", offset: 3_072)
        XCTAssertTrue(first.contains("offset 3072"))
        XCTAssertTrue(next.contains("; end"))
        XCTAssertEqual(try String(contentsOf: workspace.appendingPathComponent("sample.txt"), encoding: .utf8), content)
    }

    func testCommandReturnsExitCodeAndUsesWorkspace() async throws {
        let result = try await AppleCommand.run("[[ -n $BASH_VERSION ]] || exit 9; pwd; printf expected; exit 7", workspace: workspace)
        XCTAssertEqual(result.status, 7)
        XCTAssertTrue(result.output.contains(workspace.path))
        XCTAssertTrue(result.output.hasSuffix("expected"))
    }

    func testContextOverflowDoesNotMaskCancellationRefusalOrServiceErrors() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Requires Foundation Models") }
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "synthetic")
        XCTAssertTrue(AppleContextOverflow.matches(AppleContextLimit()))
        XCTAssertTrue(AppleContextOverflow.matches(LanguageModelSession.GenerationError.exceededContextWindowSize(context)))
        XCTAssertTrue(AppleContextOverflow.matches(NSError(domain: "TokenGenerationInference.DecoderModelError", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Provided 4,130 tokens, but the maximum allowed is 4,096."])))
        XCTAssertFalse(AppleContextOverflow.matches(CancellationError()))
        XCTAssertFalse(AppleContextOverflow.matches(LanguageModelSession.GenerationError.guardrailViolation(context)))
        XCTAssertFalse(AppleContextOverflow.matches(LanguageModelSession.GenerationError.rateLimited(context)))
        XCTAssertFalse(AppleContextOverflow.matches(NSError(domain: "UnrelatedService", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Provided 4,130 tokens, but the maximum allowed is 4,096."])))
    }

    func testReadPagesDoNotSplitUTF8Characters() async throws {
        let tools = try AppleToolContext(workspace: workspace)
        _ = try await tools.write(path: "unicode.txt", content: String(repeating: "a", count: 3_071) + "🍎done")
        let first = try await tools.read(path: "unicode.txt")
        XCTAssertTrue(first.contains("offset 3071"))
        let next = try await tools.read(path: "unicode.txt", offset: 3_071)
        XCTAssertTrue(next.hasPrefix("🍎done"))
    }

    func testCommandOutputKeepsItsEndWhereErrorsAppear() async throws {
        let tools = try AppleToolContext(workspace: workspace)
        let output = try await tools.execute(command: "seq 1 5000; echo 'error: final failure'")
        XCTAssertTrue(output.contains("Exit status: 0\n1\n2\n"))
        XCTAssertTrue(output.contains("error: final failure"), "The end of a long command's output must reach the model")
        XCTAssertTrue(output.contains("[Full result saved at "))
    }

    func testToolCallsAreBoundedByTheTurnNotTheToolContext() async throws {
        let tools = try AppleToolContext(workspace: workspace)
        _ = try await tools.write(path: "note.txt", content: "saffron")
        for _ in 0..<40 { _ = try await tools.read(path: "note.txt") }
    }

    func testEditReplacesOneExactPassage() async throws {
        let tools = try AppleToolContext(workspace: workspace)
        _ = try await tools.write(path: "notes.txt", content: "alpha\nbeta\nalpha\n")
        _ = try await tools.edit(path: "notes.txt", old: "beta", new: "gamma")
        XCTAssertEqual(try String(contentsOf: workspace.appendingPathComponent("notes.txt"), encoding: .utf8), "alpha\ngamma\nalpha\n")
        for (old, reason) in [("alpha", "2 times"), ("delta", "not in")] {
            do {
                _ = try await tools.edit(path: "notes.txt", old: old, new: "x")
                XCTFail("An ambiguous or missing passage must not change the file")
            } catch { XCTAssertTrue(error.localizedDescription.contains(reason), error.localizedDescription) }
        }
        XCTAssertEqual(try String(contentsOf: workspace.appendingPathComponent("notes.txt"), encoding: .utf8), "alpha\ngamma\nalpha\n")
    }

    func testWriteAppendsSoLongFilesCanBeWrittenInParts() async throws {
        let tools = try AppleToolContext(workspace: workspace)
        _ = try await tools.write(path: "long.txt", content: "part one\n", append: true)
        _ = try await tools.write(path: "long.txt", content: "part two\n", append: true)
        XCTAssertEqual(try String(contentsOf: workspace.appendingPathComponent("long.txt"), encoding: .utf8), "part one\npart two\n")
    }

    func testPagesFollowTheModelContext() async throws {
        let small = try AppleToolContext(workspace: workspace)
        let large = try AppleToolContext(workspace: workspace, pageBytes: 16_384)
        _ = try await small.write(path: "big.txt", content: String(repeating: "a", count: 20_000))
        let smallPage = try await small.read(path: "big.txt")
        let largePage = try await large.read(path: "big.txt")
        XCTAssertTrue(smallPage.contains("offset 3072"))
        XCTAssertTrue(largePage.contains("offset 16384"))
    }

    func testOnlyImageFilesOpenAsImages() async throws {
        let tools = try AppleToolContext(workspace: workspace)
        try Data("not text".utf8).write(to: workspace.appendingPathComponent("photo.png"))
        _ = try await tools.write(path: "notes.txt", content: "text")
        let image = try await tools.image(path: "photo.png")
        let text = try await tools.image(path: "notes.txt")
        let missing = try await tools.image(path: "absent.png")
        XCTAssertEqual(image?.lastPathComponent, "photo.png")
        XCTAssertNil(text)
        XCTAssertNil(missing)
    }

    func testCommandTimeoutKillsItsDescendants() async throws {
        do {
            _ = try await AppleCommand.run("(sleep 1; touch late.txt) & wait", workspace: workspace, timeout: 0.1)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("time limit")) }
        try await Task.sleep(for: .milliseconds(1_100))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("late.txt").path))
    }

    func testCancellationStopsCommand() async throws {
        let task = Task { try await AppleCommand.run("sleep 30", workspace: workspace) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
    }
}
