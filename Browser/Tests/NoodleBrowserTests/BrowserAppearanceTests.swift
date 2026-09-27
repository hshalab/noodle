import AppKit
import BrowserCore
@testable import NoodleBrowser
import SwiftUI
import XCTest

/// Browser's windows and sheets follow the system's light or dark appearance.
@MainActor final class BrowserAppearanceTests: XCTestCase {
    func testTheBrowserFormFollowsALightAppearance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BrowserLibrary(root: root)
        let presentation = BrowserPresentation(library: library, runtime: BrowserRuntime(library: library), defaults: nil)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        defer { window.contentView = nil; window.close() }
        let host = NSHostingView(rootView: BrowserProfileEditor(presentation: presentation))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua, "the form forced a dark appearance")
    }
}
