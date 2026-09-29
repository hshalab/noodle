#if os(macOS)
import AppKit

/// Delivers what a person did to a surface into the view that draws it, as real mouse, key and
/// scroll events. Keep one per surface: a press and its release go to the same view.
@MainActor public final class SurfaceEventInjector {
    private let view: NSView
    private var pressed: NSView?
    private var eventNumber = 0
    /// Holds the view when nothing on screen shows it, since events need a window.
    private var host: NSPanel?

    public init(view: NSView) { self.view = view }

    /// `input` points are in the view's bounds, from its top-left corner.
    public func deliver(_ input: SurfaceInput) throws {
        let window = try window()
        switch input {
        case .pointer(let phase, let x, let y, let count):
            let types: [SurfaceInput.Phase: NSEvent.EventType] = [.move: .mouseMoved, .down: .leftMouseDown, .drag: .leftMouseDragged, .up: .leftMouseUp]
            let location = locationInWindow(x: x, y: y)
            eventNumber += 1
            guard let type = types[phase],
                  let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber,
                                                 clickCount: phase == .move ? 0 : count, pressure: phase == .down ? 1 : 0) else { return }
            let target = pressed ?? target(at: location)
            switch phase {
            case .move: target.mouseMoved(with: event)
            case .down: window.makeFirstResponder(target); pressed = target; target.mouseDown(with: event)
            case .drag: target.mouseDragged(with: event)
            case .up: pressed = nil; target.mouseUp(with: event)
            }
        case .scroll(let x, let y, let dx, let dy):
            guard let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                       wheel1: Int32(-dy.rounded()), wheel2: Int32(-dx.rounded()), wheel3: 0) else { return }
            let location = locationInWindow(x: x, y: y)
            scroll.location = CGPoint(x: window.frame.minX + location.x, y: window.frame.minY + location.y)
            guard let event = NSEvent(cgEvent: scroll) else { return }
            target(at: location).scrollWheel(with: event)
        case .key(let key):
            if let (characters, code) = Self.keys[key.rawValue] { type(characters, keyCode: code, in: window) }
        case .text(let text):
            for character in text { type(String(character), keyCode: 0, in: window) }
        case .hold(let key, let pressed):
            if let (characters, code) = Self.keys[key] { type(characters, keyCode: code, in: window, as: pressed ? [.keyDown] : [.keyUp]) }
        }
    }

    /// Characters and virtual key codes of the keys a live view presses by name.
    private static let keys: [String: (String, UInt16)] = {
        var keys: [String: (String, UInt16)] = [
            "enter": ("\r", 36), "tab": ("\t", 48), "escape": ("\u{1b}", 53), "backspace": ("\u{7f}", 51), "space": (" ", 49),
            "left": ("\u{f702}", 123), "right": ("\u{f703}", 124), "down": ("\u{f701}", 125), "up": ("\u{f700}", 126),
        ]
        let codes: [Character: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14,
            "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
            "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        ]
        for (character, code) in codes { keys[String(character)] = (String(character), code) }
        return keys
    }()

    private func window() throws -> NSWindow {
        if let window = view.window { return window }
        let panel = host ?? NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        host = panel
        return panel
    }

    private func locationInWindow(x: Double, y: Double) -> NSPoint {
        let local = view.isFlipped ? NSPoint(x: x, y: y) : NSPoint(x: x, y: view.bounds.height - y)
        return view.convert(local, to: nil)
    }

    private func target(at location: NSPoint) -> NSView {
        guard let superview = view.superview else { return view }
        let hit = view.hitTest(superview.convert(location, from: nil))
        return hit.flatMap { $0 === view || $0.isDescendant(of: view) ? $0 : nil } ?? view
    }

    private func type(_ characters: String, keyCode: UInt16, in window: NSWindow, as types: [NSEvent.EventType] = [.keyDown, .keyUp]) {
        let responder: NSResponder = (window.firstResponder as? NSView).flatMap { $0 === view || $0.isDescendant(of: view) ? $0 : nil } ?? view
        if responder === view { window.makeFirstResponder(view) }
        for type in types {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil, characters: characters,
                                               charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode) else { continue }
            if type == .keyDown { responder.keyDown(with: event) } else { responder.keyUp(with: event) }
        }
    }
}
#endif
