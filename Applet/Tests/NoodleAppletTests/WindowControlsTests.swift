import AppKit
import AppletCore
import ObjectiveC
import WebKit
import XCTest

@testable import NoodleApplet

/// A noodlet that draws its own title bar hides the native buttons and acts through noodle.window.
final class WindowControlsTests: XCTestCase {
    @MainActor private func window(titlebar: String, extra: String = "") throws -> NSWindow {
        let options = try JSONDecoder().decode(
            NoodletWindowOptions.self, from: Data(#"{"titlebar":\#(titlebar)\#(extra)}"#.utf8))
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

    /// macOS rounds only titled windows, so a set radius drops the title bar and shapes the content.
    @MainActor func testSquareCornersDropTheTitleBarButKeepFocusAndActions() throws {
        let window = try window(titlebar: #""none""#, extra: #","cornerRadius":0"#)
        XCTAssertFalse(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.isSuperset(of: [.closable, .miniaturizable, .resizable]))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.canBecomeMain)
        XCTAssertTrue(window.isOpaque)
    }

    @MainActor func testARoundedRadiusClipsTheContent() throws {
        let window = try window(titlebar: #""none""#, extra: #","cornerRadius":12"#)
        XCTAssertFalse(window.styleMask.contains(.titled))
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        let layer = try XCTUnwrap(window.contentView?.layer)
        XCTAssertEqual(layer.cornerRadius, 12)
        XCTAssertTrue(layer.masksToBounds)
    }

    @MainActor func testARoundedTranslucentWindowMasksItsMaterial() throws {
        let window = try window(titlebar: #""none""#, extra: #","cornerRadius":12,"background":"translucent""#)
        let effect = try XCTUnwrap(window.contentView?.subviews.first as? NSVisualEffectView)
        XCTAssertNotNil(effect.maskImage)
    }

    /// WebKit hands a key the page did not cancel back up to the window, where AppKit beeps. A game
    /// reading the arrow keys without preventDefault beeped on every press; the page had the key.
    @MainActor func testKeysAPageLeftUnhandledDoNotBeep() throws {
        let original = try XCTUnwrap(class_getInstanceMethod(NSResponder.self, #selector(NSResponder.noResponder(for:))))
        let recording = try XCTUnwrap(class_getInstanceMethod(NSResponder.self, #selector(NSResponder.recordingNoResponder(for:))))
        method_exchangeImplementations(original, recording)
        defer { method_exchangeImplementations(original, recording) }
        let keyDown = #selector(NSResponder.keyDown(with:))
        for extra in ["", #","cornerRadius":12"#, #","type":"preview""#] {
            let window = try window(titlebar: "true", extra: extra)
            let page = WKWebView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            let field = NSTextView()
            window.contentView?.addSubview(page)
            window.contentView?.addSubview(field)
            unhandledKeys = 0
            XCTAssertTrue(window.makeFirstResponder(page), extra)
            window.noResponder(for: keyDown)
            XCTAssertEqual(unhandledKeys, 0, "a key the page had beeped\(extra)")

            // Anything else in the window still says when nothing took a key.
            XCTAssertTrue(window.makeFirstResponder(field), extra)
            window.noResponder(for: keyDown)
            XCTAssertEqual(unhandledKeys, 1, extra)
        }
    }
}

@MainActor private var unhandledKeys = 0
extension NSResponder {
    /// Stands in for AppKit's beep while the test runs.
    @MainActor @objc fileprivate func recordingNoResponder(for selector: Selector) {
        if selector == #selector(NSResponder.keyDown(with:)) { unhandledKeys += 1 }
    }
}
