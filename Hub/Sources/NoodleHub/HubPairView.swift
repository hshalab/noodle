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

/// Pairs a new device with the Hub: first whom it is for, an existing user or a new one, then
/// the invitation it joins with.
struct HubPairView: View {
    static let windowID = "pair"

    /// Its own window, or the steps the welcome brings up under the wordmark.
    enum Placement { case window, welcome }

    /// Whom the device is for.
    enum Choice: Hashable { case user(HubUser.ID), new }

    let hub: Hub
    var placement = Placement.window
    @Environment(\.dismiss) private var dismiss
    @State private var choice: Choice?
    @State private var user: HubUser?
    @State private var invitation: LinkInvitation?
    @State private var name = ""
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    private var access: HubAccess { hub.access }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var canContinue: Bool {
        switch choice {
        case .user: true
        case .new: !trimmedName.isEmpty
        case nil: false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                if let user, let invitation {
                    Text("Pair a Device for \(user.name)").font(.title2.bold())
                    HubInvitationView(access: access, user: user, invitation: invitation) {
                        self.invitation = hub.link.invite(user)
                    }
                    .id(invitation.joinKey)
                } else {
                    Text("Pair a Device").font(.title2.bold())
                    chooser
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
                if user != nil {
                    Button("Back") {
                        user = nil
                        invitation = nil
                    }
                }
                Spacer()
                if user == nil {
                    Button("Continue", action: next)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canContinue)
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
        .onAppear {
            guard choice == nil else { return }
            if let first = access.users.first {
                choice = .user(first.id)
            } else {
                choice = .new
                name = NSFullUserName()
            }
        }
    }

    /// The Hub's users to pick from, and a new one to name.
    private var chooser: some View {
        Picker("Who is it for?", selection: $choice) {
            ForEach(access.users) { user in
                Text(user.name).tag(Optional(Choice.user(user.id)))
            }
            HStack {
                Text("New User")
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($nameFocused)
                    .onSubmit(next)
            }
            .tag(Optional(Choice.new))
        }
        .pickerStyle(.radioGroup)
        .frame(width: 300, alignment: .leading)
        .onChange(of: nameFocused) { _, focused in if focused { choice = .new } }
        .onChange(of: choice) { _, choice in nameFocused = choice == .new }
    }

    /// Adds the new user if that is the choice, then brings up the invitation for whom it is for.
    private func next() {
        guard canContinue else { return }
        do {
            let chosen: HubUser
            switch choice {
            case .user(let id):
                guard let found = access.users.first(where: { $0.id == id }) else { return }
                chosen = found
            case .new:
                chosen = try access.addUser(named: trimmedName)
                choice = .user(chosen.id)
                name = ""
            case nil:
                return
            }
            error = nil
            user = chosen
            invitation = hub.link.invite(chosen)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
