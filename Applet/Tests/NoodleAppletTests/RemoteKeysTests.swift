import AppKit
import AppletBridge
import AppletCore
import Surface
import WebKit
import XCTest

@testable import NoodleApplet

/// Keys from someone playing on another device go straight into the noodlet's page. Sent as Mac
/// key events they went through the Mac's text input, which serves whichever window is active:
/// they moved the library's selection, opened the emoji picker and beeped.
@MainActor final class RemoteKeysTests: XCTestCase {
    private func open() async throws -> (AppletRuntime, AppletSession) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "RemoteKeys." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let library = botLibrary(root: root, defaults: defaults)
        let runtime = AppletRuntime(library: library, defaults: defaults)
        let page = """
            <title>Keys</title><input id="name">
            <script>window.seen=[];for(const t of ['keydown','keyup'])addEventListener(t,e=>seen.push(`${e.type} ${e.key} ${e.code} ${e.keyCode}`))</script>
            """
        var validate = AppletRequest(.validate)
        validate.path = try botNoodlet(["noodlet.json": try JSONEncoder().encode(NoodletManifest(title: "Keys")), "index.html": Data(page.utf8)],
                                       named: "Keys", owner: "author", root: library.root)
        validate.owner = "author"
        let installed = try await runtime.handle(validate, identity: AppletBuildIdentity.current.noodleID).checked()
        var request = AppletRequest(.open)
        request.path = try library.package(for: try XCTUnwrap(installed.noodletID)).url.path
        request.owner = "author"
        request.mode = "background"
        let response = try await runtime.handle(request, identity: AppletBuildIdentity.current.noodleID).checked()
        let session = try XCTUnwrap(runtime.sessions[try XCTUnwrap(response.sessionID)])
        for _ in 0..<100 where session.web?.web.isLoading != false { try await Task.sleep(for: .milliseconds(20)) }
        return (runtime, session)
    }

    func testRemoteKeysReachThePageWithoutTheMacsKeyboard() async throws {
        // Someone at the Mac typing in another window, which the Mac's text input serves.
        let front = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        front.isReleasedWhenClosed = false
        addTeardownBlock { front.orderOut(nil) }
        let field = NSTextView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        front.contentView?.addSubview(field)
        front.makeKeyAndOrderFront(nil)
        XCTAssertTrue(front.makeFirstResponder(field))

        let (runtime, session) = try await open()
        let web = try XCTUnwrap(session.web)
        for input: SurfaceInput in [.hold(key: "space", pressed: true), .hold(key: "space", pressed: false), .hold(key: "left", pressed: true),
                                    .hold(key: "z", pressed: true), .hold(key: "7", pressed: false), .key(.escape)] {
            try await runtime.deliver(input, to: session)
        }
        let seen = try await web.evaluate("return seen")
        XCTAssertEqual(seen, #"["keydown   Space 32","keyup   Space 32","keydown ArrowLeft ArrowLeft 37","keydown z KeyZ 90","keyup 7 Digit7 55","keydown Escape Escape 27","keyup Escape Escape 27"]"#)

        _ = try await web.evaluate("document.getElementById('name').focus(); seen = []")
        try await runtime.deliver(.text("hi"), to: session)
        try await runtime.deliver(.key(.backspace), to: session)
        let value = try await web.evaluate("return document.getElementById('name').value")
        let first = try await web.evaluate("return seen[0]")
        XCTAssertEqual(value, #""h""#)
        XCTAssertEqual(first, #""keydown h KeyH 72""#)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(field.string, "", "a remote key landed in another window")
        XCTAssertEqual(field.selectedRange(), NSRange(location: 0, length: 0), "a remote arrow moved another window's cursor")
    }
}
