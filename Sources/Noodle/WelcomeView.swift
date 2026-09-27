import SwiftUI
import NoodleBrand
import NoodleWallpaper

/// The first launch, in the main window: the wordmark writes itself, and Continue lifts it
/// to make room for the first bot's setup.
struct WelcomeView: View {
    @Environment(NoodleStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var written = false
    @State private var ready = false
    @State private var settingUp = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let wordWidth = min(size.width * 0.34, 360)
            let wordHeight = wordWidth * Wordmark.bounds.height / Wordmark.bounds.width
            let liftedScale = 0.5
            let liftedCentre: CGFloat = 64
            ZStack {
                Wordmark(progress: written ? 1 : 0, wordWidth: wordWidth)
                    .stroke(.primary, style: StrokeStyle(
                        lineWidth: Wordmark.lineWidth(forWordWidth: wordWidth), lineCap: .round, lineJoin: .round))
                    .scaleEffect(settingUp ? liftedScale : 1)
                    .offset(y: settingUp ? liftedCentre - size.height / 2 : 0)
                    .accessibilityElement()
                    .accessibilityLabel("Noodle")
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    if settingUp {
                        Spacer().frame(height: liftedCentre + wordHeight * liftedScale / 2 + 32)
                        FirstBotSetupSheet(setup: store.harnessSetup, runtime: store.runtime, placement: .welcome)
                            .transition(.opacity.combined(with: .offset(y: 24)))
                        Spacer(minLength: 24)
                    } else {
                        Spacer()
                        Button("Continue") {
                            withAnimation(.spring(duration: 0.7, bounce: 0.1)) { settingUp = true }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .opacity(ready ? 1 : 0)
                        .offset(y: ready ? 0 : 12)
                        .disabled(!ready)
                        .padding(.bottom, size.height * 0.16)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background {
            ConversationWallpaper(background: store.background(for: nil))
                .overlay(alignment: .top) { ConversationWindowHeaderShade() }
                .ignoresSafeArea()
        }
        // The main window keeps its toolbar, and with it its shape, while the welcome fills it.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
                .sharedBackgroundVisibility(.hidden)
        }
        .onAppear(perform: write)
    }

    private func write() {
        guard !written else { return }
        if reduceMotion {
            written = true
            ready = true
        } else {
            // A short pause, the swirl and the word in one stroke, then Continue rises in.
            withAnimation(.easeInOut(duration: 3.4).delay(0.55)) { written = true }
            withAnimation(.easeOut(duration: 0.5).delay(4.05)) { ready = true }
        }
    }
}
