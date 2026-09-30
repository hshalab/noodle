import AppletCore
import AppKit
import XCTest

@testable import NoodleApplet

/// Playing a noodlet on a TV takes its window full screen on that display, which a fixed-size
/// or floating window cannot do; bringing it back must leave the window as the manifest made it.
final class CastTests: XCTestCase {
    @MainActor private func makeRunner(window: String) throws -> (WebRunner, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = #"{"version":1,"title":"Game","runtime":"html","entry":"index.html","window":\#(window)}"#
        let package = try NoodletPackage.install([
            "noodlet.json": Data(manifest.utf8),
            "index.html": Data("<title>Game</title>".utf8),
        ], to: root.appendingPathComponent("Game.noodlet"))
        let runner = WebRunner(
            package: package, dataRoot: root, log: AppletLog(url: root.appendingPathComponent("log.txt")),
            size: CGSize(width: 320, height: 240), storeID: UUID(), rememberFrame: false)
        return (runner, root)
    }

    @MainActor func testCastingLiftsTheLimitsAndBringingBackRestoresThem() throws {
        let (runner, root) = try makeRunner(
            window: #"{"type":"floating","resizable":false,"maxWidth":400,"maxHeight":300}"#)
        defer { try? FileManager.default.removeItem(at: root) }
        defer { runner.stop() }
        let window = runner.window
        let frame = window.frame
        let cast = NoodletCast(window)
        var changes = 0
        cast.changed = { changes += 1 }
        XCTAssertTrue(cast.canCast)

        cast.lift(onto: try XCTUnwrap(NSScreen.screens.last))
        XCTAssertTrue(cast.isCasting)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertGreaterThan(window.contentMaxSize.width, 10_000)
        XCTAssertEqual(window.level, .normal)
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenAuxiliary))

        window.setFrame(CGRect(x: 0, y: 0, width: 900, height: 700), display: false)
        cast.bringBack()
        XCTAssertFalse(cast.isCasting)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.contentMaxSize, CGSize(width: 400, height: 300))
        XCTAssertEqual(window.level, .floating)
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertEqual(window.frame, frame)
        XCTAssertEqual(changes, 2)
    }

    /// A fixed-size game keeps its own size on the TV: scaled up as far as it fits without
    /// stretching and centred. A resizable one takes the whole screen and adapts itself.
    @MainActor func testAFixedSizeNoodletScalesToFitWhileAResizableOneFills() throws {
        let (fixed, fixedRoot) = try makeRunner(window: #"{"type":"standard","resizable":false}"#)
        defer { try? FileManager.default.removeItem(at: fixedRoot) }
        defer { fixed.stop() }
        let cast = NoodletCast(fixed.window)
        fixed.window.makeFirstResponder(fixed.web)
        cast.lift(onto: try XCTUnwrap(NSScreen.screens.first))
        fixed.window.setContentSize(CGSize(width: 800, height: 480))
        XCTAssertEqual(fixed.web.bounds.size, CGSize(width: 320, height: 240))
        XCTAssertEqual(fixed.web.convert(fixed.web.bounds, to: nil), CGRect(x: 80, y: 0, width: 640, height: 480))
        XCTAssertTrue(fixed.window.firstResponder === fixed.web)
        cast.bringBack()
        XCTAssertTrue(fixed.window.contentView === fixed.web)
        XCTAssertEqual(fixed.web.frame.size, CGSize(width: 320, height: 240))
        XCTAssertTrue(fixed.window.firstResponder === fixed.web)

        let (dynamic, dynamicRoot) = try makeRunner(window: #"{"type":"standard"}"#)
        defer { try? FileManager.default.removeItem(at: dynamicRoot) }
        defer { dynamic.stop() }
        let fill = NoodletCast(dynamic.window)
        fill.lift(onto: try XCTUnwrap(NSScreen.screens.first))
        dynamic.window.setContentSize(CGSize(width: 800, height: 480))
        XCTAssertTrue(dynamic.window.contentView === dynamic.web)
        XCTAssertEqual(dynamic.web.frame.size, CGSize(width: 800, height: 480))
    }

    /// A quick-look panel is not something to play on a TV.
    @MainActor func testPreviewPanelsCannotBeCast() throws {
        let (web, webRoot) = try makeRunner(window: #"{"type":"preview"}"#)
        defer { try? FileManager.default.removeItem(at: webRoot) }
        defer { web.stop() }
        XCTAssertFalse(web.canCast)
    }
}
