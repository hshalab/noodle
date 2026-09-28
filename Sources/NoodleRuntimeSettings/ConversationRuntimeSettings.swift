import SwiftUI
import NoodleCore
import NoodleRuntime

/// The Conversation settings that shape how bots run, shared by Noodle and the Hub.
public struct ConversationRuntimeSettingsSections: View {
    @AppStorage(MessageDeliveryMode.defaultsKey) private var messageDelivery = MessageDeliveryMode.automatic.rawValue
    @AppStorage(AgentSessionRollover.ageDefaultsKey) private var sessionAge = AgentSessionRollover.defaultAge
    @AppStorage(AgentSessionRollover.idleDefaultsKey) private var sessionIdle = AgentSessionRollover.defaultIdle

    public init() {}

    public var body: some View {
        Section {
            Picker("Message delivery", selection: $messageDelivery) {
                ForEach(MessageDeliveryMode.allCases) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
        } footer: {
            Text("Automatic uses Apple Intelligence to decide whether new messages should reach a busy agent immediately or wait until its turn finishes. When Apple Intelligence is unavailable, messages wait.")
        }
        Section {
            Picker("New session", selection: $sessionAge) {
                ForEach(options(AgentSessionRollover.ageOptions, current: sessionAge), id: \.self) { age in
                    Text(AgentSessionRollover.ageName(age)).tag(age)
                }
            }
            Picker("When idle for", selection: $sessionIdle) {
                ForEach(options(AgentSessionRollover.idleOptions, current: sessionIdle), id: \.self) { idle in
                    Text(AgentSessionRollover.idleName(idle)).tag(idle)
                }
            }
            .disabled(sessionAge <= 0)
        } footer: {
            Text("An idle bot starts a fresh session once its current one is this old. Its workspace, memory and messages are kept.")
        }
    }

    private func options(_ values: [TimeInterval], current: TimeInterval) -> [TimeInterval] {
        Array(Set(values + [current])).sorted()
    }
}

/// Confirms replacing a bot's session. Attach to the containing view, as with Kick.
public struct NewSessionConfirmation: ViewModifier {
    let store: any BotSettingsHost
    @Binding var agent: AgentRecord?

    public init(store: any BotSettingsHost, agent: Binding<AgentRecord?>) {
        self.store = store
        self._agent = agent
    }

    public func body(content: Content) -> some View {
        content.alert("Start a new session for \(agent?.displayName ?? "this bot")?", isPresented: Binding(
            get: { agent != nil }, set: { if !$0 { agent = nil } }
        ), presenting: agent) { agent in
            Button("New Session") {
                store.runtime.startNewSession(agent: agent, repository: store.repository)
            }
            Button("Cancel", role: .cancel) {}
        } message: { agent in
            Text("\(agent.displayName) will start with a fresh context. Its workspace, memory and messages are kept.")
        }
    }
}
