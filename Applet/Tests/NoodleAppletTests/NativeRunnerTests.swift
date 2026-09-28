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
}
