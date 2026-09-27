import AppKit
import HubCore
import HubLink
import NoodleBrand
import NoodleRuntimeSettings
import SwiftUI

/// The first launch: the wordmark writes itself, as in Noodle, and Continue brings up pairing
/// the first device in its place.
struct HubWelcomeView: View {
    static let windowID = "welcome"
    static let shownKey = "HubWelcomeShown"

    /// Once, and only for a Hub nobody has paired with yet, such as one from before the welcome.
    static func isNeeded(_ hub: Hub, defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: shownKey) && hub.access.devices.isEmpty
    }

    let hub: Hub

    var body: some View {
        WordmarkWelcome {
            HubPairView(hub: hub, placement: .welcome)
        }
        .frame(minWidth: 560, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { UserDefaults.standard.set(true, forKey: Self.shownKey) }
    }
}

/// Pairs a new device with the Hub: whom it is for, then the invitation it joins with.
struct HubPairView: View {
    static let windowID = "pair"

    /// Its own window, or the steps the welcome brings up under the wordmark.
    enum Placement { case window, welcome }

    let hub: Hub
    var placement = Placement.window
    @Environment(\.dismiss) private var dismiss
    @State private var userID: HubUser.ID?
    @State private var invitation: LinkInvitation?
    @State private var name = NSFullUserName()
    @State private var error: String?

    private var access: HubAccess { hub.access }
    private var user: HubUser? { access.users.first { $0.id == userID } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text("Pair a Device").font(.title2.bold())
                if let user, let invitation {
                    if access.users.count > 1 {
                        Picker("For", selection: $userID) {
                            ForEach(access.users) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .fixedSize()
                    }
                    HubInvitationView(access: access, user: user, invitation: invitation) {
                        self.invitation = hub.link.invite(user)
                    }
                    .id(invitation.joinKey)
                } else {
                    TextField("User Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                        .onSubmit(addUser)
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(24)
            Divider()
            HStack {
                Spacer()
                if user == nil {
                    Button("Continue", action: addUser)
                        .keyboardShortcut(.defaultAction)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            if placement == .welcome {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial)
            }
        }
        .onAppear { if userID == nil { userID = access.users.first?.id } }
        .onChange(of: userID, initial: true) { _, _ in invitation = user.map(hub.link.invite) }
    }

    /// A Hub with nobody on it yet gets its first user, named here, for the device to join as.
    private func addUser() {
        do {
            userID = try access.addUser(named: name.trimmingCharacters(in: .whitespaces)).id
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
