import HubLink
import SwiftUI
import UIKit

@main
struct NoodleMobileApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @Environment(\.scenePhase) private var phase
    @State private var notifications = HubNotifications()
    @State private var hubs: HubMemberships
    @AppStorage(CurrentHub.key) private var current = ""
    @AppStorage(CurrentHub.togetherKey) private var together = false

    init() {
        let own = URL.applicationSupportDirectory.appendingPathComponent("Hubs", isDirectory: true)
        let shared = AppGroup.hubs ?? own
        AppGroup.moveHubs(from: own, to: shared)
        _hubs = State(initialValue: HubMemberships(directory: shared, deviceName: UIDevice.current.name))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                let shown = CurrentHub.shown(hubs.hubs, saved: current, together: together)
                if shown.isEmpty {
                    JoinView()
                } else {
                    AgentsView(pairings: shown, opening: Binding(get: { delegate.opening }, set: { delegate.opening = $0 }))
                }
            }
            .environment(hubs)
            // An invitation link opened from Messages, Mail or a QR code in the Camera app.
            .onOpenURL { url in hubs.offer(url.absoluteString) }
            .alert("Join this Hub?", isPresented: Binding(get: { hubs.offered != nil }, set: { if !$0 { hubs.declineOffered() } }),
                   presenting: hubs.offered) { invitation in
                Button("Cancel", role: .cancel) {}
                Button("Join") { Task { await hubs.join(invitation.url().absoluteString) } }
            } message: { invitation in
                Text("Hub key \(invitation.hubKey.fingerprint)")
            }
            .onChange(of: hubs.hubs.map(CurrentHub.name)) { before, after in
                if let joined = CurrentHub.joined(before: before, after: after) { current = joined }
            }
            .task { await hubs.stayConnected() }
            // Again each time the app comes back, since notifications may have been turned off or on in Settings.
            .task(id: NotificationKey(hubs: hubs.hubs.map(CurrentHub.name), active: phase == .active)) {
                guard phase == .active else { return }
                // Nobody is asked until there is a Hub to hear from.
                let allowed = hubs.hubs.isEmpty ? true : await HubNotifications.allowed(registering: delegate)
                await notifications.register(hubs.hubs, allowed: allowed)
            }
            // A tapped notification's Hub is shown, so its conversation can open.
            .onChange(of: delegate.opening) {
                guard let route = delegate.opening, !together,
                      let pairing = hubs.hubs.first(where: { PushTopic.topic(for: $0) == route.topic }) else { return }
                current = CurrentHub.name(of: pairing)
            }
        }
    }
}

private struct NotificationKey: Equatable {
    let hubs: [String]
    let active: Bool
}

/// The Hub the phone shows, of those it joined; saved on the phone by the name of the Hub's folder.
@MainActor enum CurrentHub {
    static let key = "currentHub"
    /// Whether every Hub's bots show in one list, rather than one Hub's at a time.
    static let togetherKey = "hubsTogether"

    static func name(of pairing: HubPairing) -> String { pairing.directory.lastPathComponent }

    static func pick(_ hubs: [HubPairing], saved: String) -> HubPairing? {
        hubs.first { name(of: $0) == saved } ?? hubs.first
    }

    static func shown(_ hubs: [HubPairing], saved: String, together: Bool) -> [HubPairing] {
        together ? hubs : pick(hubs, saved: saved).map { [$0] } ?? []
    }

    /// A Hub just joined, which the phone then shows.
    static func joined(before: [String], after: [String]) -> String? {
        after.first { !before.contains($0) }
    }
}
