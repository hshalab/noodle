import AppKit
import HubCore
import HubLink
import ServiceManagement
import SwiftUI

/// Whether devices can reach the Hub, and the addresses invitations carry.
struct HubNetworkSettingsView: View {
    @Bindable var link: HubLinkService
    @State private var editingAddress = false
    @State private var address = ""
    @State private var opensAtLogin = SMAppService.mainApp.status

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    switch link.state {
                    case .listening(let port): Text("Listening on port \(String(port))")
                    case .starting: Text("Starting…")
                    case .stopped: Text("Stopped")
                    case .failed(let message): Text(message).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                TimelineView(.periodic(from: .now, by: 15)) { _ in
                    LabeledContent("Connected") {
                        let people = link.connectedUsers.count, devices = link.connectedDevices.count
                        Text(devices == 0 ? "No one"
                             : "\(people) \(people == 1 ? "person" : "people") on \(devices) \(devices == 1 ? "device" : "devices")")
                    }
                }
            }
            Section {
                Toggle("Open at Login", isOn: Binding(
                    get: { opensAtLogin == .enabled || opensAtLogin == .requiresApproval },
                    set: { setOpensAtLogin($0) }))
                    .help("Opens the Hub in the menu bar when you log in, so devices can reach it after the Mac restarts")
                if opensAtLogin == .requiresApproval {
                    LabeledContent("Needs approval in Login Items") {
                        Button("Open System Settings") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                Toggle("Open Port on Router", isOn: $link.opensRouterPort)
                    .help("Asks the router, through UPnP or NAT-PMP, to forward the Hub’s port so devices can reach it away from home")
                Picker("Largest File", selection: $link.uploadLimit) {
                    ForEach(link.uploadLimitChoices, id: \.self) { limit in
                        Text(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)).tag(limit)
                    }
                }
                .help("The largest file a device can send to a conversation on the Hub")
            }
            Section("Addresses") {
                ForEach(link.endpoints.filter { $0 != link.manualEndpoint }, id: \.self) { endpoint in
                    Text(endpoint.description).font(.body.monospaced()).textSelection(.enabled)
                }
                if let manual = link.manualEndpoint {
                    HStack {
                        Text(manual.description).font(.body.monospaced()).textSelection(.enabled)
                        Spacer()
                        Button("Remove") { link.manualAddress = "" }
                    }
                    .help("Reaches this Mac from outside your network")
                }
            }
        }
        .formStyle(.grouped)
        .accessFooter(link.manualEndpoint == nil ? "Add Address" : "Change Address") {
            address = link.manualAddress
            editingAddress = true
        }
        .alert("Remote Address", isPresented: $editingAddress) {
            TextField("Address", text: $address, prompt: Text("hub.example.com"))
            Button("Cancel", role: .cancel) {}
            Button("Save") { link.manualAddress = address.trimmingCharacters(in: .whitespaces) }
                .disabled(LinkEndpoint(text: address, defaultPort: LinkEndpoint.defaultPort) == nil)
        } message: {
            Text("A domain, public address or forwarded port that reaches this Mac from outside your network.")
        }
        // Login Items can be changed in System Settings while this is open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            opensAtLogin = SMAppService.mainApp.status
        }
    }

    private func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Noodle Hub could not change Open at Login: \(error.localizedDescription)")
        }
        opensAtLogin = SMAppService.mainApp.status
    }
}
