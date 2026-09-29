import AppKit
import AppletCore
import XCTest

@testable import NoodleApplet

/// A noodlet that draws its own title bar hides the native buttons and acts through noodle.window.
final class WindowControlsTests: XCTestCase {
    @MainActor private func window(titlebar: String) throws -> NSWindow {
        let options = try JSONDecoder().decode(
            NoodletWindowOptions.self, from: Data(#"{"titlebar":\#(titlebar)}"#.utf8))
        let window = WindowPresentation.make(options, size: options.size())
        WindowPresentation.apply(options, to: window, content: NSView(), size: options.size(), key: "", remember: false)
        return window
    }

    @MainActor private func buttons(_ window: NSWindow) -> [NSButton] {
        [.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
    }

    @MainActor func testNoTitlebarHidesTheNativeButtonsButKeepsTheirActions() throws {
        let window = try window(titlebar: #""none""#)
        XCTAssertEqual(buttons(window).count, 3)
        XCTAssertTrue(buttons(window).allSatisfy(\.isHidden))
        XCTAssertTrue(window.styleMask.isSuperset(of: [.closable, .miniaturizable, .resizable]))
        XCTAssertEqual(window.titleVisibility, .hidden)
    }

    @MainActor func testAHiddenTitlebarKeepsTheNativeButtons() throws {
        let window = try window(titlebar: "false")
        XCTAssertEqual(buttons(window).count, 3)
        XCTAssertFalse(buttons(window).contains(where: \.isHidden))
    }

    @MainActor func testWindowActionsOnlyActOnScreen() throws {
        let window = try window(titlebar: #""none""#)
        for action in ["close", "minimize", "zoom", "toggleFullScreen"] {
            XCTAssertFalse(try WindowPresentation.perform(action, on: window), action)
        }
        XCTAssertThrowsError(try WindowPresentation.perform("maximize", on: window))
    }
}
