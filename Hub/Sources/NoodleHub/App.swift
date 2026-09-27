import AppKit
import HubCore
import HubLink
import NoodleLaunchChecks
import NoodleRuntimeSettings
import SwiftUI

/// "Noodle Hub Dev" in development builds, so they are told apart from a released Hub running beside them.
let hubAppName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Noodle Hub"

/// Claims the app's single running copy before SwiftUI makes its delegate, which opens its data.
@main enum NoodleHubEntry {
    static func main() {
        AppInstance.claim()
        NoodleHubApp.main()
    }
}

struct NoodleHubApp: App {
    @NSApplicationDelegateAdaptor(HubDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            HubMenu(hub: delegate.settings.hub)
        } label: {
            HubMenuBarLabel(presence: delegate.presence)
        }
        Window("Usage", id: UsageView.windowID) {
            UsageView(history: delegate.settings.hub.usage, agents: delegate.settings.agents)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 860, height: 680)
        .windowResizability(.contentMinSize)
        Settings {
            HubSettingsView(host: delegate.settings)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
    }
}

/// The Hub lives in the menu bar only, never in the Dock or the app switcher.
@MainActor final class HubDelegate: NSObject, NSApplicationDelegate {
    let settings: HubSettingsHost = {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let messenger = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/messenger")
        // Development builds listen on their own port so they can run beside a released Hub.
        let port = (Bundle.main.object(forInfoDictionaryKey: "NoodleHubLinkPort") as? String).flatMap(UInt16.init)
        return HubSettingsHost(hub: Hub(root: Hub.root(applicationSupport: applicationSupport),
            messenger: FileManager.default.isExecutableFile(atPath: messenger.path) ? messenger : nil,
            linkPort: port ?? LinkEndpoint.defaultPort, router: SystemRouterPortMapper()))
    }()
    lazy var presence = HubPresence(link: settings.hub.link)

    /// Opened by a person rather than as a login item, so it shows Settings instead of only a menu bar icon.
    private var launchedByPerson = true

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedByPerson = event?.eventID != kAEOpenApplication
            || event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue != keyAELaunchedAsLogInItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        HubUpdater.shared.start()
        do { try settings.hub.bots.start() }
        catch { NSLog("Noodle Hub could not start its bots: \(error.localizedDescription)") }
        Task { await settings.hub.link.start() }
        presence.start()
        if launchedByPerson { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showSettings() }
        return true
    }

    /// SwiftUI refuses a direct `showSettingsWindow:` outside a view, so this goes through its own Settings menu item.
    private func showSettings() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard let menu = NSApp.mainMenu?.items.first?.submenu,
              let item = menu.items.firstIndex(where: { $0.keyEquivalent == "," }) else { return }
        menu.performActionForItem(at: item)
    }

    func applicationWillTerminate(_ notification: Notification) {
        settings.hub.link.stop()
        settings.hub.bots.stop()
    }
}

/// Whether anyone is connected, rechecked on a timer because presence lapses without an event.
@MainActor @Observable final class HubPresence {
    private(set) var connected = false
    private let link: HubLinkService
    private var timer: Timer?

    init(link: HubLinkService) { self.link = link }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        let connected = !link.connectedDevices.isEmpty
        if connected != self.connected { self.connected = connected }
    }
}

/// The server symbol, with a green dot while someone is connected.
struct HubMenuBarLabel: View {
    let presence: HubPresence

    var body: some View {
        if presence.connected {
            Image(nsImage: Self.connectedImage).accessibilityLabel("\(hubAppName), connected")
        } else {
            Image(systemName: "server.rack").accessibilityLabel(hubAppName)
        }
    }

    // A template image loses the dot's colour, so the symbol is tinted at draw time to follow the menu bar.
    private static let connectedImage: NSImage = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let symbol = NSImage(systemSymbolName: "server.rack", accessibilityDescription: nil)!
            .withSymbolConfiguration(configuration)!
        let dot: CGFloat = 6
        let size = NSSize(width: symbol.size.width + dot / 2, height: max(symbol.size.height, 16))
        let image = NSImage(size: size, flipped: false) { _ in
            let symbolRect = NSRect(x: 0, y: (size.height - symbol.size.height) / 2,
                                    width: symbol.size.width, height: symbol.size.height)
            let tinted = NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                NSColor.labelColor.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: symbolRect)
            let dotRect = NSRect(x: size.width - dot, y: 0, width: dot, height: dot)
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }()
}

struct HubMenu: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    let hub: Hub

    var body: some View {
        Button("Usage…") {
            hub.usage.agentFilter = nil
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: UsageView.windowID)
        }
        .keyboardShortcut("u", modifiers: [.command, .shift])
        Button("Settings…") {
            // A menu bar app is never frontmost on its own, and cooperative activation leaves it behind.
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit \(hubAppName)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
