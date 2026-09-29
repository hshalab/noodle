import AppletBridge
import XCTest
@testable import NoodleApplet

final class NativeRunnerTests: XCTestCase {
    private func toolchain(platformPlugins: Bool) throws -> (root: URL, compiler: String, sdk: String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let developer = root.appendingPathComponent("Platform/Developer")
        for directory in ["Toolchain/usr/bin", "Toolchain/usr/lib/swift/host/plugins", "Platform/Developer/SDKs/MacOSX.sdk"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        if platformPlugins {
            for directory in ["usr/bin", "usr/lib/swift/host/plugins"] {
                try FileManager.default.createDirectory(at: developer.appendingPathComponent(directory), withIntermediateDirectories: true)
            }
            let server = developer.appendingPathComponent("usr/bin/swift-plugin-server")
            try Data().write(to: server)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: server.path)
        }
        return (root, root.appendingPathComponent("Toolchain/usr/bin/swiftc").path, developer.appendingPathComponent("SDKs/MacOSX.sdk").path)
    }

    func testPluginArgumentsIncludeToolchainAndPlatformMacros() throws {
        let fixture = try toolchain(platformPlugins: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let developer = fixture.root.appendingPathComponent("Platform/Developer").path
        XCTAssertEqual(NativeRunner.pluginArguments(compiler: fixture.compiler, sdk: fixture.sdk), [
            "-plugin-path", fixture.root.appendingPathComponent("Toolchain/usr/lib/swift/host/plugins").path,
            "-disable-sandbox", "-external-plugin-path", "\(developer)/usr/lib/swift/host/plugins#\(developer)/usr/bin/swift-plugin-server",
        ])
    }

    func testPluginArgumentsOmitPlatformMacrosWithoutPluginServer() throws {
        let fixture = try toolchain(platformPlugins: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        XCTAssertEqual(NativeRunner.pluginArguments(compiler: fixture.compiler, sdk: fixture.sdk), [
            "-plugin-path", fixture.root.appendingPathComponent("Toolchain/usr/lib/swift/host/plugins").path,
        ])
    }

    func testWarmUpImportsNameModulesOnly() {
        let source = """
            import SwiftUI
            @preconcurrency import AVFoundation; import Vision
              import struct Foundation.URL
            import Darwin.C
            // import Commented
            let imported = "import Fake"
            import Bad-Name
            """
        XCTAssertEqual(NativeRunner.imports(source), ["AVFoundation", "Darwin", "Foundation", "SwiftUI", "Vision"])
    }

    /// A live view reads the pixels a native noodlet drew as they are, without a picture format
    /// between, and only from the plain file the noodlet was given.
    func testALiveFrameIsReadAsTheNoodletDrewIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let frame = root.appendingPathComponent(".live-frame")
        // Two rows of three pixels, each row padded to 16 bytes.
        var bytes = [UInt8](repeating: 0, count: 32)
        for pixel in 0..<3 { bytes.replaceSubrange(pixel * 4..<pixel * 4 + 4, with: [255, 0, 0, 255]) }
        for pixel in 0..<3 { bytes.replaceSubrange(16 + pixel * 4..<16 + pixel * 4 + 4, with: [0, 0, 255, 255]) }
        try Data(bytes).write(to: frame)
        let reply = #"{"width":3,"height":2,"bytesPerRow":16,"alphaFirst":false,"littleEndian":false}"#
        let image = try NativeRunner.liveFrame(reply, in: root)
        XCTAssertEqual(image.width, 3)
        XCTAssertEqual(image.height, 2)
        XCTAssertEqual(image.alphaInfo, .premultipliedLast)
        XCTAssertEqual(image.dataProvider?.data as Data?, Data(bytes))

        let bgra = try NativeRunner.liveFrame(#"{"width":3,"height":2,"bytesPerRow":16,"alphaFirst":true,"littleEndian":true}"#, in: root)
        XCTAssertEqual(bgra.alphaInfo, .premultipliedFirst)
        XCTAssertTrue(bgra.bitmapInfo.contains(.byteOrder32Little))

        for (label, bad) in [("short rows", #"{"width":5,"height":2,"bytesPerRow":16,"alphaFirst":false,"littleEndian":false}"#),
                             ("more rows than written", #"{"width":3,"height":3,"bytesPerRow":16,"alphaFirst":false,"littleEndian":false}"#),
                             ("absurd size", #"{"width":100000,"height":100000,"bytesPerRow":400000,"alphaFirst":false,"littleEndian":false}"#)] {
            XCTAssertThrowsError(try NativeRunner.liveFrame(bad, in: root), label)
        }

        // A noodlet cannot have Applet read another file for it.
        let secret = root.appendingPathComponent("secret")
        try Data(bytes).write(to: secret)
        try FileManager.default.removeItem(at: frame)
        try FileManager.default.createSymbolicLink(at: frame, withDestinationURL: secret)
        XCTAssertThrowsError(try NativeRunner.liveFrame(reply, in: root), "followed a link")
    }

    /// A live view clicks a noodlet whose window is out of sight; SwiftUI controls must still act,
    /// and the window must stay hidden.
    func testSwiftUIControlsActWhileTheWindowIsHidden() throws {
        let lines = try runBackground("""
            import SwiftUI
            struct Noodlet: View {
                var body: some View {
                    VStack(spacing: 0) {
                        Button("Press") { print("pressed") }.frame(width: 200, height: 100)
                        Color.red.frame(width: 200, height: 100).onTapGesture { print("tapped") }
                        Color.blue.frame(width: 200, height: 100).gesture(DragGesture().onEnded { _ in print("dragged") })
                    }
                }
            }
            """) { send in
            // Points from the top left: the button, the tap area, then a drag across the blue area.
            XCTAssertNil(try send("button", ["operation": "click", "x": 100, "y": 50])["error"])
            XCTAssertNil(try send("tap", ["operation": "click", "x": 100, "y": 150])["error"])
            XCTAssertNil(try send("drag", ["operation": "drag", "x": 40, "y": 250, "toX": 160, "toY": 250])["error"])
            XCTAssertNotNil(try send("place", ["operation": "place"])["error"], "the window was shown")
        }
        XCTAssertEqual(lines, ["pressed", "tapped", "dragged"])
    }

    /// A noodlet that draws its own title bar has no native buttons, and its window actions
    /// do nothing while the window is out of sight.
    func testNoTitlebarHidesTheNativeButtons() throws {
        let lines = try runBackground("""
            import SwiftUI
            struct Noodlet: View {
                var body: some View {
                    Color.red.ignoresSafeArea().onTapGesture {
                        let window = NSApp.windows.first { $0.contentView != nil }!
                        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
                        print(buttons.count, buttons.allSatisfy { $0.isHidden })
                        print(NoodletContext.window.minimize(), NoodletContext.window.zoom(), NoodletContext.window.toggleFullScreen(), NoodletContext.window.close())
                    }
                }
            }
            """, window: #"{"titlebar":"none"}"#) { send in
            XCTAssertNil(try send("check", ["operation": "click", "x": 100, "y": 150])["error"])
        }
        XCTAssertEqual(lines, ["3 true", "false false false false"])
    }

    /// Square corners drop the title bar, and the window still takes the keyboard.
    func testSquareCornersDropTheTitleBar() throws {
        let lines = try runBackground("""
            import SwiftUI
            struct Noodlet: View {
                var body: some View {
                    Color.red.ignoresSafeArea().onTapGesture {
                        let window = NSApp.windows.first { $0.contentView != nil }!
                        print(window.styleMask.contains(.titled), window.canBecomeKey, window.collectionBehavior.contains(.fullScreenPrimary))
                    }
                }
            }
            """, window: #"{"titlebar":"none","cornerRadius":0}"#) { send in
            XCTAssertNil(try send("check", ["operation": "click", "x": 100, "y": 150])["error"])
        }
        XCTAssertEqual(lines, ["false true true"])
    }

    /// Keys from someone playing on another device reach a native game as a keyboard sends them:
    /// held until let go, with their key codes, typing without a text field arriving as keys, and
    /// a key the game ignores ending without a beep, since nobody at this Mac pressed it.
    func testRemoteKeysReachANativeGameAsAKeyboardSendsThem() throws {
        let lines = try runBackground("""
            import SwiftUI
            import ObjectiveC
            final class Keys: NSView {
                override var acceptsFirstResponder: Bool { true }
                override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
                private func log(_ kind: String, _ event: NSEvent) {
                    print(kind, event.keyCode, event.characters?.unicodeScalars.map { String($0.value) }.joined() ?? "")
                }
                override func keyDown(with event: NSEvent) { log("down", event); if event.keyCode == 53 { super.keyDown(with: event) } }
                override func keyUp(with event: NSEvent) { log("up", event) }
            }
            extension NSResponder { @objc func beeped(_ selector: Selector) { print("beep") } }
            struct KeysView: NSViewRepresentable {
                func makeNSView(context: Context) -> Keys {
                    method_exchangeImplementations(class_getInstanceMethod(NSResponder.self, #selector(NSResponder.noResponder(for:)))!,
                                                   class_getInstanceMethod(NSResponder.self, #selector(NSResponder.beeped(_:)))!)
                    return Keys()
                }
                func updateNSView(_ view: Keys, context: Context) {}
            }
            struct Noodlet: View { var body: some View { KeysView() } }
            """) { send in
            for (id, command) in [("space down", ["text": "space", "pressed": true]), ("space up", ["text": "space", "pressed": false]),
                                  ("left", ["text": "left", "pressed": true]), ("z", ["text": "z", "pressed": true]),
                                  ("7", ["text": "7", "pressed": false]), ("escape", ["text": "Escape"])] as [(String, [String: Any])] {
                XCTAssertNil(try send(id, command.merging(["operation": "key"]) { old, _ in old })["error"], id)
            }
            XCTAssertNil(try send("type", ["operation": "type", "text": "hi"])["error"])
        }
        XCTAssertEqual(lines, ["down 49 32", "up 49 32", "down 123 63234", "down 6 122", "up 26 55", "down 53 27", "up 53 27",
                               "down 4 104", "up 4 104", "down 34 105", "up 34 105"])
    }

    /// Builds `source` with the native runtime, runs it in background mode, which never orders
    /// the window in, and returns what it printed after `drive` sends it commands.
    private func runBackground(
        _ source: String, window: String? = nil,
        drive: (_ send: (String, [String: Any]) throws -> [String: Any]) throws -> Void
    ) throws -> [String] {
        guard let toolchain = try? NativeRunner.toolchain() else { throw XCTSkip("No Apple Swift compiler is installed.") }
        let compiler = URL(fileURLWithPath: toolchain.frontend).deletingLastPathComponent().appendingPathComponent("swiftc").path
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for folder in ["data", "package", "cache"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        try source.write(to: root.appendingPathComponent("Main.swift"), atomically: true, encoding: .utf8)
        let resources = AppletResources.bundle.url(forResource: "Resources", withExtension: nil)!
        let build = Process(), log = Pipe()
        build.executableURL = URL(fileURLWithPath: compiler)
        build.arguments = ["-Onone", "-parse-as-library", "-swift-version", "5", "-sdk", toolchain.sdk,
                           "-module-cache-path", root.appendingPathComponent("cache").path, "-o", root.appendingPathComponent("noodlet").path,
                           root.appendingPathComponent("Main.swift").path]
            + ["WindowFocusGuard.swift", "NoodletCast.swift", "NoodletRuntime.swift"].map { resources.appendingPathComponent($0).path }
        build.standardOutput = log; build.standardError = log
        try build.run()
        let diagnostics = String(decoding: log.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        build.waitUntilExit()
        XCTAssertEqual(build.terminationStatus, 0, diagnostics)
        guard build.terminationStatus == 0 else { return [] }

        let noodlet = Process(), input = Pipe(), output = Pipe()
        noodlet.executableURL = root.appendingPathComponent("noodlet")
        var environment = [
            "NOODLET_PROTOCOL": "P:", "NOODLET_MODE": "background", "NOODLET_WIDTH": "200", "NOODLET_HEIGHT": "300",
            "NOODLET_DATA": root.appendingPathComponent("data").path, "NOODLET_PACKAGE": root.appendingPathComponent("package").path,
        ]
        environment["NOODLET_WINDOW"] = window
        noodlet.environment = ProcessInfo.processInfo.environment.filter { ["PATH", "HOME", "TMPDIR"].contains($0.key) }
            .merging(environment) { _, new in new }
        noodlet.standardInput = input; noodlet.standardOutput = output; noodlet.standardError = FileHandle.nullDevice
        try noodlet.run()
        defer { if noodlet.isRunning { noodlet.terminate() } }
        // A noodlet that stops answering is ended, so the test fails instead of hanging.
        DispatchQueue.global().asyncAfter(deadline: .now() + 120) { if noodlet.isRunning { noodlet.terminate() } }
        let lines = LineReader(output.fileHandleForReading)
        func reply(_ id: String) throws -> [String: Any] {
            while let line = lines.next() {
                guard line.hasPrefix("P:"), let reply = try JSONSerialization.jsonObject(with: Data(line.dropFirst(2).utf8)) as? [String: Any],
                      reply["id"] as? String == id else { continue }
                return reply
            }
            throw AppletError("The noodlet ended before replying to \(id).")
        }
        _ = try reply("ready")
        try drive { id, command in
            input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: command.merging(["id": id]) { _, new in new }) + Data("\n".utf8))
            return try reply(id)
        }
        input.fileHandleForWriting.closeFile()
        while lines.next() != nil {}
        noodlet.waitUntilExit()
        return lines.seen.filter { !$0.hasPrefix("P:") }
    }
}

/// Lines from a pipe, blocking for each; ends when the writer does.
private final class LineReader {
    private let handle: FileHandle
    private var buffer = Data()
    private(set) var seen: [String] = []
    init(_ handle: FileHandle) { self.handle = handle }
    func next() -> String? {
        while true {
            if let end = buffer.firstIndex(of: 10) {
                let line = String(decoding: buffer[..<end], as: UTF8.self)
                buffer.removeSubrange(...end)
                seen.append(line)
                return line
            }
            let chunk = handle.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }
}
